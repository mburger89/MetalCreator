#ifndef COCCT_H
#define COCCT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// An owned OCCT shape. Free it with occt_shape_free.
typedef struct occt_shape occt_shape;

/// Outcome of a shim call. `ok` is 1 on success; otherwise `message` holds OCCT's reason.
typedef struct {
    int ok;
    char message[512];
} occt_status;

occt_shape *occt_make_box(double dx, double dy, double dz, occt_status *status);
void occt_shape_free(occt_shape *shape);

/// The query functions below (volume, face/edge count, edge length) never throw; they
/// return the sentinel -1 if OCCT fails internally.
double occt_volume(const occt_shape *shape);
int occt_face_count(const occt_shape *shape);
int occt_edge_count(const occt_shape *shape);
/// Length of the edge at 1-based `index` in OCCT's indexed edge map, or -1 if out of range.
double occt_edge_length(const occt_shape *shape, int index);
/// 1 when OCCT's checker (BRepCheck_Analyzer, geometry included) accepts the shape as a valid B-rep, 0 when it
/// rejects it, -1 if the check itself fails.
int occt_is_valid(const occt_shape *shape);
/// How far any face's pcurve leaves its surface's parameter range, in parameter units, sampled at 65 points along
/// each pcurve: 0 when every pcurve lies inside (an unbounded or periodic direction never counts), -1 if the check fails.
double occt_pcurve_domain_excursion(const occt_shape *shape);

/// Fillets the edge at 1-based `edge_index` with `radius`. Returns NULL on failure.
occt_shape *occt_fillet_edge(const occt_shape *shape, int edge_index, double radius, occt_status *status);
/// Writes `shape` as AP214 STEP in millimetres. Returns 1 on success.
int occt_write_step(const occt_shape *shape, const char *path, occt_status *status);
/// Meshes `shape` with `linear_deflection` (mm) and writes ASCII STL. Returns 1 on success.
int occt_write_stl(const occt_shape *shape, const char *path, double linear_deflection, occt_status *status);

/// Prepares process-wide OCCT state once: STEP units (mm) and silencing OCCT's stdout
/// printer. Idempotent and thread-safe.
void occt_initialize(void);

/// History: where an output face came from. `out_face` is the 1-based index in the output's
/// face map; `operand`/`index` refer to the operation's inputs (index is 1-based for faces and
/// edges, 0-based for profile segments). For OCCT_FROM_SEGMENT, `operand` is the profile loop
/// (0 = outer boundary, n = hole n, as in occt_profile.loops) and `index` the segment in that loop.
typedef enum {
    OCCT_FROM_START_CAP = 0,
    OCCT_FROM_END_CAP = 1,
    OCCT_FROM_SEGMENT = 2,
    OCCT_FROM_FACE = 3,
    OCCT_FROM_EDGE = 4
} occt_history_kind;

typedef struct {
    int out_face;
    int kind;
    int operand;
    int index;
} occt_history_record;

typedef struct {
    occt_history_record *records;
    int count;
} occt_history;

void occt_history_free(occt_history *history);

/// One edge of a result made from an edge of an input (NS-5, R5): `out_edge` and `index` are 1-based, `operand` is 0-based (the input's position).
typedef struct {
    int out_edge;
    int operand;
    int index;
} occt_edge_record;

typedef struct {
    occt_edge_record *records;
    int count;
} occt_edge_history;

void occt_edge_history_free(occt_edge_history *history);

typedef struct {
    double volume;
    double area;
    double centroid[3];
    double min[3];
    double max[3];
} occt_properties;

int occt_read_properties(const occt_shape *shape, occt_properties *out, occt_status *status);
/// The shape's tight axis-aligned bounds, without computing mass properties. `pole_hull` nonzero bounds a face on a B-spline surface
/// of over 400 poles by its pole hull instead (loose but free; a control-point preview's). Returns 1 on success.
int occt_read_bounds(const occt_shape *shape, double min[3], double max[3], int pole_hull, occt_status *status);

/// Surface kinds: 0 plane, 1 cylinder, 2 cone, 3 sphere, 4 torus, 5 bspline, 6 other.
typedef struct {
    int kind;
    int has_normal;
    double normal[3];
    double area;
    double centroid[3];
    /// Cylinders only: has_axis is 1 and `radius` and `axis_point` (a point on the axis) are set.
    int has_axis;
    double radius;
    double axis_point[3];
    /// 1 when the face lies on a shell that is not closed (a sheet), or on no shell at all.
    int on_open_shell;
} occt_face_info;

/// Curve kinds: 0 line, 1 circle, 2 ellipse, 3 bspline, 4 other.
/// Convexity: 0 convex, 1 concave, 2 smooth, 3 unknown.
/// face_a/face_b: 1-based face indices; equal for a seam; both 0 for a free edge. A boundary edge (a sheet's free
/// edge: one face, not closed on it, not degenerate) has `boundary` 1, face_a its face and face_b 0.
/// For projecting edges into a sketch (S4): when has_ends, `start` and `end` are the curve's points at
/// its first and last parameter. For a circle, `center` and `radius` are its own, and the edge runs
/// counter-clockwise about `direction` from `start` through `sweep` radians (2π for a full circle).
typedef struct {
    int kind;
    int has_direction;
    double direction[3];
    double length;
    double midpoint[3];
    int convexity;
    int face_a;
    int face_b;
    int has_ends;
    double start[3];
    double end[3];
    double center[3];
    double radius;
    double sweep;
    int boundary;
} occt_edge_info;

typedef struct {
    occt_face_info *faces;
    int face_count;
    occt_edge_info *edges;
    int edge_count;
} occt_topology;

int occt_read_topology(const occt_shape *shape, occt_topology *out, occt_status *status);
void occt_topology_free(occt_topology *topology);

/// A plane: origin, unit normal, unit in-plane x axis (y = normal × x).
typedef struct {
    double origin[3];
    double normal[3];
    double x_axis[3];
} occt_plane;

/// One profile segment in plane coordinates. kind 0 = line (x0,y0)→(x1,y1);
/// kind 1 = arc around (cx,cy) with `radius` from angle `start` to `end` (radians): counter-clockwise when
/// end > start, clockwise when end < start (a counter-clockwise loop running along a notch).
/// kind 2 = degree-5 clamped B-spline: `pole_count` poles from `occt_profile.spline_poles` (x,y pairs, starting at pair
/// `pole_offset`) and `knot_count` distinct knots with multiplicities from `spline_knots` / `spline_mults` (from `knot_offset`);
/// x0..y1 are the end points.
typedef struct {
    int kind;
    double x0, y0, x1, y1;
    double cx, cy, radius, start, end;
    int pole_offset, pole_count, knot_offset, knot_count;
} occt_segment;

/// One closed loop of segments, in order.
typedef struct {
    const occt_segment *segments;
    int segment_count;
} occt_loop;

/// A planar region. loops[0] is the outer boundary; loops[1 ..< loop_count] are holes, which must
/// lie inside it without touching it or each other. Holes may wind either way: the shim reverses a
/// hole wire that winds the same way as the outer loop, which is what OCCT needs.
typedef struct {
    occt_plane plane;
    const occt_loop *loops;
    int loop_count;
    /// The side tables kind-2 segments index (shared by every profile of one call); may be null without splines.
    const double *spline_poles;
    const double *spline_knots;
    const int *spline_mults;
} occt_profile;

/// Extrudes the profile along its plane normal by `distance`. History: start/end caps and
/// one OCCT_FROM_SEGMENT record per side face (operand = loop, index = segment), hole walls included.
occt_shape *occt_extrude(const occt_profile *profile, double distance, occt_history *history, occt_status *status);

