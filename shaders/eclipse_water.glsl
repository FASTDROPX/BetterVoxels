// =============================================================================
//  ECLIPSE WATER MODULE  (Iteration 25 / hardened in Iteration 26)
// -----------------------------------------------------------------------------
//  Standalone port of the Eclipse Shader's native water wave engine
//  (github.com/Merlin1809/Eclipse-Shader, branch Unstable) into Rethinking
//  Voxels. Source, traced line-by-line: lib/waterBump.glsl (3-octave
//  golden-angle-rotated fBm heightmap, analytical finite-difference normals,
//  exponential caustics, 600-block "patchy" swell mask), all_translucent.vsh
//  (LARGE_WAVE_DISPLACEMENT vertex swell), all_translucent.fsh (parallax +
//  flowing-face UV mapping) and lib/ripples.glsl (rain ripples). Eclipse's
//  lib/oceans.glsl was intentionally NOT ported -- it is the Physics Mod stub
//  whose physics_* uniforms only exist with that external mod.
//
//  Iteration 26 -- NOISE BRIDGE (the fish-scale fix). Eclipse sampled its own
//  512x512 SMOOTH-value noises.png. RV ships a 128x128 noisetex whose content
//  is NOT smooth value noise, so feeding Eclipse's heightmap/normal finite
//  differences from raw noisetex taps produced per-texel garbage -> the water
//  shattered into "fish scales". This module now generates its wave field from
//  a PROCEDURAL quintic value noise (the same technique the Bliss cloud port
//  uses, lib/atmospherics/clouds/bliss_clouds.glsl) calibrated to Eclipse's
//  ~1.9-block base feature size, so the heightmap is C1-smooth and the normals
//  are gentle. Normal reconstruction was also made unconditionally stable
//  (z pinned positive, so it can never flip inside-out) and the tangent-space
//  parallax is clamped so it can no longer explode at grazing angles (that was
//  the radial smear). noisetex is no longer touched by the wave field.
//
//  RV integration rules: pure ALU (no texture wave taps, no SSBOs, no image
//  ops, no new uniforms/buffers) -> compiles under #version 130 (composite)
//  and 430 compatibility (gbuffers_water / shadow); bufferObject.0 and every
//  RV binding untouched. All advection runs on eclipseWaterTimeG, derived from
//  blissCloudSyncedTime (lib/common.glsl), so the waves fast-forward with the
//  sun/clouds during an ECLIPSE_TIME_ACTIVE transition and otherwise drift at
//  the normal rate. Every symbol is "eclipse/Eclipse"-prefixed and verified
//  collision-free. Include only from the top level of a program.
// =============================================================================
#ifndef INCLUDE_ECLIPSE_WATER
#define INCLUDE_ECLIPSE_WATER

// ---- Procedural smooth value noise (noise bridge) --------------------------
// Calibrated so one noise cell ~= Eclipse's noises.png correlation length
// (~20 texels of a 512 tile) -> ECLIPSE_NOISE_RES cells per input unit.
#define ECLIPSE_NOISE_RES (512.0 / 20.0)

float eclipse_hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Smooth (quintic) 2D value noise in [0,1], mean ~0.5.
float eclipse_vnoise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = eclipse_hash12(i);
    float b = eclipse_hash12(i + vec2(1.0, 0.0));
    float c = eclipse_hash12(i + vec2(0.0, 1.0));
    float d = eclipse_hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Drop-in stand-ins for Eclipse's noisetex .b / .r channel taps.
float eclipseNoiseB(vec2 c) { return eclipse_vnoise2(c * ECLIPSE_NOISE_RES); }
float eclipseNoiseR(vec2 c) { return eclipse_vnoise2(c * ECLIPSE_NOISE_RES + 3.1); }

// Eclipse waterBump.glsl: anisotropic octave tile sizes, in blocks.
const vec2 eclipseWaveSizes[3] = vec2[](
    vec2(48.0, 12.0),
    vec2(12.0, 48.0),
    vec2(32.0, 32.0)
);

// Golden-angle octave rotation (Eclipse "radiance" constant).
const float eclipseRadiance = 2.39996;

// Unified advection clock: Eclipse used frameTimeCounter; here the waves ride
// the smooth visual clock so they fast-forward with the sky on a time jump.
float eclipseWaterTimeG = blissCloudSyncedTime * ECLIPSE_WATER_WAVE_SPEED;

