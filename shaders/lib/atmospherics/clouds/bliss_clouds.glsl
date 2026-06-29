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
//  Bliss' ORIGINAL coordinate math is left intact at every call site;
//  only the texture FETCH is swapped for a scale-matched procedural
//  field, so the relative feature sizes Bliss tuned between cloud layers
//  are preserved.
// =====================================================================

// Effective "texture resolution" the emulated channels are sampled at.
// A low base frequency biases the 2D coverage reads toward large cloud
// masses with open-sky gaps (natural layer separation); the fine fluff
// comes from the 3D erosion noise (bliss_densityAtPos) on top.
#define BLISS_NOISE_RES 48.0
// Bliss read ONE texel per coverage lookup (full local contrast) and built
// richness by COMBINING the large + small + 3D-erosion fields. Matching that
// here with only 2 octaves keeps the coverage contrast crisp (more octaves
// average toward 0.5 and wash the clouds out); the high-frequency fluff is
// supplied by the 3D erosion noise, not by stacking 2D octaves.
#define BLISS_FBM_OCTAVES 2

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

// Procedural stand-ins for the noisetex channels Bliss' cloud code reads.
// The argument C is the SAME normalized coord Bliss handed to texture2D();
// scaling by BLISS_NOISE_RES restores the feature sizes a real texture
// fetch would have produced. The per-channel offset decorrelates the
// "red" (fine detail) and "blue" (coverage) fields, matching the way
// Bliss used two distinct channels of noises.png.
float bliss_noiseB(vec2 C){ return bliss_fbm2(C * BLISS_NOISE_RES + 53.7); }
float bliss_noiseR(vec2 C){ return bliss_fbm2(C * BLISS_NOISE_RES +  3.1); }

//3D erosion noise (procedural; replaces Bliss' 3D-from-2D noisetex trick)
float bliss_densityAtPos(in vec3 pos){
	pos /= 18.;
	pos.xz *= 0.5;
	// The original built a trilinear value noise from a 2D fetch offset
	// per y-slice; this is the same value noise evaluated directly in 3D
	// with smooth interpolation, so cloud edges read soft, not blocky.
	return bliss_vnoise3(pos);
}


float bliss_GetAltostratusDensity(vec3 pos){

	float large = 1.0 - bliss_noiseB((pos.xz + cloud_movement)/100000.);
	large = max(large + LAYER2_COVERAGE - 0.7, 0.0);

	float medium = 1.0 - bliss_noiseB((pos.xz - cloud_movement)/7500. + vec2(-large,1.0-large)/5.0);

	float shape = max(large - medium*0.4 * clamp(1.5-large,0.0,1.0),0.0);

	return shape*shape;
}

