import { common, ConfigurationConstant, Want, wantConstant } from '@kit.AbilityKit';
import { unifiedDataChannel, uniformTypeDescriptor } from '@kit.ArkData';
import { BusinessError, deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { fileIo, fileShare, fileUri, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { KeyCode } from '@kit.InputKit';
import { display, window } from '@kit.ArkUI';
import {
  CAPSULE_HEIGHT,
  CAPSULE_CLOSE_WIDTH,
  CAPSULE_MAX_WIDTH,
  CAPSULE_MIN_WIDTH,
  EXPANDED_EDGE_INSET,
  MARKDOWN_BASIC,
  MARKDOWN_ENHANCED,
  MARKDOWN_OFF,
  NOTE_MAX_LENGTH,
  NoteImageAsset,
  PAPER_MIN_HEIGHT,
  PAPER_MIN_WIDTH,
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  PaperData,
  PaperItem,
  QUICK_LAUNCH_FILE,
  QUICK_LAUNCH_FOLDER,
  QUICK_LAUNCH_NAME_MAX_LENGTH,
  QUICK_LAUNCH_URI_MAX_LENGTH,
  RESIZE_GRIP_HIDDEN,
  RESIZE_GRIP_SOFT,
  THEME_DARK,
  THEME_LIGHT,
  THEME_SYSTEM,
  TITLE_MAX_LENGTH,
  TODO_ITEM_MAX_LENGTH,
  TODO_PASTE_MAX_ITEMS,
  TODO_VISUAL_LARGE,
  TODO_VISUAL_MEDIUM,
  TODO_VISUAL_SMALL,
  TODO_VISUAL_XLARGE,
  VISUAL_TEXT_LARGE,
  VISUAL_TEXT_SMALL
} from '../common/Models';
import {
  MarkdownInlineToken,
  MarkdownLine,
  MD_KIND_BULLET,
  MD_KIND_CODE,
  MD_KIND_HEADING,
  MD_KIND_IMAGE,
  MD_KIND_ORDERED,
  MD_KIND_QUOTE,
  MD_KIND_RULE,
  parseMarkdownLines
} from '../common/MarkdownLite';
import { PaperStore } from '../common/PaperStore';
import { cleanCommittedPaperTitle, cleanPaperTitle, effectivePaperTitle } from '../common/PaperTitles';
import {
  PAPER_ACTION_COLLAPSE,
  PAPER_ACTION_EXPAND,
  PAPER_ACTION_HIDE,
  isPaperEmpty,
  resolveLinkedPaperAction,
  resolveSystemCloseAction,
  resolveTopBarDismissAction
} from '../common/PaperInteractionPolicy';
import {
  PAPER_LINK_UDMF_TYPE,
  PaperLinkDragPayload,
  createPaperLinkDragData,
  parsePaperLinkDragRecord
} from '../common/PaperLinkDrag';
import {
  applyMarkdownBold,
  applyMarkdownCode,
  applyMarkdownItalic,
  handleMarkdownListEnter,
  insertMarkdownLinePrefix,
  insertMarkdownLink,
  NoteEditResult,
  NoteTextSelection,
  wrapMarkdownSelection
} from '../common/NoteEditing';
import {
  IMAGE_IMPORT_ANIMATED_TOO_LARGE,
  IMAGE_IMPORT_COMPRESSION_DISABLED,
  IMAGE_IMPORT_DIMENSIONS_TOO_LARGE,
  IMAGE_IMPORT_INPUT_TOO_LARGE,
  IMAGE_IMPORT_INVALID,
  IMAGE_IMPORT_OUTPUT_TOO_LARGE,
  IMAGE_IMPORT_STORAGE_FULL,
  NoteImageImportResult,
  NoteImageStore
} from '../common/NoteImageStore';
import { formatText, tForSystem } from '../common/Strings';
import { ThemePalette, resolvePalette } from '../common/ThemePalette';
import { TodoHistory, cloneTodoItems } from '../common/TodoHistory';
import {
  TODO_ITEM_UDMF_TYPE,
  TodoItemDragPayload,
  createTodoItemDragData,
  parseTodoItemDragRecord
} from '../common/TodoDrag';
import { truncateText } from '../common/TextSafety';
import { DesktopShell } from '../common/DesktopShell';
import { ExternalMarkdown } from '../common/ExternalMarkdown';

interface NoteInsertion {
  value: string;
  caret: number;
}

interface QuickLaunchDropTarget {
  uri: string;
  kind: string;
}

interface ClipboardImageCandidate {
  pixelMap?: image.PixelMap;
  uri?: string;
}

@Entry({ useSharedStorage: true })
@Component
struct Paper {
  @LocalStorageProp('paperId') paperId: string = '';
  @StorageLink('uiLanguage') @Watch('onUiLanguageChanged') uiLanguage: string = 'system';
  @StorageLink('systemLanguage') @Watch('onUiLanguageChanged') systemLanguage: string = 'zh-CN';
  @StorageLink('theme') theme: string = THEME_SYSTEM;
  @StorageLink('colorScheme') colorScheme: string = 'warm';
  @StorageLink('markdownRenderMode') @Watch('onMarkdownModeChanged') markdownRenderMode: string = MARKDOWN_ENHANCED;
  @StorageLink('useCapsuleMode') @Watch('onCapsuleSettingsChanged') useCapsuleMode: boolean = true;
  @StorageLink('useDeepCapsuleMode') @Watch('onCapsuleSettingsChanged') useDeepCapsuleMode: boolean = true;
  @StorageLink('todoVisualSize') todoVisualSize: string = TODO_VISUAL_MEDIUM;
  @StorageLink('autoClearCompletedTodos') autoClearCompletedTodos: boolean = false;
  @StorageLink('autoBottomCompleted') autoBottomCompleted: boolean = false;
  @StorageLink('autoCompressLargeImages') autoCompressLargeImages: boolean = true;
  @StorageLink('capsuleGap') @Watch('onCapsuleSettingsChanged') capsuleGap: number = 4;
  @StorageLink('enableAnimations') enableAnimations: boolean = true;
  @StorageLink('rememberEdgeExpandedPosition') rememberEdgeExpandedPosition: boolean = true;
  @StorageLink('collapseExpandedEdgeCapsuleOnClick') collapseExpandedEdgeCapsuleOnClick: boolean = false;
  @StorageLink('hideEdgeCapsuleCloseButtonOnHover') hideEdgeCapsuleCloseButtonOnHover: boolean = false;
  @StorageLink('edgeCapsuleTitleCharacterLimit') @Watch('onCapsuleSettingsChanged')
  edgeCapsuleTitleCharacterLimit: number = 0;
  @StorageLink('enablePaperLinks') enablePaperLinks: boolean = true;
  @StorageLink('overallFontScale') @Watch('onCapsuleSettingsChanged') overallFontScale: number = 1;
  @StorageLink('noteTextSize') noteTextSize: string = 'medium';
  @StorageLink('noteTextBold') noteTextBold: boolean = false;
  @StorageLink('todoTextBold') todoTextBold: boolean = false;
  @StorageLink('titleTextSize') titleTextSize: string = 'medium';
  @StorageLink('titleTextBold') titleTextBold: boolean = true;
  @StorageLink('capsuleTextSize') @Watch('onCapsuleSettingsChanged') capsuleTextSize: string = 'medium';
  @StorageLink('capsuleTextBold') @Watch('onCapsuleSettingsChanged') capsuleTextBold: boolean = false;
  @StorageLink('resizeGripMode') resizeGripMode: string = RESIZE_GRIP_SOFT;
  @StorageLink('showTopBarNewTodoButton') showTopBarNewTodoButton: boolean = true;
  @StorageLink('showTopBarNewNoteButton') showTopBarNewNoteButton: boolean = true;
  @StorageLink('showTopBarExternalOpenButton') showTopBarExternalOpenButton: boolean = true;
  @StorageLink('titleCharacterLimit') titleCharacterLimit: number = 6;
  @StorageLink('paperRevision') @Watch('onPaperRevision') paperRevision: number = 0;
  @StorageLink('paperWindowEventRevision') @Watch('onPaperWindowEvent') paperWindowEventRevision: number = 0;
  @StorageLink('systemColorMode') systemColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  @State title: string = '';
  @State items: PaperItem[] = [];
  @State content: string = '';
  @State isNoteBrowsing: boolean = true;
  @State alwaysOnTop: boolean = false;
  @State isCollapsed: boolean = false;
  @State markdownLines: MarkdownLine[] = [];
  @State layoutWidth: number = 320;
  @State titleEditing: boolean = false;
  @State statusMessage: string = '';
  @State capsuleHovered: boolean = false;
  @State linkingTodoId: string = '';
  @State keyboardMenuTodoId: string = '';
  @State contextMenuTodoId: string = '';
  @State canUndoTodo: boolean = false;
  @State canRedoTodo: boolean = false;
  @State textZoom: number = 1;
  @State imageImporting: boolean = false;
  @State brokenNoteImageIds: string[] = [];
  @State surfaceOpacity: number = 1;
  @State surfaceScale: number = 1;
  @State todoDraggingId: string = '';
  @State todoDropTargetId: string = '';
  @State todoDeleteDropHovered: boolean = false;
  @State failedQuickLaunchKeys: string[] = [];

  private paper: PaperData | null = null;
  private titleBeforeEdit: string = '';
  private titleController: TextInputController = new TextInputController();
  private moveBaseX: number = 0;
  private moveBaseY: number = 0;
  private moveCurrentX: number = 0;
  private moveCurrentY: number = 0;
  private resizeBaseWidth: number = 0;
  private resizeBaseHeight: number = 0;
  private resizeBaseX: number = 0;
  private resizeBaseY: number = 0;
  private resizeCurrentWidth: number = 0;
  private resizeCurrentHeight: number = 0;
  private resizeCurrentX: number = 0;
  private resizeCurrentY: number = 0;
  private resizeDirection: string = 'bottom-right';
  private presentedWindowX: number = 0;
  private presentedWindowY: number = 0;
  private windowMotionGeneration: number = 0;
  private windowMotionTimer: number = -1;
  private windowLayoutGeneration: number = 0;
  private hoverGeneration: number = 0;
  private capsuleDragMoved: boolean = false;
  private lastCapsuleDragEndAt: number = 0;
  private todoHistory: TodoHistory = new TodoHistory();
  private todoControllers: Map<string, TextAreaController> = new Map<string, TextAreaController>();
  private focusedTodoId: string = '';
  private noteController: TextAreaController = new TextAreaController();
  private noteInteractionActive: boolean = false;
  private noteBlurGeneration: number = 0;
  private componentActive: boolean = false;
  private imageOperationGeneration: number = 0;
  private surfaceTransitionGeneration: number = 0;
  private lastMarkdownLinkActivatedAt: number = 0;
  private pendingImageSelection: NoteTextSelection = { start: 0, end: 0 };
  private pendingImageContent: string = '';

  aboutToAppear(): void {
    this.componentActive = true;
    this.imageImporting = false;
    this.noteInteractionActive = false;
    this.noteBlurGeneration += 1;
    this.finishTodoItemDrag();
    this.reloadPaper();
  }

  aboutToDisappear(): void {
    this.componentActive = false;
    this.noteInteractionActive = false;
    this.noteBlurGeneration += 1;
    this.finishTodoItemDrag();
    this.imageOperationGeneration += 1;
    this.surfaceTransitionGeneration += 1;
    this.cancelWindowMotion();
    PaperStore.flushNow();
  }

  private reloadPaper(): void {
    const loaded: PaperData | null = PaperStore.getPaper(this.paperId);
    if (loaded === null) {
      return;
    }
    this.paper = loaded;
    this.title = loaded.title;
    this.titleBeforeEdit = loaded.title;
    this.titleEditing = false;
    this.items = loaded.items;
    this.content = loaded.content;
    this.isNoteBrowsing = loaded.type !== PAPER_TYPE_NOTE || loaded.content.length > 0;
    this.alwaysOnTop = loaded.alwaysOnTop;
    this.isCollapsed = loaded.isCollapsed && this.useCapsuleMode;
    this.textZoom = loaded.textZoom;
    this.brokenNoteImageIds = [];
    this.layoutWidth = loaded.expandedWidth;
    this.todoHistory.reset();
    this.refreshHistoryState();
    this.refreshMarkdown();
    if (this.isCollapsed) {
      const measuredWidth: number = this.calculateCapsuleWidth();
      if (loaded.capsuleWidth !== measuredWidth) {
        loaded.capsuleWidth = measuredWidth;
        PaperStore.updatePaper(loaded, false);
      }
      if (this.useDeepCapsuleMode) {
        setTimeout((): void => {
          DesktopShell.syncCapsules(this.hostContext());
        }, 50);
      } else {
        setTimeout((): void => this.syncCollapsedWindow(false, false), 100);
      }
    } else {
      this.presentedWindowX = loaded.expandedX;
      this.presentedWindowY = loaded.expandedY;
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
    if (this.isCollapsed) {
      if (this.useDeepCapsuleMode) {
        DesktopShell.syncCapsules(this.hostContext());
      } else {
        this.syncCollapsedWindow(false);
      }
    }
  }

  private onMarkdownModeChanged(): void {
    this.refreshMarkdown();
  }

  private onPaperWindowEvent(): void {
    if (AppStorage.get<string>('paperWindowEventPaperId') !== this.paperId ||
      AppStorage.get<boolean>('paperWindowEventActive') !== false || this.isNoteBrowsing ||
      this.noteInteractionActive || this.imageImporting || this.paper === null || this.paper.type !== PAPER_TYPE_NOTE) {
      return;
    }
    try {
      this.noteController.stopEditing();
    } catch (error) {
      console.warn('stop note editing failed: ' + String(error));
    }
    this.finishNoteEdit();
  }

  private onUiLanguageChanged(): void {
    this.statusMessage = '';
    this.onCapsuleSettingsChanged();
  }

  private onCapsuleSettingsChanged(): void {
    if (this.paper === null) {
      return;
    }
    const latest: PaperData | null = PaperStore.getPaper(this.paperId);
    if (latest !== null) {
      this.paper = latest;
    }
    const wasCollapsed: boolean = this.isCollapsed;
    this.isCollapsed = this.paper.isCollapsed && this.useCapsuleMode;
    if (!this.isCollapsed) {
      if (wasCollapsed) {
        this.restoreExpandedWindow();
      }
      return;
    }
    if (this.useDeepCapsuleMode) {
      DesktopShell.syncCapsules(this.hostContext());
      return;
    }
    this.syncCollapsedWindow(false, false);
  }

  private savePaper(immediate: boolean = false): void {
    if (this.paper === null) {
      return;
    }
    if (!this.titleEditing) {
      const titleLimit: number = Math.max(2, Math.min(TITLE_MAX_LENGTH, Math.round(this.titleCharacterLimit)));
      this.title = cleanCommittedPaperTitle(this.title, titleLimit);
      this.paper.title = this.title;
    }
    this.paper.items = this.items;
    this.paper.content = truncateText(this.content, NOTE_MAX_LENGTH);
    this.paper.alwaysOnTop = this.alwaysOnTop;
    this.paper.isCollapsed = this.isCollapsed;
    this.paper.textZoom = this.textZoom;
    PaperStore.updatePaper(this.paper, immediate);
  }

  private currentWindow(): window.Window | undefined {
    return AppStorage.get<window.Window>('paperWindow:' + this.paperId);
  }

  private defaultDisplay(): display.Display | undefined {
    try {
      return display.getDefaultDisplaySync();
    } catch (error) {
      console.error('get default display failed: ' + String(error));
      return undefined;
    }
  }

  private terminatePaper(): void {
    this.hostContext().terminateSelf().catch((error: BusinessError): void => {
      console.error('terminate paper failed: ' + error.message);
    });
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private text(key: string): string {
    return tForSystem(this.uiLanguage, this.systemLanguage, key);
  }

  private formatted(key: string, name: string, value: string): string {
    return formatText(this.text(key), name, value);
  }

  private vpToPx(value: number): number {
    return Math.round(this.getUIContext().vp2px(value));
  }

  private pxToVp(value: number): number {
    return this.getUIContext().px2vp(value);
  }

  private availableWidth(screen: display.Display): number {
    return this.pxToVp(screen.availableWidth > 0 ? screen.availableWidth : screen.width);
  }

  private availableHeight(screen: display.Display): number {
    return this.pxToVp(screen.availableHeight > 0 ? screen.availableHeight : screen.height);
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

  private paperColor(): string {
    return this.palette().paper;
  }

  private textColor(): string {
    return this.palette().text;
  }

  private mutedColor(): string {
    return this.palette().muted;
  }

  private paperBorderColor(): string {
    return this.palette().border;
  }

  private inputColor(): string {
    return this.palette().input;
  }

  private accentColor(): string {
    return this.palette().accent;
  }

  private dangerColor(): string {
    return this.palette().danger;
  }

  private scaledFontSize(base: number): number {
    return Math.round(base * this.overallFontScale * 10) / 10;
  }

  private visualFontSize(base: number, size: string): number {
    let adjusted: number = base;
    if (size === VISUAL_TEXT_SMALL) {
      adjusted -= 1;
    } else if (size === VISUAL_TEXT_LARGE) {
      adjusted += 1;
    }
    return this.scaledFontSize(adjusted);
  }

  private titleFontSize(): number {
    return this.visualFontSize(14, this.titleTextSize);
  }

  private capsuleFontSize(): number {
    return this.visualFontSize(13, this.capsuleTextSize);
  }

  private noteFontSize(): number {
    return Math.round(this.visualFontSize(14, this.noteTextSize) * this.textZoom * 10) / 10;
  }

  private configuredFontWeight(bold: boolean): FontWeight {
    return bold ? FontWeight.Bold : FontWeight.Normal;
  }

  private typeLabel(): string {
    return this.paper !== null && this.paper.type === PAPER_TYPE_NOTE ? '✎' : '☑';
  }

  private titleOrFallback(): string {
    if (this.paper === null) {
      return this.text('paper.todo');
    }
    const currentTitle: string = cleanPaperTitle(this.title);
    if (currentTitle.length > 0) {
      return currentTitle;
    }
    return effectivePaperTitle(this.paper, PaperStore.listPapers(), this.uiLanguage, this.systemLanguage);
  }

  private capsuleTitle(): string {
    const title: string = this.titleOrFallback();
    if (!this.useDeepCapsuleMode || this.edgeCapsuleTitleCharacterLimit <= 0 ||
      title.length <= this.edgeCapsuleTitleCharacterLimit) {
      return title;
    }
    return truncateText(title, this.edgeCapsuleTitleCharacterLimit);
  }

  private calculateCapsuleWidth(): number {
    let titleWidth: number = this.capsuleTitle().length * this.capsuleFontSize();
    try {
      titleWidth = this.pxToVp(this.getUIContext().getMeasureUtils().measureText({
        textContent: this.capsuleTitle(),
        fontSize: this.capsuleFontSize(),
        fontWeight: this.configuredFontWeight(this.capsuleTextBold)
      }));
    } catch (error) {
      console.warn('measure capsule title failed: ' + String(error));
    }
    const desired: number = Math.ceil(10 + 18 + 4 + titleWidth + 28 + 8);
    return Math.max(CAPSULE_MIN_WIDTH, Math.min(CAPSULE_MAX_WIDTH, desired));
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
      return this.scaledFontSize(12);
    }
    if (this.todoVisualSize === TODO_VISUAL_LARGE) {
      return this.scaledFontSize(16);
    }
    if (this.todoVisualSize === TODO_VISUAL_XLARGE) {
      return this.scaledFontSize(18);
    }
    return this.scaledFontSize(14);
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

  private beginTitleEdit(): void {
    if (this.titleEditing) {
      return;
    }
    this.titleBeforeEdit = this.title;
    if (this.title.trim().length === 0) {
      this.title = this.titleOrFallback();
    }
    this.titleEditing = true;
    setTimeout((): void => {
      try {
        this.getUIContext().getFocusController().requestFocus('paper_title_input');
        this.titleController.setTextSelection(0, this.title.length);
      } catch (error) {
        console.warn('focus paper title failed: ' + String(error));
      }
    }, 0);
  }

  private finishTitleEdit(): void {
    if (!this.titleEditing) {
      return;
    }
    const titleLimit: number = Math.max(2, Math.min(TITLE_MAX_LENGTH, Math.round(this.titleCharacterLimit)));
    this.title = cleanCommittedPaperTitle(this.title, titleLimit);
    this.titleEditing = false;
    this.titleBeforeEdit = this.title;
    this.savePaper(true);
  }

  private cancelTitleEdit(): void {
    if (!this.titleEditing) {
      return;
    }
    this.title = this.titleBeforeEdit;
    this.titleEditing = false;
  }

  private handleTitleKey(event: KeyEvent): boolean {
    if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.cancelTitleEdit();
      return true;
    }
    return false;
  }

  private finishNoteEdit(): void {
    if (this.isNoteBrowsing || this.paper === null || this.paper.type !== PAPER_TYPE_NOTE) {
      return;
    }
    this.isNoteBrowsing = true;
    this.refreshMarkdown();
    this.savePaper(true);
  }

  private beginNoteInteraction(): void {
    this.noteInteractionActive = true;
    this.noteBlurGeneration += 1;
  }

  private resumeNoteEditing(): void {
    this.noteInteractionActive = false;
    this.noteBlurGeneration += 1;
    if (!this.componentActive || this.isNoteBrowsing || this.imageImporting || this.paper === null ||
      this.paper.type !== PAPER_TYPE_NOTE) {
      return;
    }
    setTimeout((): void => {
      if (!this.componentActive || this.isNoteBrowsing || this.imageImporting) {
        return;
      }
      try {
        this.getUIContext().getFocusController().requestFocus('paper_note_editor');
      } catch (error) {
        console.warn('restore note editor focus failed: ' + String(error));
      }
    }, 0);
  }

  private handleNoteEditorBlur(): void {
    const generation: number = ++this.noteBlurGeneration;
    setTimeout((): void => {
      if (generation !== this.noteBlurGeneration || !this.componentActive || this.noteInteractionActive ||
        this.imageImporting || this.isNoteBrowsing) {
        return;
      }
      this.finishNoteEdit();
    }, 140);
  }

  private finishNoteImageInteraction(): void {
    this.imageImporting = false;
    this.resumeNoteEditing();
  }

  private noteEditorActionLabel(action: string): string {
    const selected: string = (this.uiLanguage === 'system' ? this.systemLanguage : this.uiLanguage).toLowerCase();
    if (selected.startsWith('ja')) {
      return action === 'copy' ? 'コピー' : 'すべて選択';
    }
    if (selected.startsWith('ko')) {
      return action === 'copy' ? '복사' : '전체 선택';
    }
    if (selected.startsWith('en')) {
      return action === 'copy' ? 'Copy' : 'Select all';
    }
    return action === 'copy' ? '复制' : '全选';
  }

  private copyNoteSelection(): void {
    const selection: NoteTextSelection = this.currentNoteSelection();
    const start: number = Math.min(selection.start, selection.end);
    const end: number = Math.max(selection.start, selection.end);
    if (end <= start) {
      return;
    }
    try {
      const data: pasteboard.PasteData = pasteboard.createData(
        pasteboard.MIMETYPE_TEXT_PLAIN, this.content.substring(start, end));
      pasteboard.getSystemPasteboard().setData(data).catch((error: BusinessError): void => {
        console.warn('copy note selection failed: ' + error.message);
      });
    } catch (error) {
      console.warn('copy note selection failed: ' + String(error));
    }
  }

  private selectAllNote(): void {
    this.noteController.setTextSelection(0, this.content.length);
  }

  private beginPaperLinkDrag(event: DragEvent): DragItemInfo {
    if (this.paper === null || !this.enablePaperLinks) {
      return { extraInfo: '' };
    }
    const data: unifiedDataChannel.UnifiedData = createPaperLinkDragData(
      this.paper.id,
      this.paper.type,
      this.paperDisplayTitle(this.paper)
    );
    event.setData(data);
    event.dragBehavior = DragBehavior.COPY;
    return { extraInfo: this.paper.id };
  }

  private toggleTopmost(): void {
    this.alwaysOnTop = !this.alwaysOnTop;
    this.savePaper(true);
    const win: window.Window | undefined = this.currentWindow();
    if (win !== undefined) {
      win.setWindowTopmost(this.alwaysOnTop || this.isCollapsed)
        .catch((error: BusinessError): void => {
        console.error('setWindowTopmost failed: ' + error.message);
      });
    }
  }

  private hidePaper(): void {
    if (this.paper === null) {
      return;
    }
    this.savePaper(false);
    PaperStore.flushNow();
    DesktopShell.hidePaper(this.hostContext(), this.paperId).catch((error: Error): void => {
      this.statusMessage = String(error);
    });
  }

  private performDeletePaper(): void {
    PaperStore.flushNow();
    DesktopShell.deletePaper(this.hostContext(), this.paperId).catch((error: Error): void => {
      this.statusMessage = String(error);
    });
  }

  private deletePaper(): void {
    if (this.paper === null) {
      return;
    }
    this.savePaper(false);
    if (isPaperEmpty(this.paper)) {
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
        fontColor: this.dangerColor(),
        action: (): void => this.performDeletePaper()
      }
    });
  }

  private createPaper(type: string): void {
    DesktopShell.createPaper(this.hostContext(), type, this.paperId).then((created: PaperData | null): void => {
      if (created === null) {
        this.statusMessage = this.text('status.createPaperBlocked');
      }
    }).catch((error: Error): void => {
      this.statusMessage = this.formatted('status.createPaperFailed', 'error', error.message);
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
      return this.text('markdown.shortOff');
    }
    if (this.markdownRenderMode === MARKDOWN_BASIC) {
      return this.text('markdown.shortBasic');
    }
    return this.text('markdown.shortEnhanced');
  }

  private setCollapsed(collapsed: boolean): void {
    if (this.paper === null) {
      return;
    }
    if (collapsed && !this.canCollapseToCapsule()) {
      return;
    }
    if (this.isCollapsed === collapsed) {
      return;
    }
    this.cancelWindowMotion();
    const generation: number = ++this.surfaceTransitionGeneration;
    if (this.enableAnimations) {
      this.getUIContext().animateTo({ duration: 90, curve: Curve.EaseIn }, (): void => {
        this.surfaceOpacity = 0;
        this.surfaceScale = collapsed ? 0.94 : 0.97;
      });
      setTimeout((): void => {
        if (generation !== this.surfaceTransitionGeneration || !this.componentActive) {
          return;
        }
        this.applyCollapsedState(collapsed);
        this.surfaceScale = collapsed ? 0.96 : 0.98;
        setTimeout((): void => {
          if (generation !== this.surfaceTransitionGeneration || !this.componentActive) {
            return;
          }
          this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseOut }, (): void => {
            this.surfaceOpacity = 1;
            this.surfaceScale = 1;
          });
        }, 70);
      }, 95);
      return;
    }
    this.surfaceOpacity = 1;
    this.surfaceScale = 1;
    this.applyCollapsedState(collapsed);
  }

  private applyCollapsedState(collapsed: boolean): void {
    if (this.paper === null) {
      return;
    }
    if (collapsed && !this.canCollapseToCapsule()) {
      return;
    }
    if (collapsed) {
      this.finishTodoItemDrag();
    }
    this.isCollapsed = collapsed;
    this.paper.isCollapsed = collapsed;
    if (collapsed) {
      this.paper.capsuleWidth = this.calculateCapsuleWidth();
    } else {
      this.capsuleHovered = false;
      this.hoverGeneration += 1;
    }
    this.savePaper(false);
    PaperStore.setPaperCollapsed(this.paperId, collapsed);
    if (collapsed) {
      if (this.useDeepCapsuleMode) {
        DesktopShell.syncCapsules(this.hostContext()).catch((error: Error): void => {
          console.error('sync deep capsule failed: ' + error.message);
        });
      } else {
        this.syncCollapsedWindow(false, this.enableAnimations);
        DesktopShell.syncCapsules(this.hostContext());
      }
    } else {
      this.restoreExpandedWindow();
      DesktopShell.syncCapsules(this.hostContext());
    }
  }

  private restoreExpandedWindow(): void {
    const generation: number = ++this.windowLayoutGeneration;
    this.restoreExpandedWindowAsync(generation).catch((error: Error): void => {
      console.error('restore expanded window failed: ' + error.message);
    });
  }

  private async restoreExpandedWindowAsync(generation: number): Promise<void> {
    if (this.paper === null) {
      return;
    }
    const paper: PaperData = this.paper;
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    const screen: display.Display | undefined = this.defaultDisplay();
    if (screen === undefined) {
      return;
    }
    const screenWidth: number = this.availableWidth(screen);
    const screenHeight: number = this.availableHeight(screen);
    const width: number = Math.min(screenWidth, Math.max(PAPER_MIN_WIDTH, paper.expandedWidth));
    const height: number = Math.min(screenHeight, Math.max(PAPER_MIN_HEIGHT, paper.expandedHeight));
    let x: number = paper.expandedX;
    let y: number = paper.expandedY;
    if (this.useDeepCapsuleMode && !this.rememberEdgeExpandedPosition) {
      x = Math.max(0, screenWidth - width - EXPANDED_EDGE_INSET);
      y = this.clamp(paper.capsuleY, 0, Math.max(0, screenHeight - height));
    }
    x = this.clamp(x, 0, Math.max(0, screenWidth - width));
    y = this.clamp(y, 0, Math.max(0, screenHeight - height));
    this.layoutWidth = width;
    try {
      await win.resize(this.vpToPx(width), this.vpToPx(height));
    } catch (error) {
      console.error('restore paper size failed: ' + String(error));
      return;
    }
    if (generation !== this.windowLayoutGeneration || this.isCollapsed) {
      return;
    }
    try {
      await win.setWindowTopmost(this.alwaysOnTop);
    } catch (error) {
      console.error('restore topmost failed: ' + String(error));
    }
    if (generation !== this.windowLayoutGeneration || this.isCollapsed) {
      return;
    }
    this.moveWindowAnimated(Math.round(x), Math.round(y), this.enableAnimations, 180);
  }

  private syncCollapsedWindow(hovered: boolean, animate: boolean = true): void {
    const generation: number = ++this.windowLayoutGeneration;
    this.syncCollapsedWindowAsync(hovered, animate, generation).catch((error: Error): void => {
      console.error('sync collapsed window failed: ' + error.message);
    });
  }

  private async syncCollapsedWindowAsync(hovered: boolean, animate: boolean, generation: number): Promise<void> {
    if (!this.isCollapsed || this.paper === null) {
      return;
    }
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    const measuredWidth: number = this.calculateCapsuleWidth();
    if (this.paper.capsuleWidth !== measuredWidth) {
      this.paper.capsuleWidth = measuredWidth;
      PaperStore.updatePaper(this.paper, false);
    }
    try {
      await win.resize(this.vpToPx(this.paper.capsuleWidth), this.vpToPx(CAPSULE_HEIGHT));
    } catch (error) {
      console.error('resize capsule failed: ' + String(error));
      return;
    }
    if (generation !== this.windowLayoutGeneration || !this.isCollapsed) {
      return;
    }
    try {
      await win.setWindowTopmost(true);
    } catch (error) {
      console.error('capsule topmost failed: ' + String(error));
    }
    if (generation !== this.windowLayoutGeneration || !this.isCollapsed) {
      return;
    }
    if (this.useDeepCapsuleMode) {
      this.snapCapsule(hovered, animate);
    } else {
      this.moveFloatingCapsule();
    }
  }

  private moveFloatingCapsule(): void {
    if (this.paper === null) {
      return;
    }
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    const screen: display.Display | undefined = this.defaultDisplay();
    if (screen === undefined) {
      return;
    }
    const screenWidth: number = this.availableWidth(screen);
    const screenHeight: number = this.availableHeight(screen);
    const width: number = this.paper.capsuleWidth;
    this.paper.capsuleX = this.clamp(this.paper.capsuleX, 0, Math.max(0, screenWidth - width));
    this.paper.capsuleY = this.clamp(this.paper.capsuleY, 0, Math.max(0, screenHeight - CAPSULE_HEIGHT));
    PaperStore.updatePaper(this.paper, false);
    this.cancelWindowMotion();
    this.presentedWindowX = Math.round(this.paper.capsuleX);
    this.presentedWindowY = Math.round(this.paper.capsuleY);
    win.moveWindowTo(this.vpToPx(this.presentedWindowX), this.vpToPx(this.presentedWindowY))
      .catch((error: BusinessError): void => {
      console.error('move floating capsule failed: ' + error.message);
    });
  }

  private snapCapsule(hovered: boolean, animate: boolean = true): void {
    if (!this.isCollapsed || !this.useDeepCapsuleMode || this.paper === null) {
      return;
    }
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    this.capsuleHovered = hovered;
    const screen: display.Display | undefined = this.defaultDisplay();
    if (screen === undefined) {
      return;
    }
    const screenWidth: number = this.availableWidth(screen);
    const screenHeight: number = this.availableHeight(screen);
    const width: number = this.paper.capsuleWidth;
    const fullX: number = Math.max(0, screenWidth - width);
    const restingX: number = Math.min(screenWidth, fullX + Math.min(width, CAPSULE_CLOSE_WIDTH));
    const index: number = PaperStore.getCollapsedIndex(this.paperId);
    const targetY: number = this.clamp(20 + index * (CAPSULE_HEIGHT + this.capsuleGap), 0,
      Math.max(0, screenHeight - CAPSULE_HEIGHT));
    if (this.paper.capsuleX !== fullX || this.paper.capsuleY !== targetY) {
      this.paper.capsuleX = fullX;
      this.paper.capsuleY = targetY;
      PaperStore.updatePaper(this.paper, false);
    }
    this.moveWindowAnimated(hovered ? fullX : restingX, targetY,
      animate && this.enableAnimations, hovered ? 140 : 180);
  }

  private moveWindowAnimated(targetX: number, targetY: number, animated: boolean, duration: number): void {
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    this.cancelWindowMotion();
    if (!animated || duration <= 0 || (this.presentedWindowX === 0 && this.presentedWindowY === 0)) {
      this.presentedWindowX = targetX;
      this.presentedWindowY = targetY;
      win.moveWindowTo(this.vpToPx(targetX), this.vpToPx(targetY)).catch((error: BusinessError): void => {
        console.error('move paper window failed: ' + error.message);
      });
      return;
    }

    const generation: number = this.windowMotionGeneration;
    const startX: number = this.presentedWindowX;
    const startY: number = this.presentedWindowY;
    const startedAt: number = Date.now();
    const tick = async (): Promise<void> => {
      if (generation !== this.windowMotionGeneration) {
        return;
      }
      const raw: number = Math.min(1, Math.max(0, (Date.now() - startedAt) / duration));
      const eased: number = 1 - Math.pow(1 - raw, 3);
      this.presentedWindowX = Math.round(startX + (targetX - startX) * eased);
      this.presentedWindowY = Math.round(startY + (targetY - startY) * eased);
      try {
        await win.moveWindowTo(this.vpToPx(this.presentedWindowX), this.vpToPx(this.presentedWindowY));
      } catch (error) {
        console.error('animate paper window failed: ' + String(error));
        return;
      }
      if (generation !== this.windowMotionGeneration) {
        return;
      }
      if (raw < 1) {
        this.windowMotionTimer = setTimeout((): void => {
          tick().catch((error: Error): void => {
            console.error('animate paper window tick failed: ' + error.message);
          });
        }, 16);
      } else {
        this.windowMotionTimer = -1;
      }
    };
    tick().catch((error: Error): void => {
      console.error('animate paper window failed: ' + error.message);
    });
  }

  private cancelWindowMotion(): void {
    this.windowMotionGeneration += 1;
    if (this.windowMotionTimer >= 0) {
      clearTimeout(this.windowMotionTimer);
      this.windowMotionTimer = -1;
    }
  }

  private handleCapsuleHover(hovered: boolean): void {
    const generation: number = ++this.hoverGeneration;
    if (hovered) {
      this.snapCapsule(true, true);
      return;
    }
    this.capsuleHovered = false;
    setTimeout((): void => {
      if (generation === this.hoverGeneration && !this.capsuleHovered && !this.capsuleDragMoved) {
        this.snapCapsule(false, true);
      }
    }, 90);
  }

  private activateCapsule(): void {
    if (this.capsuleDragMoved || Date.now() - this.lastCapsuleDragEndAt < 180) {
      this.capsuleDragMoved = false;
      return;
    }
    this.setCollapsed(false);
  }

  private beginMove(): void {
    if (this.paper === null) {
      return;
    }
    this.cancelWindowMotion();
    this.capsuleDragMoved = false;
    if (this.isCollapsed) {
      if (this.useDeepCapsuleMode) {
        this.snapCapsule(true, false);
        this.moveBaseX = this.paper.capsuleX;
        this.moveBaseY = this.paper.capsuleY;
      } else {
        this.moveBaseX = this.paper.capsuleX;
        this.moveBaseY = this.paper.capsuleY;
      }
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
    if (this.isCollapsed && Math.abs(event.offsetX) + Math.abs(event.offsetY) > 4) {
      this.capsuleDragMoved = true;
    }
    if (this.isCollapsed && this.useDeepCapsuleMode) {
      const screen: display.Display | undefined = this.defaultDisplay();
      if (screen === undefined) {
        return;
      }
      const screenHeight: number = this.availableHeight(screen);
      this.moveCurrentX = Math.round(this.moveBaseX);
      this.moveCurrentY = this.clamp(Math.round(this.moveBaseY + event.offsetY), 0,
        Math.max(0, screenHeight - CAPSULE_HEIGHT));
    } else {
      this.moveCurrentX = Math.round(this.moveBaseX + event.offsetX);
      this.moveCurrentY = Math.round(this.moveBaseY + event.offsetY);
    }
    this.presentedWindowX = this.moveCurrentX;
    this.presentedWindowY = this.moveCurrentY;
    win.moveWindowTo(this.vpToPx(this.moveCurrentX), this.vpToPx(this.moveCurrentY))
      .catch((error: BusinessError): void => {
      console.error('drag paper window failed: ' + error.message);
    });
  }

  private endMove(): void {
    if (this.paper === null) {
      return;
    }
    if (this.isCollapsed) {
      if (this.useDeepCapsuleMode) {
        const desiredIndex: number = Math.max(0,
          Math.round((this.moveCurrentY - 20) / (CAPSULE_HEIGHT + this.capsuleGap)));
        PaperStore.moveCollapsedPaper(this.paperId, desiredIndex);
        const latest: PaperData | null = PaperStore.getPaper(this.paperId);
        if (latest !== null) {
          this.paper = latest;
        }
        if (this.capsuleDragMoved) {
          this.lastCapsuleDragEndAt = Date.now();
        }
        this.snapCapsule(false, this.enableAnimations);
        this.capsuleDragMoved = false;
      } else {
        const screen: display.Display | undefined = this.defaultDisplay();
        if (screen === undefined) {
          return;
        }
        const screenWidth: number = this.availableWidth(screen);
        const screenHeight: number = this.availableHeight(screen);
        this.paper.capsuleX = this.clamp(this.moveCurrentX, 0,
          Math.max(0, screenWidth - this.paper.capsuleWidth));
        this.paper.capsuleY = this.clamp(this.moveCurrentY, 0,
          Math.max(0, screenHeight - CAPSULE_HEIGHT));
        this.presentedWindowX = this.paper.capsuleX;
        this.presentedWindowY = this.paper.capsuleY;
        if (this.capsuleDragMoved) {
          this.lastCapsuleDragEndAt = Date.now();
        }
        PaperStore.updatePaper(this.paper, false);
        this.capsuleDragMoved = false;
      }
      return;
    }

    this.paper.expandedX = this.moveCurrentX;
    this.paper.expandedY = this.moveCurrentY;
    PaperStore.updatePaper(this.paper, false);
  }

  private cancelMove(): void {
    this.capsuleDragMoved = false;
    this.moveCurrentX = this.moveBaseX;
    this.moveCurrentY = this.moveBaseY;
    if (this.isCollapsed && this.useDeepCapsuleMode) {
      this.snapCapsule(false, this.enableAnimations);
      return;
    }
    this.presentedWindowX = this.moveBaseX;
    this.presentedWindowY = this.moveBaseY;
    const win: window.Window | undefined = this.currentWindow();
    if (win !== undefined) {
      win.moveWindowTo(this.vpToPx(this.moveBaseX), this.vpToPx(this.moveBaseY))
        .catch((error: BusinessError): void => {
          console.error('restore cancelled drag failed: ' + error.message);
        });
    }
  }

  private beginResize(direction: string = 'bottom-right'): void {
    if (this.paper === null || this.isCollapsed) {
      return;
    }
    this.resizeDirection = direction;
    this.resizeBaseX = this.paper.expandedX;
    this.resizeBaseY = this.paper.expandedY;
    this.resizeBaseWidth = this.paper.expandedWidth;
    this.resizeBaseHeight = this.paper.expandedHeight;
    this.resizeCurrentX = this.paper.expandedX;
    this.resizeCurrentY = this.paper.expandedY;
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
    const screen: display.Display | undefined = this.defaultDisplay();
    if (screen === undefined) {
      return;
    }
    const screenWidth: number = this.availableWidth(screen);
    const screenHeight: number = this.availableHeight(screen);
    const fromLeft: boolean = this.resizeDirection.indexOf('left') >= 0;
    const fromRight: boolean = this.resizeDirection.indexOf('right') >= 0;
    const fromTop: boolean = this.resizeDirection.indexOf('top') >= 0;
    const fromBottom: boolean = this.resizeDirection.indexOf('bottom') >= 0;
    this.resizeCurrentX = this.resizeBaseX;
    this.resizeCurrentY = this.resizeBaseY;
    this.resizeCurrentWidth = this.resizeBaseWidth;
    this.resizeCurrentHeight = this.resizeBaseHeight;
    if (fromLeft) {
      const right: number = this.resizeBaseX + this.resizeBaseWidth;
      this.resizeCurrentX = this.clamp(Math.round(this.resizeBaseX + event.offsetX), 0,
        Math.max(0, right - PAPER_MIN_WIDTH));
      this.resizeCurrentWidth = right - this.resizeCurrentX;
    } else if (fromRight) {
      this.resizeCurrentWidth = this.clamp(Math.round(this.resizeBaseWidth + event.offsetX), PAPER_MIN_WIDTH,
        Math.max(PAPER_MIN_WIDTH, screenWidth - this.resizeBaseX));
    }
    if (fromTop) {
      const bottom: number = this.resizeBaseY + this.resizeBaseHeight;
      this.resizeCurrentY = this.clamp(Math.round(this.resizeBaseY + event.offsetY), 0,
        Math.max(0, bottom - PAPER_MIN_HEIGHT));
      this.resizeCurrentHeight = bottom - this.resizeCurrentY;
    } else if (fromBottom) {
      this.resizeCurrentHeight = this.clamp(Math.round(this.resizeBaseHeight + event.offsetY), PAPER_MIN_HEIGHT,
        Math.max(PAPER_MIN_HEIGHT, screenHeight - this.resizeBaseY));
    }
    this.layoutWidth = this.resizeCurrentWidth;
    this.presentedWindowX = this.resizeCurrentX;
    this.presentedWindowY = this.resizeCurrentY;
    win.resize(this.vpToPx(this.resizeCurrentWidth), this.vpToPx(this.resizeCurrentHeight))
      .then((): void => {
        if (fromLeft || fromTop) {
          win.moveWindowTo(this.vpToPx(this.resizeCurrentX), this.vpToPx(this.resizeCurrentY))
            .catch((moveError: BusinessError): void => {
              console.error('move resized paper failed: ' + moveError.message);
            });
        }
      }).catch((error: BusinessError): void => {
        console.error('resize paper failed: ' + error.message);
      });
  }

  private endResize(): void {
    if (this.paper === null || this.isCollapsed) {
      return;
    }
    this.paper.expandedX = this.resizeCurrentX;
    this.paper.expandedY = this.resizeCurrentY;
    this.paper.expandedWidth = this.resizeCurrentWidth;
    this.paper.expandedHeight = this.resizeCurrentHeight;
    PaperStore.updatePaper(this.paper, false);
  }

  private cancelResize(): void {
    if (this.paper === null || this.isCollapsed) {
      return;
    }
    this.resizeCurrentX = this.resizeBaseX;
    this.resizeCurrentY = this.resizeBaseY;
    this.resizeCurrentWidth = this.resizeBaseWidth;
    this.resizeCurrentHeight = this.resizeBaseHeight;
    this.layoutWidth = this.resizeBaseWidth;
    this.presentedWindowX = this.resizeBaseX;
    this.presentedWindowY = this.resizeBaseY;
    const win: window.Window | undefined = this.currentWindow();
    if (win !== undefined) {
      win.resize(this.vpToPx(this.resizeBaseWidth), this.vpToPx(this.resizeBaseHeight))
        .then((): void => {
          win.moveWindowTo(this.vpToPx(this.resizeBaseX), this.vpToPx(this.resizeBaseY))
            .catch((moveError: BusinessError): void => {
              console.error('restore resized paper position failed: ' + moveError.message);
            });
        }).catch((error: BusinessError): void => {
          console.error('restore resized paper failed: ' + error.message);
        });
    }
  }

  private copyTodoItem(item: PaperItem, order: number = item.order, text: string = item.text,
    done: boolean = item.done): PaperItem {
    return {
      id: item.id,
      text: text,
      done: done,
      order: order,
      linkedPaperId: item.linkedPaperId,
      quickLaunchUri: item.quickLaunchUri,
      quickLaunchName: item.quickLaunchName,
      quickLaunchKind: item.quickLaunchKind
    };
  }

  private syncCapsulesAfterAssociationChange(): void {
    DesktopShell.syncCapsules(this.hostContext()).catch((error: Error): void => {
      console.error('sync capsules after todo association change failed: ' + error.message);
    });
  }

  private toggleTodo(id: string): void {
    this.captureTodoHistory();
    let changed: PaperItem | null = null;
    const remaining: PaperItem[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      const item: PaperItem = this.items[i];
      if (item.id === id) {
        changed = this.copyTodoItem(item, item.order, item.text, !item.done);
      } else {
        remaining.push(this.copyTodoItem(item));
      }
    }
    if (changed === null) {
      return;
    }

    if (this.autoClearCompletedTodos && changed.done) {
      if (remaining.length === 0) {
        remaining.push(PaperStore.createTodoItem('', 0));
      }
      this.items = this.renumberItems(remaining);
    } else if (!this.autoBottomCompleted) {
      const next: PaperItem[] = [];
      for (let i: number = 0; i < this.items.length; i++) {
        const item: PaperItem = this.items[i];
        next.push(item.id === id ? changed : this.copyTodoItem(item));
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
    if (this.autoClearCompletedTodos && changed.done && changed.linkedPaperId !== undefined) {
      this.syncCapsulesAfterAssociationChange();
    }
  }

  private updateTodoText(id: string, text: string): void {
    const safeText: string = truncateText(text, TODO_ITEM_MAX_LENGTH);
    let changed: boolean = false;
    for (let i: number = 0; i < this.items.length; i++) {
      if (this.items[i].id === id && this.items[i].text !== safeText) {
        changed = true;
        break;
      }
    }
    if (!changed) {
      return;
    }
    this.captureTodoHistory('text:' + id);
    const next: PaperItem[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      const item: PaperItem = this.items[i];
      next.push(this.copyTodoItem(item, i, item.id === id ? safeText : item.text));
    }
    this.items = next;
    this.savePaper(false);
  }

  private todoController(id: string): TextAreaController {
    const existing: TextAreaController | undefined = this.todoControllers.get(id);
    if (existing !== undefined) {
      return existing;
    }
    const created: TextAreaController = new TextAreaController();
    this.todoControllers.set(id, created);
    return created;
  }

  private todoFocusKey(id: string): string {
    return 'todo_input_' + id;
  }

  private requestTodoFocus(id: string, selectAll: boolean = false, caret: number = -1): void {
    setTimeout((): void => {
      try {
        this.getUIContext().getFocusController().requestFocus(this.todoFocusKey(id));
        if (selectAll) {
          const item: PaperItem | undefined = this.items.find((candidate: PaperItem): boolean => candidate.id === id);
          this.todoController(id).setTextSelection(0, item === undefined ? 0 : item.text.length);
        } else if (caret >= 0) {
          this.todoController(id).setTextSelection(caret, caret);
        }
      } catch (error) {
        console.warn('focus todo failed: ' + String(error));
      }
    }, 0);
  }

  private focusTodoForContextMenu(id: string): void {
    this.contextMenuTodoId = id;
    this.focusedTodoId = id;
    try {
      this.getUIContext().getFocusController().requestFocus(this.todoFocusKey(id));
    } catch (error) {
      this.requestTodoFocus(id);
    }
  }

  private finishTodoContextMenu(id: string): void {
    if (this.contextMenuTodoId === id) {
      this.contextMenuTodoId = '';
    }
    if (this.todoIndexById(id) >= 0) {
      this.requestTodoFocus(id);
    } else if (this.items.length > 0) {
      this.requestTodoFocus(this.items[0].id);
    }
  }

  private deleteTodo(id: string): void {
    let deletedIndex: number = -1;
    for (let i: number = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        deletedIndex = i;
        break;
      }
    }
    if (deletedIndex < 0) {
      return;
    }
    this.captureTodoHistory();
    const next: PaperItem[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      if (this.items[i].id !== id) {
        const item: PaperItem = this.items[i];
        next.push(this.copyTodoItem(item, next.length));
      }
    }
    if (next.length === 0) {
      next.push(PaperStore.createTodoItem('', 0));
    }
    this.items = next;
    this.todoControllers.delete(id);
    this.clearQuickLaunchFailures(id);
    this.savePaper(false);
    this.syncCapsulesAfterAssociationChange();
    const focusIndex: number = Math.min(deletedIndex, next.length - 1);
    this.requestTodoFocus(next[focusIndex].id);
  }

  private insertTodoAfter(id: string): void {
    this.captureTodoHistory();
    const next: PaperItem[] = [];
    let insertedId: string = '';
    for (let i: number = 0; i < this.items.length; i++) {
      const item: PaperItem = this.items[i];
      next.push(this.copyTodoItem(item, next.length));
      if (item.id === id) {
        const inserted: PaperItem = PaperStore.createTodoItem('', next.length);
        insertedId = inserted.id;
        next.push(inserted);
      }
    }
    this.items = next;
    this.savePaper(false);
    if (insertedId.length > 0) {
      this.requestTodoFocus(insertedId);
    }
  }

  private clearCompleted(): void {
    if (this.completedCount() === 0) {
      return;
    }
    this.captureTodoHistory();
    const next: PaperItem[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      if (!this.items[i].done) {
        const item: PaperItem = this.items[i];
        next.push(this.copyTodoItem(item, next.length, item.text, false));
      }
    }
    if (next.length === 0) {
      next.push(PaperStore.createTodoItem('', 0));
    }
    this.items = next;
    this.savePaper(false);
    this.syncCapsulesAfterAssociationChange();
  }

  private moveTodo(from: number, to: number): void {
    if (from < 0 || from >= this.items.length || to < 0 || to >= this.items.length || from === to) {
      return;
    }
    this.captureTodoHistory();
    const next: PaperItem[] = cloneTodoItems(this.items);
    const moved: PaperItem[] = next.splice(from, 1);
    next.splice(to, 0, moved[0]);
    this.items = this.renumberItems(next);
    this.savePaper(false);
  }

  private todoIndexById(id: string): number {
    for (let i: number = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  private beginTodoItemDrag(event: DragEvent, item: PaperItem): DragItemInfo {
    const data: unifiedDataChannel.UnifiedData = createTodoItemDragData(this.paperId, item.id);
    event.setData(data);
    event.dragBehavior = DragBehavior.MOVE;
    this.todoDraggingId = item.id;
    this.todoDropTargetId = '';
    this.todoDeleteDropHovered = false;
    return { extraInfo: item.id };
  }

  private finishTodoItemDrag(): void {
    this.todoDraggingId = '';
    this.todoDropTargetId = '';
    this.todoDeleteDropHovered = false;
  }

  private todoItemDragPayload(event: DragEvent): TodoItemDragPayload | null {
    try {
      const records: unifiedDataChannel.UnifiedRecord[] = event.getData().getRecords();
      for (let i: number = 0; i < records.length; i++) {
        const payload: TodoItemDragPayload | null = parseTodoItemDragRecord(records[i]);
        if (payload !== null) {
          return payload;
        }
      }
    } catch (error) {
      return null;
    }
    return null;
  }

  private handleTodoMoveDrop(event: DragEvent, targetId: string): boolean {
    const payload: TodoItemDragPayload | null = this.todoItemDragPayload(event);
    if (payload === null) {
      return false;
    }
    const from: number = this.todoIndexById(payload.todoId);
    const to: number = this.todoIndexById(targetId);
    if (payload.paperId !== this.paperId || payload.todoId !== this.todoDraggingId || from < 0 || to < 0) {
      event.setResult(DragResult.DRAG_FAILED);
      this.finishTodoItemDrag();
      return true;
    }
    event.setResult(DragResult.DRAG_SUCCESSFUL);
    this.finishTodoItemDrag();
    if (from !== to) {
      this.moveTodo(from, to);
    }
    return true;
  }

  private handleTodoDeleteDrop(event: DragEvent): void {
    try {
      const payload: TodoItemDragPayload | null = this.todoItemDragPayload(event);
      if (payload === null || payload.paperId !== this.paperId || payload.todoId !== this.todoDraggingId ||
        this.todoIndexById(payload.todoId) < 0) {
        event.setResult(DragResult.DRAG_FAILED);
        this.finishTodoItemDrag();
        return;
      }
      event.setResult(DragResult.DRAG_SUCCESSFUL);
      this.finishTodoItemDrag();
      this.deleteTodo(payload.todoId);
      this.statusMessage = this.text('status.todoDragDeleted');
    } catch (error) {
      event.setResult(DragResult.DRAG_FAILED);
      this.finishTodoItemDrag();
    }
  }

  private renumberItems(items: PaperItem[]): PaperItem[] {
    const next: PaperItem[] = [];
    for (let i: number = 0; i < items.length; i++) {
      next.push(this.copyTodoItem(items[i], i));
    }
    return next;
  }

  private appendBlankTodo(): void {
    this.captureTodoHistory();
    const next: PaperItem[] = cloneTodoItems(this.items);
    const created: PaperItem = PaperStore.createTodoItem('', next.length);
    next.push(created);
    this.items = this.renumberItems(next);
    this.savePaper(false);
    this.requestTodoFocus(created.id);
  }

  private pasteTodoLines(itemId: string, content: string, event: PasteEvent): void {
    const normalized: string = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    if (normalized.indexOf('\n') < 0) {
      return;
    }
    if (event.preventDefault !== undefined) {
      event.preventDefault();
    }
    const lines: string[] = normalized.split('\n');
    const cleaned: string[] = [];
    for (let i: number = 0; i < lines.length && cleaned.length < TODO_PASTE_MAX_ITEMS; i++) {
      const value: string = truncateText(this.cleanTodoPrefix(lines[i]).trim(), TODO_ITEM_MAX_LENGTH);
      if (value.length > 0) {
        cleaned.push(value);
      }
    }
    if (cleaned.length === 0) {
      return;
    }
    if (lines.length > TODO_PASTE_MAX_ITEMS) {
      this.statusMessage = this.formatted('status.todoPasteLimit', 'count', TODO_PASTE_MAX_ITEMS.toString());
    }
    let sourceText: string = '';
    for (let i: number = 0; i < this.items.length; i++) {
      if (this.items[i].id === itemId) {
        sourceText = this.items[i].text;
        break;
      }
    }
    const controller: TextAreaController = this.todoController(itemId);
    let selectionStart: number = 0;
    let selectionEnd: number = 0;
    try {
      const selection: TextRange = controller.getSelection();
      const caret: number = controller.getCaretOffset().index;
      selectionStart = selection.start === undefined ? caret : selection.start;
      selectionEnd = selection.end === undefined ? selectionStart : selection.end;
    } catch (error) {
      selectionStart = sourceText.length;
      selectionEnd = sourceText.length;
    }
    selectionStart = this.clamp(selectionStart, 0, sourceText.length);
    selectionEnd = this.clamp(selectionEnd, selectionStart, sourceText.length);
    const prefix: string = sourceText.substring(0, selectionStart);
    const suffix: string = sourceText.substring(selectionEnd);
    const pastedTexts: string[] = cleaned.slice();
    if (pastedTexts.length === 1) {
      pastedTexts[0] = truncateText(prefix + pastedTexts[0] + suffix, TODO_ITEM_MAX_LENGTH);
    } else {
      pastedTexts[0] = truncateText(prefix + pastedTexts[0], TODO_ITEM_MAX_LENGTH);
      const finalIndex: number = pastedTexts.length - 1;
      pastedTexts[finalIndex] = truncateText(pastedTexts[finalIndex] + suffix, TODO_ITEM_MAX_LENGTH);
    }
    this.captureTodoHistory();
    const next: PaperItem[] = [];
    let lastCreatedId: string = itemId;
    for (let i: number = 0; i < this.items.length; i++) {
      const item: PaperItem = this.items[i];
      if (item.id === itemId) {
        next.push(this.copyTodoItem(item, next.length, pastedTexts[0]));
        for (let lineIndex: number = 1; lineIndex < pastedTexts.length; lineIndex++) {
          const created: PaperItem = PaperStore.createTodoItem(pastedTexts[lineIndex], next.length);
          lastCreatedId = created.id;
          next.push(created);
        }
      } else {
        next.push(this.copyTodoItem(item, next.length));
      }
    }
    this.items = this.renumberItems(next);
    this.savePaper(false);
    const caret: number = pastedTexts.length === 1 ?
      Math.min(pastedTexts[0].length, prefix.length + cleaned[0].length) :
      Math.max(0, pastedTexts[pastedTexts.length - 1].length - suffix.length);
    this.requestTodoFocus(lastCreatedId, false, caret);
  }

  private captureTodoHistory(coalesceKey: string = ''): void {
    this.todoHistory.capture(this.items, coalesceKey);
    this.refreshHistoryState();
  }

  private refreshHistoryState(): void {
    this.canUndoTodo = this.todoHistory.canUndo();
    this.canRedoTodo = this.todoHistory.canRedo();
  }

  private undoTodo(): void {
    const previous: PaperItem[] | null = this.todoHistory.undo(this.items);
    if (previous === null) {
      return;
    }
    this.items = this.renumberItems(previous);
    this.savePaper(false);
    this.syncCapsulesAfterAssociationChange();
    this.refreshHistoryState();
  }

  private redoTodo(): void {
    const next: PaperItem[] | null = this.todoHistory.redo(this.items);
    if (next === null) {
      return;
    }
    this.items = this.renumberItems(next);
    this.savePaper(false);
    this.syncCapsulesAfterAssociationChange();
    this.refreshHistoryState();
  }

  private handleTodoKey(event: KeyEvent, item: PaperItem): boolean {
    if (event.type !== KeyType.Down) {
      return false;
    }
    let shiftPressed: boolean = false;
    let controlPressed: boolean = false;
    if (event.getModifierKeyState !== undefined) {
      try {
        shiftPressed = event.getModifierKeyState(['Shift']);
        controlPressed = event.getModifierKeyState(['Ctrl']);
      } catch (error) {
        shiftPressed = false;
        controlPressed = false;
      }
    }
    if (event.keyCode === KeyCode.KEYCODE_MENU ||
      (event.keyCode === KeyCode.KEYCODE_F10 && shiftPressed)) {
      this.keyboardMenuTodoId = item.id;
      this.contextMenuTodoId = item.id;
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE && this.useCapsuleMode) {
      this.setCollapsed(true);
      return true;
    }
    if (!controlPressed && (event.keyCode === KeyCode.KEYCODE_ENTER ||
      event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER)) {
      this.insertTodoAfter(item.id);
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_DEL && item.text.length === 0 &&
      !item.done && item.linkedPaperId === undefined && item.quickLaunchUri === undefined && this.items.length > 1) {
      this.deleteTodo(item.id);
      return true;
    }
    return false;
  }

  private linkTargets(): PaperData[] {
    const papers: PaperData[] = PaperStore.listPapers();
    const result: PaperData[] = [];
    for (let i: number = 0; i < papers.length; i++) {
      if (papers[i].id !== this.paperId) {
        result.push(papers[i]);
      }
    }
    return result;
  }

  private paperDisplayTitle(paper: PaperData): string {
    return effectivePaperTitle(paper, PaperStore.listPapers(), this.uiLanguage, this.systemLanguage);
  }

  private isPaperLinked(): boolean {
    const papers: PaperData[] = PaperStore.listPapers();
    for (let paperIndex: number = 0; paperIndex < papers.length; paperIndex++) {
      const candidate: PaperData = papers[paperIndex];
      for (let itemIndex: number = 0; itemIndex < candidate.items.length; itemIndex++) {
        if (candidate.items[itemIndex].linkedPaperId === this.paperId) {
          return true;
        }
      }
    }
    return false;
  }

  private linkedPaper(item: PaperItem): PaperData | null {
    if (item.linkedPaperId === undefined) {
      return null;
    }
    return PaperStore.getPaper(item.linkedPaperId);
  }

  private linkedPaperIsActive(item: PaperItem): boolean {
    const target: PaperData | null = this.linkedPaper(item);
    return target !== null && target.isVisible && !target.isCollapsed;
  }

  private quickLaunchFailurePrefix(itemId: string): string {
    return itemId + '\n';
  }

  private quickLaunchFailureKey(item: PaperItem): string {
    return this.quickLaunchFailurePrefix(item.id) + (item.quickLaunchUri ?? '');
  }

  private quickLaunchHasFailed(item: PaperItem): boolean {
    if (item.quickLaunchUri === undefined || item.quickLaunchUri.length === 0) {
      return false;
    }
    return this.failedQuickLaunchKeys.indexOf(this.quickLaunchFailureKey(item)) >= 0;
  }

  private markQuickLaunchFailed(item: PaperItem): void {
    const key: string = this.quickLaunchFailureKey(item);
    if (this.failedQuickLaunchKeys.indexOf(key) >= 0) {
      return;
    }
    const next: string[] = this.failedQuickLaunchKeys.slice();
    next.push(key);
    if (next.length > 32) {
      next.shift();
    }
    this.failedQuickLaunchKeys = next;
  }

  private clearQuickLaunchFailures(itemId: string): void {
    const prefix: string = this.quickLaunchFailurePrefix(itemId);
    const next: string[] = [];
    for (let i: number = 0; i < this.failedQuickLaunchKeys.length; i++) {
      if (!this.failedQuickLaunchKeys[i].startsWith(prefix)) {
        next.push(this.failedQuickLaunchKeys[i]);
      }
    }
    if (next.length !== this.failedQuickLaunchKeys.length) {
      this.failedQuickLaunchKeys = next;
    }
  }

  private linkedPaperButtonLabel(item: PaperItem): string {
    if (item.quickLaunchUri !== undefined) {
      const name: string = this.quickLaunchDisplayName(item);
      const icon: string = item.quickLaunchKind === QUICK_LAUNCH_FOLDER ? '▣ ' : '▤ ';
      const prefix: string = this.quickLaunchHasFailed(item) ? '⚠ ' : icon;
      return prefix + (name.length > 5 ? truncateText(name, 5) : name);
    }
    const target: PaperData | null = this.linkedPaper(item);
    if (target === null) {
      return item.linkedPaperId === undefined ? '⌖' : this.text('link.invalid');
    }
    const title: string = this.paperDisplayTitle(target);
    return '↗ ' + (title.length > 5 ? title.substring(0, 5) : title);
  }

  private responsiveAssociationLabel(item: PaperItem): string {
    if (this.layoutWidth < 260) {
      if (item.quickLaunchUri !== undefined) {
        if (this.quickLaunchHasFailed(item)) {
          return '⚠';
        }
        return item.quickLaunchKind === QUICK_LAUNCH_FOLDER ? '▣' : '▤';
      }
      return item.linkedPaperId !== undefined ? '↗' : '⌖';
    }
    return this.linkedPaperButtonLabel(item);
  }

  private setTodoLink(itemId: string, targetPaperId: string): void {
    if (targetPaperId.length > 0 && (targetPaperId === this.paperId || PaperStore.getPaper(targetPaperId) === null)) {
      return;
    }
    const next: PaperItem[] = cloneTodoItems(this.items);
    let found: boolean = false;
    for (let i: number = 0; i < next.length; i++) {
      if (next[i].id === itemId) {
        found = true;
        next[i].linkedPaperId = targetPaperId.length > 0 ? targetPaperId : undefined;
        next[i].quickLaunchUri = undefined;
        next[i].quickLaunchName = undefined;
        next[i].quickLaunchKind = undefined;
      }
    }
    if (!found) {
      return;
    }
    this.captureTodoHistory();
    this.items = next;
    this.linkingTodoId = '';
    this.clearQuickLaunchFailures(itemId);
    this.savePaper(true);
    this.syncCapsulesAfterAssociationChange();
  }

  private chooseQuickLaunch(itemId: string, kind: string): void {
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      if (kind === QUICK_LAUNCH_FOLDER) {
        options.selectMode = picker.DocumentSelectMode.FOLDER;
      }
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(this.hostContext());
      documentPicker.select(options).then((uris: string[]): void => {
        if (uris.length === 0) {
          return;
        }
        const uri: string = uris[0];
        this.persistQuickLaunchPermission(uri).then((): void => {
          this.setTodoQuickLaunch(itemId, uri, kind);
        }).catch((error: Error): void => {
          this.setTodoQuickLaunch(itemId, uri, kind);
          this.statusMessage = this.formatted('status.quickLaunchPermissionFailed', 'error', error.message);
        });
      }).catch((error: BusinessError): void => {
        this.statusMessage = this.formatted('status.quickLaunchPickerFailed', 'error', error.message);
      });
    } catch (error) {
      this.statusMessage = this.formatted('status.quickLaunchPickerFailed', 'error', String(error));
    }
  }

  private quickLaunchDropTarget(record: unifiedDataChannel.UnifiedRecord): QuickLaunchDropTarget | null {
    const type: string = record.getType().toLowerCase();
    let uri: string = '';
    let folder: boolean = type === uniformTypeDescriptor.UniformDataType.FOLDER ||
      type === uniformTypeDescriptor.UniformDataType.DIRECTORY;
    if (folder) {
      const folderRecord: unifiedDataChannel.Folder = record as unifiedDataChannel.Folder;
      uri = folderRecord.folderUri;
      if (uri.length === 0) {
        uri = folderRecord.uri;
      }
    } else if (type === uniformTypeDescriptor.UniformDataType.FILE_URI) {
      const value: unifiedDataChannel.ValueType = record.getValue();
      uri = typeof value === 'string' ? value : '';
    } else {
      const fileRecord: unifiedDataChannel.File = record as unifiedDataChannel.File;
      uri = fileRecord.uri;
    }
    if (uri.length === 0) {
      return null;
    }
    if (!folder) {
      try {
        folder = fileIo.statSync(uri).isDirectory();
      } catch (error) {
        // Some document providers only make the URI readable after the drop
        // completes. Keep the UDMF type hint and persist permission below.
      }
    }
    return {
      uri: uri,
      kind: folder ? QUICK_LAUNCH_FOLDER : QUICK_LAUNCH_FILE
    };
  }

  private handleTodoQuickLaunchDrop(event: DragEvent, itemId: string): void {
    try {
      const records: unifiedDataChannel.UnifiedRecord[] = event.getData().getRecords();
      let target: QuickLaunchDropTarget | null = null;
      for (let i: number = 0; i < records.length; i++) {
        try {
          target = this.quickLaunchDropTarget(records[i]);
        } catch (error) {
          target = null;
        }
        if (target !== null) {
          break;
        }
      }
      if (target === null) {
        event.setResult(DragResult.DRAG_FAILED);
        this.statusMessage = this.text('status.quickLaunchDropUnsupported');
        return;
      }
      event.setResult(DragResult.DRAG_SUCCESSFUL);
      const droppedTarget: QuickLaunchDropTarget = target;
      this.persistQuickLaunchPermission(droppedTarget.uri).then((): void => {
        this.setTodoQuickLaunch(itemId, droppedTarget.uri, droppedTarget.kind);
      }).catch((error: Error): void => {
        this.setTodoQuickLaunch(itemId, droppedTarget.uri, droppedTarget.kind);
        this.statusMessage = this.formatted('status.quickLaunchPermissionFailed', 'error', error.message);
      });
    } catch (error) {
      event.setResult(DragResult.DRAG_FAILED);
      this.statusMessage = this.text('status.quickLaunchDropUnsupported');
    }
  }

  private handleTodoAssociationDrop(event: DragEvent, itemId: string): void {
    try {
      if (this.handleTodoMoveDrop(event, itemId)) {
        return;
      }
      const records: unifiedDataChannel.UnifiedRecord[] = event.getData().getRecords();
      for (let i: number = 0; i < records.length; i++) {
        const payload: PaperLinkDragPayload | null = parsePaperLinkDragRecord(records[i]);
        if (payload === null) {
          continue;
        }
        if (!this.enablePaperLinks) {
          event.setResult(DragResult.DRAG_FAILED);
          this.statusMessage = this.text('status.paperLinkDropDisabled');
          return;
        }
        const target: PaperData | null = PaperStore.getPaper(payload.paperId);
        if (target === null) {
          event.setResult(DragResult.DRAG_FAILED);
          this.statusMessage = this.text('status.linkedPaperMissing');
          return;
        }
        if (target.id === this.paperId) {
          event.setResult(DragResult.DRAG_FAILED);
          this.statusMessage = this.text('status.paperLinkDropSelf');
          return;
        }
        event.setResult(DragResult.DRAG_SUCCESSFUL);
        this.setTodoLink(itemId, target.id);
        this.statusMessage = this.formatted('status.paperLinkDropLinked', 'title', this.paperDisplayTitle(target));
        return;
      }
      this.handleTodoQuickLaunchDrop(event, itemId);
    } catch (error) {
      event.setResult(DragResult.DRAG_FAILED);
      this.statusMessage = this.text('status.quickLaunchDropUnsupported');
    }
  }

  private async persistQuickLaunchPermission(uri: string): Promise<void> {
    const policy: fileShare.PolicyInfo = {
      uri: uri,
      operationMode: fileShare.OperationMode.READ_MODE
    };
    try {
      await fileShare.persistPermission([policy]);
    } catch (error) {
      throw new Error(String(error));
    }
  }

  private async activateQuickLaunchPermission(uri: string): Promise<void> {
    const policy: fileShare.PolicyInfo = {
      uri: uri,
      operationMode: fileShare.OperationMode.READ_MODE
    };
    try {
      const persisted: boolean[] = await fileShare.checkPersistentPermission([policy]);
      if (persisted.length > 0 && persisted[0]) {
        await fileShare.activatePermission([policy]);
      }
    } catch (error) {
      // Some providers expose only a temporary picker grant or do not support
      // the permission query. The direct activation remains the best effort
      // fallback before access is validated below.
      await fileShare.activatePermission([policy]);
    }
  }

  private isDefinitiveQuickLaunchAccessError(error: BusinessError): boolean {
    return error.code === 13900002 || error.code === 13900012 || error.code === 13900020 ||
      error.code === 14300002;
  }

  private quickLaunchUriAccessState(uri: string): boolean | null {
    let accessError: BusinessError | null = null;
    try {
      if (fileIo.accessSync(uri, fileIo.AccessModeType.READ)) {
        return true;
      }
    } catch (error) {
      accessError = error as BusinessError;
    }
    try {
      fileIo.statSync(uri);
      return true;
    } catch (error) {
      const statError: BusinessError = error as BusinessError;
      if ((accessError !== null && this.isDefinitiveQuickLaunchAccessError(accessError)) ||
        this.isDefinitiveQuickLaunchAccessError(statError)) {
        return false;
      }
    }
    // Provider-specific or cloud URIs can reject fileIo probing while still
    // being openable by a registered viewer. Let viewData be the final check.
    return null;
  }

  private async prepareQuickLaunchUri(uri: string): Promise<boolean | null> {
    try {
      await this.activateQuickLaunchPermission(uri);
    } catch (error) {
      console.warn('activate quick-launch permission failed: ' + String(error));
    }
    return this.quickLaunchUriAccessState(uri);
  }

  private syntacticQuickLaunchParent(uri: string): string {
    let end: number = uri.length;
    const queryIndex: number = uri.indexOf('?');
    const fragmentIndex: number = uri.indexOf('#');
    if (queryIndex >= 0) {
      end = Math.min(end, queryIndex);
    }
    if (fragmentIndex >= 0) {
      end = Math.min(end, fragmentIndex);
    }
    let core: string = uri.substring(0, end);
    while (core.length > 0 && core.endsWith('/')) {
      core = core.substring(0, core.length - 1);
    }
    const schemeIndex: number = core.indexOf('://');
    const minimumSlash: number = schemeIndex >= 0 ? schemeIndex + 3 : 0;
    const slash: number = core.lastIndexOf('/');
    if (slash <= minimumSlash) {
      return '';
    }
    return core.substring(0, slash);
  }

  private quickLaunchParentUris(uri: string): string[] {
    const parents: string[] = [];
    let current: string = uri;
    for (let depth: number = 0; depth < 8; depth++) {
      let parent: string = '';
      try {
        parent = new fileUri.FileUri(current).getFullDirectoryUri();
      } catch (error) {
        parent = '';
      }
      if (parent.length === 0 || parent === current) {
        parent = this.syntacticQuickLaunchParent(current);
      }
      if (parent.length === 0 || parent === current || parents.indexOf(parent) >= 0) {
        break;
      }
      parents.push(parent);
      current = parent;
    }
    return parents;
  }

  private quickLaunchStillMatches(item: PaperItem): boolean {
    for (let i: number = 0; i < this.items.length; i++) {
      if (this.items[i].id === item.id) {
        return this.items[i].quickLaunchUri === item.quickLaunchUri;
      }
    }
    return false;
  }

  private presentQuickLaunchFailure(item: PaperItem, message: string): void {
    if (!this.quickLaunchStillMatches(item)) {
      return;
    }
    this.markQuickLaunchFailed(item);
    this.statusMessage = message;
    this.linkingTodoId = item.id;
  }

  private clearQuickLaunchFailureAfterSuccess(item: PaperItem): void {
    if (!this.quickLaunchStillMatches(item)) {
      return;
    }
    this.clearQuickLaunchFailures(item.id);
    this.statusMessage = '';
    if (this.linkingTodoId === item.id) {
      this.linkingTodoId = '';
    }
  }

  private setTodoQuickLaunch(itemId: string, uri: string, kind: string): void {
    if (uri.length === 0) {
      return;
    }
    const next: PaperItem[] = cloneTodoItems(this.items);
    let found: boolean = false;
    for (let i: number = 0; i < next.length; i++) {
      if (next[i].id === itemId) {
        found = true;
        next[i].linkedPaperId = undefined;
        next[i].quickLaunchUri = truncateText(uri, QUICK_LAUNCH_URI_MAX_LENGTH);
        next[i].quickLaunchName = truncateText(this.nameFromUri(uri), QUICK_LAUNCH_NAME_MAX_LENGTH);
        next[i].quickLaunchKind = kind === QUICK_LAUNCH_FOLDER ? QUICK_LAUNCH_FOLDER : QUICK_LAUNCH_FILE;
      }
    }
    if (!found) {
      return;
    }
    this.captureTodoHistory();
    this.items = next;
    this.linkingTodoId = '';
    this.clearQuickLaunchFailures(itemId);
    this.savePaper(true);
    this.syncCapsulesAfterAssociationChange();
  }

  private nameFromUri(uri: string): string {
    const withoutQuery: string = uri.split('?')[0];
    const slash: number = withoutQuery.lastIndexOf('/');
    const encoded: string = slash >= 0 ? withoutQuery.substring(slash + 1) : withoutQuery;
    if (encoded.length === 0) {
      return '';
    }
    try {
      return decodeURIComponent(encoded);
    } catch (error) {
      return encoded;
    }
  }

  private quickLaunchDisplayName(item: PaperItem): string {
    if (item.quickLaunchName !== undefined && item.quickLaunchName.length > 0) {
      return item.quickLaunchName;
    }
    if (item.quickLaunchUri !== undefined) {
      const derivedName: string = this.nameFromUri(item.quickLaunchUri);
      return derivedName.length > 0 ? derivedName : this.text('quick.unnamed');
    }
    return this.text('quick.unnamed');
  }

  private async openQuickLaunch(item: PaperItem): Promise<void> {
    if (item.quickLaunchUri === undefined || item.quickLaunchUri.length === 0) {
      this.statusMessage = this.text('status.quickLaunchMissing');
      this.linkingTodoId = item.id;
      return;
    }
    const accessState: boolean | null = await this.prepareQuickLaunchUri(item.quickLaunchUri);
    if (accessState === false) {
      this.presentQuickLaunchFailure(item, this.text('status.quickLaunchMissing'));
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: item.quickLaunchUri,
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
    };
    if (item.quickLaunchKind === QUICK_LAUNCH_FOLDER) {
      want.type = uniformTypeDescriptor.UniformDataType.DIRECTORY;
    }
    try {
      await this.hostContext().startAbility(want);
      this.clearQuickLaunchFailureAfterSuccess(item);
    } catch (error) {
      this.presentQuickLaunchFailure(item,
        this.formatted('status.quickLaunchOpenFailed', 'error', String(error)));
    }
  }

  private async openQuickLaunchContainingFolder(item: PaperItem): Promise<void> {
    if (item.quickLaunchUri === undefined || item.quickLaunchUri.length === 0) {
      this.statusMessage = this.text('status.quickLaunchMissing');
      this.linkingTodoId = item.id;
      return;
    }
    const accessState: boolean | null = await this.prepareQuickLaunchUri(item.quickLaunchUri);
    const parentUris: string[] = this.quickLaunchParentUris(item.quickLaunchUri);
    let lastError: string = '';
    for (let i: number = 0; i < parentUris.length; i++) {
      const directoryUri: string = parentUris[i];
      const parentAccessState: boolean | null = await this.prepareQuickLaunchUri(directoryUri);
      if (parentAccessState === false) {
        continue;
      }
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: directoryUri,
        type: uniformTypeDescriptor.UniformDataType.DIRECTORY,
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
      };
      try {
        await this.hostContext().startAbility(want);
        if (accessState === false) {
          this.presentQuickLaunchFailure(item, this.text('status.quickLaunchMissing'));
        } else {
          this.clearQuickLaunchFailureAfterSuccess(item);
        }
        return;
      } catch (error) {
        lastError = String(error);
      }
    }
    const detail: string = lastError.length > 0 ? lastError : item.quickLaunchUri;
    const message: string = this.formatted('status.quickLaunchContainingFolderFailed', 'error', detail) +
      ' · ' + this.text('status.quickLaunchMissing');
    this.presentQuickLaunchFailure(item, message);
  }

  private async openMarkdownExternally(): Promise<void> {
    if (this.paper === null || this.paper.type !== PAPER_TYPE_NOTE) {
      return;
    }
    this.savePaper(true);
    try {
      const latest: PaperData | null = PaperStore.getPaper(this.paperId);
      if (latest !== null) {
        await ExternalMarkdown.open(this.hostContext(), latest);
      }
    } catch (error) {
      this.statusMessage = this.formatted('status.externalMarkdownOpenFailed', 'error', String(error));
    }
  }

  private openTodoAssociation(item: PaperItem): void {
    if (item.quickLaunchUri !== undefined) {
      this.openQuickLaunch(item);
    } else if (item.linkedPaperId !== undefined) {
      this.openLinkedPaper(item);
    } else {
      this.linkingTodoId = item.id;
    }
  }

  private hasTodoAssociation(item: PaperItem): boolean {
    return item.linkedPaperId !== undefined || item.quickLaunchUri !== undefined;
  }

  private supportsFolderQuickLaunch(): boolean {
    return deviceInfo.deviceType === '2in1';
  }

  private openLinkedPaper(item: PaperItem): void {
    const target: PaperData | null = this.linkedPaper(item);
    if (target === null) {
      this.statusMessage = this.text('status.linkedPaperMissing');
      this.linkingTodoId = item.id;
      return;
    }
    const action: string = resolveLinkedPaperAction(target.isVisible, target.isCollapsed,
      this.collapseExpandedEdgeCapsuleOnClick);
    let request: Promise<void>;
    if (action === PAPER_ACTION_COLLAPSE) {
      request = DesktopShell.setPaperCollapsed(this.hostContext(), target.id, true);
    } else if (action === PAPER_ACTION_EXPAND) {
      request = DesktopShell.setPaperCollapsed(this.hostContext(), target.id, false);
    } else {
      request = DesktopShell.startPaper(this.hostContext(), target.id, 'show').then((): void => {});
    }
    request.catch((error: Error): void => {
      this.statusMessage = this.formatted('status.openLinkedPaperFailed', 'error', error.message);
    });
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
    this.content = truncateText(value, NOTE_MAX_LENGTH);
    if (value.length > NOTE_MAX_LENGTH) {
      this.statusMessage = this.text('status.noteLengthLimit');
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
    const insertion: NoteInsertion = this.buildNoteBlockInsertion(snippet);
    if (insertion.value.length > NOTE_MAX_LENGTH) {
      this.statusMessage = this.text('status.noteLengthLimit');
      return;
    }
    this.content = insertion.value;
    this.savePaper(false);
    setTimeout((): void => this.noteController.caretPosition(insertion.caret), 0);
  }

  private currentNoteSelection(): NoteTextSelection {
    try {
      const selection: TextRange = this.noteController.getSelection();
      const start: number = this.clamp(selection.start ?? this.content.length, 0, this.content.length);
      const end: number = this.clamp(selection.end ?? start, 0, this.content.length);
      return { start: start, end: end };
    } catch (error) {
      return { start: this.content.length, end: this.content.length };
    }
  }

  private applyNoteEdit(result: NoteEditResult): boolean {
    if (!result.handled) {
      return false;
    }
    if (result.nextText.length > NOTE_MAX_LENGTH) {
      this.statusMessage = this.text('status.noteLengthLimit');
      return true;
    }

    const previous: string = this.content;
    let prefix: number = 0;
    const comparableLength: number = Math.min(previous.length, result.nextText.length);
    while (prefix < comparableLength && previous.charAt(prefix) === result.nextText.charAt(prefix)) {
      prefix += 1;
    }
    let suffix: number = 0;
    while (suffix < previous.length - prefix && suffix < result.nextText.length - prefix &&
      previous.charAt(previous.length - 1 - suffix) === result.nextText.charAt(result.nextText.length - 1 - suffix)) {
      suffix += 1;
    }
    const deleteEnd: number = previous.length - suffix;
    const inserted: string = result.nextText.substring(prefix, result.nextText.length - suffix);
    try {
      if (deleteEnd > prefix) {
        this.noteController.deleteText({ start: prefix, end: deleteEnd });
      }
      if (inserted.length > 0) {
        this.noteController.addText(inserted, { offset: prefix });
      }
    } catch (error) {
      console.warn('controller note edit failed: ' + String(error));
    }
    this.updateNote(result.nextText);
    setTimeout((): void => {
      this.noteController.setTextSelection(result.selection.start, result.selection.end);
    }, 0);
    return true;
  }

  private markdownLinkLabel(): string {
    const sample: string = this.text('markdown.sampleLink');
    const closing: number = sample.indexOf(']');
    return sample.startsWith('[') && closing > 1 ? sample.substring(1, closing) : 'link';
  }

  private formatNoteBold(): void {
    this.applyNoteEdit(applyMarkdownBold(this.content, this.currentNoteSelection()));
  }

  private formatNoteItalic(): void {
    this.applyNoteEdit(applyMarkdownItalic(this.content, this.currentNoteSelection()));
  }

  private formatNoteWrap(prefix: string, suffix: string): void {
    this.applyNoteEdit(wrapMarkdownSelection(this.content, this.currentNoteSelection(), prefix, suffix));
  }

  private formatNoteLinePrefix(prefix: string): void {
    this.applyNoteEdit(insertMarkdownLinePrefix(this.content, this.currentNoteSelection(), prefix));
  }

  private formatNoteCode(): void {
    this.applyNoteEdit(applyMarkdownCode(this.content, this.currentNoteSelection()));
  }

  private formatNoteLink(): void {
    this.applyNoteEdit(insertMarkdownLink(this.content, this.currentNoteSelection(), this.markdownLinkLabel()));
  }

  private buildNoteBlockInsertion(block: string): NoteInsertion {
    let start: number = this.content.length;
    let end: number = this.content.length;
    if (!this.isNoteBrowsing) {
      try {
        const selection: TextRange = this.noteController.getSelection();
        start = this.clamp(selection.start ?? this.content.length, 0, this.content.length);
        end = this.clamp(selection.end ?? start, start, this.content.length);
      } catch (error) {
        start = this.content.length;
        end = this.content.length;
      }
    }
    return this.buildNoteBlockInsertionAt(block, { start: start, end: end });
  }

  private buildNoteBlockInsertionAt(block: string, selection: NoteTextSelection): NoteInsertion {
    const start: number = this.clamp(Math.min(selection.start, selection.end), 0, this.content.length);
    const end: number = this.clamp(Math.max(selection.start, selection.end), start, this.content.length);
    const before: string = this.content.substring(0, start);
    const after: string = this.content.substring(end);
    const leadingBreak: string = before.length > 0 && !before.endsWith('\n') ? '\n' : '';
    const trailingBreak: string = after.length > 0 && !after.startsWith('\n') ? '\n' : '';
    const inserted: string = leadingBreak + block + trailingBreak;
    return {
      value: before + inserted + after,
      caret: start + inserted.length
    };
  }

  private continueMarkdownList(value: InsertValue): boolean {
    if (value.insertValue !== '\n' && value.insertValue !== '\r\n' && value.insertValue !== '\r') {
      return true;
    }
    const selection: NoteTextSelection = this.currentNoteSelection();
    if (selection.start !== selection.end) {
      return true;
    }
    const offset: number = this.clamp(value.insertOffset, 0, this.content.length);
    const result: NoteEditResult = handleMarkdownListEnter(this.content, { start: offset, end: offset });
    return result.handled ? !this.applyNoteEdit(result) : true;
  }

  private handleNoteKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) {
      return false;
    }
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE && this.useCapsuleMode) {
      this.setCollapsed(true);
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER) {
      try {
        if (event.getModifierKeyState !== undefined &&
          (event.getModifierKeyState(['Ctrl']) || event.getModifierKeyState(['Alt']) ||
            event.getModifierKeyState(['Shift']))) {
          return false;
        }
      } catch (error) {
        return false;
      }
      const result: NoteEditResult = handleMarkdownListEnter(this.content, this.currentNoteSelection());
      return result.handled ? this.applyNoteEdit(result) : false;
    }
    let ctrl: boolean = false;
    try {
      ctrl = event.getModifierKeyState !== undefined && event.getModifierKeyState(['Ctrl']);
    } catch (error) {
      return false;
    }
    if (!ctrl) {
      return false;
    }
    if (event.keyCode === KeyCode.KEYCODE_B) {
      this.formatNoteBold();
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_I) {
      this.formatNoteItalic();
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_K) {
      this.formatNoteLink();
      return true;
    }
    return false;
  }

  private handleNoteAxis(event: AxisEvent): void {
    if (event.getModifierKeyState === undefined) {
      return;
    }
    try {
      if (!event.getModifierKeyState(['Ctrl'])) {
        return;
      }
    } catch (error) {
      return;
    }
    const delta: number = event.getVerticalAxisValue();
    if (Math.abs(delta) < 0.001) {
      return;
    }
    this.changeTextZoom(delta > 0 ? -0.1 : 0.1);
  }

  private chooseNoteImage(): void {
    if (this.paper === null || this.paper.type !== PAPER_TYPE_NOTE || this.imageImporting) {
      return;
    }
    const generation: number = ++this.imageOperationGeneration;
    this.prepareNoteImageInsertion();
    this.imageImporting = true;
    this.statusMessage = this.text('status.imageImporting');
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 10;
      options.fileSuffixFilters = [this.text('image.filterLabel') + '|.png,.jpg,.jpeg,.webp,.gif,.bmp,.tif,.tiff'];
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(this.hostContext());
      documentPicker.select(options).then((uris: string[]): void => {
        if (!this.isCurrentImageOperation(generation)) {
          return;
        }
        if (uris.length === 0) {
          this.finishNoteImageInteraction();
          this.statusMessage = '';
          return;
        }
        this.importNoteImages(uris, generation).catch((error: Error): void => {
          if (this.isCurrentImageOperation(generation)) {
            this.finishNoteImageInteraction();
            this.statusMessage = this.text('status.imageImportFailedGeneric');
          }
          console.error('import note image failed: ' + error.message);
        });
      }).catch((error: BusinessError): void => {
        if (this.isCurrentImageOperation(generation)) {
          this.finishNoteImageInteraction();
          this.statusMessage = this.formatted('status.imagePickerFailed', 'error', error.message);
        }
      });
    } catch (error) {
      this.finishNoteImageInteraction();
      this.statusMessage = this.formatted('status.imagePickerFailed', 'error', String(error));
    }
  }

  private async importNoteImages(uris: string[], generation: number): Promise<void> {
    if (this.paper === null || this.paper.type !== PAPER_TYPE_NOTE) {
      return;
    }
    const ownerId: string = this.paper.id;
    const context: common.UIAbilityContext = this.hostContext();
    const imported: NoteImageAsset[] = [];
    let reservedBytes: number = PaperStore.getNoteImageTotalBytes();
    let lastFailure: NoteImageImportResult | undefined = undefined;
    const count: number = Math.min(10, uris.length);
    for (let i: number = 0; i < count; i++) {
      if (!this.isCurrentImageOperation(generation)) {
        break;
      }
      const result: NoteImageImportResult = await NoteImageStore.importFromUri(
        context, ownerId, uris[i], this.autoCompressLargeImages, reservedBytes,
        (): boolean => !this.isCurrentImageOperation(generation));
      if (result.asset === undefined) {
        lastFailure = result;
        continue;
      }
      imported.push(result.asset);
      reservedBytes += result.asset.byteLength;
    }
    if (!this.isCurrentImageOperation(generation)) {
      for (let i: number = 0; i < imported.length; i++) {
        NoteImageStore.deleteAsset(context, imported[i], ownerId);
      }
      return;
    }
    if (imported.length === 0) {
      this.finishNoteImageInteraction();
      this.statusMessage = lastFailure === undefined ? this.text('status.imageImportFailedGeneric') :
        this.imageImportErrorMessage(lastFailure);
      return;
    }
    const owner: PaperData | null = PaperStore.getPaper(ownerId);
    if (owner === null || owner.type !== PAPER_TYPE_NOTE) {
      this.finishNoteImageInteraction();
      for (let i: number = 0; i < imported.length; i++) {
        NoteImageStore.deleteAsset(context, imported[i], ownerId);
      }
      return;
    }
    const markers: string[] = [];
    for (let i: number = 0; i < imported.length; i++) {
      markers.push('![image|100%](i:' + imported[i].id + ')');
    }
    const insertion: NoteInsertion = this.buildNoteBlockInsertionAt(
      markers.join('\n'), this.pendingNoteImageSelection());
    if (insertion.value.length > NOTE_MAX_LENGTH) {
      this.finishNoteImageInteraction();
      for (let i: number = 0; i < imported.length; i++) {
        NoteImageStore.deleteAsset(context, imported[i], ownerId);
      }
      this.statusMessage = this.text('status.noteLengthLimit');
      return;
    }
    const registeredIds: string[] = [];
    let registrationFailed: boolean = false;
    for (let i: number = 0; i < imported.length; i++) {
      try {
        if (!PaperStore.addNoteImage(imported[i])) {
          registrationFailed = true;
          break;
        }
      } catch (error) {
        registrationFailed = true;
        console.error('register note image failed: ' + String(error));
        break;
      }
      registeredIds.push(imported[i].id);
    }
    if (registrationFailed) {
      for (let i: number = 0; i < registeredIds.length; i++) {
        try {
          PaperStore.removeNoteImage(registeredIds[i]);
        } catch (error) {
          console.error('roll back note image metadata failed: ' + String(error));
        }
      }
      for (let i: number = 0; i < imported.length; i++) {
        NoteImageStore.deleteAsset(context, imported[i], ownerId);
      }
      this.finishNoteImageInteraction();
      this.statusMessage = this.text('status.imageStorageFull');
      return;
    }
    this.content = insertion.value;
    this.finishNoteImageInteraction();
    this.savePaper(true);
    this.refreshMarkdown();
    setTimeout((): void => this.noteController.caretPosition(insertion.caret), 0);
    this.statusMessage = this.text('status.imageImported');
  }

  private async importNoteImage(uri: string, generation: number): Promise<void> {
    if (this.paper === null || this.paper.type !== PAPER_TYPE_NOTE) {
      return;
    }
    const ownerId: string = this.paper.id;
    const context: common.UIAbilityContext = this.hostContext();
    const result: NoteImageImportResult = await NoteImageStore.importFromUri(
      context, ownerId, uri, this.autoCompressLargeImages, PaperStore.getNoteImageTotalBytes(),
      (): boolean => !this.isCurrentImageOperation(generation));
    this.applyNoteImageImportResult(result, generation, context, ownerId);
  }

  private async importNotePixelMap(pixelMap: image.PixelMap, generation: number): Promise<void> {
    if (this.paper === null || this.paper.type !== PAPER_TYPE_NOTE) {
      try {
        await pixelMap.release();
      } catch (error) {
        console.warn('release unused clipboard image failed: ' + String(error));
      }
      return;
    }
    try {
      const ownerId: string = this.paper.id;
      const context: common.UIAbilityContext = this.hostContext();
      const result: NoteImageImportResult = await NoteImageStore.importFromPixelMap(
        context, ownerId, pixelMap, this.autoCompressLargeImages,
        PaperStore.getNoteImageTotalBytes(), (): boolean => !this.isCurrentImageOperation(generation));
      this.applyNoteImageImportResult(result, generation, context, ownerId);
    } finally {
      try {
        await pixelMap.release();
      } catch (error) {
        console.warn('release clipboard image failed: ' + String(error));
      }
    }
  }

  private applyNoteImageImportResult(result: NoteImageImportResult, generation: number,
    context: common.UIAbilityContext, ownerId: string): void {
    if (!this.isCurrentImageOperation(generation)) {
      if (result.asset !== undefined) {
        NoteImageStore.deleteAsset(context, result.asset, ownerId);
      }
      return;
    }
    this.finishNoteImageInteraction();
    if (result.asset === undefined) {
      this.statusMessage = this.imageImportErrorMessage(result);
      return;
    }
    const owner: PaperData | null = PaperStore.getPaper(ownerId);
    if (owner === null || owner.type !== PAPER_TYPE_NOTE || result.asset.noteId !== ownerId) {
      NoteImageStore.deleteAsset(context, result.asset, ownerId);
      return;
    }
    const marker: string = '![image|100%](i:' + result.asset.id + ')';
    const insertion: NoteInsertion = this.buildNoteBlockInsertionAt(marker, this.pendingNoteImageSelection());
    if (insertion.value.length > NOTE_MAX_LENGTH) {
      NoteImageStore.deleteAsset(context, result.asset, ownerId);
      this.statusMessage = this.text('status.noteLengthLimit');
      return;
    }
    let registered: boolean = false;
    try {
      registered = PaperStore.addNoteImage(result.asset);
    } catch (error) {
      console.error('register note image failed: ' + String(error));
    }
    if (!registered) {
      NoteImageStore.deleteAsset(context, result.asset, ownerId);
      this.statusMessage = this.text('status.imageStorageFull');
      return;
    }
    this.content = insertion.value;
    this.savePaper(true);
    this.refreshMarkdown();
    setTimeout((): void => this.noteController.caretPosition(insertion.caret), 0);
    this.statusMessage = this.text('status.imageImported');
  }

  private beginPasteNoteImage(result: PasteButtonOnClickResult): number {
    if (result !== PasteButtonOnClickResult.SUCCESS) {
      this.statusMessage = this.text('status.imagePastePermissionFailed');
      return -1;
    }
    if (this.paper === null || this.paper.type !== PAPER_TYPE_NOTE || this.imageImporting) {
      return -1;
    }
    const generation: number = ++this.imageOperationGeneration;
    this.prepareNoteImageInsertion();
    this.imageImporting = true;
    this.statusMessage = this.text('status.imageImporting');
    return generation;
  }

  private pasteNoteImageFromClipboard(result: PasteButtonOnClickResult): void {
    const generation: number = this.beginPasteNoteImage(result);
    if (generation < 0) {
      return;
    }
    try {
      pasteboard.getSystemPasteboard().getData((error: BusinessError, data: pasteboard.PasteData): void => {
        this.consumePastedNoteImage(generation, error, data);
      });
    } catch (error) {
      this.finishImageImportException(generation, new Error(String(error)));
    }
  }

  private consumePastedNoteImage(generation: number, error: BusinessError,
    data: pasteboard.PasteData): void {
    if (error) {
      this.finishImageImportException(generation, new Error(error.message));
      return;
    }
    if (!this.isCurrentImageOperation(generation)) {
      return;
    }
    this.consumePastedNoteImageAsync(generation, data).catch((pasteError: Error): void => {
      this.finishImageImportException(generation, pasteError);
    });
  }

  private async consumePastedNoteImageAsync(generation: number, data: pasteboard.PasteData): Promise<void> {
    const candidate: ClipboardImageCandidate | null = await this.findClipboardImage(data);
    if (!this.isCurrentImageOperation(generation)) {
      if (candidate !== null && candidate.pixelMap !== undefined) {
        await candidate.pixelMap.release();
      }
      return;
    }
    if (candidate !== null && candidate.pixelMap !== undefined) {
      await this.importNotePixelMap(candidate.pixelMap, generation);
      return;
    }
    if (candidate !== null && candidate.uri !== undefined && candidate.uri.length > 0) {
      // The importer validates the actual image bytes, so content URIs do not
      // need a filename extension.
      await this.importNoteImage(candidate.uri, generation);
      return;
    }
    this.finishNoteImageInteraction();
    this.statusMessage = this.text('status.imagePasteUnsupported');
  }

  private async findClipboardImage(data: pasteboard.PasteData): Promise<ClipboardImageCandidate | null> {
    const recordCount: number = data.getRecordCount();
    for (let i: number = 0; i < recordCount; i++) {
      const record: pasteboard.PasteDataRecord = data.getRecord(i);
      if (record.mimeType === pasteboard.MIMETYPE_PIXELMAP) {
        return { pixelMap: record.pixelMap };
      }
      try {
        const types: string[] = record.getValidTypes([pasteboard.MIMETYPE_PIXELMAP]);
        if (types.length > 0) {
          const value: pasteboard.ValueType = await record.getData(pasteboard.MIMETYPE_PIXELMAP);
          return { pixelMap: value as image.PixelMap };
        }
      } catch (error) {
        console.warn('read clipboard pixel map record failed: ' + String(error));
      }
    }
    for (let i: number = 0; i < recordCount; i++) {
      const record: pasteboard.PasteDataRecord = data.getRecord(i);
      if (record.mimeType === pasteboard.MIMETYPE_TEXT_URI && record.uri.length > 0) {
        return { uri: record.uri };
      }
      try {
        const types: string[] = record.getValidTypes([pasteboard.MIMETYPE_TEXT_URI]);
        if (types.length > 0) {
          const value: pasteboard.ValueType = await record.getData(pasteboard.MIMETYPE_TEXT_URI);
          if (typeof value === 'string' && value.length > 0) {
            return { uri: value };
          }
        }
      } catch (error) {
        console.warn('read clipboard URI record failed: ' + String(error));
      }
    }
    return null;
  }

  private startNativeWindowMove(event: TouchEvent): void {
    if (event.type !== TouchType.Down || this.isCollapsed || this.titleEditing) {
      return;
    }
    const win: window.Window | undefined = this.currentWindow();
    if (win === undefined) {
      return;
    }
    win.startMoving().catch((error: BusinessError): void => {
      console.error('start native paper move failed: ' + error.message);
    });
  }

  private finishImageImportException(generation: number, error: Error): void {
    if (this.isCurrentImageOperation(generation)) {
      this.finishNoteImageInteraction();
      this.statusMessage = this.text('status.imageImportFailedGeneric');
    }
    console.error('import note image failed: ' + error.message);
  }

  private isCurrentImageOperation(generation: number): boolean {
    return this.componentActive && generation === this.imageOperationGeneration;
  }

  private prepareNoteImageInsertion(): void {
    this.pendingImageContent = this.content;
    this.pendingImageSelection = this.isNoteBrowsing ?
      { start: this.content.length, end: this.content.length } : this.currentNoteSelection();
  }

  private pendingNoteImageSelection(): NoteTextSelection {
    if (this.pendingImageContent === this.content) {
      return this.pendingImageSelection;
    }
    // Do not replace an unrelated range if the user edited while the image
    // was being copied or compressed; append to the latest note instead.
    return { start: this.content.length, end: this.content.length };
  }

  private handleNoteImageDrop(event: DragEvent): void {
    if (this.paper === null || this.paper.type !== PAPER_TYPE_NOTE || this.imageImporting) {
      event.setResult(DragResult.DRAG_FAILED);
      return;
    }
    try {
      const records: unifiedDataChannel.UnifiedRecord[] = event.getData().getRecords();
      const uris: string[] = [];
      for (let i: number = 0; i < records.length && uris.length < 10; i++) {
        let uri: string = '';
        const type: string = records[i].getType().toLowerCase();
        if (type.indexOf('image') >= 0) {
          uri = (records[i] as unifiedDataChannel.Image).imageUri;
        } else if (type === uniformTypeDescriptor.UniformDataType.FILE) {
          uri = (records[i] as unifiedDataChannel.File).uri;
        } else if (type === uniformTypeDescriptor.UniformDataType.FILE_URI) {
          const value: unifiedDataChannel.ValueType = records[i].getValue();
          uri = typeof value === 'string' ? value : '';
        }
        if (uri.length > 0) {
          let duplicate: boolean = false;
          for (let j: number = 0; j < uris.length; j++) {
            if (uris[j] === uri) {
              duplicate = true;
              break;
            }
          }
          if (!duplicate) {
            uris.push(uri);
          }
        }
      }
      if (uris.length === 0) {
        event.setResult(DragResult.DRAG_FAILED);
        this.statusMessage = this.text('status.imageDropUnsupported');
        return;
      }
      event.setResult(DragResult.DRAG_SUCCESSFUL);
      const generation: number = ++this.imageOperationGeneration;
      this.prepareNoteImageInsertion();
      this.imageImporting = true;
      this.statusMessage = this.text('status.imageImporting');
      this.importNoteImages(uris, generation).catch((error: Error): void => {
        if (this.isCurrentImageOperation(generation)) {
          this.finishNoteImageInteraction();
          this.statusMessage = this.text('status.imageImportFailedGeneric');
        }
        console.error('import dropped image failed: ' + error.message);
      });
    } catch (error) {
      event.setResult(DragResult.DRAG_FAILED);
      this.statusMessage = this.formatted('status.imageImportFailed', 'error', String(error));
    }
  }

  private isSupportedImageUri(uri: string): boolean {
    const path: string = uri.split('?')[0].split('#')[0].toLowerCase();
    return path.endsWith('.png') || path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.webp') ||
      path.endsWith('.gif') || path.endsWith('.bmp') || path.endsWith('.tif') || path.endsWith('.tiff');
  }

  private imageImportErrorMessage(result: NoteImageImportResult): string {
    if (result.errorCode === IMAGE_IMPORT_INPUT_TOO_LARGE) {
      return this.text('status.imageInputTooLarge');
    }
    if (result.errorCode === IMAGE_IMPORT_DIMENSIONS_TOO_LARGE) {
      return this.text('status.imageDimensionsTooLarge');
    }
    if (result.errorCode === IMAGE_IMPORT_COMPRESSION_DISABLED) {
      return this.text('status.imageCompressionDisabled');
    }
    if (result.errorCode === IMAGE_IMPORT_ANIMATED_TOO_LARGE) {
      return this.text('status.imageAnimatedTooLarge');
    }
    if (result.errorCode === IMAGE_IMPORT_STORAGE_FULL) {
      return this.text('status.imageStorageFull');
    }
    if (result.errorCode === IMAGE_IMPORT_OUTPUT_TOO_LARGE) {
      return this.text('status.imageOutputTooLarge');
    }
    if (result.errorCode === IMAGE_IMPORT_INVALID) {
      return this.text('status.imageInvalid');
    }
    return this.text('status.imageImportFailedGeneric');
  }

  private noteImageAsset(id: string | undefined): NoteImageAsset | null {
    return id === undefined ? null : PaperStore.getNoteImageForPaper(id, this.paperId);
  }

  private markdownImageAvailable(line: MarkdownLine): boolean {
    const asset: NoteImageAsset | null = this.noteImageAsset(line.imageId);
    return asset !== null && !this.isBrokenNoteImage(asset.id) && NoteImageStore.assetExists(this.hostContext(), asset);
  }

  private isBrokenNoteImage(id: string): boolean {
    for (let i: number = 0; i < this.brokenNoteImageIds.length; i++) {
      if (this.brokenNoteImageIds[i] === id) {
        return true;
      }
    }
    return false;
  }

  private markNoteImageBroken(id: string | undefined): void {
    if (id === undefined || this.isBrokenNoteImage(id)) {
      return;
    }
    const next: string[] = this.brokenNoteImageIds.slice();
    next.push(id);
    this.brokenNoteImageIds = next;
  }

  private markdownImageUri(line: MarkdownLine): string {
    const asset: NoteImageAsset | null = this.noteImageAsset(line.imageId);
    return asset === null ? '' : NoteImageStore.assetUri(this.hostContext(), asset);
  }

  private markdownImageAspect(line: MarkdownLine): number {
    const asset: NoteImageAsset | null = this.noteImageAsset(line.imageId);
    return asset === null || asset.height <= 0 ? 1 : asset.width / asset.height;
  }

  private markdownImageWidth(line: MarkdownLine): number {
    const availableWidth: number = Math.max(48, this.layoutWidth - 24);
    const percent: number = line.imagePercent === undefined ? 100 : line.imagePercent;
    const declaredWidth: number | undefined = line.imageWidth;
    const targetWidth: number = declaredWidth !== undefined && Number.isFinite(declaredWidth) ?
      declaredWidth * percent / 100 : availableWidth * percent / 100;
    return this.clamp(targetWidth, 48, availableWidth);
  }

  private markdownImageHeight(line: MarkdownLine): number {
    const width: number = this.markdownImageWidth(line);
    const declaredAspect: number | null = line.imageWidth !== undefined && line.imageHeight !== undefined &&
      line.imageHeight > 0 ? line.imageWidth / line.imageHeight : null;
    const naturalHeight: number = width / Math.max(0.01,
      declaredAspect === null ? this.markdownImageAspect(line) : declaredAspect);
    const paperHeight: number = this.paper === null ? 360 : this.paper.expandedHeight;
    return this.clamp(naturalHeight, 48, Math.max(160, paperHeight - 120));
  }

  private markdownImageAlt(line: MarkdownLine): string {
    return line.imageAlt !== undefined && line.imageAlt.length > 0 ? line.imageAlt : this.text('image.alt');
  }

  private changeTextZoom(delta: number): void {
    this.textZoom = Math.round(Math.max(0.5, Math.min(1.5, this.textZoom + delta)) * 10) / 10;
    this.savePaper(false);
  }

  private resetTextZoom(): void {
    this.textZoom = 1;
    this.savePaper(false);
  }

  private openMarkdownLink(url: string | undefined): void {
    if (url === undefined || url.length === 0) {
      return;
    }
    this.lastMarkdownLinkActivatedAt = Date.now();
    this.hostContext().openLink(url).catch((error: BusinessError): void => {
      this.statusMessage = this.formatted('status.openLinkFailed', 'error', error.message);
    });
  }

  private noteLineOffset(line: MarkdownLine): number {
    const marker: string = 'line_';
    if (!line.id.startsWith(marker)) {
      return this.content.length;
    }
    const lineIndex: number = Number(line.id.substring(marker.length));
    if (!Number.isFinite(lineIndex) || lineIndex <= 0) {
      return 0;
    }
    let offset: number = 0;
    let currentLine: number = 0;
    while (offset < this.content.length && currentLine < lineIndex) {
      const nextBreak: number = this.content.indexOf('\n', offset);
      if (nextBreak < 0) {
        return this.content.length;
      }
      offset = nextBreak + 1;
      currentLine += 1;
    }
    return offset;
  }

  private enterNoteEditFromPreview(offset: number = this.content.length): void {
    if (Date.now() - this.lastMarkdownLinkActivatedAt < 180) {
      return;
    }
    if (this.isNoteBrowsing) {
      this.toggleNoteBrowse();
      setTimeout((): void => {
        try {
          this.getUIContext().getFocusController().requestFocus('paper_note_editor');
          const target: number = this.clamp(offset, 0, this.content.length);
          this.noteController.setTextSelection(target, target);
        } catch (error) {
          console.warn('focus note editor failed: ' + String(error));
        }
      }, 0);
    }
  }

  private handlePaperKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) {
      return false;
    }
    let altPressed: boolean = false;
    let controlPressed: boolean = false;
    let shiftPressed: boolean = false;
    try {
      altPressed = event.getModifierKeyState !== undefined && event.getModifierKeyState(['Alt']);
      controlPressed = event.getModifierKeyState !== undefined && event.getModifierKeyState(['Ctrl']);
      shiftPressed = event.getModifierKeyState !== undefined && event.getModifierKeyState(['Shift']);
    } catch (error) {
      altPressed = false;
      controlPressed = false;
      shiftPressed = false;
    }
    if (altPressed && event.keyCode === KeyCode.KEYCODE_F4) {
      if (resolveSystemCloseAction() === PAPER_ACTION_HIDE) {
        this.hidePaper();
      }
      return true;
    }
    if (controlPressed && this.paper !== null && this.paper.type === PAPER_TYPE_TODO &&
      this.focusedTodoId.length === 0) {
      if (event.keyCode === KeyCode.KEYCODE_Z) {
        if (shiftPressed) {
          this.redoTodo();
        } else {
          this.undoTodo();
        }
        return true;
      }
      if (event.keyCode === KeyCode.KEYCODE_Y) {
        this.redoTodo();
        return true;
      }
    }
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE && !this.isCollapsed && this.useCapsuleMode) {
      this.setCollapsed(true);
      return true;
    }
    return false;
  }

  private headingSize(level: number): number {
    if (level <= 1) {
      return Math.round(this.noteFontSize() * 1.85);
    }
    if (level === 2) {
      return Math.round(this.noteFontSize() * 1.55);
    }
    if (level === 3) {
      return Math.round(this.noteFontSize() * 1.35);
    }
    return Math.round(this.noteFontSize() * 1.15);
  }

  private markdownLineColor(line: MarkdownLine): string {
    return line.kind === MD_KIND_QUOTE ? this.mutedColor() : this.textColor();
  }

  private markdownLineFontSize(line: MarkdownLine): number {
    return line.kind === MD_KIND_HEADING ? this.headingSize(line.level) : this.noteFontSize();
  }

  @Builder
  private MarkdownRichLine(line: MarkdownLine) {
    Text() {
      if (line.kind === MD_KIND_QUOTE) {
        Span('│ ')
          .fontColor(this.mutedColor())
      }
      if (line.inlineTokens !== undefined && line.inlineTokens.length > 0) {
        ForEach(line.inlineTokens, (token: MarkdownInlineToken) => {
          if (token.linkUrl !== undefined) {
            Span(token.text)
              .fontColor(this.accentColor())
              .fontWeight(this.configuredFontWeight(line.kind === MD_KIND_HEADING ||
                this.noteTextBold || token.style.bold))
              .fontStyle(token.style.italic ? FontStyle.Italic : FontStyle.Normal)
              .fontFamily(token.style.code ? 'monospace' : '')
              .decoration({
                type: token.style.strike ? TextDecorationType.LineThrough : TextDecorationType.Underline,
                color: this.accentColor()
              })
              .textBackgroundStyle({
                color: token.style.code ? this.inputColor() : Color.Transparent,
                radius: token.style.code ? 3 : 0
              })
              .onClick((): void => this.openMarkdownLink(token.linkUrl))
          } else {
            Span(token.text)
              .fontColor(this.markdownLineColor(line))
              .fontWeight(this.configuredFontWeight(line.kind === MD_KIND_HEADING ||
                this.noteTextBold || token.style.bold))
              .fontStyle(token.style.italic ? FontStyle.Italic : FontStyle.Normal)
              .fontFamily(token.style.code ? 'monospace' : '')
              .decoration({
                type: token.style.strike ? TextDecorationType.LineThrough : TextDecorationType.None,
                color: this.markdownLineColor(line)
              })
              .textBackgroundStyle({
                color: token.style.code ? this.inputColor() : Color.Transparent,
                radius: token.style.code ? 3 : 0
              })
          }
        }, (token: MarkdownInlineToken): string => token.sourceStart.toString() + '_' +
          token.sourceEnd.toString() + '_' + token.kind)
      } else {
        Span(line.text.length > 0 ? line.text : ' ')
          .fontColor(line.linkUrl !== undefined ? this.accentColor() : this.markdownLineColor(line))
      }
    }
    .width('100%')
    .fontSize(this.markdownLineFontSize(line))
    .fontWeight(this.configuredFontWeight(line.kind === MD_KIND_HEADING || this.noteTextBold))
    .fontColor(this.markdownLineColor(line))
    .padding({
      left: line.kind === MD_KIND_QUOTE ? 6 :
        (line.kind === MD_KIND_BULLET || line.kind === MD_KIND_ORDERED ? 10 : 0),
      top: line.kind === MD_KIND_QUOTE ? 4 : 0,
      bottom: line.kind === MD_KIND_QUOTE ? 4 : 0
    })
    .margin({
      top: line.kind === MD_KIND_HEADING ? 4 : 0,
      bottom: line.kind === MD_KIND_HEADING ? 2 : 0
    })
    .onClick((): void => {
      if (line.inlineTokens === undefined) {
        this.openMarkdownLink(line.linkUrl);
      }
      this.enterNoteEditFromPreview(this.noteLineOffset(line));
    })
  }

  private clamp(value: number, minValue: number, maxValue: number): number {
    return Math.max(minValue, Math.min(value, maxValue));
  }

  private canCollapseToCapsule(): boolean {
    return this.useCapsuleMode && this.paper !== null && PaperStore.canPaperDisplayAsCapsule(this.paper);
  }

  private topBarActionItemCount(): number {
    let count: number = 0;
    if (this.enablePaperLinks) {
      count += 1;
    }
    if (this.showTopBarExternalOpenButton && this.paper !== null && this.paper.type === PAPER_TYPE_NOTE) {
      count += 1;
    }
    if (this.showTopBarNewTodoButton) {
      count += 1;
    }
    if (this.showTopBarNewNoteButton) {
      count += 1;
    }
    return count;
  }

  private topBarActionGroupWidth(): number {
    let width: number = 0;
    if (this.enablePaperLinks) {
      width += 26;
    }
    if (this.showTopBarExternalOpenButton && this.paper !== null && this.paper.type === PAPER_TYPE_NOTE) {
      width += 38;
    }
    if (this.showTopBarNewTodoButton) {
      width += 34;
    }
    if (this.showTopBarNewNoteButton) {
      width += 34;
    }
    const count: number = this.topBarActionItemCount();
    return width + Math.max(0, count - 1) * 2;
  }

  private showTopBarActionGroup(): boolean {
    const actionWidth: number = this.topBarActionGroupWidth();
    // Pin + title minimum + drag strip + dismiss + outer gaps/padding must all
    // fit before the original action cluster is allowed to appear.
    return actionWidth > 0 && this.layoutWidth >= 134 + actionWidth;
  }

  private showTopBarTitle(): boolean {
    return this.layoutWidth >= 150;
  }

  @Builder
  private HeaderBar() {
    Row({ space: 2 }) {
      Button() {
        Image(this.alwaysOnTop ? $r('app.media.pin_filled') : $r('app.media.pin_outline'))
          .width(15)
          .height(15)
          .fillColor(this.alwaysOnTop ? this.accentColor() : this.mutedColor())
      }
        .width(28)
        .height(30)
        .type(ButtonType.Normal)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText(this.text(this.alwaysOnTop ? 'action.unpin' : 'action.pin'))
        .onClick((): void => this.toggleTopmost())

      if (this.showTopBarTitle()) {
        if (this.titleEditing) {
          TextInput({
            text: this.title,
            placeholder: this.text(this.paper !== null && this.paper.type === PAPER_TYPE_NOTE ?
              'paper.note' : 'paper.todo'),
            controller: this.titleController
          })
            .id('paper_title_input')
            .constraintSize({ minWidth: 40, maxWidth: 92 })
            .height(30)
            .fontSize(this.titleFontSize())
            .fontWeight(this.configuredFontWeight(this.titleTextBold))
            .fontColor(this.textColor())
            .placeholderColor(this.mutedColor())
            .backgroundColor(Color.Transparent)
            .padding(0)
            .maxLength(TITLE_MAX_LENGTH)
            .onChange((value: string): void => {
              this.title = value;
            })
            .onSubmit((): void => this.finishTitleEdit())
            .onBlur((): void => this.finishTitleEdit())
            .onKeyPreIme((event: KeyEvent): boolean => this.handleTitleKey(event))
            .onKeyEvent((event: KeyEvent): boolean => this.handleTitleKey(event))
        } else {
          Text(this.titleOrFallback())
            .constraintSize({ minWidth: 40, maxWidth: 92 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontSize(this.titleFontSize())
            .fontWeight(this.configuredFontWeight(this.titleTextBold))
            .fontColor(this.textColor())
            .padding({ left: 2, right: 2 })
            .onClick((): void => this.beginTitleEdit())
        }
      }

      Blank()
        .layoutWeight(1)
        .height(30)
        .onTouch((event: TouchEvent): void => this.startNativeWindowMove(event))

      if (this.showTopBarActionGroup()) {
        Row({ space: 2 }) {
          if (this.enablePaperLinks) {
            Stack({ alignContent: Alignment.Center }) {
              Text(this.isPaperLinked() ? '⦿' : '⌖')
                .fontSize(13)
                .fontColor(this.textColor())
                .textAlign(TextAlign.Center)
            }
              .id('paper_link_drag_handle')
              .width(26)
              .height(30)
              .accessibilityText(this.text('link.to'))
              .draggable(true)
              .dragPreview('paper_link_drag_handle')
              .onDragStart((event: DragEvent): DragItemInfo => this.beginPaperLinkDrag(event))
          }

          if (this.showTopBarExternalOpenButton && this.paper !== null && this.paper.type === PAPER_TYPE_NOTE) {
            Button('MD')
              .width(38)
              .height(30)
              .type(ButtonType.Normal)
              .padding(0)
              .fontSize(10)
              .fontColor(this.textColor())
              .backgroundColor(Color.Transparent)
              .accessibilityText(this.text('action.openExternally'))
              .onClick((): void => {
                this.openMarkdownExternally();
              })
          }

          if (this.showTopBarNewTodoButton) {
            Button('＋✓')
              .width(34)
              .height(30)
              .type(ButtonType.Normal)
              .padding(0)
              .fontSize(11)
              .fontColor(this.textColor())
              .backgroundColor(Color.Transparent)
              .accessibilityText(this.text('action.newTodo'))
              .onClick((): void => this.createPaper(PAPER_TYPE_TODO))
          }

          if (this.showTopBarNewNoteButton) {
            Button('＋✎')
              .width(34)
              .height(30)
              .type(ButtonType.Normal)
              .padding(0)
              .fontSize(11)
              .fontColor(this.textColor())
              .backgroundColor(Color.Transparent)
              .accessibilityText(this.text('action.newNote'))
              .onClick((): void => this.createPaper(PAPER_TYPE_NOTE))
          }
        }
        .height(30)
      }

      Button(this.canCollapseToCapsule() ? '─' : '×')
        .width(28)
        .height(30)
        .type(ButtonType.Normal)
        .padding(0)
        .fontSize(13)
        .fontColor(this.mutedColor())
        .backgroundColor(Color.Transparent)
        .accessibilityText(this.text(this.canCollapseToCapsule() ? 'action.collapse' : 'action.hide'))
        .onClick((): void => {
          const action: string = resolveTopBarDismissAction(this.canCollapseToCapsule());
          if (action === PAPER_ACTION_COLLAPSE) {
            this.setCollapsed(true);
          } else if (action === PAPER_ACTION_HIDE) {
            this.hidePaper();
          }
        })
    }
    .width('100%')
    .height(34)
    .padding({ left: 6, right: 6 })
  }

  @Builder
  private TodoContextMenu(item: PaperItem) {
    Menu() {
      MenuItem({ content: this.text(item.done ? 'action.markUndone' : 'action.markDone') })
        .onClick((): void => this.toggleTodo(item.id))
      MenuItem({ content: this.text('action.clearCompleted') })
        .enabled(this.completedCount() > 0)
        .onClick((): void => this.clearCompleted())
      MenuItem({
        content: this.text(this.hasTodoAssociation(item) ? 'action.openAssociation' : 'action.addAssociation')
      })
        .onClick((): void => this.openTodoAssociation(item))
      if (this.hasTodoAssociation(item)) {
        if (item.quickLaunchUri !== undefined) {
          MenuItem({ content: this.text('action.openContainingFolder') })
            .onClick((): void => {
              this.openQuickLaunchContainingFolder(item);
            })
        }
        MenuItem({ content: this.text('action.changeAssociation') })
          .onClick((): void => {
            this.linkingTodoId = item.id;
          })
        MenuItem({ content: this.text('action.removeAssociation') })
          .onClick((): void => this.setTodoLink(item.id, ''))
      }
      MenuItem({ content: this.text('action.deleteTodo') })
        .contentFontColor('#B42318')
        .onClick((): void => this.deleteTodo(item.id))
    }
  }

  @Builder
  private TodoBody() {
    Column() {
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

              TextArea({
                text: item.text,
                placeholder: this.text('placeholder.todoItem'),
                controller: this.todoController(item.id)
              })
                .id(this.todoFocusKey(item.id))
                .layoutWeight(1)
                .minLines(1)
                .textOverflow(TextOverflow.Clip)
                .maxLines(6, { overflowMode: MaxLinesMode.SCROLL })
                .fontSize(this.todoFontSize())
                .fontWeight(this.configuredFontWeight(this.todoTextBold))
                .fontColor(item.done ? this.mutedColor() : this.textColor())
                .decoration({
                  type: item.done ? TextDecorationType.LineThrough : TextDecorationType.None,
                  color: this.mutedColor()
                })
                .placeholderColor(this.mutedColor())
                .backgroundColor(Color.Transparent)
                .padding(0)
                .maxLength(TODO_ITEM_MAX_LENGTH)
                .enterKeyType(EnterKeyType.Next)
                .onChange((value: string): void => this.updateTodoText(item.id, value))
                .onPaste((content: string, event: PasteEvent): void => this.pasteTodoLines(item.id, content, event))
                .onSubmit((): void => this.insertTodoAfter(item.id))
                .onKeyPreIme((event: KeyEvent): boolean => this.handleTodoKey(event, item))
                .onKeyEvent((event: KeyEvent): boolean => this.handleTodoKey(event, item))
                .onFocus((): void => {
                  this.focusedTodoId = item.id;
                })
                .onBlur((): void => {
                  if (this.focusedTodoId === item.id) {
                    this.focusedTodoId = '';
                  }
                  this.todoHistory.breakCoalescing();
                })
                .parallelGesture(
                  TapGesture({ count: 2 })
                    .onAction((): void => this.todoController(item.id).setTextSelection(0, item.text.length))
                )

              if (this.hasTodoAssociation(item)) {
                Button(this.responsiveAssociationLabel(item))
                  .width(this.layoutWidth >= 260 ? 72 : 28)
                  .height(26)
                  .fontSize(10)
                  .fontColor(this.quickLaunchHasFailed(item) || this.linkedPaperIsActive(item) ?
                    this.paperColor() : this.accentColor())
                  .backgroundColor(this.quickLaunchHasFailed(item) ? this.dangerColor() :
                    (this.linkedPaperIsActive(item) ? this.accentColor() : Color.Transparent))
                  .border({
                    width: this.quickLaunchHasFailed(item) ? 1 : 0,
                    color: this.quickLaunchHasFailed(item) ? this.dangerColor() : Color.Transparent
                  })
                  .borderRadius(7)
                  .accessibilityText(this.quickLaunchHasFailed(item) ?
                    this.text('status.quickLaunchMissing') : this.responsiveAssociationLabel(item))
                  .onClick((): void => this.openTodoAssociation(item))
              }

              Text('≡')
                .width(22)
                .height(30)
                .fontSize(15)
                .fontColor(this.mutedColor())
                .textAlign(TextAlign.Center)
                .draggable(true)
                .onDragStart((event: DragEvent): DragItemInfo => this.beginTodoItemDrag(event, item))
                .onDragEnd((): void => this.finishTodoItemDrag())

            }
            .width('100%')
            .constraintSize({ minHeight: this.todoRowHeight() })
            .alignItems(VerticalAlign.Center)
            .padding({ left: 8, right: 4 })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
              .animation({ duration: this.enableAnimations ? 160 : 0, curve: Curve.EaseOut }))
            .animation({ duration: this.enableAnimations ? 160 : 0, curve: Curve.EaseOut })
            .backgroundColor(this.todoDropTargetId === item.id || this.contextMenuTodoId === item.id ||
              this.keyboardMenuTodoId === item.id ? this.inputColor() : Color.Transparent)
            .allowDrop([
              TODO_ITEM_UDMF_TYPE,
              PAPER_LINK_UDMF_TYPE,
              uniformTypeDescriptor.UniformDataType.FILE,
              uniformTypeDescriptor.UniformDataType.FOLDER,
              uniformTypeDescriptor.UniformDataType.DIRECTORY,
              uniformTypeDescriptor.UniformDataType.FILE_URI
            ])
            .onDragEnter((event: DragEvent): void => {
              if (this.todoDraggingId.length > 0 && this.todoDraggingId !== item.id) {
                this.todoDropTargetId = item.id;
              }
              this.todoDeleteDropHovered = false;
              event.dragBehavior = this.todoDraggingId.length > 0 ? DragBehavior.MOVE : DragBehavior.COPY;
              event.setResult(DragResult.DROP_ENABLED);
            })
            .onDragMove((event: DragEvent): void => {
              this.todoDeleteDropHovered = false;
              event.dragBehavior = this.todoDraggingId.length > 0 ? DragBehavior.MOVE : DragBehavior.COPY;
              event.setResult(DragResult.DROP_ENABLED);
            })
            .onDragLeave((): void => {
              if (this.todoDropTargetId === item.id) {
                this.todoDropTargetId = '';
              }
            })
            .onDrop((event: DragEvent): void => this.handleTodoAssociationDrop(event, item.id))
            .onMouse((event: MouseEvent): void => {
              if (event.button === MouseButton.Right && event.action === MouseAction.Press) {
                this.focusTodoForContextMenu(item.id);
              }
            })
            .bindMenu(this.keyboardMenuTodoId === item.id, () => {
              this.TodoContextMenu(item)
            }, {
              onDisappear: (): void => {
                if (this.keyboardMenuTodoId === item.id) {
                  this.keyboardMenuTodoId = '';
                }
                this.finishTodoContextMenu(item.id);
              }
            })
            .bindContextMenu(() => {
              this.TodoContextMenu(item)
            }, ResponseType.RightClick, {
              aboutToAppear: (): void => this.focusTodoForContextMenu(item.id),
              onDisappear: (): void => this.finishTodoContextMenu(item.id)
            })
          }
        }, (item: PaperItem): string => item.id)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)

      if (this.linkingTodoId.length > 0) {
        Scroll() {
          Row({ space: 5 }) {
            Text(this.text('link.to'))
              .fontSize(10)
              .fontColor(this.mutedColor())
            Button(this.text('link.none'))
              .height(28)
              .fontSize(10)
              .onClick((): void => this.setTodoLink(this.linkingTodoId, ''))
            Button(this.text('quick.file'))
              .height(28)
              .fontSize(10)
              .onClick((): void => this.chooseQuickLaunch(this.linkingTodoId, QUICK_LAUNCH_FILE))
            if (this.supportsFolderQuickLaunch()) {
              Button(this.text('quick.folder'))
                .height(28)
                .fontSize(10)
                .onClick((): void => this.chooseQuickLaunch(this.linkingTodoId, QUICK_LAUNCH_FOLDER))
            }
            if (this.enablePaperLinks) {
              ForEach(this.linkTargets(), (target: PaperData) => {
                Button((target.type === PAPER_TYPE_NOTE ? '✎ ' : '☑ ') + this.paperDisplayTitle(target))
                  .height(28)
                  .fontSize(10)
                  .onClick((): void => this.setTodoLink(this.linkingTodoId, target.id))
              }, (target: PaperData): string => target.id)
            }
            Button(this.text('action.cancel'))
              .height(28)
              .fontSize(10)
              .backgroundColor(Color.Transparent)
              .onClick((): void => {
                this.linkingTodoId = '';
              })
          }
          .padding({ left: 8, right: 8 })
        }
        .width('100%')
        .height(34)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }

      Button('＋')
      .width('100%')
      .height(32)
      .fontSize(20)
      .fontColor(this.mutedColor())
      .backgroundColor(Color.Transparent)
      .onClick((): void => this.appendBlankTodo())
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private NoteEditContextMenu() {
    Menu() {
      MenuItem({ content: this.noteEditorActionLabel('copy') })
        .onClick((): void => this.copyNoteSelection())
      MenuItem({ content: this.noteEditorActionLabel('selectAll') })
        .onClick((): void => this.selectAllNote())
      MenuItem({ content: this.text('glyph.bold') + '  ' + this.text('markdown.sampleBold') })
        .onClick((): void => this.formatNoteBold())
      MenuItem({ content: this.text('glyph.italic') + '  ' + this.text('markdown.sampleItalic') })
        .onClick((): void => this.formatNoteItalic())
      MenuItem({ content: this.text('glyph.strike') + '  ' + this.text('markdown.sampleStrike') })
        .onClick((): void => this.formatNoteWrap('~~', '~~'))
      MenuItem({ content: this.text('glyph.heading') + '  ' + this.text('markdown.sampleHeading') })
        .onClick((): void => this.formatNoteLinePrefix('## '))
      MenuItem({ content: this.text('glyph.quote') + '  ' + this.text('markdown.sampleQuote') })
        .onClick((): void => this.formatNoteLinePrefix('> '))
      MenuItem({ content: this.text('glyph.bullet') + '  ' + this.text('markdown.sampleList') })
        .onClick((): void => this.formatNoteLinePrefix('- '))
      MenuItem({ content: this.text('glyph.code') + '  ' + this.text('markdown.sampleInlineCode') })
        .onClick((): void => this.formatNoteCode())
      MenuItem({ content: this.text('glyph.link') + '  ' + this.text('markdown.sampleLink') })
        .onClick((): void => this.formatNoteLink())
      MenuItem({ content: this.text('glyph.image') + '  ' + this.text('image.alt') })
        .enabled(!this.imageImporting)
        .onClick((): void => this.chooseNoteImage())
    }
  }

  @Builder
  private NoteBody() {
    Column() {
      if (!this.isNoteBrowsing) {
        TextArea({
          text: this.content,
          placeholder: this.text('placeholder.noteContent'),
          controller: this.noteController
        })
          .id('paper_note_editor')
          .layoutWeight(1)
          .width('100%')
          .fontSize(this.noteFontSize())
          .fontWeight(this.configuredFontWeight(this.noteTextBold))
          .fontColor(this.textColor())
          .placeholderColor(this.mutedColor())
          .backgroundColor(Color.Transparent)
          .padding(12)
          .defaultFocus(true)
          .onWillInsert((value: InsertValue): boolean => this.continueMarkdownList(value))
          .onChange((value: string): void => this.updateNote(value))
          .onBlur((): void => this.handleNoteEditorBlur())
          .onKeyPreIme((event: KeyEvent): boolean => this.handleNoteKey(event))
          .onKeyEvent((event: KeyEvent): boolean => this.handleNoteKey(event))
          .bindContextMenu(() => {
            this.NoteEditContextMenu()
          }, ResponseType.RightClick, {
            aboutToAppear: (): void => this.beginNoteInteraction(),
            onDisappear: (): void => this.resumeNoteEditing()
          })

        Row() {
          Blank()
          PasteButton({
            icon: PasteIconStyle.LINES,
            text: PasteDescription.PASTE,
            buttonType: ButtonType.Capsule
          })
            .width(82)
            .height(30)
            .fontSize(11)
            .iconSize(14)
            .fontColor(this.textColor())
            .iconColor(this.textColor())
            .backgroundColor(this.inputColor())
            .borderRadius(15)
            .onClick((_event: ClickEvent, result: PasteButtonOnClickResult): void => {
              this.pasteNoteImageFromClipboard(result);
              if (!this.imageImporting) {
                this.resumeNoteEditing();
              }
            })
        }
        .width('100%')
        .height(34)
        .padding({ left: 8, right: 8, bottom: 4 })
      } else if (this.markdownRenderMode === MARKDOWN_OFF) {
        Scroll() {
          Text(this.content.length > 0 ? this.content : this.text('empty.noteStart'))
            .width('100%')
            .fontSize(this.noteFontSize())
            .fontWeight(this.configuredFontWeight(this.noteTextBold))
            .fontColor(this.content.length > 0 ? this.textColor() : this.mutedColor())
            .padding(12)
        }
        .layoutWeight(1)
        .width('100%')
        .onClick((): void => this.enterNoteEditFromPreview())
      } else {
        Scroll() {
          Column({ space: 3 }) {
            ForEach(this.markdownLines, (line: MarkdownLine) => {
              if (line.kind === MD_KIND_RULE) {
                Divider()
                  .color(this.paperBorderColor())
                  .margin({ top: 6, bottom: 6 })
              } else if (line.kind === MD_KIND_IMAGE) {
                if (this.markdownImageAvailable(line)) {
                  Image(this.markdownImageUri(line))
                    .width(this.markdownImageWidth(line))
                    .height(this.markdownImageHeight(line))
                    .sourceSize({
                      width: Math.ceil(this.markdownImageWidth(line)),
                      height: Math.ceil(this.markdownImageHeight(line))
                    })
                    .orientation(ImageRotateOrientation.AUTO)
                    .objectFit(ImageFit.Contain)
                    .autoResize(true)
                    .borderRadius(8)
                    .margin({ top: 4, bottom: 4 })
                    .onError((): void => this.markNoteImageBroken(line.imageId))
                } else {
                  Text('▧ ' + this.markdownImageAlt(line) + ' · ' + this.text('image.missing'))
                    .width('100%')
                    .fontSize(Math.max(10, this.noteFontSize() - 1))
                    .fontColor(this.mutedColor())
                    .backgroundColor(this.inputColor())
                    .padding(8)
                    .borderRadius(8)
                }
              } else if (line.kind === MD_KIND_CODE) {
                Text(line.text)
                  .width('100%')
                  .fontSize(Math.max(10, this.noteFontSize() - 1))
                  .fontColor(this.textColor())
                  .backgroundColor(this.inputColor())
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              } else {
                this.MarkdownRichLine(line)
              }
            }, (line: MarkdownLine): string => line.id)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(12)
        }
        .layoutWeight(1)
        .width('100%')
        .onClick((): void => this.enterNoteEditFromPreview())
      }

      if (Math.abs(this.textZoom - 1) > 0.001) {
        Button(Math.round(this.textZoom * 100).toString() + '%')
          .height(24)
          .fontSize(9)
          .fontColor(this.mutedColor())
          .backgroundColor(Color.Transparent)
          .alignSelf(ItemAlign.End)
          .margin({ right: 8, bottom: 4 })
          .onClick((): void => this.resetTextZoom())
      }
    }
    .layoutWeight(1)
    .width('100%')
    .allowDrop([
      uniformTypeDescriptor.UniformDataType.IMAGE,
      uniformTypeDescriptor.UniformDataType.FILE,
      uniformTypeDescriptor.UniformDataType.FILE_URI
    ])
    .onDragMove((event: DragEvent): void => event.setResult(DragResult.DROP_ENABLED))
    .onDrop((event: DragEvent): void => this.handleNoteImageDrop(event))
    .onAxisEvent((event: AxisEvent): void => this.handleNoteAxis(event))
  }

  @Builder
  private TodoDeleteDropZone() {
    Row({ space: 7 }) {
      Text('⌫')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.todoDeleteDropHovered ? this.paperColor() : this.dangerColor())
      Text(this.text('action.dropTodoToDelete'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.todoDeleteDropHovered ? this.paperColor() : this.dangerColor())
    }
    .justifyContent(FlexAlign.Center)
    .width('94%')
    .height(42)
    .align(Alignment.Bottom)
    .margin({ bottom: this.resizeGripMode === RESIZE_GRIP_HIDDEN ? 8 : 28 })
    .backgroundColor(this.todoDeleteDropHovered ? this.dangerColor() : this.inputColor())
    .border({ width: this.todoDeleteDropHovered ? 2 : 1, color: this.dangerColor() })
    .borderRadius(11)
    .shadow(this.todoDeleteDropHovered ? ShadowStyle.OUTER_DEFAULT_SM : ShadowStyle.OUTER_DEFAULT_XS)
    .zIndex(40)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
      .animation({ duration: this.enableAnimations ? 120 : 0, curve: Curve.EaseOut }))
    .allowDrop([TODO_ITEM_UDMF_TYPE])
    .onDragEnter((event: DragEvent): void => {
      this.todoDropTargetId = '';
      this.todoDeleteDropHovered = true;
      event.dragBehavior = DragBehavior.MOVE;
      event.setResult(DragResult.DROP_ENABLED);
    })
    .onDragMove((event: DragEvent): void => {
      this.todoDropTargetId = '';
      this.todoDeleteDropHovered = true;
      event.dragBehavior = DragBehavior.MOVE;
      event.setResult(DragResult.DROP_ENABLED);
    })
    .onDragLeave((): void => {
      this.todoDeleteDropHovered = false;
    })
    .onDrop((event: DragEvent): void => this.handleTodoDeleteDrop(event))
  }

  @Builder
  private HorizontalResizeHitZone(direction: string, alignment: Alignment) {
    Row()
      .width('100%')
      .height(7)
      .align(alignment)
      .zIndex(20)
      .backgroundColor('#01000000')
      .gesture(
        PanGesture({ direction: PanDirection.All })
          .onActionStart((): void => this.beginResize(direction))
          .onActionUpdate((event: GestureEvent): void => this.updateResize(event))
          .onActionEnd((): void => this.endResize())
          .onActionCancel((): void => this.cancelResize())
      )
  }

  @Builder
  private VerticalResizeHitZone(direction: string, alignment: Alignment) {
    Column()
      .width(7)
      .height('100%')
      .align(alignment)
      .zIndex(20)
      .backgroundColor('#01000000')
      .gesture(
        PanGesture({ direction: PanDirection.All })
          .onActionStart((): void => this.beginResize(direction))
          .onActionUpdate((event: GestureEvent): void => this.updateResize(event))
          .onActionEnd((): void => this.endResize())
          .onActionCancel((): void => this.cancelResize())
      )
  }

  @Builder
  private CornerResizeHitZone(direction: string, alignment: Alignment) {
    Row()
      .width(14)
      .height(14)
      .align(alignment)
      .zIndex(21)
      .backgroundColor('#01000000')
      .gesture(
        PanGesture({ direction: PanDirection.All })
          .onActionStart((): void => this.beginResize(direction))
          .onActionUpdate((event: GestureEvent): void => this.updateResize(event))
          .onActionEnd((): void => this.endResize())
          .onActionCancel((): void => this.cancelResize())
      )
  }

  @Builder
  private ResizeHandle() {
    Row() {
      Blank()
      Text(this.resizeGripMode === RESIZE_GRIP_HIDDEN ? '' : '◢')
        .width(28)
        .height(24)
        .fontSize(12)
        .fontColor(this.mutedColor())
        .opacity(this.resizeGripMode === RESIZE_GRIP_HIDDEN ? 0 :
          (this.resizeGripMode === RESIZE_GRIP_SOFT ? 0.5 : 1))
        .textAlign(TextAlign.Center)
        .gesture(
          PanGesture({ direction: PanDirection.All })
            .onActionStart((): void => this.beginResize('bottom-right'))
            .onActionUpdate((event: GestureEvent): void => this.updateResize(event))
            .onActionEnd((): void => this.endResize())
            .onActionCancel((): void => this.cancelResize())
        )
    }
    .width('100%')
    .height(24)
  }

  @Builder
  private PaperContextMenu() {
    Menu() {
      MenuItem({ content: this.text('action.newTodo') })
        .onClick((): void => this.createPaper(PAPER_TYPE_TODO))
      MenuItem({ content: this.text('action.newNote') })
        .onClick((): void => this.createPaper(PAPER_TYPE_NOTE))
      MenuItem({ content: this.text('action.settings') })
        .onClick((): void => {
          DesktopShell.openSettings(this.hostContext());
        })
      if (this.paper !== null && this.paper.type === PAPER_TYPE_TODO) {
        MenuItem({ content: this.text('action.clearCompleted') })
          .enabled(this.completedCount() > 0)
          .onClick((): void => this.clearCompleted())
      }
      if (this.paper !== null && this.paper.type === PAPER_TYPE_NOTE) {
        MenuItem({ content: this.text('action.openExternally') })
          .onClick((): void => {
            this.openMarkdownExternally();
          })
      }
      if (this.canCollapseToCapsule() || this.isCollapsed) {
        MenuItem({ content: this.text(this.isCollapsed ? 'action.expand' : 'action.collapse') })
          .onClick((): void => this.setCollapsed(!this.isCollapsed))
      }
      MenuItem({ content: this.text('action.hide') })
        .onClick((): void => this.hidePaper())
      MenuItem({ content: this.text('action.deletePaper') })
        .contentFontColor('#B42318')
        .onClick((): void => this.deletePaper())
    }
  }

  @Builder
  private CapsuleBody() {
    Row() {
      Row({ space: 4 }) {
        Text(this.typeLabel())
          .fontSize(this.scaledFontSize(14))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor())
        Text(this.capsuleTitle())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontSize(this.capsuleFontSize())
          .fontWeight(this.configuredFontWeight(this.capsuleTextBold))
          .fontColor(this.textColor())
      }
      .layoutWeight(1)
      .height('100%')
      .padding({ left: 10, right: 5 })
      .onClick((): void => this.activateCapsule())
      .gesture(
        PanGesture({ direction: PanDirection.All })
          .onActionStart((): void => this.beginMove())
          .onActionUpdate((event: GestureEvent): void => this.updateMove(event))
          .onActionEnd((): void => this.endMove())
          .onActionCancel((): void => this.cancelMove())
      )

      if (this.hideEdgeCapsuleCloseButtonOnHover && this.useDeepCapsuleMode && this.capsuleHovered) {
        Button('')
          .width(28)
          .height('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius({
            topLeft: 20,
            bottomLeft: 20,
            topRight: this.useDeepCapsuleMode ? 0 : 20,
            bottomRight: this.useDeepCapsuleMode ? 0 : 20
          })
          .onClick((): void => this.activateCapsule())
      } else {
        Button('×')
          .width(28)
          .height('100%')
          .fontSize(15)
          .fontColor(this.mutedColor())
          .backgroundColor(Color.Transparent)
          .borderRadius({
            topLeft: 20,
            bottomLeft: 20,
            topRight: this.useDeepCapsuleMode ? 0 : 20,
            bottomRight: this.useDeepCapsuleMode ? 0 : 20
          })
          .onClick((): void => this.hidePaper())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.paperColor())
    .border({ width: 1, color: this.paperBorderColor() })
    .borderRadius({
      topLeft: 22,
      bottomLeft: 22,
      topRight: this.useDeepCapsuleMode ? 0 : 22,
      bottomRight: this.useDeepCapsuleMode ? 0 : 22
    })
    .shadow(this.useDeepCapsuleMode ? ShadowStyle.OUTER_DEFAULT_XS : ShadowStyle.OUTER_DEFAULT_SM)
    .opacity(this.surfaceOpacity)
    .scale({ x: this.surfaceScale, y: this.surfaceScale })
    .onHover((isHover: boolean): void => this.handleCapsuleHover(isHover))
    .onKeyEvent((event: KeyEvent): boolean => this.handlePaperKey(event))
    .bindContextMenu(() => {
      this.PaperContextMenu()
    }, ResponseType.RightClick)
  }

  build() {
    if (this.isCollapsed) {
      this.CapsuleBody()
    } else {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
          this.HeaderBar()
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
          if (this.resizeGripMode !== RESIZE_GRIP_HIDDEN) {
            this.ResizeHandle()
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.paperColor())
        .border({ width: 1, color: this.paperBorderColor() })
        .borderRadius(14)
        .shadow(ShadowStyle.OUTER_DEFAULT_MD)
        .opacity(this.surfaceOpacity)
        .scale({ x: this.surfaceScale, y: this.surfaceScale })
        .onKeyEvent((event: KeyEvent): boolean => this.handlePaperKey(event))
        .bindContextMenu(() => {
          this.PaperContextMenu()
        }, ResponseType.RightClick)

        if (this.paper !== null && this.paper.type === PAPER_TYPE_TODO && this.todoDraggingId.length > 0) {
          this.TodoDeleteDropZone()
        }

        if (this.resizeGripMode === RESIZE_GRIP_HIDDEN) {
          this.HorizontalResizeHitZone('top', Alignment.Top)
          this.HorizontalResizeHitZone('bottom', Alignment.Bottom)
          this.VerticalResizeHitZone('left', Alignment.Start)
          this.VerticalResizeHitZone('right', Alignment.End)
          this.CornerResizeHitZone('top-left', Alignment.TopStart)
          this.CornerResizeHitZone('top-right', Alignment.TopEnd)
          this.CornerResizeHitZone('bottom-left', Alignment.BottomStart)
          this.CornerResizeHitZone('bottom-right', Alignment.BottomEnd)
        }
      }
      .width('100%')
      .height('100%')
    }
  }
}
