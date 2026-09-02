from pathlib import Path

# 1) Settings close must keep the launcher/taskbar mission alive.
index_path = Path('entry/src/main/ets/pages/Index.ets')
index_text = index_path.read_text()
old_close = '''  private closeSettings(): void {
    PaperStore.flushNow();
    this.hostContext().terminateSelf().catch((error: BusinessError): void => {
      console.error('close settings failed: ' + error.message);
    });
  }
'''
new_close = '''  private closeSettings(): void {
    PaperStore.flushNow();
    const win: window.Window | null = this.settingsWindow;
    if (win === null) {
      console.warn('minimize settings skipped: settings window is unavailable');
      return;
    }
    win.minimize().catch((error: BusinessError): void => {
      console.error('minimize settings failed: ' + error.message);
    });
  }
'''
if index_text.count(old_close) != 1:
    raise SystemExit(f'Index closeSettings marker mismatch: {index_text.count(old_close)}')
index_path.write_text(index_text.replace(old_close, new_close, 1))

# 2) Initial capsule host X must use the physical display edge, not work-area right.
ability_path = Path('entry/src/main/ets/mastercapsuleability/MasterCapsuleAbility.ets')
ability_text = ability_path.read_text()
old_x = '    const xPx: number = Math.round(area.left + area.width - widthPx);'
new_x = '    const xPx: number = Math.round(targetDisplay.width - widthPx);'
if ability_text.count(old_x) != 1:
    raise SystemExit(f'MasterCapsuleAbility X marker mismatch: {ability_text.count(old_x)}')
ability_path.write_text(ability_text.replace(old_x, new_x, 1))

# 3) Runtime capsule geometry and native shape mask.
page_path = Path('entry/src/main/ets/pages/MasterCapsule.ets')
page_text = page_path.read_text()
import_marker = "import { PaperStore } from '../common/PaperStore';\n"
import_line = "import { CapsuleWindowMaskRow, applyCapsuleWindowMask } from '../common/CapsuleWindowMask';\n"
if page_text.count(import_marker) != 1:
    raise SystemExit('MasterCapsule import marker mismatch')
page_text = page_text.replace(import_marker, import_marker + import_line, 1)

hover_old = "  @State hoveredPaperId: string = '';"
hover_new = "  @State @Watch('onLayoutChanged') hoveredPaperId: string = '';"
if page_text.count(hover_old) != 1:
    raise SystemExit('MasterCapsule hover marker mismatch')
page_text = page_text.replace(hover_old, hover_new, 1)

runtime_x_old = '    const xPx: number = Math.round(area.left + area.width - widthPx);'
runtime_x_new = '    const xPx: number = Math.round(targetDisplay.width - widthPx);'
if page_text.count(runtime_x_old) != 1:
    raise SystemExit(f'MasterCapsule runtime X marker mismatch: {page_text.count(runtime_x_old)}')
page_text = page_text.replace(runtime_x_old, runtime_x_new, 1)

old_geometry = '''    const signature: string = [xPx, yPx, widthPx, heightPx].join(':');
    if (signature === this.lastGeometrySignature) {
      return;
    }

    try {
      await win.setWindowLimits({
        minWidth: Math.round(uiContext.vp2px(CAPSULE_PLATFORM_MIN_WIDTH)),
        minHeight: Math.round(uiContext.vp2px(CAPSULE_HEIGHT)),
        maxWidth: Math.max(widthPx, area.width),
        maxHeight: Math.max(heightPx, area.height)
      }, true);
    } catch (error) {
      console.warn('set capsule host limits failed: ' + String(error));
    }
    try {
      await win.resizeAsync(widthPx, heightPx);
      await win.moveWindowToAsync(xPx, yPx);
    } catch (error) {
      console.warn('async capsule host geometry failed, falling back: ' + String(error));
      await win.resize(widthPx, heightPx);
      await win.moveWindowTo(xPx, yPx);
    }
    this.lastGeometrySignature = signature;
'''
new_geometry = '''    const signature: string = [xPx, yPx, widthPx, heightPx].join(':');
    const geometryChanged: boolean = signature !== this.lastGeometrySignature;
    if (geometryChanged) {
      try {
        await win.setWindowLimits({
          minWidth: Math.round(uiContext.vp2px(CAPSULE_PLATFORM_MIN_WIDTH)),
          minHeight: Math.round(uiContext.vp2px(CAPSULE_HEIGHT)),
          maxWidth: Math.max(widthPx, targetDisplay.width),
          maxHeight: Math.max(heightPx, area.height)
        }, true);
      } catch (error) {
        console.warn('set capsule host limits failed: ' + String(error));
      }
      try {
        await win.resizeAsync(widthPx, heightPx);
        await win.moveWindowToAsync(xPx, yPx);
      } catch (error) {
        console.warn('async capsule host geometry failed, falling back: ' + String(error));
        await win.resize(widthPx, heightPx);
        await win.moveWindowTo(xPx, yPx);
      }
      this.lastGeometrySignature = signature;
    }
    await this.syncNativeWindowMask(win, uiContext, widthPx, heightPx, state, includeMaster, queueRetracted);
'''
if page_text.count(old_geometry) != 1:
    raise SystemExit(f'MasterCapsule geometry marker mismatch: {page_text.count(old_geometry)}')
