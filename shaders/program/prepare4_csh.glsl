#include "/lib/common.glsl"

#ifdef CSH
#ifdef PER_PIXEL_LIGHT
layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
#if BLOCKLIGHT_RESOLUTION == 1
    const vec2 workGroupsRender = vec2(1.0, 1.0);
#elif BLOCKLIGHT_RESOLUTION == 2
    const vec2 workGroupsRender = vec2(0.5, 0.5);
#elif BLOCKLIGHT_RESOLUTION == 3
    const vec2 workGroupsRender = vec2(0.3333333, 0.3333333);
#elif BLOCKLIGHT_RESOLUTION == 4
    const vec2 workGroupsRender = vec2(0.25, 0.25);
#elif BLOCKLIGHT_RESOLUTION == 6
    const vec2 workGroupsRender = vec2(0.1666667, 0.1666667);
#elif BLOCKLIGHT_RESOLUTION == 8
    const vec2 workGroupsRender = vec2(0.125, 0.125);
#endif
vec2 view = vec2(viewWidth, viewHeight);
layout(rgba16f) uniform image2D colorimg10;
#ifdef BLOCKLIGHT_HIGHLIGHT
    layout(rgba16f) uniform image2D colorimg13;
#endif
layout(rgba16i) uniform iimage2D colorimg11;

vec3 fractCamPos =
    cameraPositionInt.y == -98257195 ?
    fract(cameraPosition) :
    cameraPositionFract;
ivec3 floorCamPosOffset =
    cameraPositionInt.y == -98257195 ?
    ivec3((floor(cameraPosition) - floor(previousCameraPosition)) * 1.001) :
    cameraPositionInt - previousCameraPositionInt;

#include "/lib/vx/SSBOs.glsl"
#include "/lib/vx/voxelReading.glsl"
#include "/lib/util/random.glsl"
#include "/lib/vx/positionHashing.glsl"
#ifdef BLOCKLIGHT_HIGHLIGHT
    #include "/lib/lighting/ggx.glsl"
#endif

#ifdef DO_PIXELATION_EFFECTS
    #if PIXEL_SCALE == -2
        #define PIXEL_TEXEL_SCALE TEXTURE_RES / 4.0
    #elif PIXEL_SCALE == -1
        #define PIXEL_TEXEL_SCALE TEXTURE_RES / 2.0
    #elif PIXEL_SCALE == 2
        #define PIXEL_TEXEL_SCALE TEXTURE_RES / 0.5
    #elif PIXEL_SCALE == 3
        #define PIXEL_TEXEL_SCALE TEXTURE_RES / 0.25
    #elif PIXEL_SCALE == 4
        #define PIXEL_TEXEL_SCALE TEXTURE_RES / 0.125
    #elif PIXEL_SCALE == 5
        #define PIXEL_TEXEL_SCALE TEXTURE_RES / 0.0625
    #else // 1 or out of range
        #define PIXEL_TEXEL_SCALE TEXTURE_RES / 1.0
    #endif
#endif

#if MAX_TRACE_COUNT < 128 && !defined LONGER_LIGHT_LISTS
    #define MAX_LIGHT_COUNT 128
#else
    #define MAX_LIGHT_COUNT 512
#endif
shared int lightCount;
shared ivec4 cumulatedPos;
shared ivec4 cumulatedNormal;
shared ivec4[MAX_LIGHT_COUNT] lightCoords;
shared vec3[MAX_LIGHT_COUNT] lightPositions;
shared vec3[MAX_LIGHT_COUNT] lightCols;
shared int[MAX_LIGHT_COUNT] extraData;
shared float[MAX_LIGHT_COUNT] weights;
shared uint[128] lightHashMap;

ivec2 getFlipPair(int index, int stage) {
    int groupSize = 1<<stage;
    return ivec2(index / groupSize * groupSize * 2) +
           ivec2(index%groupSize, 2 * groupSize - index%groupSize - 1);
}
ivec2 getDispersePair(int index, int stage) {
    int groupSize = 1<<stage;
    return ivec2(index / groupSize * groupSize * 2) +
           ivec2(index%groupSize, groupSize + index%groupSize);
}

