from pathlib import Path

path = Path('entry/src/main/ets/mastercapsuleability/MasterCapsuleAbility.ets')
text = path.read_text()

old_topmost = '''    try {\n      await win.setWindowTopmost(true);\n    } catch (error) {\n      console.warn('set capsule ability host topmost failed: ' + String(error));\n    }\n\n'''
if text.count(old_topmost) != 1:
    raise SystemExit('host topmost block not found exactly once')
text = text.replace(old_topmost, '', 1)

old_position = '''    let hostWidth: number = 64;\n    let hostHeight: number = 64;\n    try {\n      const rect = win.getWindowProperties().windowRect;\n      hostWidth = Math.max(1, rect.width);\n      hostHeight = Math.max(1, rect.height);\n    } catch (error) {\n      console.warn('query capsule ability host rect failed: ' + String(error));\n    }\n    const offscreenX: number = screen.width + hostWidth + 64;\n    const offscreenY: number = screen.height + hostHeight + 64;\n    try {\n      await win.moveWindowToAsync(offscreenX, offscreenY);\n    } catch (error) {\n      try {\n        await win.moveWindowTo(offscreenX, offscreenY);\n      } catch (moveError) {\n        console.warn('move capsule ability host offscreen failed: ' + String(moveError));\n      }\n    }\n'''
new_position = '''    // API 23 application subwindows still belong to the parent WindowStage.\n    // Keep exactly one physical pixel of the parent window on-screen instead of\n    // moving the entire parent outside the display; API 26 independent subwindows\n    // are not available to this build yet. The parent remains non-touchable,\n    // non-focusable, transparent, and sits in the bottom-right corner.\n    const edgeX: number = Math.max(0, screen.width - 1);\n    const edgeY: number = Math.max(0, screen.height - 1);\n    try {\n      await win.moveWindowToAsync(edgeX, edgeY);\n    } catch (error) {\n      try {\n        await win.moveWindowTo(edgeX, edgeY);\n      } catch (moveError) {\n        console.warn('anchor capsule ability host at display edge failed: ' + String(moveError));\n      }\n    }\n    try {\n      await win.showWindow();\n    } catch (error) {\n      console.warn('ensure capsule ability host visible failed: ' + String(error));\n    }\n'''
if text.count(old_position) != 1:
    raise SystemExit('host offscreen block not found exactly once')
text = text.replace(old_position, new_position, 1)

old_context = '''    const win: window.Window | null = this.mainWindow;\n    if (win === null) {\n      return;\n    }\n    const uiContext: UIContext = win.getUIContext();\n    const targetDisplay: display.Display = this.activeDisplay ?? display.getDefaultDisplaySync();\n'''
new_context = '''    const win: window.Window | null = this.mainWindow;\n    const contextWindow: window.Window | null = this.hostWindow;\n    if (win === null || contextWindow === null) {\n      return;\n    }\n    // A newly created subwindow does not have page content yet at this point.\n    // Huawei's official irregular-window flow sizes/moves the subwindow before\n    // setUIContent(), so use the already-loaded parent UIContext for vp/px\n    // conversion. After setUIContent succeeds, MasterCapsule uses the subwindow's\n    // own UIContext for all subsequent geometry/mask updates.\n    const uiContext: UIContext = contextWindow.getUIContext();\n    const targetDisplay: display.Display = this.activeDisplay ?? display.getDefaultDisplaySync();\n'''
if text.count(old_context) != 1:
    raise SystemExit('prepareInitialGeometry UIContext block not found exactly once')
text = text.replace(old_context, new_context, 1)

path.write_text(text)

app = Path('AppScope/app.json5')
app_text = app.read_text()
if '"versionCode": 3030600' not in app_text or '"versionName": "3.3.6"' not in app_text:
    raise SystemExit('unexpected app version before v3.3.7 patch')
app_text = app_text.replace('"versionCode": 3030600', '"versionCode": 3030700', 1)
app_text = app_text.replace('"versionName": "3.3.6"', '"versionName": "3.3.7"', 1)
app.write_text(app_text)

changelog = Path('CHANGELOG.md')
change_text = changelog.read_text()
entry = '''## 3.3.7 — 2026-09-03\n\n第七轮 HarmonyOS PC / 2in1 真机回归修复，修复 3.3.6 将胶囊迁移到应用子窗口后完全不可见的问题。\n\n- 修复在子窗口 `setUIContent()` 之前调用其 `getUIContext()` 的初始化顺序错误；初始 vp/px 换算改用已加载完成的父窗口 UIContext，严格保持 `createSubWindow → move/resize → setUIContent → setWindowMask → showWindow` 的官方异形窗口顺序。\n- API 23 普通应用子窗口仍绑定父 WindowStage；父窗口不再整体移动到物理屏幕外，而是保持不可交互、不可聚焦、透明，并仅在屏幕右下角保留 1 个物理像素，避免子窗口因 parent 完全离屏而失去可见性。\n- 可见胶囊仍由 `PaperTodoCapsuleSubWindow` 承载，Window Mask、实际最终 `windowRect` 贴右定位和 3.3.5 设置任务栏修复均保留。\n- 版本更新为 `3.3.7`（`versionCode: 3030700`，`buildVersion: 1`）。\n\n'''
marker = '# Changelog\n\n'
if marker not in change_text:
    raise SystemExit('changelog header missing')
change_text = change_text.replace(marker, marker + entry, 1)
changelog.write_text(change_text)
