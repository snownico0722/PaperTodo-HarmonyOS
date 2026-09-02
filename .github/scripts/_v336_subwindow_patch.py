from pathlib import Path


def replace_between(text: str, start_marker: str, end_marker: str, replacement: str) -> str:
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    return text[:start] + replacement + text[end:]


ability_path = Path('entry/src/main/ets/mastercapsuleability/MasterCapsuleAbility.ets')
text = ability_path.read_text()
text = text.replace('  CAPSULE_PLATFORM_MIN_WIDTH,\n', '')
text = text.replace(
    'const INITIAL_INTERACTION_RESTORE_DELAY_MS: number = 16;\n',
    "const INITIAL_INTERACTION_RESTORE_DELAY_MS: number = 16;\nconst CAPSULE_SUBWINDOW_NAME: string = 'PaperTodoCapsuleSubWindow';\n"
)
text = text.replace(
    '  private mainWindow: window.Window | null = null;\n',
    '  private hostWindow: window.Window | null = null;\n  private mainWindow: window.Window | null = null;\n',
    1
)

text = replace_between(
    text,
    '  onWindowStageCreate(windowStage: window.WindowStage): void {',
    '\n  onForeground(): void {',
    '''  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    if (this.closeRequested || !this.isEligible()) {
      this.clearHostRegistration();
      this.terminateAbility();
      return;
    }

    try {
      this.hostWindow = windowStage.getMainWindowSync();
    } catch (error) {
      console.error('get capsule ability host window failed: ' + String(error));
      this.terminateAbility();
      return;
    }
    AppStorage.setOrCreate<number>('capsuleAreaRevision',
      AppStorage.get<number>('capsuleAreaRevision') ?? 0);
    this.registerAvailableAreaListener();

    windowStage.loadContent('pages/Host', (error: BusinessError): void => {
      if (error.code !== 0) {
        console.error('load capsule ability host page failed: ' + error.message);
        this.terminateAbility();
        return;
      }
      this.configureHiddenHostWindow().then((): Promise<void> => {
        return this.createCapsuleSubWindow(windowStage);
      }).catch((reason: Error): void => {
        console.error('create capsule subwindow failed: ' + reason.message);
        this.terminateAbility();
      });
    });
  }
'''
)

text = replace_between(
    text,
    '  onForeground(): void {',
    '\n  onConfigurationUpdate(config: Configuration): void {',
    '''  onForeground(): void {
    this.configureHiddenHostWindow().catch((error: Error): void => {
      console.warn('re-hide capsule ability host failed: ' + error.message);
    });
    this.showAndRestyle();
    this.notifyAvailableAreaChanged();
  }
'''
)

text = replace_between(
    text,
    '  onDestroy(): void {',
    '\n  async onPrepareToTerminateAsync(): Promise<boolean> {',
    '''  onDestroy(): void {
    PaperStore.flushNow();
    this.unregisterCloseEvents();
    this.unregisterAvailableAreaListener();
    const capsuleWindow: window.Window | null = this.mainWindow;
    this.mainWindow = null;
    if (capsuleWindow !== null) {
      try {
        capsuleWindow.destroyWindow();
      } catch (error) {
        console.warn('destroy capsule subwindow failed: ' + String(error));
      }
    }
    this.hostWindow = null;
    this.windowStage = null;
    if (AppStorage.get<string>('masterCapsuleToken') === this.instanceToken) {
      this.clearHostRegistration();
    }
  }
'''
)