mat2 EclipseRotationMatrix() {
    return mat2(vec2(cos(eclipseRadiance), -sin(eclipseRadiance)),
                vec2(sin(eclipseRadiance),  cos(eclipseRadiance)));
}

// 600-block swell mask: decides where the sea is calm vs. cresting.
float EclipseLargeWaves(vec2 posxz) {
    return eclipseNoiseB(posxz / 600.0);
}

float EclipseLargeWavesCurved(float largeWaves) {
    float curved = pow(1.0 - pow(1.0 - largeWaves, 2.5), 4.5);
    return mix(1.0 - curved, curved, ECLIPSE_PATCHY_WAVE_BLEND);
}

// Eclipse getWaterHeightmap: 3 rotated, drifting smooth-noise octaves.
float EclipseWaterHeightmap(vec2 posxz, float largeWavesCurved) {
    vec2 pos = posxz;
    float movement = eclipseWaterTimeG * 0.035;
    mat2 rotationMatrix = EclipseRotationMatrix();

    float heightSum = 0.0;
    for (int i = 0; i < 3; i++) {
        pos = rotationMatrix * pos;
        heightSum += eclipseNoiseB(pos / eclipseWaveSizes[i] + largeWavesCurved * 0.5 + movement);
    }

    return (heightSum / 4.5) * max(largeWavesCurved, 0.3);
}

// Eclipse getWaveNormal, made unconditionally stable: analytical finite-
// difference gradient of the smooth heightmap, z pinned to +1 so the normal
// tilts gently and can NEVER flip inside-out (the old 1-pow(|x+y|,2) form went
// negative on any steep gradient -> faceting). Returned in bump space
// (x=d/dx, y=d/dz, z=up-along-geometric-normal).
vec3 EclipseWaveNormal(vec2 posxz, vec3 relPos) {
    float largeWaves = EclipseLargeWaves(posxz);
    float largeWavesCurved = EclipseLargeWavesCurved(largeWaves);

    #if ECLIPSE_HYPER_DETAILED_WAVES == 1
        float deltaPos = 0.35;
    #else
        float deltaPos = mix(ECLIPSE_WAVES_A_RADIUS, ECLIPSE_WAVES_B_RADIUS, largeWavesCurved);
        deltaPos += min(length(relPos) / (16.0 * 24.0), 3.0);
    #endif
    deltaPos = max(deltaPos, 0.25); // guard: keep the difference well-sampled

    float h0 = EclipseWaterHeightmap(posxz, largeWavesCurved);
    float h1 = EclipseWaterHeightmap(posxz + vec2(deltaPos, 0.0), largeWavesCurved);
    float h3 = EclipseWaterHeightmap(posxz + vec2(0.0, deltaPos), largeWavesCurved);

    float xDelta = (h1 - h0) / deltaPos;
    float yDelta = (h3 - h0) / deltaPos;

    return normalize(vec3(xDelta, yDelta, 1.0));
}

// Eclipse getParallaxDisplacement, clamped: slides the sampling plane along the
// tangent-space view vector by the local wave height. The raw ratio explodes
// as tanViewVector.z -> 0 (grazing angles), which was the radial smear; the
// offset is now clamped to a fraction of a block so parallax stays a subtle
// depth cue and can never tear.
vec2 EclipseParallax(vec2 posxz, vec3 tanViewVector) {
    float largeWaves = EclipseLargeWaves(posxz);
    float largeWavesCurved = EclipseLargeWavesCurved(largeWaves);

    float waterHeight = EclipseWaterHeightmap(posxz, largeWavesCurved);
    waterHeight = exp(-7.0 * exp(-7.0 * waterHeight)) * 0.25;

    vec2 parallax = tanViewVector.xy / (-tanViewVector.z - 0.35);
    parallax = clamp(parallax, vec2(-1.5), vec2(1.5));

    return posxz + parallax * waterHeight;
}

// Eclipse all_translucent.vsh getWave: low-frequency swell that physically
// displaces water vertices. Now on smooth procedural noise so the mesh rolls
// instead of spiking. Range grows with distance (capped in the caller).
float EclipseVertexWave(vec3 worldPos, float range) {
    float n = eclipseNoiseR((worldPos.xz + eclipseWaterTimeG) / 125.0);
    return pow(1.0 - n, 5.0) * min(ECLIPSE_WATER_WAVE_STRENGTH, 1.0) * range;
}

