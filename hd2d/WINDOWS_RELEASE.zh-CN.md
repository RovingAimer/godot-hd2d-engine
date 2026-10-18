# Windows 发布与切换指南（4.7.2-hd2d.1）

本版本通过 GitHub Release [4.7.2-hd2d.1](https://github.com/RovingAimer/godot-hd2d-engine/releases/tag/4.7.2-hd2d.1) 提供 Windows x86_64 非 .NET 编辑器和导出模板。本次二进制构建、资产与导出运行证据见 Release 随附的 [BUILD_MANIFEST.json](https://github.com/RovingAimer/godot-hd2d-engine/releases/download/4.7.2-hd2d.1/BUILD_MANIFEST.json)。本版本支持使用 Forward+／Vulkan 渲染并导出 Windows x86_64 独立游戏。Windows x86_64 是编译与导出目标；Forward+ 是项目的渲染方法，需在项目设置中选择。

## 发布资产

| 文件 | 用途 |
|---|---|
| `godot-hd2d-4.7.2-hd2d.1-windows-x86_64-editor.zip` | 独立编辑器，解压后运行 `godot.windows.editor.x86_64.hd2d.exe` |
| `godot-hd2d-4.7.2-hd2d.1-windows-x86_64-templates.zip` | Windows x86_64 Debug 与 Release 导出模板 |
| `BUILD_MANIFEST.json` | 本次源码身份、构建选项、资产哈希与验证证据 |
| `SHA256SUMS.txt` | 两个 ZIP 与 manifest 的 SHA256 校验值 |

两个 ZIP 均随附 Godot 的 `LICENSE.txt`、`COPYRIGHT.txt` 与相关许可声明。校验时对两个 ZIP 及 `BUILD_MANIFEST.json` 分别运行 `Get-FileHash -Algorithm SHA256`，并将结果与 `SHA256SUMS.txt` 对照。

## 构建配置

从同一个源码提交、补丁状态和 SCons 配置构建编辑器及两种模板。当前发行目标为 Windows x86_64，关闭 D3D12、ANGLE 和 AccessKit；Mono 默认关闭，本包不支持 C# 项目。

~~~powershell
scons -j8 platform=windows arch=x86_64 target=editor accesskit=no d3d12=no angle=no extra_suffix=hd2d
scons -j8 platform=windows arch=x86_64 target=template_debug accesskit=no d3d12=no angle=no extra_suffix=hd2d
scons -j8 platform=windows arch=x86_64 target=template_release accesskit=no d3d12=no angle=no extra_suffix=hd2d
~~~

模板 ZIP 中提供 `windows_debug_x86_64.exe` 与 `windows_release_x86_64.exe`。Windows 导出器按架构检查自定义模板，并分别读取 Debug 与 Release 路径。

## 在框架项目中切换

1. 将旧 Godot 编辑器可执行文件和项目配置文件 `project.godot`、`export_presets.cfg` 保留副本。
2. 将两个 ZIP 解压到独立目录。不要把新编辑器覆盖到已有 Godot 安装。本发行不提供 `.tpz`，以免模板写入官方 4.7.2 使用的同版本目录；项目通过 Custom Template 路径使用这套模板。
3. 运行新目录中的 `godot.windows.editor.x86_64.hd2d.exe`；在项目管理器中点击“导入”，选择框架的 `project.godot`，再点击“编辑”。
4. 在项目设置的 `Rendering > Renderer > Rendering Method` 选择 `Forward+`。本次 Windows 构建使用 Vulkan。若项目使用 `dof_exempt` 或 `dof_world_layer`，保持单视图，并关闭 MSAA、TAA 和时域升频。
5. 打开 `Project > Export`，新建或选择 `Windows Desktop` 预设。在 `Custom Template` 中分别把 `Debug` 指向解压出的 `windows_debug_x86_64.exe`，把 `Release` 指向 `windows_release_x86_64.exe`。
6. 导出到新的空目录。若要生成独立 `.pck`，在导出预设中关闭 `Binary Format > Embed PCK`。启动导出的游戏检查 `.exe`、`.pck` 与所需外部数据齐全。

启用 `Debug > Export Console Wrapper` 时，导出器会额外生成 `<游戏名>.console.exe`，用于带控制台输出的调试运行。面向玩家分发导出的游戏可执行文件、独立 `.pck` 和运行所需数据；玩家无需安装 Godot。

返回旧版本时，运行保留的旧编辑器并恢复 `project.godot` 与 `export_presets.cfg` 副本。官方编辑器和模板保持在原目录中，不受本次切换影响。

## 支持范围与验证记录

当前发行包仅覆盖 Windows x86_64 的 Forward+／Vulkan。`Mobile` 是渲染方法；手机平台、主机、Linux 与 SteamOS 未验收。景深扩展使用 Forward+；平台适配需分别验证渲染器与效果。C# 项目需要后续单独构建并验证 Mono 版本。

本次二进制的源码提交、构建选项、资产 SHA256、Windows 导出与运行检查记录在 Release 的 [BUILD_MANIFEST.json](https://github.com/RovingAimer/godot-hd2d-engine/releases/download/4.7.2-hd2d.1/BUILD_MANIFEST.json) 中。
## 在业务项目中切换

业务项目按上述步骤导入自己的 `project.godot`，并在自己的 Windows 导出预设中填写两条自定义模板路径。已经接入框架景深接口的项目可直接使用这版引擎；引擎切换保留原有相机、运镜轨道和文字策略配置。先导出到独立验证目录，确认启动、运镜、文字与透明图片表现后，再采用这套构建产物。C# 项目等待配套 .NET 版本。
