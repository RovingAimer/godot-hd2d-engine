# Godot HD2D Fork

这是基于 Godot 4.7.2-stable 的独立 HD-2D 引擎定制，基线为 **ed1daf0bf001b61586d9930840f2f1394092c079**。此 fork 由 AI 辅助开发，属于非官方项目；与 Godot Foundation 及上游团队无隶属关系，也未获其背书。不会自动向上游创建 Pull Request。

上游 Godot 的 MIT 许可、版权、作者和第三方声明保留在仓库根目录。分发或修改时请一并保留这些文件与各依赖自身的许可说明。本仓库自有的定制修改同样以 MIT 许可发布。AI 辅助开发不改变这些许可义务。

AI 参与了定制补丁的设计、实现和文档整理。公开维护本 fork 不代表这些修改已满足 Godot 上游的贡献要求；如未来考虑上游贡献，应由维护者先核对[官方贡献政策](https://contributing.godotengine.org/en/latest/development/contribution_rules.html)。

当前 fork 的默认维护分支为 **codex/hd2d-4.7.2**；官方 **upstream/master** 保持上游原样。

English: [README.en.md](README.en.md).

## 当前实现

Production P 是本 fork 的景深基础，整合了 Forward+ 的场景景深路径。其上加入用户接受的局部 FAR 支撑补偿：算法只从局部范围内寻找 CoC 为正、且不比当前中心更清晰的 FAR 供体；清晰前景仍会被排除。它是局部图像近似，不能恢复被遮挡的场景信息，也不保证修复所有边缘。

P 的主要接口如下：

- **GeometryInstance3D.dof_exempt**：将对象从原生景深输入中排除，并通过独立绘制保持清晰；若两个标记都启用，dof_exempt 优先。
- **GeometryInstance3D.dof_world_layer**：将对象绘制到自定义 WORLD 景深层，供 WORLD 路径处理。
- **RenderingServer.camera_attributes_set_dof_responses(camera_attributes, responses)**：为相机设置加权的近景/远景响应端点。每个端点由 8 个浮点数组成：远景启用、距离、过渡，近景启用、距离、过渡，模糊量和权重；距离以米计，负过渡使用原生物理响应，空数组恢复原生响应。此接口仅支持 Forward+。

精确基线与补丁身份见 [SOURCE_IDENTITY.json](SOURCE_IDENTITY.json)；补丁记录位于 [patches](patches/)。

## 适用范围

目前只支持 **Forward+** 路径；Mobile 不包含相同的 WORLD 与 READABLE 景深处理，Compatibility 不支持该功能。使用 dof_exempt 或 dof_world_layer 时，必须关闭 MSAA、TAA、时域升频并使用单视图；否则渲染器会报错并省略这些标记的几何体。带有这些标记的对象也不会绘制到反射探针。

这些入口只适用于受支持的材质：dof_exempt 与 WORLD 几何层不支持 depth_draw_always、alpha 预处理/裁剪/覆盖抗锯齿、stencil 或 SSS；WORLD 层还要求普通 MIX 混合与常规深度测试，并且不能使用屏幕纹理、自定义 DEPTH 或折射。

Windows 构建选项不会启用 Forward+。在 Godot 项目中将渲染方法设为 Forward+，并使用本 fork 构建的编辑器和导出模板。请勿将官方版或不同源码版本的模板与此 fork 混用。

## 构建与导出

先按 [Godot 官方编译文档](https://docs.godotengine.org/en/latest/engine_details/development/compiling)准备当前 Godot 版本所需的平台工具链。以下命令从仓库根目录执行，使用当前记录的 Windows x86_64 配置；Mono 模块默认关闭。

~~~powershell
scons -j8 platform=windows arch=x86_64 target=editor accesskit=no d3d12=no angle=no extra_suffix=hd2d
scons -j8 platform=windows arch=x86_64 target=template_debug accesskit=no d3d12=no angle=no extra_suffix=hd2d
scons -j8 platform=windows arch=x86_64 target=template_release accesskit=no d3d12=no angle=no extra_suffix=hd2d
~~~

三个目标必须使用同一源码、补丁和其余 SCons 选项。将生成的匹配编辑器与 debug/release 模板用于编辑和导出；Forward+ 需在项目渲染设置中选择。

本次已在独立目录完成编辑器完整构建，并使用真实街景完成强虚化及前后焦点反转的 Vulkan 运行与静态画面观察；未发现本次整理引入的明显画面回退。构建身份和检查边界见 [BUILD_VALIDATION.json](BUILD_VALIDATION.json)。本次未重新构建导出模板、验证导出游戏、测量性能或进行完整正常速度运镜验收，因此只发布源码，不发布二进制发行包。

## 性能参考

已有 GPU 样本来自 Windows、Forward+ / Vulkan、RTX 4060 Laptop、1920×1080、HEX/LOW 与固定弱虚化街景。数据来自 marker3 验收构建，按 P1→候选→P2 测量，预热 60 帧后采样 120 帧；P1/P2 是同一个候选构建中关闭补偿的测量状态，不是旧 P 二进制或 stock 基线。

| GPU 区段中位数（ms） | P1 | 候选 | P2 |
|---|---:|---:|---:|
| 原生 DOF | 0.965712 | 0.973520 | 0.945184 |
| 两方向滤波合计 | 0.686080 | 0.703488 | 0.684544 |
| WORLD compute | 1.409024 | 1.409536 | 1.401856 |

候选的两方向滤波合计相对 P 参考状态约增加 0.017–0.019 ms；样本未增加纹理或缓冲。WORLD 数值不包含前面的几何 MRT 和后续 READABLE 重绘；也没有同配置的 stock 或关闭 DOF 基线。因此这些数据不能代表完整自定义景深成本，也不能据此宣称整帧提速。计时只覆盖 HEX/LOW；BOX 共用补偿路径但未单独验收，CIRCULAR 不使用局部补偿。结果只适用于上述硬件、场景和设置。

## 升级维护

从选定的官方 Godot tag 创建独立升级分支，按顺序重放 production P 与已接受的 FAR 补偿。下面两个提交只包含引擎修改，可直接按顺序迁移，无需依赖切换上游后不在工作区的补丁文件。将 4.x.y 替换为所选官方 tag。升级分支与当前默认维护分支分开；不要改动 upstream/master。

~~~powershell
git fetch upstream tag 4.x.y
git switch -c codex/hd2d-upgrade-4.x.y 4.x.y
git cherry-pick c51abe811d181725e143d2a70e3966b3cd31db16
git cherry-pick 57ef0fd1147006d3668cb6a0fe7060f56fc8dd3f
~~~

解决冲突后，从同一源码和选项构建编辑器、debug 模板及 release 模板；随后检查 shader 接口、实际导出、运行行为和正常速度下的动态画面。本仓库不会自动向 Godot 上游开 PR。任何对上游的提议都需要维护者单独审查并主动发起。