page_text = page_text.replace(old_geometry, new_geometry, 1)

method_marker = '''  private capsuleWidth(paper: PaperData): number {
    return Math.max(CAPSULE_MIN_WIDTH, Math.min(CAPSULE_MAX_WIDTH, paper.capsuleWidth));
  }
'''
mask_method = '''

  private async syncNativeWindowMask(win: window.Window, uiContext: UIContext, widthPx: number, heightPx: number,
    state: AppState, includeMaster: boolean, queueRetracted: boolean): Promise<void> {
    const rows: CapsuleWindowMaskRow[] = [];
    const rowHeightVp: number = 30;
    const rowTopInsetVp: number = (CAPSULE_HEIGHT - rowHeightVp) / 2;
    const radiusVp: number = rowHeightVp / 2;
    let slotIndex: number = 0;

    if (includeMaster) {
      rows.push({
        topPx: uiContext.vp2px(rowTopInsetVp),
        heightPx: uiContext.vp2px(rowHeightVp),
        visibleWidthPx: uiContext.vp2px(this.masterRowWidthVp),
        radiusPx: uiContext.vp2px(radiusVp)
      });
      slotIndex++;
    }

    if (!queueRetracted) {
      for (let i: number = 0; i < this.members.length; i++) {
        const paper: PaperData = this.members[i];
        const visibleWidthVp: number = Math.max(1, this.capsuleWidth(paper) - this.capsuleOffsetX(paper));
        const topVp: number = slotIndex * (CAPSULE_HEIGHT + state.capsuleGap) + rowTopInsetVp;
        rows.push({
          topPx: uiContext.vp2px(topVp),
          heightPx: uiContext.vp2px(rowHeightVp),
          visibleWidthPx: uiContext.vp2px(visibleWidthVp),
          radiusPx: uiContext.vp2px(radiusVp)
        });
        slotIndex++;
      }
    }

    const applied: boolean = await applyCapsuleWindowMask(win, widthPx, heightPx, rows);
    if (!applied) {
      console.warn('capsule host is using rectangular transparency fallback');
    }
  }
'''
if page_text.count(method_marker) != 1:
    raise SystemExit('MasterCapsule capsuleWidth marker mismatch')
page_text = page_text.replace(method_marker, method_marker + mask_method, 1)
page_path.write_text(page_text)

# 4) Version bump for device-installable regression build.
app_path = Path('AppScope/app.json5')
app_text = app_path.read_text()
if app_text.count('"versionCode": 3030400') != 1 or app_text.count('"versionName": "3.3.4"') != 1:
    raise SystemExit('AppScope version marker mismatch')
app_text = app_text.replace('"versionCode": 3030400', '"versionCode": 3030500', 1)
app_text = app_text.replace('"versionName": "3.3.4"', '"versionName": "3.3.5"', 1)
app_path.write_text(app_text)

# 5) Changelog records only the two confirmed device root causes plus mask capability.
changelog_path = Path('CHANGELOG.md')
changelog = changelog_path.read_text()
header = '# Changelog\n\n'
entry = '''## 3.3.5 — 2026-09-02

第五轮 HarmonyOS PC / 2in1 真机回归修复，针对 3.3.4 仍可复现的任务栏设置入口和胶囊原生矩形壳。

- 设置窗口自定义关闭不再 `terminateSelf()`；改为最小化并保留 `ManagerAbility` / mission，让任务栏点击恢复同一个仍存活的设置窗口，避免 `removeMissionAfterTerminate: false` 留下死 mission。
- 胶囊宿主横坐标不再使用会扣除 Dock / 系统保留区的 `availableArea` 右边界，改为默认 2in1 物理显示宽度右边界，右侧胶囊真正贴屏幕边缘；纵向位置仍使用可用区域避让系统 UI。
- 按华为 2in1 异形窗口实践新增 `SystemCapability.Window.SessionManager` 和 `Window.setWindowMask()`：原生宿主窗口按主胶囊与普通胶囊实际可见像素生成联合掩码，矩形空白、队列间隙及收起后不可见区域由窗口系统真正裁掉，不再依赖背景色透明模拟异形窗口。
- 胶囊 Hover 导致关闭段伸出 / 收回时同步重算 Window Mask，即使宿主宽高未变化也更新原生窗口形状。
- 版本更新为 `3.3.5`（`versionCode: 3030500`，`buildVersion: 1`）。

'''
if not changelog.startswith(header):
    raise SystemExit('CHANGELOG header mismatch')
changelog_path.write_text(header + entry + changelog[len(header):])
