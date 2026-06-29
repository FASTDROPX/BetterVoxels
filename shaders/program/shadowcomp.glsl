#include "/lib/common.glsl"

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

layout(rgba16f) uniform image3D distanceFieldI;
layout(r32i) uniform restrict iimage3D occupancyVolume;
layout(r32i) uniform restrict iimage3D voxelCols;

ivec3 floorCamPosOffset =
    cameraPositionInt.y == -98257195 ?
    ivec3((floor(cameraPosition) - floor(previousCameraPosition)) * 1.001) :
    cameraPositionInt - previousCameraPositionInt;

bvec2 or(bvec2 a, bvec2 b) {
    return bvec2(a.x || b.x, a.y || b.y);
}

bvec3 or(bvec3 a, bvec3 b) {
    return bvec3(a.x || b.x, a.y || b.y, a.z || b.z);
}

bvec4 or(bvec4 a, bvec4 b) {
    return bvec4(a.x || b.x, a.y || b.y, a.z || b.z, a.w || b.w);
}

shared float fullDist[10][10][10];
shared uint isActive;

#include "/lib/vx/positionHashing.glsl"
#define WRITE_TO_SSBOS
#include "/lib/vx/SSBOs.glsl"

const float levelFadeDist = 2.0;

void main() {
    ivec3 baseCoord = ivec3(gl_WorkGroupID) * 8;
    ivec3 localCoord = ivec3(gl_LocalInvocationID);
    ivec3 texCoord = baseCoord + localCoord;
    float[8] theseDists;
    for (int k = 0; k < 8; k++) theseDists[k] = 1000;
    int thisOccupancy = imageLoad(occupancyVolume, texCoord).r;
    #define j 0
    #include "/program/shadowcomp_sdf_loop.glsl"
    #undef j
    #if VOXEL_DETAIL_AMOUNT > 1
        #define j 1
        #include "/program/shadowcomp_sdf_loop.glsl"
        #undef j
    #endif
    #if VOXEL_DETAIL_AMOUNT > 2
        #define j 2
        #include "/program/shadowcomp_sdf_loop.glsl"
        #undef j
    #endif
    #if VOXEL_DETAIL_AMOUNT > 3
        #define j 3
        #include "/program/shadowcomp_sdf_loop.glsl"
        #undef j
    #endif
    #if VOXEL_DETAIL_AMOUNT > 4
        #define j 4
        #include "/program/shadowcomp_sdf_loop.glsl"
        #undef j
    #endif
    #if VOXEL_DETAIL_AMOUNT > 5
        #define j 5
        #include "/program/shadowcomp_sdf_loop.glsl"
        #undef j
    #endif
    #if VOXEL_DETAIL_AMOUNT > 6
        #define j 6
        #include "/program/shadowcomp_sdf_loop.glsl"
        #undef j
    #endif
    #if VOXEL_DETAIL_AMOUNT > 7
        #define j 7
        #include "/program/shadowcomp_sdf_loop.glsl"
        #undef j
    #endif
    imageStore(
        distanceFieldI,
        texCoord + ivec3(0, (frameCounter+1)%2 * 2 * voxelVolumeSize.y, 0),
        vec4(theseDists[0], theseDists[1], theseDists[2], theseDists[3]));
    imageStore(
        distanceFieldI,
        texCoord + ivec3(0, ((frameCounter+1)%2 * 2 + 1) * voxelVolumeSize.y, 0),
        vec4(theseDists[4], theseDists[5], theseDists[6], theseDists[7]));

    // extend colour data into adjacent air for less artefacts in corners etc
    ivec2 rawCol = ivec2(
        imageLoad(voxelCols, texCoord * ivec3(1, 2, 1)).r,
        imageLoad(voxelCols, texCoord * ivec3(1, 2, 1) + ivec3(0, 1, 0)).r
    );
    int dataBits = rawCol.x >> 26 << 26;
    if ((rawCol.g >> 23) == 0) {
        for (int k = 0; k < 6; k++) {
            ivec3 offset = (k/3*2-1) * ivec3(equal(ivec3(k%3), ivec3(0, 1, 2)));
            ivec2 otherRawCol = ivec2(
                imageLoad(voxelCols, (texCoord + offset) * ivec3(1, 2, 1)).r,
                imageLoad(voxelCols, (texCoord + offset) * ivec3(1, 2, 1) + ivec3(0, 1, 0)).r
            );
            if ((otherRawCol.g >> 23) > (rawCol.g >> 23)) {
                rawCol = otherRawCol;
                rawCol.g &= ~(0x3ff << 13);
            }
        }
        if ((rawCol.g >> 23) > 0) {
            rawCol.r &= (1<<26) - 1;
            rawCol.r |= dataBits;
            imageStore(voxelCols, texCoord * ivec3(1, 2, 1), ivec4(rawCol.r));
            imageStore(voxelCols, texCoord * ivec3(1, 2, 1) + ivec3(0, 1, 0), ivec4(rawCol.g));
        }
    }
    if ((thisOccupancy >> 16 & 1) != 0) {
        uint hash0 = posToHash(texCoord - voxelVolumeSize/2) % uint(1<<18);
        globalLightHashMap[hash0*4+3] |= 0xffff0000u;
        globalLightHashMap[hash0*4+3] &= (16 + (16 << 5) + (16 << 10)) << 16 | 0xffffu;
    }
}
#endif