/// Revolves the profile about the axis by `angle` (radians, 0 < angle <= 2π). Caps
/// (OCCT_FROM_START_CAP/END_CAP) exist only for a partial revolve; sides are OCCT_FROM_SEGMENT
/// (operand = loop, index = segment), hole walls included.
occt_shape *occt_revolve(const occt_profile *profile, const double axis_origin[3], const double axis_direction[3],
                         double angle, occt_history *history, occt_status *status);
/// Lofts through `count` profiles (ruled = straight sides). Sides are OCCT_FROM_SEGMENT (operand 0)
/// with the index of the first section's segment; caps are the first and last sections. Every
/// section must be a single loop: a profile with holes is refused.
occt_shape *occt_loft(const occt_profile *profiles, int count, int ruled, occt_history *history, occt_status *status);

/// Boolean of `a` with `tools` (op 0 fuse, 1 cut, 2 common). History operands: 0 = a, i+1 = tools[i].
occt_shape *occt_boolean(int op, const occt_shape *a, const occt_shape *const *tools, int tool_count,
                         occt_history *history, occt_status *status);
/// Rotates about the axis (if has_rotation) and then translates. History operand 0 = shape.
occt_shape *occt_transform(const occt_shape *shape, const double translation[3], int has_rotation,
                           const double axis_origin[3], const double axis_direction[3], double angle,
                           occt_history *history, occt_status *status);

/// FOR TESTS ONLY. A copy of `shape` carrying a non-identity TopLoc_Location (`shape.Moved(loc)`: the geometry is shared and
/// unchanged, only the location is set, as a STEP import can give): a rotation about Z by `angle_z` radians, then a translation.
/// Reports failure in `status` and returns null; throws nothing; the caller frees the result with occt_shape_free.
occt_shape *occt_test_located_copy(const occt_shape *shape, const double translation[3], double angle_z, occt_status *status);

/// FOR TESTS ONLY. The largest BRep_Tool::Tolerance over the vertices of `shape` in millimetres, or -1 if anything throws.
/// Reads only; allocates nothing the caller must free.
double occt_test_max_vertex_tolerance(const occt_shape *shape);

/// Fillets the edges (1-based indices) with `radius`. History operand 0 = shape:
/// OCCT_FROM_FACE for kept/modified faces, OCCT_FROM_EDGE (index = input edge) for blend faces.
occt_shape *occt_fillet(const occt_shape *shape, const int *edge_indices, int count, double radius,
                        occt_history *history, occt_status *status);
/// SPIKE (G-b). Per-seam gaps of a curvature-continuous fillet, measured at 65 points along each strip's spring edges.
#define OCCT_G2_MAX_SEAMS 64
typedef struct {
    double position;           // worst distance between the two faces, mm
    double angle_degrees;      // worst angle between the faces' outward normals
    double curvature;          // worst difference of the normal curvatures across the seam, 1/mm
    double curvature_allowed;  // the tolerance at that sample: max(1 % of the larger curvature, 1e-4)
    double curvature_ratio;    // worst gap / allowed over the samples (<= 1 passes)
} occt_g2_seam;
typedef struct {
    int strips;                // strip faces replaced
    int sections;              // the most cross-sections any strip needed
    int strip_sections[32];    // cross-sections each strip needed (strips in edge order)
    int corners;               // corner patches refilled
    int g1_joins;              // chain joins whose springs kink (> 0.01 degrees): only approximately tangent there, the node warns
    int g2_corners;            // corners rebuilt as one G2 three-sided patch
    int g1_corners;            // the corners refilled tangent only (G1): the node warns
    int seam_count;            // the strips' spring seams, in strip order, two each
    occt_g2_seam seams[OCCT_G2_MAX_SEAMS];   // a sample of them: the first OCCT_G2_MAX_SEAMS
    int seams_total;           // every spring seam the shim judged, however many the array holds
    int seams_judged;          // 1 once the shim has judged all of them at the promised tolerances (else a miss threw)
    int mitres;                // strip pairs that meet in a mitre, cut by one another
    int mitre_seam_count;      // their seams: a mitre is a crease, only its position is promised
    occt_g2_seam mitre_seams[OCCT_G2_MAX_SEAMS];
    int corner_seam_count;     // the corner patches' boundaries against their strips / faces, measured apart
    occt_g2_seam corner_seams[OCCT_G2_MAX_SEAMS];
    // The corner patches' (worst over the g2_corners), for the tests and the benchmarks.
    double corner_milliseconds;      // time to build all of them
    double corner_block_mismatch;    // the shared control blocks' disagreement, mm
    double corner_min_lambda;        // the least across scale (positive: the reparametrisation is monotone)
    double corner_max_curvature;     // the largest principal curvature over the patch interior, 1/mm
    double corner_min_sine;          // the least sine of the angle between the parameter curves (regular: > 0)
    int corner_attempts;             // corners a patch was tried on, accepted or not
} occt_g2_report;
/// The gaps between the two faces of edge `edge_index` (1-based, as in the topology), read at `samples` + 1 points evenly
/// along it, ends included. 0 if the edge does not border exactly two faces. For tests.
int occt_edge_seam_dense(const occt_shape *shape, int edge_index, int samples, occt_g2_seam *seam);
/// Fillets like occt_fillet, then replaces each strip's surface with quintic G2 sections whose end tangent lengths are
/// `weight` times the circle's. Sections start at 9 per strip and double until the strip's spring seams measure inside
/// half the tolerances; past 129 the call fails ("The fillet can't be made curvature continuous at this radius.").
/// A corner where three strips end is one degree-17 three-sided patch, G2 to all three strips (g2_corners), when its
/// across scales are positive, its shared control blocks agree to 1e-6 mm, its principal curvature stays within 4 / r,
/// its seams pass and the solid is valid; any other corner is refilled with MakeFilling constrained G1 to the strips and
/// original faces and counted in g1_corners (OCCT 7.9's MakeFilling cannot constrain G2); if that misses the position or
/// angle tolerance, or the solid fails BRepCheck, the call fails ("The fillet's corners can't be made smooth at this
/// radius."). A crease and an invalid solid are never returned. The history names the final solid's faces. A tangency weight
/// that pushes a section past the neighbours' surfaces fails with "The tangency weight is too large for this
/// fillet."; anything else the construction cannot do fails with "The fillet can't be made curvature continuous at
/// this radius."
/// The weight must be greater than 0.
occt_shape *occt_fillet_g2(const occt_shape *shape, const int *edge_indices, int count, double radius, double weight,
                           occt_history *history, occt_g2_report *report, occt_status *status);
