import {
  common,
  ConfigurationConstant
} from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { display, window } from '@kit.ArkUI';
import { capsuleSlotTop, normalizeCapsuleStartTopMargin } from '../common/CapsuleLayout';
import { DesktopShell, PAPER_COMMAND_SHOW } from '../common/DesktopShell';
import { ExternalMarkdown } from '../common/ExternalMarkdown';
import {
  CAPSULE_CLOSE_WIDTH,
  CAPSULE_HEIGHT,
  CAPSULE_MAX_WIDTH,
  CAPSULE_MIN_WIDTH,
  CAPSULE_PLATFORM_MIN_WIDTH,
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  THEME_DARK,
  THEME_LIGHT,
  VISUAL_TEXT_LARGE,
  VISUAL_TEXT_SMALL,
  AppState,
  PaperData,
  PaperItem
} from '../common/Models';
import { PaperStore } from '../common/PaperStore';
import { effectivePaperTitle } from '../common/PaperTitles';
import {
  PAPER_ACTION_COLLAPSE,
  PAPER_ACTION_EXPAND,
  isPaperEmpty,
  resolveEdgeActivateAction
} from '../common/PaperInteractionPolicy';
import { tForSystem } from '../common/Strings';
import { truncateText } from '../common/TextSafety';
import { ThemePalette, resolvePalette } from '../common/ThemePalette';

@Entry({ useSharedStorage: true })
@Component
struct EdgeCapsule {
  @LocalStorageProp('paperId') paperId: string = '';
  @StorageLink('uiLanguage') uiLanguage: string = 'system';
  @StorageLink('systemLanguage') systemLanguage: string = 'zh-CN';
  @StorageLink('theme') theme: string = 'system';
  @StorageLink('colorScheme') colorScheme: string = 'warm';
  @StorageLink('useCapsuleMode') @Watch('onCapsuleSettingsChanged') useCapsuleMode: boolean = true;
  @StorageLink('useDeepCapsuleMode') @Watch('onCapsuleSettingsChanged') useDeepCapsuleMode: boolean = true;
  @StorageLink('showDeepCapsuleWhileExpanded') @Watch('onCapsuleSettingsChanged')
  showDeepCapsuleWhileExpanded: boolean = true;
  @StorageLink('useMasterCapsule') @Watch('onCapsuleSettingsChanged') useMasterCapsule: boolean = true;
  @StorageLink('capsuleCollapseAllActive') @Watch('onCapsuleSettingsChanged')
  capsuleCollapseAllActive: boolean = false;
  @StorageLink('capsuleStartTop') @Watch('onCapsuleSettingsChanged') capsuleStartTop: number = 48;
  @StorageLink('capsuleGap') @Watch('onCapsuleSettingsChanged') capsuleGap: number = 4;
  @StorageLink('enableAnimations') enableAnimations: boolean = true;
  @StorageLink('collapseExpandedEdgeCapsuleOnClick')
  collapseExpandedEdgeCapsuleOnClick: boolean = false;
  @StorageLink('hideEdgeCapsuleCloseButtonOnHover') @Watch('onCapsuleSettingsChanged')
  hideEdgeCapsuleCloseButtonOnHover: boolean = false;
  @StorageLink('edgeCapsuleTitleCharacterLimit') edgeCapsuleTitleCharacterLimit: number = 0;
  @StorageLink('overallFontScale') overallFontScale: number = 1;
  @StorageLink('capsuleTextSize') capsuleTextSize: string = 'medium';
  @StorageLink('capsuleTextBold') capsuleTextBold: boolean = false;
  @StorageLink('paperRevision') @Watch('onPaperRevision') paperRevision: number = 0;
  @StorageLink('capsuleAreaRevision') @Watch('onCapsuleAreaChanged') capsuleAreaRevision: number = 0;
  @StorageLink('systemColorMode') systemColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  @State capsuleText: string = '';
  @State paperType: string = PAPER_TYPE_TODO;
  @State isCollapsed: boolean = true;
  @State completedTodos: number = 0;
  @State hovered: boolean = false;
  @State contextMenuOpen: boolean = false;

  private paper: PaperData | null = null;
  private componentActive: boolean = false;
  private layoutGeneration: number = 0;
  private motionGeneration: number = 0;
  private motionTimer: number = -1;

  aboutToAppear(): void {
    this.componentActive = true;
    this.reloadPaper();
    setTimeout((): void => this.syncGeometry(false), 30);
  }

  aboutToDisappear(): void {
    this.componentActive = false;
    this.cancelWindowMotion();
    PaperStore.flushNow();
  }

