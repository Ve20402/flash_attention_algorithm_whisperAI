import torch
import sounddevice as sd
import numpy as np
from transformers import WhisperProcessor, WhisperForConditionalGeneration
from transformers.models.whisper.modeling_whisper import WhisperAttention
import queue
import json
from pathlib import Path
import soundfile as sf

try:
    import multihead_attention_algorithm
    print("Cpp fajl je uspesno uvezen!")
except ImportError:
    print("Greska! Nije moguce uvesti cpp fajl.")
    multihead_attention_algorithm = None

# --- Podesavanja --
MODEL_NAME = "openai/whisper-base"
RECORD_SECONDS = 4
SAMPLE_RATE = 16000
BLOCK_SIZE = 1024

# Flagovi za test
USE_CPP_ATTENTION = True     # True koristi C++ funkciju
USE_MICROPHONE = False        # True - hvata sa mikrofona False - uzima .wav fajl umesto mikrofona
PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / "data"
TEST_WAV = DATA_DIR / "normal.wav"
OUT_DIR = DATA_DIR / "matrice"

REFERENCE_ATOL = 1e-4
REFERENCE_RTOL = 1e-4

q = queue.Queue()

def audio_callback(indata, frames, time, status):
    q.put(indata.copy())


def python_attention_reference(q_scaled, k, v, num_heads):
    """Float PyTorch golden za MHA izlaz pre zavrsne out_proj projekcije."""
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


def compare_arrays(got, expected, label):
    got = np.asarray(got, dtype=np.float64)
    expected = np.asarray(expected, dtype=np.float64)
    if got.shape != expected.shape:
        raise RuntimeError(f"[{label}] razliciti oblici: {got.shape} i {expected.shape}")
    if not np.isfinite(got).all() or not np.isfinite(expected).all():
        raise RuntimeError(f"[{label}] rezultat sadrzi NaN ili Inf")

    difference = np.abs(got - expected)
    max_abs = float(difference.max())
    rms = float(np.sqrt(np.mean(difference ** 2)))
    print(f"[{label}] max_abs={max_abs:.3e}, rms={rms:.3e}")
    if not np.allclose(got, expected, atol=REFERENCE_ATOL, rtol=REFERENCE_RTOL):
        raise RuntimeError(
            f"[{label}] rezultat nije unutar atol={REFERENCE_ATOL}, rtol={REFERENCE_RTOL}"
        )

