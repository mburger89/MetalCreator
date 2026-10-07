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
/// edges, 0-based for profile segments).
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

typedef struct {
    occt_plane plane;
    const occt_segment *segments;
    int segment_count;
} occt_profile;

/// Extrudes the profile along its plane normal by `distance`. History: start/end caps and
/// one OCCT_FROM_SEGMENT record per side face (index = segment).
occt_shape *occt_extrude(const occt_profile *profile, double distance, occt_history *history, occt_status *status);

/// Boolean of `a` with `tools` (op 0 fuse, 1 cut, 2 common). History operands: 0 = a, i+1 = tools[i].
occt_shape *occt_boolean(int op, const occt_shape *a, const occt_shape *const *tools, int tool_count,
                         occt_history *history, occt_status *status);
/// Rotates about the axis (if has_rotation) and then translates. History operand 0 = shape.
occt_shape *occt_transform(const occt_shape *shape, const double translation[3], int has_rotation,
                           const double axis_origin[3], const double axis_direction[3], double angle,
                           occt_history *history, occt_status *status);

#ifdef __cplusplus
}
#endif

#endif
