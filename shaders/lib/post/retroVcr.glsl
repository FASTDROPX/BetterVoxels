// =============================================================================
//  RETRO CRT/VCR POST-PROCESSING OVERLAY  (Iteration 39)
// -----------------------------------------------------------------------------
//  Standalone port of the CRT/VCR effect stack from "CTRVCR" v1.4.4
//  (Apache License 2.0), adapted as an ISOLATED overlay for Rethinking Voxels:
//  every effect is compiled and executed ONLY at the very end of the final
//  pass, strictly on the finalized frame buffer. Nothing here reads or writes
//  voxel data, shadow maps, lighting buffers or any mid-pipeline resource --
//  with every toggle OFF the two entry points below compile to the identity
//  and the pack output is bit-identical to Iteration 38.
//
//  Every effect has its own strict two-state toggle (0 = OFF, 1 = ON, shown
//  as OFF/ON in the GUI). Tuning constants are baked from the CTRVCR default
//  configuration (its shader.h values, noted per effect). All symbols are
//  "PP_"/"pp" prefixed and collision-free.
//
//  ENTRY POINTS (called from program/final.glsl only):
//    vec2 RetroPostUV(vec2 uv)                         -- UV-stage effects
//        (screen curvature, tape distortion, pixelation) applied to the
//        final buffer fetch coordinate.
//    void ApplyRetroVcr(inout vec3 color, sampler2D src, vec2 uv, vec2 uvRaw)
//        -- color-stage effects applied on top of the finished frame.
// =============================================================================
#ifndef INCLUDE_RETRO_VCR
#define INCLUDE_RETRO_VCR

// -------------------------- The twelve toggles -------------------------------
#define PP_CRT_CURVATURE 0      //[0 1]
#define PP_VHS_ABERRATION 0     //[0 1]
#define PP_CRT_SCANLINES 0      //[0 1]
#define PP_VHS_NOISE 0          //[0 1]
#define PP_CRT_VIGNETTE 0       //[0 1]
#define PP_VHS_TAPE_DISTORTION 0 //[0 1]
#define PP_CRT_BLOOM 0          //[0 1]
#define PP_VHS_TRACKING 0       //[0 1]
#define PP_RETRO_PIXELATE 0     //[0 1]
#define PP_VHS_GRAIN 0          //[0 1]
#define PP_RETRO_COLOR_DEPTH 0  //[0 1]
#define PP_RETRO_MONOCHROME 0   //[0 1]

#if PP_VHS_ABERRATION == 1 || PP_CRT_SCANLINES == 1 || PP_VHS_NOISE == 1 || PP_CRT_VIGNETTE == 1 || PP_CRT_BLOOM == 1 || PP_VHS_TRACKING == 1 || PP_VHS_GRAIN == 1 || PP_RETRO_COLOR_DEPTH == 1 || PP_RETRO_MONOCHROME == 1
    #define PP_RETRO_COLOR_STAGE
#endif

// ------------------------------ Helpers --------------------------------------
// CTRVCR common/hash.glsl, pp-prefixed.
float ppRandom(vec2 seed) {
    return fract(sin(dot(seed, vec2(12.9898, 78.233))) * 43758.5453123);
}
float ppHash(vec2 p, float t) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y + t);
}
#if PP_RETRO_COLOR_DEPTH == 1
    // CTRVCR bayer4x4 ordered dithering (COLOR_DITERING == 2 path).
    float ppDither4(vec2 p) {
        ivec2 ip = ivec2(mod(p * vec2(viewWidth, viewHeight), 4.0));
        float bayer[16] = float[16](
             0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
            12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0,
             3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
            15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0
        );
        int index = ip.x + ip.y * 4;
        return bayer[index];
    }
#endif

// ------------------------------ UV stage --------------------------------------
vec2 RetroPostUV(vec2 uv) {
    #if PP_CRT_CURVATURE == 1
        // CTRVCR barrel distortion, DISTRORTION_FACTOR 500 -> factor 0.05.
        vec2 ppDir = uv - vec2(0.5);
        float ppDist = length(ppDir);
        float ppDistortion = 1.0 + 0.05 * ppDist * ppDist;
        uv = vec2(0.5) + ppDir * ppDistortion * (1.0 - 0.05 / 3.0);
    #endif
    #if PP_VHS_TAPE_DISTORTION == 1
        // CTRVCR rolling screen-tear band: SCREEN_TEAR_SPEED 1300 (-> 1.3),
        // SCREEN_TEAR_SIZE 8 (-> 0.08), SCREEN_TEAR_DELAY 10000 (-> 100).
        float ppTearTime = mod(frameTimeCounter, 8192.0);
        float ppY1 = mod(1.3 * ppTearTime + 0.08, 100.0 + 0.08);
        float ppY2 = uv.y - ppY1;
        if (ppY2 < 0.0 && ppY2 > -0.08) uv.y = fract(ppY1);
    #endif
    #if PP_RETRO_PIXELATE == 1
        // CTRVCR RENDER_PIXEL_SIZE resolution scaling, fixed 4-px cells.
        vec2 ppRes = vec2(viewWidth, viewHeight);
        uv -= mod(uv, 4.0 / ppRes);
    #endif
    return uv;
}

