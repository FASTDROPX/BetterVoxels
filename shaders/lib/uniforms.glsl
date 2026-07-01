/*----------------------------------------------------------------------------------------------
        _____                                                                    _____
        ( ___ )                                                                  ( ___ )
        |   |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~|   |
        |   | ██╗   ██╗███╗   ██╗██╗███████╗ ██████╗ ██████╗ ███╗   ███╗███████╗ |   |
        |   | ██║   ██║████╗  ██║██║██╔════╝██╔═══██╗██╔══██╗████╗ ████║██╔════╝ |   |
        |   | ██║   ██║██╔██╗ ██║██║█████╗  ██║   ██║██████╔╝██╔████╔██║███████╗ |   |
        |   | ██║   ██║██║╚██╗██║██║██╔══╝  ██║   ██║██╔══██╗██║╚██╔╝██║╚════██║ |   |
        |   | ╚██████╔╝██║ ╚████║██║██║     ╚██████╔╝██║  ██║██║ ╚═╝ ██║███████║ |   |
        |   |  ╚═════╝ ╚═╝  ╚═══╝╚═╝╚═╝      ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝ |   |
        |___|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~|___|
        (_____)                              (thanks to isuewo and SpacEagle17)  (_____)

---------------------------------------------------------------------------------------------*/

uniform bool firstPersonCamera;

uniform int blockEntityId;
uniform int currentRenderedItemId;
uniform int entityId;
uniform int frameCounter;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform int heldItemId;
uniform int heldItemId2;
uniform int isEyeInWater;
uniform int moonPhase;
uniform int worldTime;
uniform int worldDay;
uniform int renderStage;

uniform float aspectRatio;
uniform float blindness;
uniform float darknessFactor;
uniform float darknessLightFactor;
uniform float maxBlindnessDarkness;
uniform float eyeAltitude;
uniform float frameTime;
uniform float frameTimeCounter;
uniform float far;
uniform float near;
uniform float nightVision;
uniform float rainStrength;
uniform float screenBrightness;
uniform float viewHeight;
uniform float viewWidth;
uniform float wetness;
uniform float sunAngle;
uniform float playerMood;
uniform float playerSize = 1.8;

uniform ivec2 atlasSize;
uniform ivec2 eyeBrightness;

uniform vec3 cameraPosition;
uniform vec3 fogColor;
uniform vec3 previousCameraPosition;
uniform vec3 skyColor;
uniform vec3 relativeEyePosition;

uniform vec4 entityColor;
uniform vec4 lightningBoltPosition;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D colortex9;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D gaux4;
uniform sampler2D normals;
uniform sampler2D noisetex;
uniform sampler2D specular;
uniform sampler2D tex;

uniform ivec3 cameraPositionInt = ivec3(-98257195);
uniform ivec3 previousCameraPositionInt;
uniform vec3 cameraPositionFract;
uniform vec3 previousCameraPositionFract;

uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;
#ifdef IRIS_FEATURE_HIGHER_SHADOWCOLOR
    uniform sampler2D shadowcolor2;
    uniform sampler2D shadowcolor3;
#endif

uniform sampler2DShadow shadowtex1;

#ifdef COMPOSITE
    uniform sampler2D shadowtex0;
#else
    uniform sampler2DShadow shadowtex0;
#endif

#if !defined DH_TERRAIN && !defined DH_WATER
    uniform mat4 gbufferProjection;
    uniform mat4 gbufferProjectionInverse;
#endif

#ifdef DISTANT_HORIZONS
    uniform int dhRenderDistance;

    uniform mat4 dhProjection;
    uniform mat4 dhProjectionInverse;
    
    uniform sampler2D dhDepthTex;
    uniform sampler2D dhDepthTex1;
#endif

#if COLORED_LIGHTING_INTERNAL > 0
    uniform usampler3D voxel_sampler;
#endif

#ifdef PUDDLE_VOXELIZATION
    uniform usampler2D puddle_sampler;
#endif

/*-----------------------------------------------------------------------------
  ___ _   _ ___ _____ ___  __  __   _   _ _  _ ___ ___ ___  ___ __  __ ___
 / __| | | / __|_   _/ _ \|  \/  | | | | | \| |_ _| __/ _ \| _ \  \/  / __|
| (__| |_| \__ \ | || (_) | |\/| | | |_| | .` || || _| (_) |   / |\/| \__ \
 \___|\___/|___/ |_| \___/|_|  |_|  \___/|_|\_|___|_| \___/|_|_\_|  |_|___/

-----------------------------------------------------------------------------*/

uniform float framemod8;
uniform float isEyeInCave;
uniform float inDry;
uniform float inRainy;
uniform float inSnowy;
uniform float velocity;
uniform float starter;
uniform float frameTimeSmooth;
uniform float eyeBrightnessM;
uniform float eyeBrightnessM2;
uniform float rainFactor;
#ifdef ECLIPSE_TIME_ACTIVE
// Eclipse global cinematic time (Iteration 14 base / Iteration 23): engine-
// smoothed sin/cos of the celestial angle at SEVEN pre-baked fade tiers
// (0.4/0.8/1.2/2.0/3.0/5.0/10.0 s). common.glsl selects the pair matching the
// TIME_TRANSITION_SPEED slider so the GUI speed control is live. Maintained by
// Iris across frames -- no fragile feedback buffer.
uniform float blissSunAngleS04;  uniform float blissSunAngleC04;
uniform float blissSunAngleS08;  uniform float blissSunAngleC08;
uniform float blissSunAngleS12;  uniform float blissSunAngleC12;
uniform float blissSunAngleS20;  uniform float blissSunAngleC20;
uniform float blissSunAngleS30;  uniform float blissSunAngleC30;
uniform float blissSunAngleS50;  uniform float blissSunAngleC50;
uniform float blissSunAngleS100; uniform float blissSunAngleC100;
#endif
uniform float inBasaltDeltas;
uniform float inCrimsonForest;
uniform float inNetherWastes;
uniform float inSoulValley;
uniform float inWarpedForest;
uniform float inPaleGarden;