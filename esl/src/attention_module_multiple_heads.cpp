#include <algorithm>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
using Matrix = std::vector<std::vector<double>>;
using Vector = std::vector<double>;
using Matrix3D = std::vector<Matrix>;
Matrix readMatrix(const std::string &filename) {
	Matrix mat;
	std::ifstream file(filename);
	if (!file.is_open())
		return mat;
	std::string line;
	while (std::getline(file, line)) {
		Vector row;
		std::stringstream ss(line);
		double val;
		while (ss >> val) {
			row.push_back(val);
		}
		if (!row.empty()) {
			mat.push_back(row);
		}
	}
	return mat;
}
Vector readVector(const std::string &filename) {
	Vector vec;
	std::ifstream file(filename);
	if (!file.is_open())
		return vec;
	double val;
	while (file >> val) {
		vec.push_back(val);
	}
	return vec;
}
void writeMatrix(const std::string &filename, const Matrix &mat) {
	std::ofstream file(filename);
	for (const auto &row : mat) {
		for (size_t i = 0; i < row.size(); ++i) {
			file << row[i] << (i == row.size() - 1 ? "" : " ");
		}
		file << std::endl;
	}
}
void analyze_bits(const std::string &name, const Matrix &mat) {
	double min_abs_val = 1e9;
	double max_abs_val = -1e9;
	size_t rows = mat.size();
	size_t cols = mat[0].size();
	for (size_t i = 0; i < rows; i++) {
		for (size_t j = 0; j < cols; j++) {
			double val = mat[i][j];
			double abs_val = std::abs(val);
			if (abs_val > max_abs_val) {
				max_abs_val = abs_val;
			}
		}
	}
	int integer_bits = 0;
	if (max_abs_val > 0) {
		integer_bits = static_cast<int>(std::ceil(std::log2(max_abs_val)));
	} else {
		integer_bits = 1;
	}
	integer_bits += 1;
	int fract_bits = 0;
	for (size_t i = 0; i < rows; i++) {
		for (size_t j = 0; j < cols; j++) {
			double val = min_abs_val;
			double abs_val = std::abs(val);
			if (abs_val != 0 && abs_val < min_abs_val) {
				min_abs_val = abs_val;
			}
		}
	}
	if (min_abs_val > 0) {
		fract_bits = static_cast<int>(std::ceil(std::log(1.0 / min_abs_val)));
	} else {
		fract_bits = 0;
	}
	fract_bits += 1;
	std::cout << "Opseg : " << min_abs_val << " ... " << max_abs_val
	          << std::endl;
}
Matrix matmul_standard(const Matrix &A, const Matrix &B) {
	size_t A_rows = A.size();
	size_t B_rows = B.size();
	size_t A_cols = A[0].size();
	size_t B_cols = B[0].size();
	Matrix C(A_rows, Vector(B_cols, 0.0));
	for (size_t i = 0; i < A_rows; i++) {
		for (size_t j = 0; j < B_cols; j++) {
			double sum = 0.0;
			for (size_t k = 0; k < A_cols; k++) {
				sum += A[i][k] * B[k][j];
			}
			C[i][j] = sum;
		}
	}
	return C;
}
Matrix matmul_transpone(const Matrix &A, const Matrix &B) {
	size_t A_rows = A.size();
	size_t B_rows = B.size();
	size_t A_cols = A[0].size();
	size_t B_cols = B[0].size();
	Matrix C(A_rows, Vector(B_rows, 0.0));
	for (size_t i = 0; i < A_rows; i++) {
		for (size_t j = 0; j < B_rows; j++) {
			double sum = 0.0;
			for (size_t k = 0; k < A_rows; k++) {
				sum += A[i][k] * B[j][k];
			}
			C[i][j] = sum;
		}
	}
	return C;
}
Matrix softmax(const Matrix &mat) {
	size_t rows = mat.size();
	size_t cols = mat[0].size();
	Matrix results = mat;
	for (size_t i = 0; i < rows; i++) {
		double max_val = mat[i][0];
		for (size_t k = 1; k < cols; k++) {
			if (max_val < mat[i][k]) {
				max_val = mat[i][k];
			}
		}
		double sum = 0.0;
		for (size_t j = 0; j < cols; j++) {
			results[i][j] = std::exp(mat[i][j] - max_val);
			sum += results[i][j];
		}
		double sum_podeljena = 1 / sum;
		for (size_t j = 0; j < cols; j++) {
			results[i][j] = results[i][j] * sum_podeljena;
		}
	}
	return results;
}
Matrix multihead_attention(const Matrix &Q, const Matrix &K, const Matrix &V,
                           int num_heads) {
	size_t seq_len = Q.size();
	size_t embed_dim = Q[0].size();
	size_t head_dim = embed_dim / num_heads;
	Matrix3D q_heads(num_heads, Matrix(seq_len, Vector(embed_dim)));
	Matrix3D k_heads(num_heads, Matrix(seq_len, Vector(embed_dim)));
	Matrix3D v_heads(num_heads, Matrix(seq_len, Vector(embed_dim)));
	for (int h = 0; h < num_heads; h++) {
		for (size_t i = 0; i < seq_len; i++) {
			for (size_t j = 0; j < head_dim; j++) {
				q_heads[h][i][j] = Q[i][h * head_dim + j];
				k_heads[h][i][j] = K[i][h * head_dim + j];
				v_heads[h][i][j] = V[i][h * head_dim + j];
			}
		}
	}
	Matrix3D spojeno(num_heads, Matrix(seq_len, Vector(head_dim)));
	for (int h = 0; h < num_heads; h++) {
		Matrix scores = matmul_transpone(q_heads[h], k_heads[h]);
		Matrix probs = softmax(scores);
		spojeno[h] = matmul_standard(probs, v_heads[h]);
	}
	Matrix merged_output(seq_len, Vector(embed_dim));
	for (int h = 0; h < num_heads; h++) {
		for (size_t i = 0; i < embed_dim; i++) {
			for (size_t j = 0; j < head_dim; j++) {
				merged_output[i][h * head_dim + j] = spojeno[h][i][j];
			}
		}
	}
	return merged_output;
}
int main() {
	std::cout << "Pokrecemo nas cpp algoritam..." << std::endl;
	Matrix Q = readMatrix("izlaz/matrice/multihead_ulaz_Q.txt");
	Matrix K = readMatrix("izlaz/matrice/multihead_ulaz_K.txt");
	Matrix V = readMatrix("izlaz/matrice/multihead_ulaz_V.txt");
	Matrix W = readMatrix("izlaz/matrice/multihead_W_out.txt");
	Vector b = readVector("izlaz/matrice/multihead_b_out.txt");
	if (Q.empty())
		return 1;
	Matrix merged = multihead_attention(Q, K, V, 8);
	Matrix final_proj = matmul_standard(merged, W);
	size_t seq_len = final_proj.size();
	size_t embed_dim = final_proj[0].size();
	for (int i = 0; i < seq_len; i++) {
		for (int j = 0; j < embed_dim; j++) {
			final_proj[i][j] += b[j];
		}
	}
	std::cout << "Finalna projekcija uspesno izvrsena!" << std::endl;
	writeMatrix("izlaz/izlaz_cpp.txt", final_proj);
	std::cout << "Izlazni fajl kreiran." << std::endl;
	return 0;
}