  private onPaperRevision(): void {
    this.reloadPaper();
    this.syncGeometry(true);
  }

  private onCapsuleSettingsChanged(): void {
    if (this.capsuleCollapseAllActive) {
      this.hovered = false;
    }
    this.reloadPaper();
    this.syncGeometry(true);
  }

  private onCapsuleAreaChanged(): void {
    this.syncGeometry(false);
  }

  private reloadPaper(): void {
    const loaded: PaperData | null = PaperStore.getPaper(this.paperId);
    if (loaded === null) {
      this.paper = null;
      this.capsuleText = '';
      this.completedTodos = 0;
      return;
    }
    this.paper = loaded;
    this.capsuleText = this.capsuleTitleForPaper(loaded);
    this.paperType = loaded.type;
    this.isCollapsed = loaded.isCollapsed;
    this.completedTodos = this.countCompleted(loaded.items);
  }

  private syncGeometry(animate: boolean): void {
    if (!this.componentActive) {
      return;
    }
    const generation: number = ++this.layoutGeneration;
    this.syncGeometryAsync(animate, generation).catch((error: Error): void => {
      console.error('sync edge capsule geometry failed: ' + error.message);
    });
  }

  private async syncGeometryAsync(animate: boolean, generation: number): Promise<void> {
    const latest: PaperData | null = PaperStore.getPaper(this.paperId);
    const members: PaperData[] = PaperStore.listEdgeCapsulePapers();
    const memberIndex: number = this.memberIndex(members);
    if (latest === null || memberIndex < 0 || !this.useCapsuleMode || !this.useDeepCapsuleMode) {
      await DesktopShell.syncCapsules(this.hostContext());
      return;
    }
    this.paper = latest;
    this.isCollapsed = latest.isCollapsed;
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }

    const screen: display.Display = display.getDefaultDisplaySync();
    const area: display.Rect = await this.getAvailableArea(screen);
    if (generation !== this.layoutGeneration || !this.componentActive) {
      return;
    }
    const uiContext: UIContext = win.getUIContext();
    const state: AppState = PaperStore.loadState();
    const includeMaster: boolean = state.useMasterCapsule && members.length > 0;
    const startTop: number = normalizeCapsuleStartTopMargin(state.capsuleStartTop,
      uiContext.px2vp(area.height), members.length, state.capsuleGap, includeMaster);
    const slotTop: number = capsuleSlotTop(startTop, memberIndex, state.capsuleGap, includeMaster);
    const targetTop: number = state.capsuleCollapseAllActive ?
      capsuleSlotTop(startTop, 0, state.capsuleGap, false) : slotTop;
    const widthVp: number = this.calculateCapsuleWidth(latest, uiContext);
    if (Math.abs(widthVp - latest.capsuleWidth) > 0.1) {
      latest.capsuleWidth = widthVp;
      PaperStore.updatePaper(latest, false);
    }
    const widthPx: number = Math.round(uiContext.vp2px(widthVp));
    const heightPx: number = Math.round(uiContext.vp2px(CAPSULE_HEIGHT));
    // The native window itself always stays flush with and fully inside the
    // right edge. Visual retraction is an ArkUI translation below, not an
    // out-of-bounds moveWindowTo() request that the PC window manager can clamp.
    const targetX: number = area.left + area.width - widthPx;
    const targetY: number = area.top + Math.round(uiContext.vp2px(targetTop));

