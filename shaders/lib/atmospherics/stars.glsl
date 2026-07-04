#include "/lib/colors/skyColors.glsl"

float GetStarNoise(vec2 pos) {
    return fract(sin(dot(pos, vec2(12.9898, 4.1414))) * 43758.54953);
}

vec2 GetStarCoord(vec3 viewPos, float sphereness) {
    vec3 wpos = normalize((gbufferModelViewInverse * vec4(viewPos * 1000.0, 1.0)).xyz);
    vec3 starCoord = wpos / (wpos.y + length(wpos.xz) * sphereness);
    // Iteration 38: the star-field rotation is bound to the TRACKED visual
    // clock (blissCloudSyncedTime rides the eclipseTimeTracker visual angle;
    // it equals raw syncedTime whenever the Eclipse time transition is off).
    // On a time jump the stars now glide, accelerate and settle on the exact
    // same Iteration 31 exponential curve as the sun, sky and clouds instead
    // of snapping with raw world time.
    starCoord.x += 0.006 * blissCloudSyncedTime;
    return starCoord.xz;
}

vec3 GetStars(vec2 starCoord, float VdotU, float VdotS) {
    if (VdotU < 0.0) return vec3(0.0);

    starCoord *= 0.2;
    float starFactor = 1024.0;
    starCoord = floor(starCoord * starFactor) / starFactor;

    float star = 1.0;
    star *= GetStarNoise(starCoord.xy);
    star *= GetStarNoise(starCoord.xy+0.1);
    star *= GetStarNoise(starCoord.xy+0.23);

    #if NIGHT_STAR_AMOUNT == 2
        star -= 0.7;
    #else
        star -= 0.6;
        star *= 0.65;
    #endif
    star = max0(star);
    star *= star;

    star *= min1(VdotU * 3.0) * max0(1.0 - pow(abs(VdotS) * 1.002, 100.0));
    star *= invRainFactor * pow2(pow2(invNoonFactor2)) * (1.0 - 0.5 * sunVisibility);

    return 40.0 * star * vec3(0.38, 0.4, 0.5);
}