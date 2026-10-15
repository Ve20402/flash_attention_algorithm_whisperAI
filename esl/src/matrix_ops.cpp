#include "header/matrix_ops.h"

#include <algorithm>
#include <cmath>
#include <systemc>
#include <vector>

using Data = sc_dt::sc_fixed<24, 6, sc_dt::SC_TRN, sc_dt::SC_WRAP>;
using Score = sc_dt::sc_fixed<48, 12, sc_dt::SC_TRN, sc_dt::SC_WRAP>;
using Probability = sc_dt::sc_fixed<18, 2, sc_dt::SC_TRN, sc_dt::SC_WRAP>;
using Sum = sc_dt::sc_fixed<48, 32, sc_dt::SC_TRN, sc_dt::SC_WRAP>;
using Output = sc_dt::sc_fixed<48, 14, sc_dt::SC_TRN, sc_dt::SC_WRAP>;

template <typename Fixed>
Fixed from_raw(fixed_word_t raw) {
	Fixed format = 0;
	return Fixed(std::ldexp(static_cast<double>(raw), format.iwl() - format.wl()));
}

template <typename Fixed>
fixed_word_t to_raw(const Fixed &value) {
	return static_cast<fixed_word_t>(std::ldexp(value.to_double(), value.wl() - value.iwl()));
}
Probability fixed_exp(const Score &argument) {
	return Probability(std::exp(argument.to_double()));
}

void flash_attn_init(fixed_word_t *maximum, fixed_word_t *sum,
	                 fixed_word_t *output, int query_rows, int head_dim) {
	for (int row = 0; row < query_rows; ++row) {
		maximum[row] = -(fixed_word_t{1} << 46);
		sum[row] = 0;
		std::fill_n(output + row * head_dim, head_dim, 0);
	}
}

void flash_attn_step(const fixed_word_t *q, int query_rows,
	                 const fixed_word_t *k, const fixed_word_t *v, int kv_rows,
	                 fixed_word_t *maximum, fixed_word_t *sum,
	                 fixed_word_t *output, int head_dim) {
	std::vector<Data> q_fixed(static_cast<std::size_t>(query_rows) * head_dim);
	std::vector<Data> k_fixed(static_cast<std::size_t>(kv_rows) * head_dim);
	std::vector<Data> v_fixed(static_cast<std::size_t>(kv_rows) * head_dim);
	std::vector<Score> scores(static_cast<std::size_t>(query_rows) * kv_rows);

	for (std::size_t i = 0; i < q_fixed.size(); ++i)
		q_fixed[i] = from_raw<Data>(q[i]);
	for (std::size_t i = 0; i < k_fixed.size(); ++i) {
		k_fixed[i] = from_raw<Data>(k[i]);
		v_fixed[i] = from_raw<Data>(v[i]);
	}

	for (int row = 0; row < query_rows; ++row) {
		for (int column = 0; column < kv_rows; ++column) {
			Score score = 0;
			for (int dim = 0; dim < head_dim; ++dim)
				score += q_fixed[row * head_dim + dim] * k_fixed[column * head_dim + dim];
			scores[row * kv_rows + column] = score;
		}
	}

	for (int row = 0; row < query_rows; ++row) {
		std::vector<Output> output_fixed(head_dim);
		const Score old_maximum = from_raw<Score>(maximum[row]);
		Score new_maximum = old_maximum;
		for (int column = 0; column < kv_rows; ++column)
			new_maximum = std::max(new_maximum, scores[row * kv_rows + column]);

		const Probability scale = fixed_exp(old_maximum - new_maximum);
		Sum new_sum = from_raw<Sum>(sum[row]) * scale;
		for (int dim = 0; dim < head_dim; ++dim)
			output_fixed[dim] = from_raw<Output>(output[row * head_dim + dim]) * scale;

		for (int column = 0; column < kv_rows; ++column) {
			const Probability probability = fixed_exp(scores[row * kv_rows + column] - new_maximum);
			new_sum += probability;
			for (int dim = 0; dim < head_dim; ++dim)
				output_fixed[dim] += Output(probability * v_fixed[column * head_dim + dim]);
		}

		maximum[row] = to_raw(new_maximum);
		sum[row] = to_raw(new_sum);
		for (int dim = 0; dim < head_dim; ++dim)
			output[row * head_dim + dim] = to_raw(output_fixed[dim]);
	}
}

void flash_attn_finalize(fixed_word_t *output, const fixed_word_t *sum, int query_rows, int head_dim) {
	for (int row = 0; row < query_rows; ++row) {
		const Sum row_sum = from_raw<Sum>(sum[row]);
		const Probability inverse = Probability(1.0 / row_sum.to_double());
		for (int dim = 0; dim < head_dim; ++dim) {
			const Output value = from_raw<Output>(output[row * head_dim + dim]);
			output[row * head_dim + dim] = to_raw(Output(value * inverse));
		}
	}
}
