import torch
import sounddevice as sd
import numpy as np
from transformers import WhisperProcessor, WhisperForConditionalGeneration
from transformers.models.whisper.modeling_whisper import WhisperAttention
import queue
from pathlib import Path
import soundfile as sf

from vp_attention import FixedPointVPRunner

MODEL_NAME = "openai/whisper-base"
RECORD_SECONDS = 4
SAMPLE_RATE = 16000
BLOCK_SIZE = 1024

USE_FIXED_VP_ATTENTION = True
VP_ENCODER_LAYERS = 6
COMPARE_VP_TO_FLOAT = True
COMPARE_TRANSCRIPT = True
KEEP_VP_ARTIFACTS = False
SAVE_MATRICES = False
TEST_WAV_NAME = "data/normal.wav"

USE_MICROPHONE = False
PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / "data"
_configured_audio = Path(TEST_WAV_NAME)
TEST_WAV = (
    _configured_audio
    if _configured_audio.is_absolute()
    else PROJECT_ROOT / _configured_audio
)
OUT_DIR = DATA_DIR / "matrice"

q = queue.Queue()

def audio_callback(indata, frames, time, status):
    q.put(indata.copy())


def python_attention_reference(q_scaled, k, v, num_heads):
    _, _, cols = q_scaled.shape
    if cols % num_heads != 0:
        raise ValueError(f"embed_dim={cols} nije deljiv sa num_heads={num_heads}")

    head_dim = cols // num_heads
    output = torch.empty_like(q_scaled)
    for head in range(num_heads):
        start = head * head_dim
        stop = start + head_dim
        q_head = q_scaled[:, :, start:stop]
        k_head = k[:, :, start:stop]
        v_head = v[:, :, start:stop]
        scores = torch.matmul(q_head, k_head.transpose(-1, -2))
        probabilities = torch.softmax(scores, dim=-1)
        output[:, :, start:stop] = torch.matmul(probabilities, v_head)
    return output


def save_matrix(filename, value):
    path = OUT_DIR / filename
    np.savetxt(path, value, fmt="%.10e")
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError(f"Fajl nije uspesno sacuvan: {path}")


def report_difference(got, expected, label):
    got = np.asarray(got, dtype=np.float64)
    expected = np.asarray(expected, dtype=np.float64)
    if got.shape != expected.shape:
        raise RuntimeError(f"[{label}] razliciti oblici: {got.shape} i {expected.shape}")
    difference = np.abs(got - expected)
    print(
        f"[{label}] max_abs={difference.max():.3e}, "
        f"rms={np.sqrt(np.mean(difference ** 2)):.3e}"
    )

class AttentionWhisperBlock(WhisperAttention):
    def __init__(self, embed_dim, num_heads, dropout, layer_index, vp_runner,
                 is_decoder=False):
        super().__init__(embed_dim, num_heads, dropout, is_decoder)
        self.layer_index = layer_index
        self.vp_runner = vp_runner

    def forward(self, hidden_states, key_value_states=None, past_key_value=None,
                attention_mask=None, layer_head_mask=None, output_attentions=False):

        if key_value_states is not None or self.is_decoder:
            raise RuntimeError("Fixed-point VP blok podrzava encoder self-attention")

        Q = self.q_proj(hidden_states)
        K = self.k_proj(hidden_states)
        V = self.v_proj(hidden_states)

        scale_factor = 1.0 / np.sqrt(self.head_dim)
        q_scaled = Q * scale_factor
        q_list = q_scaled.detach().cpu().numpy()
        k_list = K.detach().cpu().numpy()
        v_list = V.detach().cpu().numpy()
        heads = int(self.num_heads)

        outputs = []
        for batch_index in range(q_list.shape[0]):
            attn_out_b = self.vp_runner.run(
                q_list[batch_index],
                k_list[batch_index],
                v_list[batch_index],
                heads,
                self.layer_index,
            )
            outputs.append(np.asarray(attn_out_b, dtype=np.float32))
        vp_pre_np = np.stack(outputs, axis=0)
        vp_pre = torch.from_numpy(vp_pre_np).to(
            hidden_states.device, dtype=hidden_states.dtype
        )
        attn_output = self.out_proj(vp_pre)

        reference_pre = None
        reference_post = None
        if COMPARE_VP_TO_FLOAT:
            reference_pre = python_attention_reference(q_scaled, K, V, heads)
            reference_post = self.out_proj(reference_pre)
            report_difference(
                vp_pre_np,
                reference_pre.detach().cpu().numpy(),
                f"VP layer {self.layer_index} pre-out_proj vs float",
            )
            report_difference(
                attn_output.detach().cpu().numpy(),
                reference_post.detach().cpu().numpy(),
                f"VP layer {self.layer_index} post-out_proj vs float",
            )

        if SAVE_MATRICES:
            OUT_DIR.mkdir(parents=True, exist_ok=True)
            prefix = f"layer_{self.layer_index}"
            save_matrix(f"{prefix}_Q.txt", q_list[0])
            save_matrix(f"{prefix}_K.txt", k_list[0])
            save_matrix(f"{prefix}_V.txt", v_list[0])
            save_matrix(f"{prefix}_vp_pre_out_proj.txt", vp_pre_np[0])
            if reference_pre is not None:
                save_matrix(
                    f"{prefix}_float_pre_out_proj.txt",
                    reference_pre.detach().cpu().numpy()[0],
                )

        return attn_output, None, None

