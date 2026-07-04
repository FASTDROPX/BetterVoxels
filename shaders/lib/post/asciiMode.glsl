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

// ---- Glyph tables, values ported VERBATIM from ASCII Shader V1.2 -----------
// Luminance ramp: FULL @ ? O P o c i . (empty).
// Iteration 40 (final form): the glyph plumbing is now completely ARRAY-FREE.
// Iris's ANTLR parser rejects array declarators in FUNCTION SIGNATURES (both
// the original "int[8] f(...)" return form and the "out int p[8]" parameter
// form raised the missing-';'-at-'{' ParseCancellationException at the same
// spot), so the eight 8-bit row bitmasks of each glyph are packed into a pair
// of ivec4s (rows 0-3 / rows 4-7) and read back with dynamic vector indexing
// -- plain vector syntax that every GLSL frontend parses. The bitmask VALUES
// are byte-identical to the source shader.
void ppAsciiPattern(float luminance, out ivec4 rowsLo, out ivec4 rowsHi) {
    if (luminance > 0.9)      { rowsLo = ivec4(0xF8, 0xF8, 0xF8, 0xF8); rowsHi = ivec4(0xF8, 0x00, 0x00, 0x00); } // FULL
    else if (luminance > 0.8) { rowsLo = ivec4(0x70, 0x90, 0x60, 0xB8); rowsHi = ivec4(0x88, 0x70, 0x00, 0x00); } // @
    else if (luminance > 0.7) { rowsLo = ivec4(0x20, 0x00, 0x38, 0x08); rowsHi = ivec4(0x70, 0x00, 0x00, 0x00); } // ?
    else if (luminance > 0.6) { rowsLo = ivec4(0xF0, 0x90, 0x90, 0x90); rowsHi = ivec4(0xF0, 0x00, 0x00, 0x00); } // O
    else if (luminance > 0.5) { rowsLo = ivec4(0x80, 0x80, 0xF0, 0x90); rowsHi = ivec4(0xF0, 0x00, 0x00, 0x00); } // P
    else if (luminance > 0.4) { rowsLo = ivec4(0x70, 0x50, 0x70, 0x00); rowsHi = ivec4(0x00, 0x00, 0x00, 0x00); } // o
    else if (luminance > 0.3) { rowsLo = ivec4(0x70, 0x40, 0x70, 0x00); rowsHi = ivec4(0x00, 0x00, 0x00, 0x00); } // c
    else if (luminance > 0.2) { rowsLo = ivec4(0x20, 0x20, 0x00, 0x20); rowsHi = ivec4(0x00, 0x00, 0x00, 0x00); } // i
    else if (luminance > 0.1) { rowsLo = ivec4(0x20, 0x00, 0x00, 0x00); rowsHi = ivec4(0x00, 0x00, 0x00, 0x00); } // .
    else                      { rowsLo = ivec4(0x00, 0x00, 0x00, 0x00); rowsHi = ivec4(0x00, 0x00, 0x00, 0x00); } // (empty)
}

#if PP_ASCII_EDGE_GLYPHS == 1
    // Directional glyphs for edges (- / | \), by Sobel gradient angle.
    void ppAsciiPatternAngle(float angle, out ivec4 rowsLo, out ivec4 rowsHi) {
        float a = mod(angle, 6.2831853);
        rowsHi = ivec4(0x00, 0x00, 0x00, 0x00);
        if (a < 0.3927 || a > 5.8905)        { rowsLo = ivec4(0x20, 0x20, 0x20, 0x20); rowsHi.x = 0x20; } // |
        else if (a < 1.1781)                 { rowsLo = ivec4(0x80, 0x40, 0x20, 0x10); rowsHi.x = 0x08; } // /
        else if (a < 1.9635)                 { rowsLo = ivec4(0x00, 0x00, 0xF8, 0x00); }                  // -
        else if (a < 2.7489)                 { rowsLo = ivec4(0x08, 0x10, 0x20, 0x40); rowsHi.x = 0x80; } // \
        else if (a < 3.5343)                 { rowsLo = ivec4(0x20, 0x20, 0x20, 0x20); rowsHi.x = 0x20; } // |
        else if (a < 4.3197)                 { rowsLo = ivec4(0x80, 0x40, 0x20, 0x10); rowsHi.x = 0x08; } // /
        else if (a < 5.1051)                 { rowsLo = ivec4(0x00, 0x00, 0xF8, 0x00); }                  // -
        else                                 { rowsLo = ivec4(0x08, 0x10, 0x20, 0x40); rowsHi.x = 0x80; } // \
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

    ivec4 rowsLo = ivec4(0);
    ivec4 rowsHi = ivec4(0);
    #if PP_ASCII_EDGE_GLYPHS == 1
        // Source Sobel over neighbouring cells (single-tap estimator per cell).
        // Array-free: the Sobel weights are accumulated directly in the loop
        // (weight for gradX = gx * (2 when gy == 0 else 1), and symmetrically
        // for gradY) -- identical result to the source's kernel matrices.
        float gradX = 0.0;
        float gradY = 0.0;
        for (int gy = -1; gy <= 1; gy++) {
            for (int gx = -1; gx <= 1; gx++) {
                float ppL = ppAsciiLuma(texture2D(src, cellOrigin + (vec2(gx, gy) + 0.5) * cellSize).rgb);
                gradX += ppL * float(gx) * (gy == 0 ? 2.0 : 1.0);
                gradY += ppL * float(gy) * (gx == 0 ? 2.0 : 1.0);
            }
        }
        float magnitude = length(vec2(gradX, gradY));
        if (magnitude < 0.4) ppAsciiPattern(cellLuma, rowsLo, rowsHi);
        else ppAsciiPatternAngle(clamp(atan(gradY, gradX), 0.0, 6.2831853), rowsLo, rowsHi);
    #else
        ppAsciiPattern(cellLuma, rowsLo, rowsHi);
    #endif

    // Position inside the character cell, mapped onto the 8x8 bitmask
    // (dynamic vector indexing picks the row from the ivec4 pair).
    vec2 cellPos = mod(uv / cellSize, vec2(1.0));
    ivec2 px = ivec2(floor(cellPos * 8.0));
    int rowBits = px.y < 4 ? rowsLo[px.y] : rowsHi[px.y - 4];
    bool litUp = (rowBits & (1 << (7 - px.x))) != 0;
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
