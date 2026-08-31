# PaperTodo HarmonyOS

PaperTodo 的 HarmonyOS 原生版本，使用 ArkTS + ArkUI 重写。当前功能面已达到 Windows [PaperTodo v1.6](https://github.com/snownico0722/PaperTodo/releases/tag/v1.6) 的主体范围，同时直接吸收 2.x / 3.x 已验证的基础设计经验，避免重走早期版本的数据、保存与胶囊状态弯路。

## 当前状态

- HarmonyOS Stage 模型
- HarmonyOS SDK `6.1.0 / API 23`
- 当前正式目标设备：`2in1`（HarmonyOS PC）
- GitHub Actions 已真实通过 `assembleHap` 与 `assembleApp`
- 普通代码 PR 同时验证 debug HAP 编译与 release APP 打包
- 可生成 unsigned `.hap`、release `.app`、`SHA256SUMS` 和完整 ZIP
- HarmonyOS PC / 2in1 的实际窗口行为仍需要真机或云真机验证

## 已实现能力

### 纸片与数据

- Todo / Note 两类纸片
- 多纸片，每张纸独立 `PaperAbility` 窗口
- 同一 `paperId` 复用同一个 `specified` UIAbility 实例
- `schemaVersion` 数据版本，为后续迁移保留正式入口
- 正确区分首次启动与合法的“0 张纸片”状态
- 主数据和备份都损坏时进入数据保护模式，拒绝用默认纸片覆盖原存储
- 旧 v1 `x / y / width / height` 自动迁移到新版几何模型
- 最多 100 张纸片

### 保存策略

编辑不再每个字符同步写 Preferences：

- UI 修改立即进入内存状态
- 空闲约 1 秒后保存
- 持续输入最长约 10 秒强制保存一次
- 保存失败约 10 秒后自动重试
- Ability 进入后台或销毁前强制 flush
- backup 始终保留“上一份成功落盘状态”
- 控制中心支持手动恢复上一份有效备份

### Todo 纸

- 完成 / 恢复
- 行内编辑
- Enter 在当前项后新增
- 删除
- 清除已完成
- List 拖动排序
- 底部快速添加
- 多行文本拆分为多项
- 自动清理常见列表、数字序号、Markdown checkbox 和 `☐ / ☑ / ✓` 前缀
- 单次多行添加最多 200 条
- 单项长度保护
- 待办视觉大小：小 / 中 / 大 / 特大
- 可选“已完成自动置底”；取消完成时回到未完成区域末尾

### Note 纸

- 编辑 / 浏览双模式
- 自动保存
- Markdown 三档：不启用 / 启用 / 增强
- 轻量渲染标题、列表、引用、代码块、分割线
- 增强模式清理常见 Markdown inline 标记
- 工具栏：粗体、斜体、删除线、标题、引用、列表、代码块、链接
- 笔记总长度保护，避免无界内容直接压入 UI 与 Preferences

### 窗口

- 无系统标题栏
- 拖动移动
- 自定义缩放手柄
- 最小尺寸限制
- 单纸片 Topmost
- 隐藏 / 删除
- 从任意纸片新建 Todo / Note，新纸片默认靠近来源纸片
- 启动时恢复所有可见纸片
- 启动恢复时会把展开纸片夹回当前显示范围，降低窗口丢到屏幕外的风险
- 控制中心在 2in1 上启动纸片后使用普通窗口最小化；再次启动应用可恢复控制中心
- 窄纸片按宽度自动隐藏低优先级顶栏按钮，并通过 `⋯` 操作条保留完整入口
- 标题最多 20 个字符
- 展开纸片几何持久化统一使用逻辑 `vp`，仅在 Window API 边界转换为物理 `px`
- 监听 `windowRectChange`，系统自由窗调整后回写真实展开几何

### 胶囊

展开纸片和胶囊不再共用一套 `x / y`：

- 展开态保存 `expandedX / expandedY / expandedWidth / expandedHeight`（逻辑 `vp`）
- 普通悬浮胶囊保存独立 `capsuleX / capsuleY`（逻辑 `vp`）
- 贴边状态保存 `edgeOrder / edgeSide / edgeDisplayId`，实际贴边 X / Y 从屏幕与队列派生
- 拖动胶囊不会覆盖纸片展开位置
- 108 × 46 vp 胶囊尺寸，调用 Window API 时按 `densityPixels` 转换为 px
- `PaperAbility` 向窗口管理器声明 `minWindowWidth: 108` / `minWindowHeight: 46`
- 折叠 / 展开
- 自动排列在屏幕右上区域
- 右侧半隐藏
- Hover 单轴滑出 / 收回
- 动画窗口移动采用单飞 + 合并，只保留最新坐标，避免异步调用积压
- 点击恢复纸片
- 普通悬浮胶囊可独立保存位置
- 贴边胶囊纵向拖动按队列顺序重排
- 全局胶囊开关
- 自动贴边开关
- 关闭胶囊模式时，已打开胶囊会实时恢复为原展开几何
- 关闭自动贴边时保留普通胶囊形态和位置
- 胶囊间距支持 `0 / 4 / 8`

### 全局设置

HarmonyOS 没有 Windows 传统托盘，因此当前使用轻量“纸片控制中心”承担全局入口：

- 新建 Todo / Note
- 显示 / 隐藏单张纸片
- 显示全部 / 隐藏全部
- 删除纸片
- System / Light / Dark 主题
- Markdown 三档模式
- 胶囊开关
- 自动贴边开关
- 待办视觉大小
- 已完成自动置底
- 胶囊间距
- 自动备份恢复

## 从 Windows 2.x / 3.x 提前下放的经验

当前不是照着旧版本逐版移植，而是直接采用成熟后的基础规则：

- 不再把 `papers.length === 0` 当成首次启动
- 不再每个字符同步写盘
- 展开态与胶囊态几何分离
- 隐藏、胶囊、贴边状态各自保留语义
- 新建纸片使用来源位置，而不是永远固定左上角
- 窄窗口顶栏按优先级收缩，不继续横向堆按钮
- 对纸片数量、标题、Todo 粘贴和 Note 内容设置安全上限
- 普通 PR 必须同时通过 Build 与 Package

暂时不下放多屏左右边缘多队列、主胶囊、Windows 全屏避让、图片、文件快启和脚本胶囊。这些要么复杂度较高，要么高度依赖 HarmonyOS PC 实际窗口管理行为。

## 与 Windows 版的平台差异

当前目标是功能等级和成熟行为对齐，而不是逐 API / 逐像素复制 Windows WPF 实现。

尚未等价实现：

- Windows 托盘：改用 HarmonyOS 纸片控制中心
- Windows 开机启动 / CLI 参数：属于平台专属能力，尚未接入 HarmonyOS 等价机制
- Todo `Ctrl+Z / Ctrl+Y`
- 空白 Todo 的 Backspace 快捷删除
- Todo 拖到专用删除区
- zh / en / ja / ko 完整本地化
- 复杂 Markdown inline 样式的 1:1 渲染
- phone / tablet 形态：移动端后续应单独设计，不直接复用桌面自由窗 / 边缘胶囊模型

尤其需要注意：`WINDOW_TOPMOST`、无边框、自由窗口尺寸、极小胶囊窗口、贴边与 Hover 的代码路径已经通过 API 23 云端真实编译，但这些是窗口管理器的运行时行为，必须在 HarmonyOS PC / 2in1 真机或可用云真机上最终验收。

## 构建

### GitHub Actions

仓库包含两条流水线，普通 PR 两条都会执行：

- **HarmonyOS Build**：以 debug 模式执行 `assembleHap`
- **HarmonyOS Package**：PR 默认以 release 模式执行 `assembleApp`，收集 `.app` / unsigned `.hap` 并生成校验文件与 ZIP

工具链固定为 HarmonyOS `6.1.0.816`，下载包带 SHA-256 校验并使用 GitHub Actions Cache。

当前 CI 不保存发布证书、发布 Profile 或私钥，因此 release APP 仍为 **unsigned**。AGC 云调试要求 release 应用包并会校验发布 Profile / 证书；可先使用 CI 产出的 release `.app`，再通过开发者自己的发布签名或 DevEco Studio 支持的发布重签名能力生成可上传包。

### DevEco Studio

使用支持 HarmonyOS SDK `6.1.0(23)` 的 DevEco Studio 打开仓库根目录，完成 SDK / ohpm 同步后即可构建。

仓库不会提交签名证书或私钥。安装真机、AGC 云调试或提交 AppGallery Connect 时，需要使用开发者自己的签名身份。

## 工程结构

```text
PaperTodo-HarmonyOS/
├─ AppScope/
├─ entry/
│  └─ src/main/
│     ├─ ets/
│     │  ├─ abilitystage/
│     │  │  └─ PaperTodoAbilityStage.ets
│     │  ├─ entryability/
│     │  │  └─ EntryAbility.ets
│     │  ├─ paperability/
│     │  │  └─ PaperAbility.ets
│     │  ├─ common/
│     │  │  ├─ Models.ets
│     │  │  ├─ PaperStore.ets
│     │  │  ├─ WindowGeometry.ets
│     │  │  ├─ CapsuleGeometry.ets
│     │  │  ├─ CapsuleMotion.ets
│     │  │  └─ MarkdownLite.ets
│     │  └─ pages/
│     │     ├─ Index.ets
│     │     └─ Paper.ets
│     └─ resources/
├─ .github/workflows/
│  ├─ harmonyos-build.yml
│  └─ harmonyos-package.yml
├─ build-profile.json5
├─ hvigorfile.ts
└─ oh-package.json5
```

## 下一步

优先顺序：

1. 用发布签名后的 release APP 在 HarmonyOS PC / 2in1 云调试或真机验证多窗口、Topmost、最小窗口尺寸与焦点行为
2. 按真机结果校准胶囊贴边几何和 Hover 动画
3. 补 Todo 键盘操作与撤销 / 重做
4. 补完整本地化
5. 固化可安装 Release 签名流水线
