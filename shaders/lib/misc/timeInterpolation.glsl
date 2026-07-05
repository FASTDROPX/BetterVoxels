#ifndef BLISS_TIME_INTERP_GLSL
#define BLISS_TIME_INTERP_GLSL
/*
=======================================================================
  CINEMATIC TIME INTERPOLATION   (Eclipse-style smooth time)
  Iteration 10 -- FRAMEWORK + HOOKS
=======================================================================
  GOAL
  ----
  When the world time JUMPS (/time set, sleeping in a bed, time plugins)
  the sky must not snap. The sun, moon, stars, sky gradient, cloud lighting
  and shadow projection should ease toward the new time over
  TIME_TRANSITION_SPEED seconds using an EXPONENTIAL-OUT curve.

  WHY A FEEDBACK BUFFER IS REQUIRED
  ---------------------------------
  A fragment shader is stateless between frames. To ease a *jump* you must
  remember last frame's VISUAL time, compare it to this frame's real
  worldTime, and step the visual time toward it. That memory needs a
  PERSISTENT buffer (a single texel is enough) that Iris/Optifine does not
  clear between frames. There is no way to smooth a discontinuity without
  per-frame state, so the easing math below is exact and ready, but the
  STATE it eases lives in a buffer that must be declared in the pipeline.

  ARCHITECTURE (the hooks this module lays down)
  ----------------------------------------------
   [STATE]   one persistent texel  feedbackTime = vec2(visualTimeTicks,
             lastFrameTimeCounter).  Reserve it in shaders.properties, e.g.
             a 1x1 region of a spare colortex that is flagged to persist
             (not cleared each frame).
   [UPDATE]  in a prepare/begin pass, once per frame:
                 dt        = frameTimeCounter - feedbackTime.y;      // seconds
                 targetT   = float(worldDay)*24000.0 + float(worldTime); // unwrapped ticks
                 w         = eclipseEaseExpOut(dt);                  // exp-out weight
                 visualT   = eclipseAdvanceTime(feedbackTime.x, targetT, dt);
                 // (snap if the gap is tiny or absurdly large to avoid drift)
                 write vec2(visualT, frameTimeCounter) back to the texel.
   [READ]    sun / moon / sky / shadow / cloud code reads visualT instead of
             worldTime via bliss_GetVisualWorldTime() and derives a visual
             time-of-day / sun vector from it.

  ACTIVATION
  ----------
  This header is COMPILE-SAFE and NON-BREAKING by default: with
  ECLIPSE_TIME_ACTIVE undefined, bliss_GetVisualWorldTime() returns the real
  game time, so every consumer behaves exactly as before. To turn the system
  on you:
     1) reserve + persist the feedback texel in shaders.properties,
     2) add the [UPDATE] pass,
     3) #define ECLIPSE_TIME_ACTIVE and point bliss_GetVisualWorldTime() at
        the feedback texel,
     4) replace worldTime / sunPosition reads in the sky+shadow code with the
        bliss_GetVisual* accessors.
  Steps 1-2-4 touch RV's core sky/shadow pipeline and must be validated
  against a live Iris build, so they are intentionally left as documented
  hooks rather than wired blind (which would risk the whole pack).
=======================================================================
*/

// ---------------------------------------------------------------------
//  EASING  (exact, ready to use)
// ---------------------------------------------------------------------

// Exponential-out weight: the fraction of the remaining gap that is closed
// in a frame of length dt seconds, for the TIME_TRANSITION_SPEED time
// constant. dt -> 0 gives 0 (no move); long dt gives ~1 (snap). This is the
// frame-rate-independent form of  1 - exp(-a*t).
float eclipseEaseExpOut(float dt){
	return clamp(1.0 - exp(-dt / max(TIME_TRANSITION_SPEED, 0.0001)), 0.0, 1.0);
}

// Advance a stored visual value toward a target by one frame (exp-out).
// Works for scalars (time in ticks) and, component-wise, for vectors
// (light/sun vectors, sky params) -- see the vec3 overload below.
float eclipseAdvanceTime(float storedVisual, float target, float dt){
	return mix(storedVisual, target, eclipseEaseExpOut(dt));
}
vec3 eclipseAdvanceVec(vec3 storedVisual, vec3 target, float dt){
	return mix(storedVisual, target, eclipseEaseExpOut(dt));
}

// ---------------------------------------------------------------------
//  READ INTERFACE
// ---------------------------------------------------------------------
//  The cinematic easing is delivered through the SUN VECTOR, not through a
//  smoothed scalar clock. Easing a vector (instead of re-deriving celestial
//  math from a smoothed tick count) keeps the transition robust: the
//  feedback texel stores the already-eased world-space sun direction, and
//  consumers simply read it. The scalar time accessors below stay as the
//  real game time in BOTH modes so they are always defined and link-safe.
float bliss_GetVisualWorldTime(){ return float(worldDay) * 24000.0 + float(worldTime); }

// Convenience: visual time-of-day phase in [0,1) (0 = sunrise reference).
float bliss_GetVisualTimeFract(){
	return fract(bliss_GetVisualWorldTime() / 24000.0);
}

// ---------------------------------------------------------------------
//  SMOOTHED SUN  (Iteration 14 base; Iteration 36: tracker-based)
// ---------------------------------------------------------------------
//  The cinematic easing is applied at the celestial ROOT in lib/common.glsl.
//  As of Iteration 36 the state described in the ARCHITECTURE section above
//  finally exists literally: lib/misc/eclipseTimeTracker.glsl keeps
//  (previous native angle, jump start time, jump start angle, visual angle)
//  in a persistent 2x1 custom image, updated once per frame by a single
//  shadowcomp compute invocation, with a raw-angle delta-trigger and a pure
//  frameTimeCounter timeline. The native timeAngle is replaced by RV's remap
//  of that tracked visual angle, so every pass derives its eased sun/light
//  vector, sky gradient and noon/night factors from the single override via
//  GetSunVector(), and the whole environment glides together. This header
//  keeps the original easing math above as documentation/reference.

#endif // BLISS_TIME_INTERP_GLSL