/// FOR TESTS ONLY. Evaluates the quintic section through two end conditions {position[3], direction[3], acceleration[3]}
/// with end derivative lengths len0 and len1: out = position[3], d1[3], d2[3] at t. Returns 1.
int occt_g2_section_test(const double end0[9], double len0, const double end1[9], double len1, double t, double out[9]);
/// The circle's cubic-equivalent end derivative length for a chord and a turning angle (radians).
double occt_g2_tangent_length(double chord, double turning_angle);
/// SPIKE (G-d). One end of an end-constrained loft: `face_index` is a 1-based face of the part (OCCT's indexed face map);
/// below 1 the end has no face. `continuity` 0 Free, 1 Tangent (G1), 2 Curvature (G2); `weight` (> 0) scales the
/// across-tangent length, the fillet's circular-arc convention (occt_g2_tangent_length).
typedef struct {
    int face_index;
    int continuity;
    double weight;
} occt_loft_end;
#define OCCT_LOFT_MAX_SEGMENTS 32
typedef struct {
    int segments;                          // side patches (the loop's edges)
    int columns[OCCT_LOFT_MAX_SEGMENTS];   // columns each patch needed (0 for a ThruSections loft)
    int max_columns;                       // the most any patch needed
    int seams_total;                       // face-end seams judged on the built solid (one per loop edge per face end)
    int seams_judged;                      // 1 once every promised seam met its tolerance (else the call failed)
    occt_g2_seam worst_seam;               // the worst face-end seam on the built solid
    double side_gap;                       // the worst distance between neighbouring side patches along their shared column
    double section_gap;                    // the worst distance between a patch and its sections' curves
    int used_thru_sections;                // 1 when every end was Free and OCCT's ThruSections built the loft
} occt_loft_report;
/// Lofts from an optional face of `part` (start), through `count` profiles, to an optional face of `part` (end); at
/// least two sections in all; a face's outer loop is its section. Sections are paired segment by segment and points
/// along them by the fraction of their parameter; a face loop runs in its wire's order from its edge with the lowest
/// index, then is turned to wind the same way as the section next to it (by vector area) and started at the edge whose
/// rotation best matches that section's vertices (least squares about the loops' centres; the first such rotation on a
/// tie; a one-edge closed loop, a circle, starts at the point nearest the paired section's start). A face that is not flat
/// is refused ("The loft's end face must be flat."), as is a weight that loops a column back ("The tangency weight is too
/// large for this loft."). With every end Free it is occt_loft's ThruSections (a face end through the face's own edges). With Tangent or
/// Curvature at a face end the loft is skinned here: per segment, columns across the sections as quintic C4 B-splines
/// (one chord-length knot vector for the whole loft), the face end's first derivative = weight x the circular length
/// along the part's adjacent face's direction away from the part, its second derivative from that face's normal
/// curvature (G2) or the third derivative zero (G1); Free ends the natural conditions (third and fourth derivatives
/// zero). Each pole row is skinned along the segment by our own spline (cubic, then quintic if the cubic misses; periodic with a knot per
/// column on a one-edge closed loop; broken at a part edge's knots where its derivatives jump; cubic where a smooth vertex gives its
/// tangents). Columns start at 5 per segment (9 on a closed loop) and a span that misses gets its middle (129 in all at most) until the
/// face-end seams (half tolerances) and the sections fit; the built solid's face-end seams are then judged at the full tolerances ("The loft can't meet the part tangent
/// (G1) here." / "The loft can't meet the part with matching curvature (G2) here."). History as occt_loft: caps
/// (a face end's cap is a copy of the face), sides OCCT_FROM_SEGMENT (operand 0, index = the paired segment).
occt_shape *occt_loft_ends(const occt_shape *part, const occt_loft_end *start, const occt_loft_end *end,
                           const occt_profile *sections, int count, occt_history *history, occt_loft_report *report,
                           occt_status *status);

/// Equal-distance chamfer of the edges; same history contract as occt_fillet.
occt_shape *occt_chamfer(const occt_shape *shape, const int *edge_indices, int count, double distance,
                         occt_history *history, occt_status *status);

/// Triangles per face plus B-rep edge polylines. Free with occt_mesh_free.
/// edge_offsets has edge_count + 1 entries: points of edge e (0-based) are
/// edge_points[3*edge_offsets[e] ..< 3*edge_offsets[e+1]]; seams and degenerate edges are empty.
typedef struct {
    double *positions;
    double *normals;
    int vertex_count;
    unsigned int *indices;
    int *triangle_faces;
    int triangle_count;
    double *edge_points;
    int *edge_offsets;
    int edge_count;
} occt_mesh;

/// `angle` is the largest turn in radians between neighbouring triangle normals on a curved face (OCCT's angular deflection).
int occt_tessellate(const occt_shape *shape, double tolerance, double angle, occt_mesh *out, occt_status *status);
void occt_mesh_free(occt_mesh *mesh);
/// Distances in millimetres from `point_count` points (x, y, z triples in `points`) to part of `shape`, written to
/// `out` (one per point; the caller owns it, the shim allocates nothing). `kind` 0 measures to the surface of the whole
/// shape (every face), 1 to the faces and 2 to the edges at the 1-based `indices` (OCCT's indexed face and edge maps,
/// as in occt_fillet). With `signed_distance` and kind 0, a point inside the shape gets a negative distance. Returns 1.
int occt_distances(const occt_shape *shape, int kind, const int *indices, int index_count, const double *points,
                   int point_count, int signed_distance, double *out, occt_status *status);
/// The same measurement with BRepExtrema alone, no analytic fast path for planes and cylinders: the reference the fast
/// path is tested against. Same arguments and result as occt_distances.
int occt_distances_reference(const occt_shape *shape, int kind, const int *indices, int index_count, const double *points,
                             int point_count, int signed_distance, double *out, occt_status *status);
/// How a face is parametrized (implicit spec §3.5, Face mapping): the range of its u and v, the millimetres of surface per unit of
/// each (the mean of |dS/du| and |dS/dv| over the range), the period of a coordinate in which the face closes on itself (0 when it
/// does not), and whether the face has a degenerate edge (a pole or an apex).
typedef struct {
    double u_min, u_max, v_min, v_max;
    double u_scale, v_scale;
    double u_period, v_period;
    int degenerate;
} occt_face_chart_info;
/// The parametrization of the face at the 1-based `face_index` (OCCT's indexed face map, as in occt_distances). Returns 1.
int occt_face_chart_info_of(const occt_shape *shape, int face_index, occt_face_chart_info *out, occt_status *status);
/// Where `point_count` points (x, y, z triples in `points`) stand against that face: three numbers per point in `out` (u, v and the
/// signed distance along the face's outward normal, negative on the solid's side), where (u, v) belong to the nearest point of the
/// face, kept within half a period of the face's middle on a periodic surface. The caller owns `out`. Returns 1.
int occt_face_coordinates(const occt_shape *shape, int face_index, const double *points, int point_count, double *out,
                          occt_status *status);
/// The cross-section of a solid by a plane (section analysis part B): the solid is cut by a planar face on the plane
/// (BRepAlgoAPI_Common) and each face of the result is a region, tessellated at `tolerance` with every triangle's normal along
/// `normal`. All regions share `positions` / `indices`; region r owns triangles `region_triangle_offsets[r]` to `[r + 1]`.
/// Pieces are the edges of each region's face: `piece_kind` 0 polyline only, 1 line, 2 circle; `piece_curve` holds 11 numbers
/// per piece (line: start xyz, end xyz; circle: centre xyz, axis xyz, radius, start xyz, sweep); `piece_source_face` is the
/// solid's 0-based face the edge lies on, -1 when unknown; `piece_points` are the polylines, `piece_point_offsets` the
/// piece_count + 1 starts. A plane that misses the solid succeeds with zero regions. Free with occt_section_free.
typedef struct {
    double *positions;
    int vertex_count;
    unsigned int *indices;
    int triangle_count;
    int *region_triangle_offsets;
    int region_count;
    int piece_count;
    int *piece_region;
    int *piece_kind;
    double *piece_curve;
    int *piece_source_face;
    double *piece_points;
    int *piece_point_offsets;
} occt_section_result;
int occt_section(const occt_shape *shape, const double origin[3], const double normal[3], const double x_axis[3],
                 double tolerance, occt_section_result *out, occt_status *status);
