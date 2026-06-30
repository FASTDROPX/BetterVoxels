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
#ifdef ECLIPSE_TIME_ACTIVE
    /* RENDERTARGETS:3,15 */
#else
    /* DRAWBUFFERS:3 */
#endif
    gl_FragData[0] = vec4(color, 1.0);

#ifdef ECLIPSE_TIME_ACTIVE
    // ---- Eclipse cinematic time interpolation: feedback update -----------
    // colortex15 holds ONE persistent texel: the smoothed world-space sun,
    // ENCODED to [0,1] (.rgb) with a "seeded" flag in .a so it survives the
    // buffer's default format (this pack declares no custom colortexN format).
    // Each frame we recompute the REAL sun (same math as GetSunVector,
    // overworld branch). During normal play the stored sun tracks the real sun
    // EXACTLY (no lag, no low-precision stepping); only when worldTime JUMPS
    // (/time set, sleeping, plugins) -- i.e. the real sun is >~2 deg off the
    // stored sun -- do we EASE across the gap with an exponential-out step of
    // time-constant TIME_TRANSITION_SPEED seconds. frameTime is the real
    // per-frame delta, so the easing is frame-rate independent.
    vec4 sunState;
    #ifdef OVERWORLD
        const vec2 spr = vec2(cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994));
        float sang = fract(timeAngle - 0.25);
        sang = (sang + (cos(sang * 3.14159265358979) * -0.5 + 0.5 - sang) / 3.0) * 6.28318530717959;
        vec3 sunView = normalize((gbufferModelView * vec4(vec3(-sin(sang), cos(sang) * spr) * 2000.0, 1.0)).xyz);
        vec3 realSun = normalize(mat3(gbufferModelViewInverse) * sunView);

        vec4 prev = texelFetch(colortex15, ivec2(0), 0);
        // Decode the previous smoothed sun, or seed with the real sun on the
        // first frame / uninitialised texel (.a flag clear) so there is no pop.
        vec3 storedSun = (prev.a > 0.5) ? normalize(prev.rgb * 2.0 - 1.0) : realSun;

        // Iteration 13: CONTINUOUS exponential-out easing toward the real sun
        // EVERY frame -- no jump-detect snap. During normal play the real sun
        // barely moves so the eased sun tracks it with an invisible constant
        // lag; when worldTime JUMPS (/time set, sleeping, plugins) the eased sun
        // glides across the whole gap over ~TIME_TRANSITION_SPEED s instead of
        // snapping. frameTime is the real per-frame delta, so the curve is
        // frame-rate independent: ew = 1 - exp(-dt / TIME_TRANSITION_SPEED).
        float ew = clamp(1.0 - exp(-frameTime / max(TIME_TRANSITION_SPEED, 0.0001)), 0.0, 1.0);
        vec3 newSun = mix(storedSun, realSun, ew);
        newSun = (dot(newSun, newSun) > 1e-6) ? normalize(newSun) : realSun;

        sunState = vec4(newSun * 0.5 + 0.5, 1.0); // encode to [0,1] + seeded flag
    #else
        sunState = vec4(0.0);                     // non-overworld: mark unseeded
    #endif
    gl_FragData[1] = sunState;
#endif
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
