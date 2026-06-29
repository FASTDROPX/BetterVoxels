#ifndef INCLUDE_MANDELBROT
#define INCLUDE_MANDELBROT
#if FRACTAL_GALAXY ==2
    #define FRACTAL_MAX_ITER 300
#else
    #define FRACTAL_MAX_ITER 100
#endif
int mandelbrot(vec2 coords) {
    float p = pow2(coords.x - 0.25) + coords.y * coords.y;
    if (p * (p + coords.x - 0.25) <= 0.25 * coords.y * coords.y || pow2(coords.x - 1) + coords.y * coords.y <= 0.0625) {
        return -1;
    }
    vec2 z = coords;
    int iter = -1;
    for (int k = 0; k < FRACTAL_MAX_ITER; k++) {
        z = vec2(z.x * z.x - z.y * z.y, 2 * z.x * z.y) + coords;
        if (length(z) > 2.0) {
            iter = k+1;
            break;
        }
    }
    return iter;
}

int julia(vec2 coords, vec2 c) {
    vec2 z = coords;
    int iter = -1;
    for (int k = 0; k < FRACTAL_MAX_ITER; k++) {
        z = vec2(z.x * z.x - z.y * z.y, 2 * z.x * z.y) + c;
        if (length(z) > 2.0) {
            iter = k+1;
            break;
        }
    }
    return iter;
}

vec4 fractalColorMap(float iter) {
    return vec4(iter);
}
void fractalSkyColorMod(inout vec3 skyColor, vec3 dir0, vec3 sunDir) {
    mat3 sunRotMat0 = mat3(-sunDir, normalize(cross(sunDir, vec3(0, 0, 1))), vec3(0));
    sunRotMat0[2] = cross(sunRotMat0[0], sunRotMat0[1]);
    mat3 sunRotMat = inverse(sunRotMat0);
    vec3 dir = sunRotMat * dir0;
    if (dir.x < -0.9) {
        return;
    }
    vec2 coords = 1.3 * dir.yz / (dir.x + 1);
    #if FRACTAL_GALAXY == 2
        coords = -vec2(0.76602, 0.10087) + 0.002 * coords;
    #endif
    #if FRACTAL_GALAXY == 1 || FRACTAL_GALAXY == 2
        int iter_count = mandelbrot(coords);
    #elif FRACTAL_GALAXY == 3
        vec2 c = vec2(-0.8, 0.2);
        int iter_count = julia(coords, c);
    #else
        int iter_count = 0;
    #endif
    vec4 fractalColor = fractalColorMap(iter_count * 1.0 / FRACTAL_MAX_ITER);
    skyColor = mix(skyColor, fractalColor.rgb, fractalColor.a);
}
#endif