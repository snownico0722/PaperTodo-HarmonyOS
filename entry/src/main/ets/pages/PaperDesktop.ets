import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { display, window } from '@kit.ArkUI';
import {
  CapsuleMetrics,
  createCapsuleMetrics,
  edgeCapsuleFullX,
  edgeCapsuleHiddenX,
  edgeCapsuleY
} from '../common/CapsuleGeometry';
import { CapsuleMotion } from '../common/CapsuleMotion';
import {
  CAPSULE_HEIGHT,
  CAPSULE_WIDTH,
  MARKDOWN_BASIC,
  MARKDOWN_ENHANCED,
  MARKDOWN_OFF,
  NOTE_MAX_LENGTH,
  PAPER_MIN_HEIGHT,
  PAPER_MIN_WIDTH,
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  PaperData,
  PaperItem,
  THEME_DARK,
  THEME_LIGHT,
  THEME_SYSTEM,
  TITLE_MAX_LENGTH,
  TODO_ITEM_MAX_LENGTH,
  TODO_PASTE_MAX_ITEMS,
  TODO_VISUAL_LARGE,
  TODO_VISUAL_MEDIUM,
  TODO_VISUAL_SMALL,
  TODO_VISUAL_XLARGE
} from '../common/Models';
import {
  MarkdownLine,
  MD_KIND_CODE,
  MD_KIND_HEADING,
  MD_KIND_QUOTE,
  MD_KIND_RULE,
  parseMarkdownLines
} from '../common/MarkdownLite';
import { PaperStore } from '../common/PaperStore';
import {
  createDisplayGeometry,
  DisplayGeometry,
  pxToVp,
  vpToPx
} from '../common/WindowGeometry';

const CAPSULE_REVEAL_MS: number = 110;
const CAPSULE_HIDE_MS: number = 130;
const CAPSULE_DRAG_THRESHOLD: number = 4;
const CAPSULE_CLICK_SUPPRESS_MS: number = 250;

@Entry({ useSharedStorage: true })
@Component
struct PaperDesktop {
  @LocalStorageProp('paperId') paperId: string = '';
  @LocalStorageLink('windowWidthVp') windowWidthVp: number = 320;
  @LocalStorageLink('windowHeightVp') windowHeightVp: number = 360;
  @StorageLink('theme') theme: string = THEME_SYSTEM;
  @StorageLink('markdownRenderMode') @Watch('onMarkdownModeChanged') markdownRenderMode: string = MARKDOWN_ENHANCED;
  @StorageLink('useCapsuleMode') useCapsuleMode: boolean = true;
  @StorageLink('useDeepCapsuleMode') @Watch('onDeepCapsuleModeChanged') useDeepCapsuleMode: boolean = true;
  @StorageLink('todoVisualSize') todoVisualSize: string = TODO_VISUAL_MEDIUM;
  @StorageLink('autoBottomCompleted') autoBottomCompleted: boolean = false;
  @StorageLink('capsuleGap') capsuleGap: number = 4;
  @StorageLink('paperRevision') @Watch('onPaperRevision') paperRevision: number = 0;
  @StorageLink('systemColorMode') systemColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  @State title: string = '';
  @State items: PaperItem[] = [];
  @State content: string = '';
  @State draft: string = '';
  @State isNoteBrowsing: boolean = true;
  @State alwaysOnTop: boolean = false;
  @State isCollapsed: boolean = false;
  @State markdownLines: MarkdownLine[] = [];
  @State deleteConfirm: boolean = false;
  @State showMoreActions: boolean = false;
  @State statusMessage: string = '';

  private paper: PaperData | null = null;
  private moveBaseX: number = 0;
  private moveBaseY: number = 0;
  private moveCurrentX: number = 0;
  private moveCurrentY: number = 0;
  private resizeBaseWidth: number = 0;
  private resizeBaseHeight: number = 0;
  private resizeCurrentWidth: number = 0;
  private resizeCurrentHeight: number = 0;
  private todoDragId: string = '';
  private todoDragStartIndex: number = -1;
  private todoDragCurrentIndex: number = -1;
  private capsuleMotion: CapsuleMotion = new CapsuleMotion();
  private capsuleHovered: boolean = false;
  private capsuleDragging: boolean = false;
  private capsuleMovedDuringDrag: boolean = false;
  private suppressCapsuleClickUntil: number = 0;

  aboutToAppear(): void {
    this.reloadPaper();
  }

  aboutToDisappear(): void {
    this.capsuleMotion.stop();
    PaperStore.flushNow();
  }

  private reloadPaper(): void {
    const loaded: PaperData | null = PaperStore.getPaper(this.paperId);
    if (loaded === null) {
      return;
    }
    this.paper = loaded;
    this.title = loaded.title;
    this.items = loaded.items.slice();
    this.content = loaded.content;
    this.alwaysOnTop = loaded.alwaysOnTop;
    this.isCollapsed = loaded.isCollapsed && this.useCapsuleMode;
    this.windowWidthVp = loaded.expandedWidth;
    this.windowHeightVp = loaded.expandedHeight;
    this.refreshMarkdown();
    if (this.isCollapsed) {
      setTimeout((): void => this.syncCollapsedWindow(false), 60);
    }
  }

