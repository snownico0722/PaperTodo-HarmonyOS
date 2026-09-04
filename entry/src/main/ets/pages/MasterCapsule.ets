import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { CapsuleRuntime } from '../common/CapsuleRuntime';
import { CAPSULE_PAGER_WIDTH, capsuleViewport, capsuleViewportTop } from '../common/CapsuleViewport';
import { DesktopShell, PAPER_COMMAND_SHOW } from '../common/DesktopShell';
import {
  CAPSULE_CLOSE_WIDTH,
  CAPSULE_HEIGHT,
  CAPSULE_MAX_WIDTH,
  CAPSULE_MIN_WIDTH,
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  THEME_DARK,
  THEME_LIGHT,
  AppState,
  PaperData,
  VISUAL_TEXT_LARGE,
  VISUAL_TEXT_SMALL
} from '../common/Models';
import { PaperStore } from '../common/PaperStore';
import { CapsuleWindowMaskRow, applyCapsuleWindowMask } from '../common/CapsuleWindowMask';
import { effectivePaperTitle } from '../common/PaperTitles';
import {
  MASTER_ACTION_RETRACT,
  PAPER_ACTION_COLLAPSE,
  PAPER_ACTION_EXPAND,
  isPaperEmpty,
  resolveEdgeActivateAction,
  resolveMasterToggleAction
} from '../common/PaperInteractionPolicy';
import { formatText, tForSystem } from '../common/Strings';
import { ThemePalette, resolvePalette } from '../common/ThemePalette';

const MASTER_ROW_INITIAL_WIDTH: number = 96;
const MASTER_ROW_MIN_WIDTH: number = 64;
const MASTER_ROW_MAX_WIDTH: number = 144;

@Entry({ useSharedStorage: true })
@Component
struct MasterCapsule {
  @StorageLink('capsuleLayoutRequest') @Watch('onStoreChanged') capsuleLayoutRequest: number = 0;
  @StorageLink('paperRevision') @Watch('onStoreChanged') paperRevision: number = 0;
  @StorageLink('capsuleAreaRevision') @Watch('onLayoutChanged') capsuleAreaRevision: number = 0;
  @StorageLink('capsuleCollapseAllActive') @Watch('onLayoutChanged')
  capsuleCollapseAllActive: boolean = false;
  @StorageLink('capsuleStartTop') @Watch('onLayoutChanged') capsuleStartTop: number = 48;
  @StorageLink('capsuleGap') @Watch('onLayoutChanged') capsuleGap: number = 4;
  @StorageLink('useCapsuleMode') @Watch('onStoreChanged') useCapsuleMode: boolean = true;
  @StorageLink('useDeepCapsuleMode') @Watch('onStoreChanged') useDeepCapsuleMode: boolean = true;
  @StorageLink('useMasterCapsule') @Watch('onStoreChanged') useMasterCapsule: boolean = true;
  @StorageLink('enableAnimations') enableAnimations: boolean = true;
  @StorageLink('collapseExpandedEdgeCapsuleOnClick')
  collapseExpandedEdgeCapsuleOnClick: boolean = false;
  @StorageLink('hideEdgeCapsuleCloseButtonOnHover') @Watch('onLayoutChanged') hideEdgeCapsuleCloseButtonOnHover: boolean = false;
  @StorageLink('edgeCapsuleTitleCharacterLimit') @Watch('onLayoutChanged') edgeCapsuleTitleCharacterLimit: number = 0;
  @StorageLink('theme') theme: string = 'system';
  @StorageLink('colorScheme') colorScheme: string = 'warm';
  @StorageLink('overallFontScale') @Watch('onLayoutChanged') overallFontScale: number = 1;
  @StorageLink('capsuleTextSize') @Watch('onLayoutChanged') capsuleTextSize: string = 'medium';
  @StorageLink('capsuleTextBold') @Watch('onLayoutChanged') capsuleTextBold: boolean = false;
  @StorageLink('uiLanguage') @Watch('onLayoutChanged') uiLanguage: string = 'system';
  @StorageLink('systemLanguage') @Watch('onLayoutChanged') systemLanguage: string = 'zh-CN';
  @StorageLink('systemColorMode') systemColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  @State members: PaperData[] = [];
  @State visibleMembers: PaperData[] = [];
  @State page: number = 0;
  @State pages: number = 1;
  @State hasPager: boolean = false;
  private ownerToken: string = '';
  private active: boolean = false;
  private layoutGeneration: number = 0;
  private viewportHeight: number = CAPSULE_HEIGHT;
  private lastPresentedRequest: number = -1;
  @State @Watch('onLayoutChanged') hoveredPaperId: string = '';
  @State masterHovered: boolean = false;
  @State masterRowWidthVp: number = MASTER_ROW_INITIAL_WIDTH;