// entity light clumping
#ifdef CSH_A
#if VX_VOL_SIZE == 0
    const ivec3 workGroups = ivec3(3, 2, 3);
#elif VX_VOL_SIZE == 1
    const ivec3 workGroups = ivec3(4, 3, 4);
#elif VX_VOL_SIZE == 2
    const ivec3 workGroups = ivec3(8, 4, 8);
#elif VX_VOL_SIZE == 3
    const ivec3 workGroups = ivec3(16, 4, 16);
#endif

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

layout(r32i) uniform restrict iimage3D occupancyVolume;

#include "/lib/vx/positionHashing.glsl"
#define WRITE_TO_SSBOS
#include "/lib/vx/SSBOs.glsl"
shared int lights[512];
shared int lightCount;
shared ivec4 lightLocs[512];
void main() {
    int index = int(gl_LocalInvocationID.x) + 8 * int(gl_LocalInvocationID.y) + 64 * int(gl_LocalInvocationID.z);
    if (index == 0) {
        lightCount = 0;
    }
    barrier();
    memoryBarrierShared();
    for (int k = 0; k < 64; k++) {
        ivec3 offset = ivec3(k%4, k/4%4, k/16%4);
        ivec3 coord = ivec3(gl_GlobalInvocationID) * 4 + 3 + offset;
        int thisOccupancy = imageLoad(occupancyVolume, coord).r;
        if ((thisOccupancy >> 27 & 1) == 1) {
            int lightIndex = atomicAdd(lightCount, 1);
            if (lightIndex < 512) {
                lightLocs[lightIndex] = ivec4(coord, thisOccupancy >> 22 & 31);
                lights[lightIndex] = 0;
            } else {
                atomicMin(lightCount, 512);
            }
        }
    }
    barrier();
    memoryBarrierShared();
    int aroundLightCount = 1;
    for (int k = index + 1; k < lightCount; k++) {
        if (length(lightLocs[k] - lightLocs[index]) < 1.1) {
            for (int l = index + 1; l < k; l++) {
                if (length(lightLocs[l] - lightLocs[k]) < 1.1) {
                    atomicExchange(lights[l], -1);
                }
            }
            atomicExchange(lights[k], -1);
        }
    }
    barrier();
    memoryBarrierShared();
    bool restoreEmissiveness = false;
    ivec3 coord;
    uvec4 packedLightDataToWrite;
    int maxLightLevel = 0;
    #define MAX_CLUMP_SIZE 128
    if (index < lightCount) {
        coord = lightLocs[index].xyz;
        imageAtomicAnd(occupancyVolume, coord, ~(1<<16));
        if (lights[index] == 0) {
            int thisOccupancy = imageLoad(occupancyVolume, coord).r;
            int linkedLightCount = 1;
            ivec3 linkedLights[MAX_CLUMP_SIZE];
            linkedLights[0] = coord;
            for (int j = 0; j < min(MAX_CLUMP_SIZE, linkedLightCount); j++) {
                if (linkedLightCount >= MAX_CLUMP_SIZE) break;
                for (int i = 0; i < 6; i++) {
                    ivec3 offset = (i/3*2-1)*ivec3(equal(ivec3(i%3), ivec3(0, 1, 2)));
                    ivec3 thisLight = linkedLights[j] + offset;
                    int aroundOccupancy = imageLoad(occupancyVolume, thisLight).r;
                    if ((aroundOccupancy >> 22 & 63) != (thisOccupancy >> 22 & 63)) continue;
                    bool known = false;
                    for (int n = 0; n < min(MAX_CLUMP_SIZE, linkedLightCount); n++) {
                        if (linkedLights[n] == thisLight) {
                            known = true;
                            break;
                        }
                    }
                    if (known || linkedLightCount >= MAX_CLUMP_SIZE) {
                        continue;
                    }
                    linkedLights[linkedLightCount++] = thisLight;
                    maxLightLevel = max(maxLightLevel, aroundOccupancy >> 17 & 31);
                }
            }
            ivec4 meanPos = ivec4(0);
            ivec3 meanCol = ivec3(0);
            for (int k = 0; k < linkedLightCount; k++) {
                restoreEmissiveness = true;
                ivec3 otherLightCoord = linkedLights[k];
                uint hash = posToHash(otherLightCoord - voxelVolumeSize/2) % uint(1<<18);
                uvec4 packedLightData = uvec4(
                    globalLightHashMap[4 * hash],
                    globalLightHashMap[4 * hash + 1],
                    globalLightHashMap[4 * hash + 2],
                    globalLightHashMap[4 * hash + 3]
                );
                ivec4 otherPos = ivec4(packedLightData.x & 0xffffu, packedLightData.x >> 16, packedLightData.y & 0xffffu, packedLightData.y >> 16);
                ivec4 otherCol = ivec4(packedLightData.z & 0xffffu, packedLightData.z >> 16, packedLightData.w & 0xffffu, packedLightData.w >> 16);
                ivec4 offset = ivec4(otherLightCoord - coord, 0);
                meanPos += otherPos + offset * 32 * otherPos.w;
                meanCol += otherCol.xyz;
                if (otherCol.w == 0xffff) {
                    restoreEmissiveness = false;
                    break;
                }
            }
            if (restoreEmissiveness) {
                meanCol /= meanPos.w;
                meanPos /= meanPos.w;
                vec3 probePos = coord + meanPos.xyz/32.0 - vec3(0.991775521, 1.0061213, 1.000062142);
                float minLen = 1000000.0;
                int bestFitIndex = 0;
                for (int k = 0; k < linkedLightCount; k++) {
                    float thisLen = length(probePos - linkedLights[k]);
                    if (thisLen < minLen) {
                        bestFitIndex = k;
                        minLen = thisLen;
                    }
                }
                meanPos.xyz += 32 * (coord - linkedLights[bestFitIndex]);
                coord = linkedLights[bestFitIndex];
                packedLightDataToWrite = uvec4(
                    uint(meanPos.x) | uint(meanPos.y) << 16,
                    uint(meanPos.z) | uint(1) << 16,
                    uint(meanCol.x) | uint(meanCol.y) << 16,
                    uint(meanCol.z) | 0xffff0000u
                );
            }
        }
    }
    barrier();
    if (restoreEmissiveness) {
        imageAtomicAnd(occupancyVolume, coord, 63<<16);
        imageAtomicOr(occupancyVolume, coord, (1 + (maxLightLevel << 1)) << 16);
        uint hash = posToHash(coord - voxelVolumeSize/2) % uint(1<<18);
        for (int k = 3; k >= 0; k--) {
            atomicExchange(globalLightHashMap[4 * hash + k], packedLightDataToWrite[k]);
        }
    }
}
#endif


