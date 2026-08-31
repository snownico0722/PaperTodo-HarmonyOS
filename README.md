# PaperTodo HarmonyOS

PaperTodo 的 HarmonyOS 原生版本。当前阶段先建立可编译、可继续扩展的基础纸片结构，目标设备包含 HarmonyOS PC / 2in1。

## 当前实现

- HarmonyOS Stage 模型工程
- ArkTS + ArkUI
- HarmonyOS SDK 6.1.0 / API 23
- `phone` / `tablet` / `2in1` 工程目标，便于预览和后续 PC 适配
- 一个基础 PaperTodo 纸片页面
- 待办完成 / 恢复
- 添加待办
- 无网络、无后台权限、无数据写入

当前待办仅保存在页面内存中，关闭应用后会恢复默认示例数据。持久化、多纸片、多窗口、置顶和边缘胶囊会在后续阶段接入。

## 开发环境

使用支持 HarmonyOS SDK `6.1.0(23)` 的 DevEco Studio 打开仓库根目录。

首次打开后让 DevEco Studio 完成 SDK 和 ohpm 同步，然后执行 **Build > Make Project**。

仓库故意不提交任何签名证书。`hvigor/hvigor-config.json5` 中关闭了签名任务，因此源码可以在没有开发者证书的情况下完成构建检查。若要安装到模拟器或真机，请在 DevEco Studio 中配置自动签名，并重新启用签名任务。

## 工程结构

```text
PaperTodo-HarmonyOS/
├─ AppScope/
├─ entry/
│  ├─ src/main/ets/
│  │  ├─ entryability/EntryAbility.ets
│  │  └─ pages/Index.ets
│  └─ src/main/resources/
├─ hvigor/
├─ build-profile.json5
├─ hvigorfile.ts
└─ oh-package.json5
```

## 下一阶段

1. PaperTodo 纸片数据模型与本地持久化
2. 多纸片 / 多窗口
3. 无边框窗口与窗口尺寸约束探针
4. `WINDOW_TOPMOST` 与后台显示探针
5. 贴边、Hover 展开与边缘胶囊 FSM
