// Control nets (NURBS spec, NS-3): the B-spline poles of a sheet's one face or a curve's one piece, and a face's surface kind.
#include "cocct_sheet.hpp"

#include <BRepAdaptor_Surface.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_NurbsConvert.hxx>
#include <BRep_Tool.hxx>
#include <GeomAbs_SurfaceType.hxx>
#include <GeomConvert.hxx>
#include <Geom_BSplineCurve.hxx>
#include <Geom_BSplineSurface.hxx>
#include <Geom_BezierSurface.hxx>
#include <Geom_Circle.hxx>
#include <Geom_Curve.hxx>
#include <Geom_Line.hxx>
#include <Geom_RectangularTrimmedSurface.hxx>
#include <Geom_Surface.hxx>
#include <Geom_TrimmedCurve.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColgp_Array2OfPnt.hxx>
#include <TopAbs_Orientation.hxx>
#include <TopoDS_Wire.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <new>
#include <vector>

using namespace cocct;

namespace {

// `occt_surface_net.kind` and `converted_from` codes; Swift's SurfaceKind in this order.
enum surface_code {
    kPlane = 0, kCylinder, kCone, kSphere, kTorus, kBSpline, kOther, kBezier, kRevolution, kExtrusion, kOffset
};

int code_of(GeomAbs_SurfaceType type) {
    switch (type) {
    case GeomAbs_Plane: return kPlane;
    case GeomAbs_Cylinder: return kCylinder;
    case GeomAbs_Cone: return kCone;
    case GeomAbs_Sphere: return kSphere;
    case GeomAbs_Torus: return kTorus;
    case GeomAbs_BezierSurface: return kBezier;
    case GeomAbs_BSplineSurface: return kBSpline;
    case GeomAbs_SurfaceOfRevolution: return kRevolution;
    case GeomAbs_SurfaceOfExtrusion: return kExtrusion;
    case GeomAbs_OffsetSurface: return kOffset;
    default: return kOther;
    }
}

constexpr int kMaxDegree = 11;

template <typename T>
T *zeroed(size_t count) {
    T *memory = static_cast<T *>(std::calloc(count > 0 ? count : 1, sizeof(T)));
    if (!memory) {
        throw std::bad_alloc();
    }
    return memory;
}

Handle(Geom_Surface) unwrapped(Handle(Geom_Surface) surface) {
    while (!surface.IsNull()) {
        Handle(Geom_RectangularTrimmedSurface) trimmed = Handle(Geom_RectangularTrimmedSurface)::DownCast(surface);
        if (trimmed.IsNull()) {
            break;
        }
        surface = trimmed->BasisSurface();
    }
    return surface;
}

TopoDS_Face face_at(const occt_shape *shape, int face_index) {
    if (!shape) {
        throw user_error("That face no longer exists.");
    }
    const TopTools_IndexedMapOfShape faces = map_of(shape->shape, TopAbs_FACE);
    if (face_index < 1 || face_index > faces.Extent()) {
        throw user_error("That face no longer exists.");
    }
    return TopoDS::Face(faces(face_index));
}

/// Greville abscissa of every pole of one direction: the mean of the `degree` knots after the pole's own first knot in the flat
/// sequence. A clamped direction reads it from the usual flat sequence. A periodic one has the flat sequence of one period
/// (every knot but the last, each repeated by its multiplicity: as many as poles), continued by the period in both directions.
/// OpenCascade's periodic flat knots begin `degree + 1 - first multiplicity` knots before that sequence, and pole j is the
/// basis function whose support starts at its own flat knot j, so pole j's support starts that many places before flat knot j.
/// Values are folded into [first, last].
std::vector<double> greville_all(const Handle(Geom_BSplineSurface) &surface, bool u_direction, double first, double last) {
    const int count = u_direction ? surface->NbUPoles() : surface->NbVPoles();
    const int degree = u_direction ? surface->UDegree() : surface->VDegree();
    const bool periodic = u_direction ? surface->IsUPeriodic() : surface->IsVPeriodic();
    std::vector<double> flat;
    int shift = 0;
    if (periodic) {
        shift = degree + 1 - (u_direction ? surface->UMultiplicity(1) : surface->VMultiplicity(1));
        const int knots = u_direction ? surface->NbUKnots() : surface->NbVKnots();
        for (int k = 1; k < knots; ++k) {
            const int multiplicity = u_direction ? surface->UMultiplicity(k) : surface->VMultiplicity(k);
            for (int m = 0; m < multiplicity; ++m) {
                flat.push_back(u_direction ? surface->UKnot(k) : surface->VKnot(k));
            }
        }
        if (static_cast<int>(flat.size()) != count) {
            throw user_error("This surface's periodic knots couldn't be read.");
        }
    }
    const double period = last - first;
    std::vector<double> out(count);
    for (int j = 0; j < count; ++j) {
        double sum = 0;
        for (int k = 1; k <= degree; ++k) {
            if (periodic) {
                const int at = j + k - shift;
                const int wraps = at >= 0 ? at / count : -((-at + count - 1) / count);
                sum += flat[at - wraps * count] + wraps * period;
            } else {
                const TColStd_Array1OfReal &sequence = u_direction ? surface->UKnotSequence() : surface->VKnotSequence();
                sum += sequence(std::min(sequence.Upper(), sequence.Lower() + j + k));
            }
        }
        double value = sum / degree;
        if (periodic && period > 0) {
            while (value > last) {
                value -= period;
            }
            while (value < first) {
                value += period;
            }
        }
        out[j] = std::min(std::max(value, first), last);
    }
    return out;
}

void unit_normal(const Handle(Geom_BSplineSurface) &surface, double u, double v, bool flip, double (&out)[3]) {
    double u0, u1, v0, v1;
    surface->Bounds(u0, u1, v0, v1);
    const double mid_u = 0.5 * (u0 + u1);
    const double mid_v = 0.5 * (v0 + v1);
    for (int attempt = 0; attempt < 4; ++attempt) {
        // A pole or apex gives a zero cross product: step toward the middle of the domain until it doesn't.
        const double t = attempt == 0 ? 0.0 : std::pow(10.0, attempt - 5);
        const double pu = u + t * (mid_u - u);
        const double pv = v + t * (mid_v - v);
        gp_Pnt point;
        gp_Vec du, dv;
        surface->D1(pu, pv, point, du, dv);
        const gp_Vec n = du.Crossed(dv);
        const double length = n.Magnitude();
        if (length > 1e-12) {
            const double sign = flip ? -1.0 : 1.0;
            out[0] = sign * n.X() / length;
            out[1] = sign * n.Y() / length;
            out[2] = sign * n.Z() / length;
            return;
        }
    }
    out[0] = 0;
    out[1] = 0;
    out[2] = 1;
}

struct converted_face {
    TopoDS_Face face;
    Handle(Geom_BSplineSurface) surface;
    int original = 0;
    bool converted = false;
};

/// Face `face_index`'s surface as a B-spline: itself when it is one, else an exact conversion of a copy.
converted_face convert_face(const occt_shape *shape, int face_index) {
    converted_face out;
    const TopoDS_Face source = face_at(shape, face_index);
    const BRepAdaptor_Surface adaptor(source, Standard_True);
    out.original = code_of(adaptor.GetType());
    out.face = source;
    if (out.original == kBSpline) {
        out.surface = Handle(Geom_BSplineSurface)::DownCast(unwrapped(BRep_Tool::Surface(source)));
    }
    if (out.surface.IsNull()) {
        BRepBuilderAPI_NurbsConvert converter(source, Standard_True);
        if (!converter.IsDone() || converter.Shape().IsNull() || converter.Shape().ShapeType() != TopAbs_FACE) {
            throw user_error("This surface couldn't be converted to a B-spline.");
        }
        out.face = TopoDS::Face(converter.Shape());
        out.surface = Handle(Geom_BSplineSurface)::DownCast(unwrapped(BRep_Tool::Surface(out.face)));
        if (out.surface.IsNull()) {
            throw user_error("This surface couldn't be converted to a B-spline.");
        }
        out.converted = true;
    }
    return out;
}

/// Copies `surface`'s net into `out`; with `normals` also the unit normal at each pole's Greville point.
void fill_net(const Handle(Geom_BSplineSurface) &surface, bool normals, bool flip, occt_surface_net &out) {
    const int nu = surface->NbUPoles();
    const int nv = surface->NbVPoles();
    out.degree_u = surface->UDegree();
    out.degree_v = surface->VDegree();
    out.u_count = nu;
    out.v_count = nv;
    out.periodic_u = surface->IsUPeriodic() ? 1 : 0;
    out.periodic_v = surface->IsVPeriodic() ? 1 : 0;
    out.rational = surface->IsURational() || surface->IsVRational() ? 1 : 0;
    out.poles = zeroed<double>(static_cast<size_t>(nu) * nv * 3);
    if (out.rational) {
        out.weights = zeroed<double>(static_cast<size_t>(nu) * nv);
    }
    for (int i = 0; i < nu; ++i) {
        for (int j = 0; j < nv; ++j) {
            const size_t at = static_cast<size_t>(i) * nv + j;
            const gp_Pnt p = surface->Pole(i + 1, j + 1);
            out.poles[3 * at] = p.X();
            out.poles[3 * at + 1] = p.Y();
            out.poles[3 * at + 2] = p.Z();
            if (out.weights) {
                out.weights[at] = surface->Weight(i + 1, j + 1);
            }
        }
    }
    out.knot_u_count = surface->NbUKnots();
    out.knot_v_count = surface->NbVKnots();
    out.knots_u = zeroed<double>(out.knot_u_count);
    out.mult_u = zeroed<int>(out.knot_u_count);
    out.knots_v = zeroed<double>(out.knot_v_count);
    out.mult_v = zeroed<int>(out.knot_v_count);
    for (int k = 0; k < out.knot_u_count; ++k) {
        out.knots_u[k] = surface->UKnot(k + 1);
        out.mult_u[k] = surface->UMultiplicity(k + 1);
    }
    for (int k = 0; k < out.knot_v_count; ++k) {
        out.knots_v[k] = surface->VKnot(k + 1);
        out.mult_v[k] = surface->VMultiplicity(k + 1);
    }
    if (!normals) {
        return;
    }
    out.normals = zeroed<double>(static_cast<size_t>(nu) * nv * 3);
    double u0, u1, v0, v1;
    surface->Bounds(u0, u1, v0, v1);
    const std::vector<double> us = greville_all(surface, true, u0, u1);
    const std::vector<double> vs = greville_all(surface, false, v0, v1);
    for (int i = 0; i < nu; ++i) {
        for (int j = 0; j < nv; ++j) {
            double n[3];
            unit_normal(surface, us[i], vs[j], flip, n);
            const size_t at = static_cast<size_t>(i) * nv + j;
            out.normals[3 * at] = n[0];
            out.normals[3 * at + 1] = n[1];
            out.normals[3 * at + 2] = n[2];
        }
    }
}

} // namespace