// ------------------------------ Color stage -----------------------------------
// src   = the finalized frame buffer (the same sampler final.glsl reads).
// uv    = the (possibly UV-stage-modified) fetch coordinate.
// uvRaw = the untouched screen coordinate (the CTRVCR edge/noise effects seed
//         from the raw coordinate, exactly like its texcoord_vs).
void ApplyRetroVcr(inout vec3 color, sampler2D src, vec2 uv, vec2 uvRaw) {
    #ifdef PP_RETRO_COLOR_STAGE
        float ppTime = mod(frameTimeCounter, 8192.0);
        float ppTime8 = mod(frameTimeCounter * 7.987, 8192.0);
        float ppV = ppHash(uvRaw, ppTime8);
        float ppV2 = ppHash(uvRaw, ppTime8 + 456.789);

        #if PP_CRT_BLOOM == 1
            // CTRVCR analog glow, BLOOM_SIZE 90 -> 0.009.
            vec3 ppSum = vec3(0.0);
            for (int i = -3; i < 3; i++) {
                float ppI3 = float(i) * 3.0;
                float ppV3 = (0.5 - ppRandom(uv + vec2(1.0 + ppI3, 0.0) + ppTime)) + float(i);
                float ppV4 = (0.5 - ppRandom(uv + vec2(2.0 + ppI3, 0.0) + (ppTime + 100.2)));
                float ppV5 = (0.5 - ppRandom(uv + vec2(3.0 + ppI3, 0.0) + (ppTime + 200.5)));
                ppSum += texture2D(src, uv + vec2(-1.0 + ppV4, ppV3) * 0.004).rgb * 0.009;
                ppSum += texture2D(src, uv + vec2(ppV5, ppV3) * 0.004).rgb * 0.009;
                ppSum += texture2D(src, uv + vec2(1.0 + ppV5, ppV3) * 0.004).rgb * 0.009;
            }
            vec3 ppBloom;
            if (color.r < 0.3 && color.g < 0.3 && color.b < 0.3)      ppBloom = ppSum * ppSum * 0.012 + color;
            else if (color.r < 0.5 && color.g < 0.5 && color.b < 0.5) ppBloom = ppSum * ppSum * 0.009 + color;
            else                                                      ppBloom = ppSum * ppSum * 0.0075 + color;
            color = mix(color, ppBloom, 0.5);
        #endif

        #if PP_VHS_ABERRATION == 1
            // CTRVCR blur + RGB channel split, BLUR_SIZE 100 -> 0.01.
            float ppBSize = 0.01;
            float ppVS = ppV * ppBSize;
            float ppVHalf = ppVS * 0.5;
            vec3 ppLeft1  = texture2D(src, vec2(uv.x - ppVS,   uv.y + ppVS / 3.0)).rgb;
            vec3 ppLeft2  = texture2D(src, vec2(uv.x - ppVHalf + ppLeft1.r * ppBSize * 0.25, uv.y + ppVS / 6.0)).rgb;
            vec3 ppRight1 = texture2D(src, vec2(uv.x + ppVS,   uv.y + ppVS)).rgb;
            float ppRO = ppVHalf - ppRight1.r * ppBSize * 0.25;
            vec3 ppRight2 = texture2D(src, vec2(uv.x + ppRO, uv.y + ppRO)).rgb;
            color = vec3((ppLeft1.r + ppLeft2.r + color.r) / 3.0,
                         color.g,
                         (ppRight1.b + ppRight2.b + color.b) / 3.0);
        #endif

        #if PP_VHS_GRAIN == 1
            // CTRVCR film grain, GRAIN_INTENSITY 30 -> 0.3.
            color += color * (0.5 - ppV) * 0.3;
        #endif

        // VHS static + tracking line (CTRVCR STATIC 10 -> 0.001,
        // STATIC_TEAR_CHANCE 75 -> 0.75).
        #if PP_VHS_NOISE == 1 || PP_VHS_TRACKING == 1
            #if PP_VHS_NOISE == 1
                float ppStatic = 0.001;
            #else
                float ppStatic = 0.0;
            #endif
            #if PP_VHS_TRACKING == 1
                float ppVRow = ppRandom(vec2(ppTime, 0.0));
                float ppL = abs(ppVRow - uv.y) * 0.75;
                if (ppL < 0.004 * ppV) ppStatic = 1.0 - min(ppL, 0.05 * ppV) * 50.0 / max(ppV, 0.0001);
            #endif
            if (ppV < ppStatic) {
                float ppSV = (ppStatic + 0.5) * ppV2;
                color = (color + vec3(ppSV)) * (1.0 - ppStatic) + vec3(ppV * ppStatic);
            }
        #endif

        #if PP_RETRO_MONOCHROME == 1
            // CTRVCR BNW at full strength.
            color = vec3((color.r + color.g + color.b) / 3.0);
        #endif

        #if PP_RETRO_COLOR_DEPTH == 1
            // CTRVCR color quantization, COLOR_RESOLUTION 32 + bayer4x4 dither.
            float ppDit = ppDither4(uv) - 0.5;
            color = floor(color * 32.0 + ppDit) / 31.0;
        #endif

        #if PP_CRT_SCANLINES == 1
            // CTRVCR composite1 scanlines, SCANLINE_INTENSITY 50 -> 0.5.
            float ppScan = mod(gl_FragCoord.y, 2.0);
            if (ppScan > 1.0) ppScan = 1.0 + 0.25;
            else ppScan += 0.5 - 0.25;
            color *= ppScan;
        #endif

        #if PP_CRT_VIGNETTE == 1
            // CTRVCR DARK_EDGES 0: light absorbed at the CRT tube edges.
            float ppA = uvRaw.x * 100.0;
            color = max(color, vec3(0.0));
            color *= min(ppA * 3.0 + ppV * 0.2, 2.0) - min(ppA * ppA + ppV2 * 0.2, 1.0);
            ppA = (1.0 - uvRaw.x) * 150.0;
            color *= min(ppA + ppV2 * 0.2, 1.0);
        #endif
    #endif
}

#endif // INCLUDE_RETRO_VCR
