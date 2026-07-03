#ifndef INCLUDE_CLOUD_COORD
    #define INCLUDE_CLOUD_COORD

    const float cloudNarrowness = 0.05;

    // Thanks to SixthSurge
    vec2 GetRoundedCloudCoord(vec2 pos, float cloudRoundness) { // cloudRoundness is meant to be 0.125 for clouds and 0.35 for cloud shadows
        vec2 coord = pos.xy + 0.5;
        vec2 signCoord = sign(coord);
        coord = abs(coord) + 1.0;
        vec2 i, f = modf(coord, i);
        f = smoothstep(0.5 - cloudRoundness, 0.5 + cloudRoundness, f);
        coord = i + f;
        return (coord - 0.5) * signCoord / 256.0;
    }

    vec3 ModifyTracePos(vec3 tracePos, int cloudAltitude) {
        #if CLOUD_SPEED_MULT == 100
            // Iteration 24: blissCloudSyncedTime == syncedTime when Eclipse easing
            // is off (byte-identical), and rides the eased visual clock when on, so
            // Reimagined clouds + their terrain shadows time-lapse warp with the sun.
            float wind = blissCloudSyncedTime;
        #else
            #define CLOUD_SPEED_MULT_M CLOUD_SPEED_MULT * 0.01
            #if ECLIPSE_TIME_ACTIVE >= 2
                // Iteration 33: custom cloud speed rides the shaped visual clock
                // UNCONDITIONALLY -- in steady state it advances at the same
                // 1.0/s rate as frameTimeCounter and warps only during a jump.
                // The old runtime "if (eclActive)" could flip between the two
                // clocks mid-transition on a near-half-turn jump, snapping the
                // cloud field -- part of the reported transition hitch.
                float wind = blissCloudSyncedTime * (CLOUD_SPEED_MULT * 0.01);
            #else
                float wind = frameTimeCounter * CLOUD_SPEED_MULT_M;
            #endif
        #endif
        tracePos.x += wind;
        tracePos.z += cloudAltitude * 64.0;
        tracePos.xz *= cloudNarrowness;
        return tracePos.xyz;
    }

#endif