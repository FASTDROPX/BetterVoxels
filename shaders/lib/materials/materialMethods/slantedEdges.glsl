#ifdef GBUFFERS_TERRAIN
    #ifdef ACL_VOXELIZATION
        #include "/lib/misc/voxelization.glsl"
    #endif
    void GenerateEdgeSlopes(inout vec3 normalM, vec3 playerPos) {
        // we will be working in world-aligned coordinates
        normalM = mat3(gbufferModelViewInverse) * normalM;
        vec3 voxelPos = SceneToVoxel(playerPos);
        // position relative to block center, pushed back slightly along normal to avoid floating point precision issues
        vec3 blockRelPos = fract(voxelPos - 0.1 * normalM) - 0.5;
        // the current fragment is at the block edge if it is more than 0.5 blocks - 1 pixel away from the block center in any direction. we keep the direction because we will need it to determine where to tilt the normal later.
        ivec3 edge = ivec3(greaterThan(abs(blockRelPos) - 0.5 + 0.0625 - abs(normalM), vec3(0.0))) * ivec3(sign(blockRelPos) * 1.01);
        // this whole thing works best if the normal is axis-aligned, so we ignore all other cases
        if (max(max(abs(normalM.x), abs(normalM.y)), abs(normalM.z)) < 0.99) {
            edge = ivec3(0);
        }
        #ifdef ACL_VOXELIZATION
            // remove edges between blocks with same voxel ID
            if (edge != ivec3(0) && CheckInsideVoxelVolume(voxelPos)) {
                ivec3 coords = ivec3(voxelPos - 0.05 * normalM);
                uint this_mat = texelFetch(voxel_sampler, coords, 0).r;
                for (int k = 0; k < 3; k++) {
                    if (edge[k] == 0) continue;
                    // if the fragment qualifies as a block edge in this direction, then check the adjacent material directly and diagonally upward (in the direction of the face normal)
                    ivec3 offset = edge * ivec3(equal(ivec3(k), ivec3(0, 1, 2)));
                    uint other_mat = texelFetch(voxel_sampler, coords + offset, 0).r;
                    uint above_mat = texelFetch(voxel_sampler, coords + offset + ivec3(1.01 * normalM), 0).r;
                    if (this_mat == above_mat) {
                        // if the diagonally upward adjacent block is the same, we have an inner edge, so we need to tilt inward instead of outward
                        edge[k] *= -1;
                    } else if (this_mat == other_mat) {
                        // if the directly adjacent block is the same, then we don't need to tilt.
                        edge[k] = 0;
                    }
                }
            }
        #endif
        // apply tilt
        normalM = mat3(gbufferModelView) * normalize(normalM + edge);
    }
#else
    void GenerateEdgeSlopes(inout vec3 normalM) {
        #ifdef GBUFFERS_ENTITIES
            // atlasSize doesn't seem to work for entities
            ivec2 atlasSize = textureSize(tex, 0);
        #endif
        // this is actually only 0.5 * spriteSize, but it is what we need
        vec2 spriteSize = atlasSize * absMidCoordPos;
        // signMidCoordPos * spriteSize is the position relative to the sprite center in pixels
        // we do the same as with the block-relative position, but in texture space rather than world space.
        vec2 edge = vec2(greaterThan(abs(signMidCoordPos * spriteSize) - max(spriteSize, vec2(2)) + 1.0, vec2(0.0))) * sign(signMidCoordPos);
        // this time, we don't transform the normal into a space where it is axis-aligned, instead we use the other basis vectors of the basis in which it is axis-aligned directly.
        normalM = normalize(
            normalM +
            edge.x * tangent +
            edge.y * binormal
        );
    }
#endif