extern "C" {

int occt_control_net_of_face(const occt_shape *shape, int face_index, int max_poles, occt_surface_net *out,
                             occt_status *status) {
    return guarded(status, [&]() -> int {
        occt_initialize();
        *out = occt_surface_net{};
        const converted_face converted = convert_face(shape, face_index);
        const Handle(Geom_BSplineSurface) &surface = converted.surface;
        out->converted_from = converted.converted ? converted.original : -1;
        const int degree = std::max(surface->UDegree(), surface->VDegree());
        if (degree > kMaxDegree) {
            throw user_error("Edit Surface works on degree 1 to " + number(kMaxDegree) + "; this surface is degree " +
                             number(degree) + ". Rebuild it first.");
        }
        const double count = static_cast<double>(surface->NbUPoles()) * surface->NbVPoles();
        if (max_poles > 0 && count > max_poles) {
            throw user_error("This surface has " + number(count) + " control points; Edit Surface works on at most " +
                             number(max_poles) + ".");
        }
        out->kind = converted.original;
        fill_net(surface, true, converted.face.Orientation() == TopAbs_REVERSED, *out);
        return 1;
    });
}

int occt_surface_info(const occt_shape *shape, int face_index, occt_surface_net *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        occt_initialize();
        *out = occt_surface_net{};
        const TopoDS_Face face = face_at(shape, face_index);
        const BRepAdaptor_Surface adaptor(face, Standard_True);
        out->kind = code_of(adaptor.GetType());
        out->converted_from = -1;
        const Handle(Geom_Surface) surface = unwrapped(BRep_Tool::Surface(face));
        if (out->kind == kBSpline) {
            Handle(Geom_BSplineSurface) spline = Handle(Geom_BSplineSurface)::DownCast(surface);
            if (!spline.IsNull()) {
                fill_net(spline, false, false, *out);
            }
        } else if (out->kind == kBezier) {
            Handle(Geom_BezierSurface) bezier = Handle(Geom_BezierSurface)::DownCast(surface);
            if (!bezier.IsNull()) {
                fill_net(GeomConvert::SurfaceToBSplineSurface(bezier), false, false, *out);
            }
        }
        return 1;
    });
}