void occt_section_free(occt_section_result *result);
/// The exact shortest distance between two elements (Measure): each is a point (`kind` 0, `point` x, y, z), a face (1) or an edge (2)
/// at the 1-based `index` of `shape`'s indexed face or edge map; `shape` is ignored for a point and `point` for a face or edge. The
/// two shapes may be different solids. `out` holds the distance and the nearest point on each element. Nothing to free. Returns 1.
typedef struct {
    double distance;
    double from[3];
    double to[3];
} occt_shape_distance;
/// One side of a shortest-distance query: kind 0 a point, 1 a face and 2 an edge of `shape` (1-based `index`), 3 a polyline of `point_count`
/// (at least 2) x, y, z triples in `points` (borrowed for the call), 4 a circle arc from `start` about `axis` by `sweep` (a negative sweep runs clockwise).
typedef struct {
    const occt_shape *shape;
    int kind;
    int index;
    double point[3];
    const double *points;
    int point_count;
    double centre[3];
    double axis[3];
    double start[3];
    double radius;
    double sweep;
} occt_measure_operand;
int occt_shortest_distance(const occt_measure_operand *a, const occt_measure_operand *b, occt_shape_distance *out, occt_status *status);
/// How smoothly the two faces of an edge meet (G-b): the worst position gap (mm), normal angle (radians, outward normals oriented by the
/// faces' orientation in the shape), and normal-curvature gap across the edge over 32 samples. `edge_index` is 1-based in the shape's
/// edge map. An edge that is a seam or has fewer than two distinct faces fails with "This edge doesn't join two faces."
typedef struct {
    double position_gap;
    double angle_gap;
    double curvature_gap;
    double absolute_curvature_gap;
} occt_edge_continuity;
int occt_edge_continuity_of(const occt_shape *shape, int edge_index, occt_edge_continuity *out, occt_status *status);
/// The same grading between the free edge `edge_index` (1-based) of `first`, a sheet, and face `face_index` (1-based) of `second`: samples
/// are projected onto the face (a sample over 1 mm away, or outside the trimmed face, is skipped), curvature signs follow the normals
/// compared up to sign, and the angle is that between A's direction continuing past the edge and B's direction leaving it, so a face
/// folded back over A reads 180 degrees though it shares A's tangent plane. Fewer than half the samples usable is refused. Fails with "The edge must be a surface's
/// free edge." or "The edge doesn't run along that face.".
int occt_edge_continuity_against(const occt_shape *first, int edge_index, const occt_shape *second, int face_index,
                                 occt_edge_continuity *out, occt_status *status);
/// A faceted solid from a closed triangle mesh (implicit spec §4.7): `positions` is `vertex_count` x, y, z triples in millimetres and
/// `triangles` three vertex numbers per face, counter-clockwise seen from outside. A planar face is built per triangle on vertices and edges shared by index
/// (no BRepBuilderAPI_Sewing), same-domain faces are merged (ShapeUpgrade_UnifySameDomain), a shell facing inwards becomes a
/// void of the solid that contains it, and BRepCheck_Analyzer must accept the result. A mesh that is not closed, not a manifold, wound
/// inside out or rejected by the checker fails with the reason in `status`. Several outer surfaces give a compound of solids.
occt_shape *occt_mesh_to_solid(const double *positions, int vertex_count, const unsigned int *triangles, int triangle_count,
                               occt_status *status);
/// A compound of copies-by-reference of the given shapes.
occt_shape *occt_make_compound(const occt_shape *const *shapes, int count, occt_status *status);
/// Reads a STEP file into one shape (a compound for several bodies).
occt_shape *occt_read_step(const char *path, occt_status *status);
/// Reads a STEP model from `size` bytes, in millimetres, as one shape (several roots are a compound). The messages are
/// worded for people: "The STEP model couldn't be read." and "The model contains no shapes.". Returns null on failure; the caller
/// frees the result with occt_shape_free. OpenCascade 7.9 has no IGES stream reader: use occt_read_iges_file.
occt_shape *occt_read_model(const char *data, size_t size, occt_status *status);
/// Reads the IGES file at `path` like occt_read_model ("The IGES model couldn't be read.").
occt_shape *occt_read_iges_file(const char *path, occt_status *status);
/// What a model file holds, sorted (NURBS spec, Import Model): `count` shapes, each a solid (kind 0), a sheet (kind 1: a free shell or
/// face) or a curve (kind 2: a free wire, or a free edge as a wire), in the file's order, read in millimetres. `file_unit_mm` (0 when the file names no length unit OpenCascade can give a factor for) is the
/// length unit the file was written in, in millimetres. The caller takes the shapes it uses (setting the entry to null) and frees
/// the rest with occt_model_shapes_free.
typedef struct {
    occt_shape **shapes;
    int *kinds;
    int count;
    double file_unit_mm;
} occt_model_shapes;
void occt_model_shapes_free(occt_model_shapes *models);
/// Reads a STEP model from `size` bytes, or, when `iges_path` is not null, the IGES file at that path (the bytes are then ignored).
/// Refuses with "The STEP model couldn't be read.", "The IGES model couldn't be read." and "The model contains no shapes.". Returns 1,
/// or 0 with `status` set.
int occt_read_shapes(const char *data, size_t size, const char *iges_path, occt_model_shapes *out, occt_status *status);
/// FOR TESTS ONLY. Writes `shape` as a STEP file at `path` with the file's length unit `unit` ("MM", "INCH", ...).
int occt_test_write_step_units(const occt_shape *shape, const char *path, const char *unit, occt_status *status);
/// A copy of `shape` scaled about the origin: a similarity when the three factors are equal, OpenCascade's general transform
/// otherwise. Faces keep their order in the shape's face map. Every factor must be finite and greater than 0.
occt_shape *occt_scale(const occt_shape *shape, double sx, double sy, double sz, occt_status *status);
/// FOR TESTS ONLY. Writes `shape` as an IGES file at `path` in `unit` ("MM", "IN", ...). Returns 1, or 0 with `status` set.
int occt_test_write_iges(const occt_shape *shape, const char *path, const char *unit, occt_status *status);

/// One piece of a curve for occt_make_curve. kind 0 is a line from `a` to `b`; kind 1 an arc about `a` (centre) with unit normal `b`
/// from `c` (a point on the circle) through `sweep` radians, signed about the normal; kind 2 a B-spline.
typedef struct {
    int kind;
    double a[3];
    double b[3];
    double c[3];
    double radius;
    double sweep;
    int degree;
    int pole_count;
    const double *poles;     // pole_count * 3
    const double *weights;   // pole_count, or null
    int knot_count;
    const double *knots;     // knot_count
    const int *multiplicities; // knot_count
    int periodic;            // spline only: poles and knots are one period's, as OpenCascade keeps them (NS-3)
} occt_curve_piece;

/// What the Swift side reads of a curve (a wire). `polyline` is shim-owned: free it with occt_curve_info_free.
typedef struct {
    int piece_count;
    int is_closed;
    int planar;
    double plane_origin[3];
    double plane_normal[3];
    double plane_x[3];
    double length;
    double min[3];
    double max[3];
    double *polyline;
    int polyline_count;
} occt_curve_info;

/// A wire over `count` pieces that join end to end within 1e-6 mm. Null with `status` set otherwise.
occt_shape *occt_make_curve(const occt_curve_piece *pieces, int count, occt_status *status);
/// A curve through `count` points (xyz triples) of degree 3 (GeomAPI_Interpolate, optional end tangents, never with `closed`) or
/// degree 5 (GeomAPI_PointsToBSpline, no tangents), returned as a one-edge wire. A degree-5 curve more than `max_deviation` mm from
/// any point is refused. `start_tangent` and `end_tangent` are xyz triples or null.
occt_shape *occt_interpolate_curve(const double *points, int count, int degree, int closed, const double *start_tangent,
                                   const double *end_tangent, double max_deviation, occt_status *status);