  private layoutRunning: boolean = false;
  private layoutPending: boolean = false;
  private availableHeightVp: number = 0;
  private dragStartTop: number = 48;
  private dragMoved: boolean = false;
  private suppressClickUntil: number = 0;
  private lastGeometrySignature: string = '';
  private lastMaskSignature: string = '';

  aboutToAppear(): void {
    this.active = true;
    this.ownerToken = AppStorage.get<string>('masterCapsuleToken') ?? '';
    this.refreshMembers();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.layoutGeneration++;
    PaperStore.flushNow();
  }

  private onStoreChanged(): void {
    this.refreshMembers();
  }

  private onLayoutChanged(): void {
    this.requestWindowLayout();
  }

  private refreshMembers(): void {
    this.members = PaperStore.listEdgeCapsulePapers().slice();
    if (!this.useCapsuleMode || !this.useDeepCapsuleMode || this.members.length === 0) {
      DesktopShell.syncCapsules(this.hostContext()).catch((error: Error): void => {
        console.warn('close stale capsule host failed: ' + error.message);
      });
      return;
    }
    this.requestWindowLayout();
  }

  private requestWindowLayout(): void {
    if (!this.active || !CapsuleRuntime.isOwner(this.ownerToken) || CapsuleRuntime.hasFailed()) {
      return;
    }
    this.layoutGeneration++;
    this.layoutPending = true;
    if (this.layoutRunning) {
      return;
    }
    this.layoutRunning = true;
    this.runWindowLayoutLoop().then((): void => {
      this.layoutRunning = false;
      if (this.layoutPending) {
        this.requestWindowLayout();
      }
    }).catch((error: Error): void => {
      this.layoutRunning = false;
      this.handleLayoutFailure(error).catch((recoveryError: Error): void => {
        console.error('capsule recovery failed: ' + recoveryError.message);
      });
    });
  }

  private async handleLayoutFailure(error: Error): Promise<void> {
    if (!this.active || !CapsuleRuntime.isOwner(this.ownerToken)) {
      return;
    }
    const context: common.UIAbilityContext = this.hostContext();
    this.layoutPending = false;
    CapsuleRuntime.fail(this.ownerToken, error.message);
    const win: window.Window | undefined = AppStorage.get<window.Window>('masterCapsuleWindow');
    if (win !== undefined) {
      await this.disposeFailedWindow(win);
    }
    await DesktopShell.syncCapsules(context);
  }

  private async disposeFailedWindow(win: window.Window): Promise<void> {
    // API 23 public Window has no hide(). Dispose the failed subwindow and let
    // the owning Ability terminate; an explicit retry creates a fresh one.
    try {
      await win.setWindowTouchable(false);
    } catch (error) {
      console.warn('disable failed capsule interaction: ' + String(error));
    }
    try {
      await win.destroyWindow();
    } catch (error) {
      console.warn('dispose failed capsule window: ' + String(error));
    }
  }

  private async runWindowLayoutLoop(): Promise<void> {
    while (this.layoutPending && this.active && !CapsuleRuntime.hasFailed()) {
      this.layoutPending = false;
      await this.syncWindowGeometry();
    }
  }

