# Changelog

## 3.3.7 — 2026-09-03

第七轮 HarmonyOS PC / 2in1 真机回归修复，修复 3.3.6 将胶囊迁移到应用子窗口后完全不可见的问题。

- 修复在子窗口 `setUIContent()` 之前调用其 `getUIContext()` 的初始化顺序错误；初始 vp/px 换算改用已加载完成的父窗口 UIContext，严格保持 `createSubWindow → move/resize → setUIContent → setWindowMask → showWindow` 的官方异形窗口顺序。
- API 23 普通应用子窗口仍绑定父 WindowStage；父窗口不再整体移动到物理屏幕外，而是保持不可交互、不可聚焦、透明，并仅在屏幕右下角保留 1 个物理像素，避免子窗口因 parent 完全离屏而失去可见性。
- 可见胶囊仍由 `PaperTodoCapsuleSubWindow` 承载，Window Mask、实际最终 `windowRect` 贴右定位和 3.3.5 设置任务栏修复均保留。
- 版本更新为 `3.3.7`（`versionCode: 3030700`，`buildVersion: 1`）。

## 3.3.6 — 2026-09-03

第六轮 HarmonyOS PC / 2in1 真机回归修复，3.3.5 已证明 `setWindowMask()` 直接作用于多 UIAbility 的主窗口无法移除系统 floating 主窗外壳，本版按华为官方异形窗口实现改为真实应用子窗口。

- `MasterCapsuleAbility` 的 UIAbility 主窗口不再承载可见胶囊；主窗口仅作为 2in1 子窗口的生命周期宿主，关闭装饰、禁用交互并移动到物理屏幕外。
- 通过 `WindowStage.createSubWindow()` 创建 `PaperTodoCapsuleSubWindow`，使用 `setUIContent('pages/MasterCapsule')` 加载胶囊 UI；`Window.setWindowMask()` 现在作用于官方异形窗口实践明确支持的应用子窗口，而不是普通 UIAbility 主窗口。
- 子窗口显式关闭 `setFollowParentWindowLayoutEnabled`，独立维护位置和大小；父主窗保持 `WINDOW_TOPMOST`，子窗口随应用层级保持桌面可达。
- 每次调整胶囊尺寸后读取 `getWindowProperties().windowRect.width/height` 的实际像素尺寸，再以 `display.width - actualWidth` 重新计算 X；即使系统修正请求尺寸，右边缘仍精确落在物理屏幕边缘。
- Window Mask 同样按子窗口实际像素尺寸生成，避免请求尺寸与最终窗口尺寸不一致导致掩码失效。
- 版本更新为 `3.3.6`（`versionCode: 3030600`，`buildVersion: 1`）。

## 3.3.5 — 2026-09-02

第五轮 HarmonyOS PC / 2in1 真机回归修复，针对 3.3.4 仍可复现的任务栏设置入口和胶囊原生矩形壳。

- 设置窗口自定义关闭不再 `terminateSelf()`；改为最小化并保留 `ManagerAbility` / mission，让任务栏点击恢复同一个仍存活的设置窗口，避免 `removeMissionAfterTerminate: false` 留下死 mission。
- 胶囊宿主横坐标不再使用会扣除 Dock / 系统保留区的 `availableArea` 右边界，改为默认 2in1 物理显示宽度右边界，右侧胶囊真正贴屏幕边缘；纵向位置仍使用可用区域避让系统 UI。
- 按华为 2in1 异形窗口实践新增 `SystemCapability.Window.SessionManager` 和 `Window.setWindowMask()`：原生宿主窗口按主胶囊与普通胶囊实际可见像素生成联合掩码，矩形空白、队列间隙及收起后不可见区域由窗口系统真正裁掉，不再依赖背景色透明模拟异形窗口。
- 胶囊 Hover 导致关闭段伸出 / 收回时同步重算 Window Mask，即使宿主宽高未变化也更新原生窗口形状。
- 版本更新为 `3.3.5`（`versionCode: 3030500`，`buildVersion: 1`）。

## 3.3.4 — 2026-09-02

第四轮 HarmonyOS PC / 2in1 真机收敛，修复 3.3.3 审查发现的生命周期与发布门禁问题。