/// Reads a wire made by the functions above. Returns 1, or 0 with `status` set; free `out->polyline` with occt_curve_info_free.
int occt_curve_info_of(const occt_shape *wire, occt_curve_info *out, occt_status *status);
void occt_curve_info_free(occt_curve_info *info);
/// The wires that `edge_indices` (1-based, in `shape`'s edge map) chain into, as one compound ordered by each wire's lowest edge index.
occt_shape *occt_curves_from_edges(const occt_shape *shape, const int *edge_indices, int count, occt_status *status);
/// The curves where `a` and `b` meet (BRepAlgoAPI_Section, no approximation), chained into wires within 1e-6 mm and returned as one
/// compound (empty when they don't meet): an open wire runs from its lexicographically smaller end, a closed one starts at its smallest
/// vertex, and the wires are ordered by start point (x, then y, then z, within 1e-6 mm; NS-4 R14). The same shape twice is refused.
occt_shape *occt_intersection_curves(const occt_shape *a, const occt_shape *b, occt_status *status);
/// The number of children of a compound made by occt_curves_from_edges, and the child at `index` (0-based).
int occt_compound_child_count(const occt_shape *compound);
occt_shape *occt_compound_child(const occt_shape *compound, int index, occt_status *status);
/// FOR TESTS ONLY. The degree and pole count of the first edge of a wire, which must be a B-spline.
int occt_test_curve_spline_info(const occt_shape *wire, int *degree, int *pole_count, occt_status *status);
/// FOR TESTS ONLY. The shortest distance from the point to the curve (a wire).
double occt_test_curve_distance(const occt_shape *wire, double x, double y, double z, occt_status *status);

/// A B-spline surface's net (NS-3). `poles` is u_count * v_count xyz triples, row-major (pole (i, j) at i * v_count + j);
/// `weights` is null unless rational. `kind` is the face's surface kind before conversion: 0 plane, 1 cylinder, 2 cone, 3 sphere,
/// 4 torus, 5 B-spline, 6 other, 7 Bezier, 8 revolution, 9 extrusion, 10 offset; `converted_from` is that kind when the net was
/// made by conversion, else -1. `normals` (3 per pole, at its Greville point, oriented by the face) only from
/// occt_control_net_of_face. All arrays are shim-owned: free with occt_surface_net_free.
typedef struct {
    int kind;
    int converted_from;
    int degree_u;
    int degree_v;
    int u_count;
    int v_count;
    int periodic_u;
    int periodic_v;
    int rational;
    int knot_u_count;
    int knot_v_count;
    double *poles;
    double *weights;
    double *knots_u;
    int *mult_u;
    double *knots_v;
    int *mult_v;
    double *normals;
} occt_surface_net;

/// The B-spline net of face `face_index` (1-based, in `shape`'s face map), converting any other surface exactly. More than
/// `max_poles` poles (0: no limit) is refused with the pole count marked as a number. Returns 1, or 0 with `status` set.
int occt_control_net_of_face(const occt_shape *shape, int face_index, int max_poles, occt_surface_net *out, occt_status *status);
/// The kind of face `face_index`'s surface and, for a Bezier or B-spline one, its net as it stands (no normals, no conversion
/// of other kinds: `poles` is null for them).
int occt_surface_info(const occt_shape *shape, int face_index, occt_surface_net *out, occt_status *status);
void occt_surface_net_free(occt_surface_net *net);

/// A curve of one piece as one B-spline (NS-3). `converted_from` -1 for a B-spline, 0 line, 1 arc, 2 other. A periodic spline
/// keeps its periodic form and unique poles (`periodic` 1) unless the edge trims it, when it is cut to a clamped segment
/// (`periodic` 0). Free with occt_curve_net_free.
typedef struct {
    int converted_from;
    int periodic;
    int degree;
    int rational;
    int pole_count;
    int knot_count;
    double *poles;
    double *weights;
    double *knots;
    int *multiplicities;
} occt_curve_net;

int occt_control_net_of_curve(const occt_shape *wire, occt_curve_net *out, occt_status *status);
void occt_curve_net_free(occt_curve_net *net);
/// A copy of `shape` with the poles of face `face_index` (1-based) moved: `count` moves, move k naming pole (indices[2k], indices[2k+1])
/// (0-based i along u, j along v, as occt_surface_net lays them out) and the offset offsets[3k..3k+2]. Weights are kept. The face is
/// converted to a B-spline first when it isn't one (as occt_control_net_of_face does), keeps its pcurves, and its edges' 3D curves and
/// vertices are rebuilt on the moved surface; the faces and edges keep their order in the shape's maps. A pole that doesn't exist, or a
/// result BRepCheck_Analyzer rejects (when the input passed it), is refused. Never changes `shape` or geometry it shares.
occt_shape *occt_move_face_poles(const occt_shape *shape, int face_index, const int *indices, const double *offsets, int count,
                                 occt_status *status);
/// 1 when `a` and `b` have the same faces, edges and vertices in their maps: the same counts, each edge between the same vertex indices
/// (first and last, as the edge runs), and each face's edges in the same order. 0 otherwise (or on a null shape).
int occt_same_structure(const occt_shape *a, const occt_shape *b, occt_status *status);
/// Sets `*folds` to 1 when face `face_index` (1-based) folds over itself: on a 33 x 33 grid of its parameter range (samples inside the
/// face only, none on a degenerate edge's point) two neighbouring unit normals have a negative dot product, or one sample's
/// |du x dv| is under 1e-12 x the face's bounding size squared and its neighbour's is not.
int occt_surface_folds(const occt_shape *shape, int face_index, int *folds, occt_status *status);
/// FOR TESTS ONLY. The same shape with the opposite orientation (its faces are TopAbs_REVERSED), geometry untouched.
occt_shape *occt_test_reversed_copy(const occt_shape *shape, occt_status *status);
/// FOR TESTS ONLY. A sheet of one face of the given `degree` (poles in the plane z = 0, uniform knots) with `u_count` x
/// `v_count` poles.
occt_shape *occt_test_bspline_sheet(int u_count, int v_count, int degree, occt_status *status);
/// The one tolerance (mm) of control-net editing: poles this close count as one point, and an apex or a seam may open no more than this
/// over what it was.
double occt_net_coincidence(void);
/// FOR TESTS ONLY. The one-face sheet with the poles of its collapsed boundary row (an apex) moved apart on a circle of radius `distance`
/// about their point, in the plane across the row's direction. Bypasses the apex guard.
occt_shape *occt_test_spread_apex(const occt_shape *shape, double distance, occt_status *status);
/// FOR TESTS ONLY. A periodic degree-3 tube of radius 10 (eight poles round, 10 mm tall), one face over `fraction` (0, 1] of its period.
occt_shape *occt_test_partial_periodic_sheet(double fraction, occt_status *status);
/// FOR TESTS ONLY. Over every pole's Greville point of face `face_index`'s B-spline net: the largest |normal . tangent| / |tangent|
/// and the largest distance from the surface point there to the pole.
int occt_test_net_gaps(const occt_shape *shape, int face_index, double *normal_error, double *pole_gap, occt_status *status);

/// What a sheet builder says about the names of its boundary edges (NURBS spec, Task 3). `kind` 0 none (the edge is
/// not named), 1 start, 2 end, 3 rail (`a` 0 for an open curve's start, 1 for its end), 4 piece (`a` the loop, `b` the
/// segment), 5 imported (`a` the edge's index in the file's edge map).
typedef struct {
    int kind;
    int a;
    int b;
} occt_boundary_role;

