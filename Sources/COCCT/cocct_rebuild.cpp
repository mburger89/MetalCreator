// Rebuilding a sheet's one face or a curve to a chosen degree and span count (NS-3, Task 4). Our own separable least-squares fit.
#include "cocct_control_net.hpp"
#include "cocct_sheet.hpp"

#include <BRepAdaptor_CompCurve.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRep_Tool.hxx>
#include <Geom_Curve.hxx>
#include <Geom_TrimmedCurve.hxx>
#include <TopExp_Explorer.hxx>
#include <BRepTools.hxx>
#include <Geom_BSplineCurve.hxx>
#include <Geom_BSplineSurface.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColgp_Array1OfPnt.hxx>
#include <TColgp_Array2OfPnt.hxx>
#include <TopoDS.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <string>
#include <cmath>
#include <cstdlib>
#include <new>
#include <vector>

using namespace cocct;

namespace {

constexpr int kMaxDegree = 11;
constexpr double kMaxPoles = 100000;

template <typename T>
T *zeroed(size_t count) {
    T *memory = static_cast<T *>(std::calloc(count > 0 ? count : 1, sizeof(T)));
    if (!memory) {
        throw std::bad_alloc();
    }
    return memory;
}

/// The flat knot vector of a clamped B-spline of degree `d` with `s` equal spans over [a, b].
std::vector<double> flat_knots(double a, double b, int d, int s) {
    std::vector<double> flat;
    flat.reserve(2 * d + s + 1);
    for (int k = 0; k <= d; ++k) {
        flat.push_back(a);
    }
    for (int k = 1; k < s; ++k) {
        flat.push_back(a + (b - a) * k / s);
    }
    for (int k = 0; k <= d; ++k) {
        flat.push_back(b);
    }
    return flat;
}

enum fit_mode { kClamped, kPinned, kPeriodic };

/// Least squares of one direction: the samples' basis values and the banded Cholesky factor of the normal equations, made once and
/// used for every row or column of data. `kPinned` gives the first and last poles instead of fitting them. `kPeriodic` fits
/// uniform periodic knots over [a, b] with `spans` poles; the normal equations are cyclic, solved as a banded interior (all but
/// the last `degree` poles) plus a dense border of those `degree` poles (a Schur complement).
class fit_1d {
public:
    fit_1d(const std::vector<double> &params, double a, double b, int degree, int spans, fit_mode mode)
        : d_(degree), mode_(mode), n_(mode == kPeriodic ? spans : degree + spans), m_(static_cast<int>(params.size())),
          pinned_(mode == kPinned), lo_(mode == kPinned ? 1 : 0),
          hi_(mode == kPinned ? n_ - 2 : (mode == kPeriodic ? n_ - degree - 1 : n_ - 1)) {
        const bool periodic = mode == kPeriodic;
        const double h = (b - a) / spans;
        if (periodic) {
            for (int k = 0; k <= spans + 2 * d_; ++k) {
                flat_.push_back(a + h * (k - d_));
            }
        } else {
            flat_ = flat_knots(a, b, degree, spans);
        }
        unknowns_ = std::max(0, hi_ - lo_ + 1);
        border_ = periodic ? d_ : 0;
        span_.resize(m_);
        values_.assign(static_cast<size_t>(m_) * (d_ + 1), 0.0);
        std::vector<double> left(d_ + 1), right(d_ + 1);
        for (int t = 0; t < m_; ++t) {
            const double u = params[t];
            int k = d_;
            if (periodic) {
                k = d_ + std::min(spans - 1, std::max(0, static_cast<int>(std::floor((u - a) / h))));
            } else {
                int lower = d_;
                int upper = n_;
                // The largest span index in [d, n - 1] with flat[k] <= u.
                while (upper - lower > 1) {
                    const int mid = (lower + upper) / 2;
                    if (flat_[mid] <= u) {
                        lower = mid;
                    } else {
                        upper = mid;
                    }
                }
                k = lower;
            }
            span_[t] = k;
            double *basis = &values_[static_cast<size_t>(t) * (d_ + 1)];
            basis[0] = 1.0;
            for (int j = 1; j <= d_; ++j) {
                left[j] = u - flat_[k + 1 - j];
                right[j] = flat_[k + j] - u;
                double saved = 0.0;
                for (int r = 0; r < j; ++r) {
                    const double denominator = right[r + 1] + left[j - r];
                    const double temp = denominator != 0.0 ? basis[r] / denominator : 0.0;
                    basis[r] = saved + right[r + 1] * temp;
                    saved = left[j - r] * temp;
                }
                basis[j] = saved;
            }
        }
        normal_.assign(static_cast<size_t>(unknowns_) * (d_ + 1), 0.0);
        interior_border_.assign(static_cast<size_t>(unknowns_) * border_, 0.0);
        border_border_.assign(static_cast<size_t>(border_) * border_, 0.0);
        for (int t = 0; t < m_; ++t) {
            const double *basis = &values_[static_cast<size_t>(t) * (d_ + 1)];
            for (int p = 0; p <= d_; ++p) {
                const int i = index_of(t, p) - lo_;
                for (int q = 0; q <= d_; ++q) {
                    const int j = index_of(t, q) - lo_;
                    const double product = basis[p] * basis[q];
                    if (i < 0 || j < 0 || i >= unknowns_ + border_ || j >= unknowns_ + border_) {
                        continue;
                    }
                    if (i < unknowns_ && j < unknowns_) {
                        if (j <= i) {
                            normal_[static_cast<size_t>(i) * (d_ + 1) + (i - j)] += product;
                        }
                    } else if (i < unknowns_) {
                        interior_border_[static_cast<size_t>(i) * border_ + (j - unknowns_)] += product;
                    } else if (j >= unknowns_) {
                        border_border_[static_cast<size_t>(i - unknowns_) * border_ + (j - unknowns_)] += product;
                    }
                }
            }
        }
        if (!factor(0.0) && !factor(1e-10)) {
            throw user_error("The fit couldn't be solved for these settings.");
        }
        if (periodic) {
            prepare_border();
        }
    }

