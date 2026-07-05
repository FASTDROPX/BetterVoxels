/*
=======================================================================

=======================================================================
*/
#ifndef BLISS_CLOUDS_COMPAT_GLSL
#define BLISS_CLOUDS_COMPAT_GLSL

// ---------------------------------------------------------------------
// Feature toggles
// ---------------------------------------------------------------------
#define VOLUMETRIC_CLOUDS
#define HQ_CLOUDS
#define SKY_GROUND
#define CLOUDS_SHADOWS
#define CloudLayer0
#define CloudLayer1
#define CloudLayer2
// Deliberately LEFT UNDEFINED (their #ifdef branches pull Bliss-only
// subsystems that do not exist in RV, so we keep them compiled out):
//   Daily_Weather, CLOUDS_INTERSECT_TERRAIN, EXCLUDE_WRITE_TO_LUT,
//   CLOUDSHADOWSONLY, WEATHERCLOUDS, TEST

// ---------------------------------------------------------------------
// Ray-march quality
// ---------------------------------------------------------------------
#define minRayMarchSteps 15
#define maxRayMarchSteps 15
#define minRayMarchStepsLQ 10
#define maxRayMarchStepsLQ 30
#define cloud_LevelOfDetail 1
#define cloud_ShadowLevelOfDetail 0
#define cloud_LevelOfDetailLQ 1
#define cloud_ShadowLevelOfDetailLQ 0

// ---------------------------------------------------------------------
// Cloud layer parameters
//   NOTE: the per-layer coverage/density/height, Rain_coverage, Cloud_Speed
//   and the brightness knob are exposed as adjustable OPTIONS in
//   lib/common.glsl (Bliss cloud settings block) so they appear in the
//   in-game menu. Only the fixed shadow strength stays here.
// ---------------------------------------------------------------------
#define CLOUD_SHADOW_STRENGTH 1.0

// ---------------------------------------------------------------------
// fBm / noise shaping
// ---------------------------------------------------------------------
#define fbmAmount 0.5
#define fbmPower1 3.00
#define fbmPower2 2.50

// ---------------------------------------------------------------------
// Atmosphere constants
// Bliss colours its clouds from a Rayleigh-ish scattering term; RV has
// no such constants, so we provide them here with the original values.
// ---------------------------------------------------------------------
#define Sky_Brightness 1.0
#define sky_coefficientRayleighR 5.8
#define sky_coefficientRayleighG 1.35
#define sky_coefficientRayleighB 3.31

// ---------------------------------------------------------------------
// Calibration knob BLISS_CLOUD_BRIGHTNESS is exposed as an option in
// lib/common.glsl so it can be tuned from the in-game menu.
// ---------------------------------------------------------------------

// ---------------------------------------------------------------------
// Light-direction bridge.
// Bliss reads two WORLD-space globals that RV does not expose:
//     WsunVec       world-space sun direction
//     sunElevation  >1e-5 means "sun is above the horizon"
// GLSL forbids global initialisers that read uniforms, so we give them
// constant defaults here and OVERWRITE them at runtime at the top of the
// GetVolumetricClouds() adapter (see bliss_clouds.glsl).
// ---------------------------------------------------------------------
vec3  WsunVec      = vec3(0.0, 1.0, 0.0);
float sunElevation = 1.0;

#endif