/// One role per edge of the returned shape, in its TopExp::MapShapes(TopAbs_EDGE) order (index n is edge map index
/// n + 1), so the table lines up with `occt_topology.edges`. Free with occt_boundary_roles_free.
typedef struct {
    occt_boundary_role *roles;
    int count;
} occt_boundary_roles;

void occt_boundary_roles_free(occt_boundary_roles *roles);

/// A planar surface (one face) bounded by closed `loops` (wires made by occt_make_curve), all in `plane` within 1e-6 mm:
/// one outer loop that contains every other, which are holes. The result's loop 0 is the outer one and the holes follow in
/// input order. `plane`'s normal gives the face its direction. History: the face is OCCT_FROM_START_CAP. Roles: loop i's
/// edge k (in wire order) is kind 4 with a = i, b = k. Refuses with "The curves must be one outer loop with holes inside
/// it." and "The curve isn't closed, so it can't be filled.".
occt_shape *occt_planar_surface(const occt_shape *const *loops, int loop_count, const occt_plane *plane,
                                occt_history *history, occt_boundary_roles *roles, occt_status *status);

/// The sheet swept by `curve` (a wire) moved along `direction` by `distance` (both sides when `symmetric`: from -distance to
/// +distance). History: the face from piece k is OCCT_FROM_SEGMENT (operand 0, index k). Roles: start and end edges (kinds 1, 2), and
/// for an open curve the edges traced by its first and last vertex (kind 3, a = 0 and 1). Refuses with "The direction can't be zero.".
occt_shape *occt_extrude_curve(const occt_shape *curve, const double direction[3], double distance, int symmetric,
                               occt_history *history, occt_boundary_roles *roles, occt_status *status);
/// The sheet swept by turning `curve` about the axis through `angle` radians (0 < angle <= 2π). History as occt_extrude_curve. Roles:
/// start and end edges only for a partial turn; rails as occt_extrude_curve, except one that collapses onto the axis, which is not named.
occt_shape *occt_revolve_curve(const occt_shape *curve, const double axis_origin[3], const double axis_direction[3],
                               double angle, occt_history *history, occt_boundary_roles *roles, occt_status *status);
/// The surface through `count` section curves (wires; ThruSections with isSolid false). `closed` returns to the first section.
/// History: the face from piece k of the first section is OCCT_FROM_SEGMENT (0, k). Roles: start and end edges unless `closed`;
/// for open sections the edges joining the sections' first vertices are rail 0 and their last vertices rail 1.
occt_shape *occt_loft_curves(const occt_shape *const *sections, int count, int ruled, int closed,
                             occt_history *history, occt_boundary_roles *roles, occt_status *status);

/// The shape made by sweeping `count` profile curves (wires) along `path` (a wire): BRepOffsetAPI_MakePipeShell, each profile added
/// as given (no contact, with correction). `mode` 0 keeps the Frenet frame, 1 fixes `binormal`, 2 follows `guide` as a second rail
/// (a wire that must touch every profile: "The rail must touch every profile."), 3 keeps the profile against `guide` as a guide
/// surface. `twist_degrees` (|twist| at most 3,600; refused beyond: "The twist must be between −3,600° and 3,600°.") turns the profile
/// that much along the path through an auxiliary spine, with mode 0 or 1 only ("Twist can't be combined with a rail or a guide surface."). An `end_scale` other than 1
/// scales the one profile linearly along the path (refused with several: "An end scale needs exactly one profile."). With `make_solid`
/// and every profile closed the result is a solid: history OCCT_FROM_START_CAP / OCCT_FROM_END_CAP for the caps; otherwise a sheet.
/// Sides are OCCT_FROM_SEGMENT (operand 0, index = the profile's piece). Roles: start and end edges (kinds 1, 2) and, for open
/// profiles, rails 0 and 1. Refuses "The sweep runs into itself; shorten the path or shrink the profile." and "The sweep couldn't be
/// made along this path.".
occt_shape *occt_sweep_curves(const occt_shape *const *profiles, int count, const occt_shape *path, int mode,
                              const double binormal[3], double end_scale, int make_solid, const occt_shape *guide,
                              double twist_degrees, occt_history *history,
                              occt_boundary_roles *roles, occt_status *status);

/// A flag another thread sets to stop a long shim call; the call polls it between steps and refuses with "The operation was cancelled.".
typedef struct occt_cancel occt_cancel;
occt_cancel *occt_cancel_new(void);
void occt_cancel_set(occt_cancel *cancel);
void occt_cancel_free(occt_cancel *cancel);

/// The Gordon surface through a grid of curves (wires): `u_count` curves one way and `v_count` the other, in any order and
/// direction (they are sorted and turned here, the first u and the first v curve fixing the orientation; each pair must cross within
/// `tolerance`). A curve that runs past the border curves is trimmed to them. One face, non-rational, at most 100,000 control points
/// ("The network is too detailed: ..."). History: the face is OCCT_FROM_SEGMENT (0, 0). Roles: the first and last u curve's edges are
/// kinds 1 and 2, the first and last v curve's are kind 3 with a = 0 and 1 (in the sorted order). Numbers in refusals are wrapped in
/// \x01 ... \x02 so the caller can write them in its locale. `cancel` may be NULL. Refuses with sentences such as
/// "u curve 2 and v curve 3 miss each other by 0.4 mm.".
occt_shape *occt_network_surface(const occt_shape *const *u_curves, int u_count, const occt_shape *const *v_curves,
                                 int v_count, double tolerance, const occt_cancel *cancel, occt_history *history,
                                 occt_boundary_roles *roles, occt_status *status);

/// A patch (one face) that fills the closed loop of bounding pieces: the edges of each of `curve_count` curves (wires, in wire
/// order) followed by `edge_count` edges of `part` (`edge_indices`, 1-based in part's edge map, each with the 1-based face of
/// `part` it is held tangent to in `face_indices`, or 0 to hold it to position only). Between 1 and 16 pieces must chain end
/// to end within 1e-4 mm into exactly one loop. The patch also passes within 1e-3 mm of each of `points` (3 doubles each) and follows `interior_curves` (wires). `continuity` is 0 (G0), 1 (G1) or 2 (G2: three or four pieces and no points or interior curves; a piece on a sheet is held curvature continuous by a degree-17 triangular or biquintic patch of our own, the rest in position only; with no piece on a sheet it is the G0 fill); the pieces' continuity is checked by the caller.
/// `piece_order[k]` is set to the input index (0-based) of the loop's piece k, starting from input piece 0; `piece_capacity` must be
/// at least 16 and `total_pieces` is set to the number of input pieces. History: the face is OCCT_FROM_START_CAP. Roles: loop piece
/// k is kind 4 with a = 0 and b = k. Numbers in refusals are wrapped in \x01 ... \x02. `cancel` may be NULL.
occt_shape *occt_boundary_patch(const occt_shape *const *curves, int curve_count, const occt_shape *part,
                                const int *edge_indices, const int *face_indices, int edge_count, const double *points,
                                int point_count, const occt_shape *const *interior_curves, int interior_count,
                                int continuity, const occt_cancel *cancel, int *piece_order, int piece_capacity,
                                int *total_pieces, occt_history *history, occt_boundary_roles *roles, occt_status *status);

