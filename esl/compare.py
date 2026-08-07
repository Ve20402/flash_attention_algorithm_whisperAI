import sys
import numpy as np

def compare_files(file1, file2, tolerance=0.01):
    print(f"Poređenje fajlova: {file1} i {file2}")
    print(f"Korišćena tolerancija: {tolerance}")

    with open(file1, 'r') as f1, open(file2, 'r') as f2:
        lines1 = f1.readlines()
        lines2 = f2.readlines()

    if len(lines1) != len(lines2):
        print(f"Error! Files have a different number of rows! ({len(lines1)} vs {len(lines2)})")
        return False

    for i, (line1, line2) in enumerate(zip(lines1, lines2)):
        vals1 = [float(v) for v in line1.strip().split()]
        vals2 = [float(v) for v in line2.strip().split()]

        if len(vals1) != len(vals2):
            print(f"Error! The Row {i+1} has a different number of values.")
            return False

        if not np.allclose(vals1, vals2, atol=tolerance):
            print(f"Error! Found a difference in  {i+1} that is greater than the specified tolerance.")
            return False

    print("SUCCESS! The Files are numerically indentical within the given tolerance.")
    return True

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Upotreba: python3 compare.py <fajl1> <fajl2>")
        sys.exit(1)

    compare_files(sys.argv[1], sys.argv[2])