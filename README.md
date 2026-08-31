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

## 已对齐的 Windows 2.2 基础行为

### 待办纸

- 原生 Checkbox 勾选
- 完成项淡化并显示删除线
- Enter 在当前项后创建新待办并切换焦点
- 空待办 Backspace 删除并恢复相邻行焦点
- 单条待办最大 5000 字符
- 多行粘贴 / 批量添加最多 200 条，并清理 Markdown 任务列表、数字列表、项目符号前缀
- 显式 `≡` 拖动把手排序
- 拖到底部删除区可删除
- 100 步结构级撤销 / 重做
- 完成项自动置底
- 完成后自动清除，可通过结构历史恢复
- 待办项可关联一张笔记纸，可取消关联
- 关联笔记已经打开时，再点击关联入口会折叠回侧边；打开状态会亮起提示

### 笔记纸

- 编辑 / 浏览双模式
- Markdown 不启用 / 启用 / 增强三档
- 标题、引用、无序列表、数字列表、代码块、分隔线等轻量呈现
- Markdown 列表编辑：Enter 自动延续项目符号、数字列表和任务列表；空列表项再次回车退出列表

### 纸片

- 点击标题进入编辑，提交或失焦退出
- 左上角使用空心 / 实心图钉表示窗口置顶状态
- 纸片隐藏与真正删除分离
- 新建纸片尽量靠近当前纸片
- 标题、位置、尺寸、置顶、显示、折叠状态持久化

### 状态栏与管理

- 启动后不默认展示大型管理中心
- 系统状态栏提供新建待办 / 笔记、显示全部、隐藏全部
- 状态栏实时列出纸片，点击条目切换显隐
- 管理中心只在用户主动选择“管理”时打开
- 管理中心提供：主题、Markdown、待办视觉大小、完成项置底、完成后清除、待办关联笔记、关联标题显示、现有胶囊设置等

## 数据与稳定性

- Preferences 持久化
- schema 4
- 主数据与上一份成功保存状态分离
- 主数据损坏时尝试备份恢复
- 主数据与备份都异常时进入保护状态，避免空状态覆盖原数据
- 遇到未来 schema 时拒绝降级覆盖
- 编辑先写内存，空闲约 1 秒保存；持续输入最长约 10 秒强制保存；失败约 10 秒重试

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

这些 API 编译通过不代表所有 PC 窗口行为已经被真机确认；系统外框、极小窗口尺寸和窗口越界仍必须以真实 2in1 行为为准。

## 仍需继续对齐

当前还不能称为 Windows 2.2 完整等价，主要剩余：

- Todo 文本编辑结束后进入全局历史，以及“局部字符撤销优先、全局列表撤销兜底”的精确 Ctrl+Z 语义
- Todo 右键聚焦与紧凑右键菜单
- 更接近 Windows 的底部 `＋` 追加区与直接在行内处理多行粘贴
- zh / en / ja / ko 完整界面资源
- 笔记正文缩放等 v2.0 非平台专属细节
- 更完整的 Markdown 浏览态视觉
- HarmonyOS 真机上的窗口、状态栏、鼠标与 IME 回归

## CI

GitHub Actions 当前会对普通 PR 同时执行：

- `assembleHap`
- `assembleApp`
- AGC Developer-level Service Account 只读鉴权

测试签名采用显式的一次性流程；不会在日常 PR 提交中自动申请新的证书 / Profile。