  private onPaperRevision(): void {
    const latest: PaperData | null = PaperStore.getPaper(this.paperId);
    if (latest === null) {
      return;
    }
    const wasCollapsed: boolean = this.isCollapsed;
    this.paper = latest;
    this.alwaysOnTop = latest.alwaysOnTop;
    this.isCollapsed = latest.isCollapsed && this.useCapsuleMode;
    if (wasCollapsed && !this.isCollapsed) {
      this.restoreExpandedWindow();
      return;
    }
    if (this.isCollapsed && !this.capsuleDragging) {
      this.syncCollapsedWindow(this.capsuleHovered);
    }
  }

  private onMarkdownModeChanged(): void {
    this.refreshMarkdown();
  }

  private onDeepCapsuleModeChanged(): void {
    if (!this.isCollapsed || this.paper === null || this.capsuleDragging) {
      return;
    }
    if (!this.useDeepCapsuleMode) {
      const geometry: DisplayGeometry = this.displayGeometry();
      const metrics: CapsuleMetrics = this.capsuleMetrics();
      const index: number = PaperStore.getCollapsedIndex(this.paperId);
      this.paper.capsuleX = pxToVp(edgeCapsuleFullX(metrics), geometry.density);
      this.paper.capsuleY = pxToVp(edgeCapsuleY(index, metrics), geometry.density);
      PaperStore.updatePaper(this.paper, false);
    }
    this.syncCollapsedWindow(this.capsuleHovered);
  }

  private savePaper(immediate: boolean = false): void {
    if (this.paper === null) {
      return;
    }
    this.paper.title = this.title.slice(0, TITLE_MAX_LENGTH);
    this.paper.items = this.items;
    this.paper.content = this.content.slice(0, NOTE_MAX_LENGTH);
    this.paper.alwaysOnTop = this.alwaysOnTop;
    this.paper.isCollapsed = this.isCollapsed;
    PaperStore.updatePaper(this.paper, immediate);
  }