  private async syncWindowGeometry(): Promise<void> {
    const generation: number = this.layoutGeneration;
    const request: number = CapsuleRuntime.currentRequest();
    const win: window.Window | undefined = AppStorage.get<window.Window>('masterCapsuleWindow');
    if (win === undefined || this.members.length === 0 || !CapsuleRuntime.isParentReady(this.ownerToken)) {
      return;
    }
    let uiContext: UIContext;
    let targetDisplay: display.Display;
    try {
      uiContext = win.getUIContext();
      targetDisplay = display.getDefaultDisplaySync();
    } catch (error) {
      console.warn('query capsule host display failed: ' + String(error));
      return;
    }
    let area: display.Rect;
    try {
      area = await targetDisplay.getAvailableArea();
    } catch (error) {
      area = {
        left: 0,
        top: 0,
        width: targetDisplay.availableWidth > 0 ? targetDisplay.availableWidth : targetDisplay.width,
        height: targetDisplay.availableHeight > 0 ? targetDisplay.availableHeight : targetDisplay.height
      };
    }

    const state: AppState = PaperStore.loadState();
    const includeMaster: boolean = state.useMasterCapsule;
    const queueRetracted: boolean = includeMaster && state.capsuleCollapseAllActive;
    const areaHeightVp: number = uiContext.px2vp(area.height);
    this.availableHeightVp = areaHeightVp;
    const viewport = capsuleViewport(areaHeightVp, this.members.length, state.capsuleGap,
      includeMaster, queueRetracted, this.page);
    if (!viewport.fits) {
      throw new Error('Available area is too small for a capsule viewport.');
    }
    this.page = viewport.page;
    this.pages = viewport.pages;
    this.hasPager = viewport.pager;
    this.visibleMembers = this.members.slice(viewport.start, viewport.end);
    this.viewportHeight = viewport.height;
    const normalizedTop: number = capsuleViewportTop(state.capsuleStartTop, areaHeightVp, viewport.height);
    if (Math.abs(normalizedTop - state.capsuleStartTop) > 0.1) {
      PaperStore.setCapsuleStartTop(normalizedTop);
    }
    const measuredMasterWidth: number = this.measureMasterRowWidth(uiContext);
    if (Math.abs(measuredMasterWidth - this.masterRowWidthVp) > 0.1) {
      this.masterRowWidthVp = measuredMasterWidth;
    }
    const widthVp: number = Math.max(viewport.pager ? CAPSULE_PAGER_WIDTH : 0,
      this.hostWidthVp(includeMaster, queueRetracted));
    const heightVp: number = viewport.height;
    const requestedWidthPx: number = Math.round(uiContext.vp2px(widthVp));
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
    if (actualHeightPx > area.height || actualWidthPx > targetDisplay.width ||
      actualHeightPx + 1 < requestedHeightPx || actualWidthPx + 1 < requestedWidthPx) {
      throw new Error('System capsule geometry exceeds the available display.');
    }
    const xPx: number = Math.round(targetDisplay.width - actualWidthPx);
    const yPx: number = Math.round(area.top + uiContext.vp2px(normalizedTop));
    try {
      await win.moveWindowToAsync(xPx, yPx);
    } catch (error) {
      console.warn('async capsule subwindow edge move failed, falling back: ' + String(error));
      await win.moveWindowTo(xPx, yPx);
    }
    if (!this.active || !CapsuleRuntime.isOwner(this.ownerToken) || CapsuleRuntime.hasFailed()) {
      return;
    }
    if (generation !== this.layoutGeneration || request !== CapsuleRuntime.currentRequest()) {
      this.layoutPending = true;
      return;
    }
    const finalRect = win.getWindowProperties().windowRect;
    if (Math.abs(finalRect.left + finalRect.width - targetDisplay.width) > 1 ||
      finalRect.top < area.top || finalRect.top + finalRect.height > area.top + area.height) {
      throw new Error('System adjusted the capsule edge position: ' + JSON.stringify(finalRect));
    }
    await this.syncNativeWindowMask(win, uiContext, actualWidthPx, actualHeightPx,
      state, includeMaster, queueRetracted);
    if (!this.active || !CapsuleRuntime.isOwner(this.ownerToken) || CapsuleRuntime.hasFailed()) {
      return;
    }
    if (generation !== this.layoutGeneration || request !== CapsuleRuntime.currentRequest()) {
      this.layoutPending = true;
      return;
    }
    if (this.lastPresentedRequest !== request) {
      await win.showWindow();
      await win.setWindowTouchable(true);
      await win.setWindowFocusable(true);
      this.lastPresentedRequest = request;
    }
    const confirmed: boolean = CapsuleRuntime.confirm(this.ownerToken, request);
    if (!confirmed && (!this.active || !CapsuleRuntime.isOwner(this.ownerToken) || CapsuleRuntime.hasFailed())) {
      await this.disposeFailedWindow(win);
    }
  }

