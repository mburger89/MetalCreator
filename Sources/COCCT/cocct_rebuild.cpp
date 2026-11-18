// Rebuilding a sheet's one face or a curve to a chosen degree and span count (NS-3, Task 4). Our own separable least-squares fit.
#include "cocct_control_net.hpp"
#include "cocct_sheet.hpp"

#include <BRepAdaptor_CompCurve.hxx>
#include <BRepCheck_Analyzer.hxx>
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

/// Least squares of one direction: the samples' basis values and the banded Cholesky factor of the normal equations, made once and
/// used for every row or column of data. With `pinned` the first and last poles are given, not fitted.
class fit_1d {
public:
    fit_1d(const std::vector<double> &params, double a, double b, int degree, int spans, bool pinned)
        : d_(degree), n_(degree + spans), m_(static_cast<int>(params.size())), pinned_(pinned),
          lo_(pinned ? 1 : 0), hi_(pinned ? n_ - 2 : n_ - 1), flat_(flat_knots(a, b, degree, spans)) {
        unknowns_ = std::max(0, hi_ - lo_ + 1);
        span_.resize(m_);
        values_.assign(static_cast<size_t>(m_) * (d_ + 1), 0.0);
        std::vector<double> left(d_ + 1), right(d_ + 1);
        for (int t = 0; t < m_; ++t) {
            const double u = params[t];
            int k = d_;
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
        for (int t = 0; t < m_; ++t) {
            const double *basis = &values_[static_cast<size_t>(t) * (d_ + 1)];
            const int first = span_[t] - d_;
            for (int p = 0; p <= d_; ++p) {
                const int i = first + p - lo_;
                if (i < 0 || i >= unknowns_) {
                    continue;
                }
                for (int q = 0; q <= p; ++q) {
                    const int j = first + q - lo_;
                    if (j < 0 || j >= unknowns_) {
                        continue;
                    }
                    normal_[static_cast<size_t>(i) * (d_ + 1) + (i - j)] += basis[p] * basis[q];
                }
            }
        }
        if (!factor(0.0) && !factor(1e-10)) {
            throw user_error("The fit couldn't be solved for these settings.");
        }
    }

    int poles() const { return n_; }

    /// Fits `data` (m points, interleaved xyz) into `out` (n points); with `pinned` out's first and last points are set to the
    /// data's first and last.
    void solve(const double *data, double *out) const {
        if (pinned_) {
            for (int c = 0; c < 3; ++c) {
                out[c] = data[c];
                out[3 * (n_ - 1) + c] = data[3 * (m_ - 1) + c];
            }
        }
        if (unknowns_ == 0) {
            return;
        }
        std::vector<double> rhs(static_cast<size_t>(unknowns_) * 3, 0.0);
        for (int t = 0; t < m_; ++t) {
            const double *basis = &values_[static_cast<size_t>(t) * (d_ + 1)];
            const int first = span_[t] - d_;
            double residual[3] = {data[3 * t], data[3 * t + 1], data[3 * t + 2]};
            if (pinned_) {
                for (int p = 0; p <= d_; ++p) {
                    const int index = first + p;
                    if (index == 0 || index == n_ - 1) {
                        for (int c = 0; c < 3; ++c) {
                            residual[c] -= basis[p] * out[3 * index + c];
                        }
                    }
                }
            }
            for (int p = 0; p <= d_; ++p) {
                const int i = first + p - lo_;
                if (i < 0 || i >= unknowns_) {
                    continue;
                }
                for (int c = 0; c < 3; ++c) {
                    rhs[static_cast<size_t>(i) * 3 + c] += basis[p] * residual[c];
                }
            }
        }
        // L y = rhs, then L^T x = y.
        for (int i = 0; i < unknowns_; ++i) {
            for (int k = std::max(0, i - d_); k < i; ++k) {
                const double l = factor_[static_cast<size_t>(i) * (d_ + 1) + (i - k)];
                for (int c = 0; c < 3; ++c) {
                    rhs[static_cast<size_t>(i) * 3 + c] -= l * rhs[static_cast<size_t>(k) * 3 + c];
                }
            }
            const double diagonal = factor_[static_cast<size_t>(i) * (d_ + 1)];
            for (int c = 0; c < 3; ++c) {
                rhs[static_cast<size_t>(i) * 3 + c] /= diagonal;
            }
        }
        for (int i = unknowns_ - 1; i >= 0; --i) {
            for (int k = i + 1; k < std::min(unknowns_, i + d_ + 1); ++k) {
                const double l = factor_[static_cast<size_t>(k) * (d_ + 1) + (k - i)];
                for (int c = 0; c < 3; ++c) {
                    rhs[static_cast<size_t>(i) * 3 + c] -= l * rhs[static_cast<size_t>(k) * 3 + c];
                }
            }
            const double diagonal = factor_[static_cast<size_t>(i) * (d_ + 1)];
            for (int c = 0; c < 3; ++c) {
                const double value = rhs[static_cast<size_t>(i) * 3 + c] / diagonal;
                rhs[static_cast<size_t>(i) * 3 + c] = value;
                out[3 * (lo_ + i) + c] = value;
            }
        }
    }

private:
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
    int n_;
    int m_;
    bool pinned_;
    int lo_;
    int hi_;
    int unknowns_ = 0;
    std::vector<double> flat_;
    std::vector<int> span_;
    std::vector<double> values_;
    std::vector<double> normal_;
    std::vector<double> factor_;
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
        throw user_error("That would make " + number(count) + " control points; at most " + number(kMaxPoles) + " are allowed.");
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
        const int nu = degree_u + spans_u;
        const int nv = degree_v + spans_v;
        const int mu = 4 * nu + 1;
        const int mv = 4 * nv + 1;
        const std::vector<double> us = evenly(a_u, b_u, mu);
        const std::vector<double> vs = evenly(a_v, b_v, mv);
        const fit_1d fit_u(us, a_u, b_u, degree_u, spans_u, false);
        const fit_1d fit_v(vs, a_v, b_v, degree_v, spans_v, false);

        // Rows first: along u at each sampled v, then along v for each of those poles.
        std::vector<double> rows(static_cast<size_t>(nu) * mv * 3);
        std::vector<double> data(static_cast<size_t>(std::max(mu, mv)) * 3);
        std::vector<double> fitted(static_cast<size_t>(nu) * 3);
        for (int j = 0; j < mv; ++j) {
            poll(cancel);
            for (int i = 0; i < mu; ++i) {
                const gp_Pnt p = source->Value(us[i], vs[j]);
                data[3 * i] = p.X();
                data[3 * i + 1] = p.Y();
                data[3 * i + 2] = p.Z();
            }
            fit_u.solve(data.data(), fitted.data());
            for (int i = 0; i < nu; ++i) {
                for (int c = 0; c < 3; ++c) {
                    rows[(static_cast<size_t>(i) * mv + j) * 3 + c] = fitted[3 * i + c];
                }
            }
        }
        TColgp_Array2OfPnt poles(1, nu, 1, nv);
        std::vector<double> column(static_cast<size_t>(nv) * 3);
        for (int i = 0; i < nu; ++i) {
            poll(cancel);
            fit_v.solve(&rows[static_cast<size_t>(i) * mv * 3], column.data());
            for (int j = 0; j < nv; ++j) {
                poles(i + 1, j + 1) = gp_Pnt(column[3 * j], column[3 * j + 1], column[3 * j + 2]);
                if (!std::isfinite(column[3 * j]) || !std::isfinite(column[3 * j + 1]) || !std::isfinite(column[3 * j + 2])) {
                    throw user_error("The fit couldn't be solved for these settings.");
                }
            }
        }
        TColStd_Array1OfReal knots_u(1, spans_u + 1);
        TColStd_Array1OfInteger mult_u(1, spans_u + 1);
        TColStd_Array1OfReal knots_v(1, spans_v + 1);
        TColStd_Array1OfInteger mult_v(1, spans_v + 1);
        distinct_knots(a_u, b_u, degree_u, spans_u, knots_u, mult_u);
        distinct_knots(a_v, b_v, degree_v, spans_v, knots_v, mult_v);
        Handle(Geom_BSplineSurface) rebuilt =
            new Geom_BSplineSurface(poles, knots_u, knots_v, mult_u, mult_v, degree_u, degree_v);

        // The deviation: a grid twice as dense as the fit's samples, over the face's parameter box.
        const double d_u0 = std::max(a_u, box_u0);
        const double d_u1 = std::min(b_u, box_u1);
        const double d_v0 = std::max(a_v, box_v0);
        const double d_v1 = std::min(b_v, box_v1);
        double worst = 0.0;
        const std::vector<double> grid_u = evenly(d_u0, std::max(d_u0, d_u1), 2 * (mu - 1) + 1);
        const std::vector<double> grid_v = evenly(d_v0, std::max(d_v0, d_v1), 2 * (mv - 1) + 1);
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
        // Parametrized by arc length across every piece.
        const BRepAdaptor_CompCurve source(TopoDS::Wire(wire->shape), Standard_True);
        const double t0 = source.FirstParameter();
        const double t1 = source.LastParameter();
        const int n = degree + spans;
        const int m = 4 * n + 1;
        const std::vector<double> ts = evenly(t0, t1, m);
        const fit_1d fit(ts, t0, t1, degree, spans, true);
        std::vector<double> data(static_cast<size_t>(m) * 3);
        for (int k = 0; k < m; ++k) {
            if (k % 1024 == 0) {
                poll(cancel);
            }
            const gp_Pnt p = source.Value(ts[k]);
            data[3 * k] = p.X();
            data[3 * k + 1] = p.Y();
            data[3 * k + 2] = p.Z();
        }
        std::vector<double> fitted(static_cast<size_t>(n) * 3);
        fit.solve(data.data(), fitted.data());
        TColgp_Array1OfPnt poles(1, n);
        for (int k = 0; k < n; ++k) {
            if (!std::isfinite(fitted[3 * k]) || !std::isfinite(fitted[3 * k + 1]) || !std::isfinite(fitted[3 * k + 2])) {
                throw user_error("The fit couldn't be solved for these settings.");
            }
            poles(k + 1) = gp_Pnt(fitted[3 * k], fitted[3 * k + 1], fitted[3 * k + 2]);
        }
        TColStd_Array1OfReal knots(1, spans + 1);
        TColStd_Array1OfInteger mult(1, spans + 1);
        distinct_knots(t0, t1, degree, spans, knots, mult);
        Handle(Geom_BSplineCurve) rebuilt = new Geom_BSplineCurve(poles, knots, mult, degree);

        double worst = 0.0;
        const std::vector<double> grid = evenly(t0, t1, 2 * (m - 1) + 1);
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
        out->periodic = 0;
        out->degree = degree;
        out->rational = 0;
        out->pole_count = n;
        out->poles = zeroed<double>(static_cast<size_t>(n) * 3);
        for (int k = 0; k < n; ++k) {
            out->poles[3 * k] = fitted[3 * k];
            out->poles[3 * k + 1] = fitted[3 * k + 1];
            out->poles[3 * k + 2] = fitted[3 * k + 2];
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

} // extern "C"
