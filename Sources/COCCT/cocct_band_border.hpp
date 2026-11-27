// The normal equations of a least-squares fit of a B-spline direction, stored as a banded interior plus a dense border, so a
// periodic (cyclic) direction costs O(n d^2 + d^3) rather than O(n^3). Shared by Rebuild (`fit_1d`) and Match Surface on a closed
// edge. Not part of the public C API.
#ifndef COCCT_BAND_BORDER_HPP
#define COCCT_BAND_BORDER_HPP

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

namespace cocct {

/// A symmetric positive definite system over `interior` + `border` unknowns (interior first). The interior couples only within
/// `degree` of itself (Cholesky of a band); the border (for a cyclic direction the last `degree` poles, which every wrapped basis
/// window touches) couples with everything, solved as a Schur complement. With no border it is an ordinary banded solve.
class band_border_system {
public:
    band_border_system(int interior, int border, int degree)
        : m_(interior), b_(border), d_(degree), width_(static_cast<size_t>(degree) + 1),
          normal_(static_cast<size_t>(interior) * width_, 0.0), interior_border_(static_cast<size_t>(interior) * border, 0.0),
          border_border_(static_cast<size_t>(border) * border, 0.0) {}

    /// Adds `value` to entry (i, j). The caller adds each ordered pair, so both (i, j) and (j, i) arrive; only the lower triangle
    /// (and the interior-border block) is kept.
    void add(int i, int j, double value) {
        if (i < m_ && j < m_) {
            if (j <= i) {
                normal_[static_cast<size_t>(i) * width_ + (i - j)] += value;
            }
        } else if (i < m_) {
            interior_border_[static_cast<size_t>(i) * b_ + (j - m_)] += value;
        } else if (j >= m_) {
            border_border_[static_cast<size_t>(i - m_) * b_ + (j - m_)] += value;
        }
    }

    /// The largest diagonal of the interior and of the border, for a caller's own regularisation.
    double largest_diagonal() const {
        double largest = 0.0;
        for (int i = 0; i < m_; ++i) {
            largest = std::max(largest, normal_[static_cast<size_t>(i) * width_]);
        }
        for (int i = 0; i < b_; ++i) {
            largest = std::max(largest, border_border_[static_cast<size_t>(i) * b_ + i]);
        }
        return largest;
    }

    /// Factors, first as given and then with 1e-10 of each interior diagonal added. False when neither works.
    bool factor() { return (factor_band(0.0) && prepare_border()) || (factor_band(1e-10) && prepare_border()); }

    /// Solves in place for `stride` right-hand sides interleaved per unknown (interior then border).
    void solve(double *rhs, int stride) const {
        banded_solve(rhs, stride);
        if (b_ == 0) {
            return;
        }
        // y = A_II^-1 b_I; x_B = S^-1 (b_B - A_BI y); x_I = y - X x_B.
        std::vector<double> border(static_cast<size_t>(b_) * stride);
        for (int q = 0; q < b_; ++q) {
            for (int c = 0; c < stride; ++c) {
                double value = rhs[static_cast<size_t>(m_ + q) * stride + c];
                for (int i = 0; i < m_; ++i) {
                    value -= interior_border_[static_cast<size_t>(i) * b_ + q] * rhs[static_cast<size_t>(i) * stride + c];
                }
                border[static_cast<size_t>(q) * stride + c] = value;
            }
        }
        dense_solve(border.data(), stride);
        for (int i = 0; i < m_; ++i) {
            for (int c = 0; c < stride; ++c) {
                double value = rhs[static_cast<size_t>(i) * stride + c];
                for (int q = 0; q < b_; ++q) {
                    value -= schur_x_[static_cast<size_t>(i) * b_ + q] * border[static_cast<size_t>(q) * stride + c];
                }
                rhs[static_cast<size_t>(i) * stride + c] = value;
            }
        }
        for (int q = 0; q < b_; ++q) {
            for (int c = 0; c < stride; ++c) {
                rhs[static_cast<size_t>(m_ + q) * stride + c] = border[static_cast<size_t>(q) * stride + c];
            }
        }
    }

private:
    void banded_solve(double *rhs, int stride) const {
        for (int i = 0; i < m_; ++i) {
            for (int k = std::max(0, i - d_); k < i; ++k) {
                const double l = factor_[static_cast<size_t>(i) * width_ + (i - k)];
                for (int c = 0; c < stride; ++c) {
                    rhs[static_cast<size_t>(i) * stride + c] -= l * rhs[static_cast<size_t>(k) * stride + c];
                }
            }
            const double diagonal = factor_[static_cast<size_t>(i) * width_];
            for (int c = 0; c < stride; ++c) {
                rhs[static_cast<size_t>(i) * stride + c] /= diagonal;
            }
        }
        for (int i = m_ - 1; i >= 0; --i) {
            for (int k = i + 1; k < std::min(m_, i + d_ + 1); ++k) {
                const double l = factor_[static_cast<size_t>(k) * width_ + (k - i)];
                for (int c = 0; c < stride; ++c) {
                    rhs[static_cast<size_t>(i) * stride + c] -= l * rhs[static_cast<size_t>(k) * stride + c];
                }
            }
            const double diagonal = factor_[static_cast<size_t>(i) * width_];
            for (int c = 0; c < stride; ++c) {
                rhs[static_cast<size_t>(i) * stride + c] /= diagonal;
            }
        }
    }

