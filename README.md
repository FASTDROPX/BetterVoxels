# 🎥 Better Voxels (BodyCam & Immersive Edition)

[![Platform](https://img.shields.io/badge/Platform-Minecraft_Java-brightgreen?style=flat-square)](https://modrinth.com/)
[![Shader Loader](https://img.shields.io/badge/Loader-Iris%20%2F%20OptiFine-orange?style=flat-square)](https://github.com/IrisShaders/Iris)

**Better Voxels** is a heavyweight, highly customized fork of the voxel-based shader architecture, completely reimagined to deliver an ultra-realistic, cinematic **BodyCam (body-worn camera)** experience combined with deep environmental immersion. 

Originally built to transform standard volumetric lighting into an analog horror or tactical recording pipeline, this shader forces Minecraft's rendering engine to simulate camera lens distortion, dynamic physics, and high-fidelity lighting tech entirely via GLSL mathematics.

---

## 🚀 Key Features & Architectural Upgrades

### 🎥 1. The BodyCam Core
* **Fisheye Lens Distortion:** A custom-coded barrel distortion applied to the final frame buffer, simulating a wide-angle tactical bodycam lens.
* **Camera Artifacts & Vignette:** Realistic peripheral darkening, subtle chromatic aberration (RGB channel splitting), and analog camera grain that amplifies in low-light environments.
* **Adaptive Auto-Exposure:** Dynamic exposure simulation that mimics a digital sensor trying to adjust when transitioning from blinding daylight into pitch-black caves.

### 🌿 2. Advanced Grass & Foliage Physics
* **Entity Interaction:** Fully reactive vertex displacement. Grass, crops, and leaves realistically bend and flatten under the feet of both the player and nearby mobs[cite: 1].
* **Directional Weather Turbulence:** During storms or rain, foliage no longer just waves in a static loop[cite: 1]. The bending vector dynamically calculates its tilt based on storm intensity and the exact movement direction of the volumetric clouds[cite: 1].

### 🌦️ 3. Intelligent Cloud & Weather Mechanics
* **Altitude-Based Rain Occlusion:** An immersive weather logic override. The shader constantly tracks the camera's Y position. If you fly or ascend above the cloud generation threshold during a rainstorm, the shader dynamically drops the weather rendering alpha to 0, perfectly simulating flying above the storm into clear skies.

### 🌫️ 4. Environmental Immersion & Distortions
* **Multi-Layer Heat Shimmering:** High-fidelity air refraction (heat waves) rendered over extreme heat sources like lava blocks and torches[cite: 1]. 
* **Biomic Heat Waves:** Constant, subtle atmospheric distortion active throughout the entire Nether dimension and Desert biomes to simulate scorching air temperatures[cite: 1].
* **Lowland & Valley Fog:** Context-aware fog density that dynamically thickens inside deep cave systems, near large bodies of water, and within low-altitude biomes during nighttime[cite: 1].
* **Lens Fogging (Condensation):** A gradual white vignette that creeps onto the screen edges during sustained sprinting or when abruptly diving into freezing underground depths, simulating the operator’s heavy breathing fogging up the lens[cite: 1].

### ⚡ 5. Tactical Lighting Tech
* **Sensor Blinding:** Heavy lightning strikes momentarily overload the camera sensor, completely white-washing the exposure before smoothly recovering based on a customizable cooldown slider[cite: 1].
* **Volumetric Handheld Light:** True volumetric light shafts cutting through fog and darkness, emitted dynamically from light sources held in the player's hand[cite: 1].

> [!WARNING]
> **Better Voxels** utilizes advanced voxel-based path tracing and real-time GLSL calculations. It is a highly demanding graphical suite.

### Recommended Environment:
* **GPU:** NVIDIA GeForce RTX 3060 / 4060 / 5060 or AMD equivalent.
* **RAM:** **10GB - 12GB** allocated to Java (highly recommended to prevent Garbage Collector micro-stutters when running heavy modpacks).
* **Render Distance Optimization:** For maximum stability, it is recommended to set Minecraft's native Render Distance to **12–14 chunks** and offload distant rendering to **Distant Horizons (LODs)**.

## 📦 Installation

1. Ensure you are running **Minecraft 1.21.1+** with the **Iris Shader Loader** (or Oculus on Fabric/NeoForge).
2. Download the latest `.zip` release: `§1§lBetter§f§lVoxels v1.1§f§l.zip`.
3. Drop the zip file directly into your `.minecraft/shaderpacks/` directory.
4. Activate the shader in the in-game Video Settings menu and configure your preferences under the **Effects** tab.

---

## ⚖️ License & Credits

This project is a legal modified fork compliant with the **Complementary Agreement 1.3** / original shader licenses. 
* Core Voxel Architecture based on Complementary / Rethinking Voxels.

*Developed with passion for tactical realism, analog horror creators, and immersion enthusiasts.*
