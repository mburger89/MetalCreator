// The Gordon network surface (NURBS spec, NS-2 Task 2): one B-spline face through a grid of curves.
//
// The u curves and the v curves are found in order and direction (R4), trimmed to the window the border curves cut, refitted
// so each crossing lands on a common parameter, made compatible, and then three surfaces are built over them: S_u skins the
// u curves, S_v skins the v curves and T interpolates the crossing points. The Gordon surface is S_u + S_v - T, pole by pole.
// Everything is non-rational; a rational input curve is refused.

#include "cocct_sheet.hpp"

#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepExtrema_DistShapeShape.hxx>
#include <BRepBuilderAPI_MakeVertex.hxx>
#include <BRepTools_WireExplorer.hxx>
#include <BRep_Tool.hxx>
#include <BSplCLib.hxx>
#include <GeomAPI_ExtremaCurveCurve.hxx>
#include <GeomAPI_PointsToBSpline.hxx>
#include <GeomAPI_ProjectPointOnCurve.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <GeomConvert.hxx>
#include <GeomConvert_CompCurveToBSplineCurve.hxx>
#include <Geom2d_Curve.hxx>
#include <Geom_BSplineCurve.hxx>
#include <Geom_BSplineSurface.hxx>
#include <Geom_Curve.hxx>
#include <Geom_TrimmedCurve.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColgp_Array1OfPnt.hxx>
#include <TColgp_Array2OfPnt.hxx>
#include <TopLoc_Location.hxx>
#include <gp_Pnt.hxx>
#include <gp_Pnt2d.hxx>

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <memory>
#include <numeric>
#include <string>
#include <vector>

using namespace cocct;

/// A flag a caller on another thread sets to stop a long build; polled between the build's steps.
struct occt_cancel {
    std::atomic<int> flag{0};
};