    try {
      await win.setWindowLimits({
        minWidth: Math.round(uiContext.vp2px(CAPSULE_PLATFORM_MIN_WIDTH)),
        minHeight: heightPx,
        maxWidth: Math.max(widthPx, area.width),
        maxHeight: Math.max(heightPx, area.height)
      }, true);
    } catch (error) {
      console.warn('set edge capsule limits failed: ' + String(error));
    }
    if (generation !== this.layoutGeneration || !this.componentActive) {
      return;
    }
    await win.resize(widthPx, heightPx);
    await win.setWindowTopmost(true);
    try {
      await win.setWindowTouchable(!state.capsuleCollapseAllActive);
    } catch (error) {
      console.warn('update retracted capsule hit testing failed: ' + String(error));
    }
    if (generation !== this.layoutGeneration || !this.componentActive) {
      return;
    }
    const closeVisible: boolean = !this.hideEdgeCapsuleCloseButtonOnHover &&
      (this.isPointerSessionActive() || !latest.isCollapsed);
    this.moveWindow(win, targetX, targetY, animate && this.enableAnimations, closeVisible ? 130 : 170);
  }

  private isPointerSessionActive(): boolean {
    return this.hovered || this.contextMenuOpen;
  }

  private onContextMenuAppear(): void {
    if (this.contextMenuOpen) {
      return;
    }
    this.contextMenuOpen = true;
    this.syncGeometry(true);
  }

  private onContextMenuDisappear(): void {
    if (!this.contextMenuOpen) {
      return;
    }
    this.contextMenuOpen = false;
    this.syncGeometry(true);
  }

  private moveWindow(win: window.Window, targetX: number, targetY: number,
    animate: boolean, duration: number): void {
    this.cancelWindowMotion();
    let startY: number = targetY;
    try {
      const rect: window.Rect = win.getWindowProperties().windowRect;
      startY = rect.top;
    } catch (error) {
      console.warn('read edge capsule position failed: ' + String(error));
    }
    if (!animate || duration <= 0 || startY === targetY) {
      win.moveWindowTo(targetX, targetY).catch((error: BusinessError): void => {
        console.error('move edge capsule failed: ' + error.message);
      });
      return;
    }
    const generation: number = this.motionGeneration;
    const startedAt: number = Date.now();
    const tick = async (): Promise<void> => {
      if (generation !== this.motionGeneration || !this.componentActive) {
        return;
      }
      const progress: number = Math.min(1, Math.max(0, (Date.now() - startedAt) / duration));
      const eased: number = 1 - Math.pow(1 - progress, 3);
      const y: number = Math.round(startY + (targetY - startY) * eased);
      try {
        // Horizontal motion is deliberately forbidden here. Repeated native
        // X moves fought the HarmonyOS PC window manager and produced the
        // visible edge/inset ping-pong seen on hardware.
        await win.moveWindowTo(targetX, y);
      } catch (error) {
        console.error('animate edge capsule failed: ' + String(error));
        return;
      }
      if (generation !== this.motionGeneration || !this.componentActive || progress >= 1) {
        return;
      }
      this.motionTimer = setTimeout((): void => {
        tick().catch((error: Error): void => {
          console.error('continue edge capsule animation failed: ' + error.message);
        });
      }, 16);
    };
    tick().catch((error: Error): void => {
      console.error('start edge capsule animation failed: ' + error.message);
    });
  }

  private cancelWindowMotion(): void {
    this.motionGeneration += 1;
    if (this.motionTimer >= 0) {
      clearTimeout(this.motionTimer);
      this.motionTimer = -1;
    }
  }

  private async getAvailableArea(screen: display.Display): Promise<display.Rect> {
    try {
      return await screen.getAvailableArea();
    } catch (error) {
      console.warn('get edge capsule available area failed: ' + String(error));
      return {
        left: 0,
        top: 0,
        width: screen.availableWidth > 0 ? screen.availableWidth : screen.width,
        height: screen.availableHeight > 0 ? screen.availableHeight : screen.height
      };
    }
  }

  private memberIndex(members: PaperData[]): number {
    for (let i: number = 0; i < members.length; i++) {
      if (members[i].id === this.paperId) {
        return i;
      }
    }
    return -1;
  }

  private currentWindow(): window.Window | undefined {
    return AppStorage.get<window.Window>('edgeWindow:' + this.paperId);
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private activateCapsule(): void {
    this.activateCapsuleAsync().catch((error: Error): void => {
      console.error('activate edge capsule failed: ' + error.message);
    });
  }

  private async activateCapsuleAsync(): Promise<void> {
    const latest: PaperData | null = PaperStore.getPaper(this.paperId);
    if (latest === null) {
      return;
    }
    const context: common.UIAbilityContext = this.hostContext();
    const action: string = resolveEdgeActivateAction(latest.isCollapsed,
      this.collapseExpandedEdgeCapsuleOnClick);
    if (action === PAPER_ACTION_EXPAND) {
      await DesktopShell.setPaperCollapsed(context, this.paperId, false);
      return;
    }
    if (action === PAPER_ACTION_COLLAPSE) {
      await DesktopShell.setPaperCollapsed(context, this.paperId, true);
      return;
    }
    await DesktopShell.startPaper(context, this.paperId, PAPER_COMMAND_SHOW);
    await DesktopShell.syncCapsules(context);
  }

  private hidePaper(): void {
    DesktopShell.hidePaper(this.hostContext(), this.paperId).catch((error: Error): void => {
      console.error('hide paper from edge capsule failed: ' + error.message);
    });
  }

  private toggleCollapsed(): void {
    const latest: PaperData | null = PaperStore.getPaper(this.paperId);
    if (latest === null) {
      return;
    }
    DesktopShell.setPaperCollapsed(this.hostContext(), this.paperId, !latest.isCollapsed)
      .catch((error: Error): void => {
        console.error('toggle paper from edge capsule failed: ' + error.message);
      });
  }

  private deletePaper(): void {
    const latest: PaperData | null = PaperStore.getPaper(this.paperId);
    if (latest === null) {
      return;
    }
    if (isPaperEmpty(latest)) {
      this.performDeletePaper();
      return;
    }
    AlertDialog.show({
      title: this.text('dialog.deletePaperTitle'),
      message: this.text('dialog.deletePaperMessage'),
      autoCancel: true,
      primaryButton: {
        value: this.text('action.cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: this.text('action.deletePaper'),
        fontColor: this.palette().danger,
        action: (): void => this.performDeletePaper()
      }
    });
  }

  private performDeletePaper(): void {
    this.deletePaperAsync().catch((error: Error): void => {
      console.error('delete paper from edge capsule failed: ' + error.message);
    });
  }

  private async deletePaperAsync(): Promise<void> {
    const context: common.UIAbilityContext = this.hostContext();
    await DesktopShell.deletePaper(context, this.paperId);
    PaperStore.flushNow();
    await context.terminateSelf();
  }

  private createPaper(type: string): void {
    DesktopShell.createPaper(this.hostContext(), type, this.paperId).catch((error: Error): void => {
      console.error('create paper from edge capsule failed: ' + error.message);
    });
  }

  private openSettings(): void {
    DesktopShell.openSettings(this.hostContext()).catch((error: Error): void => {
      console.error('open settings from edge capsule failed: ' + error.message);
    });
  }

  private clearCompleted(): void {
    const latest: PaperData | null = PaperStore.getPaper(this.paperId);
    if (latest === null || latest.type !== PAPER_TYPE_TODO) {
      return;
    }
    const next: PaperItem[] = [];
    for (let i: number = 0; i < latest.items.length; i++) {
      const source: PaperItem = latest.items[i];
      if (!source.done) {
        const copied: PaperItem = {
          id: source.id,
          text: source.text,
          done: false,
          order: next.length
        };
        if (source.linkedPaperId !== undefined) {
          copied.linkedPaperId = source.linkedPaperId;
        }
        if (source.quickLaunchUri !== undefined) {
          copied.quickLaunchUri = source.quickLaunchUri;
        }
        if (source.quickLaunchName !== undefined) {
          copied.quickLaunchName = source.quickLaunchName;
        }
        if (source.quickLaunchKind !== undefined) {
          copied.quickLaunchKind = source.quickLaunchKind;
        }
        next.push(copied);
      }
    }
    if (next.length === 0) {
      next.push(PaperStore.createTodoItem('', 0));
    }
    latest.items = next;
    PaperStore.updatePaper(latest, true);
    this.bumpPaperRevision();
    this.reloadPaper();
  }

  private openMarkdownExternally(): void {
    this.openMarkdownExternallyAsync().catch((error: Error): void => {
      console.error('open note externally from edge capsule failed: ' + error.message);
    });
  }

  private async openMarkdownExternallyAsync(): Promise<void> {
    const latest: PaperData | null = PaperStore.getPaper(this.paperId);
    if (latest === null || latest.type !== PAPER_TYPE_NOTE) {
      return;
    }
    await ExternalMarkdown.open(this.hostContext(), latest);
  }

  private bumpPaperRevision(): void {
    const revision: number = AppStorage.get<number>('paperRevision') ?? 0;
    AppStorage.setOrCreate<number>('paperRevision', revision + 1);
  }

  private countCompleted(items: PaperItem[]): number {
    let count: number = 0;
    for (let i: number = 0; i < items.length; i++) {
      if (items[i].done) {
        count += 1;
      }
    }
    return count;
  }

  private capsuleTitleForPaper(latest: PaperData): string {
    const value: string = effectivePaperTitle(latest, PaperStore.listPapers(),
      this.uiLanguage, this.systemLanguage);
    if (this.edgeCapsuleTitleCharacterLimit <= 0) {
      return value;
    }
    const limit: number = Math.max(2, Math.min(20, Math.round(this.edgeCapsuleTitleCharacterLimit)));
    return value.length > limit ? truncateText(value, limit) + '…' : value;
  }

  private calculateCapsuleWidth(paper: PaperData, uiContext: UIContext): number {
    const title: string = this.capsuleTitleForPaper(paper);
    const measurementTitle: string = title.length > 128 ? truncateText(title, 128) : title;
    let titleWidth: number = measurementTitle.length * this.fontSize();
    try {
      titleWidth = uiContext.px2vp(uiContext.getMeasureUtils().measureText({
        textContent: measurementTitle,
        fontSize: this.fontSize(),
        fontWeight: this.fontWeight()
      }));
    } catch (error) {
      console.warn('measure edge capsule title failed: ' + String(error));
    }
    const desired: number = Math.ceil(9 + 18 + 4 + titleWidth + 5 + CAPSULE_CLOSE_WIDTH);
    return Math.max(CAPSULE_MIN_WIDTH, Math.min(CAPSULE_MAX_WIDTH, desired));
  }

  private typeLabel(): string {
    return this.paperType === PAPER_TYPE_NOTE ? '✎' : '☑';
  }

  private text(key: string): string {
    return tForSystem(this.uiLanguage, this.systemLanguage, key);
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
      base -= 1;
    } else if (this.capsuleTextSize === VISUAL_TEXT_LARGE) {
      base += 1;
    }
    return Math.round(base * this.overallFontScale * 10) / 10;
  }

  private fontWeight(): FontWeight {
    return this.capsuleTextBold ? FontWeight.Bold : FontWeight.Normal;
  }

  private contentOffsetX(): number {
    if (this.capsuleCollapseAllActive) {
      const width: number = this.paper === null ? CAPSULE_MAX_WIDTH : this.paper.capsuleWidth;
      return Math.max(CAPSULE_MIN_WIDTH, Math.min(CAPSULE_MAX_WIDTH, width));
    }
    if (this.hideEdgeCapsuleCloseButtonOnHover ||
      (!this.isPointerSessionActive() && this.isCollapsed)) {
      return CAPSULE_CLOSE_WIDTH;
    }
    return 0;
  }

  @Builder
  private CapsuleContextMenu() {
    Menu() {
      MenuItem({ content: this.text('action.newTodo') })
        .onClick((): void => this.createPaper(PAPER_TYPE_TODO))
      MenuItem({ content: this.text('action.newNote') })
        .onClick((): void => this.createPaper(PAPER_TYPE_NOTE))
      MenuItem({ content: this.text('action.settings') })
        .onClick((): void => this.openSettings())
      if (this.paperType === PAPER_TYPE_TODO) {
        MenuItem({ content: this.text('action.clearCompleted') })
          .enabled(this.completedTodos > 0)
          .onClick((): void => this.clearCompleted())
      } else {
        MenuItem({ content: this.text('action.openExternally') })
          .onClick((): void => this.openMarkdownExternally())
      }
      MenuItem({ content: this.text(this.isCollapsed ? 'action.expand' : 'action.collapse') })
        .onClick((): void => this.toggleCollapsed())
      MenuItem({ content: this.text('action.hide') })
        .onClick((): void => this.hidePaper())
      MenuItem({ content: this.text('action.deletePaper') })
        .contentFontColor(this.palette().danger)
        .onClick((): void => this.deletePaper())
    }
    .onAppear((): void => this.onContextMenuAppear())
    .onDisAppear((): void => this.onContextMenuDisappear())
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        Row({ space: 4 }) {
          Text(this.typeLabel())
            .fontSize(this.fontSize() + 1)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().text)
          Text(this.capsuleText)
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
        .onClick((): void => this.activateCapsule())

        Stack({ alignContent: Alignment.Center }) {
          Text('×')
            .fontSize(11)
            .fontColor(this.palette().muted)
        }
        .width(CAPSULE_CLOSE_WIDTH)
        .height('100%')
        .visibility(this.hideEdgeCapsuleCloseButtonOnHover ? Visibility.Hidden : Visibility.Visible)
        .border({ width: { left: 1 }, color: this.palette().border })
        .backgroundColor(this.hovered ? this.palette().hover : Color.Transparent)
        .onClick((): void => this.hidePaper())
      }
      .width('100%')
      .height(30)
      .translate({ x: this.contentOffsetX() })
      .animation({
        duration: this.enableAnimations ? (this.isPointerSessionActive() ? 130 : 170) : 0,
        curve: Curve.EaseOut
      })
      .backgroundColor(this.palette().paper)
      .border({ width: 1, color: this.isCollapsed ? this.palette().border : this.palette().accent })
      .borderRadius({ topLeft: 15, bottomLeft: 15, topRight: 0, bottomRight: 0 })
      .shadow(ShadowStyle.OUTER_DEFAULT_XS)
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .opacity(this.capsuleCollapseAllActive ? 0 : 1)
    .backgroundColor(Color.Transparent)
    .padding({ top: 8, bottom: 8 })
    .onHover((isHover: boolean): void => {
      this.hovered = isHover;
      if (!this.contextMenuOpen) {
        this.syncGeometry(true);
      }
    })
    .bindContextMenu(() => {
      this.CapsuleContextMenu()
    }, ResponseType.RightClick)
  }
}
