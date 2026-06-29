// Volumetric tracing from Robobo1221, highly modified
#include "/lib/vx/irradianceCache.glsl"
#ifndef LIGHTSHAFTS_ACTIVE
    float GetDepth(float depth) {
        return 2.0 * near * far / (far + near - (2.0 * depth - 1.0) * (far - near));
    }

    float GetDistX(float dist) {
        return (far * (dist - near)) / (dist * (far - near));
    }
#endif
vec3 GetVolumetricBlocklight(vec3 translucentMult, float lViewPos, vec3 nViewPos, vec2 texCoord, float z0, float z1, float dither) {
    if (max(blindness, darknessFactor) > 0.1) return vec3(0.0);
    vec3 volumetricLight = vec3(0.0);

    vec3 vlMult = vec3(VBL_STRENGTH);
    #ifdef OVERWORLD
        float vlSceneIntensity = 0.3 + 0.6 * rainFactor;
    #elif defined NETHER
        float vlSceneIntensity = 0.9;
    #elif defined END
        float vlSceneIntensity = 0.5;
    #endif
    #if LIGHTSHAFT_QUALI == 4
        int sampleCount = vlSceneIntensity < 0.5 ? 30 : 50;
    #elif LIGHTSHAFT_QUALI == 3
        int sampleCount = vlSceneIntensity < 0.5 ? 15 : 30;
    #elif LIGHTSHAFT_QUALI == 2
        int sampleCount = vlSceneIntensity < 0.5 ? 10 : 20;
    #else
        int sampleCount = vlSceneIntensity < 0.5 ? 6 : 12;
    #endif
    float addition = 1.0;
    float maxDist = mix(max(far, 96.0) * 0.55, 80.0, vlSceneIntensity);

    if (isEyeInWater == 1) {
        #if WATER_FOG_MULT != 100
            #define WATER_FOG_MULT_M WATER_FOG_MULT * 0.01;
            maxDist /= WATER_FOG_MULT_M;
        #endif
    } else {
        vlMult *= 0.1;
    }

    float distMult = maxDist / (sampleCount + addition);
    float sampleMultIntense = isEyeInWater != 1 ? 1.0 : 1.85;

    float viewFactor = 1.0 - 0.7 * pow2(dot(nViewPos.xy, nViewPos.xy));

    float depth0 = GetDepth(z0);
    float depth1 = GetDepth(z1);

    // Fast but inaccurate perspective distortion approximation
    maxDist *= viewFactor;
    distMult *= viewFactor;

    #ifdef OVERWORLD
        float maxCurrentDist = min(depth1, maxDist);
    #else
        float maxCurrentDist = min(depth1, far);
    #endif

    for (int i = 0; i < sampleCount; i++) {
        float currentDist = (i + dither) * distMult + addition;

        if (currentDist > maxCurrentDist) break;

        vec4 viewPos = gbufferProjectionInverse * (vec4(texCoord, GetDistX(currentDist), 1.0) * 2.0 - 1.0);
        //viewPos /= viewPos.w;
        vec4 wpos = gbufferModelViewInverse * viewPos;
        vec3 playerPos = wpos.xyz / wpos.w;
        vec3 vxPos = playerPos + fractCamPos;

        vec3 vlSample = vec3(0.0);

        float percentComplete = currentDist / maxDist;
        float sampleMult = mix(percentComplete * 3.0, sampleMultIntense, max(rainFactor, vlSceneIntensity));
        if (currentDist < 5.0) sampleMult *= smoothstep1(clamp(currentDist / 5.0, 0.0, 1.0));
        sampleMult /= sampleCount;

        if (infnorm(vxPos/voxelVolumeSize) < 0.5) {
            vlSample = readVolumetricBlocklight(vxPos);
        }

        if (currentDist > depth0) vlSample *= translucentMult;

        volumetricLight += vlSample * sampleMult;
    }

    #ifdef OVERWORLD
        #if LIGHTSHAFT_DAY_I != 100 || LIGHTSHAFT_NIGHT_I != 100
            #define LIGHTSHAFT_DAY_IM LIGHTSHAFT_DAY_I * 0.01
            #define LIGHTSHAFT_NIGHT_IM LIGHTSHAFT_NIGHT_I * 0.01
            vlMult.rgb *= mix(LIGHTSHAFT_NIGHT_IM, LIGHTSHAFT_DAY_IM, sunVisibility);
        #endif

        #if LIGHTSHAFT_RAIN_I != 100
            #define LIGHTSHAFT_RAIN_IM LIGHTSHAFT_RAIN_I * 0.01
            vlMult.rgb *= mix(1.0, LIGHTSHAFT_RAIN_IM, rainFactor);
        #endif
    #elif defined NETHER
        vlMult *= VBL_NETHER_MULT;
    #elif defined END
        vlMult *= VBL_END_MULT;
    #endif
    volumetricLight *= vlMult;

    volumetricLight = max(volumetricLight, vec3(0.0));

    return volumetricLight;
}