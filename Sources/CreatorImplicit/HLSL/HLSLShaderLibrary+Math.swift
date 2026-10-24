/// Sine, cosine and arctangent to about one ulp on every driver, and unsigned 64-bit arithmetic in two words (plan xp-c, X-C6). Metal's
/// engine uses
/// `precise::` and `ulong`; Vulkan promises only an absolute 2^-11 for `sin`, and `uint64_t` needs a device feature SDL_GPU does not
/// report. The
/// reduction is Cody-Waite in three parts of pi/2; the polynomials are Cephes' sinf, cosf and atanf (Stephen L. Moshier, public domain).
extension HLSLShaderLibrary {
    static let math = """
    // Sine, cosine and arctangent to about one ulp on every driver (plan xp-c, user decision X-C6). Vulkan promises only an absolute
    // 2^-11 for sin on
    // [-pi, pi] and Direct3D says less, while a TPMS wall is scaled by cell / 2pi: 2^-11 would be about 4e-4 mm at a 5 mm cell, against
    // the 1e-4 mm the
    // GPU is held to. The reduction is Cody-Waite in three parts of pi/2 (the first two exact in a float product for |q| < 2^15); the
    // polynomials are
    // Cephes' sinf, cosf and atanf (Stephen L. Moshier, public domain). The arguments the lattices give are under 13 (tpmsRaw's 2q),
    // far inside that.

    void reduceQuarter(float x, out float y, out int quadrant) {
        precise float q = round(x * 0.636619772367581343f);
        y = ((x - q * 1.5703125f) - q * 4.837512969970703125e-4f) - q * 7.54978995489188216e-8f;
        quadrant = int(q);
    }

    precise float sinPolynomial(float y) {
        precise float z = y * y;
        return ((-1.9515295891e-4f * z + 8.3321608736e-3f) * z - 1.6666654611e-1f) * z * y + y;
    }

    precise float cosPolynomial(float y) {
        precise float z = y * y;
        return ((2.443315711809948e-5f * z - 1.388731625493765e-3f) * z + 4.166664568298827e-2f) * z * z - 0.5f * z + 1.0f;
    }

    precise float accSin(float x) {
        precise float y;
        int quadrant;
        reduceQuarter(x, y, quadrant);
        precise float s = sinPolynomial(y), c = cosPolynomial(y);
        int k = quadrant & 3;
        return k == 0 ? s : (k == 1 ? c : (k == 2 ? -s : -c));
    }

    precise float accCos(float x) {
        precise float y;
        int quadrant;
        reduceQuarter(x, y, quadrant);
        precise float s = sinPolynomial(y), c = cosPolynomial(y);
        int k = quadrant & 3;
        return k == 0 ? c : (k == 1 ? -s : (k == 2 ? -c : s));
    }

    precise float3 accSin3(float3 v) { return float3(accSin(v.x), accSin(v.y), accSin(v.z)); }
    precise float3 accCos3(float3 v) { return float3(accCos(v.x), accCos(v.y), accCos(v.z)); }

    precise float accAtan(float x) {
        precise float sign = x < 0.0f ? -1.0f : 1.0f;
        precise float t = abs(x);
        precise float offset = 0.0f;
        if (t > 2.414213562373095f) {
            offset = HALF_PI_F;
            t = -1.0f / t;
        } else if (t > 0.4142135623730950f) {
            offset = QUARTER_PI_F;
            t = (t - 1.0f) / (t + 1.0f);
        }
        precise float z = t * t;
        precise float series = (((8.05374449538e-2f * z - 1.38776856032e-1f) * z + 1.99777106478e-1f) * z - 3.33329491539e-1f) * z * t + t;
        return sign * (offset + series);
    }

    // atan2 as IEEE 754 and the CPU's Double have it, signed zeros included: atan2(+0, -1) = pi, atan2(-0, -1) = -pi, atan2(+-0, +0) = +-0.
    precise float accAtan2(float y, float x) {
        bool yNegative = (asuint(y) & 0x80000000u) != 0u;
        bool xNegative = (asuint(x) & 0x80000000u) != 0u;
        if (x == 0.0f) {
            if (y == 0.0f) { return xNegative ? (yNegative ? -PI_F : PI_F) : y; }
            return yNegative ? -HALF_PI_F : HALF_PI_F;
        }
        precise float angle = accAtan(y / x);
        if (xNegative) { angle += yNegative ? -PI_F : PI_F; }
        return angle;
    }

    // Unsigned 64-bit arithmetic in two 32-bit words (plan xp-c, user decision X-C6): the noise's SplitMix64 hash needs it, and
    // uint64_t needs a device
    // feature (shaderInt64) SDL_GPU neither enables nor reports. Exact, so a draw is bit for bit FieldNoise's on the CPU.

    struct U64 {
        uint hi;
        uint lo;
    };

    U64 u64(uint hi, uint lo) {
        U64 value;
        value.hi = hi;
        value.lo = lo;
        return value;
    }

    U64 u64Add(U64 a, U64 b) {
        uint lo = a.lo + b.lo;
        return u64(a.hi + b.hi + (lo < a.lo ? 1u : 0u), lo);
    }

    U64 u64Xor(U64 a, U64 b) { return u64(a.hi ^ b.hi, a.lo ^ b.lo); }
    U64 u64Or(U64 a, U64 b) { return u64(a.hi | b.hi, a.lo | b.lo); }

    // 0 < shift < 64.
    U64 u64Shr(U64 a, uint shift) {
        if (shift >= 32u) { return u64(0u, a.hi >> (shift - 32u)); }
        return u64(a.hi >> shift, (a.lo >> shift) | (a.hi << (32u - shift)));
    }

    U64 u64Shl(U64 a, uint shift) {
        if (shift >= 32u) { return u64(a.lo << (shift - 32u), 0u); }
        return u64((a.hi << shift) | (a.lo >> (32u - shift)), a.lo << shift);
    }

    // The full 64-bit product of two 32-bit words, by 16-bit halves.
    U64 u64Product(uint a, uint b) {
        uint a0 = a & 0xFFFFu, a1 = a >> 16, b0 = b & 0xFFFFu, b1 = b >> 16;
        uint p00 = a0 * b0, p01 = a0 * b1, p10 = a1 * b0, p11 = a1 * b1;
        uint middle = (p00 >> 16) + (p01 & 0xFFFFu) + (p10 & 0xFFFFu);
        return u64(p11 + (p01 >> 16) + (p10 >> 16) + (middle >> 16), (p00 & 0xFFFFu) | (middle << 16));
    }

    // The low 64 bits of a 64 x 64 product, as UInt64's &* wraps.
    U64 u64Mul(U64 a, U64 b) {
        U64 low = u64Product(a.lo, b.lo);
        return u64(low.hi + a.hi * b.lo + a.lo * b.hi, low.lo);
    }
    """
}
