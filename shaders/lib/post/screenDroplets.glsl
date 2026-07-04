// =============================================================================
//  SCREEN WATER DROPLETS  (Iteration 41)
// -----------------------------------------------------------------------------
//  Port of the "water on camera" gameplay effect from Bliss v2.1.2 (by Xonk,
//  Chocapic13 edit -- lib/gameplay_effects.glsl, WATER_ON_CAMERA_EFFECT): when
//  the eye leaves water (isEyeInWater flips 1 -> 0), droplets cling to the
//  camera and run DOWN the screen while drying out over five seconds, each
//  drop refracting the underlying image; underwater, the same mask gives the
//  lens a soft wet wobble.
//
//  STATE / TIMER. Exactly Bliss's mechanism: the engine-side smoothed uniform
//      uniform.float.exitWater = smooth(247, if(isEyeInWater == 1, 1, 0), 0.0, 5.0)
//  (shaders.properties) latches to 1 INSTANTLY while submerged (fade-up 0)
//  and decays over 5 seconds after resurfacing (fade-down 5) -- the wetness
//  accumulation timer that fires on the 1 -> 0 transition.
//
//  DROPLET FIELD. Bliss samples its 512x512 SMOOTH value-noise texture; RV's
//  noisetex is a different, non-smooth 128x128 texture (see the Iteration 26
//  "noise bridge" notes in eclipse_water.glsl), so this port generates the
//  SAME smooth field procedurally: quintic value noise calibrated with the
//  established 512/20 cells-per-tile constant. The mask math, slide motion,
//  dry-out curve and center-zoom refraction are ported line-for-line.
//
//  ISOLATION. Included only by program/final.glsl; every helper lives at
//  GLOBAL scope (no nested functions), no arrays, no comment ends in a
//  backslash. Applied to the finalized frame after the base camera pipeline
//  and BEFORE the retro overlay stack. With the toggle OFF (or exitWater at
//  rest) the entry point is never invoked / returns the color unchanged.
// =============================================================================
#ifndef INCLUDE_SCREEN_DROPLETS
#define INCLUDE_SCREEN_DROPLETS

#define WATER_DROPLETS // Water droplets on the camera when leaving water

#ifdef WATER_DROPLETS

// Wetness timer, maintained by Iris across frames (declared in
// shaders.properties; reads 0 when dry, so the effect self-disables).
uniform float exitWater;

// Smooth (quintic) value noise -- the stand-in for Bliss's noises.png red
// channel, same construction as the pack's established noise bridge.
float wdHash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float wdNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = wdHash12(i);
    float b = wdHash12(i + vec2(1.0, 0.0));
    float c = wdHash12(i + vec2(0.0, 1.0));
    float d = wdHash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// One noise tile of Bliss's 512 texture ~= 20 texels of correlation length.
#define WD_NOISE_RES (512.0 / 20.0)

vec3 ApplyWaterDroplets(vec3 color, sampler2D src, vec2 uv) {
    // Bliss gate: nothing runs once the camera has dried off.
    if (exitWater <= 0.01) return color;

    float wdAspect = viewWidth / viewHeight;

    // Ported line-for-line from applyGameplayEffects():
    //  - underwater: a static, gentle full-lens wobble;
    //  - after resurfacing: the field stretches vertically as it dries
    //    (scale.y grows with exitWater^2) and SLIDES DOWN the screen
    //    (the -scale.z offset shrinks with the timer), so the drops run
    //    downward while thinning out.
    vec3 wdScale = vec3(1.0, 1.0, 0.0);
    wdScale.xy = (isEyeInWater == 1 ? vec2(0.3) : vec2(0.5, 0.25 + (exitWater * exitWater) * 0.25)) * vec2(wdAspect, 1.0);
    wdScale.z = isEyeInWater == 1 ? 0.0 : exitWater;

    float waterDrops = wdNoise((uv - vec2(0.0, wdScale.z)) * wdScale.xy * WD_NOISE_RES);
    if (isEyeInWater == 1) waterDrops = waterDrops * waterDrops * 0.3;
    if (isEyeInWater == 0) waterDrops = sqrt(min(max(waterDrops - (1.0 - sqrt(exitWater)) * 0.7, 0.0) * (1.0 + exitWater), 1.0)) * 0.3;

    // Bliss refraction: every drop zooms the UV toward the screen center by
    // its mask strength and re-samples the finished frame.
    vec2 wdZoomUV = vec2(0.5) + (uv - vec2(0.5)) * (1.0 - waterDrops);
    return texture2D(src, wdZoomUV).rgb;
}

#endif // WATER_DROPLETS

#endif // INCLUDE_SCREEN_DROPLETS
