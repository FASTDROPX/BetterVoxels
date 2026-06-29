/////////////////////////////////////
// Complementary Shaders by EminGT //
/////////////////////////////////////

//Common//
#include "/lib/common.glsl"

//////////Fragment Shader//////////Fragment Shader//////////Fragment Shader//////////
#ifdef FRAGMENT_SHADER

noperspective in vec2 texCoord;

//Pipeline Constants//

//Common Variables//

//Common Functions//
float GetLinearDepth(float depth) {
    return (2.0 * near) / (far + near - depth * (far - near));
}

//Includes//
#if FXAA_DEFINE == 1
    #include "/lib/antialiasing/fxaa.glsl"
#endif

//Program//
#include "/lib/vx/voxelReading.glsl"
#include "/lib/vx/irradianceCache.glsl"

vec3 fractCamPos = cameraPositionInt.y == -98257195 ? fract(cameraPosition) : cameraPositionFract;

void main() {
    vec3 color = texelFetch(colortex3, texelCoord, 0).rgb;
        
    #if FXAA_DEFINE == 1
        FXAA311(color);
    #endif
/*
    if (texCoord.x < 0.5) {
        color = texture(colortex10, texCoord).rgb;
    } else if (false) {
        vec4 dir = gbufferModelViewInverse * (gbufferProjectionInverse * vec4(texCoord * 2 - 1, 0.999, 1));
        dir = normalize(dir * dir.w);
        vec3 start = fractCamPos + 2 * dir.xyz;
        vec3 normal;
        vec3 hitPos = rayTrace(
            start,
            dir.xyz * 128,
            fract(dot(
                gl_FragCoord.xy,
                vec2(
                    0.5 + 0.5 * sqrt(5),
                    pow2(0.5 + 0.5 * sqrt(5))
                )
            ))
        );
        normal = normalize(distanceFieldGradient(hitPos));
        if (!(length(normal) > 0.5)) normal = vec3(0);
        if (true) color =
            getColor(hitPos.xyz - 0.1 * normal).xyz * readIrradianceCache(hitPos.xyz + normal * 0.5, normal);
            //vec3(ivec3(getVoxelResolution(hitPos.xyz)) % ivec3(2, 4, 8)) / vec3(1, 3, 7)
            // + 0.2 * normal + 0.2;

    }*/
    /* DRAWBUFFERS:3 */
    gl_FragData[0] = vec4(color, 1.0);
}

#endif

//////////Vertex Shader//////////Vertex Shader//////////Vertex Shader//////////
#ifdef VERTEX_SHADER

noperspective out vec2 texCoord;

//Attributes//

//Common Variables//

//Common Functions//

//Includes//

//Program//
void main() {
    gl_Position = ftransform();

    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}

#endif
