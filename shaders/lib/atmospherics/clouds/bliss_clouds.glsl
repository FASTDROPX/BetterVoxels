/*
=======================================================================
  Bliss -> Rethinking Voxels  |  PORTED VOLUMETRIC CLOUD MODULE
=======================================================================
  This is X0nk's Bliss v2.1.2 volumetric cloud system
  (shaders/lib/volumetricClouds.glsl), copied with its internal mechanics
  intact (noise, 3-layer cumulus+altostratus, self-shadowing, powder,
  multiscatter, cloud->world shadows). All Bliss cloud FUNCTIONS are
  namespaced with a  bliss_  prefix to guarantee isolation from RV.

  Missing Bliss symbols are supplied by bliss_clouds_compat.glsl (below).
  An adapter at the bottom exposes the Bliss renderer through RV's native
  GetVolumetricClouds() interface so it slots into RV's cloud dispatch,
  reflections and depth/lightshaft plumbing unchanged.
=======================================================================
*/
#include "/lib/atmospherics/clouds/bliss_clouds_compat.glsl"

#ifdef HQ_CLOUDS
	int maxIT_clouds = minRayMarchSteps;
	int maxIT = maxRayMarchSteps;

	const int cloudLoD = cloud_LevelOfDetail;
	const int cloudShadowLoD = cloud_ShadowLevelOfDetail;
#else
	int maxIT_clouds = minRayMarchStepsLQ;
	int maxIT = maxRayMarchStepsLQ;

	const int cloudLoD = cloud_LevelOfDetailLQ;
	const int cloudShadowLoD = cloud_ShadowLevelOfDetailLQ;
#endif

// [RV-PORT] removed (provided by RV uniforms.glsl / not needed): uniform int worldTime;
// [RV-PORT] removed (provided by RV uniforms.glsl / not needed): #define WEATHERCLOUDS
// [RV-PORT] removed (provided by RV uniforms.glsl / not needed): #include "/lib/climate_settings.glsl"

#if defined Daily_Weather
	flat varying vec4 dailyWeatherParams0;
	flat varying vec4 dailyWeatherParams1;
#else
	vec4 dailyWeatherParams0 = vec4(CloudLayer0_coverage, CloudLayer1_coverage, CloudLayer2_coverage, 0.0);
	vec4 dailyWeatherParams1 = vec4(CloudLayer0_density, CloudLayer1_density, CloudLayer2_density, 0.0);
#endif

float LAYER0_width = 100.0; 
float LAYER0_minHEIGHT = CloudLayer0_height; 
float LAYER0_maxHEIGHT = LAYER0_width + LAYER0_minHEIGHT;

float LAYER1_width = 100.0; 
float LAYER1_minHEIGHT = max(CloudLayer1_height, LAYER0_maxHEIGHT); 
float LAYER1_maxHEIGHT = LAYER1_width + LAYER1_minHEIGHT;

float LAYER2_HEIGHT = max(CloudLayer2_height, LAYER1_maxHEIGHT); 

// float LAYER0_COVERAGE = mix(pow(dailyWeatherParams0.x*2.0,0.2), 0.9, rainStrength);
// float LAYER1_COVERAGE = mix(pow(dailyWeatherParams0.y*2.0,0.2), 0.8, rainStrength);
// float LAYER2_COVERAGE = mix(pow(dailyWeatherParams0.z*2.0,0.2), 1.3, rainStrength);

float LAYER0_COVERAGE = mix(dailyWeatherParams0.x, Rain_coverage, rainStrength);
float LAYER1_COVERAGE = mix(dailyWeatherParams0.y, 0.0, rainStrength);
float LAYER2_COVERAGE = mix(dailyWeatherParams0.z, 1.5, rainStrength);

float LAYER0_DENSITY = mix(dailyWeatherParams1.x,1.0,rainStrength);
float LAYER1_DENSITY = mix(dailyWeatherParams1.y,0.0,rainStrength);
float LAYER2_DENSITY = mix(dailyWeatherParams1.z,0.05,rainStrength);

// [RV-PORT] removed (provided by RV uniforms.glsl / not needed): uniform int worldDay;

float cloud_movement = (worldTime  + mod(worldDay,100)*24000.0) / 24.0 * Cloud_Speed;

// =====================================================================
//  NOISE BRIDGE  (Bliss noisetex  ->  RV-safe procedural noise)
// ---------------------------------------------------------------------
//  Bliss' cloud field was authored against its own 512x512 RGBA
//  noises.png: it is sampled with a 3D-from-2D channel-packing trick and
//  with hard-coded "/512" texel math. RV ships a DIFFERENT noisetex
//  (128x128 RGB, see noiseTextureResolution in pipelineSettings.glsl)
//  whose content, channel layout and tile period do not match. Feeding
//  Bliss' code RV's noisetex directly is what produced the regressions:
//    - 4x undersampling (coord/512 over a 128px tile) -> flat blocky blobs
//    - texture tile repeat                            -> ghost duplication / tiling
//    - linear interpolation + tile periodicity        -> concentric moire
//
//  Instead of rebinding a second sampler across every program that pulls
//  in the cloud code (deferred1, gbuffers_water, dh_water and the
//  deferred compute pass) -- which is fragile and stage-dependent -- the
//  noise profile is reconstructed procedurally here. This is fully
//  self-contained, never tiles, uses smooth (quintic) interpolation for
//  fluffy edges, and does NOT touch RV's noisetex (so RV's water and
//  other noise users keep their original appearance).
//
//  These low-level hash / value-noise / fbm helpers are the foundation;
//  the DENSITY FIELD that turns them into cloud shapes was rewritten in
//  Iteration 4 (see the CLOUD DENSITY FIELD block further down) -- Bliss'
//  original texel-coverage math is no longer used.
// =====================================================================

