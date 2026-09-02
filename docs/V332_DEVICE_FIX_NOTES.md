# HarmonyOS PC v3.3.2 真机回归定位

本轮不沿用 3.3.1 的窗口纠偏假设。

- HarmonyOS 窗口文档说明 `moveWindowTo()` 本身没有位置边界限制；3.3.1 将抖动归因为系统纠正越界窗口不成立。
- PC 窗口实践说明普通 `resize()` / `moveWindowTo()` 调用成功并不表示最终几何已经同步生效；连续依赖最终几何时应使用 async 版本。本轮胶囊宿主因此使用 `resizeAsync()` / `moveWindowToAsync()` 并缓存目标矩形。
- `excludeFromDock` 当前配置文档注明不生效，三方应用也不能依赖 `excludeFromMissions` 隐藏 mission。因此不再为每个侧边胶囊创建一个独立 `specified UIAbility`。
- ArkUI 拖拽示例使用普通组件 `.draggable(true)` + `.onDragStart()`，并可用 `dragPreview()` 提供预览。本轮纸片关联柄改为自定义 `Stack` 拖拽源，UDMF 数据协议保持不变。
- PC 上现有 mission 被重新带到前台会进入前台生命周期，不能只依赖 `onNewWant()`。隐藏的 EntryAbility 在完成冷启动后同时从 `onNewWant()` 和 `onForeground()` 进入设置激活路径。

这个文件只记录平台定位依据，不改变产品范围。仍然是单显示器、右侧单队列；不恢复左右换边、跨屏、多队列和队列内拖拽排序。
