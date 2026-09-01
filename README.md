# PaperTodo HarmonyOS

PaperTodo 的 HarmonyOS PC / 2in1 版本。

当前开发目标不是机械复刻 Windows 的每个历史中间版本，而是在 HarmonyOS 平台约束下，优先对齐 **Windows PaperTodo v2.2 的日常可见行为与交互完成度**。

## 当前范围

- 设备：HarmonyOS `2in1`
- Bundle Name：`com.papertodo.app`
- 多窗口：每张纸仍是独立 `PaperAbility`
- 常驻入口：HarmonyOS 系统状态栏
- 管理中心：按需打开，不作为默认主界面
- 胶囊：暂时维持单屏、右侧、单队列实现

本阶段明确 **不做**：

- 多显示器 / 混合 DPI
- 左右边缘多队列
- 主胶囊 / 收起全部胶囊
- 胶囊窗口原语重构
- Windows 专属任务栏 / Alt+Tab / Win32 全屏避让策略

Windows v2.2 在这里用于定义产品行为，不代表照搬 WPF / Win32 实现。HarmonyOS 能直接使用 ArkUI / Stage 模型能力的地方，优先使用平台原生事件和组件。

## 已对齐的 Windows 2.2 基础行为

### 待办纸

- 原生 Checkbox 勾选
- 完成项淡化并显示删除线
- Enter 在当前项后创建新待办并切换焦点
- 空待办 Backspace 删除并恢复相邻行焦点
- 单条待办最大 5000 字符
- 多行粘贴最多 200 条，并清理 Markdown 任务列表、数字列表、项目符号前缀
- 多行粘贴直接在当前行处理：第一条保留选区前缀，最后一条保留选区后缀，其余内容拆为后续待办
- 自定义多行拆分后使用 `PasteEvent.preventDefault()` 阻止系统再次粘贴；单行仍保留原生输入行为
- 显式 `≡` 拖动把手排序
- 拖到底部删除区可删除
- 底部使用轻量 `＋` 追加区，点击后直接新建空待办并聚焦
- 100 步结构级撤销 / 重做
- 文本编辑按一次编辑会话进入全局历史，不按每个字符污染结构历史
- 输入框自身的局部撤销优先，未消费的 Ctrl+Z / Ctrl+Y 再由纸片级历史兜底
- 完成项自动置底
- 完成后自动清除，可通过结构历史恢复
- 待办项可关联一张笔记纸，可更换或取消关联
- 关联笔记已经打开时，再点击关联入口会折叠回侧边；打开状态会亮起提示
- Todo 行支持原生右键菜单，并在弹出前聚焦当前文本

### 笔记纸

- 编辑 / 浏览双模式
- Markdown 不启用 / 启用 / 增强三档
- 标题、引用、无序列表、数字列表、代码块、分隔线等轻量呈现
- Markdown 列表编辑：Enter 自动延续项目符号、数字列表和任务列表；空列表项再次回车退出列表
- 正文缩放范围 `50%–150%`，按 `10%` 档位保存到单张 Note
- 编辑态与浏览态共用同一正文缩放倍率，标题、引用、代码等浏览元素同步缩放
- 非 100% 时底栏显示当前比例，点击百分比恢复 100%
- 缩放使用 ArkUI `PinchGesture`：触摸 / 触控板 pinch 直接走缩放比例，Ctrl + 鼠标滚轮使用平台提供的轴事件语义，不增加 Raw Input 或全局 wheel hook

### 纸片

- 点击标题进入编辑，提交或失焦退出
- 左上角使用空心 / 实心图钉表示窗口置顶状态
- 纸片隐藏与真正删除分离
- 新建纸片尽量靠近当前纸片
- 标题、位置、尺寸、置顶、显示、折叠状态持久化
- Note 正文缩放作为可选字段持久化；旧数据没有该字段时自然回落到 100%，不需要窗口几何迁移

### 状态栏与管理

- 启动后不默认展示大型管理中心
- 系统状态栏提供新建待办 / 笔记、显示全部、隐藏全部
- 状态栏实时列出纸片，点击条目切换显隐
- 管理中心只在用户主动选择“管理”时打开
- 管理中心提供：主题、Markdown、待办视觉大小、完成项置底、完成后清除、待办关联笔记、关联标题显示、现有胶囊设置等

### 多语言

- 使用 HarmonyOS 原生资源限定词，不维护自定义语言状态机
- 已提供 `zh_CN / en_US / ja_JP / ko_KR`
- 管理中心、系统状态栏和主要 PaperDesktop 可见文案均已进入资源文件
- 动态文本通过 `ResourceManager` 格式化资源处理
- Markdown 工具栏插入的示例文字也随当前系统语言变化
- 语言资源目录只有 locale qualifier，**没有建立 density / DPI qualifier 目录**

## 数据与稳定性

- Preferences 持久化
- schema 4
- 主数据与上一份成功保存状态分离
- 主数据损坏时尝试备份恢复
- 主数据与备份都异常时进入保护状态，避免空状态覆盖原数据
- 遇到未来 schema 时拒绝降级覆盖
- 编辑先写内存，空闲约 1 秒保存；持续输入最长约 10 秒强制保存；失败约 10 秒重试
- `textZoom` 作为向后兼容的可选 Paper 字段，不因新增正文缩放引入全量 schema / 几何迁移

## HarmonyOS PC 窗口处理

当前纸片仍沿用多 `UIAbility` + `WINDOW_TOPMOST` 路线，不在本阶段切换到受限 `SYSTEM_FLOAT_WINDOW`。

已使用：

- `ohos.permission.WINDOW_TOPMOST`
- `ohos.permission.SET_WINDOW_TRANSPARENT`
- `setSupportedWindowModes([FLOATING])`
- `recover()`
- `setWindowDecorVisible(false)`
- `setWindowTitleButtonVisible(false, false, false)`
- `setWindowContainerColor()`
- `setWindowShadowEnabled(false)`

这些 API 编译通过不代表所有 PC 窗口行为已经被真机确认；系统外框、极小窗口尺寸、Topmost、Hover 与窗口越界仍必须以真实 2in1 行为为准。

## 仍需继续对齐

当前已经覆盖 Windows v2.2 的主要日常编辑链路，但仍不宣称逐功能完全等价。下一阶段优先：

- 对齐 v2.2 的多套纸片配色，同时保持 HarmonyOS 原生主题跟随，不引入 DPI 资源体系
- 继续改善 Markdown 浏览态视觉与行内表现，但保持轻量 parser，不为了完整 CommonMark 引入重依赖
- 评估动画 / 悬浮提示等非平台专属设置是否值得下放，优先选择不扩大窗口状态复杂度的实现
- HarmonyOS 真机上的窗口、状态栏、鼠标、触控板、IME、Ctrl+滚轮 / pinch 回归
- 根据真机结果校准极小窗口、Topmost、Hover 和贴边胶囊行为

仍明确不在当前 2.2 对齐阶段做：多显示器、混合 DPI、左右多队列、主胶囊以及 Windows 特有的任务栏 / Alt+Tab / Win32 全屏检测。

## CI

GitHub Actions 当前会对普通 PR 同时执行：

- `assembleHap`
- `assembleApp`
- AGC Developer-level Service Account 只读鉴权

当前 v2.2 对齐分支在 `93cf7662` 已通过 HAP 编译和完整 APP 打包。

测试签名采用显式的一次性流程；不会在日常 PR 提交中自动申请新的证书 / Profile。