namespace {

constexpr const char *kCancelled = "The operation was cancelled.";
constexpr double kMaximumPoles = 100000;

void poll(const occt_cancel *cancel) {
    if (cancel && cancel->flag.load() != 0) {
        throw user_error(kCancelled);
    }
}

using BCurve = Handle(Geom_BSplineCurve);
using BSurface = Handle(Geom_BSplineSurface);
using Row = std::vector<double>;

constexpr double kKnotEpsilon = 1e-9;

/// A number inside a message, marked so the Swift side can write it in the message locale.
std::string number(double value) {
    char text[48];
    std::snprintf(text, sizeof text, "%.9g", value);
    return std::string(1, '\x01') + text + std::string(1, '\x02');
}

std::string curve_name(char axis, int index) { return std::string(1, axis) + " curve " + std::to_string(index + 1); }

/// The curve as one clamped B-spline (its wire's edges in wire order), parameter range [0, 1].
void normalise(BCurve &curve) {
    const double first = curve->FirstParameter();
    const double last = curve->LastParameter();
    if (!(last - first > 1e-12)) {
        throw user_error("A network curve has no length.");
    }
    TColStd_Array1OfReal knots(1, curve->NbKnots());
    for (int i = 1; i <= curve->NbKnots(); ++i) {
        knots(i) = (curve->Knot(i) - first) / (last - first);
    }
    knots(1) = 0;
    knots(curve->NbKnots()) = 1;
    curve->SetKnots(knots);
}

BCurve spline_of(const occt_shape *curve) {
    if (!curve || curve->shape.IsNull() || curve->shape.ShapeType() != TopAbs_WIRE) {
        throw user_error("This curve can't be used.");
    }
    BCurve joined;
    for (BRepTools_WireExplorer explorer(TopoDS::Wire(curve->shape)); explorer.More(); explorer.Next()) {
        const TopoDS_Edge edge = explorer.Current();
        if (BRep_Tool::Degenerated(edge)) {
            continue;
        }
        TopLoc_Location location;
        double first = 0;
        double last = 0;
        const Handle(Geom_Curve) base = BRep_Tool::Curve(edge, location, first, last);
        if (base.IsNull()) {
            throw user_error("This curve can't be used.");
        }
        Handle(Geom_TrimmedCurve) trimmed = new Geom_TrimmedCurve(Handle(Geom_Curve)::DownCast(base->Copy()), first, last);
        trimmed->Transform(location.Transformation());
        if (edge.Orientation() == TopAbs_REVERSED) {
            trimmed->Reverse();
        }
        BCurve piece = GeomConvert::CurveToBSplineCurve(trimmed);
        if (joined.IsNull()) {
            joined = piece;
        } else {
            GeomConvert_CompCurveToBSplineCurve compose(joined);
            if (!compose.Add(piece, 1e-4, Standard_True)) {
                throw user_error("This curve can't be used.");
            }
            joined = compose.BSplineCurve();
        }
    }
    if (joined.IsNull()) {
        throw user_error("This curve can't be used.");
    }
    if (joined->IsRational()) {
        for (int i = 1; i <= joined->NbPoles(); ++i) {
            if (std::abs(joined->Weight(i) - 1.0) > 1e-9) {
                throw user_error("Network curves can't be rational.");
            }
        }
    }
    normalise(joined);
    return joined;
}

/// Where one u curve and one v curve meet: the parameters of the nearest approach, how far apart the curves are there and
/// how many separate places they come within the tolerance.
struct crossing {
    double pu = 0;
    double pv = 0;
    double distance = 1e300;
    int places = 0;
};

struct candidate {
    double pu;
    double pv;
    double distance;
    gp_Pnt a;
};

double distance_to_curve(const gp_Pnt &p, const BCurve &curve) {
    double nearest = std::min(p.Distance(curve->Value(0)), p.Distance(curve->Value(1)));
    try {
        GeomAPI_ProjectPointOnCurve projection(p, curve);
        if (projection.NbPoints() > 0) {
            nearest = std::min(nearest, projection.LowerDistance());
        }
    } catch (const Standard_Failure &) {
        return nearest;
    }
    return nearest;
}

crossing cross(const BCurve &cu, const BCurve &cv, double tolerance) {
    std::vector<candidate> found;
    const auto add = [&](double pu, double pv) {
        pu = std::min(1.0, std::max(0.0, pu));
        pv = std::min(1.0, std::max(0.0, pv));
        const gp_Pnt a = cu->Value(pu);
        found.push_back(candidate{pu, pv, a.Distance(cv->Value(pv)), a});
    };
    try {
        GeomAPI_ExtremaCurveCurve extrema(cu, cv);
        if (!extrema.IsParallel()) {
            for (int i = 1; i <= extrema.NbExtrema(); ++i) {
                double pu = 0;
                double pv = 0;
                extrema.Parameters(i, pu, pv);
                add(pu, pv);
            }
        }
    } catch (const Standard_Failure &) {
        // Extrema can fail on awkward curves; the end points below still give an answer.
    }
    for (int end = 0; end < 2; ++end) {
        for (int other = 0; other < 2; ++other) {
            add(end, other);
        }
        try {
            GeomAPI_ProjectPointOnCurve onv(cu->Value(end), cv);
            if (onv.NbPoints() > 0) {
                add(end, onv.LowerDistanceParameter());
            }
            GeomAPI_ProjectPointOnCurve onu(cv->Value(end), cu);
            if (onu.NbPoints() > 0) {
                add(onu.LowerDistanceParameter(), end);
            }
        } catch (const Standard_Failure &) {
            continue;
        }
    }
    std::sort(found.begin(), found.end(), [](const candidate &x, const candidate &y) { return x.distance < y.distance; });
    crossing out;
    out.pu = found.front().pu;
    out.pv = found.front().pv;
    out.distance = found.front().distance;
    // Candidates joined by a run of the u curve that stays within the tolerance of the v curve are one place: a shallow
    // crossing keeps the curves that close over a long stretch.
    std::vector<candidate> hits;
    for (const candidate &item : found) {
        if (item.distance <= tolerance) {
            hits.push_back(item);
        }
    }
    std::sort(hits.begin(), hits.end(), [](const candidate &x, const candidate &y) { return x.pu < y.pu; });
    int places = 0;
    for (std::size_t i = 0; i < hits.size(); ++i) {
        bool joined = i > 0;
        for (int s = 1; joined && s < 16; ++s) {
            const double at = hits[i - 1].pu + (hits[i].pu - hits[i - 1].pu) * s / 16.0;
            joined = distance_to_curve(cu->Value(at), cv) <= tolerance;
        }
        if (!joined) {
            ++places;
        }
    }
    out.places = places;
    return out;
}

// MARK: Interpolation

struct interpolation {
    int degree = 1;
    std::vector<double> flat;           // the full knot vector
    std::vector<Row> poles;             // one row of `dimension` numbers per pole
};

/// The knot vector global interpolation at `params` uses (degree min(3, count - 1), knots by averaging).
std::vector<double> averaged_flat(const std::vector<double> &params) {
    const int n = static_cast<int>(params.size());
    const int q = std::min(3, n - 1);
    std::vector<double> flat(static_cast<std::size_t>(n + q + 1), 0.0);
    for (int i = 0; i <= q; ++i) {
        flat[static_cast<std::size_t>(i)] = params.front();
        flat[static_cast<std::size_t>(n + i)] = params.back();
    }
    for (int j = 1; j <= n - q - 1; ++j) {
        double sum = 0;
        for (int i = j; i < j + q; ++i) {
            sum += params[static_cast<std::size_t>(i)];
        }
        flat[static_cast<std::size_t>(j + q)] = sum / q;
    }
    return flat;
}

/// Global interpolation of `data` (one row per parameter) at `params` (strictly increasing, first 0 and last 1), of degree
/// min(3, count - 1): linear for two, quadratic for three, cubic from four (ruling R-A). Knots by averaging.
interpolation interpolate(const std::vector<double> &params, const std::vector<Row> &data) {
    const int n = static_cast<int>(params.size());
    const int dimension = static_cast<int>(data.front().size());
    const int q = std::min(3, n - 1);
    interpolation out;
    out.degree = q;
    out.flat = averaged_flat(params);
    TColStd_Array1OfReal flat(1, n + q + 1);
    for (int i = 0; i < n + q + 1; ++i) {
        flat(i + 1) = out.flat[static_cast<std::size_t>(i)];
    }
    TColStd_Array1OfReal at(1, n);
    TColStd_Array1OfInteger contact(1, n);
    std::vector<double> buffer(static_cast<std::size_t>(n * dimension));
    for (int i = 0; i < n; ++i) {
        at(i + 1) = params[static_cast<std::size_t>(i)];
        contact(i + 1) = 0;
        for (int d = 0; d < dimension; ++d) {
            buffer[static_cast<std::size_t>(i * dimension + d)] = data[static_cast<std::size_t>(i)][static_cast<std::size_t>(d)];
        }
    }
    Standard_Integer problem = 0;
    BSplCLib::Interpolate(q, flat, at, contact, dimension, buffer[0], problem);
    if (problem != 0) {
        throw user_error("The network curves can't be interpolated.");
    }
    out.poles.assign(static_cast<std::size_t>(n), Row(static_cast<std::size_t>(dimension)));
    for (int i = 0; i < n; ++i) {
        for (int d = 0; d < dimension; ++d) {
            out.poles[static_cast<std::size_t>(i)][static_cast<std::size_t>(d)] = buffer[static_cast<std::size_t>(i * dimension + d)];
        }
    }
    return out;
}

/// The distinct knots of a flat knot vector and their multiplicities.
void distinct(const std::vector<double> &flat, std::vector<double> &knots, std::vector<int> &mults) {
    knots.clear();
    mults.clear();
    for (double value : flat) {
        if (!knots.empty() && value == knots.back()) {
            ++mults.back();
        } else {
            knots.push_back(value);
            mults.push_back(1);
        }
    }
}

TColStd_Array1OfReal reals(const std::vector<double> &values) {
    TColStd_Array1OfReal out(1, static_cast<int>(values.size()));
    for (std::size_t i = 0; i < values.size(); ++i) {
        out(static_cast<int>(i) + 1) = values[i];
    }
    return out;
}

TColStd_Array1OfInteger integers(const std::vector<int> &values) {
    TColStd_Array1OfInteger out(1, static_cast<int>(values.size()));
    for (std::size_t i = 0; i < values.size(); ++i) {
        out(static_cast<int>(i) + 1) = values[i];
    }
    return out;
}

// MARK: Compatibility

/// Sorts (knot, multiplicity) pairs and merges knots within `kKnotEpsilon`, keeping the larger multiplicity.
void merge_knots(std::vector<std::pair<double, int>> &items) {
    std::sort(items.begin(), items.end());
    std::vector<std::pair<double, int>> merged;
    for (const auto &item : items) {
        if (!merged.empty() && std::abs(merged.back().first - item.first) < kKnotEpsilon) {
            merged.back().second = std::max(merged.back().second, item.second);
        } else {
            merged.push_back(item);
        }
    }
    items = std::move(merged);
}

/// Appends a curve's or surface's knots with multiplicities raised by `raise` (a degree increase).
void append_knots(std::vector<std::pair<double, int>> &into, const std::vector<double> &flat, int raise) {
    std::vector<double> knots;
    std::vector<int> mults;
    distinct(flat, knots, mults);
    for (std::size_t i = 0; i < knots.size(); ++i) {
        into.emplace_back(knots[i], mults[i] + raise);
    }
}

/// Control points along one direction once `sources` (flat knot vectors with their degrees) are made compatible.
double compatible_poles(const std::vector<std::pair<std::vector<double>, int>> &sources) {
    int degree = 0;
    for (const auto &source : sources) {
        degree = std::max(degree, source.second);
    }
    std::vector<std::pair<double, int>> items;
    for (const auto &source : sources) {
        append_knots(items, source.first, degree - source.second);
    }
    merge_knots(items);
    double total = 0;
    for (const auto &item : items) {
        total += item.second;
    }
    return total - degree - 1;
}

std::pair<TColStd_Array1OfReal, TColStd_Array1OfInteger> split(const std::vector<std::pair<double, int>> &merged) {
    TColStd_Array1OfReal knots(1, static_cast<int>(merged.size()));
    TColStd_Array1OfInteger mults(1, static_cast<int>(merged.size()));
    for (std::size_t i = 0; i < merged.size(); ++i) {
        knots(static_cast<int>(i) + 1) = merged[i].first;
        mults(static_cast<int>(i) + 1) = merged[i].second;
    }
    return {knots, mults};
}

bool same_knots(const TColStd_Array1OfReal &a, const TColStd_Array1OfInteger &am, const TColStd_Array1OfReal &b,
                const TColStd_Array1OfInteger &bm) {
    if (a.Length() != b.Length()) {
        return false;
    }
    for (int i = a.Lower(); i <= a.Upper(); ++i) {
        const int j = b.Lower() + (i - a.Lower());
        if (std::abs(a(i) - b(j)) > kKnotEpsilon || am(i) != bm(j)) {
            return false;
        }
    }
    return true;
}

/// Raises every curve to the highest degree among them and inserts every knot of every curve into each.
void make_compatible(std::vector<BCurve> &curves, const occt_cancel *cancel) {
    int degree = 0;
    for (const BCurve &curve : curves) {
        degree = std::max(degree, curve->Degree());
    }
    std::vector<std::pair<double, int>> merged;
    for (BCurve &curve : curves) {
        poll(cancel);
        if (curve->Degree() < degree) {
            curve->IncreaseDegree(degree);
        }
        for (int i = 1; i <= curve->NbKnots(); ++i) {
            merged.emplace_back(curve->Knot(i), curve->Multiplicity(i));
        }
    }
    merge_knots(merged);
    const auto inserts = split(merged);
    for (BCurve &curve : curves) {
        poll(cancel);
        curve->InsertKnots(inserts.first, inserts.second, kKnotEpsilon, Standard_False);
    }
    for (const BCurve &curve : curves) {
        if (curve->Degree() != curves.front()->Degree() || curve->NbPoles() != curves.front()->NbPoles() ||
            !same_knots(curve->Knots(), curve->Multiplicities(), curves.front()->Knots(), curves.front()->Multiplicities())) {
            throw user_error("The network curves can't be made compatible.");
        }
    }
}

/// The same for three surfaces in both directions: afterwards they share degrees, knots and multiplicities.
void make_compatible(std::vector<BSurface> &surfaces, const occt_cancel *cancel) {
    int u_degree = 0;
    int v_degree = 0;
    for (const BSurface &surface : surfaces) {
        u_degree = std::max(u_degree, surface->UDegree());
        v_degree = std::max(v_degree, surface->VDegree());
    }
    std::vector<std::pair<double, int>> u_merged;
    std::vector<std::pair<double, int>> v_merged;
    for (BSurface &surface : surfaces) {
        poll(cancel);
        surface->IncreaseDegree(u_degree, v_degree);
        for (int i = 1; i <= surface->NbUKnots(); ++i) {
            u_merged.emplace_back(surface->UKnot(i), surface->UMultiplicity(i));
        }
        for (int i = 1; i <= surface->NbVKnots(); ++i) {
            v_merged.emplace_back(surface->VKnot(i), surface->VMultiplicity(i));
        }
    }
    merge_knots(u_merged);
    merge_knots(v_merged);
    const auto u_inserts = split(u_merged);
    const auto v_inserts = split(v_merged);
    for (BSurface &surface : surfaces) {
        poll(cancel);
        surface->InsertUKnots(u_inserts.first, u_inserts.second, kKnotEpsilon, Standard_False);
        surface->InsertVKnots(v_inserts.first, v_inserts.second, kKnotEpsilon, Standard_False);
    }
    const BSurface &base = surfaces.front();
    for (const BSurface &surface : surfaces) {
        if (surface->UDegree() != base->UDegree() || surface->VDegree() != base->VDegree() ||
            surface->NbUPoles() != base->NbUPoles() || surface->NbVPoles() != base->NbVPoles() ||
            !same_knots(surface->UKnots(), surface->UMultiplicities(), base->UKnots(), base->UMultiplicities()) ||
            !same_knots(surface->VKnots(), surface->VMultiplicities(), base->VKnots(), base->VMultiplicities())) {
            throw user_error("The network surfaces can't be made compatible.");
        }
    }
}

// MARK: Surfaces

BSurface make_surface(const std::vector<std::vector<gp_Pnt>> &grid, const std::vector<double> &u_flat,
                      const std::vector<double> &v_flat, int u_degree, int v_degree) {
    TColgp_Array2OfPnt poles(1, static_cast<int>(grid.size()), 1, static_cast<int>(grid.front().size()));
    for (std::size_t i = 0; i < grid.size(); ++i) {
        for (std::size_t j = 0; j < grid[i].size(); ++j) {
            poles(static_cast<int>(i) + 1, static_cast<int>(j) + 1) = grid[i][j];
        }
    }
    std::vector<double> uk;
    std::vector<double> vk;
    std::vector<int> um;
    std::vector<int> vm;
    distinct(u_flat, uk, um);
    distinct(v_flat, vk, vm);
    return new Geom_BSplineSurface(poles, reals(uk), reals(vk), integers(um), integers(vm), u_degree, v_degree);
}

std::vector<double> flat_of(const BCurve &curve) {
    std::vector<double> flat;
    for (int i = 1; i <= curve->NbKnots(); ++i) {
        for (int m = 0; m < curve->Multiplicity(i); ++m) {
            flat.push_back(curve->Knot(i));
        }
    }
    return flat;
}

/// The surface through compatible `curves` at `params`: the curves run along u when `along_u`, else along v, and are
/// interpolated across the other direction.
BSurface skin(const std::vector<BCurve> &curves, const std::vector<double> &params, bool along_u) {
    const int count = static_cast<int>(curves.size());
    const int pole_count = curves.front()->NbPoles();
    std::vector<Row> data;
    for (const BCurve &curve : curves) {
        Row row;
        for (int k = 1; k <= pole_count; ++k) {
            const gp_Pnt p = curve->Pole(k);
            row.insert(row.end(), {p.X(), p.Y(), p.Z()});
        }
        data.push_back(row);
    }
    const interpolation across = interpolate(params, data);
    std::vector<std::vector<gp_Pnt>> grid;
    const auto point = [&](int c, int k) {
        const Row &row = across.poles[static_cast<std::size_t>(c)];
        return gp_Pnt(row[static_cast<std::size_t>(3 * k)], row[static_cast<std::size_t>(3 * k + 1)],
                      row[static_cast<std::size_t>(3 * k + 2)]);
    };
    if (along_u) {
        for (int k = 0; k < pole_count; ++k) {
            std::vector<gp_Pnt> line;
            for (int c = 0; c < count; ++c) {
                line.push_back(point(c, k));
            }
            grid.push_back(line);
        }
        return make_surface(grid, flat_of(curves.front()), across.flat, curves.front()->Degree(), across.degree);
    }
    for (int c = 0; c < count; ++c) {
        std::vector<gp_Pnt> line;
        for (int k = 0; k < pole_count; ++k) {
            line.push_back(point(c, k));
        }
        grid.push_back(line);
    }
    return make_surface(grid, across.flat, flat_of(curves.front()), across.degree, curves.front()->Degree());
}

/// The tensor interpolation of `points[i][j]` (v index i, u index j) at u = `u_params[j]`, v = `v_params[i]`.
BSurface tensor(const std::vector<std::vector<gp_Pnt>> &points, const std::vector<double> &u_params,
                const std::vector<double> &v_params) {
    const std::size_t rows = points.size();
    std::vector<interpolation> first;
    for (std::size_t i = 0; i < rows; ++i) {
        std::vector<Row> data;
        for (const gp_Pnt &p : points[i]) {
            data.push_back(Row{p.X(), p.Y(), p.Z()});
        }
        first.push_back(interpolate(u_params, data));
    }
    const std::size_t columns = first.front().poles.size();
    std::vector<Row> second_data;
    for (std::size_t i = 0; i < rows; ++i) {
        Row row;
        for (std::size_t c = 0; c < columns; ++c) {
            row.insert(row.end(), first[i].poles[c].begin(), first[i].poles[c].end());
        }
        second_data.push_back(row);
    }
    const interpolation second = interpolate(v_params, second_data);
    std::vector<std::vector<gp_Pnt>> grid(columns);
    for (std::size_t c = 0; c < columns; ++c) {
        for (std::size_t d = 0; d < second.poles.size(); ++d) {
            const Row &row = second.poles[d];
            grid[c].push_back(gp_Pnt(row[3 * c], row[3 * c + 1], row[3 * c + 2]));
        }
    }
    return make_surface(grid, first.front().flat, second.flat, first.front().degree, second.degree);
}

// MARK: Reparametrisation

/// A monotone cubic Hermite map (Fritsch-Carlson) through the points (own[j], target[j]): smooth, so the curve sampled
/// through it can be refitted by a low-degree spline, and strictly increasing, so no parameter folds back.
class monotone_map {
public:
    monotone_map(const Row &x, const Row &y) : x_(x), y_(y), m_(x.size(), 0.0) {
        const std::size_t n = x.size();
        Row d(n - 1);
        for (std::size_t k = 0; k + 1 < n; ++k) {
            d[k] = (y[k + 1] - y[k]) / (x[k + 1] - x[k]);
        }
        if (n == 2) {
            m_[0] = m_[1] = d[0];
            return;
        }
        for (std::size_t k = 1; k + 1 < n; ++k) {
            const double h0 = x[k] - x[k - 1];
            const double h1 = x[k + 1] - x[k];
            const double w1 = 2 * h1 + h0;
            const double w2 = h1 + 2 * h0;
            m_[k] = (w1 + w2) / (w1 / d[k - 1] + w2 / d[k]);
        }
        m_[0] = end_slope(x[1] - x[0], x[2] - x[1], d[0], d[1]);
        m_[n - 1] = end_slope(x[n - 1] - x[n - 2], x[n - 2] - x[n - 3], d[n - 2], d[n - 3]);
    }