#ifdef CSH_B
#ifdef LIGHT_CLUMPING
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

layout(r32i) uniform restrict iimage3D occupancyVolume;

uniform vec3 cameraPosition;

#include "/lib/vx/positionHashing.glsl"
#define WRITE_TO_SSBOS
#include "/lib/vx/SSBOs.glsl"
shared ivec3 lightCs[512];
shared int lightCount;
shared ivec4 lightLocs[8][8][8];
shared ivec3 lightCols[8][8][8];
void main() {
    int index = int(gl_LocalInvocationID.x) + 8 * int(gl_LocalInvocationID.y) + 64 * int(gl_LocalInvocationID.z);
    if (index == 0) {
        lightCount = 0;
    }
    ivec3 c = ivec3(gl_LocalInvocationID);
    lightLocs[c.x][c.y][c.z] = ivec4(0);
    lightCols[c.x][c.y][c.z] = ivec3(0);
    barrier();
    memoryBarrierShared();
    ivec3 coord = ivec3(gl_GlobalInvocationID) + ivec3(mod(cameraPosition, vec3(2)));
    int thisOccupancyData0 = imageLoad(occupancyVolume, coord).r;
    if ((thisOccupancyData0 >> 16 & 1) != 0 && (thisOccupancyData0 >> 27 & 1) == 0) {
        lightCs[atomicAdd(lightCount, 1)] = c;
    }
    barrier();
    memoryBarrierShared();
    uint hash = 0xffffffffu;
    bool spreadDown = false;
    if (index < lightCount) {
        c = lightCs[index];
        coord = c + 8 * ivec3(gl_WorkGroupID) + ivec3(mod(cameraPosition, vec3(2)));
        ivec3 lightLoc0 = coord - voxelVolumeSize/2;
        hash = posToHash(lightLoc0) % uint(1<<18);
        int thisOccupancy = imageLoad(occupancyVolume, coord).r;
        uvec2 packedLightSubPos = uvec2(
            globalLightHashMap[4 * hash],
            globalLightHashMap[4 * hash + 1]
        );
        uvec2 packedLightCol = uvec2(
            globalLightHashMap[4 * hash + 2],
            globalLightHashMap[4 * hash + 3]
        );
        ivec4 subPos = ivec4(packedLightSubPos.x & 0xffffu, packedLightSubPos.x >> 16, packedLightSubPos.y & 0xffffu, packedLightSubPos.y >> 16);
        ivec4 col = ivec4(packedLightCol.x & 0xffffu, packedLightCol.x >> 16, packedLightCol.y & 0xffffu, packedLightCol.y >> 16);
        ivec3 downRange = coord - (coord + ivec3(mod(cameraPosition, vec3(2))))%2;
        for (int k = 0; k < 4; k++) {
            atomicAdd(lightLocs[c.x][c.y][c.z][k], subPos[k]);
        }
        for (int k = 0; k < 3; k++) {
            atomicAdd(lightCols[c.x][c.y][c.z][k], col[k]);
        }
        for (int dir1 = 0; dir1 < 3; dir1++) {
            ivec4 d1 = ivec4(0);
            ivec3 offsetCoord1 = coord;
            offsetCoord1[dir1]--;
            d1[dir1]--;
            int otherOccupancy1 = imageLoad(occupancyVolume, offsetCoord1).r;
            if (all(greaterThanEqual(offsetCoord1, downRange)) && (otherOccupancy1 >> 16 & 1) != 0 && (otherOccupancy1 >> 17 & 1023) == (thisOccupancy >> 17 & 1023)) {
                spreadDown = true;
                for (int k = 0; k < 4; k++) {
                    atomicAdd(lightLocs[c.x+d1.x][c.y+d1.y][c.z+d1.z][k], subPos[k] - 32 * d1[k] * subPos[3]);
                }
                for (int k = 0; k < 3; k++) {
                    atomicAdd(lightCols[c.x+d1.x][c.y+d1.y][c.z+d1.z][k], col[k]);
                }
                for (int dir2 = 0; dir2 < 3; dir2++) {
                    ivec4 d2 = d1;
                    ivec3 offsetCoord2 = offsetCoord1;
                    offsetCoord2[dir2]--;
                    d2[dir2]--;
                    int otherOccupancy2 = imageLoad(occupancyVolume, offsetCoord2).r;
                    if (all(greaterThanEqual(offsetCoord2, downRange)) && (otherOccupancy2 >> 16 & 1) != 0 && (otherOccupancy2 >> 17 & 1023) == (thisOccupancy >> 17 & 1023)) {
                        for (int k = 0; k < 4; k++) {
                            atomicAdd(lightLocs[c.x+d2.x][c.y+d2.y][c.z+d2.z][k], subPos[k] - 32 * d2[k] * subPos[3]);
                        }
                        for (int k = 0; k < 3; k++) {
                            atomicAdd(lightCols[c.x+d2.x][c.y+d2.y][c.z+d2.z][k], col[k]);
                        }
                        for (int dir3 = 0; dir3 < 3; dir3++) {
                            ivec4 d3 = d2;
                            ivec3 offsetCoord3 = offsetCoord2;
                            offsetCoord3[dir3]--;
                            d3[dir3]--;
                            int otherOccupancy3 = imageLoad(occupancyVolume, offsetCoord3).r;
                            if (all(greaterThanEqual(offsetCoord3, downRange)) && (otherOccupancy3 >> 16 & 1) != 0 && (otherOccupancy3 >> 17 & 1023) == (thisOccupancy >> 17 & 1023)) {
                                for (int k = 0; k < 4; k++) {
                                    atomicAdd(lightLocs[c.x+d3.x][c.y+d3.y][c.z+d3.z][k], subPos[k] - 32 * d3[k] * subPos[3]);
                                }
                                for (int k = 0; k < 3; k++) {
                                    atomicAdd(lightCols[c.x+d3.x][c.y+d3.y][c.z+d3.z][k], col[k]);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    barrier();
    memoryBarrierShared();
    if (index < lightCount) {
        if (spreadDown) {
            imageAtomicAnd(occupancyVolume, coord, ~(1<<16));
        } else {
            //lightCols[c.x][c.y][c.z] /= max(1, lightLocs[c.x][c.y][c.z].w);
            //lightLocs[c.x][c.y][c.z] /= max(1, lightLocs[c.x][c.y][c.z].w);
            uvec4 packedLightData = uvec4(
                uint(lightLocs[c.x][c.y][c.z].x) | uint(lightLocs[c.x][c.y][c.z].y) << 16,
                uint(lightLocs[c.x][c.y][c.z].z) | uint(lightLocs[c.x][c.y][c.z].w) << 16,
                uint(lightCols[c.x][c.y][c.z].x) | uint(lightCols[c.x][c.y][c.z].y) << 16,
                uint(lightCols[c.x][c.y][c.z].z)
            );
            for (int k = 0; k < 4; k++) {
                globalLightHashMap[4 * hash + k] = packedLightData[k];
            }
        }
    }
}
#else
const ivec3 workGroups = ivec3(1, 1, 1);
layout(local_size_x = 1) in;
void main() {}
#endif
#endif