text = replace_between(
    text,
    '  private async prepareInitialWindowAndLoadContent(windowStage: window.WindowStage): Promise<void> {',
    '\n  private async prepareInitialGeometry(): Promise<void> {',
    '''  private async configureHiddenHostWindow(): Promise<void> {
    const win: window.Window | null = this.hostWindow;
    if (win === null) {
      return;
    }
    try {
      win.setWindowDecorVisible(false);
    } catch (error) {
      console.warn('hide capsule ability host decor failed: ' + String(error));
    }
    try {
      win.setWindowTitleButtonVisible(false, false, false);
      win.setWindowTitleMoveEnabled(false);
    } catch (error) {
      console.warn('hide capsule ability host title controls failed: ' + String(error));
    }
    try {
      win.setWindowBackgroundColor('#00000000');
      win.setWindowContainerColor('#00000000', '#00000000');
    } catch (error) {
      console.warn('clear capsule ability host surface failed: ' + String(error));
    }
    try {
      await win.setWindowShadowEnabled(false);
    } catch (error) {
      console.warn('disable capsule ability host shadow failed: ' + String(error));
    }
    try {
      await win.setWindowTouchable(false);
      await win.setWindowFocusable(false);
    } catch (error) {
      console.warn('disable capsule ability host interaction failed: ' + String(error));
    }
    try {
      await win.setWindowTopmost(true);
    } catch (error) {
      console.warn('set capsule ability host topmost failed: ' + String(error));
    }

    const screen: display.Display = display.getDefaultDisplaySync();
    try {
      await win.resizeAsync(1, 1);
    } catch (error) {
      try {
        await win.resize(1, 1);
      } catch (resizeError) {
        console.warn('shrink capsule ability host failed: ' + String(resizeError));
      }
    }
    let hostWidth: number = 64;
    let hostHeight: number = 64;
    try {
      const rect = win.getWindowProperties().windowRect;
      hostWidth = Math.max(1, rect.width);
      hostHeight = Math.max(1, rect.height);
    } catch (error) {
      console.warn('query capsule ability host rect failed: ' + String(error));
    }
    const offscreenX: number = screen.width + hostWidth + 64;
    const offscreenY: number = screen.height + hostHeight + 64;
    try {
      await win.moveWindowToAsync(offscreenX, offscreenY);
    } catch (error) {
      try {
        await win.moveWindowTo(offscreenX, offscreenY);
      } catch (moveError) {
        console.warn('move capsule ability host offscreen failed: ' + String(moveError));
      }
    }
  }

  private async createCapsuleSubWindow(windowStage: window.WindowStage): Promise<void> {
    const subWindow: window.Window = await windowStage.createSubWindow(CAPSULE_SUBWINDOW_NAME);
    if (this.windowStage !== windowStage || this.closeRequested || !this.isEligible()) {
      try {
        subWindow.destroyWindow();
      } catch (_error) {
      }
      return;
    }

    this.mainWindow = subWindow;
    try {
      await subWindow.setFollowParentWindowLayoutEnabled(false);
    } catch (error) {
      console.warn('disable capsule subwindow parent-layout following failed: ' + String(error));
    }
    AppStorage.setOrCreate<window.Window>('masterCapsuleWindow', subWindow);
    AppStorage.setOrCreate<string>('masterCapsuleToken', this.instanceToken);
    AppStorage.setOrCreate<boolean>('masterCapsuleOpen', true);
    this.applyWindowStyle();
    this.registerCloseEvents(windowStage);
    await this.setInitialWindowInteraction(false);
    await this.prepareInitialGeometry();

    await new Promise<void>((resolve: () => void, reject: (reason: Error) => void): void => {
      subWindow.setUIContent('pages/MasterCapsule', (error: BusinessError): void => {
        if (error.code !== 0) {
          reject(new Error('load capsule subwindow content failed: ' + error.message));
          return;
        }
        resolve();
      });
    });
    if (this.mainWindow !== subWindow || this.closeRequested) {
      return;
    }
    this.applyWindowStyle();
    this.applyTransparentSurfaceStyle();
    this.notifyAvailableAreaChanged();
    await subWindow.showWindow();
    setTimeout((): void => {
      this.restoreInitialWindowInteraction().catch((restoreError: Error): void => {
        console.warn('restore capsule subwindow interaction failed: ' + restoreError.message);
      });
    }, INITIAL_INTERACTION_RESTORE_DELAY_MS);
  }
'''
)