/// A copy of `shape` whose face `face_index` (1-based) is refitted by least squares to a non-rational B-spline of the given degrees
/// and span counts (equal spans; clamped, or periodic with `spans` poles in a direction the source is periodic in; fewer than degree + 1 spans there is refused) over the parameter range of the face's own B-spline net (a surface of another kind is
/// converted exactly first), so the face keeps its pcurves, trims and the order of faces and edges. Samples per direction are
/// 4 x (degree + spans) + 1, fitted rows then columns; `*deviation` is the largest distance from the source surface to the result
/// on a grid twice as dense inside the face's parameter box. Refuses a degree outside 1 to 11, under one span, over 100,000 poles
/// (numbers wrapped in \x01 ... \x02) and a result BRepCheck_Analyzer rejects (when the input passed it). `cancel` may be NULL.
occt_shape *occt_rebuild_face(const occt_shape *shape, int face_index, int degree_u, int degree_v, int spans_u, int spans_v,
                              const occt_cancel *cancel, double *deviation, occt_status *status);
/// A curve (wire) of any pieces fitted by one non-rational B-spline of `degree` and `spans` equal spans: clamped with its end poles pinned to
/// the curve's ends, or periodic (`out->periodic` 1, `spans` poles) when the wire is one edge of a periodic B-spline run for its period
/// (fewer than degree + 1 spans is refused). Samples 4 x (degree + spans) + 1, evenly in the parametrization by arc length between pieces. Fills `out` (free with occt_curve_net_free) and `*deviation`
/// (largest distance from the source on a grid twice as dense). `cancel` may be NULL.
int occt_rebuild_curve(const occt_shape *wire, int degree, int spans, const occt_cancel *cancel, occt_curve_net *out,
                       double *deviation, occt_status *status);

/// A copy of `shape` whose one face `face_index` (1-based) is grown by `length` mm across the sides of `edge_indices` (1-based, in the
/// shape's edge map; two edges on one side count once). Each must be a free edge on an untrimmed iso boundary of the face's surface (a face
/// of another kind is converted to a B-spline exactly) and every other edge must be untrimmed too. `mode` 0 is Natural
/// (GeomLib::ExtendSurfByLength, curvature continuous), 1 is Linear (a span appended straight along the cross tangent, built in
/// homogeneous coordinates so a rational surface is not approximated; refused with "weakens too fast across it" when the weights would
/// fall toward zero). The face keeps its edges, in order; the old surface is kept within 1e-7 mm. The join is graded
/// (G2 or G1) and a miss, a surface that moves, a trim and a result BRepCheck_Analyzer rejects (when the input passed it) are refused.
occt_shape *occt_extend_face(const occt_shape *shape, int face_index, const int *edge_indices, int edge_count, double length, int mode,
                             occt_status *status);
/// Match Surface (NS-4, R9): the sheet's one face (`face_index`, 1-based) changed along its open edge `edge_index` so that it meets the edge
/// `target_edge_index` of `target` at `continuity` (0, 1 or 2), by the rows of its control net nearest the edge (a rational net keeps its
/// weights); the opposite edge, the face's edges and their order are kept. The target face is the one the sheet continues. Each result is
/// graded and the spans along the edge doubled up to 5 times; a miss, ends over 0.01 mm apart, a closed or two-face edge, a trimmed edge and
/// a result BRepCheck_Analyzer rejects are refused in sentences. `cancel` may be NULL; it is polled before each refinement pass and
/// before each grade.
occt_shape *occt_match_face(const occt_shape *shape, int face_index, int edge_index, const occt_shape *target, int target_edge_index,
                            int continuity, const occt_cancel *cancel, occt_status *status);
/// Blend Surface (NS-4, R10): a new sheet (one face) joining edge `first_edge` of `first` to edge `second_edge` of `second` (1-based in
/// each shape's edge map; the shapes may be one). Each end has a `continuity` (1 or 2) and a `bulge` (0.1 to 2, the section's tangent length
/// as a multiple of the circular one); the face an end continues is the one whose leaving direction points most toward the other edge. Sections
/// join the edges' points at equal arc-length fractions (the second edge turned when that shortens the ends), are quintic Beziers matching
/// position, tangent and (G2) normal curvature, and are skinned along the edges, 9 to 129 of them, until both ends grade as asked. History: the
/// face is OCCT_FROM_SEGMENT (0, 0). Roles: the first edge's side is kind 1, the second's kind 2, the sides from the edges' starts are kind 3
/// with a = 0 and 1. `cancel` may be NULL. Refuses in sentences ("The edges touch; a blend needs a gap between them.", ...).
occt_shape *occt_blend_surface(const occt_shape *first, int first_edge, int first_continuity, double first_bulge,
                               const occt_shape *second, int second_edge, int second_continuity, double second_bulge,
                               const occt_cancel *cancel, occt_history *history, occt_boundary_roles *roles, occt_status *status);
/// FOR TESTS ONLY. The largest distance from the surface at nine points of each pcurve (both of a seam) of face `face_index` (1-based)
/// to that edge's 3D curve.
int occt_test_pcurve_gap(const occt_shape *shape, int face_index, double *gap, occt_status *status);
/// FOR TESTS ONLY. The parametric speed (the length of the partial derivative across the direction) of the B-spline face `face_index`
/// (1-based) on each side of its last interior knot (`in_u` 1 for the u direction), at the middle of the other direction.
int occt_test_knot_speeds(const occt_shape *shape, int face_index, int in_u, double *before, double *after, occt_status *status);

/// One face of a split sheet (NS-4, R2): `source_face` is the 1-based face of the input sheet it came from, `piece` its connected set
/// (0-based, in no order), `inside` 1 or 0 against a closed cutter and -1 when the cutter is not closed (or the face could not be
/// classified), and `pair_start` / `pair_count` its (element, side) pairs in `pairs`.
typedef struct {
    int source_face;
    int piece;
    int inside;
    int pair_start;
    int pair_count;
} occt_split_face;
/// A cutter element a face borders and the side it lies on: `side` 0 front, 1 back, 2 inside, 3 outside. For curves `element` is the
/// piece's number over every curve's edges in input order (0-based); for a body it is the 0-based face of the body's face map.
typedef struct {
    int element;
    int side;
} occt_split_pair;
/// One edge of the result: `source_edge` the 1-based edge of the input it is (a piece of), or 0 for a cut edge, whose cutter element is
/// `element` (-1 when none could be found).
typedef struct {
    int source_edge;
    int element;
} occt_split_edge;
typedef struct {
    occt_split_face *faces;
    int face_count;
    occt_split_pair *pairs;
    int pair_count;
    occt_split_edge *edges;
    int edge_count;
    int piece_count;
    /// 1 when every face has an `inside` of 0 or 1 (the cutter is closed curves in planes the projection crosses, or a closed solid).
    int has_inside;
    /// 1 when part of the cutter was dropped because it ended inside a face.
    int dangling;
} occt_split_result;
void occt_split_result_free(occt_split_result *result);

/// `sheet` divided by a cutter (NS-4, R2, R4, R7). `kind` 0 projects `curves` (wires) along `direction` (a prism sized from the curves'
/// and the sheet's extents along it), 1 projects them along the sheet's normals, 2 cuts with `body` (a sheet or a closed solid).
/// The result is a shell per connected set of the pieces' faces sharing their edges (a compound when there are several); `out` says where each face and edge came from, the cutter element
/// each cut edge lies on and the (element, side) pairs of each face. Refuses "Trim and Split take a sheet; this is a closed solid.",
/// "The direction can't be zero." and "The cutter doesn't cut the surface.". A cut that ends inside a face is dropped (`out->dangling`).
/// `cancel` may be NULL.
occt_shape *occt_split_sheet(const occt_shape *sheet, int kind, const occt_shape *const *curves, int curve_count,
                             const double direction[3], const occt_shape *body, const occt_cancel *cancel,
                             occt_split_result *out, occt_status *status);