    int poles() const { return n_; }

    /// Fits `data` (m points, interleaved xyz) into `out` (n points); with `kPinned` out's first and last points are set to the
    /// data's first and last.
    void solve(const double *data, double *out) const {
        if (pinned_) {
            for (int c = 0; c < 3; ++c) {
                out[c] = data[c];
                out[3 * (n_ - 1) + c] = data[3 * (m_ - 1) + c];
            }
        }
        if (unknowns_ == 0 && border_ == 0) {
            return;
        }
        std::vector<double> rhs(static_cast<size_t>(unknowns_ + border_) * 3, 0.0);
        for (int t = 0; t < m_; ++t) {
            const double *basis = &values_[static_cast<size_t>(t) * (d_ + 1)];
            double residual[3] = {data[3 * t], data[3 * t + 1], data[3 * t + 2]};
            if (pinned_) {
                for (int p = 0; p <= d_; ++p) {
                    const int index = index_of(t, p);
                    if (index == 0 || index == n_ - 1) {
                        for (int c = 0; c < 3; ++c) {
                            residual[c] -= basis[p] * out[3 * index + c];
                        }
                    }
                }
            }
            for (int p = 0; p <= d_; ++p) {
                const int i = index_of(t, p) - lo_;
                if (i < 0 || i >= unknowns_ + border_) {
                    continue;
                }
                for (int c = 0; c < 3; ++c) {
                    rhs[static_cast<size_t>(i) * 3 + c] += basis[p] * residual[c];
                }
            }
        }
        if (border_ == 0) {
            banded_solve(rhs.data(), 3);
            for (int i = 0; i < unknowns_; ++i) {
                for (int c = 0; c < 3; ++c) {
                    out[3 * (lo_ + i) + c] = rhs[static_cast<size_t>(i) * 3 + c];
                }
            }
            return;
        }
        // Periodic: y = A_II^-1 b_I; x_B = S^-1 (b_B - A_BI y); x_I = y - X x_B.
        banded_solve(rhs.data(), 3);
        std::vector<double> border(static_cast<size_t>(border_) * 3);
        for (int q = 0; q < border_; ++q) {
            for (int c = 0; c < 3; ++c) {
                double value = rhs[static_cast<size_t>(unknowns_ + q) * 3 + c];
                for (int i = 0; i < unknowns_; ++i) {
                    value -= interior_border_[static_cast<size_t>(i) * border_ + q] * rhs[static_cast<size_t>(i) * 3 + c];
                }
                border[static_cast<size_t>(q) * 3 + c] = value;
            }
        }
        dense_solve(border.data());
        for (int i = 0; i < unknowns_; ++i) {
            for (int c = 0; c < 3; ++c) {
                double value = rhs[static_cast<size_t>(i) * 3 + c];
                for (int q = 0; q < border_; ++q) {
                    value -= schur_x_[static_cast<size_t>(i) * border_ + q] * border[static_cast<size_t>(q) * 3 + c];
                }
                out[3 * i + c] = value;
            }
        }
        for (int q = 0; q < border_; ++q) {
            for (int c = 0; c < 3; ++c) {
                out[3 * (unknowns_ + q) + c] = border[static_cast<size_t>(q) * 3 + c];
            }
        }
    }

private:
    /// The pole sample `t`'s `p`th basis function belongs to.
    int index_of(int t, int p) const {
        const int index = span_[t] - d_ + p;
        return mode_ == kPeriodic ? index % n_ : index;
    }

