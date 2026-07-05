
const vec2[3] waveDirs = vec2[3](
    normalize(vec2(1, 0.4)),
    normalize(vec2(-0.5, -0.6)),
    normalize(vec2(-0.5, 0.8))
);

const vec4 waveLengths = vec4(4, 1.5, 0.3, 0.1);
#ifdef END
    const vec4 waveStrengthCoeffs = 0.1 * vec4(0.7, 0.5, 0.3, 0.1);
#else
    const vec4 waveStrengthCoeffs = 0.8 * vec4(2.4, 1.5, 0.3, 0.1);
#endif

const float waveSpeed = 1.9;

#define WATER_DEFAULT_HEIGHT 63