    /// X = A_II^-1 A_IB and the Cholesky factor of S = A_BB - A_BI X. False when S is not positive definite.
    bool prepare_border() {
        if (b_ == 0) {
            return true;
        }
        schur_x_ = interior_border_;
        banded_solve(schur_x_.data(), b_);
        schur_.assign(static_cast<size_t>(b_) * b_, 0.0);
        for (int p = 0; p < b_; ++p) {
            for (int q = 0; q < b_; ++q) {
                double value = border_border_[static_cast<size_t>(p) * b_ + q];
                for (int i = 0; i < m_; ++i) {
                    value -= interior_border_[static_cast<size_t>(i) * b_ + p] * schur_x_[static_cast<size_t>(i) * b_ + q];
                }
                schur_[static_cast<size_t>(p) * b_ + q] = value;
            }
        }
        for (int i = 0; i < b_; ++i) {
            for (int j = 0; j <= i; ++j) {
                double sum = schur_[static_cast<size_t>(i) * b_ + j];
                for (int k = 0; k < j; ++k) {
                    sum -= schur_[static_cast<size_t>(i) * b_ + k] * schur_[static_cast<size_t>(j) * b_ + k];
                }
                if (i == j) {
                    if (!(sum > 0) || !std::isfinite(sum)) {
                        return false;
                    }
                    schur_[static_cast<size_t>(i) * b_ + i] = std::sqrt(sum);
                } else {
                    schur_[static_cast<size_t>(i) * b_ + j] = sum / schur_[static_cast<size_t>(j) * b_ + j];
                }
            }
        }
        return true;
    }

    void dense_solve(double *rhs, int stride) const {
        for (int i = 0; i < b_; ++i) {
            for (int k = 0; k < i; ++k) {
                for (int c = 0; c < stride; ++c) {
                    rhs[i * stride + c] -= schur_[static_cast<size_t>(i) * b_ + k] * rhs[k * stride + c];
                }
            }
            for (int c = 0; c < stride; ++c) {
                rhs[i * stride + c] /= schur_[static_cast<size_t>(i) * b_ + i];
            }
        }
        for (int i = b_ - 1; i >= 0; --i) {
            for (int k = i + 1; k < b_; ++k) {
                for (int c = 0; c < stride; ++c) {
                    rhs[i * stride + c] -= schur_[static_cast<size_t>(k) * b_ + i] * rhs[k * stride + c];
                }
            }
            for (int c = 0; c < stride; ++c) {
                rhs[i * stride + c] /= schur_[static_cast<size_t>(i) * b_ + i];
            }
        }
    }

    /// Banded Cholesky of the interior, `ridge` times each diagonal added first. False when a pivot isn't positive.
    bool factor_band(double ridge) {
        factor_ = normal_;
        for (int i = 0; i < m_; ++i) {
            const double original = normal_[static_cast<size_t>(i) * width_];
            for (int j = std::max(0, i - d_); j <= i; ++j) {
                double sum = factor_[static_cast<size_t>(i) * width_ + (i - j)];
                if (i == j) {
                    sum += ridge * original;
                }
                for (int k = std::max(j - d_, std::max(0, i - d_)); k < j; ++k) {
                    sum -= factor_[static_cast<size_t>(i) * width_ + (i - k)] * factor_[static_cast<size_t>(j) * width_ + (j - k)];
                }
                if (i == j) {
                    if (!(sum > 1e-14 * original) || !std::isfinite(sum)) {
                        return false;
                    }
                    factor_[static_cast<size_t>(i) * width_] = std::sqrt(sum);
                } else {
                    factor_[static_cast<size_t>(i) * width_ + (i - j)] = sum / factor_[static_cast<size_t>(j) * width_];
                }
            }
        }
        return true;
    }

    int m_;
    int b_;
    int d_;
    size_t width_;
    std::vector<double> normal_;
    std::vector<double> factor_;
    std::vector<double> interior_border_;
    std::vector<double> border_border_;
    std::vector<double> schur_x_;
    std::vector<double> schur_;
};

} // namespace cocct

#endif
