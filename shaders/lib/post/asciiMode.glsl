// =============================================================================
//  ASCII MODE  (Iteration 39)
// -----------------------------------------------------------------------------
//  Standalone port of "ASCII Shader" V1.2 (composite1.fsh) as an ISOLATED
//  final-pass overlay for Rethinking Voxels. When the master toggle is ON, the
//  finalized frame is completely reconstructed from the source pack's
//  procedural 8x8 character bitmask matrix: the screen is divided into
//  character cells, each cell's average luminance picks a glyph from the
//  verbatim-ported pattern table (" . i c o P O ? @ FULL"), and screen-space
//  edges optionally swap in the directional glyphs (- / | \) via the source's
//  Sobel-angle table. Runs strictly on the final frame buffer at the end of
//  final.glsl; with the toggle OFF nothing here is executed and the output is
//  bit-identical to Iteration 38.
//
//  Exposed parameters (sub-menu of the Post-Processing tab):
//    PP_ASCII_SCALE       -- character cell size in pixels (source: 8)
//    PP_ASCII_BRIGHTNESS  -- font brightness, percent
//    PP_ASCII_CONTRAST    -- contrast boost on the sampled luminance, percent
//    PP_ASCII_COLOR_MODE  -- 0 white glyphs / 1 original frame colors
//                            (source OG_COLOR) / 2 terminal green / 3 amber
//    PP_ASCII_EDGE_GLYPHS -- directional edge glyphs via the Sobel-angle table
//    PP_ASCII_BACKGROUND  -- background plate brightness, percent
//                            (source BACK_* = 0.05)
// =============================================================================
#ifndef INCLUDE_ASCII_MODE
#define INCLUDE_ASCII_MODE

#define PP_ASCII_MODE 0        //[0 1]
#define PP_ASCII_SCALE 8       //[4 6 8 10 12 16 24 32]
#define PP_ASCII_BRIGHTNESS 100 //[50 60 70 80 90 100 110 120 130 140 150 175 200]
#define PP_ASCII_CONTRAST 100  //[50 60 70 80 90 100 110 120 130 140 150 175 200]
#define PP_ASCII_COLOR_MODE 0  //[0 1 2 3]
#define PP_ASCII_EDGE_GLYPHS 1 //[0 1]
#define PP_ASCII_BACKGROUND 5  //[0 5 10 15 20 25 30]

#if PP_ASCII_MODE == 1

// ---- Glyph tables, ported VERBATIM from ASCII Shader V1.2 ------------------
// Luminance ramp: FULL @ ? O P o c i . (empty).
// Iteration 40: rewritten from "int[8] f(...)" array-RETURN signatures to
// out-parameter form. Array return types are valid GLSL, but Iris's ANTLR
// parser rejects the "type[N] name(" function-signature production (the
// reported missing-';'-at-'{' ParseCancellationException); sized-array
// PARAMETERS and constructors parse fine and are already used elsewhere in
// the pack, so the tables below are byte-identical -- only the plumbing
// changed.
void ppAsciiPattern(float luminance, out int pattern[8]) {
    if (luminance > 0.9)      pattern = int[8](0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0x00, 0x00, 0x00); // FULL
    else if (luminance > 0.8) pattern = int[8](0x70, 0x90, 0x60, 0xB8, 0x88, 0x70, 0x00, 0x00); // @
    else if (luminance > 0.7) pattern = int[8](0x20, 0x00, 0x38, 0x08, 0x70, 0x00, 0x00, 0x00); // ?
    else if (luminance > 0.6) pattern = int[8](0xF0, 0x90, 0x90, 0x90, 0xF0, 0x00, 0x00, 0x00); // O
    else if (luminance > 0.5) pattern = int[8](0x80, 0x80, 0xF0, 0x90, 0xF0, 0x00, 0x00, 0x00); // P
    else if (luminance > 0.4) pattern = int[8](0x70, 0x50, 0x70, 0x00, 0x00, 0x00, 0x00, 0x00); // o
    else if (luminance > 0.3) pattern = int[8](0x70, 0x40, 0x70, 0x00, 0x00, 0x00, 0x00, 0x00); // c
    else if (luminance > 0.2) pattern = int[8](0x20, 0x20, 0x00, 0x20, 0x00, 0x00, 0x00, 0x00); // i
    else if (luminance > 0.1) pattern = int[8](0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00); // .
    else                      pattern = int[8](0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00); // (empty)
}