    double operator()(double t) const {
        std::size_t k = 0;
        while (k + 2 < x_.size() && t > x_[k + 1]) {
            ++k;
        }
        const double h = x_[k + 1] - x_[k];
        const double u = (t - x_[k]) / h;
        const double u2 = u * u;
        const double u3 = u2 * u;
        return (2 * u3 - 3 * u2 + 1) * y_[k] + (u3 - 2 * u2 + u) * h * m_[k] + (-2 * u3 + 3 * u2) * y_[k + 1] +
               (u3 - u2) * h * m_[k + 1];
    }

private:
    static double end_slope(double h0, double h1, double d0, double d1) {
        double m = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1);
        if (m * d0 <= 0) {
            m = 0;
        } else if (d0 * d1 <= 0 && std::abs(m) > 3 * std::abs(d0)) {
            m = 3 * d0;
        }
        return m;
    }

    Row x_;
    Row y_;
    Row m_;
};

/// `curve` refitted so its crossings, now at `own`, land on `target`. A curve already there is returned as it is.
/// An empty result means the refit left the curve by more than `limit`.
BCurve reparametrise(const BCurve &curve, const Row &own, const Row &target, double fit_tolerance, double limit) {
    bool identity = true;
    for (std::size_t j = 0; j < own.size(); ++j) {
        identity = identity && std::abs(own[j] - target[j]) < 1e-9;
    }
    if (identity) {
        return curve;
    }
    constexpr int kPerSpan = 20;
    const monotone_map map(own, target);
    std::vector<gp_Pnt> points;
    std::vector<double> params;
    for (std::size_t j = 0; j + 1 < own.size(); ++j) {
        for (int k = 0; k < kPerSpan; ++k) {
            const double at = own[j] + (own[j + 1] - own[j]) * static_cast<double>(k) / kPerSpan;
            points.push_back(curve->Value(at));
            params.push_back(k == 0 ? target[j] : map(at));
        }
    }
    points.push_back(curve->Value(1.0));
    params.push_back(1.0);
    TColgp_Array1OfPnt array(1, static_cast<int>(points.size()));
    TColStd_Array1OfReal at(1, static_cast<int>(points.size()));
    for (std::size_t i = 0; i < points.size(); ++i) {
        array(static_cast<int>(i) + 1) = points[i];
        at(static_cast<int>(i) + 1) = params[i];
    }
    GeomAPI_PointsToBSpline fit(array, at, 3, 5, GeomAbs_C2, fit_tolerance);
    if (!fit.IsDone()) {
        return BCurve();
    }
    BCurve refit = fit.Curve();
    if (refit.IsNull() || refit->IsRational()) {
        return BCurve();
    }
    for (int i = 0; i <= 100; ++i) {
        const gp_Pnt p = refit->Value(refit->FirstParameter() + (refit->LastParameter() - refit->FirstParameter()) * i / 100.0);
        double nearest = std::min(p.Distance(curve->Value(0)), p.Distance(curve->Value(1)));
        GeomAPI_ProjectPointOnCurve projection(p, curve);
        if (projection.NbPoints() > 0) {
            nearest = std::min(nearest, projection.LowerDistance());
        }
        if (nearest > limit) {
            return BCurve();
        }
    }
    return refit;
}

