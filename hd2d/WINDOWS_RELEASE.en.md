# Windows Release and Switching Guide (4.7.2-hd2d.1)

This version is distributed through [GitHub Release 4.7.2-hd2d.1](https://github.com/RovingAimer/godot-hd2d-engine/releases/tag/4.7.2-hd2d.1), with a Windows x86_64 editor and export templates built without .NET support. The accompanying Release [BUILD_MANIFEST.json](https://github.com/RovingAimer/godot-hd2d-engine/releases/download/4.7.2-hd2d.1/BUILD_MANIFEST.json) records this binary build, assets, and export/runtime evidence. It supports Forward+ / Vulkan rendering and standalone Windows x86_64 game exports. Windows x86_64 is the compile and export target; Forward+ is the project rendering method and must be selected in project settings.

## Release assets

| File | Purpose |
|---|---|
| `godot-hd2d-4.7.2-hd2d.1-windows-x86_64-editor.zip` | Standalone editor; launch `godot.windows.editor.x86_64.hd2d.exe` after extraction |
| `godot-hd2d-4.7.2-hd2d.1-windows-x86_64-templates.zip` | Windows x86_64 Debug and Release export templates |
| `BUILD_MANIFEST.json` | Source identity, build options, asset hashes, and validation evidence |
| `SHA256SUMS.txt` | SHA256 checksums for both ZIPs and the manifest |

Both ZIPs include Godot `LICENSE.txt`, `COPYRIGHT.txt`, and related notices. To verify the downloads, run `Get-FileHash -Algorithm SHA256` for both ZIPs and `BUILD_MANIFEST.json`, then compare the results with `SHA256SUMS.txt`.

## Build configuration

Build the editor and both templates from the same source commit, patch state, and SCons options. The release target is Windows x86_64, with D3D12, ANGLE, and AccessKit disabled. Mono is disabled by default; this package does not support C# projects.

~~~powershell
scons -j8 platform=windows arch=x86_64 target=editor accesskit=no d3d12=no angle=no extra_suffix=hd2d
scons -j8 platform=windows arch=x86_64 target=template_debug accesskit=no d3d12=no angle=no extra_suffix=hd2d
scons -j8 platform=windows arch=x86_64 target=template_release accesskit=no d3d12=no angle=no extra_suffix=hd2d
~~~

The template ZIP contains `windows_debug_x86_64.exe` and `windows_release_x86_64.exe`. The Windows exporter checks custom template architecture and reads separate Debug and Release paths.

## Switch a framework project

1. Keep copies of the previous Godot editor executable and the project configuration files `project.godot` and `export_presets.cfg`.
2. Extract both ZIPs into separate directories. Keep the new editor outside any existing Godot installation. This release omits `.tpz` so templates do not write into the version directory used by the official Godot 4.7.2 install; configure this project through its Custom Template paths.
3. Open the framework project's `project.godot` with `godot.windows.editor.x86_64.hd2d.exe` from the new editor directory.
4. In project settings, set `Rendering > Renderer > Rendering Method` to `Forward+`. This Windows build uses Vulkan. If the project uses `dof_exempt` or `dof_world_layer`, use a single view and disable MSAA, TAA, and temporal upscaling.
5. Open `Project > Export`, create or select a `Windows Desktop` preset, and set the `Debug` and `Release` entries under `Custom Template` to the extracted `windows_debug_x86_64.exe` and `windows_release_x86_64.exe` files.
6. Export to a new empty directory. To produce a separate `.pck`, disable `Binary Format > Embed PCK` in the export preset. Launch the exported game and check that the `.exe`, `.pck`, and required external data are present.

When `Debug > Export Console Wrapper` is enabled, the exporter also creates `<game-name>.console.exe` for debugging with console output. Distribute the exported game executable, separate `.pck`, and required runtime data to players; they do not need to install Godot.

To return to the previous version, run the saved old editor and restore the saved `project.godot` and `export_presets.cfg`. The existing official editor and templates remain in their original directories.

## Supported scope and validation

This release package covers Windows x86_64 with Forward+ / Vulkan. `Mobile` is a rendering method; phone, console, Linux, and SteamOS targets have not been validated. There is no verified automatic fallback to Compatibility and no guarantee of identical effects. C# projects require a separate Mono build and validation in the future.

The Release [BUILD_MANIFEST.json](https://github.com/RovingAimer/godot-hd2d-engine/releases/download/4.7.2-hd2d.1/BUILD_MANIFEST.json) records the source commit, build options, asset SHA256 values, Windows export, and runtime checks for this binary release.
## Switching a game project

Launch the extracted editor and use Import in the Project Manager to select the game project's own `project.godot`, then choose Edit. Set both Custom Template paths in that project's Windows export preset. Projects already using the framework DOF APIs retain their camera, cinematic tracks, and content policies. Export to a separate validation directory and check startup, cinematics, text, and transparent images before adopting the resulting build. C# projects require a future matching .NET build.