  private measureMasterRowWidth(uiContext: UIContext): number {
    const label: string = this.currentMasterLabel();
    let labelWidth: number = label.length * this.fontSize();
    try {
      labelWidth = uiContext.px2vp(uiContext.getMeasureUtils().measureText({
        textContent: label,
        fontSize: this.fontSize(),
        fontWeight: this.capsuleTextBold ? FontWeight.Bold : FontWeight.Medium
      }));
    } catch (error) {
      console.warn('measure master capsule label failed: ' + String(error));
    }
    const desired: number = Math.ceil(7 + 12 + 4 + labelWidth + 7 + 2);
    return Math.max(MASTER_ROW_MIN_WIDTH, Math.min(MASTER_ROW_MAX_WIDTH, desired));
  }

  private hostWidthVp(includeMaster: boolean = this.useMasterCapsule,
    queueRetracted: boolean = includeMaster && this.capsuleCollapseAllActive): number {
    if (includeMaster && queueRetracted) {
      return this.masterRowWidthVp;
    }
    let width: number = includeMaster ? this.masterRowWidthVp : CAPSULE_MIN_WIDTH;
    for (let i: number = 0; i < this.members.length; i++) {
      width = Math.max(width, this.capsuleWidth(this.members[i]));
    }
    return Math.max(CAPSULE_MIN_WIDTH, Math.min(CAPSULE_MAX_WIDTH, width));
  }

  private capsuleWidth(paper: PaperData): number {
    return Math.max(CAPSULE_MIN_WIDTH, Math.min(CAPSULE_MAX_WIDTH, paper.capsuleWidth));
  }


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

