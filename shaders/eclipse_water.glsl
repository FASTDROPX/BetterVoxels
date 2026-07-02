// =============================================================================
//  ECLIPSE WATER MODULE  (Iteration 25: "Hydro-Voxel Fusion")
// -----------------------------------------------------------------------------
//  Standalone port of the Eclipse Shader's native water wave engine
//  (github.com/Merlin1809/Eclipse-Shader, branch Unstable) into the
//  Rethinking Voxels pipeline. Source material, traced line-by-line:
//    - shaders/lib/waterBump.glsl  : 3-octave golden-angle-rotated fBm
//      heightmap (getWaterHeightmap), analytical finite-difference wave
//      normals (getWaveNormal) and the exponential caustic field
//      (waterCaustics), all modulated by a 600-block "patchy" swell mask.
//    - shaders/dimensions/all_translucent.vsh : the LARGE_WAVE_DISPLACEMENT
//      vertex swell (getWave / vertex getWaveNormal) that physically morphs
//      the water mesh.
//    - shaders/dimensions/all_translucent.fsh : the parallax displacement
//      of the sampling plane (getParallaxDisplacement) and the flowing-face
//      UV mapping.
//    - shaders/lib/ripples.glsl : rain-drop ripple normals (Shadertoy
//      ldfyzl port by Zavie/Ctrl-Alt-Test, public production use).
//  NOT ported: shaders/lib/oceans.glsl -- that file is the Physics Mod
//  integration stub (public-domain afl_ext Gerstner waves); every uniform in
//  it (physics_waviness, physics_gameTime, ...) is injected by the external
//  Physics Mod at runtime and does not exist under plain Iris, so it cannot
//  run inside a self-contained pack.
//
//  RV integration rules honoured by this module:
//    - VERSION SAFETY: pure ALU + noisetex taps. No SSBOs, no image ops, no
//      new uniforms, no new buffers -- compiles identically under
//      "#version 130" (composite) and "#version 430 compatibility"
//      (gbuffers_water / shadow). bufferObject.0 and every RV binding are
//      untouched by construction.
//    - NOISE BRIDGE: Eclipse samples its own 512x512 Bliss noisetex; RV ships
//      a 128x128 RGB noisetex. UV math is resolution-independent (wave tile
//      periods are in blocks), so the same channels are used (.b smooth fBm
//      for the heightmap/caustics/mask, .r for the vertex swell) -- only the
//      per-tile texel density differs.
//    - TIME BASE: all advection runs on eclipseWaterTimeG, derived from
//      blissCloudSyncedTime (lib/common.glsl) instead of frameTimeCounter.
//      In steady state that clock advances at ~1.0/s exactly like
//      frameTimeCounter, so wave speeds match Eclipse; during an
//      ECLIPSE_TIME_ACTIVE cinematic time transition it rides the eased
//      visual clock, so the water executes the same time-lapse warp as the
//      sun, clouds and cloud shadows (Iterations 22-24).
//    - NAMESPACE: every symbol is "eclipse"-prefixed; verified collision-free
//      against the whole RV tree.
//  All functions are declared at global scope: include this file only from
//  the top level of a program (gbuffers_water, composite, shadow), never
//  from inside main().
// =============================================================================
#ifndef INCLUDE_ECLIPSE_WATER
#define INCLUDE_ECLIPSE_WATER

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
    return texture2D(noisetex, posxz / 600.0).b;
}

float EclipseLargeWavesCurved(float largeWaves) {
    float curved = pow(1.0 - pow(1.0 - largeWaves, 2.5), 4.5);
    return mix(1.0 - curved, curved, ECLIPSE_PATCHY_WAVE_BLEND);
}

// Eclipse getWaterHeightmap: 3 rotated, drifting fBm octaves.
float EclipseWaterHeightmap(vec2 posxz, float largeWavesCurved) {
    vec2 pos = posxz;
    float movement = eclipseWaterTimeG * 0.035;
    mat2 rotationMatrix = EclipseRotationMatrix();

    float heightSum = 0.0;
    for (int i = 0; i < 3; i++) {
        pos = rotationMatrix * pos;
        heightSum += texture2D(noisetex, pos / eclipseWaveSizes[i] + largeWavesCurved * 0.5 + movement).b;
    }

    return (heightSum / 4.5) * max(largeWavesCurved, 0.3);
}

