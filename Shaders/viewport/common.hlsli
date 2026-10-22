// The viewport's shared HLSL declarations (cross-platform spec section 4, plan xp-3). Mirrors of the Swift structs in
// Sources/CreatorViewport/Render; GPUDataTests pins their strides. Every member is a float4 or uint4 (or a scalar after
// them), never a float3: that is the same layout in a constant buffer, a structured buffer and Swift's SIMD types.
//
// SDL_GPU's binding spaces (SDL_CreateGPUShader): a vertex stage reads storage buffers in space0 and uniforms in space1; a
// fragment stage reads samplers in space2 and uniforms in space3.

/// The camera. `viewProjection` and `view` are column-major as `Matrix4`: four columns, each a float4.
struct FrameUniforms {
    float4 viewProjection[4];
    float4 view[4];
    float4 eye;
    float4 forward;
    /// x, y: the render target's size in pixels; z: asfloat(isOrthographic); w: unused.
    float4 tail;
};

float4 mulColumns(float4 m[4], float4 v) {
    return m[0] * v.x + m[1] * v.y + m[2] * v.z + m[3] * v.w;
}

struct MeshVertex {
    float4 position;
    float4 normal;
    uint4 face;
};

/// pickBase: PickID.base for the solid's faces (ID pass). ghost: 0 opaque, 1 the blended ghost.
struct DrawUniforms {
    uint pickBase;
    uint ghost;
    uint faceCount;
    float padding;
};

struct ShadeUniforms {
    float4 light;
    float4 dark;
    float4 hover;
    float4 selection;
    float4 warning;
};

struct LineInstance {
    float4 a;
    float4 b;
    float4 color;
    float width;
    uint id;
    uint padding0;
    uint padding1;
};

struct LineUniforms {
    float widthOverride;
    float depthBias;
    float padding0;
    float padding1;
};

struct GridUniforms {
    float4 centerExtentSpacing; // x, y: center; z: extent; w: spacing
    float4 minorColor;
    float4 majorColor;
};

struct FillVertex {
    float4 position;
    float4 color;
};

struct CubeVertex {
    float4 position;
    float4 color;
    float2 uv;
    float2 padding;
    float4 labelRect;
};

/// The cut view's plane: a point is cut away when dot(plane.xyz, p) + plane.w > 0. `enabled` is 0 for no cut.
struct ClipUniforms {
    float4 plane;
    uint4 enabled;
};

bool clipped(ClipUniforms clip, float3 world) {
    return clip.enabled.x != 0u && dot(clip.plane.xyz, world) + clip.plane.w > 0.0;
}

struct FieldRampUniforms {
    float4 low;
    float4 mid;
    float4 high;
    float4 range;
};

/// FieldRamp.color(at:) in Swift: low to mid up to the middle value, mid to high above it, held beyond the ends.
float3 fieldRamp(FieldRampUniforms ramp, float value) {
    if (value <= ramp.range.y) {
        float span = ramp.range.y - ramp.range.x;
        float t = span > 0.0 ? saturate((value - ramp.range.x) / span) : 1.0;
        return lerp(ramp.low.rgb, ramp.mid.rgb, t);
    }
    float span = ramp.range.z - ramp.range.y;
    float t = span > 0.0 ? saturate((value - ramp.range.y) / span) : 1.0;
    return lerp(ramp.mid.rgb, ramp.high.rgb, t);
}