void occt_surface_net_free(occt_surface_net *net) {
    if (net) {
        std::free(net->poles);
        std::free(net->weights);
        std::free(net->knots_u);
        std::free(net->knots_v);
        std::free(net->normals);
        std::free(net->mult_u);
        std::free(net->mult_v);
        *net = occt_surface_net{};
    }
}

int occt_control_net_of_curve(const occt_shape *wire, occt_curve_net *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        occt_initialize();
        *out = occt_curve_net{};
        if (!wire || wire->shape.IsNull() || wire->shape.ShapeType() != TopAbs_WIRE) {
            throw user_error("This isn't a curve.");
        }
        TopoDS_Edge edge;
        int pieces = 0;
        for (TopExp_Explorer explorer(wire->shape, TopAbs_EDGE); explorer.More(); explorer.Next()) {
            if (pieces == 0) {
                edge = TopoDS::Edge(explorer.Current());
            }
            ++pieces;
        }
        if (pieces != 1) {
            throw user_error("A curve of one piece is needed.");
        }
        double first = 0;
        double last = 0;
        Handle(Geom_Curve) base = BRep_Tool::Curve(edge, first, last);
        if (base.IsNull()) {
            throw user_error("This curve has no geometry.");
        }
        Handle(Geom_Curve) basis = base;
        while (true) {
            Handle(Geom_TrimmedCurve) trimmed = Handle(Geom_TrimmedCurve)::DownCast(basis);
            if (trimmed.IsNull()) {
                break;
            }
            basis = trimmed->BasisCurve();
        }
        out->converted_from = -1;
        Handle(Geom_BSplineCurve) spline = Handle(Geom_BSplineCurve)::DownCast(basis);
        if (!spline.IsNull()) {
            spline = Handle(Geom_BSplineCurve)::DownCast(spline->Copy());
            const double slack = 1e-9 * (1.0 + std::abs(spline->LastParameter() - spline->FirstParameter()));
            const bool whole = std::abs(first - spline->FirstParameter()) <= slack &&
                               std::abs(last - spline->LastParameter()) <= slack;
            if (!whole) {
                if (spline->IsPeriodic()) {
                    spline->SetNotPeriodic();
                }
                spline->Segment(first, last);
            }
        } else {
            out->converted_from = !Handle(Geom_Line)::DownCast(basis).IsNull()     ? 0
                                  : !Handle(Geom_Circle)::DownCast(basis).IsNull() ? 1
                                                                                   : 2;
            const Handle(Geom_TrimmedCurve) trimmed = new Geom_TrimmedCurve(basis, first, last);
            spline = GeomConvert::CurveToBSplineCurve(trimmed);
        }
        if (spline.IsNull()) {
            throw user_error("This curve couldn't be converted to a B-spline.");
        }
        out->periodic = spline->IsPeriodic() ? 1 : 0;
        if (edge.Orientation() == TopAbs_REVERSED) {
            spline->Reverse();
        }
        if (spline->Degree() > kMaxDegree) {
            throw user_error("Edit Curve works on degree 1 to " + number(kMaxDegree) + "; this curve is degree " +
                             number(spline->Degree()) + ". Rebuild it first.");
        }
        const int n = spline->NbPoles();
        out->degree = spline->Degree();
        out->pole_count = n;
        out->poles = zeroed<double>(static_cast<size_t>(n) * 3);
        out->rational = spline->IsRational() ? 1 : 0;
        if (out->rational) {
            out->weights = zeroed<double>(n);
        }
        for (int i = 0; i < n; ++i) {
            const gp_Pnt p = spline->Pole(i + 1);
            out->poles[3 * i] = p.X();
            out->poles[3 * i + 1] = p.Y();
            out->poles[3 * i + 2] = p.Z();
            if (out->weights) {
                out->weights[i] = spline->Weight(i + 1);
            }
        }
        out->knot_count = spline->NbKnots();
        out->knots = zeroed<double>(out->knot_count);
        out->multiplicities = zeroed<int>(out->knot_count);
        for (int k = 0; k < out->knot_count; ++k) {
            out->knots[k] = spline->Knot(k + 1);
            out->multiplicities[k] = spline->Multiplicity(k + 1);
        }
        return 1;
    });
}