/// One shell of the given faces (`face_indices`, 1-based in `sheet`'s face map) sharing their edges, every face and edge the same shape as
/// in `sheet`. `out` has `source_face` and `source_edge` per output face and edge; the other fields are zero.
occt_shape *occt_sub_sheet(const occt_shape *sheet, const int *face_indices, int count, occt_split_result *out, occt_status *status);

/// One face of a piece of a split solid (NS-5, R13). Faces are listed piece by piece, each piece's in the order of its own face map (so the
/// k-th entry of piece p is face k of the p-th child of the returned compound). `source_operand` is 0 for a face of the divided solid or
/// 1 + the tool's position for a cut face, and `source_face` the 1-based face of that body it is (a piece of); `pair_start` /
/// `pair_count` index the (element, side) pairs, `element` being the tool faces' number over every tool's face map in input order and
/// `side` 0 front, 1 back, 2 inside, 3 outside (inside and outside for a tool face of a closed solid).
typedef struct {
    int piece;
    int source_operand;
    int source_face;
    int pair_start;
    int pair_count;
} occt_split_solid_face;
typedef struct {
    occt_split_solid_face *faces;
    int face_count;
    occt_split_pair *pairs;
    int pair_count;
    int piece_count;
    /// 1 when part of a tool was dropped because it doesn't cross the solid from side to side.
    int dangling;
} occt_split_solid_result;
void occt_split_solid_result_free(occt_split_solid_result *result);

/// `solid` (closed) divided by `tools` (sheets or closed solids, each one shape) with the Splitter (NS-5, R13, R15). The result is a
/// compound of the pieces' solids; `out` says where every face of every piece came from and the (element, side) pairs it carries. A tool
/// face that cuts nothing across is removed from the piece that holds it (`out->dangling`). Refuses "The tools don't cut the solid into
/// pieces." and "The tools couldn't divide this solid." (the splitter failed or a piece is invalid). `cancel` may be NULL.
occt_shape *occt_split_solid(const occt_shape *solid, const occt_shape *const *tools, int tool_count, const occt_cancel *cancel,
                             occt_split_solid_result *out, occt_status *status);

/// Sews the faces of `bodies` (sheets and solids alike, in order) at `tolerance` (NS-5, R6). A face that coincides with an earlier face is
/// not sewn and stays loose in the result. Each closed shell becomes a solid; the rest stay sheets. `history` is OCCT_FROM_FACE per result face
/// (operand = the body's position, index its 1-based face); `edges` says which input edges (1-based) each result edge was made from.
/// `solids`, `sheets` and `unclosable` are counted as the plan's R6 says. Refuses "Sew needs at least one surface.", "The tolerance must
/// be greater than 0." and "Sewing made an invalid shape; try a smaller tolerance.". `cancel` may be NULL.
occt_shape *occt_sew(const occt_shape *const *bodies, int count, double tolerance, const occt_cancel *cancel,
                     occt_history *history, occt_edge_history *edges, int *solids, int *sheets, int *unclosable,
                     occt_status *status);
/// `sheet` offset by `distance` mm along its normals (NS-5, Task 4; R7, R8): a shell of faces, each source face's image, with `history`
/// OCCT_FROM_FACE (operand 0, the source face) and `edges` pairing each source boundary edge (index) with its image (out_edge). Refuses
/// "The distance can't be 0.", "The offset couldn't be built." (nothing valid at this distance: tolerances over 0.01 mm count) and "The
/// offset changed the surface's open edges, so it can't be offset.". `cancel` may be NULL.
occt_shape *occt_offset_surface(const occt_shape *sheet, double distance, const occt_cancel *cancel, occt_history *history,
                                occt_edge_history *edges, occt_status *status);
/// The smallest positive distance (written to `limit`) at which an offset of `sheet` along its normals (`sign` > 0) or against them
/// (`sign` < 0) reaches a centre of curvature (R8); +infinity when none.
int occt_offset_limit(const occt_shape *sheet, int sign, double *limit, occt_status *status);
/// Whether two different pieces of `sheet` have edges that sewing at 0.01 mm would join (R11), written to `touching`.
int occt_touching_pieces(const occt_shape *sheet, int *touching, occt_status *status);
/// `sheet` grown into a solid `distance` mm thick (NS-5, Task 5; R3, R7): `side` 0 puts the sheet at the start and the far face at
/// +distance, 1 puts the start face at -distance and the sheet at the end, 2 puts them at -/+ distance / 2. `history` has OCCT_FROM_FACE
/// (operand 0, the source face) with OCCT_FROM_START_CAP (the face looking against the normal) or OCCT_FROM_END_CAP on each side face, and
/// OCCT_FROM_EDGE (operand 0, the source boundary edge) on each wall. The result is valid, closed, with tolerances within 0.01 mm and
/// positive volumes. Refuses "The distance must be greater than 0.", "The offset couldn't be built." and "The offset changed the
/// surface's open edges, so it can't be offset.". `cancel` may be NULL.
occt_shape *occt_thicken(const occt_shape *sheet, double distance, int side, const occt_cancel *cancel, occt_history *history,
                         occt_status *status);
/// One source edge of a cap's outer loop (NS-5, R12): `face` is the cap's 1-based face in the result, `edge` the input's 1-based edge.
typedef struct {
    int face;
    int edge;
} occt_cap_loop_edge;

typedef struct {
    occt_cap_loop_edge *records;
    int count;
} occt_cap_loops;

void occt_cap_loops_free(occt_cap_loops *loops);

/// `sheet`'s closed free loops that are flat (every sample within `flatness` mm of the plane through the samples' centroid with Newell's normal; a flat loop with a planar face of the sheet already in its plane stays open and is not counted in `not_flat`) capped with planar faces
/// (NS-5, Task 6; R12, R17): loops in one plane are nested even-odd into faces with holes, the caps are sewn to the sheet at 0.01 mm and
/// every closed shell made a solid. The input's `TopAbs_SOLID`s are set aside and put back unchanged. `history` is OCCT_FROM_FACE (operand 0,
/// the input face) for every face that came from one; `edges` is sew's R5 edge records; `loops` lists each cap's outer-loop source edges.
/// `capped` counts the caps made and `not_flat` the closed free loops left open. Refuses "Capping made an invalid shape; the holes can't be
/// capped.". `cancel` may be NULL.
occt_shape *occt_cap_planar_holes(const occt_shape *sheet, double flatness, const occt_cancel *cancel, occt_history *history,
                                  occt_edge_history *edges, occt_cap_loops *loops, int *capped, int *not_flat, occt_status *status);
/// FOR TESTS ONLY. A one-face non-periodic cubic B-spline sheet wrapped round a circle of `radius` whose first and last pole columns coincide.
occt_shape *occt_test_wrapped_sheet(double radius, double height, occt_status *status);
/// FOR TESTS ONLY. A copy of `shape` that shares no geometry or topology with it.
occt_shape *occt_test_independent_copy(const occt_shape *shape, occt_status *status);
/// FOR TESTS ONLY. The six faces of a `size` mm box, each copied on its own, as one compound; the top face moved `move_top` mm along z and,
/// when `double_top` is nonzero, written a second time last; with `as_solid` nonzero the faces are one unchecked solid with gaps.
occt_shape *occt_test_loose_box_faces(double size, double move_top, int double_top, int as_solid, occt_status *status);

/// FOR TESTS ONLY. The largest tolerance of any edge of `shape`.
int occt_test_max_edge_tolerance(const occt_shape *shape, double *tolerance, occt_status *status);

#ifdef __cplusplus
}
#endif

#endif
