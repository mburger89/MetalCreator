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

double occt_volume(const occt_shape *shape);
int occt_face_count(const occt_shape *shape);
int occt_edge_count(const occt_shape *shape);
/// Length of the edge at 1-based `index` in OCCT's indexed edge map, or -1 if out of range.
double occt_edge_length(const occt_shape *shape, int index);

#ifdef __cplusplus
}
#endif

#endif