- `ManagerAbility` 仅在冷启动时启动一次后台 `EntryAbility`；任务栏 / singleton `onNewWant` / `onForeground` 不再重复启动隐藏 UIAbility，设置窗口恢复改为单通道串行处理，避免后台宿主反向抢占前台焦点。
- `EntryAbility` 在后续 `onNewWant` / `onForeground` 被系统复用时立即重新 `hideAbility()`；Recovery 状态独立保留，避免透明后台窗口成为最终前台 mission。
- 正式签名改为持久发布身份 `PaperTodo-Release-Stable-v1`：受信 runner 从受保护 AGC 服务账号密钥通过版本化 HMAC 稳定派生同一 P-256 私钥，并长期复用同一 AGC Release 证书 / Profile；不再每次构建消耗一个传统证书槽位。首次迁移只允许精确回收已被后续版本取代的 3.3.1 旧 Release 对，3.3.2 / 3.3.3 不自动删除。
- 正式签名增加公钥一致性门禁；若 AGC 服务账号密钥轮换导致派生私钥变化，流水线直接失败并要求显式迁移，不会静默替换现有稳定签名身份。
- `HarmonyOS Build` 与正式发布流水线都会调用现有 Hypium Local Test 命令并要求全部测试源码通过 `UnitTestArkTS` 编译；Huawei Linux previewer 当前在该阶段后无法执行断言，因此 Ubuntu CI 使用有界超时并明确标记这一平台限制，断言执行仍需 Windows / macOS / 真机环境，不能将 Linux 编译门禁冒充为测试执行成功。
- 主胶囊对 `uiLanguage` / `systemLanguage` 增加布局监听，运行中切换语言后会立即重新测量本地化主胶囊宽度。
- 版本更新为 `3.3.4`（`versionCode: 3030400`，`buildVersion: 1`）。

## 3.3.3 — 2026-09-02

第三轮 HarmonyOS PC / 2in1 真机回归修复，按 3.3.2 实机截图继续收敛窗口语义。

- 暂时隐藏纸片顶栏“拖动绑定到其他”入口；保留已有纸片关联数据、关联打开和非拖拽关联能力，不再向用户暴露当前设备上不可用的跨窗口拖拽入口。
- `ManagerAbility` 改为应用真正的 HOME / 任务栏入口，`EntryAbility` 仅保留后台启动、状态栏与纸片恢复职责；冷启动、singleton `onNewWant` 和前台恢复均直接作用于设置窗口。
- 主胶囊取消固定 `200vp` 宽度，按当前本地化文案实际测量，并限制在紧凑范围。
- 胶囊队列收起时不再只把普通胶囊设为透明，而是从 ArkUI 布局中移除普通行，并将原生宿主窗口高度同步缩至一个主胶囊，消除大块空白 / 点击区域。
- 胶囊宿主的窗口样式调用拆分；在 `loadContent()` 后再次应用透明背景与容器色，避免某个不受支持的窗口 API 阻断透明设置。
- 版本更新为 `3.3.3`（`versionCode: 3030300`，`buildVersion: 1`）。

## 3.3.2 — 2026-09-02

第二轮 HarmonyOS PC / 2in1 真机回归修复。3.3.1 对窗口纠偏和 Text 拖拽的判断不成立，本版按平台真实行为做结构修复。

- 右侧主胶囊与全部普通胶囊改由一个顶层 `MasterCapsuleAbility` 宿主窗口承载，不再为每张普通胶囊创建独立 `specified UIAbility` / mission。
- 胶囊宿主窗口右边缘固定；主胶囊收起 / 展开仅通过 ArkUI 内部行的 `translate` / `opacity` 呈现，不再改变顶层窗口 X 或宽度。
- 胶囊宿主几何优先使用 `resizeAsync()` / `moveWindowToAsync()`，并缓存最终目标矩形，避免异步 `resize` / `move` 调用互相覆盖造成来回飞动。
- 纸片“绑定到其他”拖动柄由 `Text` 原生文本拖拽改为自定义 `Stack` 拖拽源，使用 `draggable(true)`、`dragPreview()` 和现有 UDMF `onDragStart` 数据协议。
- 隐藏的 `EntryAbility` 在冷启动完成后同时处理 `onNewWant` 与 `onForeground`，任务栏 / mission 将现有应用带到前台时统一打开独立设置窗口。
- 版本更新为 `3.3.2`（`versionCode: 3030200`，`buildVersion: 1`）。

## 3.3.1 — 2026-09-02

本版本集中修复 3.3.0 HarmonyOS PC / 2in1 真机验证发现的窗口与顶栏回归，不新增产品范围。

- 修复右侧只显示主胶囊、普通侧边胶囊不可见：侧边胶囊顶层窗口始终完整位于可用工作区内。
- 修复胶囊没有稳定贴边以及展开 / 收起时在边缘与内侧反复跳动：停止横向逐帧 `moveWindowTo()`，改为 ArkUI 内容层 `translate + clip` 负责视觉收起 / 展开。
- 修复纸片顶栏“绑定到其他”无法发起拖拽：Text 拖拽源补齐 `CopyOptions.LocalDevice`，保留原 UDMF 关联协议。
- 修复顶栏 MD、新建 Todo、新建 Note、折叠 / 关闭等紧凑按钮只显示为点：统一使用 Normal Button 与零内边距。
- 修复再次点击任务栏 / 启动器入口无法打开设置：保留不可见 singleton launcher host，二次激活直接打开独立设置窗口。
- 正式包版本更新为 `3.3.1`（`versionCode: 3030100`，`buildVersion: 1`）。

