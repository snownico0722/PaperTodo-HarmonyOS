import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { capsuleSlotTop, normalizeCapsuleStartTopMargin } from '../common/CapsuleLayout';
import { DesktopShell } from '../common/DesktopShell';
import {
  CAPSULE_HEIGHT,
  CAPSULE_MAX_WIDTH,
  CAPSULE_MIN_WIDTH,
  CAPSULE_PLATFORM_MIN_WIDTH,
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
import { effectivePaperTitle } from '../common/PaperTitles';
import {
  MASTER_ACTION_RETRACT,
  isPaperEmpty,
  resolveMasterToggleAction
} from '../common/PaperInteractionPolicy';
import { formatText, tForSystem } from '../common/Strings';
import { ThemePalette, resolvePalette } from '../common/ThemePalette';

@Entry({ useSharedStorage: true })
@Component
struct MasterCapsule {
  @StorageLink('paperRevision') @Watch('onStoreChanged') paperRevision: number = 0;
  @StorageLink('capsuleAreaRevision') @Watch('onLayoutChanged') capsuleAreaRevision: number = 0;
  @StorageLink('capsuleCollapseAllActive') @Watch('onLayoutChanged')
  capsuleCollapseAllActive: boolean = false;
  @StorageLink('capsuleStartTop') @Watch('onLayoutChanged') capsuleStartTop: number = 48;
  @StorageLink('capsuleGap') @Watch('onLayoutChanged') capsuleGap: number = 4;
  @StorageLink('useCapsuleMode') @Watch('onStoreChanged') useCapsuleMode: boolean = true;
  @StorageLink('useDeepCapsuleMode') @Watch('onStoreChanged') useDeepCapsuleMode: boolean = true;
  @StorageLink('useMasterCapsule') @Watch('onStoreChanged') useMasterCapsule: boolean = true;
  @StorageLink('theme') theme: string = 'system';
  @StorageLink('colorScheme') colorScheme: string = 'warm';
  @StorageLink('overallFontScale') @Watch('onAppearanceChanged') overallFontScale: number = 1;
  @StorageLink('capsuleTextSize') @Watch('onAppearanceChanged') capsuleTextSize: string = 'medium';
  @StorageLink('capsuleTextBold') @Watch('onAppearanceChanged') capsuleTextBold: boolean = false;
  @StorageLink('uiLanguage') @Watch('onAppearanceChanged') uiLanguage: string = 'system';
  @StorageLink('systemLanguage') @Watch('onAppearanceChanged') systemLanguage: string = 'zh-CN';
  @StorageLink('systemColorMode') systemColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  @State memberCount: number = 0;
  @State hovered: boolean = false;
  @State contextMenuPapers: PaperData[] = [];
  @State contextMenuOpen: boolean = false;

  private layoutRunning: boolean = false;
  private layoutPending: boolean = false;
  private availableHeightVp: number = 0;
  private dragStartTop: number = 48;
  private dragMoved: boolean = false;
  private suppressClickUntil: number = 0;

  aboutToAppear(): void {
    this.refreshMembers();
  }

  aboutToDisappear(): void {
    PaperStore.flushNow();
  }

  private onStoreChanged(): void {
    this.refreshMembers();
  }

  private onLayoutChanged(): void {
    this.requestWindowLayout();
  }

  private onAppearanceChanged(): void {
    this.refreshContextMenuPapers();
    this.requestWindowLayout();
  }

  private refreshMembers(): void {
    const state: AppState = PaperStore.loadState();
    const members: PaperData[] = PaperStore.listEdgeCapsulePapers();
    this.refreshContextMenuPapers();
    this.memberCount = members.length;
    if (!state.useCapsuleMode || !state.useDeepCapsuleMode || !state.useMasterCapsule ||
      members.length === 0) {
      DesktopShell.syncCapsules(this.hostContext()).catch((error: Error): void => {
        console.warn('close stale master capsule failed: ' + error.message);
      });
      return;
    }
    this.requestWindowLayout();
  }

  private requestWindowLayout(): void {
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
      console.warn('layout master capsule failed: ' + error.message);
    });
  }

  private async runWindowLayoutLoop(): Promise<void> {
    while (this.layoutPending) {
      this.layoutPending = false;
      await this.syncWindowGeometry();
    }
  }

  private async syncWindowGeometry(): Promise<void> {
    const win: window.Window | undefined = AppStorage.get<window.Window>('masterCapsuleWindow');
    if (win === undefined || this.memberCount <= 0) {
      return;
    }
    let uiContext: UIContext;
    let targetDisplay: display.Display;
    try {
      uiContext = win.getUIContext();
      targetDisplay = display.getDefaultDisplaySync();
    } catch (error) {
      console.warn('query master capsule display failed: ' + String(error));
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

    const areaHeightVp: number = uiContext.px2vp(area.height);
    this.availableHeightVp = areaHeightVp;
    const normalizedTop: number = normalizeCapsuleStartTopMargin(this.capsuleStartTop, areaHeightVp,
      this.memberCount, this.capsuleGap, true);
    if (Math.abs(normalizedTop - this.capsuleStartTop) > 0.1) {
      PaperStore.setCapsuleStartTop(normalizedTop);
    }
    const slotTop: number = capsuleSlotTop(normalizedTop, 0, this.capsuleGap, false);
    const widthVp: number = this.calculateMasterWidth(uiContext);
    const widthPx: number = Math.round(uiContext.vp2px(widthVp));
    const heightPx: number = Math.round(uiContext.vp2px(CAPSULE_HEIGHT));
    const xPx: number = Math.round(area.left + area.width - widthPx);
    const yPx: number = Math.round(area.top + uiContext.vp2px(slotTop));
    try {
      await win.setWindowLimits({
        minWidth: Math.round(uiContext.vp2px(CAPSULE_PLATFORM_MIN_WIDTH)),
        minHeight: heightPx,
        maxWidth: Math.max(widthPx, area.width),
        maxHeight: Math.max(heightPx, area.height)
      }, true);
    } catch (error) {
      console.warn('set master capsule limits failed: ' + String(error));
    }
    try {
      await win.resize(widthPx, heightPx);
      await win.moveWindowTo(xPx, yPx);
    } catch (error) {
      console.warn('place master capsule failed: ' + String(error));
    }
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toggleQueueRetraction(): void {
    if (Date.now() < this.suppressClickUntil) {
      return;
    }
    if (this.memberCount <= 0) {
      return;
    }
    const action: string = resolveMasterToggleAction(this.capsuleCollapseAllActive);
    PaperStore.setCapsuleCollapseAllActive(action === MASTER_ACTION_RETRACT);
    DesktopShell.syncCapsules(this.hostContext()).catch((error: Error): void => {
      console.warn('sync capsule retraction failed: ' + error.message);
    });
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
    const nextTop: number = normalizeCapsuleStartTopMargin(this.dragStartTop + event.offsetY, areaHeight,
      this.memberCount, this.capsuleGap, true);
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
    DesktopShell.syncCapsules(this.hostContext()).catch((error: Error): void => {
      console.warn('sync moved capsule queue failed: ' + error.message);
    });
  }

  private createPaper(type: string): void {
    DesktopShell.createPaper(this.hostContext(), type).catch((error: Error): void => {
      console.warn('create paper from master capsule failed: ' + error.message);
    });
  }

  private showAll(): void {
    DesktopShell.showAll(this.hostContext()).catch((error: Error): void => {
      console.warn('show papers from master capsule failed: ' + error.message);
    });
  }

  private hideAll(): void {
    DesktopShell.hideAll(this.hostContext()).catch((error: Error): void => {
      console.warn('hide papers from master capsule failed: ' + error.message);
    });
  }

  private refreshContextMenuPapers(): void {
    // The Windows master capsule reuses the live tray menu. Keep the HarmonyOS
    // equivalent backed by a fresh store read instead of the queue-only member list.
    this.contextMenuPapers = PaperStore.listPapers();
  }

  private setContextMenuOpen(open: boolean): void {
    this.contextMenuOpen = open;
    if (open) {
      this.refreshContextMenuPapers();
    }
  }

  private setPaperVisibility(paperId: string, visible: boolean): void {
    this.setPaperVisibilityAsync(paperId, visible).catch((error: Error): void => {
      console.warn('toggle paper visibility from master capsule failed: ' + error.message);
    });
  }

  private async setPaperVisibilityAsync(paperId: string, visible: boolean): Promise<void> {
    const latest: PaperData | null = PaperStore.getPaper(paperId);
    if (latest === null || latest.isVisible === visible) {
      this.refreshContextMenuPapers();
      return;
    }
    if (!visible) {
      await DesktopShell.hidePaper(this.hostContext(), paperId);
    } else {
      PaperStore.setPaperVisible(paperId, true);
      await DesktopShell.startPaper(this.hostContext(), paperId);
      await DesktopShell.syncCapsules(this.hostContext());
    }
    this.refreshContextMenuPapers();
  }

  private deletePaper(paperId: string): void {
    const latest: PaperData | null = PaperStore.getPaper(paperId);
    if (latest === null) {
      this.refreshContextMenuPapers();
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
      primaryButton: {
        value: this.text('action.cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: this.text('action.deletePaper'),
        fontColor: this.palette().danger,
        action: (): void => this.performDeletePaper(paperId)
      }
    });
  }

  private performDeletePaper(paperId: string): void {
    PaperStore.flushNow();
    DesktopShell.deletePaper(this.hostContext(), paperId).then((): void => {
      this.refreshMembers();
    }).catch((error: Error): void => {
      console.warn('delete paper from master capsule failed: ' + error.message);
      this.refreshContextMenuPapers();
    });
  }

  private openSettings(): void {
    DesktopShell.openSettings(this.hostContext()).catch((error: Error): void => {
      console.warn('open settings from master capsule failed: ' + error.message);
    });
  }

  private exitApplication(): void {
    DesktopShell.exitApplication(this.hostContext()).catch((error: Error): void => {
      console.warn('exit PaperTodo from master capsule failed: ' + error.message);
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
    return this.capsuleTextBold ? FontWeight.Bold : FontWeight.Medium;
  }

  private stateGlyph(): string {
    return this.capsuleCollapseAllActive ? '▸' : '▾';
  }

  private expandedLabel(): string {
    return this.withoutStateGlyph(this.text('capsule.retractQueue'));
  }

  private currentLabel(): string {
    if (!this.capsuleCollapseAllActive) {
      return this.expandedLabel();
    }
    return this.withoutStateGlyph(
      formatText(this.text('capsule.retractedCount'), 'count', this.memberCount.toString()));
  }

  private withoutStateGlyph(value: string): string {
    if (value.startsWith('▾') || value.startsWith('▸')) {
      return value.substring(1).trim();
    }
    return value.trim();
  }

  private calculateMasterWidth(uiContext: UIContext): number {
    const glyphSize: number = Math.round(12 * this.overallFontScale * 10) / 10;
    const glyphWidth: number = Math.max(
      this.measureTextWidth(uiContext, '▾', glyphSize, FontWeight.Bold),
      this.measureTextWidth(uiContext, '▸', glyphSize, FontWeight.Bold));
    const labelWidth: number = Math.max(
      this.measureTextWidth(uiContext, this.expandedLabel(), this.fontSize(), this.fontWeight()),
      this.measureTextWidth(uiContext, this.currentLabel(), this.fontSize(), this.fontWeight()));
    const desired: number = Math.ceil(5 + glyphWidth + 4 + labelWidth + 5 + 1);
    return Math.max(CAPSULE_MIN_WIDTH, Math.min(CAPSULE_MAX_WIDTH, desired));
  }

  private measureTextWidth(uiContext: UIContext, value: string, fontSize: number,
    fontWeight: FontWeight): number {
    let width: number = value.length * fontSize;
    try {
      width = uiContext.px2vp(uiContext.getMeasureUtils().measureText({
        textContent: value,
        fontSize: fontSize,
        fontWeight: fontWeight
      }));
    } catch (error) {
      console.warn('measure master capsule text failed: ' + String(error));
    }
    return width;
  }

  private paperMenuLabel(paper: PaperData): string {
    const papers: PaperData[] = this.contextMenuPapers;
    const icon: string = paper.type === PAPER_TYPE_NOTE ? '✎' : '☑';
    return icon + '  ' + effectivePaperTitle(paper, papers, this.uiLanguage, this.systemLanguage);
  }

  private text(key: string): string {
    return tForSystem(this.uiLanguage, this.systemLanguage, key);
  }

  @Builder
  private PaperActionsMenu(paper: PaperData) {
    Menu() {
      MenuItem({ content: this.text(paper.isVisible ? 'action.hide' : 'action.show') })
        .onClick((): void => this.setPaperVisibility(paper.id, !paper.isVisible))
      MenuItem({ content: this.text('action.deletePaper') })
        .contentFontColor(this.palette().danger)
        .onClick((): void => this.deletePaper(paper.id))
    }
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
      ForEach(this.contextMenuPapers, (paper: PaperData) => {
        MenuItem({
          content: this.paperMenuLabel(paper),
          builder: () => {
            this.PaperActionsMenu(paper)
          }
        })
          .selected(paper.isVisible)
          .selectIcon(true)
      }, (paper: PaperData): string => paper.id)
    }
  }

  build() {
    Row({ space: 4 }) {
      Text(this.stateGlyph())
        .fontSize(Math.round(12 * this.overallFontScale * 10) / 10)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().text)
      Text(this.currentLabel())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
        .fontSize(this.fontSize())
        .fontWeight(this.fontWeight())
        .fontColor(this.palette().muted)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 5, right: 5 })
    .backgroundColor(this.hovered ? this.palette().input : this.palette().paper)
    .border({ width: 1, color: this.palette().border })
    .borderRadius({ topLeft: 23, bottomLeft: 23, topRight: 0, bottomRight: 0 })
    .onHover((isHover: boolean): void => {
      this.hovered = isHover;
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
    }, ResponseType.RightClick, {
      onWillAppear: (): void => this.setContextMenuOpen(true),
      onDisappear: (): void => this.setContextMenuOpen(false)
    })
  }
}
