// Strip construction for the curvature-continuous fillet: classifying a strip face's edges into springs and ends,
// the quintic G2 sections between two springs, their pairing, the skinned surface and its pcurves, and the
// adaptive loop that adds sections until the strip's seams meet the tolerances (cocct_g2_blend_internal.hpp).

#include "cocct_g2_blend_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepTools.hxx>
#include <Extrema_ExtPC.hxx>
#include <GeomAPI_ProjectPointOnCurve.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <Geom_BSplineCurve.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColgp_Array1OfPnt2d.hxx>
#include <TColgp_Array2OfPnt.hxx>

#include <algorithm>
#include <cmath>

namespace cocct::g2_blend {

SurfacePoint surface_point(const TopoDS_Face &face, const TopoDS_Edge &edge, double t) {
    double first = 0, last = 0;
    const Handle(Geom2d_Curve) pc = BRep_Tool::CurveOnSurface(edge, face, first, last);
    if (pc.IsNull()) {
        throw user_error(kStripMessage);
    }
    BRepAdaptor_Surface surface(face, Standard_False);
    SurfacePoint s;
    // Where the parametrization is singular (a G2 corner patch at its centre, where three patches meet) the normal is
    // the limit: read it a hair further along the edge, towards its middle.
    const double towards_middle = (t < 0.5 * (first + last)) ? 1.0 : -1.0;
    for (int attempt = 0; attempt < 4; ++attempt) {
        const gp_Pnt2d uv = pc->Value(t + towards_middle * attempt * 1e-3 * (last - first));
        surface.D2(uv.X(), uv.Y(), s.p, s.su, s.sv, s.suu, s.svv, s.suv);
        s.n = s.su.Crossed(s.sv);
        if (s.n.Magnitude() > 1e-6) {
            break;
        }
    }
    if (s.n.Magnitude() < 1e-12) {
        throw user_error(kStripMessage);
    }
    s.n.Normalize();
    if (face.Orientation() == TopAbs_REVERSED) {
        s.n.Reverse();
    }
    return s;
}

Handle(Geom2d_BSplineCurve) line2d(const gp_Pnt2d &from, const gp_Pnt2d &to, double first, double last) {
    TColgp_Array1OfPnt2d poles(1, 2);
    poles.SetValue(1, from);
    poles.SetValue(2, to);
    TColStd_Array1OfReal knots(1, 2);
    knots.SetValue(1, first);
    knots.SetValue(2, last);
    TColStd_Array1OfInteger mults(1, 2);
    mults.SetValue(1, 2);
    mults.SetValue(2, 2);
    return new Geom2d_BSplineCurve(poles, knots, mults, 1);
}

bool is_blend(const TopoDS_Shape &face, const std::vector<TopoDS_Face> &blend) {
    for (const TopoDS_Face &b : blend) {
        if (b.IsSame(face)) {
            return true;
        }
    }
    return false;
}

StripEdges classify(const TopoDS_Face &strip, const TopTools_IndexedDataMapOfShapeListOfShape &edge_faces,
                    const std::vector<TopoDS_Face> &blend, const std::vector<TopoDS_Face> &strips) {
    StripEdges out;
    int springs = 0, ends = 0;
    for (TopExp_Explorer it(strip, TopAbs_EDGE); it.More(); it.Next()) {
        const TopoDS_Edge edge = TopoDS::Edge(it.Current());
        bool duplicate = false;
        for (int i = 0; i < springs; ++i) {
            duplicate = duplicate || out.spring[i].edge.IsSame(edge);
        }
        for (int i = 0; i < ends; ++i) {
            duplicate = duplicate || out.ends[i].IsSame(edge);
        }
        if (duplicate) {
            for (int i = 0; i < ends; ++i) {
                if (out.ends[i].IsSame(edge) && BRep_Tool::IsClosed(edge, strip)) {
                    out.closed = true;
                }
            }
            continue;
        }
        if (BRep_Tool::Degenerated(edge)) {
            throw user_error(kStripMessage);
        }
        TopoDS_Face other;
        for (const TopoDS_Face &face : distinct_faces(edge, edge_faces)) {
            if (!face.IsSame(strip)) {
                other = face;
            }
        }
        bool spring = false;
        if (!other.IsNull() && !is_blend(other, blend)) {
            double first = 0, last = 0;
            BRep_Tool::Range(edge, first, last);
            const double mid = 0.5 * (first + last);
            const SurfacePoint a = surface_point(strip, edge, mid);
            const SurfacePoint b = surface_point(other, edge, mid);
            spring = std::abs(a.n.Dot(b.n)) > 0.99;
        }
        if (spring && springs < 2) {
            out.spring[springs].edge = edge;
            out.spring[springs].neighbour = other;
            ++springs;
        } else if (!spring && ends < 2) {
            if (!other.IsNull() && is_blend(other, strips)) {
                // Two strips of a tangent chain share a section; two strips meeting at an angle share a mitre,
                // which has no section to replace.
                double first = 0, last = 0;
                BRep_Tool::Range(edge, first, last);
                const double mid = 0.5 * (first + last);
                if (std::abs(surface_point(strip, edge, mid).n.Dot(surface_point(other, edge, mid).n)) < 0.99) {
                    out.end_strip[ends] = other; // a mitre: both strips are built past it and meet along their intersection
                } else {
                    out.end_chain[ends] = other;
                }
            }
            out.ends[ends] = edge;
            if (!other.IsNull() && !is_blend(other, blend)) {
                out.end_face[ends] = other;
            }
            ++ends;
        } else {
            throw user_error(kStripMessage);
        }
    }
    if (out.closed && ends == 1) {
        out.ends[1] = out.ends[0];
        ends = 2;
    }
    if (springs != 2 || ends != 2) {
        throw user_error(kStripMessage);
    }
    // Sample both springs from the same end.
    BRepAdaptor_Curve ca(out.spring[0].edge), cb(out.spring[1].edge);
    const gp_Pnt a0 = ca.Value(ca.FirstParameter()), a1 = ca.Value(ca.LastParameter());
    const gp_Pnt b0 = cb.Value(cb.FirstParameter()), b1 = cb.Value(cb.LastParameter());
    out.spring[1].flipped = a0.Distance(b0) + a1.Distance(b1) > a0.Distance(b1) + a1.Distance(b0);
    for (Spring &sp : out.spring) {
        BRepAdaptor_Curve c(sp.edge);
        sp.t_start = sp.flipped ? c.LastParameter() : c.FirstParameter();
        sp.t_end = sp.flipped ? c.FirstParameter() : c.LastParameter();
    }
    return out;
}

namespace {

constexpr int kFirstSections = 9;   // cross-sections per strip to start with
constexpr int kMaxSections = 129;   // the cap: 9, 17, 33, 65, 129
constexpr int kFirstDegree = 3;     // of the skin along the strip, first: a cubic (cheaper to mesh and check) ...
constexpr int kSkinDegree = 5;      // ... and, if the cubic misses at the first sections, a quintic from then on
constexpr int kPieceSamples = 8;    // samples of a spring's pcurve in every piece between breaks, at least
constexpr double kBreakMargin = 1e-4; // a spring's knot nearer a strip's end than this share of it is no break

/// The edge parameter of fraction `fraction` of the way from the spring's sampling start to its sampling end.
double sample_parameter(const Spring &spring, double fraction) {
    return spring.t_start + fraction * (spring.t_end - spring.t_start);
}

/// What turns `spring`'s own unit tangent at its end `end` into the junction's agreed one, faded by `closeness` (1 at
/// that end, 0 at the other, with its first two derivatives): nothing where the end is no junction.
gp_Vec junction_correction(const Spring &spring, int end, double closeness) {
    if (!spring.has_tangent[end]) {
        return gp_Vec(0, 0, 0);
    }
    gp_Pnt p;
    gp_Vec own;
    BRepAdaptor_Curve(spring.edge).D1(end == 0 ? spring.t_start : spring.t_end, p, own);
    own.Normalize();
    // The agreed tangent points along one of the two strips, not necessarily along this spring's parameter.
    const gp_Vec agreed = spring.junction_tangent[end].Dot(own) < 0 ? spring.junction_tangent[end].Reversed() : spring.junction_tangent[end];
    return (agreed - own) * (closeness * closeness * closeness);
}

/// The neighbour's end condition across `spring`'s edge at edge parameter `t`: position, the unit direction of travel
/// (into the blend when `entering`, else out of it) and the acceleration, the normal curvature times the normal.
NeighbourEnd end_condition(const Spring &spring, double t, const gp_Pnt &other, bool entering) {
    const SurfacePoint s = surface_point(spring.neighbour, spring.edge, t);
    BRepAdaptor_Curve curve(spring.edge);
    gp_Pnt p;
    gp_Vec tangent;
    curve.D1(t, p, tangent);
    // At a chain junction both strips use the bisector of the two springs' tangents, so they share one section. Away
    // from it the difference between the bisector and the spring's own tangent there fades out along the whole strip,
    // so across is a smooth function of the parameter that the skin can follow: any direction in the neighbour's
    // tangent plane makes the section tangent to it. Bisector at the end section alone, a jump between the first two
    // sections, keeps the skin's across off the tangent plane of a neighbour that curves along the spring, by an angle
    // that falls only with the first power of the sections' spacing.
    if (spring.has_tangent[0] && std::abs(t - spring.t_start) < 1e-9) {
        tangent = spring.junction_tangent[0];
    } else if (spring.has_tangent[1] && std::abs(t - spring.t_end) < 1e-9) {
        tangent = spring.junction_tangent[1];
    } else if (spring.has_tangent[0] || spring.has_tangent[1]) {
        const double f = std::clamp((t - spring.t_start) / (spring.t_end - spring.t_start), 0.0, 1.0);
        tangent.Normalize();
        tangent += junction_correction(spring, 0, 1 - f) + junction_correction(spring, 1, f);
    }
    gp_Vec across = s.n.Crossed(tangent);
    if (across.Magnitude() < 1e-12) {
        throw user_error(kStripMessage);
    }
    across.Normalize();
    if (across.Dot(gp_Vec(s.p, other)) < 0) {
        across.Reverse();
    }
    const double kappa = s.normal_curvature(across);
    NeighbourEnd e;
    e.condition.position = from_pnt(s.p);
    e.condition.direction = from_vec(entering ? across : across.Reversed());
    e.condition.acceleration = from_vec(s.n * kappa);
    e.p = s.p;
    e.n = s.n;
    e.tangent = tangent;
    return e;
}

/// The edge parameters of each section's point on the first spring (linear in the parameter range) and on the second
/// (the first's point projected onto it, so a curve whose parameter runs differently from the first's is paired by
/// geometry). B's own parameter is pinned at the ends (they are the ends) and at the breaks (where the strip's skin has
/// a knot, so B's point there is the one its own curve has the break at). The projection's difference from a pin fades
/// out towards the next pin (weights w^6 and (1-w)^6 across the piece between them), so a slightly slanted end does
/// not make the pairing jump at its last section and the sections away from the pins stay square. Falls back to the
/// linear pairing when the projection is not monotone.
struct Pairing {
    std::vector<double> ta, tb;
};

Pairing pair_sections(const Spring &a, const Spring &b, const std::vector<double> &fractions,
                      const std::vector<double> &breaks) {
    const int sections = static_cast<int>(fractions.size());
    Pairing pairing;
    BRepAdaptor_Curve ca(a.edge), cb(b.edge);
    for (int j = 0; j < sections; ++j) {
        pairing.ta.push_back(sample_parameter(a, fractions[j]));
        pairing.tb.push_back(sample_parameter(b, fractions[j]));
    }
    // Springs sampled over one parameter range are the two sides of OpenCascade's own strip, both parametrized by its
    // spine: equal parameters are one of its cross-sections already, and the linear pairing is exact (a projection of a
    // point near a strip's end can find the other spring's wrong extremum by the last bit of the input).
    if (std::abs(a.t_start - b.t_start) < 1e-9 && std::abs(a.t_end - b.t_end) < 1e-9) {
        return pairing;
    }
    const double direction = b.t_end > b.t_start ? 1 : -1;
    const double lo = std::min(b.t_start, b.t_end), hi = std::max(b.t_start, b.t_end);
    const double window = 0.25 * (hi - lo);
    // The parameter of the point of B nearest A's point at fraction f (the ends may fall slightly outside B's range).
    // The search window runs past B's ends, where the curve is only an extrapolation of its polynomials: that can hold
    // a spurious minimum (even a nearer one than the true projection) that appears and vanishes with the last bits
    // of the input, and the extremum search also returns maxima. So only minima count, and of those the one nearest
    // the parameter the strip's own proportions expect (B's sample_parameter), a choice that moves continuously.
    auto project_onto_b = [&](double f, double &out) {
        Extrema_ExtPC ext(ca.Value(sample_parameter(a, f)), cb, lo - window, hi + window);
        if (!ext.IsDone() || ext.NbExt() == 0) {
            return false;
        }
        const double expected = sample_parameter(b, f);
        int best = 0;
        for (int i = 1; i <= ext.NbExt(); ++i) {
            if (!ext.IsMin(i)) {
                continue;
            }
            if (best == 0 || std::abs(ext.Point(i).Parameter() - expected) < std::abs(ext.Point(best).Parameter() - expected)) {
                best = i;
            }
        }
        if (best == 0) {
            return false;
        }
        out = ext.Point(best).Parameter();
        return true;
    };
    // The pins: the fraction and B's parameter minus the projection there. B's own ends need not be the projections
    // of A's (a slightly slanted end); without the projections of the ends the ends are not corrected.
    std::vector<double> pin_at{0.0}, pin_offset{0.0};
    for (const double f : breaks) {
        pin_at.push_back(f);
        pin_offset.push_back(0.0);
    }
    pin_at.push_back(1.0);
    pin_offset.push_back(0.0);
    bool usable = true;
    {
        double at_start = 0, at_end = 0;
        if (project_onto_b(0.0, at_start) && project_onto_b(1.0, at_end)) {
            pin_offset.front() = sample_parameter(b, 0.0) - at_start;
            pin_offset.back() = sample_parameter(b, 1.0) - at_end;
        }
        for (std::size_t k = 1; k + 1 < pin_at.size() && usable; ++k) {
            double value = 0;
            usable = project_onto_b(pin_at[k], value);
            pin_offset[k] = sample_parameter(b, pin_at[k]) - value;
        }
    }
    std::vector<double> projected = pairing.tb;
    for (int j = 1; j + 1 < sections && usable; ++j) {
        const double f = fractions[j];
        std::size_t k = 1;
        while (k + 1 < pin_at.size() && pin_at[k] < f) {
            ++k;
        }
        if (std::abs(pin_at[k] - f) < 1e-12) {
            continue; // a break: B's own parameter there
        }
        double value = 0;
        usable = project_onto_b(f, value);
        const double w = (f - pin_at[k - 1]) / (pin_at[k] - pin_at[k - 1]);
        projected[j] = value + pin_offset[k - 1] * std::pow(1 - w, 6) + pin_offset[k] * std::pow(w, 6);
    }
    for (int j = 1; j < sections && usable; ++j) {
        usable = direction * (projected[j] - projected[j - 1]) > 1e-12;
    }
    if (usable) {
        pairing.tb = projected;
    }
    return pairing;
}

/// A B-spline through given values: its poles (each as many numbers as a value has), knots, multiplicities and degree.
struct Spline {
    std::vector<std::vector<double>> poles;
    std::vector<double> knots;
    std::vector<int> mults;
    int degree = 0;
};

/// The values at `x` of the `degree + 1` B-spline basis functions of the flat knot vector `flat` that are nonzero on
/// its span `span` (flat[span] <= x < flat[span + 1]): the functions span - degree ... span (The NURBS Book, A2.2).
std::vector<double> basis_at(const std::vector<double> &flat, std::size_t span, double x, int degree) {
    const std::size_t p = static_cast<std::size_t>(degree);
    std::vector<double> n(p + 1, 0.0), left(p + 1, 0.0), right(p + 1, 0.0);
    n[0] = 1;
    for (std::size_t j = 1; j <= p; ++j) {
        left[j] = x - flat[span + 1 - j];
        right[j] = flat[span + j] - x;
        double saved = 0;
        for (std::size_t r = 0; r < j; ++r) {
            const double temp = n[r] / (right[r + 1] + left[j - r]);
            n[r] = saved + right[r + 1] * temp;
            saved = left[j - r] * temp;
        }
        n[j] = saved;
    }
    return n;
}

/// Solves `matrix` x = `rhs` (one column per number of a value) in place, by Gaussian elimination with partial
/// pivoting; the solution replaces `rhs`. False when the matrix is singular.
bool solve(std::vector<std::vector<double>> &matrix, std::vector<std::vector<double>> &rhs) {
    const std::size_t n = matrix.size();
    for (std::size_t c = 0; c < n; ++c) {
        std::size_t pivot = c;
        for (std::size_t r = c + 1; r < n; ++r) {
            if (std::abs(matrix[r][c]) > std::abs(matrix[pivot][c])) {
                pivot = r;
            }
        }
        if (std::abs(matrix[pivot][c]) < 1e-12) {
            return false;
        }
        std::swap(matrix[c], matrix[pivot]);
        std::swap(rhs[c], rhs[pivot]);
        for (std::size_t r = c + 1; r < n; ++r) {
            const double factor = matrix[r][c] / matrix[c][c];
            if (factor == 0) {
                continue;
            }
            for (std::size_t k = c; k < n; ++k) {
                matrix[r][k] -= factor * matrix[c][k];
            }
            for (std::size_t k = 0; k < rhs[r].size(); ++k) {
                rhs[r][k] -= factor * rhs[c][k];
            }
        }
    }
    for (std::size_t c = n; c-- > 0;) {
        for (std::size_t k = 0; k < rhs[c].size(); ++k) {
            double value = rhs[c][k];
            for (std::size_t r = c + 1; r < n; ++r) {
                value -= matrix[c][r] * rhs[r][k];
            }
            rhs[c][k] = value / matrix[c][c];
        }
    }
    return true;
}

/// The clamped spline of degree min(`degree`, points - 1) through `values` at the increasing parameters `x`, with
/// de Boor's averaged knots (it reproduces every polynomial of its degree, so its error falls as the spacing to the
/// power degree + 1), then raised to `degree` when it had fewer points than that needs (it is one polynomial then).
/// `poles` and `flat` (the flat knot vector) are the result.
void open_piece(const std::vector<std::vector<double>> &values, const std::vector<double> &x, int degree,
                std::vector<std::vector<double>> &poles, std::vector<double> &flat) {
    const std::size_t n = values.size();
    const int own = std::min(degree, static_cast<int>(n) - 1);
    const std::size_t p = static_cast<std::size_t>(own);
    flat.assign(p + 1, x.front());
    for (std::size_t j = 1; j + p < n; ++j) {
        double sum = 0;
        for (std::size_t k = j; k < j + p; ++k) {
            sum += x[k];
        }
        flat.push_back(sum / own);
    }
    flat.insert(flat.end(), p + 1, x.back());
    std::vector<std::vector<double>> matrix(n, std::vector<double>(n, 0.0));
    poles = values;
    for (std::size_t j = 0; j < n; ++j) {
        std::size_t span = p;
        while (span + 1 < n && flat[span + 1] <= x[j]) {
            ++span;
        }
        const std::vector<double> basis = basis_at(flat, span, x[j], own);
        for (std::size_t r = 0; r <= p; ++r) {
            matrix[j][span - p + r] = basis[r];
        }
    }
    if (!solve(matrix, poles)) {
        throw user_error(kStripMessage);
    }
    // One polynomial of a lower degree (a piece of fewer points than the degree needs): raised one degree at a time.
    for (int d = own; d < degree; ++d) {
        std::vector<std::vector<double>> raised(static_cast<std::size_t>(d) + 2, poles.front());
        raised.back() = poles.back();
        for (std::size_t i = 1; i <= static_cast<std::size_t>(d); ++i) {
            const double a = static_cast<double>(i) / (d + 1);
            for (std::size_t k = 0; k < poles[i].size(); ++k) {
                raised[i][k] = a * poles[i - 1][k] + (1 - a) * poles[i][k];
            }
        }
        poles = raised;
        flat.insert(flat.begin(), x.front());
        flat.push_back(x.back());
    }
}

/// The spline of `degree` through `values` at the increasing parameters `x`, made of one open piece (open_piece)
/// between each pair of consecutive breaks (`breaks`: indices into x, the ends excluded), joined with a knot of full
/// multiplicity there: the data need not be smooth across a break, and the spline does not smooth them over it.
Spline interpolate_open(const std::vector<std::vector<double>> &values, const std::vector<double> &x,
                        const std::vector<std::size_t> &breaks, int degree) {
    std::vector<std::size_t> ends{0};
    for (const std::size_t b : breaks) {
        ends.push_back(b);
    }
    ends.push_back(values.size() - 1);
    Spline spline;
    spline.degree = degree;
    for (std::size_t piece = 0; piece + 1 < ends.size(); ++piece) {
        const std::size_t from = ends[piece], to = ends[piece + 1];
        const std::vector<std::vector<double>> piece_values(values.begin() + static_cast<std::ptrdiff_t>(from),
                                                            values.begin() + static_cast<std::ptrdiff_t>(to) + 1);
        const std::vector<double> piece_x(x.begin() + static_cast<std::ptrdiff_t>(from),
                                          x.begin() + static_cast<std::ptrdiff_t>(to) + 1);
        std::vector<std::vector<double>> poles;
        std::vector<double> flat;
        open_piece(piece_values, piece_x, degree, poles, flat);
        // A piece's first pole is its first value, which is the previous piece's last pole.
        spline.poles.insert(spline.poles.end(), poles.begin() + (piece == 0 ? 0 : 1), poles.end());
        if (piece == 0) {
            spline.knots.push_back(flat.front());
            spline.mults.push_back(degree + 1);
        } else {
            spline.mults.back() = degree;
        }
        for (std::size_t q = static_cast<std::size_t>(degree) + 1; q + 1 < flat.size(); ++q) {
            if (flat[q] == spline.knots.back()) {
                ++spline.mults.back();
            } else {
                spline.knots.push_back(flat[q]);
                spline.mults.push_back(1);
            }
        }
        spline.mults.back() = degree + 1;
    }
    return spline;
}

/// The periodic spline of odd `degree` through `values` at `x` (the last value repeats the first, a period later),
/// with a knot at every value, so it is as smooth across its junction as anywhere. Its poles are in OpenCascade's
/// order for a periodic B-spline with these knots, all of multiplicity 1.
Spline interpolate_periodic(const std::vector<std::vector<double>> &values, const std::vector<double> &x, int degree) {
    const int m = static_cast<int>(values.size()) - 1;
    if (m <= degree) {
        throw user_error(kStripMessage);
    }
    const double period = x.back() - x.front();
    // The knots at the values, carried on periodically past both ends: flat[q] is the knot of value q - degree - 1.
    std::vector<double> flat;
    for (int q = -(degree + 1); q <= m + degree + 1; ++q) {
        const int wraps = static_cast<int>(std::floor(static_cast<double>(q) / m));
        flat.push_back(x[static_cast<std::size_t>(q - wraps * m)] + wraps * period);
    }
    const std::size_t size = static_cast<std::size_t>(m);
    std::vector<std::vector<double>> matrix(size, std::vector<double>(size, 0.0));
    std::vector<std::vector<double>> poles(values.begin(), values.end() - 1);
    for (int j = 0; j < m; ++j) {
        const std::size_t span = static_cast<std::size_t>(j + degree + 1);
        const std::vector<double> basis = basis_at(flat, span, x[static_cast<std::size_t>(j)], degree);
        for (int r = 0; r <= degree; ++r) {
            // Basis function span - degree + r of the unrolled knots is the periodic one of index (that - degree - 1).
            const int column = (((j + r - degree) % m) + m) % m;
            matrix[static_cast<std::size_t>(j)][static_cast<std::size_t>(column)] += basis[static_cast<std::size_t>(r)];
        }
    }
    if (!solve(matrix, poles)) {
        throw user_error(kStripMessage);
    }
    Spline spline;
    spline.degree = degree;
    // OpenCascade's first periodic pole is the function that starts `degree` knots before the first knot.
    std::rotate(poles.begin(), poles.begin() + (m - degree), poles.end());
    spline.poles = poles;
    spline.knots = x;
    spline.mults.assign(x.size(), 1);
    return spline;
}

/// The pcurve of a spring on the strip (v fixed): u as a function of the edge parameter, through the points
/// (t[j], u[j]), with a corner at each of `breaks` (edge parameters among t). A straight map (the usual case) is a
/// line; otherwise it is a cubic spline through the points, in pieces between the breaks.
Handle(Geom2d_Curve) spring_pcurve(std::vector<double> t, std::vector<double> u, double v,
                                   const std::vector<double> &breaks) {
    if (t.front() > t.back()) {
        std::reverse(t.begin(), t.end());
        std::reverse(u.begin(), u.end());
    }
    bool straight = true;
    for (std::size_t j = 0; j < t.size(); ++j) {
        const double expected = u.front() + (u.back() - u.front()) * (t[j] - t.front()) / (t.back() - t.front());
        straight = straight && std::abs(expected - u[j]) < 1e-7;
    }
    if (straight) {
        return line2d(gp_Pnt2d(u.front(), v), gp_Pnt2d(u.back(), v), t.front(), t.back());
    }
    std::vector<std::size_t> at;
    for (std::size_t j = 1; j + 1 < t.size(); ++j) {
        for (const double b : breaks) {
            if (std::abs(t[j] - b) < 1e-12) {
                at.push_back(j);
            }
        }
    }
    std::vector<std::vector<double>> values;
    for (const double value : u) {
        values.push_back({value});
    }
    const Spline spline = interpolate_open(values, t, at, 3);
    TColgp_Array1OfPnt2d poles(1, static_cast<int>(spline.poles.size()));
    for (std::size_t k = 0; k < spline.poles.size(); ++k) {
        poles.SetValue(static_cast<int>(k) + 1, gp_Pnt2d(spline.poles[k][0], v));
    }
    TColStd_Array1OfReal knots(1, static_cast<int>(spline.knots.size()));
    TColStd_Array1OfInteger mults(1, static_cast<int>(spline.knots.size()));
    for (std::size_t k = 0; k < spline.knots.size(); ++k) {
        knots.SetValue(static_cast<int>(k) + 1, spline.knots[k]);
        mults.SetValue(static_cast<int>(k) + 1, spline.mults[k]);
    }
    return new Geom2d_BSplineCurve(poles, knots, mults, spline.degree);
}

/// The fractions of the strip (in `spring`'s sampling range) at the interior knots of its curve where the curve's
/// first or second derivative jumps: a curve made of pieces (OpenCascade's fillet joins its springs' pieces only
/// tangent where the edges it rounds change from a line to an arc). The strip's skin breaks there.
std::vector<double> spring_breaks(const Spring &spring) {
    std::vector<double> out;
    BRepAdaptor_Curve curve(spring.edge);
    if (curve.GetType() != GeomAbs_BSplineCurve) {
        return out;
    }
    const Handle(Geom_BSplineCurve) bspline = curve.BSpline();
    for (int k = 2; k < bspline->NbKnots(); ++k) {
        const double knot = bspline->Knot(k);
        const double f = (knot - spring.t_start) / (spring.t_end - spring.t_start);
        if (f < kBreakMargin || f > 1 - kBreakMargin) {
            continue;
        }
        gp_Pnt p;
        gp_Vec d1_before, d2_before, d1_after, d2_after;
        bspline->LocalD2(knot, k - 1, k, p, d1_before, d2_before);
        bspline->LocalD2(knot, k, k + 1, p, d1_after, d2_after);
        const double speed = d1_before.Magnitude();
        const double bend = d2_before.Magnitude() + d2_after.Magnitude() + speed * speed;
        const bool jumps = (d1_after - d1_before).Magnitude() > 1e-9 * speed || (d2_after - d2_before).Magnitude() > 1e-7 * bend;
        if (jumps) {
            out.push_back(f);
        }
    }
    return out;
}

/// The strip through sections at `fractions`, its skin of `degree` along the strip and broken at `breaks` (fractions
/// among them).
BuiltStrip build_strip(const Spring &a, const Spring &b, double weight, const std::vector<double> &fractions,
                       const std::vector<double> &breaks, int degree, bool closed) {
    BuiltStrip built;
    const int sections = static_cast<int>(fractions.size());
    built.sections.resize(sections);
    const Pairing pairing = pair_sections(a, b, fractions, breaks);
    built.ta = pairing.ta;
    BRepAdaptor_Curve ca(a.edge), cb(b.edge);
    for (int j = 0; j < sections; ++j) {
        const gp_Pnt pa = ca.Value(pairing.ta[j]);
        const gp_Pnt pb = cb.Value(pairing.tb[j]);
        const NeighbourEnd e0 = end_condition(a, pairing.ta[j], pb, true);
        const NeighbourEnd e1 = end_condition(b, pairing.tb[j], pa, false);
        const double chord = pa.Distance(pb);
        const double theta = g2::turning_angle(e0.condition.direction, e1.condition.direction);
        const double d = weight * g2::circular_tangent_length(chord, theta);
        built.sections[j] = g2::quintic_poles(e0.condition, d, e1.condition, d);
        built.first_ends.push_back(e0);
        built.second_ends.push_back(e1);
    }
    const std::vector<double> &u = fractions;
    // The breaks as indices of sections and as each spring's edge parameters there.
    std::vector<std::size_t> break_index;
    std::vector<double> break_t[2];
    for (std::size_t j = 1; j + 1 < fractions.size(); ++j) {
        if (std::any_of(breaks.begin(), breaks.end(), [&](double f) { return std::abs(f - fractions[j]) < 1e-12; })) {
            break_index.push_back(j);
            break_t[0].push_back(pairing.ta[j]);
            break_t[1].push_back(pairing.tb[j]);
        }
    }
    built.pcurve[0] = spring_pcurve(pairing.ta, u, 0, break_t[0]);
    built.pcurve[1] = spring_pcurve(pairing.tb, u, 1, break_t[1]);
    // Skin: every pole row interpolated along the strip through the sections, all with the same knots. A quintic
    // follows the sections between them to the sixth power of their spacing (a cubic's error falls with the fourth,
    // its normal's with the third). A closed strip (a hole edge's) is periodic.
    std::vector<std::vector<double>> rows;
    for (const auto &section : built.sections) {
        std::vector<double> row;
        for (const g2::Vec &q : section) {
            row.insert(row.end(), q.begin(), q.end());
        }
        rows.push_back(row);
    }
    const Spline skin = closed ? interpolate_periodic(rows, u, degree) : interpolate_open(rows, u, break_index, degree);
    const int count = static_cast<int>(skin.poles.size());
    TColgp_Array2OfPnt poles(1, count, 1, 6);
    for (int k = 0; k < count; ++k) {
        const std::vector<double> &q = skin.poles[static_cast<std::size_t>(k)];
        for (std::size_t i = 0; i < 6; ++i) {
            poles.SetValue(k + 1, static_cast<int>(i) + 1, gp_Pnt(q[3 * i], q[3 * i + 1], q[3 * i + 2]));
        }
    }
    const int knot_count = static_cast<int>(skin.knots.size());
    TColStd_Array1OfReal uknots(1, knot_count);
    TColStd_Array1OfInteger umults(1, knot_count);
    for (int k = 0; k < knot_count; ++k) {
        uknots.SetValue(k + 1, skin.knots[static_cast<std::size_t>(k)]);
        umults.SetValue(k + 1, skin.mults[static_cast<std::size_t>(k)]);
    }
    TColStd_Array1OfReal vknots(1, 2);
    vknots.SetValue(1, 0);
    vknots.SetValue(2, 1);
    TColStd_Array1OfInteger vmults(1, 2);
    vmults.SetValue(1, 6);
    vmults.SetValue(2, 6);
    built.surface = new Geom_BSplineSurface(poles, uknots, vknots, umults, vmults, skin.degree, 5,
                                            closed ? Standard_True : Standard_False, Standard_False);
    if (!closed) {
        // The pcurves put each spring edge's own parametrization on the strip: u of the point of the boundary curve
        // nearest the edge's point at t, for many t, so that the strip's boundary and the edge agree wherever the edge's
        // parameter is not simply proportional to u.
        const Spring *springs[2] = {&a, &b};
        for (int side = 0; side < 2; ++side) {
            const Handle(Geom_Curve) boundary = built.surface->VIso(side);
            const int samples = 2 * (sections - 1) + 1;
            const double first = springs[side]->t_start, span = springs[side]->t_end - springs[side]->t_start;
            // Samples: evenly along the edge, plus the sections' own parameters and the middles of their spans, and
            // the breaks with a few samples in every piece between them (a piece may be a sliver at a strip's end).
            // Where the sections crowd together (a strip's ends, where the pairing bends sharply) the map from the
            // edge parameter to u bends sharply too, and evenly spaced samples cannot follow it with their end
            // conditions.
            const std::vector<double> &paired = side == 0 ? pairing.ta : pairing.tb;
            std::vector<double> fraction, kept;
            for (int k = 0; k < samples; ++k) {
                fraction.push_back(static_cast<double>(k) / (samples - 1));
            }
            for (int j = 0; j < sections; ++j) {
                fraction.push_back((paired[j] - first) / span);
                if (j + 1 < sections) {
                    fraction.push_back((0.5 * (paired[j] + paired[j + 1]) - first) / span);
                }
            }
            for (const double t : break_t[side]) {
                kept.push_back((t - first) / span);
            }
            std::vector<double> piece_ends{0.0};
            piece_ends.insert(piece_ends.end(), kept.begin(), kept.end());
            piece_ends.push_back(1.0);
            for (std::size_t q = 0; q + 1 < piece_ends.size() && !kept.empty(); ++q) {
                for (int k = 1; k < kPieceSamples; ++k) {
                    fraction.push_back(piece_ends[q] + (piece_ends[q + 1] - piece_ends[q]) * k / kPieceSamples);
                }
            }
            // Samples too near a break or each other go; the breaks stay, at exactly their parameters.
            std::sort(fraction.begin(), fraction.end());
            std::vector<double> distinct{0.0};
            for (const double value : fraction) {
                const bool near_break =
                    std::any_of(kept.begin(), kept.end(), [&](double f) { return std::abs(f - value) < 1e-6; });
                if (!near_break && value > distinct.back() + 1e-6 && value < 1 - 1e-6) {
                    distinct.push_back(value);
                }
            }
            distinct.push_back(1.0);
            for (const double f : kept) {
                distinct.insert(std::upper_bound(distinct.begin(), distinct.end(), f), f);
            }
            const int count = static_cast<int>(distinct.size());
            std::vector<double> t(count), uu(count);
            bool projected = true;
            for (int k = 0; k < count && projected; ++k) {
                t[k] = k == 0 ? first : (k == count - 1 ? springs[side]->t_end : first + span * distinct[k]);
                for (const double tb : break_t[side]) {
                    if (std::abs((tb - first) / span - distinct[static_cast<std::size_t>(k)]) < 1e-14) {
                        t[k] = tb; // exactly the break's parameter
                    }
                }
                GeomAPI_ProjectPointOnCurve project(surface_point(springs[side]->neighbour, springs[side]->edge, t[k]).p, boundary);
                projected = project.NbPoints() > 0;
                if (projected) {
                    uu[k] = project.LowerDistanceParameter();
                    projected = k == 0 || uu[k] > uu[k - 1] - 1e-12;
                }
            }
            if (projected) {
                uu.front() = 0;
                uu.back() = 1;
                built.pcurve[side] = spring_pcurve(t, uu, side, break_t[side]);
            }
        }
    }
    return built;
}

/// The signed distance of `p` from a neighbour's surface (positive on the side its outward normal points to), by
/// projecting onto the surface itself, so a neighbour that curves away from its tangent plane is not mistaken for an
/// overshoot. Falls back to the tangent plane at `end` when the projection or the face's location isn't usable.
double offset_from(const Spring &spring, const NeighbourEnd &end, const gp_Pnt &p) {
    TopLoc_Location location;
    const Handle(Geom_Surface) surface = BRep_Tool::Surface(spring.neighbour, location);
    if (!surface.IsNull()) {
        // The surface lives in the face's own frame: bring the point in, and the result back out.
        const gp_Trsf frame = location.Transformation();
        GeomAPI_ProjectPointOnSurf project(p.Transformed(frame.Inverted()), surface);
        if (project.NbPoints() > 0) {
            double u = 0, v = 0;
            project.LowerDistanceParameters(u, v);
            gp_Pnt on;
            gp_Vec du, dv;
            surface->D1(u, v, on, du, dv);
            gp_Vec n = du.Crossed(dv);
            if (n.Magnitude() > 1e-12) {
                n.Normalize();
                if (spring.neighbour.Orientation() == TopAbs_REVERSED) {
                    n.Reverse();
                }
                return gp_Vec(on.Transformed(frame), p).Dot(n.Transformed(frame));
            }
        }
    }
    return gp_Vec(end.p, p).Dot(end.n);
}

/// Refuses sections that leave the wedge the neighbours' surfaces make at their ends (the tangency weight is too
/// large: material would be pushed past the original corner), sections whose middle strays from the circular strip's
/// own face by more than half the fillet radius or off its parameter range (a strip that isn't a sane blend), and end
/// sections that don't cross the springs squarely.
void validate_sections(const BuiltStrip &built, const TopoDS_Face &circular_face, const Spring &a, const Spring &b,
                       double radius) {
    const Handle(Geom_Surface) circular = BRep_Tool::Surface(circular_face);
    double umin = 0, umax = 0, vmin = 0, vmax = 0;
    BRepTools::UVBounds(circular_face, umin, umax, vmin, vmax);
    const double margin_u = 0.05 * (umax - umin) + 1e-9, margin_v = 0.05 * (vmax - vmin) + 1e-9;
    const BRepAdaptor_Curve own_range(a.edge);
    for (std::size_t j = 0; j < built.sections.size(); ++j) {
        // A section past the spring's own end (built to be trimmed by the end face) lies outside the circular face.
        const bool inside = built.ta[j] >= own_range.FirstParameter() - 1e-9 && built.ta[j] <= own_range.LastParameter() + 1e-9;
        const auto &poles = built.sections[j];
        g2::Vec position, d1, d2;
        g2::evaluate(poles, 0.5, position, d1, d2);
        const gp_Pnt mid(position[0], position[1], position[2]);
        GeomAPI_ProjectPointOnSurf project(mid, circular);
        if (project.NbPoints() == 0 || project.LowerDistance() > 0.5 * radius) {
            throw user_error(kStripMessage);
        }
        double pu = 0, pv = 0;
        project.LowerDistanceParameters(pu, pv);
        if (inside && ((!circular->IsUPeriodic() && (pu < umin - margin_u || pu > umax + margin_u)) ||
            (!circular->IsVPeriodic() && (pv < vmin - margin_v || pv > vmax + margin_v)))) {
            throw user_error(kStripMessage);
        }
        const gp_Pnt q = project.NearestPoint();
        const NeighbourEnd &ea = built.first_ends[j], &eb = built.second_ends[j];
        if (inside && (j == 0 || j + 1 == built.sections.size())) {
            // An end section is the strip's end edge, so the chord must cross the springs squarely; a slanted
            // run-out (a blend ending on a face at an angle) isn't a cross-section and isn't supported.
            const gp_Vec chord(ea.p, eb.p);
            if (std::abs(chord.Dot(ea.tangent)) > 0.15 * chord.Magnitude() * ea.tangent.Magnitude()) {
                throw user_error(kStripMessage);
            }
        }
        const double sa = offset_from(a, ea, q) < 0 ? -1 : 1;
        const double sb = offset_from(b, eb, q) < 0 ? -1 : 1;
        const double tolerance = 0.01 * ea.p.Distance(eb.p);
        for (int k = 0; k <= 16; ++k) {
            g2::evaluate(poles, k / 16.0, position, d1, d2);
            const gp_Pnt p(position[0], position[1], position[2]);
            if (sa * offset_from(a, ea, p) < -tolerance || sb * offset_from(b, eb, p) < -tolerance) {
                throw user_error(kWeightMessage);
            }
        }
    }
}

} // namespace

void agree_chain_tangents(Run &r) {
    occt_g2_report *const report = r.report;
    const std::vector<TopoDS_Face> &strip_faces = r.strip_faces;
    std::vector<StripEdges> &strips = r.strips;
    std::vector<TopoDS_Edge> &kinked_joins = r.kinked_joins;
    // Tangent chains: where two strips of a chain meet, the springs on one face may kink (a drafted cone meeting a
    // plane): both strips take the bisector of the two springs' tangents there, so they share one section.
    {
        auto outward_tangent = [](const Spring &spring, int end, gp_Pnt &point) {
            BRepAdaptor_Curve curve(spring.edge);
            const double direction = spring.t_end > spring.t_start ? 1 : -1;
            const double t = end == 0 ? spring.t_start : spring.t_end;
            gp_Vec tangent;
            curve.D1(t, point, tangent);
            tangent.Normalize();
            return tangent * (end == 0 ? -direction : direction);
        };
        for (std::size_t s = 0; s < strips.size(); ++s) {
            if (strips[s].closed) {
                continue;
            }
            for (int end = 0; end < 2; ++end) {
                for (int i = 0; i < 2; ++i) {
                    Spring &mine = strips[s].spring[i];
                    gp_Pnt point;
                    const gp_Vec outward = outward_tangent(mine, end, point);
                    for (std::size_t t = 0; t < strips.size(); ++t) {
                        if (t == s || strips[t].closed) {
                            continue;
                        }
                        bool chained = false;
                        for (int c = 0; c < 2; ++c) {
                            chained = chained || strips[s].end_chain[c].IsSame(strip_faces[t]);
                        }
                        if (!chained) {
                            continue;
                        }
                        for (Spring &other : strips[t].spring) {
                            for (int other_end = 0; other_end < 2; ++other_end) {
                                gp_Pnt other_point;
                                const gp_Vec other_outward = outward_tangent(other, other_end, other_point);
                                if (other_point.Distance(point) > 1e-6 || outward.Dot(other_outward) > 0) {
                                    continue;
                                }
                                gp_Vec bisector = outward - other_outward;
                                if (bisector.Magnitude() < 1e-9) {
                                    continue;
                                }
                                bisector.Normalize();
                                const double kink = std::acos(std::clamp(-outward.Dot(other_outward), -1.0, 1.0)) * 180 / kPi;
                                if (kink > 0.01) {
                                    mine.kinked[end] = true;
                                    other.kinked[other_end] = true;
                                    // Every kink is a counted join: the join edge is the end that chains to the
                                    // other strip, else (never seen) the spring's own end.
                                    int join_end = end;
                                    for (int c = 0; c < 2; ++c) {
                                        if (strips[s].end_chain[c].IsSame(strip_faces[t])) {
                                            join_end = c;
                                        }
                                    }
                                    bool known = false;
                                    for (const TopoDS_Edge &join : kinked_joins) {
                                        known = known || join.IsSame(strips[s].ends[join_end]);
                                    }
                                    if (!known) {
                                        kinked_joins.push_back(strips[s].ends[join_end]);
                                    }
                                }
                                mine.has_tangent[end] = true;
                                mine.junction_tangent[end] = bisector;
                                other.has_tangent[other_end] = true;
                                other.junction_tangent[other_end] = bisector;
                            }
                        }
                    }
                }
            }
        }
    }
    report->g1_joins = static_cast<int>(kinked_joins.size());
}

void build_strips(Run &r) {
    occt_g2_report *const report = r.report;
    const double radius = r.radius;
    const double weight = r.weight;
    const std::vector<TopoDS_Face> &strip_faces = r.strip_faces;
    BRep_Builder &builder = r.builder;
    std::vector<StripEdges> &strips = r.strips;
    std::vector<StripState> &states = r.states;
    // Every strip is built first (so that two strips meeting at a mitre can be cut by each other), then the
    // mitres, then each strip's end edges and face.
    states.resize(strips.size());
    for (std::size_t s = 0; s < strips.size(); ++s) {
        const TopoDS_Face old_face = strip_faces[s];
        const Handle(Geom_Surface) circular = BRep_Tool::Surface(old_face);
        StripEdges &edges = strips[s];
        StripState &state = states[s];
        Slant(&slants)[2] = state.slants;
        plan_slants(edges, slants);
        BuiltStrip &built = state.built;
        bool &swapped = state.swapped;
        // Sections start at 9 (and one at each break), skinned with a cubic; if that misses the (halved) tolerances
        // the skin is a quintic from then on, and sections are added where the candidate's seams still miss them: a
        // span that fails gets its middle (a closed strip doubles all of them). At 129 the blend fails.
        std::vector<double> fractions(kFirstSections);
        for (int j = 0; j < kFirstSections; ++j) {
            fractions[j] = static_cast<double>(j) / (kFirstSections - 1);
        }
        // The breaks: where either spring's curve has a knot its derivatives jump at (none on a closed strip), each
        // a section from the start. Two within the margin of each other are one.
        std::vector<double> breaks;
        if (!edges.closed) {
            for (const Spring &spring : edges.spring) {
                const std::vector<double> own = spring_breaks(spring);
                breaks.insert(breaks.end(), own.begin(), own.end());
            }
            std::sort(breaks.begin(), breaks.end());
            std::vector<double> merged;
            for (const double f : breaks) {
                if (merged.empty() || f > merged.back() + kBreakMargin) {
                    merged.push_back(f);
                }
            }
            // A spring of more pieces than the cap allows sections is skinned without breaks, as before them.
            breaks = static_cast<int>(merged.size()) + kFirstSections <= kMaxSections ? merged : std::vector<double>{};
            for (const double f : breaks) {
                const auto close_to_section = [&](double g) { return std::abs(g - f) < kBreakMargin; };
                if (std::none_of(fractions.begin(), fractions.end(), close_to_section)) {
                    fractions.insert(std::upper_bound(fractions.begin(), fractions.end(), f), f);
                } else {
                    // A section already there moves onto the break.
                    for (double &g : fractions) {
                        if (std::abs(g - f) < kBreakMargin) {
                            g = f;
                        }
                    }
                }
            }
        }
        int degree = kFirstDegree;
        for (;;) {
            swapped = false;
            for (int attempt = 0; attempt < 2; ++attempt) {
                built = build_strip(edges.spring[swapped ? 1 : 0], edges.spring[swapped ? 0 : 1], weight, fractions, breaks,
                                    degree, edges.closed);
                // The raw normal must agree with the old surface's so the face keeps its orientation.
                gp_Pnt mid;
                gp_Vec du, dv;
                built.surface->D1(0.5, 0.5, mid, du, dv);
                GeomAPI_ProjectPointOnSurf project(mid, circular);
                double u = 0, v = 0;
                project.LowerDistanceParameters(u, v);
                gp_Pnt q;
                gp_Vec ou, ov;
                circular->D1(u, v, q, ou, ov);
                if (du.Crossed(dv).Dot(ou.Crossed(ov)) > 0) {
                    break;
                }
                swapped = !swapped;
            }
            validate_sections(built, old_face, edges.spring[swapped ? 1 : 0], edges.spring[swapped ? 0 : 1], radius);
            const bool reversed = old_face.Orientation() == TopAbs_REVERSED;
            std::vector<double> first_spans, second_spans;
            const occt_g2_seam first_seam = candidate_seam(
                built.surface, reversed, edges.spring[swapped ? 1 : 0], built.pcurve[0], fractions, first_spans);
            const occt_g2_seam second_seam = candidate_seam(
                built.surface, reversed, edges.spring[swapped ? 0 : 1], built.pcurve[1], fractions, second_spans);
            const bool passes = within_tolerance(first_seam) && within_tolerance(second_seam);
            if (passes) {
                // The springs keep their own curves: their tolerance covers what the strip's boundary misses.
                state.spring_gap[0] = first_seam.position;
                state.spring_gap[1] = second_seam.position;
                break;
            }
            if (degree < kSkinDegree) {
                degree = kSkinDegree; // the same sections again, skinned with the quintic
                continue;
            }
            if (static_cast<int>(fractions.size()) >= kMaxSections) {
                throw user_error(kStripMessage);
            }
            // A failing span gets its middle; a span too narrow to halve again means the error is not one more
            // sections can remove.
            std::vector<bool> split(fractions.size() - 1, edges.closed);
            for (std::size_t j = 0; j + 1 < fractions.size(); ++j) {
                if (first_spans[j] > 1 || second_spans[j] > 1) {
                    if (fractions[j + 1] - fractions[j] < 1e-5) {
                        throw user_error(kStripMessage);
                    }
                    split[j] = true;
                }
            }
            std::vector<double> refined;
            for (std::size_t j = 0; j < fractions.size(); ++j) {
                refined.push_back(fractions[j]);
                if (j + 1 < fractions.size() && split[j]) {
                    refined.push_back(0.5 * (fractions[j] + fractions[j + 1]));
                }
            }
            if (refined.size() == fractions.size()) {
                // Nothing in a span failed (the gap is at a section): halve everything.
                refined.clear();
                for (std::size_t j = 0; j < fractions.size(); ++j) {
                    refined.push_back(fractions[j]);
                    if (j + 1 < fractions.size()) {
                        refined.push_back(0.5 * (fractions[j] + fractions[j + 1]));
                    }
                }
            }
            if (static_cast<int>(refined.size()) > kMaxSections) {
                throw user_error(kStripMessage);
            }
            fractions = refined;
        }
        const int sections = static_cast<int>(fractions.size());
        report->sections = std::max(report->sections, sections);
        if (s < 32) {
            report->strip_sections[s] = sections;
        }
        // Spring edges: the pcurve on the new surface.
        const Handle(Geom_Surface) surface = built.surface;
        for (int side = 0; side < 2; ++side) {
            const Spring &spring = edges.spring[(side == 0) != swapped ? 0 : 1];
            builder.UpdateEdge(spring.edge, built.pcurve[side], surface, TopLoc_Location(),
                               std::max(kEdgeTolerance, 1.5 * state.spring_gap[side]));
            double own_first = 0, own_last = 0;
            BRep_Tool::Range(spring.edge, own_first, own_last);
            builder.Range(spring.edge, surface, TopLoc_Location(), own_first, own_last);
        }

    }
}

} // namespace cocct::g2_blend