## 3.3.0 — 2026-09-02

本阶段以 Windows PaperTodo v3.3 的产品行为为目标。冻结范围内的移植开发已经完成；涉及 HarmonyOS PC 窗口管理、系统状态栏和设备文件提供方的部分仍需真机验收，后续只处理现有功能缺陷，不再追加低优先级的 Windows 对等设置。

### 启动与系统入口

- 把 `EntryAbility` 改为无可见内容的启动 / 恢复宿主，不再把设置或纸片管理页当作应用主界面
- 接入 HarmonyOS `StatusBarViewExtensionAbility`、系统状态栏图标、快捷面板和右键菜单
- 新增附着状态栏项启动且隐藏自身窗口的驻留 Ability，承载菜单事件和运行期间全局快捷键
- 启动时恢复可见纸片，并把已折叠的侧边队列成员直接交给独立胶囊窗口，避免先闪出展开纸片
- 状态栏与纸片 / 胶囊都不可用时保留恢复页，避免静默失败
- 增加状态栏冷启动容错、Resident 就绪握手、死入口清理以及设置内诊断 / 重试
- 状态栏右键菜单增加实时纸片子菜单和统一退出入口

### 纸片产品语义

- 设置改为独立的常规、视觉、快捷键窗口，移除设置页中的新建按钮和纸片管理列表
- 重组纸片顶栏：置顶、点击编辑标题、关联拖动柄、Note 外部打开、新建 Todo、新建 Note，以及最右侧折叠 / 隐藏
- 系统关闭和 `Alt+F4` 改为隐藏纸片；空纸片立即删除，非空纸片使用明确确认对话框
- 删除最后一张纸片时自动创建并显示新的 Todo
- Todo 移除统计 / 撤销工具栏、永久草稿栏和常驻行删除按钮，改为底部轻量 `＋`、右键删除及 `Ctrl+Z` / `Ctrl+Y`
- Todo 行内多行粘贴会拆分和清理常见列表前缀；Todo 行拖动排序 / 删除保留
- Note 移除永久格式工具栏；空 Note 直接编辑，非空 Note 默认浏览，点击预览编辑，失焦回到浏览
- Note 格式入口迁移到编辑区右键菜单，保留常用键盘快捷键和顶栏 `MD` 外部打开
- 待办快启增加授权激活、失效警告和所在位置的父目录降级打开
- Markdown 增加波浪线围栏、白名单行内 HTML 和图片尺寸语法

### 胶囊

- 新增独立的 `EdgeCapsuleAbility`，在默认显示器可用工作区维护单条右侧队列
- 侧边胶囊静止时藏起关闭段，Hover / 活跃态伸出；点击折叠成员展开，点击活跃成员聚焦或按设置再次折叠
- 新增独立 `MasterCapsuleAbility`，作为队列第 0 位显示 `▾ 收起` / `▸ N 个`
- 主胶囊的收起只改变队列的视觉伸出量，不改变纸片的显示或折叠状态
- 支持纵向拖动主胶囊移动整列起始位置，并根据可用工作区、安全边距、成员数量和间距夹紧
- 增加胶囊开关依赖协调、展开纸片保留侧边标签、主胶囊开关、标题长度和队列间距设置
- 普通悬浮胶囊继续作为关闭侧边胶囊时的折叠形态

### 数据与工程

- 数据 schema 升级到 `7`，增加主胶囊、展开纸片侧边标签、整列收起状态、队列起始位置、标题长度和“关联纸片退出胶囊队列”设置
- 增加胶囊布局与纸片交互策略的纯逻辑测试
- 应用版本更新为 `3.3.0`（`versionCode: 3030003`，`buildVersion: 3`）
- release HAP / APP 已通过干净构建；正式流水线使用 AGC release 证书 / Profile 签名 APP，执行 `verify-app` 和 SHA-256 校验后才上传，任何签名失败都不降级为 unsigned；运行时测试和窗口行为仍需 HarmonyOS 目标设备

### 明确不移植

- 多显示器和多队列
- 左右边切换
- 侧边胶囊成员的队列内排序
- 把侧边胶囊横向拖出为普通悬浮胶囊
- 自定义全局快捷键录入、小键盘数字区分、队列 `1–9` 快速打开和按鼠标位置新建
- 外部字体文件、字体预设、增强粗体和标准 / 柔和 / 锐利文字渲染档位
- Markdown 图片标记的始终显示 / 仅编辑显示 / 始终隐藏档位
- 自定义外部打开后缀；固定使用临时 `.md`
- 关联名称长度、路径精简等显示细分偏好
- 高级设置模式、逐项悬浮说明和 Windows 阴影层次的逐项复刻
- 外部全屏避让、Alt+Tab / 任务视图隐藏及 Dock 聚合控制
- Windows 托盘完整菜单、开机启动、CLI、PowerShell 脚本胶囊和 Windows 分屏贴靠
