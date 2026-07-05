//////Fragment Shader//////Fragment Shader//////
#ifdef FRAGMENT_SHADER

#ifdef BLOCKLIGHT_HIGHLIGHT
    uniform sampler2D colortex8;
#endif
layout(r32ui) uniform writeonly uimage2D colorimg9;

void main() {
    imageStore(colorimg9, ivec2(gl_FragCoord.xy), uvec4(1<<31));
    /*RENDERTARGETS:8*/
    gl_FragData[0] = vec4(2);
    #ifdef BLOCKLIGHT_HIGHLIGHT
        /*RENDERTARGETS:8,6*/
        gl_FragData[1] = texelFetch(colortex8, ivec2(gl_FragCoord.xy), 0);
    #endif
}
#endif

//////Vertex Shader//////Vertex Shader//////
#ifdef VERTEX_SHADER
void main() {
    gl_Position = ftransform();
}
#endif
