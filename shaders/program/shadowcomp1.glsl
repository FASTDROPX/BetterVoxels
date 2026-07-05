#include "/lib/common.glsl"

//////1st Compute Shader//////1st Compute Shader//////1st Compute Shader//////
/*
This program offsets irradiance cache data to account for camera movement, and handles its temporal accumulation falloff
*/
#ifdef CSH

#if VX_VOL_SIZE == 0
    const ivec3 workGroups = ivec3(12, 8, 12);
#elif VX_VOL_SIZE == 1
    const ivec3 workGroups = ivec3(16, 12, 16);
#elif VX_VOL_SIZE == 2
    const ivec3 workGroups = ivec3(32, 16, 32);
#elif VX_VOL_SIZE == 3
    const ivec3 workGroups = ivec3(64, 16, 64);
#endif

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

ivec3 floorCamPosOffset =
    cameraPositionInt.y == -98257195 ?
    ivec3((floor(cameraPosition) - floor(previousCameraPosition)) * 1.001) :
    cameraPositionInt - previousCameraPositionInt;

#define WRITE_TO_SSBOS

layout(rgba16f) uniform image3D irradianceCacheI;
layout(rgba16i) uniform iimage3D lightStorage;

void main() {
    ivec3 coords = ivec3(gl_GlobalInvocationID);
    // this actually works for having threads be executed in the correct order so that they don't read the output of other previously run threads
    coords = coords * ivec3(greaterThan(floorCamPosOffset, ivec3(-1))) +
        (voxelVolumeSize - coords - 1) * ivec3(lessThan(floorCamPosOffset, ivec3(0)));
    ivec4 lightPos = imageLoad(lightStorage, coords);
    ivec3 prevCoords = coords + floorCamPosOffset;
    vec4[2] writeColors;
    for (int k = 0; k < 2; k++) {
        writeColors[k] = (all(lessThan(prevCoords, voxelVolumeSize)) && all(greaterThanEqual(prevCoords, ivec3(0)))) ? imageLoad(irradianceCacheI, prevCoords + ivec3(0, k * voxelVolumeSize.y, 0)) : vec4(0);
    }
    writeColors[0] *= 0.99; // GI accumulation falloff
    if (any(isnan(writeColors[0]))) writeColors[0] = vec4(0);
    barrier();
    memoryBarrierImage();
    for (int k = 0; k < 2; k++) {
        imageStore(irradianceCacheI, coords + ivec3(0, k * voxelVolumeSize.y, 0), writeColors[k]);
    }
    imageStore(lightStorage, coords, lightPos - ivec4(floorCamPosOffset, 0));
}
#endif

//////2nd Compute Shader//////2nd Compute Shader//////2nd Compute Shader//////
/*
this program calculates volumetric block lighting
*/
#ifdef CSH_A
#if VX_VOL_SIZE == 0
    const ivec3 workGroups = ivec3(12, 8, 12);
#elif VX_VOL_SIZE == 1
    const ivec3 workGroups = ivec3(16, 12, 16);
#elif VX_VOL_SIZE == 2
    const ivec3 workGroups = ivec3(32, 16, 32);
#elif VX_VOL_SIZE == 3
    const ivec3 workGroups = ivec3(64, 16, 64);
#endif

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

layout(rgba16f) uniform image3D irradianceCacheI;
layout(rgba16i) uniform iimage3D lightStorage;
#include "/lib/vx/SSBOs.glsl"
#include "/lib/vx/voxelReading.glsl"
#include "/lib/util/random.glsl"
#include "/lib/vx/positionHashing.glsl"

#if MAX_TRACE_COUNT < 128
    #define MAX_LIGHT_COUNT 128
#else
    #define MAX_LIGHT_COUNT 512
#endif
shared int lightCount;
shared bool anyInFrustrum;
shared ivec4[MAX_LIGHT_COUNT] lightCoords;
shared vec3[MAX_LIGHT_COUNT] lightPositions;
shared vec3[MAX_LIGHT_COUNT] lightCols;
shared int[MAX_LIGHT_COUNT] extraData;
shared float[MAX_LIGHT_COUNT] weights;
shared uint[128] lightHashMap;
shared vec3[5] frustrumSides;

const vec2[4] squareCorners = vec2[4](vec2(-1, -1), vec2(1, -1), vec2(1, 1), vec2(-1, 1));

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

