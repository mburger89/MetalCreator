#include "cocct_solids.hpp"

#include <BRepBuilderAPI_MakeSolid.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepClass3d_SolidClassifier.hxx>
#include <BRepGProp.hxx>
#include <GProp_GProps.hxx>
#include <TopAbs_State.hxx>
#include <TopoDS_Shell.hxx>
#include <TopoDS_Solid.hxx>
#include <gp_Pnt.hxx>

#include <cmath>

namespace cocct {

TopoDS_Shape solidify_closed_shell(const TopoDS_Shape &shell) {
    if (!BRep_Tool::IsClosed(shell)) {
        return TopoDS_Shape();
    }
    BRepBuilderAPI_MakeSolid maker(TopoDS::Shell(shell));
    if (!maker.IsDone()) {
        return TopoDS_Shape();
    }
    TopoDS_Shape solid = maker.Solid();
    GProp_GProps volume;
    BRepGProp::VolumeProperties(solid, volume);
    if (volume.Mass() < 0) {
        // Turn the shell, not the solid: a solid with a reversed orientation flag is valid but fillets, offsets and booleans
        // misjudge it (the fillet of a thickened plate came back invalid).
        BRepBuilderAPI_MakeSolid turned(TopoDS::Shell(shell.Reversed()));
        if (!turned.IsDone()) {
            return TopoDS_Shape();
        }
        solid = turned.Solid();
    }
    BRepCheck_Analyzer check(solid);
    return check.IsValid() ? solid : TopoDS_Shape();
}

namespace {

double volume_of(const TopoDS_Shape &shape) {
    GProp_GProps properties;
    BRepGProp::VolumeProperties(shape, properties);
    return properties.Mass();
}

} // namespace

TopoDS_Shape solid_with_void(const TopoDS_Shape &a, const TopoDS_Shape &b) {
    if (a.IsNull() || b.IsNull() || a.ShapeType() != TopAbs_SHELL || b.ShapeType() != TopAbs_SHELL) {
        return TopoDS_Shape();
    }
    const TopoDS_Shape solid_a = solidify_closed_shell(a);
    const TopoDS_Shape solid_b = solidify_closed_shell(b);
    if (solid_a.IsNull() || solid_b.IsNull()) {
        return TopoDS_Shape();
    }
    const double volume_a = volume_of(solid_a);
    const double volume_b = volume_of(solid_b);
    const bool a_is_outer = volume_a >= volume_b;
    const TopoDS_Shape &outer_solid = a_is_outer ? solid_a : solid_b;
    const TopoDS_Shape &inner_solid = a_is_outer ? solid_b : solid_a;
    const double outer_volume = a_is_outer ? volume_a : volume_b;
    const double inner_volume = a_is_outer ? volume_b : volume_a;
    if (!(outer_volume > 0) || !(inner_volume > 0)) {
        return TopoDS_Shape();
    }
    TopExp_Explorer outer_shells(outer_solid, TopAbs_SHELL);
    TopExp_Explorer inner_shells(inner_solid, TopAbs_SHELL);
    TopExp_Explorer inner_vertices(inner_solid, TopAbs_VERTEX);
    if (!outer_shells.More() || !inner_shells.More() || !inner_vertices.More()) {
        return TopoDS_Shape();
    }
    const gp_Pnt probe = BRep_Tool::Pnt(TopoDS::Vertex(inner_vertices.Current()));
    BRepClass3d_SolidClassifier classifier(outer_solid, probe, 1e-7);
    if (classifier.State() != TopAbs_IN) {
        return TopoDS_Shape();
    }
    // The inner shell, turned inward (the reverse of the orientation that gave its own solid a positive volume).
    const TopoDS_Shape inward = inner_shells.Current().Reversed();
    BRepBuilderAPI_MakeSolid maker(TopoDS::Shell(outer_shells.Current()));
    maker.Add(TopoDS::Shell(inward));
    if (!maker.IsDone()) {
        return TopoDS_Shape();
    }
    const TopoDS_Shape result = maker.Solid();
    if (!BRepCheck_Analyzer(result).IsValid()) {
        return TopoDS_Shape();
    }
    const double expected = outer_volume - inner_volume;
    const double volume = volume_of(result);
    if (!(volume > 0) || std::abs(volume - expected) > 1e-6 * expected) {
        return TopoDS_Shape();
    }
    return result;
}

} // namespace cocct
