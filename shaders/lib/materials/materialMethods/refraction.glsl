#if ECLIPSE_WATER == 1
    // Iteration 25: wave-geometry refraction source (included at global scope
    // of the composite program; pure ALU + noisetex, #version 130 safe).
    #include "/eclipse_water.glsl"
#endif

float GetApproxDistance(float depth) {
    return near * far / (far - depth * far);
}

void DoRefraction(inout vec3 color, inout float z0, inout float z1, vec3 viewPos, float lViewPos) {
    // Prep
    if (int(texelFetch(colortex6, texelCoord, 0).g * 255.1) != 241) return;

    float fovScale = gbufferProjection[1][1];

    vec3 playerPos = ViewToPlayer(viewPos.xyz);
    vec3 worldPos = playerPos.xyz + cameraPosition.xyz;
    vec2 worldPosRM = worldPos.xz * 0.02 + worldPos.y * 0.01 + 0.01 * frameTimeCounter;

    #if ECLIPSE_WATER == 1
        // Iteration 25: bend the refraction by the ACTUAL Eclipse wave-slope
        // gradient at this surface point instead of generic scrolling noise.
        // The depth-difference clamps and the colortex6 water-mask re-checks
        // below are kept untouched, so the refracted vectors feed RV's
        // underwater scattering/absorption exactly like stock -- the voxel
        // volume fog reads consistent depths and can never pull a non-water
        // pixel through the surface.
        vec2 refractNoise = EclipseRefractGradient(worldPos.xz) * 0.5;
        refractNoise *= WATER_REFRACTION_INTENSITY * fovScale / (3.0 + lViewPos);
        refractNoise *= 0.02 * ECLIPSE_WATER_WAVE_STRENGTH;
    #else
        vec2 refractNoise = texture2D(noisetex, worldPosRM).rb - vec2(0.5);
             refractNoise *= WATER_REFRACTION_INTENSITY * fovScale / (3.0 + lViewPos);

        #if WATER_STYLE < 3
            refractNoise *= 0.015;
        #else
            refractNoise *= 0.02;
        #endif
    #endif

    // Check
    float approxDif = GetApproxDistance(z1) - GetApproxDistance(z0);
    refractNoise *= clamp(approxDif, 0.0, 1.0);

    vec2 refractCoord = texCoord.xy + refractNoise;

    if (int(texture2D(colortex6, refractCoord).g * 255.1) != 241) return;

    float z0check = texture2D(depthtex0, refractCoord).r;
    float z1check = texture2D(depthtex1, refractCoord).r;
    float approxDifCheck = GetApproxDistance(z1check) - GetApproxDistance(z0check);
    refractNoise *= clamp(approxDifCheck, 0.0, 1.0);

    // Sample
    refractCoord = texCoord.xy + refractNoise;
    color = texture2D(colortex0, refractCoord).rgb;
    z0 = texture2D(depthtex0, refractCoord).r;
    z1 = texture2D(depthtex1, refractCoord).r;
}