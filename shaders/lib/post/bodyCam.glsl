// =============================================================================
//  BODYCAM MODE  (Iteration 40)
// -----------------------------------------------------------------------------
//  Standalone port of "Body Camera Shader" V1.6.1 (its world0/final.fsh post
//  chain) as an ISOLATED final-pass overlay for Rethinking Voxels. When the
//  master toggle is ON, the finished frame is re-photographed through the
//  body-camera lens: optional forced 4:3 pillarbox, zoom, procedural camera
//  shake, fisheye distortion, chromatic aberration, kernel sharpening,
//  dynamic-range curve + the source's desaturating tonemap and cool color
//  cast, scanline / grain / color-distortion artifacts, night-vision
//  transform, brightness/contrast, lens vignette and black side stripes --
//  every constant and value list mirrors the source settings.glsl.
//
//  PORT SCOPE. Ported: the complete post-process camera look above (every
//  parameter of the source's [BC], [VHS], [NVG] and CC brightness/contrast/
//  saturation/dynamic-range groups plus FORCE_4_3_RATIO). Excluded on
//  instruction: the "Hover over me" author option (BY) and the "RTX version"
//  promotional toggle (PATREON). Excluded for isolation: options that are not
//  post-processing in the source but full pipeline features RV already
//  provides natively (PBR, SSR, shadows/shading, AO, waves, foliage, fog,
//  motion blur, DOF, bloom, auto exposure, flashlight) or that need scene
//  data / extra texture bindings a pure overlay must not touch (lens flare
//  needs projected sun positions -- RV has its own; LUT/BIT need the source's
//  LUT texture stages; TI is part of its lighting pass).
//
//  Runs strictly on the finalized frame buffer at the end of final.glsl; with
//  the master toggle OFF nothing here executes and output is bit-identical.
//  All symbols are PP_BC/ppBc prefixed and collision-free.
// =============================================================================
#ifndef INCLUDE_BODYCAM_MODE
#define INCLUDE_BODYCAM_MODE

#define PP_BODYCAM 0              //[0 1]
#define PP_BC_FORCE_4_3 1         //[0 1]
#define PP_BC_ZOOM 0.80           //[0.75 0.80 0.825 0.85 0.90 0.95 1.00]
#define PP_BC_DISTORTION 1.00     //[-1.00 -0.85 -0.75 -0.65 -0.50 -0.45 -0.35 -0.25 -0.15 0.00 0.15 0.25 0.35 0.45 0.50 0.65 0.75 0.85 1.00 1.15 1.25 1.35 1.50]
#define PP_BC_SHAKE 0.00          //[0.00 0.001 0.0025 0.005 0.01]
#define PP_BC_ABERRATION 0.0025   //[0.00 0.0025 0.005 0.0075 0.01]
#define PP_BC_SHARPNESS 0.25      //[0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define PP_BC_DYNAMIC_RANGE 1.4   //[1.0 1.2 1.4 1.6 1.8 2.0 2.2]
#define PP_BC_SATURATION 0.80     //[0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25]
#define PP_BC_BRIGHTNESS 0.05     //[-1.00 -0.95 -0.90 -0.85 -0.80 -0.75 -0.70 -0.65 -0.60 -0.55 -0.50 -0.45 -0.40 -0.35 -0.30 -0.25 -0.20 -0.15 -0.10 -0.05 0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define PP_BC_CONTRAST 0.95       //[0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.025 1.05 1.075 1.10]
#define PP_BC_GRAIN 1             //[0 1]
#define PP_BC_GRAIN_STRENGTH 0.075 //[0.01 0.025 0.05 0.075 0.1 0.125 0.15]
#define PP_BC_SCANLINE 0          //[0 1]
#define PP_BC_SCANLINE_STRENGTH 0.025 //[0.01 0.025 0.05 0.075 0.1]
#define PP_BC_SCANLINE_WIDTH 750  //[100 250 500 750 1000]
#define PP_BC_COLOR_DIST 0        //[0 1]
#define PP_BC_COLOR_DIST_STRENGTH 0.01 //[0.01 0.02 0.03 0.04 0.05]
#define PP_BC_VIGNETTE 1          //[0 1]
#define PP_BC_VIGNETTE_RADIUS 0.45 //[0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define PP_BC_VIGNETTE_STRENGTH 0.20 //[0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define PP_BC_BLACK_STRIPES 0     //[0 1]
#define PP_BC_STRIPES_WIDTH 0.10  //[0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55]
#define PP_BC_STRIPES_SOFT 0.10   //[0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define PP_BC_NVG 0               //[0 1]
#define PP_BC_NVG_SNEAK 0         //[0 1]
#define PP_BC_NVG_R 0.29          //[0.0 0.05 0.10 0.15 0.20 0.25 0.29 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define PP_BC_NVG_G 0.75          //[0.0 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define PP_BC_NVG_B 0.39          //[0.0 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.39 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define PP_BC_NVG_GAIN 5          //[1 2 3 4 5 6 7 8 9 10]

