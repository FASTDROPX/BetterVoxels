#ifndef SSBO
    #define SSBO
    #ifndef WRITE_TO_SSBOS
        #define READONLY
        #define WRITE_TO_SSBOS readonly
    #endif

    layout(std430, binding=0) WRITE_TO_SSBOS buffer stuff {
        mat4 gbufferPreviousModelViewInverse;
        mat4 gbufferPreviousProjectionInverse;
        mat4 reprojectionMatrix;
        uint globalLightHashMap[];
    };
    #ifdef READONLY
        #undef WRITE_TO_SSBOS
    #endif
#endif