#if PP_ASCII_EDGE_GLYPHS == 1
    // Directional glyphs for edges (- / | \), by Sobel gradient angle.
    void ppAsciiPatternAngle(float angle, out int pattern[8]) {
        float a = mod(angle, 6.2831853);
        if (a < 0.3927 || a > 5.8905)        pattern = int[8](0x20, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00); // |
        else if (a < 1.1781)                 pattern = int[8](0x80, 0x40, 0x20, 0x10, 0x08, 0x00, 0x00, 0x00); // /
        else if (a < 1.9635)                 pattern = int[8](0x00, 0x00, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00); // -
        else if (a < 2.7489)                 pattern = int[8](0x08, 0x10, 0x20, 0x40, 0x80, 0x00, 0x00, 0x00); // \
        else if (a < 3.5343)                 pattern = int[8](0x20, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00); // |
        else if (a < 4.3197)                 pattern = int[8](0x80, 0x40, 0x20, 0x10, 0x08, 0x00, 0x00, 0x00); // /
        else if (a < 5.1051)                 pattern = int[8](0x00, 0x00, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00); // -
        else                                 pattern = int[8](0x08, 0x10, 0x20, 0x40, 0x80, 0x00, 0x00, 0x00); // \
    }
#endif

float ppAsciiLuma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

// Average luminance of one character cell (16 sub-taps of the source's 64;
// same estimator, bounded cost).
float ppAsciiCellLuma(sampler2D src, vec2 cellOrigin, vec2 cellSize) {
    float sum = 0.0;
    for (int x = 0; x < 4; x++) {
        for (int y = 0; y < 4; y++) {
            vec2 offset = (vec2(x, y) + 0.5) * cellSize * 0.25;
            sum += ppAsciiLuma(texture2D(src, cellOrigin + offset).rgb);
        }
    }
    return sum * 0.0625;
}

vec3 ApplyAsciiMode(sampler2D src, vec2 uv) {
    vec2 res = vec2(viewWidth, viewHeight);
    vec2 cellSize = float(PP_ASCII_SCALE) / res;
    vec2 cellOrigin = floor(uv / cellSize) * cellSize;

    // Cell luminance, with the contrast boost applied around mid-grey.
    float cellLuma = ppAsciiCellLuma(src, cellOrigin, cellSize);
    cellLuma = clamp((cellLuma - 0.5) * (PP_ASCII_CONTRAST * 0.01) + 0.5, 0.0, 1.0);

    int pattern[8];
    #if PP_ASCII_EDGE_GLYPHS == 1
        // Source Sobel over neighbouring cells (single-tap estimator per cell).
        float ppL[9];
        int ppIdx = 0;
        for (int gy = -1; gy <= 1; gy++) {
            for (int gx = -1; gx <= 1; gx++) {
                ppL[ppIdx++] = ppAsciiLuma(texture2D(src, cellOrigin + (vec2(gx, gy) + 0.5) * cellSize).rgb);
            }
        }
        float gradX = (ppL[2] + 2.0 * ppL[5] + ppL[8]) - (ppL[0] + 2.0 * ppL[3] + ppL[6]);
        float gradY = (ppL[6] + 2.0 * ppL[7] + ppL[8]) - (ppL[0] + 2.0 * ppL[1] + ppL[2]);
        float magnitude = length(vec2(gradX, gradY));
        if (magnitude < 0.4) ppAsciiPattern(cellLuma, pattern);
        else ppAsciiPatternAngle(clamp(atan(gradY, gradX), 0.0, 6.2831853), pattern);
    #else
        ppAsciiPattern(cellLuma, pattern);
    #endif

    // Position inside the character cell, mapped onto the 8x8 bitmask.
    vec2 cellPos = mod(uv / cellSize, vec2(1.0));
    ivec2 px = ivec2(floor(cellPos * 8.0));
    bool litUp = (pattern[px.y] & (1 << (7 - px.x))) != 0;
    if (cellLuma < 0.1) litUp = false;

    if (litUp) {
        #if PP_ASCII_COLOR_MODE == 1
            vec3 glyphColor = texture2D(src, cellOrigin + cellSize * 0.5).rgb; // source OG_COLOR
        #elif PP_ASCII_COLOR_MODE == 2
            vec3 glyphColor = vec3(0.25, 1.0, 0.30) * cellLuma;                // terminal green
        #elif PP_ASCII_COLOR_MODE == 3
            vec3 glyphColor = vec3(1.0, 0.72, 0.20) * cellLuma;                // amber
        #else
            vec3 glyphColor = vec3(1.0) * cellLuma;                            // source LIGHT_* mixed by luma
        #endif
        return glyphColor * (PP_ASCII_BRIGHTNESS * 0.01);
    }
    return vec3(PP_ASCII_BACKGROUND * 0.01); // source BACK_* plate
}

#endif // PP_ASCII_MODE == 1

#endif // INCLUDE_ASCII_MODE