float bliss_cloudCov(int layer, in vec3 pos, vec3 samplePos, float minHeight, float maxHeight){
	float FinalCloudCoverage = 0.0;
	float coverage = 0.0;
	float Topshape = 0.0;
	float Baseshape = 0.0;

	float LAYER0_minHEIGHT_FOG = CloudLayer0_height; 
	float LAYER0_maxHEIGHT_FOG = 100 + LAYER0_minHEIGHT_FOG;
	LAYER0_minHEIGHT_FOG = LAYER0_minHEIGHT;
	LAYER0_maxHEIGHT_FOG = LAYER0_maxHEIGHT;

	float LAYER1_minHEIGHT_FOG = max(CloudLayer1_height, LAYER0_maxHEIGHT); 
	float LAYER1_maxHEIGHT_FOG = 100 + LAYER1_minHEIGHT_FOG;
	LAYER1_minHEIGHT_FOG = LAYER1_minHEIGHT;
	LAYER1_maxHEIGHT_FOG = LAYER1_maxHEIGHT;


	vec2 SampleCoords0 = vec2(0.0); vec2 SampleCoords1 = vec2(0.0);

	float CloudSmall = 0.0;
	if(layer == 0){
		SampleCoords0 = (samplePos.xz + cloud_movement) / 5000 ;
		SampleCoords1 = (samplePos.xz - cloud_movement) / 500 ;
		CloudSmall = bliss_noiseR(SampleCoords1);
	}

	if(layer == 1){
		SampleCoords0 = -( (samplePos.zx + cloud_movement*2) / 10000);
		SampleCoords1 = -( (samplePos.zx - cloud_movement*2) / 2500);
		CloudSmall = bliss_noiseB(SampleCoords1);
	}

	if(layer == -1){
		float otherlayer = max(pos.y - (LAYER0_minHEIGHT_FOG+99.5), 0.0) > 0 ? 0.0 : 1.0;
		if(otherlayer > 0.0){
			SampleCoords0 = (samplePos.xz + cloud_movement) / 5000 ;
			SampleCoords1 = (samplePos.xz - cloud_movement) / 500 ;
			CloudSmall = bliss_noiseR(SampleCoords1);
		}else{
			SampleCoords0 = -( (samplePos.zx + cloud_movement*2) / 10000);
			SampleCoords1 = -( (samplePos.zx - cloud_movement*2) / 2500);
			CloudSmall = bliss_noiseB(SampleCoords1);
		}
	}

	float CloudLarge = bliss_noiseB(SampleCoords0);

	if(layer == 0){
		coverage = abs(CloudLarge*2.0 - 1.2)*0.5 - (1.0-CloudSmall);

		float layer0 = min(min(coverage + LAYER0_COVERAGE, clamp(LAYER0_maxHEIGHT_FOG - pos.y,0,1)), 1.0 - clamp(LAYER0_minHEIGHT_FOG - pos.y,0,1));

		Topshape = max(pos.y - (LAYER0_maxHEIGHT_FOG - 75),0.0) / 200.0;
		Topshape += max(pos.y - (LAYER0_maxHEIGHT_FOG - 10),0.0) / 15.0;
		Baseshape = max(LAYER0_minHEIGHT_FOG + 12.5 - pos.y, 0.0) / 50.0;

		FinalCloudCoverage = max(layer0 - Topshape - Baseshape * (1.0-rainStrength),0.0);
	}

	if(layer == 1){
		
		coverage = abs(CloudLarge-0.8) - CloudSmall;

		float layer1 = min(min(coverage + LAYER1_COVERAGE - 0.5,clamp(LAYER1_maxHEIGHT_FOG - pos.y,0,1)), 1.0 - clamp(LAYER1_minHEIGHT_FOG - pos.y,0,1));

		Topshape = max(pos.y - (LAYER1_maxHEIGHT_FOG - 75),0.0) / 200.0;
		Topshape += max(pos.y - (LAYER1_maxHEIGHT_FOG - 10), 0.0) / 15.0;
		Baseshape = max(LAYER1_minHEIGHT_FOG + 15.5 - pos.y, 0.0) / 50.0;

		FinalCloudCoverage = max(layer1 - Topshape*Topshape - Baseshape * (1.0-rainStrength), 0.0);
	}


	if(layer == -1){
	
		#ifdef CloudLayer0 
			float layer0_coverage =  abs(CloudLarge*2.0 - 1.2)*0.5 - (1.0-CloudSmall);
			float layer0 = min(min(layer0_coverage + LAYER0_COVERAGE, clamp(LAYER0_maxHEIGHT_FOG - pos.y,0,1)), 1.0 - clamp(LAYER0_minHEIGHT_FOG - pos.y,0,1));

			Topshape = max(pos.y - (LAYER0_maxHEIGHT_FOG - 75),0.0) / 200.0;
			Topshape += max(pos.y - (LAYER0_maxHEIGHT_FOG - 10),0.0) / 15.0;
			Baseshape = max(LAYER0_minHEIGHT_FOG + 12.5 - pos.y, 0.0) / 50.0;

			FinalCloudCoverage = max(layer0 - Topshape - Baseshape * (1.0-rainStrength),0.0);
		#endif
		
		#ifdef CloudLayer1
			float layer1_coverage = abs(CloudLarge-0.8) - CloudSmall;
			float layer1 = min(min(layer1_coverage + LAYER1_COVERAGE - 0.5,clamp(LAYER1_maxHEIGHT_FOG - pos.y,0,1)), 1.0 - clamp(LAYER1_minHEIGHT_FOG - pos.y,0,1));

			Topshape = max(pos.y - (LAYER1_maxHEIGHT_FOG - 75), 0.0) / 200;
			Topshape += max(pos.y - (LAYER1_maxHEIGHT_FOG - 10 ), 0.0) / 50;
			Baseshape = max(LAYER1_minHEIGHT_FOG + 12.5 - pos.y, 0.0) / 50.0;

			FinalCloudCoverage += max(layer1 - Topshape*Topshape - Baseshape * (1.0-rainStrength), 0.0);
		#endif
	}

	return FinalCloudCoverage;
}

