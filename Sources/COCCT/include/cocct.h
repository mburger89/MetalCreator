#ifndef COCCT_H
#define COCCT_H

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

typedef struct {
    double volume;
    double area;
    double centroid[3];
    double min[3];
    double max[3];
} occt_properties;

int occt_read_properties(const occt_shape *shape, occt_properties *out, occt_status *status);
/// The shape's tight axis-aligned bounds, without computing mass properties. Returns 1 on success.
int occt_read_bounds(const occt_shape *shape, double min[3], double max[3], occt_status *status);

/// Surface kinds: 0 plane, 1 cylinder, 2 cone, 3 sphere, 4 torus, 5 bspline, 6 other.
typedef struct {
    int kind;
    int has_normal;
    double normal[3];
    double area;
    double centroid[3];
} occt_face_info;

/// Curve kinds: 0 line, 1 circle, 2 ellipse, 3 bspline, 4 other.
/// Convexity: 0 convex, 1 concave, 2 smooth, 3 unknown.
/// face_a/face_b: 1-based face indices; equal for a seam; both 0 for a free edge.
typedef struct {
    int kind;
    int has_direction;
    double direction[3];
    double length;
    double midpoint[3];
    int convexity;
    int face_a;
    int face_b;
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
/// kind 1 = counter-clockwise arc around (cx,cy) with `radius` from angle `start` to `end` (radians).
typedef struct {
    int kind;
    double x0, y0, x1, y1;
    double cx, cy, radius, start, end;
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

/// Fillets the edges (1-based indices) with `radius`. History operand 0 = shape:
/// OCCT_FROM_FACE for kept/modified faces, OCCT_FROM_EDGE (index = input edge) for blend faces.
occt_shape *occt_fillet(const occt_shape *shape, const int *edge_indices, int count, double radius,
                        occt_history *history, occt_status *status);
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

int occt_tessellate(const occt_shape *shape, double tolerance, occt_mesh *out, occt_status *status);
void occt_mesh_free(occt_mesh *mesh);
/// A compound of copies-by-reference of the given shapes.
occt_shape *occt_make_compound(const occt_shape *const *shapes, int count, occt_status *status);
/// Reads a STEP file into one shape (a compound for several bodies).
occt_shape *occt_read_step(const char *path, occt_status *status);

#ifdef __cplusplus
}
#endif

#endif
