#define gl_FragCoord vec4(gl_GlobalInvocationID.xy + 0.5, 0.99, 1.0)
#include "/lib/common.glsl"

#ifdef CSH

const vec2 workGroupsRender = vec2(0.5, 0.5);

layout(local_size_x = 16, local_size_y = 16) in;

const vec2 sunRotationData = vec2(cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994));
#ifdef OVERWORLD
    float ang0 = fract(timeAngle - 0.25);
    float ang = (ang0 + (cos(ang0 * 3.14159265358979) * -0.5 + 0.5 - ang0) / 3.0) * 6.28318530717959;
    vec3 sunVec = normalize((gbufferModelView * vec4(vec3(-sin(ang), cos(ang) * sunRotationData) * 2000.0, 1.0)).xyz);
#elif defined END
    vec3 sunVec = normalize((gbufferModelView * vec4(vec3(0.0, sunRotationData * 2000.0), 1.0)).xyz);
#else
    vec3 sunVec = vec3(0.0);
#endif

vec3 upVec = normalize(gbufferModelView[1].xyz);
float SdotU = dot(sunVec, upVec);
float sunFactor = SdotU < 0.0 ? clamp(SdotU + 0.375, 0.0, 0.75) / 0.75 : clamp(SdotU + 0.03125, 0.0, 0.0625) / 0.0625;
float sunVisibility = clamp(SdotU + 0.0625, 0.0, 0.125) / 0.125;
float sunVisibility2 = sunVisibility * sunVisibility;
float shadowTimeVar1 = abs(sunVisibility - 0.5) * 2.0;
float shadowTimeVar2 = shadowTimeVar1 * shadowTimeVar1;
float shadowTime = shadowTimeVar2 * shadowTimeVar2;

float vlFactor = 0.0;

vec2 view = vec2(viewWidth, viewHeight);

#include "/lib/atmospherics/fog/mainFog.glsl"
#include "/lib/colors/skyColors.glsl"
#include "/lib/util/spaceConversion.glsl"
#include "/lib/materials/materialMethods/reflections.glsl"

layout(rgba16f) uniform image2D colorimg10;

void main() {
    #ifdef PBR_REFLECTIONS
        ivec2 coord = 2 * ivec2(gl_GlobalInvocationID.xy);

        float z0 = texelFetch(depthtex0, coord, 0).r;
        vlFactor = texelFetch(colortex4, ivec2(viewWidth-1, viewHeight-1), 0).r;
        vec4 screenPos = vec4((coord.xy + 0.5) / view, z0, 1.0);
        vec4 viewPos = gbufferProjectionInverse * (screenPos * 2.0 - 1.0);
        viewPos /= viewPos.w;
        float lViewPos = length(viewPos);
        vec3 nViewPos = normalize(viewPos.xyz);
        vec3 playerPos = ViewToPlayer(viewPos.xyz);

        float dither = texelFetch(noisetex, coord % 128, 0).b;
        #if defined TAA || defined TEMPORAL_FILTER
            dither = fract(dither + goldenRatio * mod(float(frameCounter), 3600.0));
        #endif

        vec3 texture5 = texelFetch(colortex5, coord, 0).rgb;
        vec3 normalM = mat3(gbufferModelView) * texture5;
        float smoothnessD = 0.0;
        int materialMaskInt = 0;

        vec3 texture6 = texelFetch(colortex6, coord, 0).rgb;
        bool entityOrHand = z0 < 0.56;
        materialMaskInt = int(texture6.g * 255.1);
        float intenseFresnel = 0.0;
        smoothnessD = texture6.r;

        #ifdef IPBR
            float ssao;
            vec3 reflectColor;
            #include "/lib/materials/materialHandling/deferredMaterials.glsl"
        #else
            if (materialMaskInt <= 240) {
                #ifdef CUSTOM_PBR
                    #if RP_MODE == 2 // seuspbr
                        float metalness = materialMaskInt / 240.0;

                        intenseFresnel = metalness;
                    #elif RP_MODE == 3 // labPBR
                        float metalness = float(materialMaskInt >= 230);

                        intenseFresnel = materialMaskInt / 240.0;
                    #endif
                #endif
            }
        #endif

        float skyLightFactor = texture6.b;
        float fresnel = clamp(1.0 + dot(normalM, nViewPos), 0.0, 1.0);

        vec2 roughCoord = gl_FragCoord.xy / 128.0;
        #ifdef TAA
            float noiseMult = 0.3;
        #else
            float noiseMult = 0.1;
        #endif
        #ifdef TEMPORAL_FILTER
            float blendFactor = 1.0;
            float writeFactor = 1.0;
        #endif
        #if defined CUSTOM_PBR || defined IPBR && defined IS_IRIS
            if (entityOrHand) {
                noiseMult *= 0.1;
                #ifdef TEMPORAL_FILTER
                    blendFactor = 0.0;
                    writeFactor = 0.0;
                #endif
            }
        #endif
        noiseMult *= pow2(1.0 - smoothnessD);

        vec3 roughNoise = vec3(texture2D(noisetex, roughCoord).r, texture2D(noisetex, roughCoord + 0.1).r, texture2D(noisetex, roughCoord + 0.2).r);
        roughNoise = fract(roughNoise + vec3(dither, dither * goldenRatio, dither * pow2(goldenRatio)));
        roughNoise = noiseMult * (roughNoise - vec3(0.5));

        normalM += roughNoise;

        vec4 reflection = GetReflection(normalM, viewPos.xyz, nViewPos, playerPos, lViewPos, z0,
                                        depthtex0, dither, skyLightFactor, fresnel,
                                        smoothnessD, vec3(0.0), vec3(0.0), vec3(0.0), 0.0);
        if (any(isnan(reflection))) reflection = vec4(0);
        imageStore(
            colorimg10,
            coord / 2,
            vec4(reflection.rgb, 1.0)
        );
    #endif
}
#endif
#ifdef CSH_A

const vec2 workGroupsRender = vec2(1.0, 1.0);

layout(local_size_x = 16, local_size_y = 16) in;

layout(rgba16f) uniform image2D colorimg8;
uniform sampler2D colortex10;

#include "/lib/util/random.glsl"

void main() {
    #ifdef PBR_REFLECTIONS
        ivec2 coord = ivec2(gl_GlobalInvocationID.xy);

        float z0 = texelFetch(depthtex0, coord, 0).r;
        vec4 filteredReflection = vec4(0);
        if (z0 < 1.0) {
            vec3 normalM = texelFetch(colortex5, coord, 0).rgb;
            vec4 texture6 = texelFetch(colortex6, coord, 0);
            for (int k = 0; k < 10; k++) {
                ivec2 newCoord = ivec2(coord * 0.5 + 0.5 + 0.8 * randomGaussian());
                vec3 aroundReflection = texelFetch(colortex10, newCoord, 0).rgb;
                vec3 aroundNormal = texelFetch(colortex5, newCoord << 1, 0).rgb;
                vec4 aroundTexture6 = texelFetch(colortex6, newCoord << 1, 0);
                float thisWeight = exp(
                    -10 * dot(normalM - aroundNormal, normalM - aroundNormal)
                    - 10 * dot(texture6 - aroundTexture6, texture6 - aroundTexture6)
                );
                filteredReflection += thisWeight * vec4(aroundReflection, 1);
            }
        }
        barrier();
        imageStore(colorimg8, coord, filteredReflection / (max(filteredReflection.w, 1e-3)));
    #endif
}

#endif