//Erode cloud with 3d Perlin-worley noise, actual cloud value
float bliss_cloudVol(int layer, in vec3 pos, in vec3 samplePos, in float cov, in int LoD, float minHeight, float maxHeight){
	
	// float curvature = 1-exp(-25*pow(clamp(1.0 - length(pos - cameraPosition)/(32*80),0.0,1.0),2));
	// curvature = clamp(1.0 - length(pos - cameraPosition)/(32*128),0.0,1.0);

	float otherlayer = max(pos.y - (CloudLayer0_height+99.5), 0.0) > 0 ? 0.0 : 1.0;
	float upperPlane = otherlayer;

	float noise = 0.0 ;
	float totalWeights = 0.0;
	float pw =  log(fbmPower1);
	float pw2 = log(fbmPower2);

	samplePos.xz -= cloud_movement/4;

	samplePos.xz += pow( max(pos.y - (minHeight+20), 0.0) / 20.0,1.50) ;

	noise += (1.0-bliss_densityAtPos(samplePos * mix(100.0,200.0,upperPlane)) ) * sqrt(1.0-cov);

	if (LoD > 0){
		noise += abs( bliss_densityAtPos(samplePos * mix(450.0,600.0,upperPlane) ) - (1.0-clamp(((maxHeight - pos.y) / 100.0),0.0,1.0))) * 0.75 * (1.0-cov);
	}

	noise = noise*noise;
	float cloud = max(cov - noise*noise*fbmAmount,0.0);

	return cloud;
}

float bliss_GetCumulusDensity(int layer, in vec3 pos, in int LoD, float minHeight, float maxHeight){

	vec3 samplePos =  pos*vec3(1.0,1./48.,1.0)/4;
	
	float coverageSP = bliss_cloudCov(layer, pos,samplePos, minHeight, maxHeight);

	// return coverageSP;
	if (coverageSP > 0.001) {
		if (LoD < 0) return max(coverageSP - 0.27*fbmAmount,0.0);
		return bliss_cloudVol(layer, pos,samplePos,coverageSP,LoD	,minHeight, maxHeight) ;
	} else return 0.0;
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

	#ifdef CLOUDS_INTERSECT_TERRAIN
		// thank you emin for this world intersection thing
		#if defined DISTANT_HORIZONS
			float maxdist = dhRenderDistance + 16 * 32;
		#else
			float maxdist = far + 16*5;
		#endif

   		float lViewPosM = length(FragPosition) < maxdist ? length(FragPosition) - 1.0 : 100000000.0;
	#endif

if(layer == 2){
	
	#ifdef CLOUDS_INTERSECT_TERRAIN
		IntersecTerrain = length(rayProgress - cameraPosition) > lViewPosM;
	#endif

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

		#ifdef CLOUDS_INTERSECT_TERRAIN
			IntersecTerrain = length(rayProgress - cameraPosition) > lViewPosM;
		#endif
		
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
