import sys
import numpy as np

def compare_files(file1, file2, tolerance=0.01):
    print(f"Poređenje fajlova: {file1} i {file2}")
    print(f"Korišćena tolerancija: {tolerance}")

    try:
        values1 = np.loadtxt(file1, dtype=np.float64)
        values2 = np.loadtxt(file2, dtype=np.float64)
    except (OSError, ValueError) as error:
        print(f"ERROR! Ne mogu da ucitam rezultate: {error}")
        return False

    if values1.shape != values2.shape:
        print(f"ERROR! Razliciti oblici rezultata: {values1.shape} i {values2.shape}")
        return False
    if not np.isfinite(values1).all() or not np.isfinite(values2).all():
        print("ERROR! Rezultat sadrzi NaN ili Inf.")
        return False

    difference = np.abs(values1 - values2)
    max_index = tuple(int(index) for index in np.unravel_index(np.argmax(difference), difference.shape))
    max_abs = float(difference[max_index])
    rms = float(np.sqrt(np.mean(difference ** 2)))
    print(f"max_abs={max_abs:.6e} na indeksu {max_index}; rms={rms:.6e}")

    if not np.allclose(values1, values2, atol=tolerance, rtol=0.0):
        print("ERROR! Razlika je veca od zadate apsolutne tolerancije.")
        return False

    print("SUCCESS! Rezultati su unutar zadate tolerancije.")
    return True

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Upotreba: python3 compare.py <fajl1> <fajl2>")
        sys.exit(1)

    success = compare_files(sys.argv[1], sys.argv[2])
    sys.exit(0 if success else 1)