// Matching analytic normal of the vertex swell, stable (z pinned positive),
// folded into the shading normal so lighting follows the morphing geometry.
vec3 EclipseLargeWaveNormal(vec3 worldPos, float range) {
    const float deltaPos = 0.5;

    float h0 = EclipseVertexWave(worldPos, range);
    float h1 = EclipseVertexWave(worldPos - vec3(deltaPos, 0.0, 0.0), range);
    float h3 = EclipseVertexWave(worldPos - vec3(0.0, 0.0, deltaPos), range);

    float xDelta = (h1 - h0) / deltaPos * 1.5;
    float yDelta = (h3 - h0) / deltaPos * 1.5;

    return normalize(vec3(xDelta, yDelta, 1.0));
}

// Eclipse waterCaustics: exponential response of the folded smooth wave field,
// so sunlight entering the medium projects the SAME wave geometry the surface
// renders. Advected by the visual clock.
float EclipseWaterCaustics(vec3 worldPos) {
    vec2 pos = worldPos.xz;
    float movement = eclipseWaterTimeG * 0.035;
    mat2 rotationMatrix = EclipseRotationMatrix();

    float largeWaves = eclipseNoiseB(pos / 600.0);
    float largeWavesCurved = EclipseLargeWavesCurved(largeWaves);

    float heightSum = 0.0;
    for (int i = 0; i < 3; i++) {
        pos = rotationMatrix * pos;
        float n = eclipseNoiseB(pos / eclipseWaveSizes[i] + largeWavesCurved * 0.5 + movement);
        heightSum += pow(abs(abs(n * 2.0 - 1.0) * 2.0 - 1.0), 1.0 + largeWavesCurved);
    }

    return exp((1.0 + 5.0 * sqrt(largeWavesCurved)) * (heightSum / 3.0 - 0.5));
}

// Wave-geometry gradient for the composite refraction pass: the screen-space
// refraction offset follows the actual surface slope instead of generic noise.
vec2 EclipseRefractGradient(vec2 posxz) {
    float largeWaves = EclipseLargeWaves(posxz);
    float largeWavesCurved = EclipseLargeWavesCurved(largeWaves);

    const float deltaPos = 0.35;
    float h0 = EclipseWaterHeightmap(posxz, largeWavesCurved);
    float h1 = EclipseWaterHeightmap(posxz + vec2(deltaPos, 0.0), largeWavesCurved);
    float h3 = EclipseWaterHeightmap(posxz + vec2(0.0, deltaPos), largeWavesCurved);

    return clamp(vec2(h1 - h0, h3 - h0) / deltaPos, vec2(-1.0), vec2(1.0));
}

// ---------------------------------------------------------------------------
// Rain ripples (Eclipse lib/ripples.glsl, Shadertoy ldfyzl). Rain response is
// real-time by nature, so this one effect stays on frameTimeCounter.
// ---------------------------------------------------------------------------
float EclipseHash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 EclipseHash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.xx + p3.yz) * p3.zy);
}

vec3 EclipseRipples(vec2 fragCoord) {
    const float cellDensity = 5.0;

    vec2 uv = fragCoord * cellDensity;
    vec2 p0 = floor(uv);

    const float waveFrequency = 21.0;

    vec2 circles = vec2(0.0);
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            vec2 pi = p0 + vec2(float(i), float(j));
            vec2 p = pi + EclipseHash22(pi);

            float t = fract(0.9 * frameTimeCounter + EclipseHash12(pi));
            vec2 v = p - uv;

            float d = length(v) - 2.0 * t;

            const float h = 1e-2;
            float d1 = d - h;
            float d2 = d + h;
            float p1 = sin(waveFrequency * d1) * smoothstep(-0.6, -0.3, d1) * smoothstep(0.0, -0.3, d1);
            float p2 = sin(waveFrequency * d2) * smoothstep(-0.6, -0.3, d2) * smoothstep(0.0, -0.3, d2);
            circles += 0.5 * normalize(v) * ((p2 - p1) / (2.0 * h) * (1.0 - t) * (1.0 - t));
        }
    }
    circles /= 9.0;

    return vec3(circles, sqrt(1.0 - dot(circles, circles)));
}

#endif // INCLUDE_ECLIPSE_WATER