void registerLight(ivec3 lightCoord, vec3 referencePos, float weight) {
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
            float thisTraceLen = (thisLightExtraData>>17 & 31)/32.0;
            lightCoords[lightIndex] = ivec4(lightCoord, lightIndex);

            weights[lightIndex] = max(weight,
                length(lightCol) *
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
    int index = int(gl_LocalInvocationIndex);
    float dither = nextFloat();
    if (index < 4) {
        vec4 pos = vec4(squareCorners[index], 0.9999, 1);
        pos = gbufferModelViewInverse * (gbufferProjectionInverse * pos);
        frustrumSides[index] = pos.xyz * pos.w;
    } else if (index == 4) {
        frustrumSides[4] = -normalize(gbufferModelViewInverse[2].xyz);
        lightCount = 0;
        anyInFrustrum = false;
    }
    if (index < 128) {
        lightHashMap[index] = 0;
    }
    barrier();
    memoryBarrierShared();
    vec3 sideNormal = vec3(0);
    if (index < 4) {
        sideNormal = -normalize(cross(frustrumSides[index], frustrumSides[(index+1)%4]));
    }
    barrier();
    if(index < 4) {
        frustrumSides[index] = sideNormal;
    }
    barrier();
    memoryBarrierShared();
    ivec3 coords = ivec3(gl_GlobalInvocationID);
    vec3 normal = vec3(0);
    vec3 vxPos = coords - 0.5 * voxelVolumeSize + vec3(0.41, 0.49, 0.502);
    vec3 meanPos = vec3(gl_WorkGroupID) * 8 + 4 - 0.5 * voxelVolumeSize;

    bool insideFrustrum = true;
    for (int k = 0; k < 5; k++) {
        insideFrustrum = (insideFrustrum && dot(vxPos, frustrumSides[k]) > -10.0);
    }
    bool hasNeighbor = false;
    int updateInterval = min(int(0.01 * dot(meanPos, meanPos) + 1.0), 10);
    bool activeFrame = int(gl_WorkGroupID.x + gl_WorkGroupID.y + gl_WorkGroupID.z) % updateInterval == frameCounter % updateInterval;

    if (insideFrustrum && activeFrame) {
        anyInFrustrum = true;
        hasNeighbor = getDistanceField(vxPos) < 0.7;
        if (hasNeighbor) {
            for (int k = 0; k < 3; k++) {
                normal[k] = getDistanceField(vxPos + mat3(0.5)[k]) - getDistanceField(vxPos - mat3(0.5)[k]);
            }
            normal = normalize(normal);
            vxPos -= 0.3 * normal;
        }
        registerLight(ivec3(vxPos + 1000) - 1000, meanPos, 0.0);
    }

    barrier();
    memoryBarrierShared();
    if (index < MAX_LIGHT_COUNT && anyInFrustrum) {
        ivec4 prevFrameLight = imageLoad(lightStorage, coords);
        if (prevFrameLight.w > 0) {
            registerLight(prevFrameLight.xyz, meanPos, prevFrameLight.w * 0.0001);
        }
    }
    barrier();
    memoryBarrierShared();
    if (index < MAX_LIGHT_COUNT && anyInFrustrum) {
        for (int k = 0; k < 6; k++) {
            ivec3 offset = (k/3*2-1) * ivec3(equal(ivec3(k%3), ivec3(0, 1, 2)));
            ivec4 prevFrameLight = imageLoad(
                lightStorage,
                ivec3(gl_WorkGroupSize.xyz) * (ivec3(gl_WorkGroupID.xyz) + offset) +
                ivec3(
                    index % gl_WorkGroupSize.x,
                    index / gl_WorkGroupSize.x % gl_WorkGroupSize.y,
                    index / (gl_WorkGroupSize.x * gl_WorkGroupSize.y)));
            if (prevFrameLight.w > 0) {
                registerLight(prevFrameLight.xyz, meanPos, prevFrameLight.w * 0.0001);
            }
        }
    }

    #if HELD_LIGHTING_MODE > 0
        if (index < 125 && anyInFrustrum) {
            ivec3 lightPos0 = ivec3(index%5, index/5%5, index/25%5) - 2;
            registerLight(lightPos0, meanPos, 0.0);
        }
    #endif
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
    if (insideFrustrum && activeFrame) {
        for (uint thisLightIndex = 0; thisLightIndex < MAX_LIGHT_COUNT; thisLightIndex++) {
            if (thisLightIndex >= lightCount) break;
            vec3 lightPos = lightPositions[thisLightIndex];
            float ndotl0 = infnorm(vxPos - 0.5 * normal - lightPos) < 0.5 || !hasNeighbor ? 1.0 :
                max(0, (dot(normalize(lightPos - vxPos + 0.5 * normal), normal)));
            vec3 dir = lightPos - vxPos;
            float dirLen = length(dir);
            float thisTraceLen = (extraData[thisLightIndex]>>17 & 31)/32.0;
            if (dirLen < thisTraceLen * LIGHT_TRACE_LENGTH && ndotl0 > 0.001) {
                float lightBrightness = 1.5 * thisTraceLen;
                lightBrightness *= lightBrightness;
                float ndotl = ndotl0 * lightBrightness;
                vec4 rayHit1 = coneTrace(vxPos, (1.0 - 0.1 / (dirLen + 0.1)) * dir, 0.4 / dirLen, dither);
                if (rayHit1.w > 0.01) {
                    #ifdef TRANSLUCENT_LIGHT_TINT
                        vec3 translucentNormal = vec3(0);
                        vec3 translucentPos = voxelTrace(
                            vxPos,
                            dir,
                            translucentNormal,
                            1<<8
                        ).xyz;
                        vec3 translucentCol = vec3(1.0);
                        if (length(translucentPos - vxPos) < dirLen - 1) {
                            translucentCol = getColor(translucentPos - 0.1 * translucentNormal).rgb;
                        }
                    #endif
                    vec3 lightColor = lightCols[thisLightIndex];
                    float totalBrightness = ndotl
                        * distanceFalloff(dirLen / (thisTraceLen * LIGHT_TRACE_LENGTH))
                        * lightBrightness;
                    writeColor += lightColor
                    #ifdef TRANSLUCENT_LIGHT_TINT
                        * translucentCol
                    #endif
                        * rayHit1.w
                        * totalBrightness;
                    int thisWeight = int(10000.5 * length(lightColor) * totalBrightness);
                    atomicMax(lightCoords[thisLightIndex].w, thisWeight);
                }
            }
        }
    }

    if (anyInFrustrum) {
        imageStore(irradianceCacheI, coords + ivec3(0, voxelVolumeSize.y, 0), vec4(writeColor, 1));
        ivec4 lightPosToStore = (index < lightCount && lightCoords[index].w > 0) ? lightCoords[index] : ivec4(0);
        imageStore(lightStorage, coords, lightPosToStore);
    }
}
#endif

// This program calculates GI
#ifdef CSH_B
#ifdef GI
    #if VX_VOL_SIZE == 0
        const ivec3 workGroups = ivec3(12, 8, 12);
    #elif VX_VOL_SIZE == 1
        const ivec3 workGroups = ivec3(16, 12, 16);
    #elif VX_VOL_SIZE == 2
        const ivec3 workGroups = ivec3(32, 16, 32);
    #elif VX_VOL_SIZE == 3
        const ivec3 workGroups = ivec3(64, 16, 64);
    #endif

    layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

    layout(rgba16f) uniform volatile image3D irradianceCacheI;
    #include "/lib/vx/SSBOs.glsl"
    #include "/lib/vx/voxelReading.glsl"
    #include "/lib/util/random.glsl"

    shared vec3[5] frustrumSides;

    shared ivec3[512] activeLocs;
    shared int activeCount;

    const vec2[4] squareCorners = vec2[4](vec2(-1, -1), vec2(1, -1), vec2(1, 1), vec2(-1, 1));
    #if defined REALTIME_SHADOWS && defined OVERWORLD

        const vec2 sunRotationData = vec2(cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994));
        float ang = (fract(timeAngle - 0.25) + (cos(fract(timeAngle - 0.25) * 3.14159265358979) * -0.5 + 0.5 - fract(timeAngle - 0.25)) / 3.0) * 6.28318530717959;
        vec3 sunVec = vec3(-sin(ang), cos(ang) * sunRotationData);
        vec3 lightVec = sunVec * ((timeAngle < 0.5325 || timeAngle > 0.9675) ? 1.0 : -1.0);
        float SdotU = sunVec.y;
        float sunFactor = SdotU < 0.0 ? clamp(SdotU + 0.375, 0.0, 0.75) / 0.75 : clamp(SdotU + 0.03125, 0.0, 0.0625) / 0.0625;
        float sunVisibility = clamp(SdotU + 0.0625, 0.0, 0.125) / 0.125;
        float sunVisibility2 = sunVisibility * sunVisibility;

        #define gl_FragCoord vec4(632.5, 126.5, 1.0, 1.0)
        #include "/lib/util/spaceConversion.glsl"
        #include "/lib/lighting/shadowSampling.glsl"
    #endif
    #if defined OVERWORLD && defined CAVE_FOG
        #define GL_CAVE_FACTOR
        #include "/lib/atmospherics/fog/caveFactor.glsl"
    #endif

    #include "/lib/colors/lightAndAmbientColors.glsl"

    vec3 fractCamPos = cameraPositionInt.y == -98257195 ? fract(cameraPosition) : cameraPositionFract;
