# Godot HD2D Fork

This repository is an independent HD-2D customization based on Godot 4.7.2-stable, baseline commit **ed1daf0bf001b61586d9930840f2f1394092c079**. Development was AI-assisted. This is an unofficial project, unaffiliated with and not endorsed by the Godot Foundation or upstream team. It does not automatically create pull requests to upstream.

The upstream Godot MIT license, copyright, author information, and third-party notices remain in the repository root. Preserve those files and the licenses of bundled dependencies when modifying or distributing this fork. The custom modifications authored for this fork are also released under MIT. AI assistance does not change those obligations.

AI participated in the design, implementation, and documentation of these patches. Publishing this fork does not establish eligibility for upstream contribution. Before considering upstream submission, maintainers must review the [official contribution policy](https://contributing.godotengine.org/en/latest/development/contribution_rules.html).

The fork's current default maintenance branch is **codex/hd2d-4.7.2**. The official **upstream/master** branch remains unchanged.

中文说明：[README.md](README.md).

## Current implementation

Production P is the depth-of-field baseline for this fork and integrates a scene-aware depth-of-field path into Forward+. The user-accepted local FAR support compensation searches only nearby FAR donors with positive CoC that are no sharper than the current center. Clear foreground remains excluded. This is a local image-space approximation; it cannot recover hidden scene information or guarantee repair of every edge.

P exposes these main interfaces:

- **GeometryInstance3D.dof_exempt** excludes an object from the native depth-of-field input and redraws it separately to keep it sharp. If both flags are enabled, dof_exempt takes precedence.
- **GeometryInstance3D.dof_world_layer** places an object in the custom WORLD depth-of-field layer for the WORLD path.
- **RenderingServer.camera_attributes_set_dof_responses(camera_attributes, responses)** sets weighted near/far response endpoints for a camera. Each endpoint has eight floats: far enabled, distance, and transition; near enabled, distance, and transition; blur amount; and weight. Distances are in meters. A negative transition selects the native physical response, and an empty array restores the native response. This interface is Forward+ only.

See [SOURCE_IDENTITY.json](SOURCE_IDENTITY.json) for the exact baseline and patch identity; patch records are under [patches](patches/).

## Supported scope

The feature currently supports the **Forward+** path. Mobile does not implement the same WORLD and READABLE depth-of-field processing, and Compatibility does not support this feature. When using dof_exempt or dof_world_layer, disable MSAA, TAA, and temporal upscaling, and use a single view. Otherwise the renderer reports an error and omits geometry with these flags. Flagged objects are also omitted from reflection probes.

These interfaces apply only to supported materials. dof_exempt and WORLD geometry do not support depth_draw_always, alpha prepass/clip/coverage antialiasing, stencil, or SSS. WORLD geometry additionally requires ordinary MIX blending and standard depth testing, and cannot use screen textures, custom DEPTH, or refraction.

The Windows build options do not enable Forward+ by themselves. Set the rendering method to Forward+ in the Godot project and use an editor and export templates built from this fork. Do not mix these templates with official Godot binaries or binaries from a different source revision.

## Build and export

Prepare the platform toolchain required by this Godot version using the [official Godot compilation guide](https://docs.godotengine.org/en/latest/engine_details/development/compiling). Run these commands from the repository root. They use the recorded Windows x86_64 configuration; the Mono module is disabled by default.

~~~powershell
scons -j8 platform=windows arch=x86_64 target=editor accesskit=no d3d12=no angle=no extra_suffix=hd2d
scons -j8 platform=windows arch=x86_64 target=template_debug accesskit=no d3d12=no angle=no extra_suffix=hd2d
scons -j8 platform=windows arch=x86_64 target=template_release accesskit=no d3d12=no angle=no extra_suffix=hd2d
~~~

Build all three targets from the same source, patches, and remaining SCons options. Use the matching editor and debug/release templates for editing and export; select Forward+ in the project rendering settings.

This publication completed a fresh editor build and Vulkan runtime/static-image checks in the real street scene with strong blur and reversed foreground/background focus. No obvious visual regression from this cleanup was observed. See [BUILD_VALIDATION.json](BUILD_VALIDATION.json) for identity and scope. Export templates, exported games, performance, and full-speed motion were not revalidated in this publication. This is a source publication, with no binary Release.

## Performance reference

Existing GPU measurements used Windows, Forward+ / Vulkan, an RTX 4060 Laptop, 1920×1080, HEX/LOW quality, and a fixed street scene with weak blur. They came from a marker3 acceptance build, measured P1→candidate→P2 after 60 warm-up frames and across 120 sampled frames. P1 and P2 are measurements with compensation disabled in the same candidate build, not an old P binary or a stock baseline.

| GPU section median (ms) | P1 | Candidate | P2 |
|---|---:|---:|---:|
| Native DOF | 0.965712 | 0.973520 | 0.945184 |
| Both directional filters | 0.686080 | 0.703488 | 0.684544 |
| WORLD compute | 1.409024 | 1.409536 | 1.401856 |

The candidate's combined directional-filter cost was about 0.017–0.019 ms above the P reference state; the sample added no textures or buffers. WORLD compute excludes the preceding geometry MRT and the later READABLE redraw. There is no same-configuration stock or DOF-disabled baseline. These values therefore do not represent the complete custom depth-of-field cost and do not establish a whole-frame speedup. Measurements cover HEX/LOW only; BOX shares the compensation path but was not separately validated, and CIRCULAR does not use the local compensation. Results apply only to the hardware, scene, and settings listed above.

## Upgrading

Create a separate upgrade branch from a selected official Godot tag, then replay production P followed by the accepted FAR compensation. The two commits below contain only the engine changes, so they can be replayed without depending on documentation files on the new upstream branch. Replace 4.x.y with the selected official tag. Keep the upgrade branch separate from the current default maintenance branch and leave upstream/master unchanged.

~~~powershell
git fetch upstream tag 4.x.y
git switch -c codex/hd2d-upgrade-4.x.y 4.x.y
git cherry-pick c51abe811d181725e143d2a70e3966b3cd31db16
git cherry-pick 57ef0fd1147006d3668cb6a0fe7060f56fc8dd3f
~~~

After resolving conflicts, build the editor and both export templates from the same source and options. Check shader interfaces, actual exports, runtime behavior, and dynamic visuals at normal speed. This repository does not automatically open upstream Godot pull requests. Any proposal for upstream needs a separate maintainer review and must be initiated explicitly.