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
  MD_KIND_BULLET,
  MD_KIND_CODE,
  MD_KIND_HEADING,
  MD_KIND_ORDERED,
  MD_KIND_QUOTE,
  MD_KIND_RULE,
  parseMarkdownLines
} from '../common/MarkdownLite';
import { PaperStore } from '../common/PaperStore';

const CAPSULE_REVEAL_MS: number = 110;
const CAPSULE_HIDE_MS: number = 130;
const CAPSULE_DRAG_THRESHOLD: number = 4;

@Entry({ useSharedStorage: true })
@Component
struct Paper {
  @LocalStorageProp('paperId') paperId: string = '';
  @StorageLink('theme') theme: string = THEME_SYSTEM;
  @StorageLink('markdownRenderMode') @Watch('onMarkdownModeChanged') markdownRenderMode: string = MARKDOWN_ENHANCED;
  @StorageLink('useCapsuleMode') useCapsuleMode: boolean = true;
  @StorageLink('useDeepCapsuleMode') useDeepCapsuleMode: boolean = true;
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
  @State layoutWidth: number = 320;
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
  private capsuleMotion: CapsuleMotion = new CapsuleMotion();
  private capsuleHovered: boolean = false;
  private capsuleDragging: boolean = false;
  private capsuleMovedDuringDrag: boolean = false;

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
    this.items = loaded.items;
    this.content = loaded.content;
    this.alwaysOnTop = loaded.alwaysOnTop;
    this.isCollapsed = loaded.isCollapsed && this.useCapsuleMode;
    this.layoutWidth = loaded.expandedWidth;
    this.refreshMarkdown();
    if (this.isCollapsed) {
      setTimeout((): void => this.syncCollapsedWindow(false), 100);
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
      win.setWindowTopmost(this.alwaysOnTop).catch((error: BusinessError): void => {
        console.error('setWindowTopmost failed: ' + error.message);
      });
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
      this.statusMessage = '无法继续新建纸片：已达数量上限或数据处于保护状态';
      return;
    }
    const want: Want = {
      bundleName: 'com.snownico.papertodo',
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

  private capsuleMetrics(): CapsuleMetrics {
    const screen: display.Display = display.getDefaultDisplaySync();
    return createCapsuleMetrics(screen.width, screen.height, screen.densityPixels, this.capsuleGap);
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
    this.capsuleMotion.stop();
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
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    this.capsuleMotion.stop();
    this.layoutWidth = this.paper.expandedWidth;
    win.resize(Math.round(this.paper.expandedWidth), Math.round(this.paper.expandedHeight));
    win.moveWindowTo(Math.round(this.paper.expandedX), Math.round(this.paper.expandedY));
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
    win.resize(metrics.widthPx, metrics.heightPx);
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
    const duration: number = hovered ? CAPSULE_REVEAL_MS : CAPSULE_HIDE_MS;
    this.capsuleMotion.animateX(win, targetX, targetY, duration);
  }

  private onCapsuleHover(isHover: boolean): void {
    this.capsuleHovered = isHover;
    if (!this.isCollapsed || !this.useDeepCapsuleMode || this.capsuleDragging) {
      return;
    }
    this.animateEdgeCapsule(isHover);
  }

  private activateCapsule(): void {
    if (this.capsuleMovedDuringDrag) {
      this.capsuleMovedDuringDrag = false;
      return;
    }
    this.setCollapsed(false);
  }

  private moveFloatingCapsule(metrics: CapsuleMetrics = this.capsuleMetrics()): void {
    if (this.paper === null) {
      return;
    }
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    this.capsuleMotion.stop();
    this.paper.capsuleX = this.clamp(this.paper.capsuleX, 0,
      Math.max(0, metrics.screenWidthPx - metrics.widthPx));
    this.paper.capsuleY = this.clamp(this.paper.capsuleY, 0,
      Math.max(0, metrics.screenHeightPx - metrics.heightPx));
    PaperStore.updatePaper(this.paper, false);
    this.capsuleMotion.setPosition(win, this.paper.capsuleX, this.paper.capsuleY);
  }

  private beginMove(): void {
    if (this.paper === null) {
      return;
    }
    if (this.isCollapsed) {
      this.capsuleMovedDuringDrag = false;
      if (this.useDeepCapsuleMode) {
        const win: window.Window | undefined = this.currentWindow();
        const metrics: CapsuleMetrics = this.capsuleMetrics();
        const index: number = PaperStore.getCollapsedIndex(this.paperId);
        this.capsuleDragging = true;
        this.capsuleMotion.stop();
        this.moveBaseX = edgeCapsuleFullX(metrics);
        this.moveBaseY = edgeCapsuleY(index, metrics);
        this.moveCurrentX = this.moveBaseX;
        this.moveCurrentY = this.moveBaseY;
        if (win !== undefined) {
          this.capsuleMotion.setPosition(win, this.moveBaseX, this.moveBaseY);
        }
        return;
      }
      this.moveBaseX = this.paper.capsuleX;
      this.moveBaseY = this.paper.capsuleY;
    } else {
      this.moveBaseX = this.paper.expandedX;
      this.moveBaseY = this.paper.expandedY;
    }
    this.moveCurrentX = this.moveBaseX;
    this.moveCurrentY = this.moveBaseY;
  }

  private updateMove(event: GestureEvent): void {
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }

    if (this.isCollapsed &&
      (Math.abs(event.offsetX) >= CAPSULE_DRAG_THRESHOLD || Math.abs(event.offsetY) >= CAPSULE_DRAG_THRESHOLD)) {
      this.capsuleMovedDuringDrag = true;
    }

    if (this.isCollapsed && this.useDeepCapsuleMode) {
      const metrics: CapsuleMetrics = this.capsuleMetrics();
      this.moveCurrentX = edgeCapsuleFullX(metrics);
      this.moveCurrentY = this.clamp(
        Math.round(this.moveBaseY + event.offsetY),
        0,
        Math.max(0, metrics.screenHeightPx - metrics.heightPx)
      );
      this.capsuleMotion.setPosition(win, this.moveCurrentX, this.moveCurrentY);
      return;
    }

    this.moveCurrentX = Math.round(this.moveBaseX + event.offsetX);
    this.moveCurrentY = Math.round(this.moveBaseY + event.offsetY);
    win.moveWindowTo(this.moveCurrentX, this.moveCurrentY);
  }