#else
    const ivec3 workGroups = ivec3(1, 1, 1);
    layout(local_size_x = 1) in;
#endif
void main() {
    #ifdef GI
        if (gl_LocalInvocationID == uvec3(0)) {
            activeCount = 0;
        }
        int index = int(gl_LocalInvocationIndex);
        float dither = nextFloat();
        if (index < 4) {
            vec4 pos = vec4(squareCorners[index], 0.9999, 1);
            pos = gbufferModelViewInverse * (gbufferProjectionInverse * pos);
            frustrumSides[index] = pos.xyz * pos.w;
        } else if (index == 4) {
            frustrumSides[4] = -normalize(gbufferModelViewInverse[2].xyz);
        }
        barrier();
        memoryBarrierShared();
        vec3 sideNormal = vec3(0);
        if (index < 4) {
            sideNormal = -normalize(cross(frustrumSides[index], frustrumSides[(index+1)%4]));
        }
        barrier();
        if(index < 4) {
            frustrumSides[index] = sideNormal;
        }
        barrier();
        memoryBarrierShared();
        ivec3 coords = ivec3(gl_GlobalInvocationID);
        vec3 normal = vec3(0);
        vec3 vxPos = coords - 0.5 * voxelVolumeSize + vec3(0.49, 0.51, 0.502);
        bool insideFrustrum = true;
        for (int k = 0; k < 5; k++) {
            insideFrustrum = (insideFrustrum && dot(vxPos, frustrumSides[k]) > -10.0);
        }

        if (insideFrustrum) {
            float thisDFval = getDistanceField(vxPos);
            int thisOccupancy = imageLoad(occupancyVolume, ivec3(vxPos + 0.5 * voxelVolumeSize)).r;
            if (thisDFval < 0.7 || (thisOccupancy & 1<<8) != 0) {
                activeLocs[atomicAdd(activeCount, 1)] = coords;
            } else {
                vec4 GILight = vec4(0.0);
                for (int k = 0; k < 6; k++) {
                    ivec3 offset = (k/3*2-1)*ivec3(k%3==0, k%3==1, k%3==2);
                    vec4 otherLight = imageLoad(irradianceCacheI, coords + offset);
                    GILight += 0.16667 * otherLight;
                }
                imageStore(irradianceCacheI, coords, GILight);
            }
        }
        barrier();
        memoryBarrierShared();
        memoryBarrierImage();
        if (index < activeCount) {
            coords = activeLocs[index];
            vxPos = coords - 0.5 * voxelVolumeSize + vec3(0.51, 0.49, 0.502);
            float thisDFval = getDistanceField(vxPos);
            int thisOccupancy = imageLoad(occupancyVolume, coords).r;
            bool isOccluded = (thisOccupancy & 1) != 0;
            float maxDFVal = thisDFval;
            for (int k = 0; k < 3; k++) {
                float dplus = getDistanceField(vxPos + mat3(0.5)[k]);
                float dminus = getDistanceField(vxPos - mat3(0.5)[k]);
                if (isOccluded) {
                    dplus = -dplus;
                    dminus = -dminus;
                }
                normal[k] = dplus - dminus;
                maxDFVal = max(max(dplus, dminus), maxDFVal);
            }
            normal = normalize(normal);
            if (any(isnan(normal))) normal = vec3(0);
            if (maxDFVal > 0.1 && length(normal) > 0.5) {
                vec4 GILight = imageLoad(irradianceCacheI, coords);
                float weight = 1.0;
                int intSkyLight = 0; 
                for (int k = 0; k < 6; k++) {
                    ivec3 offset = (k/3*2-1) * ivec3(equal(ivec3(k%3), ivec3(0, 1, 2)));
                    int aroundOccupancy = imageLoad(occupancyVolume, coords + offset).r;
                    intSkyLight |= aroundOccupancy >> 28 & 3;
                    if ((aroundOccupancy & 1) != 0 || getDistanceField(vxPos + 0.5 * offset) < 0.2) continue;
                    float otherWeight = 0.01;
                    GILight += otherWeight * imageLoad(irradianceCacheI, coords + offset);
                    weight += otherWeight;
                }
                float skyLight = mix(vec4(0.0, 0.333, 1.0, 0.666)[intSkyLight], 1.0, 0.4 * eyeBrightness.y / 240.0);
                GILight /= weight;
                vxPos -= min(0.3, thisDFval - 0.1) * normal;
                vec4 ambientContribution = vec4(0);
                for (int sampleNum = 0; sampleNum < GI_SAMPLE_COUNT; sampleNum++) {
                    vec3 dir = normalWeightedHemishpereSample(normal);
                    float ndotl = dot(dir, normal);
                    vec3 hitPos = rayTrace(vxPos, LIGHT_TRACE_LENGTH * dir, dither);
                    vec3 translucentNormal;
                    vec4 translucentPos = voxelTrace(vxPos, LIGHT_TRACE_LENGTH * dir, translucentNormal, 1<<8);
                    vec4 translucentCol = vec4(1);
                    if (translucentPos.w > 1) {
                        translucentCol = getColor(translucentPos.xyz - 0.1 * translucentNormal);
                        translucentCol.xyz = mix(vec3(1), translucentCol.xyz, translucentCol.w);
                    }
                    #ifdef GL_CAVE_FACTOR
                        vec3 ambientHitCol = AMBIENT_MULT * 0.25 * skyLight * ambientColor * clamp(dir.y + 1.6, 0.6, 1) * (1-GetCaveFactor(cameraPosition.y + vxPos.y)) / GI_STRENGTH;
                    #else
                        vec3 ambientHitCol = AMBIENT_MULT * 0.25 * skyLight * ambientColor * clamp(dir.y + 1.6, 0.6, 1) / GI_STRENGTH;
                    #endif
                    vec3 hitCol = vec3(0);
                    if (length(hitPos - vxPos) < LIGHT_TRACE_LENGTH - 0.5 && infnorm(hitPos / voxelVolumeSize) < 0.5) {
                        vec3 hitNormal = vec3(0);
                        for (int k = 0; k < 3; k++) {
                            hitNormal[k] = getDistanceField(hitPos + mat3(0.5)[k]) - getDistanceField(hitPos - mat3(0.5)[k]);
                        }
                        hitNormal = normalize(hitNormal);
                        vec3 hitBlocklight = imageLoad(irradianceCacheI, ivec3(hitPos + 0.5 * hitNormal + vec3(0.5, 1.5, 0.5) * voxelVolumeSize)).rgb;
                        vec4 hitGIColor = imageLoad(irradianceCacheI, ivec3(hitPos + 0.5 * hitNormal + 0.5 * voxelVolumeSize - vec3(0.5)));
                        vec3 hitGIlight = hitGIColor.rgb / max(hitGIColor.a, 0.0001);
                        if (!(length(hitNormal) > 0.5)) hitNormal = vec3(0);
                        #if defined REALTIME_SHADOWS && defined OVERWORLD
                            vec3 sunShadowPos = GetShadowPos(hitPos - fractCamPos);
                            vec3 hitSunlight = SampleShadow(sunShadowPos, 1.2 + 3.8 * skyLight, 1.0) * lightColor * max(dot(hitNormal, sunVec), 0) * float(skyLight > 0.1 || dot(hitNormal, hitPos) < 0.0);
                        #elif defined OVERWORLD
                            vec3 hitSunlight = lightColor * float(skyLight > 0.8);
                        #else
                            const float hitSunlight = 0.0;
                        #endif
                        vec3 hitAlbedo = getColor(hitPos - 0.1 * hitNormal).rgb;
                        hitCol = ((hitBlocklight + 3 * hitSunlight) * 4 + hitGIlight) * hitAlbedo;
                        ambientHitCol *= pow2(length(hitPos - vxPos) / LIGHT_TRACE_LENGTH);
                    }
                    vec3 hitContrib = hitCol * translucentCol.xyz;
                    if (all(greaterThanEqual(ambientHitCol, vec3(0)))) ambientContribution += vec4(ambientHitCol * translucentCol.xyz, 1.0);
                    if (all(greaterThanEqual(hitContrib, vec3(0)))) GILight += vec4(hitContrib, 1.0);
                }
                GILight += min(ambientContribution, vec4(ambientColor * 2.0, 1.0) * ambientContribution.a);
                if (any(isnan(GILight))) GILight = vec4(0);
                imageStore(irradianceCacheI, coords, GILight);
            } else {
                imageStore(irradianceCacheI, coords, vec4(0));
            }
        }
    #endif
}
#endif