text = replace_between(
    text,
    '  private async prepareInitialGeometry(): Promise<void> {',
    '\n  private hostWidthVp(',
    '''  private async prepareInitialGeometry(): Promise<void> {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    const uiContext: UIContext = win.getUIContext();
    const targetDisplay: display.Display = this.activeDisplay ?? display.getDefaultDisplaySync();
    const area: display.Rect = await this.getAvailableArea(targetDisplay);
    const state: AppState = PaperStore.loadState();
    const members: PaperData[] = PaperStore.listEdgeCapsulePapers();
    if (members.length === 0) {
      return;
    }
    const includeMaster: boolean = state.useMasterCapsule;
    const queueRetracted: boolean = includeMaster && state.capsuleCollapseAllActive;
    const areaHeightVp: number = uiContext.px2vp(area.height);
    const startTop: number = normalizeCapsuleStartTopMargin(state.capsuleStartTop, areaHeightVp,
      members.length, state.capsuleGap, includeMaster);
    const widthVp: number = this.hostWidthVp(members, includeMaster, queueRetracted);
    const visibleMemberCount: number = queueRetracted ? 0 : members.length;
    const slotCount: number = visibleMemberCount + (includeMaster ? 1 : 0);
    const heightVp: number = Math.max(CAPSULE_HEIGHT,
      slotCount * CAPSULE_HEIGHT + Math.max(0, slotCount - 1) * state.capsuleGap);
    const requestedWidthPx: number = Math.round(uiContext.vp2px(widthVp));
    const requestedHeightPx: number = Math.round(uiContext.vp2px(heightVp));

    try {
      await win.resizeAsync(requestedWidthPx, requestedHeightPx);
    } catch (error) {
      console.warn('initial async capsule subwindow resize failed, falling back: ' + String(error));
      await win.resize(requestedWidthPx, requestedHeightPx);
    }

    let actualWidthPx: number = requestedWidthPx;
    try {
      const rect = win.getWindowProperties().windowRect;
      actualWidthPx = Math.max(1, rect.width);
    } catch (error) {
      console.warn('query initial capsule subwindow width failed: ' + String(error));
    }
    const xPx: number = Math.round(targetDisplay.width - actualWidthPx);
    const yPx: number = Math.round(area.top + uiContext.vp2px(startTop));
    try {
      await win.moveWindowToAsync(xPx, yPx);
    } catch (error) {
      console.warn('initial async capsule subwindow move failed, falling back: ' + String(error));
      await win.moveWindowTo(xPx, yPx);
    }
    try {
      await win.setWindowShadowEnabled(false);
    } catch (error) {
      console.warn('disable initial capsule subwindow shadow failed: ' + String(error));
    }
  }
'''
)

text = replace_between(
    text,
    '  private showAndRestyle(): void {',
    '\n  private applyTransparentSurfaceStyle(): void {',
    '''  private showAndRestyle(): void {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    win.showWindow()
      .then((): void => {
        this.applyWindowStyle();
        this.applyTransparentSurfaceStyle();
      })
      .catch((error: BusinessError): void => {
        console.error('show capsule subwindow failed: ' + error.message);
      });
  }
'''
)

text = replace_between(
    text,
    '  private terminateAbility(): void {',
    '\n  private readCommand(want: Want): string {',
    '''  private terminateAbility(): void {
    this.closeRequested = true;
    this.unregisterCloseEvents();
    const capsuleWindow: window.Window | null = this.mainWindow;
    this.mainWindow = null;
    this.clearHostRegistration();
    if (capsuleWindow !== null) {
      try {
        capsuleWindow.destroyWindow();
      } catch (error) {
        console.warn('destroy capsule subwindow during terminate failed: ' + String(error));
      }
    }
    this.context.terminateSelf().catch((error: BusinessError): void => {
      console.warn('terminate capsule host failed: ' + error.message);
    });
  }
'''
)
ability_path.write_text(text)