  private currentWindow(): window.Window | undefined {
    return AppStorage.get<window.Window>('paperWindow:' + this.paperId);
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private displayGeometry(): DisplayGeometry {
    const screen: display.Display = display.getDefaultDisplaySync();
    return createDisplayGeometry(screen.width, screen.height, screen.densityPixels);
  }

  private capsuleMetrics(): CapsuleMetrics {
    const screen: display.Display = display.getDefaultDisplaySync();
    return createCapsuleMetrics(screen.width, screen.height, screen.densityPixels, this.capsuleGap);
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

  private paperColor(): string {
    return this.isDark() ? '#2C2A24' : '#FFF4C7';
  }

  private textColor(): string {
    return this.isDark() ? '#F2EBD7' : '#28251F';
  }

  private mutedColor(): string {
    return this.isDark() ? '#AFA895' : '#746D5D';
  }

  private paperBorderColor(): string {
    return this.isDark() ? '#565044' : '#D8CDA5';
  }

  private inputColor(): string {
    return this.isDark() ? '#39362F' : '#FFFDF4';
  }

  private typeLabel(): string {
    return this.paper !== null && this.paper.type === PAPER_TYPE_NOTE ? '✎' : '☑';
  }

  private pinLabel(): string {
    return this.alwaysOnTop ? '📌' : '⌖';
  }

  private titleOrFallback(): string {
    if (this.title.trim().length > 0) {
      return this.title.trim();
    }
    if (this.paper !== null && this.paper.type === PAPER_TYPE_NOTE) {
      return '笔记';
    }
    const unfinished: number = this.unfinishedCount();
    return unfinished > 0 ? '待办 ' + unfinished.toString() : '待办';
  }

  private unfinishedCount(): number {
    let count: number = 0;
    for (let i: number = 0; i < this.items.length; i++) {
      if (!this.items[i].done) {
        count += 1;
      }
    }
    return count;
  }

  private completedCount(): number {
    let count: number = 0;
    for (let i: number = 0; i < this.items.length; i++) {
      if (this.items[i].done) {
        count += 1;
      }
    }
    return count;
  }

  private todoFontSize(): number {
    if (this.todoVisualSize === TODO_VISUAL_SMALL) {
      return 12;
    }
    if (this.todoVisualSize === TODO_VISUAL_LARGE) {
      return 16;
    }
    if (this.todoVisualSize === TODO_VISUAL_XLARGE) {
      return 18;
    }
    return 14;
  }

  private todoRowHeight(): number {
    if (this.todoVisualSize === TODO_VISUAL_SMALL) {
      return 34;
    }
    if (this.todoVisualSize === TODO_VISUAL_LARGE) {
      return 46;
    }
    if (this.todoVisualSize === TODO_VISUAL_XLARGE) {
      return 52;
    }
    return 40;
  }

  private toggleTopmost(): void {
    this.alwaysOnTop = !this.alwaysOnTop;
    this.savePaper(true);
    const win: window.Window | undefined = this.currentWindow();
    if (win !== undefined) {
      try {
        win.setWindowTopmost(this.alwaysOnTop).catch((error: BusinessError): void => {
          console.error('setWindowTopmost failed: ' + error.message);
        });
      } catch (error) {
        console.error('setWindowTopmost threw: ' + String(error));
      }
    }
  }

  private hidePaper(): void {
    if (this.paper === null) {
      return;
    }
    this.capsuleMotion.stop();
    this.paper.isVisible = false;
    this.savePaper(true);
    PaperStore.flushNow();
    this.hostContext().terminateSelf();
  }

  private deletePaper(): void {
    if (!this.deleteConfirm) {
      this.deleteConfirm = true;
      return;
    }
    this.capsuleMotion.stop();
    PaperStore.deletePaper(this.paperId);
    PaperStore.flushNow();
    this.hostContext().terminateSelf();
  }

  private createPaper(type: string): void {
    const created: PaperData | null = PaperStore.createPaper(type, this.paperId);
    if (created === null) {
      this.statusMessage = '无法新建纸片';
      return;
    }
    const want: Want = {
      bundleName: 'com.papertodo.app',
      moduleName: 'entry',
      abilityName: 'PaperAbility',
      parameters: {
        paperId: created.id,
        paperCommand: 'show'
      }
    };
    this.hostContext().startAbility(want).catch((error: BusinessError): void => {
      this.statusMessage = '新建纸片失败：' + error.message;
    });
  }

  private cycleTheme(): void {
    if (this.theme === THEME_SYSTEM) {
      PaperStore.setTheme(THEME_LIGHT);
    } else if (this.theme === THEME_LIGHT) {
      PaperStore.setTheme(THEME_DARK);
    } else {
      PaperStore.setTheme(THEME_SYSTEM);
    }
  }

  private cycleMarkdownMode(): void {
    if (this.markdownRenderMode === MARKDOWN_OFF) {
      PaperStore.setMarkdownMode(MARKDOWN_BASIC);
    } else if (this.markdownRenderMode === MARKDOWN_BASIC) {
      PaperStore.setMarkdownMode(MARKDOWN_ENHANCED);
    } else {
      PaperStore.setMarkdownMode(MARKDOWN_OFF);
    }
  }

  private markdownModeLabel(): string {
    if (this.markdownRenderMode === MARKDOWN_OFF) {
      return 'MD×';
    }
    if (this.markdownRenderMode === MARKDOWN_BASIC) {
      return 'MD';
    }
    return 'MD+';
  }

  private setCollapsed(collapsed: boolean): void {
    if (collapsed && !this.useCapsuleMode) {
      return;
    }
    if (this.paper === null) {
      return;
    }
    this.capsuleHovered = false;
    this.capsuleDragging = false;
    this.capsuleMovedDuringDrag = false;
    this.suppressCapsuleClickUntil = 0;
    this.capsuleMotion.reset();
    this.isCollapsed = collapsed;
    this.paper.isCollapsed = collapsed;
    this.savePaper(true);
    if (collapsed) {
      this.syncCollapsedWindow(false);
    } else {
      this.restoreExpandedWindow();
    }
  }

  private restoreExpandedWindow(): void {
    if (this.paper === null) {
      return;
    }
    this.capsuleMotion.reset();
    this.windowWidthVp = this.paper.expandedWidth;
    this.windowHeightVp = this.paper.expandedHeight;
    this.applyWindowRectVp(
      this.paper.expandedX,
      this.paper.expandedY,
      this.paper.expandedWidth,
      this.paper.expandedHeight
    );
  }

  private syncCollapsedWindow(hovered: boolean): void {
    if (!this.isCollapsed || this.paper === null) {
      return;
    }
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    const metrics: CapsuleMetrics = this.capsuleMetrics();
    this.safeResizePx(win, metrics.widthPx, metrics.heightPx);
    if (this.useDeepCapsuleMode) {
      this.animateEdgeCapsule(hovered, metrics);
    } else {
      this.moveFloatingCapsule(metrics);
    }
  }

  private animateEdgeCapsule(hovered: boolean, metrics: CapsuleMetrics = this.capsuleMetrics()): void {
    if (!this.isCollapsed || !this.useDeepCapsuleMode || this.paper === null) {
      return;
    }
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    const index: number = PaperStore.getCollapsedIndex(this.paperId);
    const targetY: number = edgeCapsuleY(index, metrics);
    const targetX: number = hovered ? edgeCapsuleFullX(metrics) : edgeCapsuleHiddenX(metrics);
    this.capsuleMotion.animateX(win, targetX, targetY, hovered ? CAPSULE_REVEAL_MS : CAPSULE_HIDE_MS);
  }

  private onCapsuleHover(isHover: boolean): void {
    this.capsuleHovered = isHover;
    if (this.isCollapsed && this.useDeepCapsuleMode && !this.capsuleDragging) {
      this.animateEdgeCapsule(isHover);
    }
  }

  private activateCapsule(): void {
    if (Date.now() >= this.suppressCapsuleClickUntil) {
      this.setCollapsed(false);
    }
  }

  private moveFloatingCapsule(metrics: CapsuleMetrics = this.capsuleMetrics()): void {
    if (this.paper === null) {
      return;
    }
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    const geometry: DisplayGeometry = this.displayGeometry();
    this.paper.capsuleX = this.clamp(this.paper.capsuleX, 0, Math.max(0, geometry.screenWidthVp - CAPSULE_WIDTH));
    this.paper.capsuleY = this.clamp(this.paper.capsuleY, 0, Math.max(0, geometry.screenHeightVp - CAPSULE_HEIGHT));
    PaperStore.updatePaper(this.paper, false);
    this.capsuleMotion.setPosition(
      win,
      vpToPx(this.paper.capsuleX, geometry.density),
      vpToPx(this.paper.capsuleY, geometry.density)
    );
  }

  private beginMove(): void {
    if (this.paper === null) {
      return;
    }
    this.capsuleMovedDuringDrag = false;
    if (this.isCollapsed && this.useDeepCapsuleMode) {
      const win: window.Window | undefined = this.currentWindow();
      const metrics: CapsuleMetrics = this.capsuleMetrics();
      const index: number = PaperStore.getCollapsedIndex(this.paperId);
      this.capsuleDragging = true;
      this.capsuleMotion.stop();
      this.moveBaseX = pxToVp(edgeCapsuleFullX(metrics), metrics.density);
      this.moveBaseY = pxToVp(edgeCapsuleY(index, metrics), metrics.density);
      this.moveCurrentX = this.moveBaseX;
      this.moveCurrentY = this.moveBaseY;
      if (win !== undefined) {
        this.capsuleMotion.setPosition(win, edgeCapsuleFullX(metrics), edgeCapsuleY(index, metrics));
      }
      return;
    }
    this.moveBaseX = this.isCollapsed ? this.paper.capsuleX : this.paper.expandedX;
    this.moveBaseY = this.isCollapsed ? this.paper.capsuleY : this.paper.expandedY;
    this.moveCurrentX = this.moveBaseX;
    this.moveCurrentY = this.moveBaseY;
  }

  private updateMove(event: GestureEvent): void {
    const paper: PaperData | null = this.paper;
    const win: window.Window | undefined = this.currentWindow();
    if (paper === null || win === undefined) {
      return;
    }
    if (this.isCollapsed &&
      (Math.abs(event.offsetX) >= CAPSULE_DRAG_THRESHOLD || Math.abs(event.offsetY) >= CAPSULE_DRAG_THRESHOLD)) {
      this.capsuleMovedDuringDrag = true;
    }

    const geometry: DisplayGeometry = this.displayGeometry();
    if (this.isCollapsed && this.useDeepCapsuleMode) {
      const metrics: CapsuleMetrics = this.capsuleMetrics();
      this.moveCurrentY = this.clamp(
        this.moveBaseY + event.offsetY,
        0,
        Math.max(0, geometry.screenHeightVp - CAPSULE_HEIGHT)
      );
      this.capsuleMotion.setPosition(win, edgeCapsuleFullX(metrics), vpToPx(this.moveCurrentY, geometry.density));
      return;
    }

    this.moveCurrentX = this.moveBaseX + event.offsetX;
    this.moveCurrentY = this.moveBaseY + event.offsetY;
    if (this.isCollapsed) {
      this.moveCurrentX = this.clamp(this.moveCurrentX, 0, Math.max(0, geometry.screenWidthVp - CAPSULE_WIDTH));
      this.moveCurrentY = this.clamp(this.moveCurrentY, 0, Math.max(0, geometry.screenHeightVp - CAPSULE_HEIGHT));
      this.capsuleMotion.setPosition(
        win,
        vpToPx(this.moveCurrentX, geometry.density),
        vpToPx(this.moveCurrentY, geometry.density)
      );
    } else {
      this.moveCurrentX = this.clamp(this.moveCurrentX, 0, Math.max(0, geometry.screenWidthVp - paper.expandedWidth));
      this.moveCurrentY = this.clamp(this.moveCurrentY, 0, Math.max(0, geometry.screenHeightVp - paper.expandedHeight));
      this.safeMoveVp(win, this.moveCurrentX, this.moveCurrentY, geometry);
    }
  }

  private endMove(): void {
    if (this.paper === null) {
      return;
    }
    if (this.isCollapsed && this.capsuleMovedDuringDrag) {
      this.suppressCapsuleClickUntil = Date.now() + CAPSULE_CLICK_SUPPRESS_MS;
    }
    this.capsuleMovedDuringDrag = false;

    if (this.isCollapsed) {
      if (this.useDeepCapsuleMode) {
        const desiredIndex: number = Math.max(0,
          Math.round((this.moveCurrentY - 20) / (CAPSULE_HEIGHT + this.capsuleGap)));
        PaperStore.moveCollapsedPaper(this.paperId, desiredIndex);
        this.capsuleDragging = false;
        this.syncCollapsedWindow(this.capsuleHovered);
      } else {
        this.paper.capsuleX = this.moveCurrentX;
        this.paper.capsuleY = this.moveCurrentY;
        PaperStore.updatePaper(this.paper, false);
      }
      return;
    }

    this.paper.expandedX = this.moveCurrentX;
    this.paper.expandedY = this.moveCurrentY;
    PaperStore.updatePaper(this.paper, false);
  }

  private beginResize(): void {
    if (this.paper === null || this.isCollapsed) {
      return;
    }
    this.resizeBaseWidth = this.paper.expandedWidth;
    this.resizeBaseHeight = this.paper.expandedHeight;
    this.resizeCurrentWidth = this.paper.expandedWidth;
    this.resizeCurrentHeight = this.paper.expandedHeight;
  }

  private updateResize(event: GestureEvent): void {
    if (this.paper === null || this.isCollapsed) {
      return;
    }
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    const geometry: DisplayGeometry = this.displayGeometry();
    this.resizeCurrentWidth = this.clamp(this.resizeBaseWidth + event.offsetX, PAPER_MIN_WIDTH, geometry.screenWidthVp);
    this.resizeCurrentHeight = this.clamp(this.resizeBaseHeight + event.offsetY, PAPER_MIN_HEIGHT, geometry.screenHeightVp);
    this.windowWidthVp = this.resizeCurrentWidth;
    this.windowHeightVp = this.resizeCurrentHeight;
    this.safeResizeVp(win, this.resizeCurrentWidth, this.resizeCurrentHeight, geometry);
  }

  private endResize(): void {
    if (this.paper === null || this.isCollapsed) {
      return;
    }
    this.paper.expandedWidth = this.resizeCurrentWidth;
    this.paper.expandedHeight = this.resizeCurrentHeight;
    PaperStore.updatePaper(this.paper, false);
  }

  private applyWindowRectVp(xVp: number, yVp: number, widthVp: number, heightVp: number): void {
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    const geometry: DisplayGeometry = this.displayGeometry();
    this.safeResizeVp(win, widthVp, heightVp, geometry);
    this.safeMoveVp(win, xVp, yVp, geometry);
  }

  private safeMoveVp(win: window.Window, xVp: number, yVp: number, geometry: DisplayGeometry): void {
    this.safeMovePx(win, vpToPx(xVp, geometry.density), vpToPx(yVp, geometry.density));
  }

  private safeResizeVp(win: window.Window, widthVp: number, heightVp: number, geometry: DisplayGeometry): void {
    this.safeResizePx(win, vpToPx(widthVp, geometry.density), vpToPx(heightVp, geometry.density));
  }

  private safeMovePx(win: window.Window, xPx: number, yPx: number): void {
    win.moveWindowTo(Math.max(0, Math.round(xPx)), Math.max(0, Math.round(yPx))).catch(
      (error: BusinessError): void => console.error('moveWindowTo failed: ' + error.message)
    );
  }

  private safeResizePx(win: window.Window, widthPx: number, heightPx: number): void {
    win.resize(Math.max(1, Math.round(widthPx)), Math.max(1, Math.round(heightPx))).catch(
      (error: BusinessError): void => console.error('resize failed: ' + error.message)
    );
  }

  private setTodoDone(id: string, done: boolean): void {
    let changed: PaperItem | null = null;
    const remaining: PaperItem[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      const item: PaperItem = this.items[i];
      if (item.id === id) {
        if (item.done === done) {
          return;
        }
        changed = { id: item.id, text: item.text, done: done, order: item.order };
      } else {
        remaining.push({ id: item.id, text: item.text, done: item.done, order: item.order });
      }
    }
    if (changed === null) {
      return;
    }

    if (!this.autoBottomCompleted) {
      const next: PaperItem[] = [];
      for (let i: number = 0; i < this.items.length; i++) {
        const item: PaperItem = this.items[i];
        next.push(item.id === id ? changed : { id: item.id, text: item.text, done: item.done, order: item.order });
      }
      this.items = this.renumberItems(next);
    } else if (done) {
      remaining.push(changed);
      this.items = this.renumberItems(remaining);
    } else {
      let insertion: number = remaining.length;
      for (let i: number = 0; i < remaining.length; i++) {
        if (remaining[i].done) {
          insertion = i;
          break;
        }
      }
      remaining.splice(insertion, 0, changed);
      this.items = this.renumberItems(remaining);
    }
    this.savePaper(false);
  }

  private updateTodoText(id: string, text: string): void {
    const safeText: string = text.slice(0, TODO_ITEM_MAX_LENGTH);
    const next: PaperItem[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      const item: PaperItem = this.items[i];
      next.push({ id: item.id, text: item.id === id ? safeText : item.text, done: item.done, order: i });
    }
    this.items = next;
    this.savePaper(false);
  }

  private deleteTodo(id: string): void {
    const next: PaperItem[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      if (this.items[i].id !== id) {
        const item: PaperItem = this.items[i];
        next.push({ id: item.id, text: item.text, done: item.done, order: next.length });
      }
    }
    if (next.length === 0) {
      next.push(PaperStore.createTodoItem('', 0));
    }
    this.items = next;
    this.savePaper(false);
  }

  private insertTodoAfter(id: string): void {
    const next: PaperItem[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      const item: PaperItem = this.items[i];
      next.push({ id: item.id, text: item.text, done: item.done, order: next.length });
      if (item.id === id) {
        next.push(PaperStore.createTodoItem('', next.length));
      }
    }
    this.items = next;
    this.savePaper(false);
  }

  private clearCompleted(): void {
    const next: PaperItem[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      if (!this.items[i].done) {
        next.push({ id: this.items[i].id, text: this.items[i].text, done: false, order: next.length });
      }
    }
    if (next.length === 0) {
      next.push(PaperStore.createTodoItem('', 0));
    }
    this.items = next;
    this.savePaper(false);
  }

  private indexOfTodo(id: string): number {
    for (let i: number = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  private beginTodoDrag(id: string): void {
    const index: number = this.indexOfTodo(id);
    if (index < 0) {
      return;
    }
    this.todoDragId = id;
    this.todoDragStartIndex = index;
    this.todoDragCurrentIndex = index;
  }

  private updateTodoDrag(event: GestureEvent): void {
    if (this.todoDragStartIndex < 0 || this.todoDragCurrentIndex < 0) {
      return;
    }
    const delta: number = Math.round(event.offsetY / this.todoRowHeight());
    const target: number = Math.max(0, Math.min(this.items.length - 1, this.todoDragStartIndex + delta));
    if (target === this.todoDragCurrentIndex) {
      return;
    }
    const next: PaperItem[] = this.items.slice();
    const moved: PaperItem[] = next.splice(this.todoDragCurrentIndex, 1);
    next.splice(target, 0, moved[0]);
    this.items = this.renumberItems(next);
    this.todoDragCurrentIndex = target;
  }

  private endTodoDrag(): void {
    if (this.todoDragStartIndex >= 0 && this.todoDragCurrentIndex >= 0 &&
      this.todoDragStartIndex !== this.todoDragCurrentIndex) {
      this.savePaper(false);
    }
    this.todoDragId = '';
    this.todoDragStartIndex = -1;
    this.todoDragCurrentIndex = -1;
  }

  private renumberItems(items: PaperItem[]): PaperItem[] {
    const next: PaperItem[] = [];
    for (let i: number = 0; i < items.length; i++) {
      next.push({ id: items[i].id, text: items[i].text, done: items[i].done, order: i });
    }
    return next;
  }

  private addDraftTodos(): void {
    const raw: string = this.draft.replace(/\r\n/g, '\n');
    const lines: string[] = raw.split('\n');
    const next: PaperItem[] = this.items.slice();
    let added: number = 0;
    for (let i: number = 0; i < lines.length && added < TODO_PASTE_MAX_ITEMS; i++) {
      const cleaned: string = this.cleanTodoPrefix(lines[i]).trim().slice(0, TODO_ITEM_MAX_LENGTH);
      if (cleaned.length > 0) {
        next.push(PaperStore.createTodoItem(cleaned, next.length));
        added += 1;
      }
    }
    if (added === 0 && raw.trim().length === 0) {
      next.push(PaperStore.createTodoItem('', next.length));
    }
    this.items = this.renumberItems(next);
    this.draft = '';
    this.savePaper(false);
  }

  private cleanTodoPrefix(text: string): string {
    let result: string = text.trim();
    result = result.replace(/^[-*+]\s+/, '');
    result = result.replace(/^\d+[.、]\s*/, '');
    result = result.replace(/^[-*+]\s*\[[ xX]\]\s*/, '');
    result = result.replace(/^[☐☑✓]\s*/, '');
    return result;
  }

  private updateNote(value: string): void {
    this.content = value.slice(0, NOTE_MAX_LENGTH);
    this.savePaper(false);
  }

  private toggleNoteBrowse(): void {
    this.isNoteBrowsing = !this.isNoteBrowsing;
    this.refreshMarkdown();
  }

  private refreshMarkdown(): void {
    this.markdownLines = parseMarkdownLines(this.content, this.markdownRenderMode);
  }

  private appendMarkdown(snippet: string): void {
    let next: string = this.content;
    if (next.length > 0 && !next.endsWith('\n')) {
      next += '\n';
    }
    this.content = (next + snippet).slice(0, NOTE_MAX_LENGTH);
    this.savePaper(false);
  }

  private headingSize(level: number): number {
    return level <= 1 ? 25 : (level === 2 ? 21 : (level === 3 ? 18 : 16));
  }

  private clamp(value: number, minValue: number, maxValue: number): number {
    return Math.max(minValue, Math.min(value, maxValue));
  }

  @Builder
  private HeaderBar() {
    Row({ space: 2 }) {
      Text('⋮⋮')
        .width(24)
        .height(32)
        .fontSize(15)
        .fontColor(this.mutedColor())
        .textAlign(TextAlign.Center)
        .gesture(
          PanGesture({ direction: PanDirection.All })
            .onActionStart((): void => this.beginMove())
            .onActionUpdate((event: GestureEvent): void => this.updateMove(event))
            .onActionEnd((): void => this.endMove())
        )

      Button(this.pinLabel())
        .width(28)
        .height(30)
        .fontSize(12)
        .fontColor(this.textColor())
        .backgroundColor(Color.Transparent)
        .onClick((): void => this.toggleTopmost())

      TextInput({
        text: this.title,
        placeholder: this.paper !== null && this.paper.type === PAPER_TYPE_NOTE ? '笔记' : '待办'
      })
        .layoutWeight(1)
        .height(30)
        .fontSize(13)
        .fontColor(this.textColor())
        .placeholderColor(this.mutedColor())
        .backgroundColor(Color.Transparent)
        .padding(0)
        .onChange((value: string): void => {
          this.title = value.slice(0, TITLE_MAX_LENGTH);
          this.savePaper(false);
        })

      if (this.paper !== null && this.paper.type === PAPER_TYPE_NOTE) {
        Button(this.isNoteBrowsing ? '编' : '览')
          .width(28)
          .height(30)
          .fontSize(10)
          .fontColor(this.textColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.toggleNoteBrowse())
      }

      if (this.useCapsuleMode) {
        Button('▁')
          .width(28)
          .height(30)
          .fontSize(12)
          .fontColor(this.textColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.setCollapsed(true))
      }

      Button('⋯')
        .width(28)
        .height(30)
        .fontSize(14)
        .fontColor(this.textColor())
        .backgroundColor(Color.Transparent)
        .onClick((): void => {
          this.showMoreActions = !this.showMoreActions;
        })

      Button('—')
        .width(26)
        .height(30)
        .fontSize(12)
        .fontColor(this.mutedColor())
        .backgroundColor(Color.Transparent)
        .onClick((): void => this.hidePaper())

      Button(this.deleteConfirm ? '删' : '×')
        .width(26)
        .height(30)
        .fontSize(12)
        .fontColor(this.deleteConfirm ? '#B42318' : this.mutedColor())
        .backgroundColor(Color.Transparent)
        .onClick((): void => this.deletePaper())
    }
    .width('100%')
    .height(34)
    .padding({ left: 4, right: 4 })
  }

  @Builder
  private MoreActionsBar() {
    Scroll() {
      Row({ space: 4 }) {
        if (this.paper !== null && this.paper.type === PAPER_TYPE_NOTE) {
          Button(this.markdownModeLabel())
            .height(28)
            .fontSize(10)
            .onClick((): void => this.cycleMarkdownMode())
        }
        Button('主题')
          .height(28)
          .fontSize(10)
          .onClick((): void => this.cycleTheme())
        Button('新待办')
          .height(28)
          .fontSize(10)
          .onClick((): void => this.createPaper(PAPER_TYPE_TODO))
        Button('新笔记')
          .height(28)
          .fontSize(10)
          .onClick((): void => this.createPaper(PAPER_TYPE_NOTE))
      }
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .height(34)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }

  @Builder
  private TodoBody() {
    Column() {
      Row() {
        Text(this.completedCount().toString() + '/' + this.items.length.toString())
          .fontSize(11)
          .fontColor(this.mutedColor())
        Blank()
        Button('清已完成')
          .height(28)
          .fontSize(10)
          .fontColor(this.mutedColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.clearCompleted())
      }
      .width('100%')
      .height(30)
      .padding({ left: 10, right: 8 })

      List({ space: 2 }) {
        ForEach(this.items, (item: PaperItem) => {
          ListItem() {
            Row({ space: 6 }) {
              Checkbox({ name: item.id, group: 'papertodo' })
                .select(item.done)
                .width(24)
                .height(24)
                .onChange((checked: boolean): void => this.setTodoDone(item.id, checked))

              TextInput({ text: item.text, placeholder: '待办事项' })
                .layoutWeight(1)
                .height(this.todoRowHeight() - 6)
                .fontSize(this.todoFontSize())
                .fontColor(item.done ? this.mutedColor() : this.textColor())
                .placeholderColor(this.mutedColor())
                .backgroundColor(Color.Transparent)
                .padding(0)
                .onChange((value: string): void => this.updateTodoText(item.id, value))
                .onSubmit((): void => this.insertTodoAfter(item.id))

              Text('≡')
                .width(26)
                .height(this.todoRowHeight() - 4)
                .fontSize(16)
                .fontColor(this.mutedColor())
                .textAlign(TextAlign.Center)
                .gesture(
                  PanGesture({ direction: PanDirection.Vertical })
                    .onActionStart((): void => this.beginTodoDrag(item.id))
                    .onActionUpdate((event: GestureEvent): void => this.updateTodoDrag(event))
                    .onActionEnd((): void => this.endTodoDrag())
                )

              Button('×')
                .width(24)
                .height(28)
                .fontSize(12)
                .fontColor(this.mutedColor())
                .backgroundColor(Color.Transparent)
                .onClick((): void => this.deleteTodo(item.id))
            }
            .width('100%')
            .height(this.todoRowHeight())
            .padding({ left: 8, right: 4 })
          }
        }, (item: PaperItem): string => item.id)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)

      Row({ space: 6 }) {
        TextInput({ text: this.draft, placeholder: '添加待办；可粘贴多行' })
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .fontColor(this.textColor())
          .placeholderColor(this.mutedColor())
          .backgroundColor(this.inputColor())
          .border({ width: 1, color: this.paperBorderColor() })
          .borderRadius(8)
          .onChange((value: string): void => {
            this.draft = value;
          })
          .onSubmit((): void => this.addDraftTodos())
        Button('+')
          .width(38)
          .height(38)
          .fontSize(18)
          .onClick((): void => this.addDraftTodos())
      }
      .width('100%')
      .padding({ left: 8, right: 8, bottom: 8 })
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private MarkdownToolbar() {
    Row({ space: 4 }) {
      Button('B').onClick((): void => this.appendMarkdown('**文本**'))
      Button('I').onClick((): void => this.appendMarkdown('*文本*'))
      Button('H').onClick((): void => this.appendMarkdown('## 标题'))
      Button('>').onClick((): void => this.appendMarkdown('> 引用'))
      Button('•').onClick((): void => this.appendMarkdown('- 列表'))
    }
    .width('100%')
    .height(34)
    .padding({ left: 8, right: 8 })
  }

  @Builder
  private NoteBody() {
    Column() {
      if (!this.isNoteBrowsing) {
        this.MarkdownToolbar()
        TextArea({ text: this.content, placeholder: '写点什么…' })
          .layoutWeight(1)
          .width('100%')
          .fontSize(14)
          .fontColor(this.textColor())
          .placeholderColor(this.mutedColor())
          .backgroundColor(Color.Transparent)
          .padding(12)
          .onChange((value: string): void => this.updateNote(value))
      } else if (this.markdownRenderMode === MARKDOWN_OFF) {
        Scroll() {
          Text(this.content.length > 0 ? this.content : '点击“编”开始记录')
            .width('100%')
            .fontSize(14)
            .fontColor(this.content.length > 0 ? this.textColor() : this.mutedColor())
            .padding(12)
        }
        .layoutWeight(1)
        .width('100%')
        .onClick((): void => this.toggleNoteBrowse())
      } else {
        Scroll() {
          Column({ space: 3 }) {
            ForEach(this.markdownLines, (line: MarkdownLine) => {
              if (line.kind === MD_KIND_RULE) {
                Divider().color(this.paperBorderColor()).margin({ top: 6, bottom: 6 })
              } else if (line.kind === MD_KIND_HEADING) {
                Text(line.text)
                  .width('100%')
                  .fontSize(this.headingSize(line.level))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.textColor())
              } else if (line.kind === MD_KIND_QUOTE) {
                Text('│ ' + line.text)
                  .width('100%')
                  .fontSize(14)
                  .fontColor(this.mutedColor())
              } else if (line.kind === MD_KIND_CODE) {
                Text(line.text)
                  .width('100%')
                  .fontSize(13)
                  .fontColor(this.textColor())
                  .backgroundColor(this.inputColor())
                  .padding(6)
              } else {
                Text(line.text.length > 0 ? line.text : ' ')
                  .width('100%')
                  .fontSize(14)
                  .fontColor(this.textColor())
              }
            }, (line: MarkdownLine): string => line.id)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(12)
        }
        .layoutWeight(1)
        .width('100%')
        .onClick((): void => this.toggleNoteBrowse())
      }
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private ResizeHandle() {
    Row() {
      Blank()
      Text('◢')
        .width(28)
        .height(24)
        .fontSize(12)
        .fontColor(this.mutedColor())
        .textAlign(TextAlign.Center)
        .gesture(
          PanGesture({ direction: PanDirection.All })
            .onActionStart((): void => this.beginResize())
            .onActionUpdate((event: GestureEvent): void => this.updateResize(event))
            .onActionEnd((): void => this.endResize())
        )
    }
    .width('100%')
    .height(24)
  }

  @Builder
  private CapsuleBody() {
    Row({ space: 4 }) {
      Text(this.typeLabel())
        .fontSize(13)
        .fontColor(this.textColor())
      Text(this.titleOrFallback())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontSize(12)
        .fontColor(this.textColor())
      Text('›')
        .fontSize(16)
        .fontColor(this.mutedColor())
    }
    .width('100%')
    .height('100%')
    .padding({ left: 10, right: 8 })
    .backgroundColor(this.paperColor())
    .border({ width: 1, color: this.paperBorderColor() })
    .borderRadius(22)
    .onHover((isHover: boolean): void => this.onCapsuleHover(isHover))
    .onClick((): void => this.activateCapsule())
    .gesture(
      PanGesture({ direction: PanDirection.All })
        .onActionStart((): void => this.beginMove())
        .onActionUpdate((event: GestureEvent): void => this.updateMove(event))
        .onActionEnd((): void => this.endMove())
    )
  }

  build() {
    if (this.isCollapsed) {
      this.CapsuleBody()
    } else {
      Column() {
        this.HeaderBar()
        if (this.showMoreActions) {
          this.MoreActionsBar()
        }
        Divider().color(this.paperBorderColor()).opacity(0.45)
        if (this.statusMessage.length > 0) {
          Text(this.statusMessage)
            .width('100%')
            .fontSize(10)
            .fontColor(this.mutedColor())
            .padding({ left: 10, right: 10, top: 4 })
        }
        if (this.paper !== null && this.paper.type === PAPER_TYPE_NOTE) {
          this.NoteBody()
        } else {
          this.TodoBody()
        }
        this.ResizeHandle()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.paperColor())
      .border({ width: 1, color: this.paperBorderColor() })
      .borderRadius(14)
    }
  }
}