#Moj custom attention block
class AttentionWhisperBlock(WhisperAttention):
    def __init__(self, embed_dim, num_heads, dropout, is_decoder=False):
        super().__init__(embed_dim, num_heads, dropout, is_decoder)

    def forward(self, hidden_states, key_value_states=None, past_key_value=None,
                attention_mask=None, layer_head_mask=None, output_attentions=False):

        if multihead_attention_algorithm is None:
            raise RuntimeError("multihead_attention_algorithm nije ucitan!")

        #Q, K, V iz PyTorcha
        Q = self.q_proj(hidden_states)
        K = self.k_proj(hidden_states)
        V = self.v_proj(hidden_states)

        scale_factor = 1.0 / np.sqrt(self.head_dim)
        print("Skaliranje...")

        # Q je skaliran ovde, pa ni ESL ni buduci RTL ne treba ponovo da ga skaliraju.
        q_scaled = Q * scale_factor
        q_list = q_scaled.detach().cpu().numpy()
        k_list = K.detach().cpu().numpy()
        v_list = V.detach().cpu().numpy()
        print("Skaliranje zavrseno...")
        print(f"[PYTHON-INPUT] Q[0,0,0] after scale: {q_list[0,0,0]}")
        print(f"[PYTHON-INPUT] K[0,0,0]: {k_list[0,0,0]}")
        print(f"[PYTHON-INPUT] V[0,0,0]: {v_list[0,0,0]}")

        OUT_DIR.mkdir(parents=True, exist_ok=True)

        print("Saving Q, K and V...")
        save_matrix("multihead_ulaz_Q.txt", q_list[0])
        save_matrix("multihead_ulaz_K.txt", k_list[0])
        save_matrix("multihead_ulaz_V.txt", v_list[0])
        save_matrix("multihead_W_out.txt", self.out_proj.weight.detach().cpu().numpy().T)
        save_matrix("multihead_b_out.txt", self.out_proj.bias.detach().cpu().numpy())

        rows, cols = q_list[0].shape
        heads = int(self.num_heads)

        print("Racunam Python float golden pre finalne projekcije...")
        reference_pre = python_attention_reference(q_scaled, K, V, heads)
        reference_pre_np = reference_pre.detach().cpu().numpy()
        save_matrix("multihead_output_pre_wout.txt", reference_pre_np[0])

        reference_post = self.out_proj(reference_pre)
        reference_post_np = reference_post.detach().cpu().numpy()
        save_matrix("output_main_app.txt", reference_post_np[0])

        metadata = {
            "rows": rows,
            "cols": cols,
            "heads": heads,
            "head_dim": cols // heads,
            "q_is_scaled_by_inverse_sqrt_head_dim": True,
            "pre_projection_file": "multihead_output_pre_wout.txt",
            "post_projection_file": "output_main_app.txt",
        }
        with (OUT_DIR / "matrix_metadata.json").open("w", encoding="utf-8") as metadata_file:
            json.dump(metadata, metadata_file, indent=2)

        outputs = []
        for batch_index in range(q_list.shape[0]):
            attn_out_b = multihead_attention_algorithm.attention_core(
                q_list[batch_index].tolist(),
                k_list[batch_index].tolist(),
                v_list[batch_index].tolist(),
                heads,
            )
            outputs.append(np.asarray(attn_out_b, dtype=np.float32))
        cpp_pre_np = np.stack(outputs, axis=0)
        compare_arrays(cpp_pre_np, reference_pre_np, "CPP pre-projection vs Python")

        cpp_pre = torch.from_numpy(cpp_pre_np).to(
            hidden_states.device, dtype=hidden_states.dtype
        )
        attn_output = self.out_proj(cpp_pre)
        compare_arrays(
            attn_output.detach().cpu().numpy(),
            reference_post_np,
            "CPP post-projection vs Python",
        )

        print(f"Kompletne ESL matrice i golden rezultati sacuvani su u: {OUT_DIR}")

        #grananje
        if self.is_decoder:
            if key_value_states is not None:
                return attn_output, None
            else:
                return attn_output, None, None
        else:
            return attn_output, None, None

#offline test(koristi .wav fajl)
def offline_test(processor, model, device):
    print(f"Ucitavanje {TEST_WAV} fajla...")
    audio, sr = sf.read(TEST_WAV)
    if sr != 16000:
        import resampy
        audio = resampy.resample(audio, sr, 16000)
        sr = 16000
    inputs = processor(audio, sampling_rate=sr, return_tensors="pt")
    with torch.inference_mode():
        predicted_ids = model.generate(inputs.input_features.to(device))
    text = processor.batch_decode(predicted_ids, skip_special_tokens=True)
    print("Transkripcija:", text[0] if text else "<nista>")
    print("---------------------------")


#glavni deo programa
def main():
    print(f"Učitavanje modela '{MODEL_NAME}'...")
    device = "cpu"
    processor = WhisperProcessor.from_pretrained(MODEL_NAME)
    model = WhisperForConditionalGeneration.from_pretrained(MODEL_NAME).to(device)

    if USE_CPP_ATTENTION:
        print("Koristimo custom C++ funkciju")
        original_layer = model.model.encoder.layers[0].self_attn
        novi_sloj = AttentionWhisperBlock(
            embed_dim=original_layer.embed_dim,
            num_heads=original_layer.num_heads,
            dropout=original_layer.dropout
        )
        novi_sloj.load_state_dict(original_layer.state_dict())
        model.model.encoder.layers[0].self_attn = novi_sloj
        print("Zamena uspesna.\n")
    else:
        print("Koristimo originalni HuggingFace attention.\n")

    if not USE_MICROPHONE:
        offline_test(processor, model, device)
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

                print("\n****FINALNA TRANSKRIPCIJA****")
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