// Eclipse getWaveNormal: analytical finite-difference normal of the heightmap,
// in heightmap tangent space (x = d/dx, y = d/dz, z = up). The sampling radius
// blends between the A (calm) and B (crest) radii and widens with distance so
// the far field never gets more detail than it has pixels.
vec3 EclipseWaveNormal(vec2 posxz, vec3 relPos) {
    float largeWaves = EclipseLargeWaves(posxz);
    float largeWavesCurved = EclipseLargeWavesCurved(largeWaves);

    #if ECLIPSE_HYPER_DETAILED_WAVES == 1
        float deltaPos = 0.025;
    #else
        float deltaPos = mix(ECLIPSE_WAVES_A_RADIUS, ECLIPSE_WAVES_B_RADIUS, largeWavesCurved);
        deltaPos += min(length(relPos) / (16.0 * 24.0), 3.0);
    #endif

    float h0 = EclipseWaterHeightmap(posxz, largeWavesCurved);
    float h1 = EclipseWaterHeightmap(posxz + vec2(deltaPos, 0.0), largeWavesCurved);
    float h3 = EclipseWaterHeightmap(posxz + vec2(0.0, deltaPos), largeWavesCurved);

    float xDelta = (h1 - h0) / deltaPos;
    float yDelta = (h3 - h0) / deltaPos;

    return normalize(vec3(xDelta, yDelta, 1.0 - pow(abs(xDelta + yDelta), 2.0)));
}

// Eclipse getParallaxDisplacement: slides the sampling plane along the
// tangent-space view vector by the local wave height, so crests visually
// occlude troughs even at grazing angles.
vec2 EclipseParallax(vec2 posxz, vec3 tanViewVector) {
    float largeWaves = EclipseLargeWaves(posxz);
    float largeWavesCurved = EclipseLargeWavesCurved(largeWaves);

    float waterHeight = EclipseWaterHeightmap(posxz, largeWavesCurved);
    waterHeight = exp(-7.0 * exp(-7.0 * waterHeight)) * 0.25;

    return posxz + (tanViewVector.xy / -tanViewVector.z) * waterHeight;
}

// Eclipse all_translucent.vsh getWave: the low-frequency swell that physically
// displaces water vertices ("crest formation"). Range grows with distance so
// the far ocean rolls; the voxel-lit near field stays within a fraction of a
// block, which keeps displaced surfaces inside their source water voxel.
float EclipseVertexWave(vec3 worldPos, float range) {
    return pow(1.0 - texture2D(noisetex, (worldPos.xz + eclipseWaterTimeG) / 125.0).r, 5.0)
           * min(ECLIPSE_WATER_WAVE_STRENGTH, 1.0) * range;
}

// Eclipse all_translucent.vsh getWaveNormal: matching analytic normal of the
// vertex swell, folded into the shading normal so lighting follows the
// morphing geometry.
vec3 EclipseLargeWaveNormal(vec3 worldPos, float range) {
    float deltaPos = 0.5;

    float h0 = EclipseVertexWave(worldPos, range);
    float h1 = EclipseVertexWave(worldPos - vec3(deltaPos, 0.0, 0.0), range);
    float h3 = EclipseVertexWave(worldPos - vec3(0.0, 0.0, deltaPos), range);

    float xDelta = (h1 - h0) / deltaPos * 1.5;
    float yDelta = (h3 - h0) / deltaPos * 1.5;

    return normalize(vec3(xDelta, yDelta, 1.0 - pow(abs(xDelta + yDelta), 2.0)));
}

// Eclipse waterCaustics: exponential response of the folded wave field. Used
// by the shadow pass so sunlight entering the water medium projects the SAME
// wave geometry onto the floor that the surface renders above it.
float EclipseWaterCaustics(vec3 worldPos) {
    vec2 pos = worldPos.xz;
    float movement = eclipseWaterTimeG * 0.035;
    mat2 rotationMatrix = EclipseRotationMatrix();

    float largeWaves = texture2D(noisetex, pos / 600.0).b;
    float largeWavesCurved = EclipseLargeWavesCurved(largeWaves);

    float heightSum = 0.0;
    for (int i = 0; i < 3; i++) {
        pos = rotationMatrix * pos;
        heightSum += pow(abs(abs(texture2D(noisetex, pos / eclipseWaveSizes[i] + largeWavesCurved * 0.5 + movement).b * 2.0 - 1.0) * 2.0 - 1.0), 1.0 + largeWavesCurved);
    }

    return exp((1.0 + 5.0 * sqrt(largeWavesCurved)) * (heightSum / 3.0 - 0.5));
}

// Wave-geometry gradient for the composite refraction pass: the screen-space
// refraction offset follows the actual surface slope instead of generic
// noise, so underwater voxel light and the absorption fog bend consistently
// with the waves overhead.
vec2 EclipseRefractGradient(vec2 posxz) {
    float largeWaves = EclipseLargeWaves(posxz);
    float largeWavesCurved = EclipseLargeWavesCurved(largeWaves);

    const float deltaPos = 0.35;
    float h0 = EclipseWaterHeightmap(posxz, largeWavesCurved);
    float h1 = EclipseWaterHeightmap(posxz + vec2(deltaPos, 0.0), largeWavesCurved);
    float h3 = EclipseWaterHeightmap(posxz + vec2(0.0, deltaPos), largeWavesCurved);

    return vec2(h1 - h0, h3 - h0) / deltaPos;
}

// ---------------------------------------------------------------------------
// Rain ripples (Eclipse lib/ripples.glsl, Shadertoy ldfyzl). Rain response is
// real-time by nature, so this one effect stays on frameTimeCounter, exactly
// like RV's own rain puddles.
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