    /// Solves L L^T x = rhs in place for `stride` right-hand sides interleaved per unknown.
    void banded_solve(double *rhs, int stride) const {
        for (int i = 0; i < unknowns_; ++i) {
            for (int k = std::max(0, i - d_); k < i; ++k) {
                const double l = factor_[static_cast<size_t>(i) * (d_ + 1) + (i - k)];
                for (int c = 0; c < stride; ++c) {
                    rhs[static_cast<size_t>(i) * stride + c] -= l * rhs[static_cast<size_t>(k) * stride + c];
                }
            }
            const double diagonal = factor_[static_cast<size_t>(i) * (d_ + 1)];
            for (int c = 0; c < stride; ++c) {
                rhs[static_cast<size_t>(i) * stride + c] /= diagonal;
            }
        }
        for (int i = unknowns_ - 1; i >= 0; --i) {
            for (int k = i + 1; k < std::min(unknowns_, i + d_ + 1); ++k) {
                const double l = factor_[static_cast<size_t>(k) * (d_ + 1) + (k - i)];
                for (int c = 0; c < stride; ++c) {
                    rhs[static_cast<size_t>(i) * stride + c] -= l * rhs[static_cast<size_t>(k) * stride + c];
                }
            }
            const double diagonal = factor_[static_cast<size_t>(i) * (d_ + 1)];
            for (int c = 0; c < stride; ++c) {
                rhs[static_cast<size_t>(i) * stride + c] /= diagonal;
            }
        }
    }

    /// X = A_II^-1 A_IB and the Cholesky factor of S = A_BB - A_BI X.
    void prepare_border() {
        schur_x_ = interior_border_;
        banded_solve(schur_x_.data(), border_);
        schur_.assign(static_cast<size_t>(border_) * border_, 0.0);
        for (int p = 0; p < border_; ++p) {
            for (int q = 0; q < border_; ++q) {
                double value = border_border_[static_cast<size_t>(p) * border_ + q];
                for (int i = 0; i < unknowns_; ++i) {
                    value -= interior_border_[static_cast<size_t>(i) * border_ + p] * schur_x_[static_cast<size_t>(i) * border_ + q];
                }
                schur_[static_cast<size_t>(p) * border_ + q] = value;
            }
        }
        for (int i = 0; i < border_; ++i) {
            for (int j = 0; j <= i; ++j) {
                double sum = schur_[static_cast<size_t>(i) * border_ + j];
                for (int k = 0; k < j; ++k) {
                    sum -= schur_[static_cast<size_t>(i) * border_ + k] * schur_[static_cast<size_t>(j) * border_ + k];
                }
                if (i == j) {
                    if (!(sum > 0) || !std::isfinite(sum)) {
                        throw user_error("The fit couldn't be solved for these settings.");
                    }
                    schur_[static_cast<size_t>(i) * border_ + i] = std::sqrt(sum);
                } else {
                    schur_[static_cast<size_t>(i) * border_ + j] = sum / schur_[static_cast<size_t>(j) * border_ + j];
                }
            }
        }
    }

