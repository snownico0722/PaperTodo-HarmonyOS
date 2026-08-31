# PaperTodo HarmonyOS

PaperTodo 的 HarmonyOS 原生版本，使用 ArkTS + ArkUI 重写。当前目标是先达到 Windows [PaperTodo v1.6](https://github.com/snownico0722/PaperTodo/releases/tag/v1.6) 的基础产品能力，再继续向后续版本演进。

## 当前状态

- HarmonyOS Stage 模型
- HarmonyOS SDK `6.1.0 / API 23`
- `phone` / `tablet` / `2in1` 工程目标
- GitHub Actions 已真实通过 `assembleHap` 与 `assembleApp`
- 可生成 unsigned `.hap`、`.app`、`SHA256SUMS` 和完整 ZIP
- HarmonyOS PC / 2in1 的实际窗口行为仍需要真机验证

## 已实现能力

### 纸片与数据

- Todo / Note 两类纸片
- 多纸片
- 每张纸独立 `PaperAbility` 窗口
- 同一 `paperId` 复用同一个 `specified` UIAbility 实例
- 保存并恢复纸片位置、尺寸、可见状态、置顶状态和胶囊状态
- HarmonyOS Preferences 自动持久化
- 每次保存前保留上一份自动备份
- 主状态损坏时尝试从备份恢复
- 控制中心支持手动恢复上一份备份

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

### Note 纸

- 编辑 / 浏览双模式
- 自动保存
- Markdown 三档：不启用 / 启用 / 增强
- 轻量渲染标题、列表、引用、代码块、分割线
- 增强模式清理常见 Markdown inline 标记
- 工具栏：粗体、斜体、删除线、标题、引用、列表、代码块、链接

### 窗口

- 无系统标题栏
- 拖动移动
- 自定义缩放手柄
- 最小尺寸限制
- 单纸片 Topmost
- 隐藏 / 删除
- 从任意纸片新建 Todo / Note
- 启动时恢复所有可见纸片
- 2in1 启动纸片后控制中心尝试自动退到后台

### 胶囊

- 108 × 46 胶囊尺寸
- 折叠 / 展开
- 自动排列在屏幕右上区域
- 右侧半隐藏
- Hover 滑出
- 点击恢复纸片
- 胶囊可拖动
- 全局胶囊开关
- 自动贴边开关

### 全局设置

HarmonyOS 没有 Windows 传统托盘，因此当前使用一个轻量的“纸片控制中心”承担全局入口：

- 新建 Todo / Note
- 显示 / 隐藏单张纸片
- 显示全部 / 隐藏全部
- 删除纸片
- System / Light / Dark 主题
- Markdown 三档模式
- 胶囊开关
- 自动贴边开关
- 自动备份恢复

## 与 Windows v1.6 的平台差异

当前目标是功能等级对齐，而不是逐 API / 逐像素复制 Windows WPF 实现。

尚未等价实现：

- Windows 托盘：改用 HarmonyOS 纸片控制中心
- Windows 开机启动 / CLI 参数：属于平台专属能力，尚未接入 HarmonyOS 等价机制
- Todo `Ctrl+Z / Ctrl+Y`
- 空白 Todo 的 Backspace 快捷删除
- Todo 拖到专用删除区
- zh / en / ja / ko 完整本地化
- 复杂 Markdown inline 样式的 1:1 渲染

尤其需要注意：`WINDOW_TOPMOST`、无边框、自由窗口尺寸、极小胶囊窗口、贴边与 Hover 的代码路径已经通过 API 23 云端真实编译，但这些是窗口管理器的运行时行为，必须在 HarmonyOS PC / 2in1 真机上最终验收。

## 构建

### GitHub Actions

仓库包含两条流水线：

- **HarmonyOS Build**：PR / main 执行 `assembleHap`
- **HarmonyOS Package**：执行 `assembleApp`，收集 `.app` / unsigned `.hap` 并生成校验文件与 ZIP

工具链固定为 HarmonyOS `6.1.0.816`，下载包带 SHA-256 校验并使用 GitHub Actions Cache。

### DevEco Studio

使用支持 HarmonyOS SDK `6.1.0(23)` 的 DevEco Studio 打开仓库根目录，完成 SDK / ohpm 同步后即可构建。

仓库不会提交签名证书或私钥。CI 当前产物为 **unsigned**；安装真机或提交 AppGallery Connect 时，需要配置开发者签名。

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

1. HarmonyOS PC / 2in1 真机验证多窗口、Topmost、最小窗口尺寸与焦点行为
2. 校准胶囊贴边几何和 Hover 动画
3. 补 Todo 键盘操作与撤销 / 重做
4. 补完整本地化
5. 配置签名与可安装 Release 打包