page_path = Path('entry/src/main/ets/pages/MasterCapsule.ets')
text = page_path.read_text()
text = text.replace('  CAPSULE_PLATFORM_MIN_WIDTH,\n', '')
start = text.index('    const widthPx: number = Math.round(uiContext.vp2px(widthVp));')
end = text.index('\n  private measureMasterRowWidth', start)
replacement = '''    const requestedWidthPx: number = Math.round(uiContext.vp2px(widthVp));
    const requestedHeightPx: number = Math.round(uiContext.vp2px(heightVp));
    const desiredSignature: string = [normalizedTop, requestedWidthPx, requestedHeightPx].join(':');
    const geometryChanged: boolean = desiredSignature !== this.lastGeometrySignature;
    if (geometryChanged) {
      try {
        await win.resizeAsync(requestedWidthPx, requestedHeightPx);
      } catch (error) {
        console.warn('async capsule subwindow resize failed, falling back: ' + String(error));
        await win.resize(requestedWidthPx, requestedHeightPx);
      }
      this.lastGeometrySignature = desiredSignature;
    }

    let actualWidthPx: number = requestedWidthPx;
    let actualHeightPx: number = requestedHeightPx;
    try {
      const rect = win.getWindowProperties().windowRect;
      actualWidthPx = Math.max(1, rect.width);
      actualHeightPx = Math.max(1, rect.height);
    } catch (error) {
      console.warn('query capsule subwindow actual geometry failed: ' + String(error));
    }
    const xPx: number = Math.round(targetDisplay.width - actualWidthPx);
    const yPx: number = Math.round(area.top + uiContext.vp2px(normalizedTop));
    try {
      await win.moveWindowToAsync(xPx, yPx);
    } catch (error) {
      console.warn('async capsule subwindow edge move failed, falling back: ' + String(error));
      await win.moveWindowTo(xPx, yPx);
    }
    await this.syncNativeWindowMask(win, uiContext, actualWidthPx, actualHeightPx,
      state, includeMaster, queueRetracted);
  }
'''
text = text[:start] + replacement + text[end:]
page_path.write_text(text)


app_path = Path('AppScope/app.json5')
text = app_path.read_text()
text = text.replace('"versionCode": 3030500', '"versionCode": 3030600')
text = text.replace('"versionName": "3.3.5"', '"versionName": "3.3.6"')
app_path.write_text(text)


changelog_path = Path('CHANGELOG.md')
text = changelog_path.read_text()
entry = '''## 3.3.6 — 2026-09-03

第六轮 HarmonyOS PC / 2in1 真机回归修复，3.3.5 已证明 `setWindowMask()` 直接作用于多 UIAbility 的主窗口无法移除系统 floating 主窗外壳，本版按华为官方异形窗口实现改为真实应用子窗口。

- `MasterCapsuleAbility` 的 UIAbility 主窗口不再承载可见胶囊；主窗口仅作为 2in1 子窗口的生命周期宿主，关闭装饰、禁用交互并移动到物理屏幕外。
- 通过 `WindowStage.createSubWindow()` 创建 `PaperTodoCapsuleSubWindow`，使用 `setUIContent('pages/MasterCapsule')` 加载胶囊 UI；`Window.setWindowMask()` 现在作用于官方异形窗口实践明确支持的应用子窗口，而不是普通 UIAbility 主窗口。
- 子窗口显式关闭 `setFollowParentWindowLayoutEnabled`，独立维护位置和大小；父主窗保持 `WINDOW_TOPMOST`，子窗口随应用层级保持桌面可达。
- 每次调整胶囊尺寸后读取 `getWindowProperties().windowRect.width/height` 的实际像素尺寸，再以 `display.width - actualWidth` 重新计算 X；即使系统修正请求尺寸，右边缘仍精确落在物理屏幕边缘。
- Window Mask 同样按子窗口实际像素尺寸生成，避免请求尺寸与最终窗口尺寸不一致导致掩码失效。
- 版本更新为 `3.3.6`（`versionCode: 3030600`，`buildVersion: 1`）。

'''
text = text.replace('# Changelog\n\n', '# Changelog\n\n' + entry, 1)
changelog_path.write_text(text)