  private endMove(): void {
    if (this.paper === null) {
      return;
    }
    if (this.isCollapsed) {
      if (this.useDeepCapsuleMode) {
        const metrics: CapsuleMetrics = this.capsuleMetrics();
        const desiredIndex: number = Math.max(0,
          Math.round((this.moveCurrentY - metrics.topPx) / (metrics.heightPx + metrics.gapPx)));
        PaperStore.moveCollapsedPaper(this.paperId, desiredIndex);
        const latest: PaperData | null = PaperStore.getPaper(this.paperId);
        if (latest !== null) {
          this.paper = latest;
        }
        this.capsuleDragging = false;
        this.syncCollapsedWindow(this.capsuleHovered);
      } else {
        this.paper.capsuleX = this.moveCurrentX;
        this.paper.capsuleY = this.moveCurrentY;
        this.moveFloatingCapsule();
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
    if (this.isCollapsed) {
      return;
    }
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    this.resizeCurrentWidth = Math.max(PAPER_MIN_WIDTH, Math.round(this.resizeBaseWidth + event.offsetX));
    this.resizeCurrentHeight = Math.max(PAPER_MIN_HEIGHT, Math.round(this.resizeBaseHeight + event.offsetY));
    this.layoutWidth = this.resizeCurrentWidth;
    win.resize(this.resizeCurrentWidth, this.resizeCurrentHeight);
  }

  private endResize(): void {
    if (this.paper === null || this.isCollapsed) {
      return;
    }
    this.paper.expandedWidth = this.resizeCurrentWidth;
    this.paper.expandedHeight = this.resizeCurrentHeight;
    PaperStore.updatePaper(this.paper, false);
  }

  private toggleTodo(id: string): void {
    let changed: PaperItem | null = null;
    const remaining: PaperItem[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      const item: PaperItem = this.items[i];
      if (item.id === id) {
        changed = { id: item.id, text: item.text, done: !item.done, order: item.order };
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
    } else if (changed.done) {
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
        const item: PaperItem = this.items[i];
        next.push({ id: item.id, text: item.text, done: false, order: next.length });
      }
    }
    if (next.length === 0) {
      next.push(PaperStore.createTodoItem('', 0));
    }
    this.items = next;
    this.savePaper(false);
  }

  private moveTodo(from: number, to: number): void {
    if (from < 0 || from >= this.items.length || to < 0 || to >= this.items.length || from === to) {
      return;
    }
    const next: PaperItem[] = this.items.slice();
    const moved: PaperItem[] = next.splice(from, 1);
    next.splice(to, 0, moved[0]);
    this.items = this.renumberItems(next);
    this.savePaper(false);
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
      if (cleaned.length === 0) {
        continue;
      }
      next.push(PaperStore.createTodoItem(cleaned, next.length));
      added += 1;
    }
    if (added === 0 && raw.trim().length === 0) {
      next.push(PaperStore.createTodoItem('', next.length));
    }
    if (lines.length > TODO_PASTE_MAX_ITEMS) {
      this.statusMessage = '单次最多添加 ' + TODO_PASTE_MAX_ITEMS.toString() + ' 条待办';
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
    if (value.length > NOTE_MAX_LENGTH) {
      this.statusMessage = '笔记已达到安全长度上限';
    }
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
    next += snippet;
    this.content = next.slice(0, NOTE_MAX_LENGTH);
    this.savePaper(false);
  }

  private headingSize(level: number): number {
    if (level <= 1) {
      return 26;
    }
    if (level === 2) {
      return 22;
    }
    if (level === 3) {
      return 19;
    }
    return 16;
  }

  private clamp(value: number, minValue: number, maxValue: number): number {
    return Math.max(minValue, Math.min(value, maxValue));
  }

  @Builder
  private HeaderBar() {
    Row({ space: 4 }) {
      Text('⋮⋮')
        .width(26)
        .height(30)
        .fontSize(16)
        .fontColor(this.mutedColor())
        .textAlign(TextAlign.Center)
        .gesture(
          PanGesture({ direction: PanDirection.All })
            .onActionStart((): void => this.beginMove())
            .onActionUpdate((event: GestureEvent): void => this.updateMove(event))
            .onActionEnd((): void => this.endMove())
        )

      Button(this.pinLabel())
        .width(30)
        .height(30)
        .fontSize(13)
        .fontColor(this.textColor())
        .backgroundColor(Color.Transparent)
        .onClick((): void => this.toggleTopmost())

      TextInput({
        text: this.title,
        placeholder: this.paper !== null && this.paper.type === PAPER_TYPE_NOTE ? '笔记' : '待办'
      })
        .layoutWeight(1)
        .height(30)
        .fontSize(14)
        .fontColor(this.textColor())
        .placeholderColor(this.mutedColor())
        .backgroundColor(Color.Transparent)
        .padding(0)
        .onChange((value: string): void => {
          this.title = value.slice(0, TITLE_MAX_LENGTH);
          this.savePaper(false);
        })

      if (this.paper !== null && this.paper.type === PAPER_TYPE_NOTE && this.layoutWidth >= 320) {
        Button(this.isNoteBrowsing ? '编' : '览')
          .width(30)
          .height(30)
          .fontSize(12)
          .fontColor(this.textColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.toggleNoteBrowse())
      }
      if (this.paper !== null && this.paper.type === PAPER_TYPE_NOTE && this.layoutWidth >= 380) {
        Button(this.markdownModeLabel())
          .width(38)
          .height(30)
          .fontSize(10)
          .fontColor(this.textColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.cycleMarkdownMode())
      }
      if (this.layoutWidth >= 430) {
        Button('◐')
          .width(30)
          .height(30)
          .fontSize(12)
          .fontColor(this.textColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.cycleTheme())
      }
      if (this.useCapsuleMode && this.layoutWidth >= 470) {
        Button('▁')
          .width(30)
          .height(30)
          .fontSize(12)
          .fontColor(this.textColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.setCollapsed(true))
      }
      if (this.layoutWidth >= 540) {
        Button('☑+')
          .width(34)
          .height(30)
          .fontSize(10)
          .fontColor(this.textColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.createPaper(PAPER_TYPE_TODO))
      }
      if (this.layoutWidth >= 580) {
        Button('✎+')
          .width(34)
          .height(30)
          .fontSize(10)
          .fontColor(this.textColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.createPaper(PAPER_TYPE_NOTE))
      }
      if (this.layoutWidth < 580) {
        Button('⋯')
          .width(30)
          .height(30)
          .fontSize(14)
          .fontColor(this.textColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.showMoreActions = !this.showMoreActions;
          })
      }

      Button('—')
        .width(28)
        .height(30)
        .fontSize(12)
        .fontColor(this.mutedColor())
        .backgroundColor(Color.Transparent)
        .onClick((): void => this.hidePaper())

      Button(this.deleteConfirm ? '确认' : '×')
        .width(this.deleteConfirm ? 42 : 28)
        .height(30)
        .fontSize(this.deleteConfirm ? 10 : 14)
        .fontColor(this.deleteConfirm ? '#B42318' : this.mutedColor())
        .backgroundColor(Color.Transparent)
        .onClick((): void => this.deletePaper())
    }
    .width('100%')
    .height(34)
    .padding({ left: 6, right: 6 })
  }

  @Builder
  private MoreActionsBar() {
    Scroll() {
      Row({ space: 4 }) {
        if (this.paper !== null && this.paper.type === PAPER_TYPE_NOTE) {
          Button(this.isNoteBrowsing ? '编辑' : '浏览')
            .height(28)
            .fontSize(10)
            .onClick((): void => this.toggleNoteBrowse())
          Button(this.markdownModeLabel())
            .height(28)
            .fontSize(10)
            .onClick((): void => this.cycleMarkdownMode())
        }
        Button('主题')
          .height(28)
          .fontSize(10)
          .onClick((): void => this.cycleTheme())
        if (this.useCapsuleMode) {
          Button('折叠')
            .height(28)
            .fontSize(10)
            .onClick((): void => this.setCollapsed(true))
        }
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
              Button(item.done ? '✓' : '')
                .width(26)
                .height(26)
                .fontSize(13)
                .fontColor(item.done ? this.paperColor() : this.textColor())
                .backgroundColor(item.done ? this.textColor() : Color.Transparent)
                .border({ width: 1, color: this.paperBorderColor() })
                .borderRadius(7)
                .onClick((): void => this.toggleTodo(item.id))

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
                .width(22)
                .fontSize(15)
                .fontColor(this.mutedColor())
                .textAlign(TextAlign.Center)

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
          .editable(true)
        }, (item: PaperItem): string => item.id)
          .onMove((from: number, to: number): void => this.moveTodo(from, to))
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)

      Row({ space: 6 }) {
        TextInput({ text: this.draft, placeholder: '添加待办；可直接粘贴多行' })
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
          .fontSize(20)
          .fontColor(this.paperColor())
          .backgroundColor(this.textColor())
          .borderRadius(8)
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
      Button('S').onClick((): void => this.appendMarkdown('~~文本~~'))
      Button('H').onClick((): void => this.appendMarkdown('## 标题'))
      Button('>').onClick((): void => this.appendMarkdown('> 引用'))
      Button('•').onClick((): void => this.appendMarkdown('- 列表'))
      Button('{}').onClick((): void => this.appendMarkdown('```\ncode\n```'))
      Button('↗').onClick((): void => this.appendMarkdown('[链接](https://)'))
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
                Divider()
                  .color(this.paperBorderColor())
                  .margin({ top: 6, bottom: 6 })
              } else if (line.kind === MD_KIND_HEADING) {
                Text(line.text)
                  .width('100%')
                  .fontSize(this.headingSize(line.level))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.textColor())
                  .margin({ top: 4, bottom: 2 })
              } else if (line.kind === MD_KIND_QUOTE) {
                Text('│ ' + line.text)
                  .width('100%')
                  .fontSize(14)
                  .fontColor(this.mutedColor())
                  .padding({ left: 6, top: 4, bottom: 4 })
              } else if (line.kind === MD_KIND_CODE) {
                Text(line.text)
                  .width('100%')
                  .fontSize(13)
                  .fontColor(this.textColor())
                  .backgroundColor(this.inputColor())
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              } else if (line.kind === MD_KIND_BULLET || line.kind === MD_KIND_ORDERED) {
                Text(line.text)
                  .width('100%')
                  .fontSize(14)
                  .fontColor(this.textColor())
                  .padding({ left: 10 })
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
            .maxLines(2)
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