    void dense_solve(double *rhs) const {
        for (int i = 0; i < border_; ++i) {
            for (int k = 0; k < i; ++k) {
                for (int c = 0; c < 3; ++c) {
                    rhs[i * 3 + c] -= schur_[static_cast<size_t>(i) * border_ + k] * rhs[k * 3 + c];
                }
            }
            for (int c = 0; c < 3; ++c) {
                rhs[i * 3 + c] /= schur_[static_cast<size_t>(i) * border_ + i];
            }
        }
        for (int i = border_ - 1; i >= 0; --i) {
            for (int k = i + 1; k < border_; ++k) {
                for (int c = 0; c < 3; ++c) {
                    rhs[i * 3 + c] -= schur_[static_cast<size_t>(k) * border_ + i] * rhs[k * 3 + c];
                }
            }
            for (int c = 0; c < 3; ++c) {
                rhs[i * 3 + c] /= schur_[static_cast<size_t>(i) * border_ + i];
            }
        }
    }

    /// Banded Cholesky of the normal equations, `ridge` times each diagonal added first. False when a pivot isn't positive.
    bool factor(double ridge) {
        factor_ = normal_;
        const size_t width = static_cast<size_t>(d_ + 1);
        for (int i = 0; i < unknowns_; ++i) {
            const double original = normal_[static_cast<size_t>(i) * width];
            for (int j = std::max(0, i - d_); j <= i; ++j) {
                double sum = factor_[static_cast<size_t>(i) * width + (i - j)];
                if (i == j) {
                    sum += ridge * original;
                }
                for (int k = std::max(j - d_, std::max(0, i - d_)); k < j; ++k) {
                    sum -= factor_[static_cast<size_t>(i) * width + (i - k)] * factor_[static_cast<size_t>(j) * width + (j - k)];
                }
                if (i == j) {
                    if (!(sum > 1e-14 * original) || !std::isfinite(sum)) {
                        return false;
                    }
                    factor_[static_cast<size_t>(i) * width] = std::sqrt(sum);
                } else {
                    factor_[static_cast<size_t>(i) * width + (i - j)] = sum / factor_[static_cast<size_t>(j) * width];
                }
            }
        }
        return true;
    }

