uniform sampler3D distanceField;
layout(r32i) uniform restrict iimage3D occupancyVolume;
layout(r32i) uniform restrict iimage3D voxelCols;

#include "/lib/util/random.glsl"

int getVoxelResolution(vec3 pos) {
    return max(min(int(-log2(infnorm(pos/(voxelVolumeSize-2.01))))-1, VOXEL_DETAIL_AMOUNT-1), 0);
}

float getDistanceField(vec3 pos) {
    int resolution = getVoxelResolution(pos);
    pos = clamp((1<<resolution) * pos / voxelVolumeSize + 0.5, 0.5/voxelVolumeSize, 1-0.5/voxelVolumeSize);
    pos.y = 0.25 * (pos.y + (frameCounter+1)%2 * 2 + resolution/4);
    return texture(distanceField, pos)[resolution%4];
}

vec3 distanceFieldGradient(vec3 pos) {
    const float epsilon = 0.5/(1<<VOXEL_DETAIL_AMOUNT);
    vec3 grad;
    for (int k = 0; k < 3; k++) {
        grad[k] = (getDistanceField(pos + mat3(0.5*epsilon)[k]) - getDistanceField(pos - mat3(0.5*epsilon)[k])) / epsilon;
    }
    return grad;
}

vec4 getColor(vec3 pos) {
    ivec3 coords = ivec3(pos + 0.5 * voxelVolumeSize);
    if (any(lessThan(coords, ivec3(0))) || any(greaterThanEqual(coords, voxelVolumeSize))) {
        return vec4(0);
    }
    ivec2 rawCol = ivec2(
        imageLoad(voxelCols, coords * ivec3(1, 2, 1)).r,
        imageLoad(voxelCols, coords * ivec3(1, 2, 1) + ivec3(0, 1, 0)).r
    );
    vec4 col = vec4(
        rawCol.r % (1<<13),
        (rawCol.r >> 13) % (1<<13),
        rawCol.g % (1<<13),
        rawCol.g >> 13 & 0x3ff
    );
    col /= max(vec2(20, 4).xxxy * (rawCol.g >> 23), max(max(max(col.r, col.g), col.b), 1) * vec2(1, 4.0/20.0).xxxy);
    col.a = 1.0 - col.a;
    return col;
}

int getLightLevel(ivec3 coords) {
    return imageLoad(occupancyVolume, coords).r >> 6 & 15; //FIXME not implemented
}

vec3 rayTrace(vec3 start, vec3 dir, float dither) {
    float dirLen = infnorm(dir);
    dir /= dirLen;
    float w = 0.001 + dither * getDistanceField(start + 0.001 * dir);
    for (int k = 0; k < RT_STEPS; k++) {
        float thisdist = getDistanceField(start + w * dir);
        if (abs(thisdist) < 0.0001) {
            break;
        }
        w += thisdist;
        if (w > dirLen) break;
    }
    return start + min(w, dirLen) * dir;
}
vec4 coneTrace(vec3 start, vec3 dir, float angle, float dither) {
    float angle0 = angle;
    float dirLen = infnorm(dir);
    dir /= dirLen;
    float w = 0.001 + dither * getDistanceField(start + 0.001 * dir);
    vec4 color = vec4(0.0);
    int k;
    for (k = 0; k < RT_STEPS; k++) {
        vec3 thisPos = start + w * dir;
        float thisdist = getDistanceField(thisPos);

        #ifdef DIRECTION_UPDATING_CONETRACE
            if (thisdist < angle * w) {
                vec3 dfGrad = distanceFieldGradient(thisPos);
                dfGrad = normalize(dfGrad - dot(dir, dfGrad) * dir);
                if (!any(isnan(dfGrad))) {
                    float offsetLen = 0.5 * max(0.0, angle * w - thisdist);
                    dir = normalize(dir + offsetLen/w * dfGrad);
                    thisPos = start + w * dir;
                    thisdist += offsetLen;
                }
                angle = min(angle, thisdist / w);
            }
        #else
            angle = min(angle, thisdist / w);
        #endif
        #ifdef TRANSLUCENT_LIGHT_TINT
        if (thisdist < 0.75) {
            ivec3 coords = ivec3(thisPos + 1000) - 1000 + voxelVolumeSize/2;
            if ((imageLoad(occupancyVolume, coords).r >> 8 & 1) == 1) {
                vec4 localCol = getColor(thisPos);
                color += vec4(localCol.rgb, 1.0) * max(0.0, 1.2 * min(2 * localCol.a, 2 - 2 * localCol.a) - 0.2);
            }
        }
        #endif
        w += thisdist;
        if (angle < 0.01 * angle0 || w > dirLen) break;
    }
    return vec4(
        angle > 0.01 * angle0 ?
        mix(vec3(1.0), color.rgb / max(color.a, 0.0001), min(1.0, color.a * 2)) :
        start + min(w, dirLen) * dir,
        max(0, float(w > dirLen * 0.97) * (angle/angle0 - 0.01) / 0.99));
}

vec4 voxelTrace(vec3 start, vec3 dir, out vec3 normal, int hitMask) {
    dir += 0.000001 * vec3(equal(dir, vec3(0)));
    vec3 stp = 1.0 / abs(dir);
    vec3 dirsgn = sign(dir);
    vec3 progress = (0.5 + 0.5 * dirsgn - fract(start)) * stp * dirsgn;
    float w = 0.000001;
    normal = vec3(0);
    for (int k = 0; k < 2000; k++) {
        vec3 thisVoxelPos = start + w * dir;
        ivec3 thisVoxelCoord = ivec3(thisVoxelPos + 0.5 * normal * dirsgn + voxelVolumeSize/2);
        if (any(greaterThanEqual(thisVoxelCoord, voxelVolumeSize)) || any(lessThan(thisVoxelCoord, ivec3(0)))) {
            break;
        }
        int thisVoxelData = imageLoad(occupancyVolume, thisVoxelCoord).r;
        if (w > 1 || (thisVoxelData & hitMask) != 0) {
            normal *= -dirsgn;
            return vec4(start + w * dir, thisVoxelData & hitMask);
        }
        w = min(min(progress.x, progress.y), progress.z);
        normal = vec3(equal(progress, vec3(w)));
        progress += normal * stp;
    }
    return vec4(-10000);
}

