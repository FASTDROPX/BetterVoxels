uint posToHash(uvec3 pos) {
    // modified version of David Hoskins' hash without sine 2
    // https://www.shadertoy.com/view/XdGfRR -> common -> hash13
    // licensed as CC-BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/)
    pos *= uvec3(1597334673U, 3812015801U, 2798796415U);
    uint hash = (pos.x ^ pos.y ^ pos.z) * 1597334673U;
    return hash;
}

uint posToHash(vec3 pos) {
    return posToHash(uvec3(pos + 1000));
}

uint posToHash(ivec3 pos) {
    return posToHash(uvec3(pos + 1000));
}