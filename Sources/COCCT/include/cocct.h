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

#ifdef __cplusplus
}
#endif

#endif
