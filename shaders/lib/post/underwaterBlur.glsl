// =============================================================================
//  UNDERWATER BLUR  (Iteration 42)
// -----------------------------------------------------------------------------
//  Camera-tab option: while the eye is underwater (isEyeInWater == 1), a
//  clean disc blur is applied over the finished frame to simulate realistic
//  low-visibility underwater optics. OFF by default (UNDERWATER_BLUR = 0);
//  the slider sets the blur radius as a percentage of an ~8-pixel-at-1080p
//  baseline (encoded as an integer percent because the GLSL preprocessor
//  cannot compare float option values).
//
//  ISOLATION: included only by program/final.glsl, all helpers at GLOBAL
//  scope, no arrays (the 12-tap disc is generated procedurally from the
//  golden angle), no comment ends in a backslash. Complements the Iteration
//  42 droplets rework: blur runs ONLY while submerged, droplets run ONLY
//  after resurfacing -- the two never overlap.
// =============================================================================
#ifndef INCLUDE_UNDERWATER_BLUR
#define INCLUDE_UNDERWATER_BLUR

#define UNDERWATER_BLUR 0 //[0 25 50 75 100 125 150 200 250 300 400]

#if UNDERWATER_BLUR > 0

vec3 ApplyUnderwaterBlur(vec3 color, sampler2D src, vec2 uv) {
    if (isEyeInWater != 1) return color;

    // Radius in UV units: 100% ~= 8 px at 1080p, kept isotropic on screen.
    float ubRadius = float(UNDERWATER_BLUR) * 0.01 * 0.0075;
    vec2 ubScale = vec2(viewHeight / viewWidth, 1.0) * ubRadius;

    // 12-tap golden-angle disc (procedural offsets -- no lookup tables).
    vec3 ubSum = color;
    for (int i = 1; i <= 12; i++) {
        float ubAngle = float(i) * 2.39996;
        float ubR = sqrt(float(i) / 12.0);
        ubSum += texture2D(src, uv + vec2(cos(ubAngle), sin(ubAngle)) * ubR * ubScale).rgb;
    }
    return ubSum / 13.0;
}

#endif // UNDERWATER_BLUR > 0

#endif // INCLUDE_UNDERWATER_BLUR