// --- Cloud-shape tunables (Iteration 4 rewrite) ----------------------
// The geometry is now driven directly by these, NOT by Bliss' old texel
// math. Horizontal scale is the dominant control: SMALL number = features
// stretched over a huge world distance = massive sweeping pancakes.
#define BLISS_FBM_OCTAVES 3           // octaves for the 2D coverage field (multi-scale masses + sub-gaps)

// Coverage: world distance over which the big masses vary.
//   1/BLISS_COVER_SCALE = mass size in blocks. 0.00045 -> ~2200-block masses.
#define BLISS_COVER_SCALE 0.0010      // SMALLER = bigger masses. 0.0010 -> ~1000-block masses (sweeping but with visible shape + parallax)
#define BLISS_ANISO 0.70              // <1 stretches masses along X into bands (closer to 1 = rounder, less "tube")
#define BLISS_COVER_GAIN 0.72         // scales the in-game CloudLayerN_coverage slider (0.7*0.72 ~= 0.5 = open sky)
#define BLISS_EDGE 0.30               // width of the soft coverage onset (bigger = softer/larger edges)

// Erosion: 3D detail carved into the masses. Kept LOW frequency on purpose
// so the ray never undersamples it (that undersampling was the "spikes").
#define BLISS_ERODE_SCALE 0.006       // ~165-block detail; do NOT push high or spikes return
#define BLISS_ERODE_OCTAVES 3
#define BLISS_ERODE_AMOUNT 0.55       // 0..1 how deeply erosion bites the masses

// High-frequency fluff: micro-detail carved into cloud EDGES so the masses
// read as organic cloud instead of smooth plastic. It is faded out at grazing
// view angles (bliss_rayVerticality) where ray steps are huge -- that fade is
// exactly what stops fine detail from aliasing back into the old "spikes".
#define BLISS_FLUFF_SCALE 0.022       // ~45-block micro detail (finest octave ~22 blocks)
#define BLISS_FLUFF_AMOUNT 0.55       // 0..1 how deeply the fluff bites the edges

// Vertical volume: fraction of the layer thickness used as the soft base
// ramp and the soft top taper (gives heavy 3D volume, not a 2D plane).
#define BLISS_BASE_FRAC 0.22          // bottom ramp-up over this fraction of layer height
#define BLISS_TOP_FRAC  0.45          // top taper over this fraction of layer height

// Altostratus (high thin layer 2). Coverage comes from the in-game
// CloudLayer2_coverage slider (via LAYER2_COVERAGE) so the menu still works.
#define BLISS_ALTO_SCALE 0.00018      // very large, sweeping high sheets

// --- Runtime globals (set per-call by the adapter / renderer; NOT constants) ---
// bliss_terrainDist:    world distance to solid terrain along this pixel's ray
//                       (1e9 on sky pixels). The raymarch stops once it travels
//                       past this, so clouds no longer draw over / through
//                       mountains and blocks (depth occlusion -- bug fix).
// bliss_rayVerticality: abs(view-ray .y); ~1 looking up, ~0 at the horizon.
//                       Fades the high-frequency fluff out at grazing angles so
//                       it can never alias into spikes.
float bliss_terrainDist    = 1e9;
float bliss_rayVerticality = 1.0;