#offline test(koristi .wav fajl)
def offline_test(processor, model, device, label):
    print(f"[{label}] Ucitavanje {TEST_WAV} fajla...")
    audio, sr = sf.read(TEST_WAV)
    if sr != 16000:
        import resampy
        audio = resampy.resample(audio, sr, 16000)
        sr = 16000
    inputs = processor(audio, sampling_rate=sr, return_tensors="pt")
    with torch.inference_mode():
        predicted_ids = model.generate(inputs.input_features.to(device))
    text = processor.batch_decode(predicted_ids, skip_special_tokens=True)
    transcription = text[0].strip() if text else ""
    print(f"[{label}] Transkripcija:", transcription or "<nista>")
    print("---------------------------")
    return transcription


#glavni deo programa
def main():
    print(f"Učitavanje modela '{MODEL_NAME}'...")
    device = "cpu"
    processor = WhisperProcessor.from_pretrained(MODEL_NAME)
    model = WhisperForConditionalGeneration.from_pretrained(MODEL_NAME).to(device)

    baseline_transcription = None
    if (not USE_MICROPHONE and USE_FIXED_VP_ATTENTION and COMPARE_TRANSCRIPT):
        baseline_transcription = offline_test(
            processor, model, device, "FLOAT BASELINE"
        )

    if USE_FIXED_VP_ATTENTION:
        encoder_layers = model.model.encoder.layers
        layer_count = min(max(VP_ENCODER_LAYERS, 0), len(encoder_layers))
        if layer_count != VP_ENCODER_LAYERS:
            print(
                f"VP_ENCODER_LAYERS={VP_ENCODER_LAYERS} je ogranicen na {layer_count}."
            )
        vp_runner = FixedPointVPRunner(keep_artifacts=KEEP_VP_ARTIFACTS)
        print(
            f"Koristimo fixed-point SystemC VP za prvih {layer_count} "
            "encoder self-attention slojeva."
        )
        for layer_index in range(layer_count):
            original_layer = encoder_layers[layer_index].self_attn
            fixed_layer = AttentionWhisperBlock(
                embed_dim=original_layer.embed_dim,
                num_heads=original_layer.num_heads,
                dropout=original_layer.dropout,
                layer_index=layer_index,
                vp_runner=vp_runner,
            )
            fixed_layer.load_state_dict(original_layer.state_dict())
            encoder_layers[layer_index].self_attn = fixed_layer
        print("VP encoder zamena je uspesna.\n")
    else:
        print("Koristimo originalni HuggingFace attention.\n")

    if not USE_MICROPHONE:
        vp_transcription = offline_test(processor, model, device, "FIXED VP")
        if baseline_transcription is not None:
            if vp_transcription == baseline_transcription:
                print("fixed VP i float baseline su identicni.")
            else:
                print("diff ")
                print("  float:", baseline_transcription or "<nista>")
                print("  VP:   ", vp_transcription or "<nista>")
        return

    #ako koristimo mikrofon
    while True:
        try:
            num_blocks_to_record = int(RECORD_SECONDS * SAMPLE_RATE / BLOCK_SIZE)
            audio_data = []

            print("-------------------------------------------")
            input(f"Pritisnite Enter da započnete snimanje od {RECORD_SECONDS} sekundi...")

            print("Snimam...")
            with sd.InputStream(samplerate=SAMPLE_RATE, channels=1, dtype='float32',
                                blocksize=BLOCK_SIZE, callback=audio_callback):
                for _ in range(num_blocks_to_record):
                    audio_data.append(q.get())
            print("Snimanje završeno, obrađujem snimak...")

            if audio_data:
                full_audio = np.concatenate(audio_data, axis=0).flatten()
                input_features = processor(full_audio, sampling_rate=SAMPLE_RATE, return_tensors="pt").input_features.to(device)
                with torch.inference_mode():
                    predicted_ids = model.generate(input_features)
                forced_ids = processor.get_decoder_prompt_ids(language="en", task="transcribe")
                transcription = processor.batch_decode(predicted_ids, skip_special_tokens=True)

                print("\nFINALNA TRANSKRIPCIJA")
                print(transcription[0].strip() if transcription and transcription[0].strip() else "Nema prepoznatog govora")
                print("---------------------------\n")

        except KeyboardInterrupt:
            print("\nProgram prekinut.")
            break
        except Exception as e:
            print(f"Došlo je do greške: {e}")
            break

if __name__ == "__main__":
    main()