void flipPair(int index, int stage) {
    ivec2 indexPair = getFlipPair(index, stage);
    if (
        indexPair.y < lightCount && 
        weights[indexPair.x] < weights[indexPair.y]
    ) {
        ivec4 temp = lightCoords[indexPair.x];
        float temp2 = weights[indexPair.x];
        lightCoords[indexPair.x] = lightCoords[indexPair.y];
        lightCoords[indexPair.y] = temp;
        weights[indexPair.x] = weights[indexPair.y];
        weights[indexPair.y] = temp2;
    }
}

void dispersePair(int index, int stage) {
    ivec2 indexPair = getDispersePair(index, stage);
    if (
        indexPair.y < lightCount &&
        weights[indexPair.x] < weights[indexPair.y]
    ) {
        ivec4 temp = lightCoords[indexPair.x];
        float temp2 = weights[indexPair.x];
        lightCoords[indexPair.x] = lightCoords[indexPair.y];
        lightCoords[indexPair.y] = temp;
        weights[indexPair.x] = weights[indexPair.y];
        weights[indexPair.y] = temp2;
    }
}

float distanceFalloff(float maxDistRelDist) {
    return (sqrt(1 - maxDistRelDist)) / (maxDistRelDist
        #if R2_FALLOFF == 1
            * maxDistRelDist
        #endif
        + 0.01
    ) / (
        LIGHT_TRACE_LENGTH
        #if R2_FALLOFF == 1
            * sqrt(sqrt(LIGHT_TRACE_LENGTH))
        #endif
    );
}

void registerLight(ivec3 lightCoord, vec3 referencePos, vec3 referenceNormal, float weight) {
    bool isStillLight = (imageLoad(occupancyVolume, lightCoord + voxelVolumeSize/2).r >> 16 & 1) != 0;
    if (!isStillLight) {
        for (int k = 0; k < 6; k++) {
            ivec3 offset = (k/3*2-1) * ivec3(equal(ivec3(k%3), ivec3(0, 1, 2)));
            if ((imageLoad(occupancyVolume, lightCoord + offset + voxelVolumeSize/2).r >> 16 & 1) != 0) {
                isStillLight = true;
                lightCoord += offset;
                break;
            }
        }
    }
    uint hash = posToHash(lightCoord) % uint(128*32);
    bool known = !isStillLight;
    if (isStillLight) {
        known = (atomicOr(lightHashMap[hash/32], uint(1)<<hash%32) & uint(1)<<hash%32) != 0;
    }

    if (!known) {
        int lightIndex = atomicAdd(lightCount, 1);
        if (lightIndex < MAX_LIGHT_COUNT) {
            uint hash = posToHash(lightCoord) % uint(1<<18);
            uvec2 packedLightSubPos = uvec2(globalLightHashMap[4*hash], globalLightHashMap[4*hash+1]);
            uvec2 packedLightCol = uvec2(globalLightHashMap[4*hash+2], globalLightHashMap[4*hash+3]);
            int thisLightExtraData = imageLoad(occupancyVolume, lightCoord + voxelVolumeSize/2).r;
            vec3 subLightPos = (packedLightSubPos.y >> 16) == 0 ? vec3(0.5) : 1.0/32.0 * vec3(packedLightSubPos.x & 0xffff, packedLightSubPos.x>>16, packedLightSubPos.y & 0xffff) / (packedLightSubPos.y >> 16) - 1;
            vec3 lightCol = 1.0/32.0 * vec3(packedLightCol.x & 0xffff, packedLightCol.x>>16, packedLightCol.y & 0xffff) / (packedLightSubPos.y >> 16);
            vec3 dir = lightCoord + subLightPos - referencePos;
            float dirLen = length(dir);
            float ndotl = dot(normalize(dir), referenceNormal);
            float thisTraceLen = (thisLightExtraData>>17 & 31)/32.0;
            lightCoords[lightIndex] = ivec4(lightCoord, lightIndex);

            weights[lightIndex] = max(weight,
                length(lightCol) *
                ndotl *
                distanceFalloff(dirLen / (thisTraceLen * LIGHT_TRACE_LENGTH)) *
                1.5*1.5*thisTraceLen*thisTraceLen);
            lightPositions[lightIndex] = lightCoord + subLightPos;
            lightCols[lightIndex] = lightCol;
            extraData[lightIndex] = thisLightExtraData;

        } else {
            atomicMin(lightCount, MAX_LIGHT_COUNT);
        }
    }
}