// Dave Hoskins style hashes (high quality, no visible lattice patterning).
float bliss_hash12(vec2 p){
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float bliss_hash13(vec3 p3){
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth (quintic) 2D value noise in [0,1].
float bliss_vnoise2(vec2 p){
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f*f*f*(f*(f*6.0-15.0)+10.0);
	float a = bliss_hash12(i);
	float b = bliss_hash12(i + vec2(1.0,0.0));
	float c = bliss_hash12(i + vec2(0.0,1.0));
	float d = bliss_hash12(i + vec2(1.0,1.0));
	return mix(mix(a,b,f.x), mix(c,d,f.x), f.y);
}

// Smooth (quintic) 3D value noise in [0,1] -- the trilinear field Bliss'
// 3D-from-2D trick approximated, done directly in 3D for fluffy edges.
float bliss_vnoise3(vec3 p){
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f*f*f*(f*(f*6.0-15.0)+10.0);
	float n000 = bliss_hash13(i + vec3(0.0,0.0,0.0));
	float n100 = bliss_hash13(i + vec3(1.0,0.0,0.0));
	float n010 = bliss_hash13(i + vec3(0.0,1.0,0.0));
	float n110 = bliss_hash13(i + vec3(1.0,1.0,0.0));
	float n001 = bliss_hash13(i + vec3(0.0,0.0,1.0));
	float n101 = bliss_hash13(i + vec3(1.0,0.0,1.0));
	float n011 = bliss_hash13(i + vec3(0.0,1.0,1.0));
	float n111 = bliss_hash13(i + vec3(1.0,1.0,1.0));
	vec4 x = mix(vec4(n000,n010,n001,n011), vec4(n100,n110,n101,n111), f.x);
	vec2 y = mix(x.xz, x.yw, f.y);
	return mix(y.x, y.y, f.z);
}

// Normalised fractal value noise in [0,1] (broadband, like the texture).
float bliss_fbm2(vec2 p){
	float v = 0.0, a = 0.5, t = 0.0;
	for(int i = 0; i < BLISS_FBM_OCTAVES; i++){
		v += a * bliss_vnoise2(p);
		t += a;
		p = p * 2.0 + 17.3; // per-octave offset decorrelates the octaves
		a *= 0.5;
	}
	return v / t;
}

// =====================================================================
//  CLOUD DENSITY FIELD  (Iteration 4 -- full rewrite)
// ---------------------------------------------------------------------
//  The previous port tried to feed procedural noise into Bliss' original
//  texel-based coverage math (abs(CloudLarge*2-1.2) billow + a bolt-on
//  mask). That math was tuned for a specific 512px texture and fought the
//  procedural field: coverage sat near a constant ~0.3 (full-sky haze) and
//  the erosion ran at ~1.5-block features that the vertical ray could not
//  sample, aliasing into the radial "spikes".
//
//  This rewrite drives the geometry DIRECTLY:
//    * coverage  = ONE big low-frequency 2D field, world XZ scaled by a
//                  tiny number so a feature spans thousands of blocks
//                  (massive sweeping pancakes), stretched along X.
//    * a soft QUINTIC onset turns that into cloud vs open sky (no step()).
//    * a vertical QUINTIC base-ramp * top-taper gives real volume so the
//      layer is a thick deck, not a 2D plane on the horizon.
//    * erosion is LOW frequency and MULTIPLICATIVE, so it softens the
//      masses without ever undersampling (no spikes) and never goes negative.
//  Every shaping curve is the explicit quintic 6t^5-15t^4+10t^3.
// =====================================================================

// Explicit quintic (Hermite) smoothing curve. Used for every soft ramp and
// contrast shaping so NOTHING here uses step() or smoothstep() for density.
float bliss_quintic(float x){
	x = clamp(x, 0.0, 1.0);
	return x*x*x*(x*(x*6.0 - 15.0) + 10.0);
}

// Normalised 3D fractal value noise in [0,1] (quintic interpolation lives
// inside bliss_vnoise3). Kept low frequency by its caller -> no aliasing.
float bliss_fbm3(vec3 p){
	float v = 0.0, a = 0.5, t = 0.0;
	for(int i = 0; i < BLISS_ERODE_OCTAVES; i++){
		v += a * bliss_vnoise3(p);
		t += a;
		p = p * 2.0 + 19.1;
		a *= 0.5;
	}
	return v / t;
}

// Big sweeping horizontal coverage field in [0,1]. World XZ is scaled by the
// tiny BLISS_COVER_SCALE so one feature spans thousands of blocks; X is
// stretched further by BLISS_ANISO into long pancake bands. The quintic
// makes the masses distinct from the gaps with smooth (not stepped) shoulders.
float bliss_coverageField(int layer, vec2 worldXZ){
	vec2 p = worldXZ * BLISS_COVER_SCALE;
	p.x *= BLISS_ANISO;
	p += vec2(cloud_movement * BLISS_COVER_SCALE, 0.0); // wind drift
	p += float(layer) * 31.7;                            // decorrelate the two decks
	return bliss_quintic(bliss_fbm2(p));
}

// High, thin altostratus sheet (layer 2): one very large, sweeping field.
float bliss_GetAltostratusDensity(vec3 pos){
	vec2 p = pos.xz * BLISS_ALTO_SCALE;
	p.x *= BLISS_ANISO;
	p += vec2(cloud_movement * BLISS_ALTO_SCALE, 0.0);
	float cover = bliss_quintic(bliss_fbm2(p));
	// coverage from the in-game CloudLayer2 slider (+ rain), soft quintic onset
	float altoCov = clamp(LAYER2_COVERAGE, 0.0, 1.0);
	float d = (cover - (1.0 - altoCov)) / max(altoCov, 1e-3);
	float sheet = bliss_quintic(clamp(d, 0.0, 1.0));
	return sheet * sheet;
}

// Cumulus density in [0,1] for one ray sample. Same signature Bliss'
// renderer calls; LoD>=1 adds erosion, LoD<1 is the cheap shadow tap.
float bliss_GetCumulusDensity(int layer, in vec3 pos, in int LoD, float minHeight, float maxHeight){

	// --- vertical volume profile: soft base ramp * soft top taper --------
	float thickness = max(maxHeight - minHeight, 1.0);
	float h = (pos.y - minHeight) / thickness;          // 0 at base, 1 at top
	if (h <= 0.0 || h >= 1.0) return 0.0;
	float baseRamp = bliss_quintic(h / BLISS_BASE_FRAC);          // flat-ish soft base
	float topTaper = bliss_quintic((1.0 - h) / BLISS_TOP_FRAC);   // rounded soft top
	float vprofile = baseRamp * topTaper;
	if (vprofile <= 0.0) return 0.0;

	// --- horizontal coverage: massive sweeping masses --------------------
	float coverage = bliss_coverageField(layer, pos.xz);
	// coverage amount from the in-game CloudLayerN slider (+ rain), scaled so
	// the default reads as open sky. layer is 0 or 1 here.
	float layerCov = (layer == 1) ? LAYER1_COVERAGE : LAYER0_COVERAGE;
	float covAmt = clamp(layerCov * BLISS_COVER_GAIN, 0.0, 1.0);
	// soft coverage onset via quintic ramp (NO hard step / threshold)
	float d = (coverage - (1.0 - covAmt)) / BLISS_EDGE;
	float cloud = bliss_quintic(clamp(d, 0.0, 1.0));
	if (cloud <= 0.0) return 0.0;

	cloud *= vprofile;

	// --- erosion: LOW frequency + MULTIPLICATIVE (no spikes, never negative)
	if (LoD >= 1){
		vec3 ep = pos * BLISS_ERODE_SCALE;
		ep.xz *= 0.5;                                    // stretch erosion horizontally
		float er = bliss_quintic(bliss_fbm3(ep));
		// bite edges harder than cores (weight by 1-cloud)
		cloud *= 1.0 - er * BLISS_ERODE_AMOUNT * (1.0 - cloud);

		// High-frequency fluff: organic micro-detail on the edges. Faded by
		// view verticality so it is full strength overhead (small, densely
		// sampled ray steps) and gone toward the horizon (huge steps) -- this
		// is what lets us add fine detail WITHOUT the detail aliasing into spikes.
		float fluffFade = bliss_quintic(clamp((bliss_rayVerticality - 0.30) / 0.40, 0.0, 1.0));
		if (fluffFade > 0.0){
			vec3 fp = pos * BLISS_FLUFF_SCALE;
			fp.xz *= 0.6;
			// two-octave quintic value noise; finest octave kept coarse enough
			// (~half the base) to stay sampled near the camera.
			float fluff = bliss_vnoise3(fp) * 0.65 + bliss_vnoise3(fp * 2.0 + 7.3) * 0.35;
			cloud *= 1.0 - bliss_quintic(fluff) * BLISS_FLUFF_AMOUNT * fluffFade * (1.0 - cloud);
		}
	}

	return clamp(cloud, 0.0, 1.0);
}


#ifndef CLOUDSHADOWSONLY
// [RV-PORT] removed (provided by RV uniforms.glsl / not needed): uniform sampler2D colortex4; //Skybox

//Mie phase function
float bliss_phaseg(float x, float g){
    float gg = g * g;
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14;
}

vec3 bliss_DoCloudLighting(
	float density,
	
	vec3 skyLightCol,
	float skyScatter,

	float sunShadows,
	vec3 sunScatter,
	vec3 sunMultiScatter,
	float distantfog
){
	float powder = 1.0 - exp(-10.0 * density);
	vec3 directLight = sunScatter * exp(-10.0 * sunShadows) + sunMultiScatter * exp(-3.0 * sunShadows) * powder;

	vec3 indirectLight = skyLightCol * mix(1.0,  2.0 * (1.0 - sqrt((skyScatter*skyScatter*skyScatter)*density)) , pow(distantfog,1.0 - rainStrength*0.5));
	
	// return directLight;
	// #ifndef TEST
	// return indirectLight;
	// #endif
	return directLight + indirectLight;
}

vec4 bliss_renderLayer(
	int layer,
	in vec3 POSITION,
	in vec3 rayProgress, 
	in vec3 dV_view,
	in float mult,
	in float dither,

	int QUALITY,
	
	float minHeight,
	float maxHeight,

	in vec3 dV_Sun,

	float cloudDensity,
	in vec3 skyLightCol,
	in vec3 sunScatter,
	in vec3 sunMultiScatter,
	in vec3 indirectScatter,
	in float distantfog,
	bool notVisible,
	vec3 FragPosition,
	inout vec3 cloudDepth
){
	vec3 COLOR = vec3(0.0);
	float TOTAL_EXTINCTION = 1.0;
	bool IntersecTerrain = false;

	// Terrain depth occlusion. bliss_terrainDist is the world distance to solid
	// geometry on this pixel (1e9 on sky pixels), supplied by RV in the adapter.
	// Bliss' own FragPosition-based estimate was wrong in this port (FragPosition
	// is a normalized direction * 1024), so it is replaced with RV's real value.

if(layer == 2){

	IntersecTerrain = length(rayProgress - cameraPosition) > bliss_terrainDist;

	if(notVisible || IntersecTerrain) return vec4(COLOR, TOTAL_EXTINCTION);
	
	float signFlip = mix(-1.0, 1.0, clamp(cameraPosition.y - minHeight,0.0,1.0));
	
	if(max(signFlip * normalize(dV_view).y,0.0) <= 0.0){
		float altostratus = bliss_GetAltostratusDensity(rayProgress);

		float AltoWithDensity = altostratus * cloudDensity;
		
		if(altostratus > 1e-5){
			float muE = altostratus * cloudDensity;

			float directLight = 0.0;
			for (int j = 0; j < 2; j++){
				
				// lower the step size as the sun gets higher in the sky
				vec3 shadowSamplePos_high = rayProgress + dV_Sun * (1.0 + j * dither) / (pow(abs(dV_Sun.y*0.5),3.0) * 0.995 + 0.005);

				// lower density as the sun gets higher in the sky to simulate.... multiscattering or something idk it looks better this way
				directLight += bliss_GetAltostratusDensity(shadowSamplePos_high) * cloudDensity * (1.0-abs(dV_Sun.y));
			}

			vec3 lighting = bliss_DoCloudLighting(AltoWithDensity, skyLightCol, 0.5, directLight, sunScatter, sunMultiScatter, distantfog);

			COLOR += max(lighting - lighting*exp(-mult*muE),0.0) * TOTAL_EXTINCTION;
			TOTAL_EXTINCTION *= max(exp(-mult*muE),0.0);
		}
	}
	
	return vec4(COLOR, TOTAL_EXTINCTION);

}else{
	#if defined CloudLayer1 && defined CloudLayer0
		float upperLayerOcclusion = layer == 0 ? bliss_GetCumulusDensity(1, rayProgress + vec3(0.0,1.0,0.0) * max((LAYER1_minHEIGHT+70*dither) - rayProgress.y,0.0), 0, LAYER1_minHEIGHT, LAYER1_maxHEIGHT) : 0.0;
		float skylightOcclusion = mix(1.0, (1.0 - LAYER1_DENSITY)*0.8 + 0.2, (1.0 - exp2(-5.0 * (upperLayerOcclusion*upperLayerOcclusion))) * distantfog);
	#else
		float skylightOcclusion = 1.0;
	#endif

	float expFactor = 11.0;
	for(int i = 0; i < QUALITY; i++) {

		// stop the ray once it passes the solid terrain on this pixel
		IntersecTerrain = length(rayProgress - cameraPosition) > bliss_terrainDist;

		/// avoid overdraw
		if(notVisible || IntersecTerrain) break;

		// do not sample anything unless within a clouds bounding box
		if(clamp(rayProgress.y - maxHeight,0.0,1.0) < 1.0 && clamp(rayProgress.y - minHeight,0.0,1.0) > 0.0){

			float cumulus = bliss_GetCumulusDensity(layer, rayProgress, 1, minHeight, maxHeight);
			float fadedDensity = cloudDensity * pow(clamp((rayProgress.y - minHeight)/25,0.0,1.0),2.0);
			float CumulusWithDensity = cloudDensity * cumulus;

			
			if(CumulusWithDensity > 1e-5 ){ // make sure no work is done on pixels with no densities
				float muE =	cumulus * fadedDensity;

				float directLight = 0.0;
				for (int j=0; j < 3; j++){
					vec3 shadowSamplePos = rayProgress + dV_Sun * (20.0 + j * (20.0 + dither*20.0));
					directLight += bliss_GetCumulusDensity(layer, shadowSamplePos, 0, minHeight, maxHeight) * cloudDensity;
				}

				/// shadows cast from one layer to another
				/// large cumulus -> small cumulus
				#if defined CloudLayer1 && defined CloudLayer0
					if(layer == 0) directLight += LAYER1_DENSITY * 2.0 * bliss_GetCumulusDensity(1, rayProgress + dV_Sun/abs(dV_Sun.y) * max((LAYER1_minHEIGHT+70*dither) - rayProgress.y,0.0), 0, LAYER1_minHEIGHT, LAYER1_maxHEIGHT);
				#endif
				// altostratus -> cumulus
				#ifdef CloudLayer2
					vec3 HighAlt_shadowPos = rayProgress + dV_Sun/abs(dV_Sun.y) * max(LAYER2_HEIGHT - rayProgress.y,0.0);
					float HighAlt_shadow = bliss_GetAltostratusDensity(HighAlt_shadowPos) * CloudLayer2_density * (1.0-abs(WsunVec.y));
					directLight += HighAlt_shadow;
				#endif

				float skyScatter = clamp(((maxHeight - rayProgress.y) / 100.0),0.0,1.0); // linear gradient from bottom to top of cloud layer
				vec3 lighting = bliss_DoCloudLighting(CumulusWithDensity, skyLightCol * skylightOcclusion, skyScatter, directLight, sunScatter, sunMultiScatter, distantfog);

				COLOR += max(lighting - lighting*exp(-mult*muE),0.0) * TOTAL_EXTINCTION;
				TOTAL_EXTINCTION *= max(exp(-mult*muE),0.0);

				if (TOTAL_EXTINCTION < 1e-5) break;
	 			
			}

		}
		
		rayProgress += dV_view;
	}
	
	return vec4(COLOR, TOTAL_EXTINCTION);
}
}

vec3 bliss_layerStartingPosition(
	vec3 dV_view,
	vec3 cameraPos,
	float dither,
	
	float minHeight,
	float maxHeight
){
	// allow passing through/above/below the plane without limits
	float flip = mix(max(cameraPos.y - maxHeight,0.0), max(minHeight - cameraPos.y,0.0), clamp(dV_view.y,0.0,1.0));

	// orient the ray to be a flat plane facing up/down
	vec3 position = dV_view*dither + cameraPos + (dV_view/abs(dV_view.y)) * flip;
	
	return position;
}
float bliss_invLinZ_cloud (float lindepth){
	return -((2.0*near/lindepth)-far-near)/(far-near);
}
vec4 bliss_renderClouds(
	vec3 FragPosition,
	vec2 Dither,
	vec3 LightColor,
	vec3 SkyColor,
	inout vec3 cloudDepth
){	
	vec3 SignedWsunvec = WsunVec;
	vec3 WsunVec = WsunVec * (float(sunElevation > 1e-5)*2.0-1.0);

	#ifndef VOLUMETRIC_CLOUDS
		return vec4(0.0,0.0,0.0,1.0);
	#endif

	float total_extinction = 1.0;
	vec3 color = vec3(0.0);

	float heightRelativeToClouds = clamp(1.0 - max(cameraPosition.y - LAYER0_minHEIGHT,0.0) / 100.0 ,0.0,1.0);

//////////////////////////////////////////
////// Raymarching stuff 
//////////////////////////////////////////
	//project pixel position into projected shadowmap space
	vec4 viewPos = normalize(gbufferModelViewInverse * vec4(FragPosition,1.0) );
	maxIT_clouds = int(clamp(maxIT_clouds / sqrt(exp2(viewPos.y)),0.0, maxIT));
	// maxIT_clouds = 30;

	vec3 dV_view = normalize(viewPos.xyz);

	// this is the cloud curvature.
	dV_view.y += 0.025 * heightRelativeToClouds;

	// expose ray verticality so the density field can fade the high-frequency
	// fluff at grazing angles (anti-aliasing for the detail pass).
	bliss_rayVerticality = abs(dV_view.y);

	vec3 dV_view_Alto = dV_view;

	dV_view_Alto *= 5.0/abs(dV_view_Alto.y);
	float mult_alto = length(dV_view_Alto);

	// dV_view *= (LAYER0_maxHEIGHT - LAYER0_minHEIGHT)/abs(dV_view.y)/maxIT_clouds;

	vec3 dV_viewTEST = dV_view * (90.0/abs(dV_view.y)/maxIT_clouds);
	float mult = length(dV_viewTEST);

	

//////////////////////////////////////////
////// lighting stuff 
//////////////////////////////////////////

	vec3 dV_Sun = WsunVec;
	#ifdef EXCLUDE_WRITE_TO_LUT
		dV_Sun *= lightCol.a;
	#endif
	
	float SdotV = dot(WsunVec, normalize(mat3(gbufferModelViewInverse)*FragPosition + gbufferModelViewInverse[3].xyz));

	float mieDay = bliss_phaseg(SdotV, 0.85) + bliss_phaseg(SdotV, 0.75);
	float mieDayMulti = (bliss_phaseg(SdotV, 0.35) + bliss_phaseg(-SdotV, 0.35) * 0.5) ;

	vec3 directScattering = LightColor * mieDay * 3.14 ;
	vec3 directMultiScattering = LightColor * mieDayMulti * 3.14 * 2.0;
	vec3 sunIndirectScattering = LightColor;// * bliss_phaseg(dot(mat3(gbufferModelView)*vec3(0,1,0),normalize(FragPosition)), 0.5) * 3.14;

	// use this to blend into the atmosphere's ground.
	vec3 approxdistance = normalize(dV_viewTEST);
	#ifdef SKY_GROUND
		float distantfog = mix(1.0, max(1.0 - clamp(exp2(pow(abs(approxdistance.y),mix(1.5, 4.0, rainStrength)) * -mix(100.0, 35.0, rainStrength)),0.0,1.0),0.0), heightRelativeToClouds);
	#else
		float distantfog = 1.0;
		float distantfog2 = mix(1.0, max(1.0 - clamp(exp(pow(abs(approxdistance.y),1.5) * -35.0),0.0,1.0),0.0), heightRelativeToClouds);
	#endif
	
	// terrible fake rayleigh scattering
	vec3 rC = vec3(sky_coefficientRayleighR*1e-6, sky_coefficientRayleighG*1e-5, sky_coefficientRayleighB*1e-5)*3.0;
	float atmosphere =  exp(abs(approxdistance.y) * -5.0);
	vec3 scatter = distantfog * exp(-10000.0 * rC * atmosphere);

	directScattering *= scatter;
	directMultiScattering *= scatter;

	SkyColor *= mix(1.0* Sky_Brightness, 1.0-pow(1.0-clamp(SignedWsunvec.y,0.0,1.0),5.0) * 0.75 + 0.25, distantfog);

//////////////////////////////////////////
////// render Cloud layers and do blending orders
//////////////////////////////////////////

	// first cloud layer
	float MinHeight = LAYER0_minHEIGHT; 
	float MaxHeight = LAYER0_maxHEIGHT;

	float MinHeight1 = LAYER1_minHEIGHT;
	float MaxHeight1 = LAYER1_maxHEIGHT;

	float Height2 = LAYER2_HEIGHT;

	// int above_Layer0 = int(clamp(cameraPosition.y - MaxHeight,0.0,1.0));
	int below_Layer0 = int(clamp(MaxHeight - cameraPosition.y,0.0,1.0));
	int above_Layer1 = int(clamp(MaxHeight1 - cameraPosition.y,0.0,1.0));
	bool below_Layer1 = clamp(cameraPosition.y - MinHeight1,0.0,1.0) < 1.0;
	bool below_Layer2 = clamp(cameraPosition.y - Height2,0.0,1.0) < 1.0;
	// bool layer1_below_layer0 = MinHeight1 < MinHeight;
	
	bool altoNotVisible = false;
	

	#ifdef CloudLayer0
		vec3 layer0_dV_view = dV_view * (LAYER0_width/abs(dV_view.y)/maxIT_clouds);
		vec3 layer0_start = bliss_layerStartingPosition(layer0_dV_view, cameraPosition, Dither.y, MinHeight, MaxHeight);

	#endif

	#ifdef CloudLayer1
		vec3 layer1_dV_view = dV_view * (LAYER1_width/abs(dV_view.y)/maxIT_clouds);
		vec3 layer1_start = bliss_layerStartingPosition(layer1_dV_view, cameraPosition, Dither.y, MinHeight1, MaxHeight1);
	#endif
	#ifdef CloudLayer2
		vec3 layer2_start = bliss_layerStartingPosition(dV_view_Alto, cameraPosition, Dither.y, Height2, Height2);
	#endif

	#ifdef CloudLayer0
		vec4 layer0 = bliss_renderLayer(0,dV_view, layer0_start, layer0_dV_view, mult, Dither.x, maxIT_clouds, MinHeight, MaxHeight, dV_Sun, LAYER0_DENSITY, SkyColor, directScattering, directMultiScattering, sunIndirectScattering, distantfog, false, FragPosition, cloudDepth);
		total_extinction *= layer0.a;

		// stop overdraw.
		bool notVisible = layer0.a < 1e-5 && below_Layer1;
		altoNotVisible = notVisible;
	#else
		// stop overdraw.
		bool notVisible = false;
	#endif

	#ifdef CloudLayer1
		vec4 layer1 = bliss_renderLayer(1,dV_view, layer1_start, layer1_dV_view, mult, Dither.x, maxIT_clouds, MinHeight1, MaxHeight1, dV_Sun, LAYER1_DENSITY, SkyColor, directScattering, directMultiScattering, sunIndirectScattering, distantfog, notVisible, FragPosition, cloudDepth);
		total_extinction *= layer1.a;

		// stop overdraw.
		altoNotVisible = (layer1.a < 1e-5  || notVisible) && below_Layer1;	
	#endif

	#ifdef CloudLayer2
		vec4 layer2 = bliss_renderLayer(2,dV_view,layer2_start, dV_view_Alto, mult_alto, Dither.x, maxIT_clouds, Height2, Height2, dV_Sun, LAYER2_DENSITY, SkyColor, directScattering * (1.0 + rainStrength*3), directMultiScattering* (1.0 + rainStrength*3), sunIndirectScattering, distantfog, altoNotVisible, FragPosition, cloudDepth);
		total_extinction *= layer2.a;
	#endif
	
	/// i know this looks confusing
	/// it is changing blending order based on the players position relative to the clouds.
	/// to keep it simple for myself, it all revolves around layer0, the lowest cloud layer.
	/// for layer1, swap between back to front and front to back blending if you are above or below layer0
	/// for layer2, swap between back to front and front to back blending if you are above or below layer1
	

	/// blend the altostratus clouds first, so it is BEHIND all the cumulus clouds, if the player postion is below the cumulus clouds.
	/// handle the case if one of the cloud layers is disabled.
	#if !defined CloudLayer1 && defined CloudLayer2
		if(below_Layer2) color = color * layer2.a + layer2.rgb;
	#endif
	#if defined CloudLayer1 && defined CloudLayer2 
		if(below_Layer2) layer1.rgb = layer2.rgb * layer1.a + layer1.rgb;
	#endif

	/// blend the cumulus clouds together. swap the blending order from (BACK TO FRONT -> FRONT TO BACK) depending on the player position relative to the lowest cloud layer.
	#if defined CloudLayer0 && defined CloudLayer1
		color = mix(layer0.rgb, layer1.rgb,  float(below_Layer0));
		color = mix(color * layer1.a + layer1.rgb, color * layer0.a + layer0.rgb, float(below_Layer0));
	#endif

	/// handle the case of one of the cloud layers being disabled.
	#if defined CloudLayer0 && !defined CloudLayer1
		color = color * layer0.a + layer0.rgb;
	#endif
	#if !defined CloudLayer0 && defined CloudLayer1
		color = color * layer1.a + layer1.rgb;
	#endif

	/// blend the altostratus clouds last, so it is IN FRONT of all the cumulus clouds when the player position is above them.
	#ifdef CloudLayer2
		if(!below_Layer2) color = color * layer2.a + layer2.rgb;
	#endif

	#ifndef SKY_GROUND
		
		// return mix(fogcolor, vec4(color, total_extinction), clamp(distantfog2,0.0,1.0));
		return mix(vec4(vec3(0.0),1.0), vec4(color, total_extinction), clamp(distantfog2,0.0,1.0));
	#else
		return vec4(color, total_extinction);
	#endif
	
}

#endif

float bliss_GetCloudShadow(vec3 feetPlayerPos){
#ifdef CLOUDS_SHADOWS
	vec3 playerPos = feetPlayerPos + cameraPosition;

	float shadow = 0.0;

	// assume a flat layer of cloud, and stretch the sampled density along the sunvector, starting from some vertical layer in the cloud.
	#ifdef CloudLayer0
		vec3 lowShadowStart = playerPos + (WsunVec / max(abs(WsunVec.y),0.0)) * max((CloudLayer0_height + 30) - playerPos.y,0.0) ;
		shadow += bliss_GetCumulusDensity(0, lowShadowStart, 0, CloudLayer0_height, CloudLayer0_height+100)*LAYER0_DENSITY;
	#endif
	#ifdef CloudLayer1
		vec3 higherShadowStart = playerPos + (WsunVec / max(abs(WsunVec.y),0.0)) * max((CloudLayer1_height + 50) - playerPos.y,0.0) ;
		shadow += bliss_GetCumulusDensity(1, higherShadowStart, 0, CloudLayer1_height, CloudLayer1_height+100)*LAYER1_DENSITY;
	#endif
	#ifdef CloudLayer2 
		vec3 highShadowStart = playerPos + (WsunVec / max(abs(WsunVec.y),0.0)) * max(CloudLayer2_height - playerPos.y,0.0);
		shadow += bliss_GetAltostratusDensity(highShadowStart) * CloudLayer2_density * (1.0-abs(WsunVec.y));
	#endif

	shadow = clamp(shadow,0.0,1.0);

	shadow = exp2((shadow*shadow) * -100.0);

	return mix(1.0, shadow, CLOUD_SHADOW_STRENGTH);
	
#else
	return 1.0;
#endif
}


float bliss_GetCloudShadow_VLFOG(vec3 WorldPos, vec3 WorldSpace_sunVec){
#ifdef CLOUDS_SHADOWS

	float shadow = 0.0;

	#ifdef CloudLayer0
		vec3 lowShadowStart = WorldPos + (WorldSpace_sunVec / max(abs(WorldSpace_sunVec.y),0.0)) * max((CloudLayer0_height + 30) - WorldPos.y,0.0)  ;
		shadow += max(bliss_GetCumulusDensity(0, lowShadowStart, 0, CloudLayer0_height, CloudLayer0_height+100),0.0)*LAYER0_DENSITY;
	#endif
	#ifdef CloudLayer1
		vec3 higherShadowStart = WorldPos + (WorldSpace_sunVec / max(abs(WorldSpace_sunVec.y),0.0)) * max((CloudLayer1_height + 30) - WorldPos.y,0.0)  ;
		shadow += max(bliss_GetCumulusDensity(1,higherShadowStart, 0, CloudLayer1_height,CloudLayer1_height+100) ,0.0)*LAYER1_DENSITY;
	#endif
	#ifdef CloudLayer2 
		vec3 highShadowStart = WorldPos + (WorldSpace_sunVec / max(abs(WorldSpace_sunVec.y),0.0)) * max(CloudLayer2_height - WorldPos.y,0.0);
		shadow += bliss_GetAltostratusDensity(highShadowStart)*LAYER2_DENSITY * (1.0-abs(WorldSpace_sunVec.y));
	#endif

	shadow = clamp(shadow,0.0,1.0);

	shadow = exp((shadow*shadow) * -100.0);

	return mix(1.0, shadow, CLOUD_SHADOW_STRENGTH);

#else
	return 1.0;
#endif
}

// =====================================================================
//  RV INTEGRATION ADAPTER
//  Exposes the ported Bliss renderer through the exact signature RV's
//  mainClouds.glsl expects, so deferred1 (main view) AND reflections.glsl
//  (water / ice / puddles / metal) drive it with no extra wiring.
// =====================================================================
vec4 GetVolumetricClouds(int cloudAltitude, float distanceThreshold, inout float cloudLinearDepth,
                         float skyFade, float skyMult0, vec3 cameraPos, vec3 nPlayerPos,
                         float lViewPosM, float VdotS, float VdotU, float dither) {

    // (1) Map RV's view-space light basis into the world-space globals the
    //     ported Bliss code reads. sunVec / upVec / gbufferModelViewInverse
    //     are in scope at every GetClouds() call site in RV.
    WsunVec      = normalize(mat3(gbufferModelViewInverse) * sunVec);
    sunElevation = dot(sunVec, upVec);

    // (1b) Terrain depth occlusion. RV passes lViewPosM = world distance to the
    //      solid fragment on this pixel. On real sky pixels (skyFade >= 0.7,
    //      RV's own threshold) force it to infinity so distant horizon clouds
    //      are not culled; on terrain pixels keep it, so the cloud raymarch
    //      stops at the terrain and clouds no longer draw through mountains.
    bliss_terrainDist = (skyFade >= 0.7) ? 1e9 : lViewPosM;

    // (2) Bliss' renderClouds() internally multiplies by gbufferModelViewInverse,
    //     so it wants a VIEW-space frag direction. Rebuild one from RV's
    //     world-space ray direction (nPlayerPos).
    vec3 FragPosition = mat3(gbufferModelView) * (nPlayerPos * 1024.0);

    // (3) Bliss takes two dither values: Dither.x jitters every ray step,
    //     Dither.y offsets each layer's start plane. RV's incoming `dither`
    //     is already a per-pixel, blue-noise-ish, TAA-animated value. The
    //     previous port set Dither.y = fract(dither + const), which is the
    //     SAME per-pixel value merely shifted -- perfectly correlated with
    //     Dither.x, so the start-offset and step-offset moved together and
    //     left the concentric ray-march banding. Decorrelate the second
    //     channel with a multiplicative hash so the start plane and the
    //     step phase use independent jitter, breaking up the banding.
    vec2 Dither = vec2(dither, fract(dither * 147.83 + 0.6180339887498949));

    // (4) Light + sky colour come from RV's own cloud-colour model
    //     (cloudColors.glsl). THIS is the one intentional bridge: Bliss'
    //     native sky LUT is not ported, so the clouds are lit in RV's
    //     palette. Scale with BLISS_CLOUD_BRIGHTNESS to taste.
    vec3 LightColor = cloudLightColor   * BLISS_CLOUD_BRIGHTNESS;
    vec3 SkyColor   = cloudAmbientColor * BLISS_CLOUD_BRIGHTNESS;

    // (5) Run the ported Bliss pipeline.
    vec3 cloudDepth = vec3(0.0);
    vec4 raw = bliss_renderClouds(FragPosition, Dither, LightColor, SkyColor, cloudDepth);

    // (6) Bliss returns vec4(scattered_colour, transmittance);
    //     RV wants  vec4(colour, alpha).  alpha = 1 - transmittance.
    float alpha = clamp(1.0 - raw.a, 0.0, 1.0);
    vec4 clouds = vec4(raw.rgb, alpha);

    // (7) Hand RV a cloud depth for its lightshaft / fog blend. Use the
    //     altitude of the lowest active layer as a stable approximation.
    if (alpha > 0.0) {
        float approxDist = max(float(CloudLayer0_height) - cameraPos.y, 32.0) / max(abs(nPlayerPos.y), 0.05);
        cloudLinearDepth = min(cloudLinearDepth, clamp(approxDist / far, 0.0, 1.0));
    }

    return clouds;
}

// ---------------------------------------------------------------------
//  ISOLATED HOOKS (optional) for godrays / world cloud-shadowing.
//  bliss_clouds.glsl exposes the two Bliss shadow samplers; these thin
//  wrappers set the world sun vector and forward the call, so RV's
//  lightshaft / shadow code can sample cloud occlusion cleanly.
// ---------------------------------------------------------------------

// Cloud shadow on a world surface point (feet-relative player position).
float bliss_CloudShadowAt(vec3 feetPlayerPos, vec3 worldSunVec) {
    WsunVec = worldSunVec;
    return bliss_GetCloudShadow(feetPlayerPos);
}

// Cloud transmittance along the sun ray for a world point — godrays /
// volumetric light. (Bliss' VLFOG sampler already takes the sun vector.)
float bliss_CloudGodrayTransmittance(vec3 worldPos, vec3 worldSunVec) {
    return bliss_GetCloudShadow_VLFOG(worldPos, worldSunVec);
}