/// The distance from `p` to `surface`, the nearest approach over the whole face (its boundary included).
double distance_to(const gp_Pnt &p, const Handle(Geom_BSplineSurface) &surface, const TopoDS_Face &face) {
    try {
        GeomAPI_ProjectPointOnSurf projection(p, surface);
        if (projection.NbPoints() > 0) {
            return projection.LowerDistance();
        }
    } catch (const Standard_Failure &) {
        // The face-based measurement below covers it.
    }
    BRepExtrema_DistShapeShape measure(BRepBuilderAPI_MakeVertex(p).Vertex(), face);
    return measure.IsDone() ? measure.Value() : 1e300;
}

Row column_of(const std::vector<Row> &matrix, std::size_t j) {
    Row out;
    for (const Row &row : matrix) {
        out.push_back(row[j]);
    }
    return out;
}

double mean(const Row &values) { return std::accumulate(values.begin(), values.end(), 0.0) / static_cast<double>(values.size()); }

bool increasing(const Row &values) {
    for (std::size_t i = 0; i + 1 < values.size(); ++i) {
        if (!(values[i + 1] - values[i] > 1e-9)) {
            return false;
        }
    }
    return true;
}

} // namespace

extern "C" {

occt_cancel *occt_cancel_new(void) { return new occt_cancel(); }

void occt_cancel_set(occt_cancel *cancel) {
    if (cancel) {
        cancel->flag.store(1);
    }
}

void occt_cancel_free(occt_cancel *cancel) { delete cancel; }

occt_shape *occt_network_surface(const occt_shape *const *u_curves, int u_count, const occt_shape *const *v_curves,
                                 int v_count, double tolerance, const occt_cancel *cancel, occt_history *history,
                                 occt_boundary_roles *roles, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        *history = occt_history{};
        *roles = occt_boundary_roles{};
        if (!u_curves || !v_curves || u_count < 2 || v_count < 2) {
            throw user_error("A network needs at least two curves in each direction.");
        }
        if (!std::isfinite(tolerance) || tolerance <= 0) {
            throw user_error("The tolerance must be greater than 0 mm.");
        }
        const std::size_t nu = static_cast<std::size_t>(u_count);
        const std::size_t nv = static_cast<std::size_t>(v_count);
        std::vector<BCurve> raw_u;
        std::vector<BCurve> raw_v;
        for (std::size_t i = 0; i < nu; ++i) {
            poll(cancel);
            raw_u.push_back(spline_of(u_curves[i]));
        }
        for (std::size_t j = 0; j < nv; ++j) {
            poll(cancel);
            raw_v.push_back(spline_of(v_curves[j]));
        }

        // Every pair's nearest approach, then the order: u curves by where they meet the first v curve, v curves by where
        // they meet the first u curve.
        std::vector<std::vector<crossing>> raw(nu, std::vector<crossing>(nv));
        for (std::size_t i = 0; i < nu; ++i) {
            for (std::size_t j = 0; j < nv; ++j) {
                poll(cancel);
                raw[i][j] = cross(raw_u[i], raw_v[j], tolerance);
            }
        }
        std::vector<std::size_t> u_order(nu);
        std::vector<std::size_t> v_order(nv);
        std::iota(u_order.begin(), u_order.end(), std::size_t{0});
        std::iota(v_order.begin(), v_order.end(), std::size_t{0});
        std::stable_sort(u_order.begin(), u_order.end(),
                         [&](std::size_t a, std::size_t b) { return raw[a][0].pv < raw[b][0].pv; });
        std::stable_sort(v_order.begin(), v_order.end(),
                         [&](std::size_t a, std::size_t b) { return raw[0][a].pu < raw[0][b].pu; });
        std::vector<BCurve> us;
        std::vector<BCurve> vs;
        std::vector<std::vector<crossing>> sorted(nu, std::vector<crossing>(nv));
        for (std::size_t i = 0; i < nu; ++i) {
            us.push_back(raw_u[u_order[i]]);
            for (std::size_t j = 0; j < nv; ++j) {
                sorted[i][j] = raw[u_order[i]][v_order[j]];
            }
        }
        for (std::size_t j = 0; j < nv; ++j) {
            vs.push_back(raw_v[v_order[j]]);
        }
        // Each curve runs the way its crossings increase.
        std::vector<bool> reverse_u(nu, false);
        std::vector<bool> reverse_v(nv, false);
        for (std::size_t i = 0; i < nu; ++i) {
            if (sorted[i].front().pu > sorted[i].back().pu) {
                reverse_u[i] = true;
                us[i]->Reverse();
            }
        }
        for (std::size_t j = 0; j < nv; ++j) {
            if (sorted.front()[j].pv > sorted.back()[j].pv) {
                reverse_v[j] = true;
                vs[j]->Reverse();
            }
        }
        // A[i][j]: where along u curve i it meets v curve j; B[i][j]: where along v curve j it meets u curve i.
        std::vector<Row> a(nu, Row(nv));
        std::vector<Row> b(nu, Row(nv));
        for (std::size_t i = 0; i < nu; ++i) {
            for (std::size_t j = 0; j < nv; ++j) {
                a[i][j] = reverse_u[i] ? 1.0 - sorted[i][j].pu : sorted[i][j].pu;
                b[i][j] = reverse_v[j] ? 1.0 - sorted[i][j].pv : sorted[i][j].pv;
            }
        }
        for (std::size_t i = 0; i < nu; ++i) {
            for (std::size_t j = 0; j < nv; ++j) {
                const crossing &c = sorted[i][j];
                const int ui = static_cast<int>(i);
                const int vj = static_cast<int>(j);
                if (c.places > 1) {
                    throw user_error(curve_name('u', ui) + " crosses " + curve_name('v', vj) + " more than once.");
                }
                if (c.places == 0) {
                    throw user_error(curve_name('u', ui) + " and " + curve_name('v', vj) + " miss each other by " +
                                     number(c.distance) + " mm.");
                }
            }
        }
        for (std::size_t i = 0; i < nu; ++i) {
            if (!increasing(a[i])) {
                throw user_error("The curves don't form a grid.");
            }
        }
        for (std::size_t j = 0; j < nv; ++j) {
            if (!increasing(column_of(b, j))) {
                throw user_error("The curves don't form a grid.");
            }
        }

        // Trim every curve to the window the border curves cut, and normalise.
        for (std::size_t i = 0; i < nu; ++i) {
            const double lo = a[i].front();
            const double hi = a[i].back();
            if (lo > 1e-9 || hi < 1.0 - 1e-9) {
                us[i]->Segment(lo, hi);
                normalise(us[i]);
            }
            for (double &value : a[i]) {
                value = (value - lo) / (hi - lo);
            }
            a[i].front() = 0;
            a[i].back() = 1;
        }
        for (std::size_t j = 0; j < nv; ++j) {
            const double lo = b.front()[j];
            const double hi = b.back()[j];
            if (lo > 1e-9 || hi < 1.0 - 1e-9) {
                vs[j]->Segment(lo, hi);
                normalise(vs[j]);
            }
            for (std::size_t i = 0; i < nu; ++i) {
                b[i][j] = (b[i][j] - lo) / (hi - lo);
            }
            b.front()[j] = 0;
            b.back()[j] = 1;
        }
        // The common parameters: the mean of where each curve meets the others.
        Row u_bar(nv);
        Row v_bar(nu);
        for (std::size_t j = 0; j < nv; ++j) {
            u_bar[j] = mean(column_of(a, j));
        }
        for (std::size_t i = 0; i < nu; ++i) {
            v_bar[i] = mean(b[i]);
        }
        u_bar.front() = 0;
        u_bar.back() = 1;
        v_bar.front() = 0;
        v_bar.back() = 1;

        // Refit so each crossing lands on its common parameter.
        std::vector<BCurve> fit_u;
        std::vector<BCurve> fit_v;
        for (std::size_t i = 0; i < nu; ++i) {
            poll(cancel);
            const BCurve fitted = reparametrise(us[i], a[i], u_bar, tolerance / 40, tolerance / 10);
            if (fitted.IsNull()) {
                throw user_error(curve_name('u', static_cast<int>(i)) + " can't be fitted to the network.");
            }
            fit_u.push_back(fitted);
        }
        for (std::size_t j = 0; j < nv; ++j) {
            poll(cancel);
            Row own;
            for (std::size_t i = 0; i < nu; ++i) {
                own.push_back(b[i][j]);
            }
            const BCurve fitted = reparametrise(vs[j], own, v_bar, tolerance / 40, tolerance / 10);
            if (fitted.IsNull()) {
                throw user_error(curve_name('v', static_cast<int>(j)) + " can't be fitted to the network.");
            }
            fit_v.push_back(fitted);
        }
        // The crossing points, where the two refitted curves meet (their middle when they miss by a little).
        std::vector<std::vector<gp_Pnt>> points(nu, std::vector<gp_Pnt>(nv));
        for (std::size_t i = 0; i < nu; ++i) {
            for (std::size_t j = 0; j < nv; ++j) {
                const gp_Pnt pu = fit_u[i]->Value(u_bar[j]);
                const gp_Pnt pv = fit_v[j]->Value(v_bar[i]);
                points[i][j] = gp_Pnt((pu.X() + pv.X()) / 2, (pu.Y() + pv.Y()) / 2, (pu.Z() + pv.Z()) / 2);
            }
        }
        // The surface's size is known from the knots before anything is built: refuse one that is too detailed.
        std::vector<std::pair<std::vector<double>, int>> u_sources{{averaged_flat(u_bar), std::min(3, v_count - 1)}};
        std::vector<std::pair<std::vector<double>, int>> v_sources{{averaged_flat(v_bar), std::min(3, u_count - 1)}};
        for (const BCurve &curve : fit_u) {
            u_sources.emplace_back(flat_of(curve), curve->Degree());
        }
        for (const BCurve &curve : fit_v) {
            v_sources.emplace_back(flat_of(curve), curve->Degree());
        }
        const double needed = compatible_poles(u_sources) * compatible_poles(v_sources);
        if (needed > kMaximumPoles) {
            throw user_error("The network is too detailed: it would need " + number(needed) +
                             " control points (the limit is 100,000).");
        }
        poll(cancel);
        make_compatible(fit_u, cancel);
        make_compatible(fit_v, cancel);
        poll(cancel);
        std::vector<BSurface> parts{skin(fit_u, v_bar, true), skin(fit_v, u_bar, false), tensor(points, u_bar, v_bar)};
        make_compatible(parts, cancel);
        poll(cancel);

        // P = P_u + P_v - P_T.
        const BSurface &base = parts[0];
        TColgp_Array2OfPnt poles(1, base->NbUPoles(), 1, base->NbVPoles());
        for (int i = 1; i <= base->NbUPoles(); ++i) {
            for (int j = 1; j <= base->NbVPoles(); ++j) {
                const gp_Pnt p = parts[0]->Pole(i, j);
                const gp_Pnt q = parts[1]->Pole(i, j);
                const gp_Pnt t = parts[2]->Pole(i, j);
                poles(i, j) = gp_Pnt(p.X() + q.X() - t.X(), p.Y() + q.Y() - t.Y(), p.Z() + q.Z() - t.Z());
            }
        }
        const BSurface surface = new Geom_BSplineSurface(poles, base->UKnots(), base->VKnots(), base->UMultiplicities(),
                                                        base->VMultiplicities(), base->UDegree(), base->VDegree());
        BRepBuilderAPI_MakeFace maker(surface, 1e-7);
        if (!maker.IsDone()) {
            throw user_error("The network surface couldn't be made.");
        }
        const TopoDS_Face face = maker.Face();

        // Every curve must lie on the surface.
        for (int family = 0; family < 2; ++family) {
            const std::vector<BCurve> &curves = family == 0 ? us : vs;
            for (std::size_t k = 0; k < curves.size(); ++k) {
                double worst = 0;
                poll(cancel);
                for (int s = 0; s < 50; ++s) {
                    const gp_Pnt p = curves[k]->Value(static_cast<double>(s) / 49.0);
                    worst = std::max(worst, distance_to(p, surface, face));
                }
                if (worst > tolerance) {
                    throw user_error("The surface misses " + curve_name(family == 0 ? 'u' : 'v', static_cast<int>(k)) + " by " +
                                     number(worst) + " mm.");
                }
            }
        }
        if (!BRepCheck_Analyzer(face).IsValid()) {
            throw user_error("The network surface couldn't be made.");
        }

        history_builder records(face);
        records.add(face, OCCT_FROM_SEGMENT, 0, 0);
        records.move_into(history);
        boundary_table table(face);
        const TopTools_IndexedMapOfShape edges = map_of(face, TopAbs_EDGE);
        for (int e = 1; e <= edges.Extent(); ++e) {
            const TopoDS_Edge edge = TopoDS::Edge(edges(e));
            if (BRep_Tool::Degenerated(edge)) {
                continue;
            }
            double first = 0;
            double last = 0;
            const Handle(Geom2d_Curve) on_face = BRep_Tool::CurveOnSurface(edge, face, first, last);
            if (on_face.IsNull()) {
                continue;
            }
            const gp_Pnt2d middle = on_face->Value((first + last) / 2);
            if (middle.Y() < 1e-6) {
                table.set(edge, kBoundaryStart);
            } else if (middle.Y() > 1.0 - 1e-6) {
                table.set(edge, kBoundaryEnd);
            } else if (middle.X() < 1e-6) {
                table.set(edge, kBoundaryRail, 0);
            } else if (middle.X() > 1.0 - 1e-6) {
                table.set(edge, kBoundaryRail, 1);
            }
        }
        table.move_into(roles);
        return new occt_shape{face};
    });
}

} // extern "C"