#if PP_BODYCAM == 1

// Iris player-state uniform (reads 0 where unavailable -> gate simply stays
// inactive; nothing else in the pack uses it).
uniform float isSneaking;

float ppBcRand(vec2 n) {
    return fract(sin(dot(n, vec2(12.9898, 78.233))) * 43758.5453);
}

float ppBcNoise(vec2 x) {
    vec2 i = floor(x);
    vec2 f = fract(x);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = ppBcRand(i + vec2(0.0, 0.0));
    float b = ppBcRand(i + vec2(1.0, 0.0));
    float c = ppBcRand(i + vec2(0.0, 1.0));
    float d = ppBcRand(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

vec2 ppBcCameraShake(float t, float intensity, float freq) {
    float nx = ppBcNoise(vec2(0.0, t * freq));
    float ny = ppBcNoise(vec2(1.0, t * freq));
    return (vec2(nx, ny) * 2.0 - 1.0) * intensity;
}

// Source simpleBodyCamTonemap (SATURATION baked in, luminance preserved).
vec3 ppBcTonemap(vec3 color) {
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 desaturated = mix(vec3(luminance), color, PP_BC_SATURATION);
    desaturated = pow(desaturated, vec3(0.9));
    float newLum = dot(desaturated, vec3(0.299, 0.587, 0.114));
    if (newLum > 0.0) desaturated *= luminance / newLum;
    return desaturated;
}

// Complete port of the source final-pass camera chain. Reads the finalized
// frame (src) with its own lens mapping and returns the re-photographed color.
vec3 ApplyBodyCam(sampler2D src, vec2 uvRaw) {
    vec3 bcColor;

    // 4:3 mapping (source: effect UV stretched so the 4:3 area spans 0..1).
    vec2 effectUV = uvRaw;
    float currentAR = viewWidth / viewHeight;
    float targetAR = 4.0 / 3.0;
    float visibleWidth = 1.0;
    float margin = 0.0;
    #if PP_BC_FORCE_4_3 == 1
        if (currentAR > targetAR) {
            visibleWidth = targetAR / currentAR;
            margin = (1.0 - visibleWidth) / 2.0;
            effectUV.x = (uvRaw.x - margin) / visibleWidth;
        }
    #endif

    // Zoom, shake, fisheye, aberration.
    vec2 centeredCoord = (effectUV - 0.5) * PP_BC_ZOOM + 0.5;
    float bcDistance = length(centeredCoord - 0.5);
    vec2 shake = ppBcCameraShake(frameTimeCounter, PP_BC_SHAKE, 3.0);
    vec2 fisheyeUV = (centeredCoord + shake - 0.5) * (1.0 + PP_BC_DISTORTION * bcDistance * bcDistance) + 0.5;
    vec2 redUV  = fisheyeUV + vec2(PP_BC_ABERRATION) * bcDistance;
    vec2 blueUV = fisheyeUV - vec2(PP_BC_ABERRATION) * bcDistance;

    // Map back to true screen space for sampling (no stretch).
    vec2 sampleFisheyeUV = fisheyeUV;
    vec2 sampleRedUV = redUV;
    vec2 sampleBlueUV = blueUV;
    #if PP_BC_FORCE_4_3 == 1
        if (currentAR > targetAR) {
            sampleFisheyeUV.x = fisheyeUV.x * visibleWidth + margin;
            sampleRedUV.x = redUV.x * visibleWidth + margin;
            sampleBlueUV.x = blueUV.x * visibleWidth + margin;
        }
    #endif

    bcColor.r = texture2D(src, sampleRedUV).r;
    bcColor.g = texture2D(src, sampleFisheyeUV).g;
    bcColor.b = texture2D(src, sampleBlueUV).b;

    // Kernel sharpening.
    vec2 bcTexel = 1.0 / vec2(viewWidth, viewHeight);
    vec3 sharpened = vec3(0.0);
    sharpened += texture2D(src, sampleFisheyeUV + bcTexel * vec2(-1.0,  0.0)).rgb * -1.0;
    sharpened += texture2D(src, sampleFisheyeUV + bcTexel * vec2( 1.0,  0.0)).rgb * -1.0;
    sharpened += texture2D(src, sampleFisheyeUV + bcTexel * vec2( 0.0, -1.0)).rgb * -1.0;
    sharpened += texture2D(src, sampleFisheyeUV + bcTexel * vec2( 0.0,  1.0)).rgb * -1.0;
    sharpened += texture2D(src, sampleFisheyeUV).rgb * 5.0;
    bcColor = mix(bcColor, sharpened, PP_BC_SHARPNESS);
    bcColor = clamp(bcColor, 0.0, 1.0);

    // Dynamic range, tonemap and the source's cool sensor cast.
    bcColor = pow(bcColor, vec3(1.0 / PP_BC_DYNAMIC_RANGE));
    bcColor = ppBcTonemap(bcColor);
    bcColor.r *= 0.975;
    bcColor.g *= 1.025;
    bcColor.b *= 1.05;

    #if PP_BC_SCANLINE == 1
        float bcScanline = sin(fisheyeUV.y * float(PP_BC_SCANLINE_WIDTH) * 1.5) * PP_BC_SCANLINE_STRENGTH;
        bcColor += bcScanline;
    #endif

    #if PP_BC_GRAIN == 1
        float bcNoiseVal = (fract(sin(dot(fisheyeUV, vec2(12.9898, 78.233 * frameTimeCounter))) * 43758.5453) - 0.5) * PP_BC_GRAIN_STRENGTH;
        bcColor += vec3(bcNoiseVal);
    #endif

    #if PP_BC_COLOR_DIST == 1
        float bcColorDistort = PP_BC_COLOR_DIST_STRENGTH * sin(frameTimeCounter * 2.0);
        bcColor *= vec3(1.0 + bcColorDistort, 1.0 - bcColorDistort, 1.0 + bcColorDistort);
    #endif

    // Night vision (source NVG / ENABLE_NVG_IsSneaking structure).
    #if PP_BC_NVG_SNEAK == 1
        if (isSneaking > 0.5) {
            float bcGray = dot(bcColor, vec3(0.299, 0.587, 0.114));
            bcColor = vec3(bcGray) * (vec3(PP_BC_NVG_R, PP_BC_NVG_G, PP_BC_NVG_B) * float(PP_BC_NVG_GAIN));
        }
    #elif PP_BC_NVG == 1
        float bcGray = dot(bcColor, vec3(0.299, 0.587, 0.114));
        bcColor = vec3(bcGray) * (vec3(PP_BC_NVG_R, PP_BC_NVG_G, PP_BC_NVG_B) * float(PP_BC_NVG_GAIN));
    #endif

    // Brightness / contrast.
    bcColor += PP_BC_BRIGHTNESS;
    bcColor = (bcColor - 0.5) * PP_BC_CONTRAST + 0.5;

    #if PP_BC_VIGNETTE == 1
        float bcVignette = smoothstep(PP_BC_VIGNETTE_RADIUS, PP_BC_VIGNETTE_RADIUS + PP_BC_VIGNETTE_STRENGTH, bcDistance);
        bcColor = mix(bcColor, vec3(0.0), bcVignette);
        // Source pairs the lens vignette with fixed soft side stripes.
        float bcLeftV = smoothstep(0.1, 0.1 - 0.3, fisheyeUV.x);
        float bcRightV = smoothstep(1.0 - 0.1, 1.0 - (0.1 - 0.3), fisheyeUV.x);
        bcColor = mix(bcColor, vec3(0.0), max(bcLeftV, bcRightV));
    #endif

    #if PP_BC_BLACK_STRIPES == 1
        float bcLeft = smoothstep(PP_BC_STRIPES_WIDTH, PP_BC_STRIPES_WIDTH - PP_BC_STRIPES_SOFT, effectUV.x);
        float bcRight = smoothstep(1.0 - PP_BC_STRIPES_WIDTH, 1.0 - (PP_BC_STRIPES_WIDTH - PP_BC_STRIPES_SOFT), effectUV.x);
        bcColor = mix(bcColor, vec3(0.0), max(bcLeft, bcRight));
    #endif

    // 4:3 pillarbox bars.
    #if PP_BC_FORCE_4_3 == 1
        if (currentAR > targetAR) {
            if (uvRaw.x < margin || uvRaw.x > 1.0 - margin) bcColor = vec3(0.0);
        }
    #endif

    return bcColor;
}

#endif // PP_BODYCAM == 1

#endif // INCLUDE_BODYCAM_MODE