void occt_curve_net_free(occt_curve_net *net) {
    if (net) {
        std::free(net->poles);
        std::free(net->weights);
        std::free(net->knots);
        std::free(net->multiplicities);
        *net = occt_curve_net{};
    }
}

int occt_test_net_gaps(const occt_shape *shape, int face_index, double *normal_error, double *pole_gap, occt_status *status) {
    return guarded(status, [&]() -> int {
        occt_initialize();
        const converted_face converted = convert_face(shape, face_index);
        const Handle(Geom_BSplineSurface) &surface = converted.surface;
        const bool flip = converted.face.Orientation() == TopAbs_REVERSED;
        double u0, u1, v0, v1;
        surface->Bounds(u0, u1, v0, v1);
        const std::vector<double> us = greville_all(surface, true, u0, u1);
        const std::vector<double> vs = greville_all(surface, false, v0, v1);
        *normal_error = 0;
        *pole_gap = 0;
        for (int i = 0; i < surface->NbUPoles(); ++i) {
            for (int j = 0; j < surface->NbVPoles(); ++j) {
                gp_Pnt point;
                gp_Vec du, dv;
                surface->D1(us[i], vs[j], point, du, dv);
                double n[3];
                unit_normal(surface, us[i], vs[j], flip, n);
                const gp_Vec normal(n[0], n[1], n[2]);
                if (du.Magnitude() > 1e-9) {
                    *normal_error = std::max(*normal_error, std::abs(normal.Dot(du)) / du.Magnitude());
                }
                if (dv.Magnitude() > 1e-9) {
                    *normal_error = std::max(*normal_error, std::abs(normal.Dot(dv)) / dv.Magnitude());
                }
                *pole_gap = std::max(*pole_gap, point.Distance(surface->Pole(i + 1, j + 1)));
            }
        }
        return 1;
    });
}