    if (!queueRetracted && this.hasPager) {
      rows.push({
        topPx: uiContext.vp2px(slotIndex * (CAPSULE_HEIGHT + state.capsuleGap) + rowTopInsetVp),
        heightPx: uiContext.vp2px(rowHeightVp),
        visibleWidthPx: uiContext.vp2px(CAPSULE_PAGER_WIDTH),
        radiusPx: uiContext.vp2px(radiusVp)
      });
      slotIndex++;
    }
    if (!queueRetracted) {
      for (let i: number = 0; i < this.visibleMembers.length; i++) {
        const paper: PaperData = this.visibleMembers[i];
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

    const signature: string = widthPx.toString() + ':' + heightPx.toString() + ':' + JSON.stringify(rows);
    if (signature === this.lastMaskSignature) {
      return;
    }
    const applied: boolean = await applyCapsuleWindowMask(win, widthPx, heightPx, rows);
    if (!applied) {
      throw new Error('Native capsule mask failed; rectangular fallback is disabled.');
    }
    this.lastMaskSignature = signature;
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toggleQueueRetraction(): void {
    if (Date.now() < this.suppressClickUntil || this.members.length === 0) {
      return;
    }
    const action: string = resolveMasterToggleAction(this.capsuleCollapseAllActive);
    PaperStore.setCapsuleCollapseAllActive(action === MASTER_ACTION_RETRACT);
  }

  private beginVerticalMove(): void {
    this.dragStartTop = this.capsuleStartTop;
    this.dragMoved = false;
  }

  private updateVerticalMove(event: GestureEvent): void {
    if (Math.abs(event.offsetY) > 3) {
      this.dragMoved = true;
    }
    let fallbackHeight: number = this.availableHeightVp;
    try {
      const targetDisplay: display.Display = display.getDefaultDisplaySync();
      const fallbackHeightPx: number = targetDisplay.availableHeight > 0 ? targetDisplay.availableHeight :
        targetDisplay.height;
      fallbackHeight = this.getUIContext().px2vp(fallbackHeightPx);
    } catch (error) {
      console.warn('query capsule drag bounds failed: ' + String(error));
    }
    const areaHeight: number = this.availableHeightVp > 0 ? this.availableHeightVp : fallbackHeight;
    const nextTop: number = capsuleViewportTop(this.dragStartTop + event.offsetY, areaHeight,
      this.viewportHeight);
    if (Math.abs(nextTop - this.capsuleStartTop) > 0.1) {
      PaperStore.setCapsuleStartTop(nextTop);
    }
  }

  private endVerticalMove(): void {
    if (this.dragMoved) {
      this.suppressClickUntil = Date.now() + 250;
      this.dragMoved = false;
    }
    PaperStore.flushNow();
  }

  private activatePaper(paperId: string): void {
    const latest: PaperData | null = PaperStore.getPaper(paperId);
    if (latest === null) {
      return;
    }
    const action: string = resolveEdgeActivateAction(latest.isCollapsed,
      this.collapseExpandedEdgeCapsuleOnClick);
    if (action === PAPER_ACTION_EXPAND) {
      DesktopShell.setPaperCollapsed(this.hostContext(), latest.id, false);
    } else if (action === PAPER_ACTION_COLLAPSE) {
      DesktopShell.setPaperCollapsed(this.hostContext(), latest.id, true);
    } else {
      DesktopShell.startPaper(this.hostContext(), latest.id, PAPER_COMMAND_SHOW)
        .then((_started: boolean): Promise<boolean> => DesktopShell.syncCapsules(this.hostContext()))
        .catch((error: Error): void => console.warn('activate capsule paper failed: ' + error.message));
    }
  }

  private hidePaper(paperId: string): void {
    DesktopShell.hidePaper(this.hostContext(), paperId).catch((error: Error): void => {
      console.warn('hide capsule paper failed: ' + error.message);
    });
  }

  private togglePaperCollapsed(paperId: string): void {
    const latest: PaperData | null = PaperStore.getPaper(paperId);
    if (latest === null) {
      return;
    }
    DesktopShell.setPaperCollapsed(this.hostContext(), latest.id, !latest.isCollapsed)
      .catch((error: Error): void => console.warn('toggle capsule paper failed: ' + error.message));
  }

  private deletePaper(paperId: string): void {
    const latest: PaperData | null = PaperStore.getPaper(paperId);
    if (latest === null) {
      return;
    }
    if (isPaperEmpty(latest)) {
      this.performDeletePaper(paperId);
      return;
    }
    AlertDialog.show({
      title: this.text('dialog.deletePaperTitle'),
      message: this.text('dialog.deletePaperMessage'),
      autoCancel: true,
      primaryButton: { value: this.text('action.cancel'), action: (): void => {} },
      secondaryButton: {
        value: this.text('action.deletePaper'),
        fontColor: this.palette().danger,
        action: (): void => this.performDeletePaper(paperId)
      }
    });
  }

  private performDeletePaper(paperId: string): void {
    DesktopShell.deletePaper(this.hostContext(), paperId).catch((error: Error): void => {
      console.warn('delete capsule paper failed: ' + error.message);
    });
  }

  private createPaper(type: string): void {
    DesktopShell.createPaper(this.hostContext(), type).catch((error: Error): void => {
      console.warn('create paper from capsule host failed: ' + error.message);
    });
  }

  private showAll(): void {
    DesktopShell.showAll(this.hostContext()).catch((error: Error): void => {
      console.warn('show papers from capsule host failed: ' + error.message);
    });
  }

  private hideAll(): void {
    DesktopShell.hideAll(this.hostContext()).catch((error: Error): void => {
      console.warn('hide papers from capsule host failed: ' + error.message);
    });
  }

  private openSettings(): void {
    DesktopShell.openSettings(this.hostContext()).catch((error: Error): void => {
      console.warn('open settings from capsule host failed: ' + error.message);
    });
  }

  private exitApplication(): void {
    DesktopShell.exitApplication(this.hostContext()).catch((error: Error): void => {
      console.warn('exit PaperTodo from capsule host failed: ' + error.message);
    });
  }

  private isDark(): boolean {
    if (this.theme === THEME_DARK) {
      return true;
    }
    if (this.theme === THEME_LIGHT) {
      return false;
    }
    return this.systemColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private palette(): ThemePalette {
    return resolvePalette(this.colorScheme, this.isDark());
  }

  private fontSize(): number {
    let base: number = 13;
    if (this.capsuleTextSize === VISUAL_TEXT_SMALL) {
      base = 12;
    } else if (this.capsuleTextSize === VISUAL_TEXT_LARGE) {
      base = 14;
    }
    return Math.round(base * this.overallFontScale * 10) / 10;
  }

  private fontWeight(): FontWeight {
    return this.capsuleTextBold ? FontWeight.Bold : FontWeight.Normal;
  }

  private currentMasterLabel(): string {
    if (!this.capsuleCollapseAllActive) {
      return this.withoutStateGlyph(this.text('capsule.retractQueue'));
    }
    return this.withoutStateGlyph(
      formatText(this.text('capsule.retractedCount'), 'count', this.members.length.toString()));
  }

  private withoutStateGlyph(value: string): string {
    if (value.startsWith('▾') || value.startsWith('▸')) {
      return value.substring(1).trim();
    }
    return value.trim();
  }

  private capsuleTitle(paper: PaperData): string {
    const value: string = effectivePaperTitle(paper, PaperStore.listPapers(), this.uiLanguage, this.systemLanguage);
    if (this.edgeCapsuleTitleCharacterLimit <= 0) {
      return value;
    }
    const limit: number = Math.max(2, Math.min(20, Math.round(this.edgeCapsuleTitleCharacterLimit)));
    return value.length > limit ? value.substring(0, limit) + '…' : value;
  }

  private capsuleTypeGlyph(paper: PaperData): string {
    return paper.type === PAPER_TYPE_NOTE ? '✎' : '☑';
  }

  private capsuleOffsetX(paper: PaperData): number {
    const width: number = this.capsuleWidth(paper);
    if (this.hideEdgeCapsuleCloseButtonOnHover ||
      (this.hoveredPaperId !== paper.id && paper.isCollapsed)) {
      return CAPSULE_CLOSE_WIDTH;
    }
    return 0;
  }

  private text(key: string): string {
    return tForSystem(this.uiLanguage, this.systemLanguage, key);
  }

  @Builder
  private MasterContextMenu() {
    Menu() {
      MenuItem({ content: this.text('action.newTodo') })
        .onClick((): void => this.createPaper(PAPER_TYPE_TODO))
      MenuItem({ content: this.text('action.newNote') })
        .onClick((): void => this.createPaper(PAPER_TYPE_NOTE))
      MenuItem({ content: this.text('action.showAll') })
        .onClick((): void => this.showAll())
      MenuItem({ content: this.text('action.hideAll') })
        .onClick((): void => this.hideAll())
      MenuItem({ content: this.text('action.settings') })
        .onClick((): void => this.openSettings())
      MenuItem({ content: this.text('action.exit') })
        .onClick((): void => this.exitApplication())
    }
  }

  @Builder
  private CapsuleContextMenu(paper: PaperData) {
    Menu() {
      MenuItem({ content: this.text('action.settings') })
        .onClick((): void => this.openSettings())
      MenuItem({ content: this.text(paper.isCollapsed ? 'action.expand' : 'action.collapse') })
        .onClick((): void => this.togglePaperCollapsed(paper.id))
      MenuItem({ content: this.text('action.hide') })
        .onClick((): void => this.hidePaper(paper.id))
      MenuItem({ content: this.text('action.deletePaper') })
        .contentFontColor(this.palette().danger)
        .onClick((): void => this.deletePaper(paper.id))
    }
  }

  @Builder
  private MasterRow() {
    Row() {
      Row({ space: 4 }) {
        Text(this.capsuleCollapseAllActive ? '▸' : '▾')
          .fontSize(Math.round(12 * this.overallFontScale * 10) / 10)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().text)
        Text(this.currentMasterLabel())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontSize(this.fontSize())
          .fontWeight(this.capsuleTextBold ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.palette().muted)
      }
      .width(this.masterRowWidthVp)
      .height(30)
      .padding({ left: 7, right: 7 })
      .backgroundColor(this.masterHovered ? this.palette().input : this.palette().paper)
      .border({ width: 1, color: this.palette().border })
      .borderRadius({ topLeft: 15, bottomLeft: 15, topRight: 0, bottomRight: 0 })
      .onHover((hovered: boolean): void => {
        this.masterHovered = hovered;
      })
      .onClick((): void => this.toggleQueueRetraction())
      .gesture(
        PanGesture({ direction: PanDirection.Vertical })
          .onActionStart((): void => this.beginVerticalMove())
          .onActionUpdate((event: GestureEvent): void => this.updateVerticalMove(event))
          .onActionEnd((): void => this.endVerticalMove())
          .onActionCancel((): void => this.endVerticalMove())
      )
      .bindContextMenu(() => {
        this.MasterContextMenu()
      }, ResponseType.RightClick)
    }
    .width('100%')
    .height(CAPSULE_HEIGHT)
    .justifyContent(FlexAlign.End)
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  private CapsuleRow(paper: PaperData) {
    Row() {
      Row() {
        Row({ space: 4 }) {
          Text(this.capsuleTypeGlyph(paper))
            .fontSize(this.fontSize() + 1)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().text)
          Text(this.capsuleTitle(paper))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontSize(this.fontSize())
            .fontWeight(this.fontWeight())
            .fontColor(this.palette().text)
        }
        .layoutWeight(1)
        .height('100%')
        .padding({ left: 9, right: 5 })
        .onClick((): void => this.activatePaper(paper.id))

        Stack({ alignContent: Alignment.Center }) {
          Text('×')
            .fontSize(11)
            .fontColor(this.palette().muted)
        }
        .width(CAPSULE_CLOSE_WIDTH)
        .height('100%')
        .visibility(this.hideEdgeCapsuleCloseButtonOnHover ? Visibility.Hidden : Visibility.Visible)
        .border({ width: { left: 1 }, color: this.palette().border })
        .onClick((): void => this.hidePaper(paper.id))
      }
      .width(this.capsuleWidth(paper))
      .height(30)
      .translate({ x: this.capsuleOffsetX(paper) })
      .backgroundColor(this.palette().paper)
      .border({ width: 1, color: paper.isCollapsed ? this.palette().border : this.palette().accent })
      .borderRadius({ topLeft: 15, bottomLeft: 15, topRight: 0, bottomRight: 0 })
      .onHover((hovered: boolean): void => {
        if (hovered) {
          this.hoveredPaperId = paper.id;
        } else if (this.hoveredPaperId === paper.id) {
          this.hoveredPaperId = '';
        }
      })
      .bindContextMenu(() => {
        this.CapsuleContextMenu(paper)
      }, ResponseType.RightClick)
    }
    .width('100%')
    .height(CAPSULE_HEIGHT)
    .justifyContent(FlexAlign.End)
    .padding({ top: 8, bottom: 8 })
  }

  private changePage(delta: number): void {
    const next: number = Math.max(0, Math.min(this.pages - 1, this.page + delta));
    if (next !== this.page) {
      this.page = next;
      this.hoveredPaperId = '';
      this.requestWindowLayout();
    }
  }

  @Builder
  private PagerRow() {
    Row() {
      Row() {
        Button('‹', { type: ButtonType.Normal })
          .width(28).height(30).padding(0)
          .backgroundColor(Color.Transparent).fontColor(this.palette().text)
          .enabled(this.page > 0)
          .accessibilityText(this.text('capsule.previousPage'))
          .onClick((): void => this.changePage(-1))
        Text((this.page + 1).toString() + '/' + this.pages.toString())
          .layoutWeight(1).fontSize(11).textAlign(TextAlign.Center)
          .fontColor(this.palette().text)
        Button('›', { type: ButtonType.Normal })
          .width(28).height(30).padding(0)
          .backgroundColor(Color.Transparent).fontColor(this.palette().text)
          .enabled(this.page + 1 < this.pages)
          .accessibilityText(this.text('capsule.nextPage'))
          .onClick((): void => this.changePage(1))
      }
      .width(CAPSULE_PAGER_WIDTH).height(30)
      .backgroundColor(this.palette().paper)
      .border({ width: 1, color: this.palette().border })
      .borderRadius({ topLeft: 15, bottomLeft: 15, topRight: 0, bottomRight: 0 })
    }
    .width('100%').height(CAPSULE_HEIGHT)
    .justifyContent(FlexAlign.End).padding({ top: 8, bottom: 8 })
  }

  build() {
    Column({ space: this.capsuleGap }) {
      if (this.useMasterCapsule) {
        this.MasterRow()
      }
      if (!this.useMasterCapsule || !this.capsuleCollapseAllActive) {
        if (this.hasPager) {
          this.PagerRow()
        }
        ForEach(this.visibleMembers, (paper: PaperData) => {
          this.CapsuleRow(paper)
        }, (paper: PaperData): string => paper.id)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.End)
    .clip(true)
    .backgroundColor(Color.Transparent)
  }
}
