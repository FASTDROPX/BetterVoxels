#include "/lib/common.glsl"

#ifdef CSH_A
const vec2 workGroupsRender = vec2(1.0, 1.0);
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

vec2 view = vec2(viewWidth, viewHeight);

uniform sampler2D colortex10;
#ifdef BLOCKLIGHT_HIGHLIGHT
    uniform sampler2D colortex13;
    layout(rgba16f) uniform image2D colorimg14;
    layout(rgba8) uniform writeonly image2D colorimg6;
#endif
layout(rgba16f) uniform image2D colorimg12;

#include "/lib/util/random.glsl"
#include "/lib/vx/irradianceCache.glsl"

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

shared vec3 readColors[14][14];
#ifdef BLOCKLIGHT_HIGHLIGHT
    shared vec3 readSpeculars[14][14];
    shared float smoothnesses[14][14];
#endif
shared vec4 normalDepthDatas[14][14];


void main() {
    vec3 fractCamPos =
        cameraPositionInt.y == -98257195 ?
        fract(cameraPosition) :
        cameraPositionFract;
    vec3 prevFractCamPos = 
        cameraPositionInt.y == -98257195 ?
        fract(previousCameraPosition) :
        previousCameraPositionFract;
    ivec3 floorCamPosOffset =
        cameraPositionInt.y == -98257195 ?
        ivec3((floor(cameraPosition) - floor(previousCameraPosition)) * 1.001) :
        cameraPositionInt - previousCameraPositionInt;
    vec3 fractCamPosOffset = fractCamPos - prevFractCamPos;

    ivec2 texelCoord = ivec2(gl_GlobalInvocationID);
    #if BLOCKLIGHT_RESOLUTION == 1
        imageStore(
            colorimg12,
            texelCoord,
            texelFetch(colortex10, texelCoord, 0)
        );
        #ifdef BLOCKLIGHT_HIGHLIGHT
            imageStore(
                colorimg14,
                texelCoord,
                texelFetch(colortex13, texelCoord, 0)
            );
        #endif
    #else
        int index = int(gl_LocalInvocationID.x) + 16 * int(gl_LocalInvocationID.y);
        ivec2 lowerBound = ivec2(gl_WorkGroupID.xy) * 16 / BLOCKLIGHT_RESOLUTION - 2;
        ivec2 upperBound = ivec2(gl_WorkGroupID.xy + 1) * 16 / BLOCKLIGHT_RESOLUTION + 4;
        ivec2 readSize = upperBound - lowerBound;
        if (index < readSize.x * readSize.y) {
            ivec2 readCoords = ivec2(index % readSize.x, index / readSize.x);
            readColors[readCoords.x][readCoords.y] = texelFetch(colortex10, readCoords + lowerBound, 0).rgb;
            #ifdef BLOCKLIGHT_HIGHLIGHT
                readSpeculars[readCoords.x][readCoords.y] = texelFetch(colortex13, readCoords + lowerBound, 0).rgb;
            #endif
            ivec2 hrReadCoords
                = (readCoords + lowerBound) * BLOCKLIGHT_RESOLUTION
                + ivec2(
                    BLOCKLIGHT_RESOLUTION
                    * fract(vec2(
                        frameCounter % 1000 * 1.618033988749895,
                        frameCounter % 1000 * 1.618033988749895 * 1.618033988749895
                    ) + vec2(
                        (readCoords.x + lowerBound.x) * 1.618033988749895 * 1.618033988749895 * 1.618033988749895,
                        (readCoords.x + lowerBound.x) * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895
                    ) + vec2(
                        (readCoords.y + lowerBound.y) * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895,
                        (readCoords.y + lowerBound.y) * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895
                    ))
                );
            vec4 normalDepthData = texelFetch(colortex8, hrReadCoords, 0);
            normalDepthData.w *= 100.0;
            normalDepthDatas[readCoords.x][readCoords.y] = normalDepthData;
            #ifdef BLOCKLIGHT_HIGHLIGHT
                smoothnesses[readCoords.x][readCoords.y] = texelFetch(colortex3, hrReadCoords, 0).r;
            #endif
        }
        barrier();
        memoryBarrierShared();
        vec2 lrTexelCoord = vec2(texelCoord + 0.5) / BLOCKLIGHT_RESOLUTION;
        vec2 localLrTexCoord = vec2(lrTexelCoord) - lowerBound;
        vec2 weights = fract(lrTexelCoord);
        vec4 normalDepthData = texelFetch(colortex8, texelCoord, 0);
        float thisSmoothness = texelFetch(colortex3, texelCoord, 0).r;
        vec4 clipPos = vec4((texelCoord + 0.5) / view, 1.0 - normalDepthData.a, 1.0) * 2.0 - 1.0;
        vec4 playerPos = gbufferModelViewInverse * (gbufferProjectionInverse * clipPos);
        vec3 vxPos = playerPos.xyz / playerPos.w + fractCamPos;
        #if defined DO_PIXELATION_EFFECTS && defined PIXELATED_BLOCKLIGHT
            vxPos = floor(vxPos * PIXEL_TEXEL_SCALE + 0.5 * normalDepthData.xyz) / PIXEL_TEXEL_SCALE + 0.5 / PIXEL_TEXEL_SCALE;
            float lPlayerPos = length(playerPos.xyz);
        #endif
        playerPos.xyz = (vxPos - fractCamPos) * playerPos.w;
        playerPos.xyz += playerPos.w * (fractCamPosOffset + floorCamPosOffset);
        vec4 prevClipPos = gbufferPreviousProjection * (gbufferPreviousModelView * playerPos);
        prevClipPos = prevClipPos / prevClipPos.w * 0.5 + 0.5;

        vec3 writeColor = imageLoad(colorimg12, ivec2(view * prevClipPos.xy)).rgb;
        #ifdef BLOCKLIGHT_HIGHLIGHT
            vec3 writeSpecular = imageLoad(colorimg14, ivec2(view * prevClipPos.xy)).rgb;
        #endif
        float totalWeight = 1.0;
        if (length(texture(colortex4, prevClipPos.xy).gba * 2 - 1 - normalDepthData.xyz) > 0.3 || clamp(prevClipPos.xy, vec2(0), vec2(1)) != prevClipPos.xy) {
            totalWeight = 1e-2;
            writeColor = 1e-2 * readSurfaceVoxelBlocklight(vxPos, normalDepthData.xyz);
            #ifdef BLOCKLIGHT_HIGHLIGHT
                writeSpecular = vec3(0.0);
            #endif
        }
        normalDepthData.w *= 100.0;
        vec3[2] colorBounds = vec3[2](vec3(10000), vec3(0));
        #ifdef BLOCKLIGHT_HIGHLIGHT
            vec3[2] specularBounds = vec3[2](vec3(10000), vec3(0));
        #endif
        for (int k = 0; k < 8; k++) {
            vec2 texCoordOffset = randomGaussian() * 0.8;
            ivec2 c = ivec2(localLrTexCoord + texCoordOffset);
            if (c == clamp(c, ivec2(0), readSize - 1)) {
                vec2 coffset
                    = ivec2(
                        BLOCKLIGHT_RESOLUTION
                        * fract(vec2(
                            frameCounter % 1000 * 1.618033988749895,
                            frameCounter % 1000 * 1.618033988749895 * 1.618033988749895
                        ) + vec2(
                            (c.x + lowerBound.x) * 1.618033988749895 * 1.618033988749895 * 1.618033988749895,
                            (c.x + lowerBound.x) * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895
                        ) + vec2(
                            (c.y + lowerBound.y) * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895,
                            (c.y + lowerBound.y) * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895 * 1.618033988749895
                        ))
                    ) / float(BLOCKLIGHT_RESOLUTION);
                texCoordOffset = c + coffset - localLrTexCoord;
                vec4 newNormalDepthData = normalDepthDatas[c.x][c.y];
                #if defined DO_PIXELATION_EFFECTS && defined PIXELATED_BLOCKLIGHT
                    vec2 newTexelCoord = texelCoord + texCoordOffset * BLOCKLIGHT_RESOLUTION;
                    vec4 newClipPos = vec4((newTexelCoord + 0.5) / view, 1.0 - newNormalDepthData.a, 1.0) * 2.0 - 1.0;
                    vec4 newPlayerPos = gbufferModelViewInverse * (gbufferProjectionInverse * newClipPos);
                    vec3 newVxPos = newPlayerPos.xyz / newPlayerPos.w + fractCamPos;
                    newVxPos = floor(newVxPos * PIXEL_TEXEL_SCALE + 0.5 * newNormalDepthData.xyz) / PIXEL_TEXEL_SCALE + 0.5 / PIXEL_TEXEL_SCALE;
                #endif

                float weight = max(1e-5, 1.0 - 5.0 * (
                        length(normalDepthData - newNormalDepthData)
                        #ifdef BLOCKLIGHT_HIGHLIGHT
                            + 3 * abs(thisSmoothness - smoothnesses[c.x][c.y])
                        #endif
                    )) * exp(
                        -dot(texCoordOffset, texCoordOffset)*0.8
                        #if defined DO_PIXELATION_EFFECTS && defined PIXELATED_BLOCKLIGHT
                            - 2.0 * PIXEL_TEXEL_SCALE / lPlayerPos * length(vxPos - newVxPos - dot(playerPos.xyz, vxPos - newVxPos) / pow2(lPlayerPos) * playerPos.xyz)
                        #endif
                    );
                vec3 thisCol = readColors[c.x][c.y];
                writeColor += thisCol * weight;
                colorBounds[0] = min(colorBounds[0], thisCol);
                colorBounds[1] = max(colorBounds[1], thisCol);
                #ifdef BLOCKLIGHT_HIGHLIGHT
                    vec3 thisSpecular = readSpeculars[c.x][c.y];
                    writeSpecular += thisSpecular * weight;
                    specularBounds[0] = min(specularBounds[0], thisSpecular);
                    specularBounds[1] = max(specularBounds[1], thisSpecular);
                #endif
                totalWeight += weight;
            }
        }
        writeColor = clamp(writeColor, totalWeight * colorBounds[0], totalWeight * colorBounds[1]);
        imageStore(colorimg12, texelCoord, vec4(writeColor / totalWeight, 1.0));
        #ifdef BLOCKLIGHT_HIGHLIGHT
            writeSpecular = clamp(writeSpecular, totalWeight * specularBounds[0], totalWeight * specularBounds[1]);
            imageStore(colorimg14, texelCoord, vec4(writeSpecular / totalWeight, 1.0));
        #endif
    #endif
    #ifdef BLOCKLIGHT_HIGHLIGHT
        imageStore(
            colorimg6,
            texelCoord,
            vec4(0)
        );
    #endif
}
#endif