    int d_;
    fit_mode mode_;
    int n_;
    int m_;
    bool pinned_;
    int lo_;
    int hi_;
    int unknowns_ = 0;
    int border_ = 0;
    std::vector<double> flat_;
    std::vector<int> span_;
    std::vector<double> values_;
    std::vector<double> normal_;
    std::vector<double> factor_;
    std::vector<double> interior_border_;
    std::vector<double> border_border_;
    std::vector<double> schur_x_;
    std::vector<double> schur_;
};

std::vector<double> evenly(double a, double b, int count) {
    std::vector<double> out(count);
    for (int k = 0; k < count; ++k) {
        out[k] = count > 1 ? a + (b - a) * k / (count - 1) : a;
    }
    return out;
}

void distinct_knots(double a, double b, int d, int s, TColStd_Array1OfReal &knots, TColStd_Array1OfInteger &mult) {
    for (int k = 0; k <= s; ++k) {
        knots(k + 1) = a + (b - a) * k / s;
        mult(k + 1) = (k == 0 || k == s) ? d + 1 : 1;
    }
}

void require_valid_spec(int degree_u, int spans_u, int degree_v, int spans_v, bool surface) {
    if (degree_u < 1 || degree_u > kMaxDegree || (surface && (degree_v < 1 || degree_v > kMaxDegree))) {
        throw user_error("The degree must be from 1 to " + number(kMaxDegree) + ".");
    }
    if (spans_u < 1 || (surface && spans_v < 1)) {
        throw user_error("There must be at least 1 span.");
    }
    const double count = surface ? (static_cast<double>(degree_u) + spans_u) * (static_cast<double>(degree_v) + spans_v)
                                 : static_cast<double>(degree_u) + spans_u;
    if (count > kMaxPoles) {
        throw user_error("That would make " + number(count) + " control points; a " + (surface ? "surface" : "curve") +
                         " may have at most " + number(kMaxPoles) + ".");
    }
}

/// Samples of one direction: `count` evenly over [a, b], or, for a periodic fit, `count - 1` of them without the duplicate end.
std::vector<double> fit_samples(double a, double b, int count, bool periodic) {
    if (!periodic) {
        return evenly(a, b, count);
    }
    std::vector<double> out(count - 1);
    for (int k = 0; k < count - 1; ++k) {
        out[k] = a + (b - a) * k / (count - 1);
    }
    return out;
}

/// A deviation grid per direction: twice as dense as the fit's `samples` (counting the ends), the two together capped at
/// kMaxDeviationSamples points by thinning both directions alike.
void deviation_counts(int samples_u, int samples_v, int &count_u, int &count_v) {
    constexpr double kMaxDeviationSamples = 1000000.0;
    count_u = 2 * (samples_u - 1) + 1;
    count_v = 2 * (samples_v - 1) + 1;
    const double total = static_cast<double>(count_u) * count_v;
    if (total > kMaxDeviationSamples) {
        const double scale = std::sqrt(kMaxDeviationSamples / total);
        count_u = std::max(2, static_cast<int>(count_u * scale));
        count_v = std::max(2, static_cast<int>(count_v * scale));
    }
}

/// The distance from `target` to `surface`, found from the point at the same parameters by a few Gauss-Newton steps toward the
/// nearest point; never more than the gap at the same parameters.
double surface_gap(const Handle(Geom_BSplineSurface) &surface, const gp_Pnt &target, double u, double v, double u0, double u1,
                   double v0, double v1) {
    double best = surface->Value(u, v).Distance(target);
    for (int step = 0; step < 6 && best > 0; ++step) {
        gp_Pnt point;
        gp_Vec du, dv;
        surface->D1(u, v, point, du, dv);
        const gp_Vec r(point, target);
        const double a = du.Dot(du);
        const double b = du.Dot(dv);
        const double c = dv.Dot(dv);
        const double determinant = a * c - b * b;
        if (std::abs(determinant) < 1e-18 * (a * c + 1e-300)) {
            break;
        }
        const double ru = du.Dot(r);
        const double rv = dv.Dot(r);
        const double delta_u = (c * ru - b * rv) / determinant;
        const double delta_v = (a * rv - b * ru) / determinant;
        const double next_u = std::min(std::max(u + delta_u, u0), u1);
        const double next_v = std::min(std::max(v + delta_v, v0), v1);
        const double distance = surface->Value(next_u, next_v).Distance(target);
        if (!(distance < best)) {
            break;
        }
        best = distance;
        u = next_u;
        v = next_v;
    }
    return best;
}

} // namespace

namespace {

/// A direction is fitted periodically when its source is periodic; it then needs at least degree + 1 spans (so the basis functions of
/// one sample are different poles), and fewer are refused rather than fitted clamped, which would bring the seam's crease back.
bool fits_periodically(bool source_periodic, int degree, int spans, const char *what) {
    if (source_periodic && spans < degree + 1) {
        throw user_error(std::string("A closed ") + what + " needs at least " + number(degree + 1) + " spans" +
                         (std::string(what) == "surface" ? " around" : "") + " at degree " + number(degree) + ".");
    }
    return source_periodic;
}

void periodic_knots(double a, double b, int s, TColStd_Array1OfReal &knots, TColStd_Array1OfInteger &mult) {
    for (int k = 0; k <= s; ++k) {
        knots(k + 1) = a + (b - a) * k / s;
        mult(k + 1) = 1;
    }
}

/// Where OpenCascade keeps the pole the fit calls `i` of a periodic direction: the same place (its pole j is the basis function whose
/// support starts at the period's flat knot j, as the fit's does; found by trying every shift against the deviation).
int periodic_slot(int i, int, int) { return i; }

} // namespace