occt_shape *occt_test_reversed_copy(const occt_shape *shape, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * { return new occt_shape{shape->shape.Reversed()}; });
}

occt_shape *occt_test_bspline_sheet(int u_count, int v_count, int degree, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (degree < 1 || u_count < degree + 1 || v_count < degree + 1) {
            throw user_error("A sheet needs more poles than its degree each way.");
        }
        TColgp_Array2OfPnt poles(1, u_count, 1, v_count);
        for (int i = 1; i <= u_count; ++i) {
            for (int j = 1; j <= v_count; ++j) {
                poles(i, j) = gp_Pnt(i - 1, j - 1, 0);
            }
        }
        const int knot_u = u_count - degree + 1;
        const int knot_v = v_count - degree + 1;
        TColStd_Array1OfReal knots_u(1, knot_u);
        TColStd_Array1OfReal knots_v(1, knot_v);
        TColStd_Array1OfInteger mult_u(1, knot_u);
        TColStd_Array1OfInteger mult_v(1, knot_v);
        for (int i = 1; i <= knot_u; ++i) {
            knots_u(i) = i - 1;
            mult_u(i) = (i == 1 || i == knot_u) ? degree + 1 : 1;
        }
        for (int j = 1; j <= knot_v; ++j) {
            knots_v(j) = j - 1;
            mult_v(j) = (j == 1 || j == knot_v) ? degree + 1 : 1;
        }
        Handle(Geom_BSplineSurface) surface =
            new Geom_BSplineSurface(poles, knots_u, knots_v, mult_u, mult_v, degree, degree);
        BRepBuilderAPI_MakeFace face(surface, 1e-7);
        if (!face.IsDone()) {
            throw user_error("The sheet couldn't be made.");
        }
        return new occt_shape{face.Face()};
    });
}

} // extern "C"