void main() {
    int index = int(gl_LocalInvocationID.x + gl_WorkGroupSize.x * gl_LocalInvocationID.y);
    float dither = nextFloat();
    if (index == 0) {
        lightCount = 0;
        cumulatedPos = ivec4(0);
        cumulatedNormal = ivec4(0);
    }
    if (index < 128) {
        lightHashMap[index] = 0;
    }
    if (index < MAX_LIGHT_COUNT) {
        lightPositions[index] = vec3(0);
        lightCols[index] = vec3(0);
    }
    barrier();
    memoryBarrierShared();
    ivec2 readTexelCoord
        = ivec2(gl_GlobalInvocationID.xy) * BLOCKLIGHT_RESOLUTION
        + ivec2(
            BLOCKLIGHT_RESOLUTION
            * fract(vec2(
                frameCounter % 1000 * 1.618033988749895,
                frameCounter % 1000 * 1.618033988749895 * 1.618033988749895
            ) + vec2(
                gl_GlobalInvocationID.x * 1.618033988749895 * 1.618033988749895 * 1.618033988749895,
                gl_GlobalInvocationID.x * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895
            ) + vec2(
                gl_GlobalInvocationID.y * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895,
                gl_GlobalInvocationID.y * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895
            ))
        );
    ivec2 writeTexelCoord = ivec2(gl_GlobalInvocationID.xy);
    vec4 normalDepthData = texelFetch(colortex8, readTexelCoord, 0);
    #ifdef BLOCKLIGHT_HIGHLIGHT
        vec3 pbrMat = texelFetch(colortex3, readTexelCoord, 0).rgb;
        float smoothness = pbrMat.r;
        float materialMask = pbrMat.g;
    #endif
    ivec3 vxPosFrameOffset = -floorCamPosOffset;
    bool validData = (normalDepthData.a < 1.5 && length(normalDepthData.rgb) > 0.1 && all(lessThan(readTexelCoord, ivec2(view + 0.1))));
    for (int k = 1; k < BLOCKLIGHT_RESOLUTION; k++) {
        if (validData) break;
        for (int i = 0; i < 2 * k - 1; i++) {
            ivec2 offset = i < k ? ivec2(i, k) : ivec2(k, 2 * k - 2 - i);
            ivec2 newReadTexelCoord = readTexelCoord + offset;
            normalDepthData = texelFetch(colortex8, newReadTexelCoord, 0);
            bool validData = (normalDepthData.a < 1.5 && length(normalDepthData.rgb) > 0.1 && all(lessThan(newReadTexelCoord, ivec2(view + 0.1))));
            if (validData) {
                readTexelCoord = newReadTexelCoord;
            }
        }
    }
    vec4 playerPos = vec4(1000);
    vec3 vxPos = vec3(1000);
    vec3 biasedVxPos = vec3(1000);

    barrier();

    if (validData) {
        playerPos =
            gbufferModelViewInverse *
            (gbufferProjectionInverse *
            (vec4((readTexelCoord + 0.5) / view,
            1 - normalDepthData.a,
            1) * 2 - 1));
        playerPos /= playerPos.w;
        vxPos = playerPos.xyz + fractCamPos;

        normalDepthData.xyz = normalize(
            normalDepthData.xyz - max(0.0, dot(normalDepthData.xyz, playerPos.xyz)) / pow2(length(playerPos.xyz)) * playerPos.xyz
        );

        float bias = max(0.6/(1<<VOXEL_DETAIL_AMOUNT), 1.2 * infnorm(vxPos/voxelVolumeSize));
        int thisResolution = getVoxelResolution(vxPos);
        float dfValMargin = 0.01;
        if (normalDepthData.a > 0.44) { // hand
            dfValMargin = 0.5;
        } else {
            #if defined DO_PIXELATION_EFFECTS && defined PIXELATED_BLOCKLIGHT
                vxPos = floor(vxPos * PIXEL_TEXEL_SCALE + 0.5 * normalDepthData.xyz) / PIXEL_TEXEL_SCALE + 0.5 / PIXEL_TEXEL_SCALE;
            #endif
        }
        for (int k = 0; k < 4; k++) {
            biasedVxPos = vxPos + bias * normalDepthData.xyz;
            vec3 dfGrad = distanceFieldGradient(biasedVxPos);
            if (dfGrad != vec3(0)) dfGrad = normalize(dfGrad);
            vec3 dfGradPerp = dfGrad - dot(normalDepthData.xyz, dfGrad) * normalDepthData.xyz;
            float dfVal = getDistanceField(biasedVxPos);
            float dfGradPerpLength = length(dfGradPerp);
            if (dfGradPerpLength > 0.1) {
                float resolution = min(VOXEL_DETAIL_AMOUNT, -log2(infnorm(abs(vxPos) / voxelVolumeSize) - 0.5));
                dfVal = min(dfVal, getDistanceField(biasedVxPos - dfGradPerp / (pow(2, resolution + 1) * dfGradPerpLength)));
            }
            if (dfVal > dfValMargin) break;
            bias += max(0.01, dfValMargin - dfVal);
        }
        biasedVxPos = vxPos + min(1.1, bias) * normalDepthData.xyz;
        ivec4 discretizedVxPos = ivec4(100 * vxPos, 100);
        ivec4 discretizedNormal = ivec4(10 * normalDepthData.xyz, 10);
        for (int i = 0; i < 4; i++) {
            atomicAdd(cumulatedPos[i], discretizedVxPos[i]);
            atomicAdd(cumulatedNormal[i], discretizedNormal[i]);
        }
    }
    barrier();
    memoryBarrierShared();
    vec3 meanPos = vec3(cumulatedPos.xyz)/cumulatedPos.w;
    vec3 meanNormal = vec3(cumulatedNormal.xyz)/cumulatedNormal.w;

    if (false && validData) {
        meanPos = biasedVxPos;
        meanNormal = normalDepthData.xyz;
    }

    if (index < MAX_LIGHT_COUNT) {
        ivec4 prevFrameLight = imageLoad(colorimg11, writeTexelCoord);
        if (prevFrameLight.w > 0) {
            registerLight(prevFrameLight.xyz + vxPosFrameOffset, meanPos, meanNormal, 0.0001 * prevFrameLight.w);
        }
    }
    barrier();
    if (validData) {
        vec3 dir = randomSphereSample();
        if (dot(dir, normalDepthData.xyz) < 0) {
            dir *= -1;
        }
        vec3 rayNormal0;
        vec4 rayHit0 = voxelTrace(biasedVxPos, LIGHT_TRACE_LENGTH * dir, rayNormal0, 1|1<<16);
        ivec3 rayHit0Coords = ivec3(rayHit0.xyz - 0.5 * rayNormal0 + 1000) - 1000;
        registerLight(rayHit0Coords, vxPos, normalDepthData.xyz, 0.0);
    }

    if (index < 125) {
        ivec3 lightPos0 = ivec3(index%5, index/5%5, index/25%5) - 2;
        registerLight(lightPos0, meanPos, meanNormal, 0.0);
    }

    if (index < 8 * MAX_LIGHT_COUNT) {
        ivec2 offset = (1 + index%8/4*3) * (index%4/2*2-1) * ivec2(index%2, (index+1)%2);
        int otherLightIndex = index / 8;
        ivec4 prevFrameLight = imageLoad(colorimg11, ivec2(gl_WorkGroupSize.xy) * (ivec2(gl_WorkGroupID.xy) + offset) + ivec2(otherLightIndex % gl_WorkGroupSize.x, otherLightIndex / gl_WorkGroupSize.x));
        if (prevFrameLight.w > 0) {
            registerLight(prevFrameLight.xyz + vxPosFrameOffset, meanPos, meanNormal, 0.0001 / (index/8*2+1) * prevFrameLight.w);
        }
    }

    barrier();
    memoryBarrierShared();
    bool participateInSorting = index < MAX_LIGHT_COUNT/2;
    #include "/lib/misc/prepare4_BM_sort.glsl"

    vec3 origLightPos = vec3(0);
    vec3 origLightCol = vec3(0);
    int origExtraData = 0;
    
    if (index < lightCount) {
        int origIndex = lightCoords[index].w;
        origLightPos = lightPositions[origIndex];
        origLightCol = lightCols[origIndex];
        origExtraData = extraData[origIndex];
    }
    barrier();

    if (index < lightCount) {
        lightPositions[index] = origLightPos;
        lightCols[index] = origLightCol;
        extraData[index] = origExtraData;
        lightCoords[index].w = 0;
    }
    barrier();
    memoryBarrierShared();

    vec3 writeColor = vec3(0);
    #ifdef BLOCKLIGHT_HIGHLIGHT
        vec3 writeSpecular = vec3(0);
    #endif
    if (validData) {
        uint traceNum = 0;
        uint thisLightIndex = 0;
        for (; thisLightIndex < MAX_LIGHT_COUNT; thisLightIndex++) {
            if (thisLightIndex >= lightCount) break;
            float lightSize = 0.5;
            vec3 lightPos = lightPositions[thisLightIndex];
            lightSize = clamp(lightSize, 0.01, getDistanceField(lightPos));
            float ndotl0 = max(0.0, dot(normalize(lightPos - vxPos), normalDepthData.xyz));
            vec3 dir = lightPos - biasedVxPos;
            float dirLen = length(dir);
            float thisTraceLen = (extraData[thisLightIndex]>>17 & 31)/32.0;

            if (dirLen < thisTraceLen * LIGHT_TRACE_LENGTH && ndotl0 > 0.001) {
                float lightBrightness = 1.5 * thisTraceLen;
                lightBrightness *= lightBrightness;
                vec4 rayHit1 = coneTrace(biasedVxPos, (1.0 - 0.1 / (dirLen + 0.1)) * dir, lightSize * LIGHTSOURCE_SIZE_MULT / dirLen, dither);
                if (rayHit1.w > 0.01) {
                    #ifdef TRANSLUCENT_LIGHT_TINT
                        vec3 translucentNormal = vec3(0);
                        vec3 randomOffset = lightSize * LIGHTSOURCE_SIZE_MULT * randomSphereSample();
                        vec3 translucentPos = voxelTrace(
                            biasedVxPos,
                            dir + randomOffset,
                            translucentNormal,
                            1<<8
                        ).xyz;
                        vec3 translucentCol = vec3(1.0);
                        if (length(translucentPos - biasedVxPos) < dirLen - lightSize * LIGHTSOURCE_SIZE_MULT - 0.01) {
                            translucentCol = getColor(translucentPos - 0.1 * translucentNormal).rgb;
                        }
                    #endif
                    vec3 thisBaseCol =
                        lightCols[thisLightIndex] *
                    #ifdef TRANSLUCENT_LIGHT_TINT
                        translucentCol *
                    #endif
                        rayHit1.w *
                        distanceFalloff(dirLen / (thisTraceLen * LIGHT_TRACE_LENGTH)) *
                        lightBrightness;
                    if (!any(isnan(thisBaseCol)) && !isnan(ndotl0)) {
                        writeColor += thisBaseCol * ndotl0;
                        #ifdef BLOCKLIGHT_HIGHLIGHT

                            float specularBrightness = GGX(
                                normalDepthData.xyz,
                                normalize(playerPos.xyz - gbufferModelViewInverse[3].xyz),
                                normalize(lightPos - vxPos),
                                ndotl0,
                                smoothness
                            );
                            if (!isnan(specularBrightness)) {
                                writeSpecular += thisBaseCol * lightBrightness * specularBrightness;
                            }
                        #endif
                        int thisWeight = int(10000.5 * length(thisBaseCol) * ndotl0);
                        atomicMax(lightCoords[thisLightIndex].w, thisWeight);
                    }
                }
                traceNum++;
                if (traceNum >= MAX_TRACE_COUNT) break;
            }
        }
    }
    barrier();
    memoryBarrierShared();
    float lWriteColor = length(writeColor);
    if (lWriteColor > 0.01) {
        writeColor *= log(lWriteColor+1)/lWriteColor;
    }
    #ifdef BLOCKLIGHT_HIGHLIGHT
        float lWriteSpecular = length(writeSpecular);
        if (lWriteSpecular > 0.01) {
            writeSpecular *= log(lWriteSpecular+1)/lWriteSpecular;
        }
        imageStore(colorimg13, writeTexelCoord, vec4(writeSpecular, 1));
    #endif
    imageStore(colorimg10, writeTexelCoord, vec4(writeColor, 1));
    ivec4 lightPosToStore = (index < lightCount && lightCoords[index].w > 0) ? lightCoords[index] : ivec4(0);
    imageStore(colorimg11, writeTexelCoord, lightPosToStore);
}
#else
    const ivec3 workGroups = ivec3(1, 1, 1);
    layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
    void main() {}
#endif
#endif