extern "C" {

occt_shape *occt_rebuild_face(const occt_shape *shape, int face_index, int degree_u, int degree_v, int spans_u, int spans_v,
                              const occt_cancel *cancel, double *deviation, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (!shape || shape->shape.IsNull() || !deviation) {
            throw user_error("That surface no longer exists.");
        }
        require_valid_spec(degree_u, spans_u, degree_v, spans_v, true);
        const bool input_valid = BRepCheck_Analyzer(shape->shape).IsValid();
        edit_copy edit = make_edit_copy(shape, face_index);
        const TopoDS_Face face = edit.face();
        double box_u0, box_u1, box_v0, box_v1;
        BRepTools::UVBounds(face, box_u0, box_u1, box_v0, box_v1);
        const Handle(Geom_BSplineSurface) source = edit.surface;
        double a_u, b_u, a_v, b_v;
        source->Bounds(a_u, b_u, a_v, b_v);
        const bool periodic_u = fits_periodically(source->IsUPeriodic(), degree_u, spans_u, "surface");
        const bool periodic_v = fits_periodically(source->IsVPeriodic(), degree_v, spans_v, "surface");
        const int nu = periodic_u ? spans_u : degree_u + spans_u;
        const int nv = periodic_v ? spans_v : degree_v + spans_v;
        const int mu = 4 * (degree_u + spans_u) + 1;
        const int mv = 4 * (degree_v + spans_v) + 1;
        const std::vector<double> us = fit_samples(a_u, b_u, mu, periodic_u);
        const std::vector<double> vs = fit_samples(a_v, b_v, mv, periodic_v);
        const int su = static_cast<int>(us.size());
        const int sv = static_cast<int>(vs.size());
        const fit_1d fit_u(us, a_u, b_u, degree_u, spans_u, periodic_u ? kPeriodic : kClamped);
        const fit_1d fit_v(vs, a_v, b_v, degree_v, spans_v, periodic_v ? kPeriodic : kClamped);

        // The fit works about the net's centre, so a part far from the origin loses no digits.
        gp_XYZ centre(0, 0, 0);
        for (int i = 1; i <= source->NbUPoles(); ++i) {
            for (int j = 1; j <= source->NbVPoles(); ++j) {
                centre += source->Pole(i, j).XYZ();
            }
        }
        centre /= static_cast<double>(source->NbUPoles()) * source->NbVPoles();

        // Rows first: along u at each sampled v, then along v for each of those poles.
        std::vector<double> rows(static_cast<size_t>(nu) * sv * 3);
        std::vector<double> data(static_cast<size_t>(std::max(su, sv)) * 3);
        std::vector<double> fitted(static_cast<size_t>(nu) * 3);
        for (int j = 0; j < sv; ++j) {
            poll(cancel);
            for (int i = 0; i < su; ++i) {
                const gp_XYZ p = source->Value(us[i], vs[j]).XYZ() - centre;
                data[3 * i] = p.X();
                data[3 * i + 1] = p.Y();
                data[3 * i + 2] = p.Z();
            }
            fit_u.solve(data.data(), fitted.data());
            for (int i = 0; i < nu; ++i) {
                for (int c = 0; c < 3; ++c) {
                    rows[(static_cast<size_t>(i) * sv + j) * 3 + c] = fitted[3 * i + c];
                }
            }
        }
        TColgp_Array2OfPnt poles(1, nu, 1, nv);
        std::vector<double> column(static_cast<size_t>(nv) * 3);
        for (int i = 0; i < nu; ++i) {
            poll(cancel);
            fit_v.solve(&rows[static_cast<size_t>(i) * sv * 3], column.data());
            const int slot_i = periodic_u ? periodic_slot(i, degree_u, nu) : i;
            for (int j = 0; j < nv; ++j) {
                const int slot_j = periodic_v ? periodic_slot(j, degree_v, nv) : j;
                if (!std::isfinite(column[3 * j]) || !std::isfinite(column[3 * j + 1]) || !std::isfinite(column[3 * j + 2])) {
                    throw user_error("The fit couldn't be solved for these settings.");
                }
                poles(slot_i + 1, slot_j + 1) =
                    gp_Pnt(column[3 * j] + centre.X(), column[3 * j + 1] + centre.Y(), column[3 * j + 2] + centre.Z());
            }
        }
        const int knot_count_u = spans_u + 1;
        const int knot_count_v = spans_v + 1;
        TColStd_Array1OfReal knots_u(1, knot_count_u);
        TColStd_Array1OfInteger mult_u(1, knot_count_u);
        TColStd_Array1OfReal knots_v(1, knot_count_v);
        TColStd_Array1OfInteger mult_v(1, knot_count_v);
        if (periodic_u) {
            periodic_knots(a_u, b_u, spans_u, knots_u, mult_u);
        } else {
            distinct_knots(a_u, b_u, degree_u, spans_u, knots_u, mult_u);
        }
        if (periodic_v) {
            periodic_knots(a_v, b_v, spans_v, knots_v, mult_v);
        } else {
            distinct_knots(a_v, b_v, degree_v, spans_v, knots_v, mult_v);
        }
        Handle(Geom_BSplineSurface) rebuilt = new Geom_BSplineSurface(poles, knots_u, knots_v, mult_u, mult_v, degree_u, degree_v,
                                                                      periodic_u, periodic_v);

        // The deviation: a grid twice as dense as the fit's samples (capped), over the face's parameter box.
        const double d_u0 = std::max(a_u, box_u0);
        const double d_u1 = std::min(b_u, box_u1);
        const double d_v0 = std::max(a_v, box_v0);
        const double d_v1 = std::min(b_v, box_v1);
        int count_u = 0;
        int count_v = 0;
        deviation_counts(mu, mv, count_u, count_v);
        double worst = 0.0;
        const std::vector<double> grid_u = evenly(d_u0, std::max(d_u0, d_u1), count_u);
        const std::vector<double> grid_v = evenly(d_v0, std::max(d_v0, d_v1), count_v);
        for (const double u : grid_u) {
            poll(cancel);
            for (const double v : grid_v) {
                worst = std::max(worst, surface_gap(rebuilt, source->Value(u, v), u, v, a_u, b_u, a_v, b_v));
            }
        }
        *deviation = worst;

        replace_face_surface(face, rebuilt, edit.converted ? edit.original : TopoDS_Face());
        if (input_valid && !BRepCheck_Analyzer(edit.work).IsValid()) {
            throw user_error("Rebuilding gives an invalid surface.");
        }
        return new occt_shape{edit.work};
    });
}

