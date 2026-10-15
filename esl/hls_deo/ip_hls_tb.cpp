#include "ip_hls.h"
#include <cstdio>
#include <cmath>
#include <fstream>
#include <string>
#include <vector>

static const std::string MAT_DIR = "D:/kod_za_vitis/matrice";	//hardkodovano

static bool read_matrix(const std::string& filename, std::vector<float>& buf, int needed)
{
    std::ifstream file(MAT_DIR + "/" + filename);
    if (!file.is_open()) {
        printf("Error. Can't open %s/%s\n", MAT_DIR.c_str(), filename.c_str());
        return false;
    }
    float v;
    while (file >> v)
        buf.push_back(v);
    if ((int)buf.size() < needed) {
        printf("Error. %s has %d values, needs at least %d\n",
               filename.c_str(), (int)buf.size(), needed);
        return false;
    }
    return true;
}

int main()
{
    std::vector<float> Q, K, V, W, b;
    if (!read_matrix("multihead_ulaz_Q.txt", Q, ROWS * COLS)) return 1;
    if (!read_matrix("multihead_ulaz_K.txt", K, ROWS * COLS)) return 1;
    if (!read_matrix("multihead_ulaz_V.txt", V, ROWS * COLS)) return 1;
    if (!read_matrix("multihead_W_out.txt",  W, COLS * COLS)) return 1;
    if (!read_matrix("multihead_b_out.txt",  b, COLS))        return 1;

    printf("Matrice ucitane, koristi se prvih %d redova.\n", ROWS);

    hls::stream<float> stream_in, stream_out;

    for (int c = 0; c < COLS; c++)
        stream_in.write(b[c]);

    for (int qi = 0; qi < ROWS; qi += B) {
        int br = ROWS - qi;
        if (br > B) br = B;

        for (int h = 0; h < NUM_HEADS; h++) {
            for (int r = 0; r < br; r++)
                for (int d = 0; d < HEAD_DIM; d++)
                    stream_in.write(Q[(qi + r) * COLS + h * HEAD_DIM + d]);

            for (int j = 0; j < ROWS; j += BC) {
                int bc = ROWS - j;
                if (bc > BC) bc = BC;

                for (int r = 0; r < bc; r++)
                    for (int d = 0; d < HEAD_DIM; d++)
                        stream_in.write(K[(j + r) * COLS + h * HEAD_DIM + d]);
                for (int r = 0; r < bc; r++)
                    for (int d = 0; d < HEAD_DIM; d++)
                        stream_in.write(V[(j + r) * COLS + h * HEAD_DIM + d]);
            }

            for (int k = 0; k < HEAD_DIM; k++)
                for (int c = 0; c < COLS; c++)
                    stream_in.write(W[(h * HEAD_DIM + k) * COLS + c]);
        }
    }

    mha_ip(stream_in, stream_out);

    std::vector<double> Y_ref(ROWS * COLS);
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            Y_ref[r * COLS + c] = b[c];

    std::vector<double> s(ROWS), p(ROWS);
    for (int h = 0; h < NUM_HEADS; h++)
        for (int r = 0; r < ROWS; r++) {
            double m = -1e300;
            for (int c = 0; c < ROWS; c++) {
                double dot = 0.0;
                for (int d = 0; d < HEAD_DIM; d++)
                    dot += (double)Q[r * COLS + h * HEAD_DIM + d]
                         * (double)K[c * COLS + h * HEAD_DIM + d];
                s[c] = dot;
                if (dot > m) m = dot;
            }

            double l = 0.0;
            for (int c = 0; c < ROWS; c++) {
                p[c] = std::exp(s[c] - m);
                l += p[c];
            }

            for (int d = 0; d < HEAD_DIM; d++) {
                double o = 0.0;
                for (int c = 0; c < ROWS; c++)
                    o += p[c] * (double)V[c * COLS + h * HEAD_DIM + d];
                o /= l;
                for (int j = 0; j < COLS; j++)
                    Y_ref[r * COLS + j] += o * (double)W[(h * HEAD_DIM + d) * COLS + j];
            }
        }

    double max_diff = 0.0;
    for (int i = 0; i < ROWS * COLS; i++) {
        float y = stream_out.read();
        double diff = std::fabs((double)y - Y_ref[i]);
        if (diff > max_diff) max_diff = diff;
    }

    printf("max apsolutna greska: %g\n", max_diff);
    if (max_diff < 0.01) {
        printf("Test has passed.\n");
        return 0;
    }
    printf("Test has failed.\n");
    return 1;
}
