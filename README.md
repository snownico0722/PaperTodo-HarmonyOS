# PaperTodo HarmonyOS

PaperTodo 的 HarmonyOS 原生重写，使用 ArkTS + ArkUI。当前预览版以 Windows [PaperTodo](https://github.com/snownico0722/PaperTodo) v3.3 的产品语义为基准，优先还原“独立纸片 + 系统常驻入口 + 侧边胶囊”的日常使用方式，而不是把设置页做成任务管理主界面。

当前应用版本为 `3.3.0-preview.2`，数据 schema 为 `7`，目标 SDK 为 HarmonyOS `6.1.0(23)` / API 23。工程当前只声明 `2in1` 设备类型；桌面窗口、Hover、Topmost 和系统状态栏入口都需要在 HarmonyOS PC / 2in1 上验收。

> 本分支已经完成大部分 v3.3 行为的代码接入和 unsigned HAP 编译，但仍属于真机验收中的预览版本。下文把“代码已接入”和“已在所有设备验证”严格区分。

## 产品语义

启动 PaperTodo 后不应出现一个常驻的“主界面”：

1. `EntryAbility` 只负责无可见内容的启动和恢复。
2. 已显示的 Todo / Note 以各自独立纸片窗口恢复；已折叠且启用侧边胶囊的纸片由独立胶囊窗口恢复。
3. 支持 `SystemCapability.PCService.StatusBarManager` 的 2in1 设备会安装 PaperTodo 系统状态栏入口，并启动隐藏的驻留 Ability。
4. 设置是独立窗口，只包含常规、视觉、快捷键三个分区，不承担新建和纸片管理职责。

新建 Todo / Note 的主要入口位于纸片顶栏；系统状态栏菜单、状态栏快捷面板、纸片 / 胶囊右键菜单和全局快捷键也可新建。设置页不放“新建待办 / 新建笔记”操作。

### 纸片顶栏

展开纸片的顶栏按 Windows 原版语义组织：

- 拖动柄、置顶、点击编辑标题
- 可拖出的纸片关联柄
- Note 的 `MD` 外部打开入口
- `＋✓` 新建 Todo、`＋✎` 新建 Note
- 最右侧在胶囊可用时显示 `─` 并折叠；胶囊关闭时显示 `×` 并隐藏纸片

系统关闭按钮或 `Alt+F4` 的语义同样是“隐藏”，不是删除。删除只出现在右键菜单中：空纸片立即删除，有内容的纸片使用明确确认对话框；删除最后一张纸片时会自动创建并显示一张新的 Todo，避免进入无入口状态。窄窗口会把关联、MD 和新建按钮作为一组收起，但始终保留最右侧的折叠 / 隐藏入口。

### Todo 纸

- 每行只保留勾选框、行内编辑文本、可选关联标记和 `≡` 拖动柄
- 底部使用轻量的全宽 `＋` 新增项，不保留永久草稿输入栏
- Enter 插入下一项，多行粘贴自动拆分，并清理常见列表、序号和 Markdown checkbox 前缀
- `Ctrl+Z` / `Ctrl+Y` 提供整表撤销 / 重做；空白且无关联的行可用键盘删除
- Todo 行可通过拖动柄排序，也可拖到底部临时删除区删除
- Todo 可关联另一张纸片、文件或文件夹；这些关联互斥，可在右键菜单中打开、更换或解除
- “完成后清除”“已完成置底”、四档行高和文本加粗均可配置

这里的拖动排序是 Todo 行排序，与明确不移植的“侧边胶囊队列排序”无关。

### Note 纸

- 空 Note 打开后直接编辑；非空 Note 默认进入浏览态
- 点击预览内容进入对应位置编辑，编辑器失焦后回到浏览态
- 不显示永久 Markdown 格式工具栏；粗体、斜体、删除线、标题、引用、列表、代码、链接和图片入口位于编辑区右键菜单，常用格式保留键盘快捷键
- 支持关闭 / 基础 / 增强三档轻量 Markdown 预览，以及标题、列表、引用、代码块、分割线、链接和内部图片
- 可把当前内容写成临时 `.md` 并交给系统关联应用打开；外部修改不会自动回写
- 每张 Note 独立保存 50%～150% 文字缩放，支持 `Ctrl+滚轮`

图片可通过系统选择器、受授权的 `PasteButton` 或兼容的 UDMF 拖入导入。导入后保存应用私有副本，并执行格式、大小、像素尺寸和所属 Note 校验；当前不直接渲染网络图片，也不是完整 CommonMark 实现。

## v3.3 对齐矩阵

| 能力 | 当前状态 | 说明 |
| --- | --- | --- |
| 无主界面启动与独立纸片恢复 | 代码已接入，真机复核中 | 启动宿主透明、无标题栏；只在启动失败时显示恢复页 |
| HarmonyOS 系统状态栏入口 | 代码已接入，真机复核中 | 使用 `StatusBarViewExtensionAbility`、状态栏菜单和隐藏驻留 Ability；仅支持具备对应 PC 系统能力的设备 |
| 独立 Todo / Note 纸片 | 代码已接入 | `PaperAbility` 按 `paperId` 使用 `specified` 实例，窗口无系统标题栏、透明背景、无系统阴影 |
| 普通悬浮胶囊 | 已保留 | 关闭侧边胶囊后，折叠纸片可使用可自由移动的普通胶囊形态 |
| 单屏右侧侧边胶囊 | 代码已接入，真机复核中 | 每张队列成员使用独立 `EdgeCapsuleAbility`；按系统可用工作区定位 |
| 主胶囊 | 代码已接入，真机复核中 | 使用独立 `MasterCapsuleAbility`；`▾ 收起` / `▸ N 个` 只控制队列视觉收进和展开，不改变纸片折叠状态 |
| 展开纸片保留侧边标签 | 可配置 | 点击折叠标签展开；点击已展开标签默认聚焦，也可配置为再次折叠 |
| 主胶囊纵向移动整列 | 代码已接入 | 移动的是整列起始位置，不改变成员顺序 |
| 多屏 / 多队列 | 明确不移植 | HarmonyOS 版本只维护默认显示器上的一条右侧队列 |
| 左右换边 | 明确不移植 | 不提供左侧队列，也不迁移旧显示器 / 边侧状态 |
| 侧边胶囊队列排序 | 明确不移植 | 队列按稳定的纸片顺序排列，不提供逐胶囊纵向重排 |
| 从队列横向拖出 | 明确不移植 | 不通过拖出把侧边成员转换成普通悬浮胶囊 |
| Windows 托盘、开机启动、CLI、PowerShell 脚本胶囊、全屏避让 | 平台专属，不移植 | HarmonyOS 使用系统状态栏扩展作为常驻入口 |

## 胶囊行为

- 胶囊窗口高度为 46 vp，内容体高度为 30 vp；宽度按类型标记和标题动态测量并限制范围
- 侧边队列默认从可用工作区顶部 48 vp 开始，安全边距为 8 vp，间距可选 `0 / 4 / 8` vp
- 折叠成员静止时把 14 vp 的关闭段藏到屏幕外，Hover 时滑出；展开纸片对应的侧边标签保持完整可见
- 主胶囊固定在队列第 0 位，可纵向拖动整列；收起整列时每个成员只保留约 40 vp 的可见区域
- 单击折叠成员会展开纸片；单击已展开成员默认聚焦纸片，可通过设置改为再次折叠
- 关闭区只隐藏纸片；右键菜单提供新建、设置、清除已完成 / 外部打开、折叠 / 展开、隐藏和删除
- 关闭胶囊模式或侧边胶囊模式后会重新协调纸片与胶囊窗口，避免同一纸片同时留下重复窗口

## 系统状态栏入口

兼容设备上，PaperTodo 会把图标加入 HarmonyOS 系统状态栏。左键快捷面板包含：

- 新建 Todo / Note
- 显示全部 / 隐藏全部
- 打开设置

右键菜单包含新建 Todo、新建 Note、显示 / 隐藏全部、实时纸片子菜单、设置和退出。状态栏安装失败可在设置中查看状态并重试。该入口依赖 `SystemCapability.PCService.StatusBarManager`，不应把普通 Dock 图标或一个常驻大窗口当作替代品；设备不支持该能力时，纸片功能仍可工作，但没有等价的系统常驻入口。

## 设置与快捷键

设置窗口只有三个页签：

- 常规：语言、Markdown、Todo 行高、完成项行为、图片压缩、纸片关联、动画、纸片顶栏、标题长度、胶囊行为和备份恢复
- 视觉：主题、配色、整体缩放、Note / Todo / 标题 / 胶囊文字、缩放角标
- 快捷键：运行期间全局快捷键及注册状态

支持跟随系统 / 简体中文 / English / 日本語 / 한국어，主题支持跟随系统 / 浅色 / 深色，并提供暖纸、墨、林、霞四套配色。全局快捷键默认关闭，只有应用进程仍在运行且系统注册成功时有效：

- `Ctrl+Alt+S`：显示全部
- `Ctrl+Alt+H`：隐藏全部
- `Ctrl+Alt+P`：切换全部显隐
- `Ctrl+Alt+T`：新建并显示 Todo
- `Ctrl+Alt+N`：新建并显示 Note
- `Ctrl+Alt+Q`：保存、移除状态栏入口并退出

当前使用左 `Ctrl` + 左 `Alt`，不支持自定义映射；系统不支持或组合键冲突时会显示相应状态。

## 数据与恢复

- 最多 100 张纸片，标题长度可配置为 2～20 个字符
- Todo 单项最多 2000 个 UTF-16 代码单元，单次多行粘贴最多 200 项；Note 最多 200000 个 UTF-16 代码单元
- 主数据使用 Preferences 保存，UI 修改先进入内存，空闲约 1 秒后落盘，持续输入最长约 10 秒强制保存
- Ability 进入后台、销毁或执行关键操作前强制 flush；保存失败会延迟重试
- backup 保留上一份成功落盘状态；主数据损坏时优先恢复有效备份，并避免默认数据覆盖损坏现场
- v1 / v2 像素几何会迁移为 VP 几何；旧的显示器 ID 和左右边状态统一归入默认显示器的右侧队列
- 删除纸片会清理其他 Todo 对它的失效关联；Note 附件采用延迟孤儿回收，以保护仍可能被 backup 引用的文件

## 构建

### DevEco Studio

使用支持 HarmonyOS SDK `6.1.0(23)` 的 DevEco Studio 打开仓库根目录，完成 SDK / ohpm 同步后构建。仓库不提交签名证书或私钥；安装真机或提交 AppGallery Connect 时需要配置开发者签名。

### 命令行

准备 HarmonyOS Command Line Tools `6.1.0.816`，设置 `OHPM_HOME`、`HOS_SDK_HOME` 和 `PATH`，并在仓库根目录创建不提交的 `local.properties`：

```properties
hwsdk.dir=/absolute/path/to/command-line-tools/sdk
```

安装依赖并编译 unsigned HAP：

```bash
ohpm install
hvigorw clean --no-daemon
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

打包 unsigned APP：

```bash
hvigorw assembleApp --mode project -p product=default -p buildMode=debug -p enableSignTask=false --no-daemon
```

逻辑测试位于 `entry/src/test/`。`hvigorw test` 可以编译测试模块，但在无 HarmonyOS 测试运行时的纯 Linux 环境中可能等待设备；完整执行请使用已配置目标设备 / 模拟器的 DevEco Studio 测试目标。

### GitHub Actions

- **HarmonyOS Build**：main 分支 push、PR 和手动触发时编译 unsigned HAP
- **HarmonyOS Package**：PR、`v*` tag 和手动触发时打包 unsigned APP / HAP、`SHA256SUMS` 和 ZIP
- CI 工具链固定为 `6.1.0.816`，下载包执行 SHA-256 校验并使用 GitHub Actions Cache

## 工程结构

```text
entry/src/main/ets/
├─ entryability/                 # 无可见内容的启动与恢复宿主
├─ trayresidentability/          # 系统状态栏附着的隐藏驻留 Ability
├─ statusbarviewability/         # 状态栏快捷面板 ExtensionAbility
├─ managerability/               # 独立设置窗口
├─ paperability/                 # 独立展开纸片 / 普通胶囊窗口
├─ edgecapsuleability/           # 单个右侧胶囊窗口
├─ mastercapsuleability/         # 主胶囊窗口
├─ common/                       # 数据、窗口协调、Markdown、图片和拖放逻辑
└─ pages/                        # Host、Recovery、Settings、Paper 和胶囊 UI
```

## 已知限制与验收重点

- 系统状态栏扩展、隐藏驻留、无边框透明窗口、Topmost、Hover 和 40 vp 级小窗口都依赖 HarmonyOS PC / 2in1 的实际窗口管理实现，编译通过不代表所有机器行为一致
- API 23 中 `excludeFromDock` 对三方应用不能作为有效保证；隐藏 Resident 不显示 Dock 图标，可见纸片在 Dock / 任务中心的聚合方式由系统决定
- 文件 / 文件夹快启依赖来源应用提供兼容 UDMF 记录，以及系统文档提供方授予可持久化 URI 权限
- 图片粘贴和拖入依赖系统授权与来源记录；不解析 HTML / Base64 图片，不直接渲染网络图片
- Markdown 是轻量逐行预览，不支持表格、完整块级 HTML 或完整 CommonMark
- 外部打开只交付临时 Markdown 只读副本，不自动同步外部编辑结果
- 多屏、多队列、左右换边、侧边胶囊队列排序和横向拖出不在移植范围内

本预览的行为变更见 [CHANGELOG.md](CHANGELOG.md)。