int occt_rebuild_curve(const occt_shape *wire, int degree, int spans, const occt_cancel *cancel, occt_curve_net *out,
                       double *deviation, occt_status *status) {
    return guarded(status, [&]() -> int {
        occt_initialize();
        *out = occt_curve_net{};
        if (!wire || wire->shape.IsNull() || wire->shape.ShapeType() != TopAbs_WIRE || !deviation) {
            throw user_error("This isn't a curve.");
        }
        require_valid_spec(degree, spans, 1, 1, false);
        // A wire of one edge whose curve is a periodic B-spline run for its whole period is fitted periodically.
        bool source_periodic = false;
        int pieces = 0;
        for (TopExp_Explorer explorer(wire->shape, TopAbs_EDGE); explorer.More(); explorer.Next()) {
            ++pieces;
            if (pieces == 1) {
                double first = 0;
                double last = 0;
                Handle(Geom_Curve) basis = BRep_Tool::Curve(TopoDS::Edge(explorer.Current()), first, last);
                while (!basis.IsNull() && !Handle(Geom_TrimmedCurve)::DownCast(basis).IsNull()) {
                    basis = Handle(Geom_TrimmedCurve)::DownCast(basis)->BasisCurve();
                }
                const Handle(Geom_BSplineCurve) spline = Handle(Geom_BSplineCurve)::DownCast(basis);
                source_periodic = !spline.IsNull() && spline->IsPeriodic() &&
                                  std::abs((last - first) - spline->Period()) <= 1e-9 * (1.0 + spline->Period());
            }
        }
        if (pieces != 1) {
            source_periodic = false;
        }
        const bool periodic = fits_periodically(source_periodic, degree, spans, "curve");
        // Parametrized by arc length between pieces (and by the piece's own parameter within one).
        const BRepAdaptor_CompCurve source(TopoDS::Wire(wire->shape), Standard_True);
        const double t0 = source.FirstParameter();
        const double t1 = source.LastParameter();
        const int n = periodic ? spans : degree + spans;
        const int m = 4 * (degree + spans) + 1;
        const std::vector<double> ts = fit_samples(t0, t1, m, periodic);
        const int count = static_cast<int>(ts.size());
        const fit_1d fit(ts, t0, t1, degree, spans, periodic ? kPeriodic : kPinned);
        std::vector<double> data(static_cast<size_t>(count) * 3);
        gp_XYZ centre(0, 0, 0);
        for (int k = 0; k < count; ++k) {
            if (k % 1024 == 0) {
                poll(cancel);
            }
            const gp_Pnt p = source.Value(ts[k]);
            data[3 * k] = p.X();
            data[3 * k + 1] = p.Y();
            data[3 * k + 2] = p.Z();
            centre += p.XYZ();
        }
        centre /= static_cast<double>(count);
        for (int k = 0; k < count; ++k) {
            data[3 * k] -= centre.X();
            data[3 * k + 1] -= centre.Y();
            data[3 * k + 2] -= centre.Z();
        }
        std::vector<double> fitted(static_cast<size_t>(n) * 3);
        fit.solve(data.data(), fitted.data());
        TColgp_Array1OfPnt poles(1, n);
        for (int k = 0; k < n; ++k) {
            if (!std::isfinite(fitted[3 * k]) || !std::isfinite(fitted[3 * k + 1]) || !std::isfinite(fitted[3 * k + 2])) {
                throw user_error("The fit couldn't be solved for these settings.");
            }
            const int slot = periodic ? periodic_slot(k, degree, n) : k;
            poles(slot + 1) = gp_Pnt(fitted[3 * k] + centre.X(), fitted[3 * k + 1] + centre.Y(), fitted[3 * k + 2] + centre.Z());
        }
        TColStd_Array1OfReal knots(1, spans + 1);
        TColStd_Array1OfInteger mult(1, spans + 1);
        if (periodic) {
            periodic_knots(t0, t1, spans, knots, mult);
        } else {
            distinct_knots(t0, t1, degree, spans, knots, mult);
        }
        Handle(Geom_BSplineCurve) rebuilt = new Geom_BSplineCurve(poles, knots, mult, degree, periodic);

        // The deviation: twice as dense as the fit's samples (capped at one million points).
        double worst = 0.0;
        const int grid_count = std::min(2 * (m - 1) + 1, 1000000);
        const std::vector<double> grid = evenly(t0, t1, grid_count);
        for (size_t k = 0; k < grid.size(); ++k) {
            if (k % 1024 == 0) {
                poll(cancel);
            }
            const double t = grid[k];
            const gp_Pnt target = source.Value(t);
            double param = t;
            double best = rebuilt->Value(param).Distance(target);
            for (int step = 0; step < 6 && best > 0; ++step) {
                gp_Pnt point;
                gp_Vec derivative;
                rebuilt->D1(param, point, derivative);
                const double speed = derivative.Dot(derivative);
                if (speed < 1e-18) {
                    break;
                }
                const double next = std::min(std::max(param + derivative.Dot(gp_Vec(point, target)) / speed, t0), t1);
                const double distance = rebuilt->Value(next).Distance(target);
                if (!(distance < best)) {
                    break;
                }
                best = distance;
                param = next;
            }
            worst = std::max(worst, best);
        }
        *deviation = worst;

        out->converted_from = -1;
        out->periodic = periodic ? 1 : 0;
        out->degree = degree;
        out->rational = 0;
        out->pole_count = n;
        out->poles = zeroed<double>(static_cast<size_t>(n) * 3);
        for (int k = 0; k < n; ++k) {
            const gp_Pnt p = poles(k + 1);
            out->poles[3 * k] = p.X();
            out->poles[3 * k + 1] = p.Y();
            out->poles[3 * k + 2] = p.Z();
        }
        out->knot_count = spans + 1;
        out->knots = zeroed<double>(out->knot_count);
        out->multiplicities = zeroed<int>(out->knot_count);
        for (int k = 0; k <= spans; ++k) {
            out->knots[k] = knots(k + 1);
            out->multiplicities[k] = mult(k + 1);
        }
        return 1;
    });
}

int occt_test_max_edge_tolerance(const occt_shape *shape, double *tolerance, occt_status *status) {
    return guarded(status, [&]() -> int {
        *tolerance = 0;
        for (TopExp_Explorer it(shape->shape, TopAbs_EDGE); it.More(); it.Next()) {
            *tolerance = std::max(*tolerance, BRep_Tool::Tolerance(TopoDS::Edge(it.Current())));
        }
        return 1;
    });
}

} // extern "C"
