#include "/lib/common.glsl"

//////Fragment Shader//////Fragment Shader//////
#ifdef FRAGMENT_SHADER

in mat4 unprojectionMatrix, projectionMatrix;

vec2 view = vec2(viewWidth, viewHeight);

uniform sampler2D colortex10;

layout(rgba16f) uniform image2D colorimg8;
#ifdef BLOCKLIGHT_HIGHLIGHT
    layout(rgba8) uniform image2D colorimg3;
#endif
layout(r32ui) uniform restrict readonly uimage2D colorimg9;

#define MATERIALMAP_ONLY
#include "/lib/vx/SSBOs.glsl"

void main() {
    ivec2 texelCoord = ivec2(gl_FragCoord.xy);
    float prevDepth = texelFetch(colortex1, texelCoord, 0).r;
    vec4 prevClipPos = vec4(gl_FragCoord.xy / view, prevDepth, 1) * 2 - 1;
    vec4 newClipPos = prevClipPos;
    if (prevDepth > 0.56) {
        newClipPos = unprojectionMatrix * prevClipPos;
        newClipPos.xyz += newClipPos.w * (previousCameraPosition - cameraPosition);
        if (abs(texelFetch(colortex1, texelCoord, 0).y - OSIEBCA * 254.0) < 0.5 * OSIEBCA) {
            vec3 velocity = texelFetch(colortex10, texelCoord, 0).rgb;
            newClipPos.xyz += newClipPos.w * velocity;
        }
        newClipPos = projectionMatrix * newClipPos;
        newClipPos /= newClipPos.w;
    }
    newClipPos = 0.5 * newClipPos + 0.5;
    if (prevClipPos.z > 0.99998) newClipPos.z = 0.9999985;
    if (all(greaterThan(newClipPos.xyz, vec3(0))) && all(lessThan(newClipPos.xyz, vec3(0.999999)))) {
        newClipPos.xy *= view;
        vec2 diff = newClipPos.xy - gl_FragCoord.xy + 0.01;
        ivec2 writePixelCoord = ivec2(gl_FragCoord.xy + floor(diff));
        uint depth = uint((1<<30) * newClipPos.z);
        if (imageLoad(colorimg9, writePixelCoord).r == depth) {
            vec2 prevSampleCoord = (gl_FragCoord.xy - fract(diff)) / view;
            vec4 writeData = vec4(newClipPos.z < 0.999998 ? texture(colortex4, prevSampleCoord).gba * 2 - 1 : vec3(0), 1 - newClipPos.z);
            #ifdef BLOCKLIGHT_HIGHLIGHT
                vec4 materialData = texture(colortex6, prevSampleCoord);
                imageStore(colorimg3, writePixelCoord, materialData);
            #endif
            imageStore(colorimg8, writePixelCoord, writeData);
            
        }
    }
    /*DRAWBUFFERS:3*/
    discard;
}
#endif

//////Vertex Shader//////Vertex Shader//////
#ifdef VERTEX_SHADER

out mat4 unprojectionMatrix, projectionMatrix;

#define MATERIALMAP_ONLY
#include "/lib/vx/SSBOs.glsl"

void main() {
    projectionMatrix =
        gbufferProjection *
        gbufferModelView;
    unprojectionMatrix =
        gbufferPreviousModelViewInverse * 
        gbufferPreviousProjectionInverse;
    gl_Position = ftransform();
}
#endif