import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { display } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import {
  AppState,
  CAPSULE_EDGE_START_TOP,
  CAPSULE_MAX_WIDTH,
  CAPSULE_MIN_WIDTH,
  CAPSULE_WIDTH,
  CAPSULE_GAP_DEFAULT,
  COLOR_SCHEME_FOREST,
  COLOR_SCHEME_INK,
  COLOR_SCHEME_SUNSET,
  COLOR_SCHEME_WARM,
  DEFAULT_DISPLAY_ID,
  EDGE_SIDE_RIGHT,
  MARKDOWN_BASIC,
  MARKDOWN_ENHANCED,
  MARKDOWN_OFF,
  MAX_PAPERS,
  NOTE_DEFAULT_HEIGHT,
  NOTE_DEFAULT_WIDTH,
  NOTE_IMAGE_DIMENSION_MAX,
  NOTE_IMAGE_FILE_MAX_BYTES,
  NOTE_IMAGE_TOTAL_MAX_BYTES,
  NOTE_MAX_LENGTH,
  NoteImageAsset,
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
  RESIZE_GRIP_STANDARD,
  SCHEMA_VERSION,
  THEME_DARK,
  THEME_LIGHT,
  THEME_SYSTEM,
  TITLE_MAX_LENGTH,
  TODO_DEFAULT_HEIGHT,
  TODO_DEFAULT_WIDTH,
  TODO_ITEM_MAX_LENGTH,
  TODO_VISUAL_LARGE,
  TODO_VISUAL_MEDIUM,
  TODO_VISUAL_SMALL,
  TODO_VISUAL_XLARGE,
  UI_LANGUAGE_EN,
  UI_LANGUAGE_JA,
  UI_LANGUAGE_KO,
  UI_LANGUAGE_SYSTEM,
  UI_LANGUAGE_ZH_CN,
  VISUAL_TEXT_LARGE,
  VISUAL_TEXT_MEDIUM,
  VISUAL_TEXT_SMALL
} from './Models';
import { truncateText } from './TextSafety';
import { NoteImageStore } from './NoteImageStore';
import {
  cleanCommittedPaperTitle,
  cleanPaperTitle,
  defaultPaperTitle,
  DEFAULT_PAPER_TITLE_LIMIT,
  nextPaperTitleNumber,
  normalizePaperTitleLimit
} from './PaperTitles';

const STORE_NAME: string = 'PaperTodoState';
const STATE_KEY: string = 'state_json';
const BACKUP_KEY: string = 'state_backup_json';
const SAVE_IDLE_MS: number = 1000;
const SAVE_MAX_MS: number = 10000;
const SAVE_RETRY_MS: number = 10000;

interface LoadResult {
  state: AppState;
  persistedJson: string;
  shouldPersist: boolean;
  blocked: boolean;
}

class PaperStoreImpl {
  private store: preferences.Preferences | null = null;
  private state: AppState | null = null;
  private persistedJson: string = '';
  private storageBlocked: boolean = false;
  private dirty: boolean = false;
  private sequence: number = 0;
  private debounceTimer: number = -1;
  private maxTimer: number = -1;
  private retryTimer: number = -1;
  private revision: number = 0;
  private imageFilesReconciled: boolean = false;
  private capsuleEligibilitySignature: string = '';
  private capsuleEligibilitySignatureInitialized: boolean = false;

  initialize(context: Context): void {
    if (this.store === null) {
      try {
        const options: preferences.Options = { name: STORE_NAME };
        this.store = preferences.getPreferencesSync(context, options);
      } catch (error) {
        console.error('PaperTodo preferences init failed: ' + String(error));
        this.storageBlocked = true;
      }
    }

    let shouldPersist: boolean = false;
    let shouldCleanupImages: boolean = false;
    if (this.state === null) {
      const loaded: LoadResult = this.loadInitialState();
      this.state = loaded.state;
      this.persistedJson = loaded.persistedJson;
      this.storageBlocked = this.storageBlocked || loaded.blocked;
      shouldPersist = loaded.shouldPersist;
    }
    if (!this.storageBlocked && this.state !== null && !this.imageFilesReconciled) {
      const reconciled: NoteImageAsset[] = NoteImageStore.reconcileAssets(context, this.state.noteImages);
      if (JSON.stringify(reconciled) !== JSON.stringify(this.state.noteImages)) {
        this.state.noteImages = reconciled;
        shouldPersist = true;
      }
      this.imageFilesReconciled = true;
      shouldCleanupImages = true;
    }
    if (shouldPersist && !this.storageBlocked) {
      this.dirty = true;
      this.flushNow();
    }
    if (!this.storageBlocked && shouldCleanupImages) {
      NoteImageStore.cleanupOrphans(context, this.protectedImageFileNames());
    }
    this.publishSettings();
  }

  loadState(): AppState {
    return this.ensureState();
  }

  listPapers(): PaperData[] {
    return this.ensureState().papers.slice();
  }

  getPaper(id: string): PaperData | null {
    const papers: PaperData[] = this.ensureState().papers;
    for (let i: number = 0; i < papers.length; i++) {
      if (papers[i].id === id) {
        return papers[i];
      }
    }
    return null;
  }

  getNoteImage(id: string): NoteImageAsset | null {
    const assets: NoteImageAsset[] = this.ensureState().noteImages;
    for (let i: number = 0; i < assets.length; i++) {
      if (assets[i].id === id) {
        return assets[i];
      }
    }
    return null;
  }

  getNoteImageForPaper(id: string, paperId: string): NoteImageAsset | null {
    const asset: NoteImageAsset | null = this.getNoteImage(id);
    return asset !== null && asset.noteId === paperId ? asset : null;
  }

  getNoteImageTotalBytes(): number {
    const assets: NoteImageAsset[] = this.ensureState().noteImages;
    let total: number = 0;
    for (let i: number = 0; i < assets.length; i++) {
      total += assets[i].byteLength;
    }
    return total;
  }

  addNoteImage(asset: NoteImageAsset): boolean {
    if (this.storageBlocked || this.getPaper(asset.noteId)?.type !== PAPER_TYPE_NOTE ||
      this.getNoteImage(asset.id) !== null || !this.isValidNoteImage(asset) ||
      this.getNoteImageTotalBytes() + asset.byteLength > NOTE_IMAGE_TOTAL_MAX_BYTES) {
      return false;
    }
    this.ensureState().noteImages.push({
      id: asset.id,
      noteId: asset.noteId,
      fileName: asset.fileName,
      mimeType: asset.mimeType,
      width: asset.width,
      height: asset.height,
      byteLength: asset.byteLength,
      createdAt: asset.createdAt
    });
    this.requestSave(false);
    return true;
  }

  removeNoteImage(id: string): void {
    const state: AppState = this.ensureState();
    const next: NoteImageAsset[] = [];
    for (let i: number = 0; i < state.noteImages.length; i++) {
      if (state.noteImages[i].id !== id) {
        next.push(state.noteImages[i]);
      }
    }
    if (next.length !== state.noteImages.length) {
      state.noteImages = next;
      this.requestSave(false);
    }
  }

  hasStorageError(): boolean {
    return this.storageBlocked;
  }

  createPaper(type: string, sourcePaperId: string = ''): PaperData | null {
    if (this.storageBlocked) {
      return null;
    }
    const state: AppState = this.ensureState();
    if (state.papers.length >= MAX_PAPERS) {
      return null;
    }

    const isNote: boolean = type === PAPER_TYPE_NOTE;
    const now: number = Date.now();
    const source: PaperData | null = sourcePaperId.length > 0 ? this.getPaper(sourcePaperId) : null;
    const systemLanguage: string = this.currentSystemLanguage();
    const offset: number = (state.papers.length % 8) * 28;
    const startX: number = source !== null ? source.expandedX + 32 : 120 + offset;
    const startY: number = source !== null ? source.expandedY + 32 : 120 + offset;
    const edgeOrder: number = this.nextEdgeOrder(state);
    const paper: PaperData = {
      id: this.nextId('paper'),
      type: isNote ? PAPER_TYPE_NOTE : PAPER_TYPE_TODO,
      title: defaultPaperTitle(isNote ? PAPER_TYPE_NOTE : PAPER_TYPE_TODO,
        nextPaperTitleNumber(state.papers, isNote ? PAPER_TYPE_NOTE : PAPER_TYPE_TODO,
          state.uiLanguage, systemLanguage), state.uiLanguage, systemLanguage),
      expandedX: startX,
      expandedY: startY,
      expandedWidth: isNote ? NOTE_DEFAULT_WIDTH : TODO_DEFAULT_WIDTH,
      expandedHeight: isNote ? NOTE_DEFAULT_HEIGHT : TODO_DEFAULT_HEIGHT,
      capsuleX: startX,
      capsuleY: startY,
      capsuleWidth: CAPSULE_WIDTH,
      edgeSide: EDGE_SIDE_RIGHT,
      edgeOrder: edgeOrder,
      edgeDisplayId: DEFAULT_DISPLAY_ID,
      isVisible: true,
      alwaysOnTop: source !== null ? source.alwaysOnTop : false,
      isCollapsed: false,
      textZoom: 1,
      items: isNote ? [] : [this.createItem('', 0)],
      content: '',
      createdAt: now,
      updatedAt: now
    };
    state.papers.push(paper);
    this.requestSave(true);
    return paper;
  }

  updatePaper(paper: PaperData, immediate: boolean = false): void {
    if (this.storageBlocked) {
      return;
    }
    this.normalizePaper(paper, paper.edgeOrder);
    this.sanitizePaperLinks(paper);
    paper.updatedAt = Date.now();
    const state: AppState = this.ensureState();
    const papers: PaperData[] = state.papers;
    for (let i: number = 0; i < papers.length; i++) {
      if (papers[i].id === paper.id) {
        papers[i] = paper;
        const eligibilityChanged: boolean = this.refreshCapsuleEligibilitySignature(state);
        const expandedIneligiblePaper: boolean = this.expandIneligibleCapsulePapers(state);
        if (this.countEdgeCapsulePapers(state) === 0) {
          state.capsuleCollapseAllActive = false;
        }
        this.requestSave(immediate);
        if (eligibilityChanged || expandedIneligiblePaper) {
          this.notifyRevision();
        }
        return;
      }
    }
    if (papers.length < MAX_PAPERS) {
      papers.push(paper);
      const eligibilityChanged: boolean = this.refreshCapsuleEligibilitySignature(state);
      const expandedIneligiblePaper: boolean = this.expandIneligibleCapsulePapers(state);
      this.requestSave(immediate);
      if (eligibilityChanged || expandedIneligiblePaper) {
        this.notifyRevision();
      }
    }
  }

  commitPaperTitle(id: string, title: string, immediate: boolean = true): string | null {
    if (this.storageBlocked) {
      return null;
    }
    const state: AppState = this.ensureState();
    const paper: PaperData | null = this.getPaper(id);
    if (paper === null) {
      return null;
    }
    const cleaned: string = cleanCommittedPaperTitle(title, state.titleCharacterLimit);
    if (paper.title !== cleaned) {
      paper.title = cleaned;
      this.updatePaper(paper, immediate);
      this.notifyRevision();
    }
    return cleaned;
  }

  deletePaper(id: string): PaperData | null {
    if (this.storageBlocked) {
      return null;
    }
    const state: AppState = this.ensureState();
    let removed: boolean = false;
    const next: PaperData[] = [];
    for (let i: number = 0; i < state.papers.length; i++) {
      if (state.papers[i].id !== id) {
        for (let itemIndex: number = 0; itemIndex < state.papers[i].items.length; itemIndex++) {
          if (state.papers[i].items[itemIndex].linkedPaperId === id) {
            state.papers[i].items[itemIndex].linkedPaperId = undefined;
            state.papers[i].updatedAt = Date.now();
          }
        }
        next.push(state.papers[i]);
      } else {
        removed = true;
      }
    }
    if (!removed) {
      return null;
    }
    state.papers = next;
    const remainingImages: NoteImageAsset[] = [];
    for (let i: number = 0; i < state.noteImages.length; i++) {
      if (state.noteImages[i].noteId !== id) {
        remainingImages.push(state.noteImages[i]);
      }
    }
    state.noteImages = remainingImages;
    let replacement: PaperData | null = null;
    if (state.papers.length === 0) {
      const now: number = Date.now();
      const systemLanguage: string = this.currentSystemLanguage();
      replacement = {
        id: this.nextId('paper'),
        type: PAPER_TYPE_TODO,
        title: defaultPaperTitle(PAPER_TYPE_TODO,
          nextPaperTitleNumber(state.papers, PAPER_TYPE_TODO, state.uiLanguage, systemLanguage),
          state.uiLanguage, systemLanguage),
        expandedX: 120,
        expandedY: 120,
        expandedWidth: TODO_DEFAULT_WIDTH,
        expandedHeight: TODO_DEFAULT_HEIGHT,
        capsuleX: 120,
        capsuleY: 120,
        capsuleWidth: CAPSULE_WIDTH,
        edgeSide: EDGE_SIDE_RIGHT,
        edgeOrder: 0,
        edgeDisplayId: DEFAULT_DISPLAY_ID,
        isVisible: true,
        alwaysOnTop: false,
        isCollapsed: false,
        textZoom: 1,
        items: [this.createItem('', 0)],
        content: '',
        createdAt: now,
        updatedAt: now
      };
      state.papers.push(replacement);
    }
    if (this.countEdgeCapsulePapers(state) === 0) {
      state.capsuleCollapseAllActive = false;
    }
    this.refreshCapsuleEligibilitySignature(state);
    this.resequenceEdges();
    this.requestSave(true);
    this.notifyRevision();
    return replacement;
  }

  setPaperVisible(id: string, visible: boolean): void {
    const paper: PaperData | null = this.getPaper(id);
    if (paper === null) {
      return;
    }
    paper.isVisible = visible;
    this.updatePaper(paper, true);
    const state: AppState = this.ensureState();
    if (this.countEdgeCapsulePapers(state) === 0) {
      state.capsuleCollapseAllActive = false;
    }
    this.notifyRevision();
  }

  setPaperCollapsed(id: string, collapsed: boolean): void {
    const state: AppState = this.ensureState();
    const paper: PaperData | null = this.getPaper(id);
    if (paper === null) {
      return;
    }
    paper.isCollapsed = collapsed && this.canPaperDisplayAsCapsuleInState(state, paper);
    this.updatePaper(paper, true);
    if (this.countEdgeCapsulePapers(state) === 0) {
      state.capsuleCollapseAllActive = false;
    }
    this.notifyRevision();
  }

  setTodoLink(paperId: string, itemId: string, targetPaperId: string): boolean {
    const paper: PaperData | null = this.getPaper(paperId);
    if (paper === null || paper.type !== PAPER_TYPE_TODO) {
      return false;
    }
    if (targetPaperId.length > 0 && (targetPaperId === paperId || this.getPaper(targetPaperId) === null)) {
      return false;
    }
    for (let i: number = 0; i < paper.items.length; i++) {
      if (paper.items[i].id === itemId) {
        paper.items[i].linkedPaperId = targetPaperId.length > 0 ? targetPaperId : undefined;
        if (targetPaperId.length > 0) {
          paper.items[i].quickLaunchUri = undefined;
          paper.items[i].quickLaunchName = undefined;
          paper.items[i].quickLaunchKind = undefined;
        }
        this.updatePaper(paper, true);
        this.notifyRevision();
        return true;
      }
    }
    return false;
  }

  setUiLanguage(language: string): void {
    const state: AppState = this.ensureState();
    state.uiLanguage = this.normalizeUiLanguage(language);
    try {
      i18n.System.setAppPreferredLanguage(state.uiLanguage === UI_LANGUAGE_SYSTEM ? 'default' : state.uiLanguage);
    } catch (error) {
      console.warn('PaperTodo preferred language update failed: ' + String(error));
    }
    this.requestSave(true);
    this.publishSettings();
  }

  setTheme(theme: string): void {
    const state: AppState = this.ensureState();
    state.theme = theme === THEME_LIGHT || theme === THEME_DARK ? theme : THEME_SYSTEM;
    this.requestSave(true);
    this.publishSettings();
  }

  setColorScheme(scheme: string): void {
    const state: AppState = this.ensureState();
    state.colorScheme = this.normalizeColorScheme(scheme);
    this.requestSave(true);
    this.publishSettings();
  }

  setMarkdownMode(mode: string): void {
    const state: AppState = this.ensureState();
    if (mode === MARKDOWN_OFF || mode === MARKDOWN_BASIC) {
      state.markdownRenderMode = mode;
    } else {
      state.markdownRenderMode = MARKDOWN_ENHANCED;
    }
    this.requestSave(true);
    this.publishSettings();
  }

  setCapsuleMode(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.useCapsuleMode = enabled;
    if (!enabled) {
      state.useDeepCapsuleMode = false;
      state.capsuleCollapseAllActive = false;
      state.capsuleStartTop = CAPSULE_EDGE_START_TOP;
      for (let i: number = 0; i < state.papers.length; i++) {
        state.papers[i].isCollapsed = false;
      }
    }
    this.requestSave(true);
    this.publishSettings();
  }

  setDeepCapsuleMode(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.useDeepCapsuleMode = enabled;
    if (enabled) {
      state.useCapsuleMode = true;
    } else {
      state.capsuleCollapseAllActive = false;
      state.capsuleStartTop = CAPSULE_EDGE_START_TOP;
    }
    this.requestSave(true);
    this.publishSettings();
  }

  setShowDeepCapsuleWhileExpanded(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.showDeepCapsuleWhileExpanded = enabled;
    if (this.countEdgeCapsulePapers(state) === 0) {
      state.capsuleCollapseAllActive = false;
    }
    this.requestSave(true);
    this.publishSettings();
  }

  setMasterCapsuleEnabled(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.useMasterCapsule = enabled;
    if (!enabled) {
      state.capsuleCollapseAllActive = false;
      state.capsuleStartTop = CAPSULE_EDGE_START_TOP;
    }
    this.requestSave(true);
    this.publishSettings();
  }

  setCapsuleCollapseAllActive(active: boolean): void {
    const state: AppState = this.ensureState();
    state.capsuleCollapseAllActive = active && state.useCapsuleMode && state.useDeepCapsuleMode &&
      state.useMasterCapsule && this.listEdgeCapsulePapers().length > 0;
    this.requestSave(true);
    this.publishSettings();
  }

  setCapsuleStartTop(top: number): void {
    const state: AppState = this.ensureState();
    state.capsuleStartTop = Number.isFinite(top) ? Math.max(8, top) : CAPSULE_EDGE_START_TOP;
    this.requestSave(false);
    this.publishSettings();
  }

  setTitleCharacterLimit(limit: number): void {
    const state: AppState = this.ensureState();
    state.titleCharacterLimit = normalizePaperTitleLimit(limit);
    for (let i: number = 0; i < state.papers.length; i++) {
      state.papers[i].title = cleanCommittedPaperTitle(state.papers[i].title, state.titleCharacterLimit);
    }
    this.requestSave(true);
    this.publishSettings();
  }

  setTodoVisualSize(size: string): void {
    const state: AppState = this.ensureState();
    if (size === TODO_VISUAL_SMALL || size === TODO_VISUAL_LARGE || size === TODO_VISUAL_XLARGE) {
      state.todoVisualSize = size;
    } else {
      state.todoVisualSize = TODO_VISUAL_MEDIUM;
    }
    this.requestSave(true);
    this.publishSettings();
  }

  setAutoBottomCompleted(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.autoBottomCompleted = enabled;
    this.requestSave(true);
    this.publishSettings();
  }

  setAutoClearCompleted(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.autoClearCompletedTodos = enabled;
    this.requestSave(true);
    this.publishSettings();
  }

  setAutoCompressLargeImages(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.autoCompressLargeImages = enabled;
    this.requestSave(true);
    this.publishSettings();
  }

  setGlobalHotkeysEnabled(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.globalHotkeysEnabled = enabled;
    this.requestSave(true);
    this.publishSettings();
  }

  setCapsuleGap(gap: number): void {
    const state: AppState = this.ensureState();
    state.capsuleGap = gap === 0 || gap === 8 ? gap : CAPSULE_GAP_DEFAULT;
    this.requestSave(true);
    this.publishSettings();
  }

  setAnimationsEnabled(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.enableAnimations = enabled;
    this.requestSave(true);
    this.publishSettings();
  }

  setRememberEdgeExpandedPosition(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.rememberEdgeExpandedPosition = enabled;
    this.requestSave(true);
    this.publishSettings();
  }

  setCollapseExpandedEdgeCapsuleOnClick(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.collapseExpandedEdgeCapsuleOnClick = enabled;
    this.requestSave(true);
    this.publishSettings();
  }

  setHideEdgeCapsuleCloseButtonOnHover(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.hideEdgeCapsuleCloseButtonOnHover = enabled;
    this.requestSave(true);
    this.publishSettings();
  }

  setEdgeCapsuleTitleCharacterLimit(limit: number): void {
    const state: AppState = this.ensureState();
    state.edgeCapsuleTitleCharacterLimit = limit === 8 || limit === 12 || limit === 16 ? limit : 0;
    this.requestSave(true);
    this.publishSettings();
  }

  setPaperLinksEnabled(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.enablePaperLinks = enabled;
    if (enabled) {
      this.expandIneligibleCapsulePapers(state);
    }
    if (this.countEdgeCapsulePapers(state) === 0) {
      state.capsuleCollapseAllActive = false;
    }
    this.requestSave(true);
    this.publishSettings();
  }

  setHideLinkedPapersFromCapsules(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.hideLinkedPapersFromCapsules = enabled;
    if (enabled) {
      this.expandIneligibleCapsulePapers(state);
    }
    if (this.countEdgeCapsulePapers(state) === 0) {
      state.capsuleCollapseAllActive = false;
    }
    this.requestSave(true);
    this.publishSettings();
  }

  setOverallFontScale(scale: number): void {
    const state: AppState = this.ensureState();
    state.overallFontScale = this.normalizeOverallFontScale(scale);
    this.requestSave(true);
    this.publishSettings();
  }

  setNoteTextAppearance(size: string, bold: boolean): void {
    const state: AppState = this.ensureState();
    state.noteTextSize = this.normalizeVisualTextSize(size);
    state.noteTextBold = bold;
    this.requestSave(true);
    this.publishSettings();
  }

  setTodoTextBold(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.todoTextBold = enabled;
    this.requestSave(true);
    this.publishSettings();
  }

  setTitleTextAppearance(size: string, bold: boolean): void {
    const state: AppState = this.ensureState();
    state.titleTextSize = this.normalizeVisualTextSize(size);
    state.titleTextBold = bold;
    this.requestSave(true);
    this.publishSettings();
  }

  setCapsuleTextAppearance(size: string, bold: boolean): void {
    const state: AppState = this.ensureState();
    state.capsuleTextSize = this.normalizeVisualTextSize(size);
    state.capsuleTextBold = bold;
    this.requestSave(true);
    this.publishSettings();
  }

  setResizeGripMode(mode: string): void {
    const state: AppState = this.ensureState();
    state.resizeGripMode = mode === RESIZE_GRIP_STANDARD || mode === RESIZE_GRIP_HIDDEN ?
      mode : RESIZE_GRIP_SOFT;
    this.requestSave(true);
    this.publishSettings();
  }

  setTopBarButtons(showNewTodo: boolean, showNewNote: boolean): void {
    const state: AppState = this.ensureState();
    state.showTopBarNewTodoButton = showNewTodo;
    state.showTopBarNewNoteButton = showNewNote;
    this.requestSave(true);
    this.publishSettings();
  }

  setExternalOpenButton(enabled: boolean): void {
    const state: AppState = this.ensureState();
    state.showTopBarExternalOpenButton = enabled;
    this.requestSave(true);
    this.publishSettings();
  }

  isPaperLinkedToAnyTodo(paperId: string): boolean {
    return this.isPaperLinkedToAnyTodoInState(this.ensureState(), paperId);
  }

  canPaperDisplayAsCapsule(paper: PaperData): boolean {
    return this.canPaperDisplayAsCapsuleInState(this.ensureState(), paper);
  }

  listEdgeCapsulePapers(): PaperData[] {
    const state: AppState = this.ensureState();
    const queue: PaperData[] = [];
    if (!state.useCapsuleMode || !state.useDeepCapsuleMode) {
      return queue;
    }
    for (let i: number = 0; i < state.papers.length; i++) {
      const paper: PaperData = state.papers[i];
      if (this.canPaperDisplayAsCapsuleInState(state, paper) && paper.isVisible &&
        (paper.isCollapsed || state.showDeepCapsuleWhileExpanded)) {
        queue.push(paper);
      }
    }
    queue.sort((a: PaperData, b: PaperData): number => a.edgeOrder - b.edgeOrder);
    return queue;
  }

  getCollapsedIndex(id: string): number {
    const target: PaperData | null = this.getPaper(id);
    if (target === null) {
      return 0;
    }
    const papers: PaperData[] = this.ensureState().papers;
    let count: number = 0;
    for (let i: number = 0; i < papers.length; i++) {
      const paper: PaperData = papers[i];
      if (paper.id !== id && paper.isVisible && paper.isCollapsed &&
        paper.edgeSide === target.edgeSide && paper.edgeDisplayId === target.edgeDisplayId &&
        paper.edgeOrder < target.edgeOrder) {
        count += 1;
      }
    }
    return count;
  }

  moveCollapsedPaper(id: string, requestedIndex: number): void {
    const target: PaperData | null = this.getPaper(id);
    if (target === null) {
      return;
    }
    const queue: PaperData[] = [];
    const papers: PaperData[] = this.ensureState().papers;
    for (let i: number = 0; i < papers.length; i++) {
      const paper: PaperData = papers[i];
      if (paper.isVisible && paper.isCollapsed && paper.edgeSide === target.edgeSide &&
        paper.edgeDisplayId === target.edgeDisplayId) {
        queue.push(paper);
      }
    }
    queue.sort((a: PaperData, b: PaperData): number => a.edgeOrder - b.edgeOrder);
    let oldIndex: number = -1;
    for (let i: number = 0; i < queue.length; i++) {
      if (queue[i].id === id) {
        oldIndex = i;
        break;
      }
    }
    if (oldIndex < 0) {
      return;
    }
    const removed: PaperData[] = queue.splice(oldIndex, 1);
    const nextIndex: number = Math.max(0, Math.min(requestedIndex, queue.length));
    queue.splice(nextIndex, 0, removed[0]);
    for (let i: number = 0; i < queue.length; i++) {
      queue[i].edgeOrder = i;
      queue[i].updatedAt = Date.now();
    }
    const remaining: PaperData[] = [];
    for (let i: number = 0; i < papers.length; i++) {
      const paper: PaperData = papers[i];
      if (!(paper.isVisible && paper.isCollapsed && paper.edgeSide === target.edgeSide &&
        paper.edgeDisplayId === target.edgeDisplayId) && paper.edgeSide === target.edgeSide &&
        paper.edgeDisplayId === target.edgeDisplayId) {
        remaining.push(paper);
      }
    }
    remaining.sort((a: PaperData, b: PaperData): number => a.edgeOrder - b.edgeOrder);
    for (let i: number = 0; i < remaining.length; i++) {
      remaining[i].edgeOrder = queue.length + i;
      remaining[i].updatedAt = Date.now();
    }
    this.requestSave(false);
    this.notifyRevision();
  }

  createTodoItem(text: string, order: number): PaperItem {
    return this.createItem(truncateText(text, TODO_ITEM_MAX_LENGTH), order);
  }

  restoreBackup(): boolean {
    if (this.store === null) {
      return false;
    }
    try {
      const backup: string = this.store.getSync(BACKUP_KEY, '') as string;
      const restored: AppState | null = this.parseState(backup);
      if (restored === null) {
        return false;
      }
      const payload: string = JSON.stringify(restored);
      this.store.putSync(STATE_KEY, payload);
      this.store.flushSync();
      this.state = restored;
      this.persistedJson = payload;
      this.storageBlocked = false;
      this.dirty = false;
      this.clearSaveTimers();
      this.publishSettings();
      return true;
    } catch (error) {
      console.error('PaperTodo restore backup failed: ' + String(error));
      return false;
    }
  }

  flushNow(): boolean {
    this.clearDebounceTimers();
    if (!this.dirty || this.storageBlocked || this.store === null || this.state === null) {
      return !this.storageBlocked;
    }

    const payload: string = JSON.stringify(this.state);
    if (payload === this.persistedJson) {
      this.dirty = false;
      return true;
    }

    try {
      if (this.persistedJson.length > 0) {
        this.store.putSync(BACKUP_KEY, this.persistedJson);
      }
      this.store.putSync(STATE_KEY, payload);
      this.store.flushSync();
      this.persistedJson = payload;
      this.dirty = false;
      if (this.retryTimer >= 0) {
        clearTimeout(this.retryTimer);
        this.retryTimer = -1;
      }
      return true;
    } catch (error) {
      console.error('PaperTodo state save failed: ' + String(error));
      this.dirty = true;
      this.scheduleRetry();
      return false;
    }
  }

  private requestSave(immediate: boolean): void {
    if (this.storageBlocked) {
      return;
    }
    this.dirty = true;
    if (immediate) {
      this.flushNow();
      return;
    }

    if (this.debounceTimer >= 0) {
      clearTimeout(this.debounceTimer);
    }
    this.debounceTimer = setTimeout((): void => {
      this.debounceTimer = -1;
      this.flushNow();
    }, SAVE_IDLE_MS);

    if (this.maxTimer < 0) {
      this.maxTimer = setTimeout((): void => {
        this.maxTimer = -1;
        this.flushNow();
      }, SAVE_MAX_MS);
    }
  }

  private scheduleRetry(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
    }
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      this.flushNow();
    }, SAVE_RETRY_MS);
  }

  private clearDebounceTimers(): void {
    if (this.debounceTimer >= 0) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    if (this.maxTimer >= 0) {
      clearTimeout(this.maxTimer);
      this.maxTimer = -1;
    }
  }

  private clearSaveTimers(): void {
    this.clearDebounceTimers();
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  private loadInitialState(): LoadResult {
    if (this.store === null) {
      return { state: this.createSafeEmptyState(), persistedJson: '', shouldPersist: false, blocked: true };
    }

    let raw: string = '';
    let backup: string = '';
    try {
      raw = this.store.getSync(STATE_KEY, '') as string;
      backup = this.store.getSync(BACKUP_KEY, '') as string;
    } catch (error) {
      console.error('PaperTodo state read failed: ' + String(error));
      return { state: this.createSafeEmptyState(), persistedJson: '', shouldPersist: false, blocked: true };
    }

    if (raw.length === 0) {
      if (backup.length > 0) {
        if (this.hasUnsupportedFutureSchema(backup)) {
          console.error('PaperTodo backup schema is newer than this app; refusing to overwrite stored data.');
          return { state: this.createSafeEmptyState(), persistedJson: backup, shouldPersist: false, blocked: true };
        }
        const recovered: AppState | null = this.parseState(backup);
        if (recovered !== null) {
          // Force the recovered payload back into the missing primary slot without
          // rotating an empty/invalid primary value over the known-good backup.
          return { state: recovered, persistedJson: '', shouldPersist: true, blocked: false };
        }
      }
      return { state: this.createDefaultState(), persistedJson: '', shouldPersist: true, blocked: false };
    }

    if (this.hasUnsupportedFutureSchema(raw)) {
      console.error('PaperTodo state schema is newer than this app; refusing to overwrite stored data.');
      return { state: this.createSafeEmptyState(), persistedJson: raw, shouldPersist: false, blocked: true };
    }
    const parsed: AppState | null = this.parseState(raw);
    if (parsed !== null) {
      const normalized: string = JSON.stringify(parsed);
      return { state: parsed, persistedJson: raw, shouldPersist: normalized !== raw, blocked: false };
    }

    if (backup.length > 0) {
      if (this.hasUnsupportedFutureSchema(backup)) {
        console.error('PaperTodo backup schema is newer than this app; refusing to overwrite stored data.');
        return { state: this.createSafeEmptyState(), persistedJson: raw, shouldPersist: false, blocked: true };
      }
      const recovered: AppState | null = this.parseState(backup);
      if (recovered !== null) {
        // An invalid primary payload must never replace the valid backup during
        // the recovery write. An empty persisted marker suppresses that rotation.
        return { state: recovered, persistedJson: '', shouldPersist: true, blocked: false };
      }
    }

    console.error('PaperTodo main state and backup are both invalid; refusing to overwrite stored data.');
    return { state: this.createSafeEmptyState(), persistedJson: raw, shouldPersist: false, blocked: true };
  }

  private parseState(raw: string): AppState | null {
    if (raw.length === 0) {
      return null;
    }
    try {
      const parsed: AppState = JSON.parse(raw) as AppState;
      if (parsed.papers === undefined || !Array.isArray(parsed.papers)) {
        return null;
      }
      const sourceVersion: number = Number.isFinite(parsed.schemaVersion) ? parsed.schemaVersion : 1;
      if (sourceVersion > SCHEMA_VERSION) {
        console.error('PaperTodo state schema is newer than this app; refusing to rewrite it.');
        return null;
      }
      this.normalizeState(parsed, sourceVersion);
      return parsed;
    } catch (error) {
      console.error('PaperTodo state parse failed: ' + String(error));
      return null;
    }
  }

  private hasUnsupportedFutureSchema(raw: string): boolean {
    try {
      const parsed: AppState = JSON.parse(raw) as AppState;
      return parsed !== null && Number.isFinite(parsed.schemaVersion) && parsed.schemaVersion > SCHEMA_VERSION;
    } catch (error) {
      return false;
    }
  }

  private normalizeState(state: AppState, sourceVersion: number): void {
    state.initialized = true;
    if (state.noteImages === undefined || !Array.isArray(state.noteImages)) {
      state.noteImages = [];
    }
    if (typeof state.autoCompressLargeImages !== 'boolean') {
      state.autoCompressLargeImages = true;
    }
    if (typeof state.globalHotkeysEnabled !== 'boolean') {
      state.globalHotkeysEnabled = false;
    }
    state.uiLanguage = this.normalizeUiLanguage(state.uiLanguage);
    state.theme = state.theme === THEME_LIGHT || state.theme === THEME_DARK ? state.theme : THEME_SYSTEM;
    state.colorScheme = this.normalizeColorScheme(state.colorScheme);
    if (state.markdownRenderMode !== MARKDOWN_OFF && state.markdownRenderMode !== MARKDOWN_BASIC) {
      state.markdownRenderMode = MARKDOWN_ENHANCED;
    }
    if (state.todoVisualSize !== TODO_VISUAL_SMALL && state.todoVisualSize !== TODO_VISUAL_LARGE &&
      state.todoVisualSize !== TODO_VISUAL_XLARGE) {
      state.todoVisualSize = TODO_VISUAL_MEDIUM;
    }
    if (typeof state.autoBottomCompleted !== 'boolean') {
      state.autoBottomCompleted = false;
    }
    if (typeof state.autoClearCompletedTodos !== 'boolean') {
      state.autoClearCompletedTodos = false;
    }
    if (state.capsuleGap !== 0 && state.capsuleGap !== 8) {
      state.capsuleGap = CAPSULE_GAP_DEFAULT;
    }
    if (typeof state.useCapsuleMode !== 'boolean') {
      state.useCapsuleMode = true;
    }
    if (typeof state.useDeepCapsuleMode !== 'boolean') {
      state.useDeepCapsuleMode = true;
    }
    if (typeof state.showDeepCapsuleWhileExpanded !== 'boolean') {
      state.showDeepCapsuleWhileExpanded = true;
    }
    if (typeof state.useMasterCapsule !== 'boolean') {
      state.useMasterCapsule = true;
    }
    if (typeof state.capsuleCollapseAllActive !== 'boolean') {
      state.capsuleCollapseAllActive = false;
    }
    if (!Number.isFinite(state.capsuleStartTop)) {
      state.capsuleStartTop = CAPSULE_EDGE_START_TOP;
    }
    state.capsuleStartTop = Math.max(8, state.capsuleStartTop);
    if (typeof state.enableAnimations !== 'boolean') {
      state.enableAnimations = true;
    }
    if (typeof state.rememberEdgeExpandedPosition !== 'boolean') {
      state.rememberEdgeExpandedPosition = true;
    }
    if (typeof state.collapseExpandedEdgeCapsuleOnClick !== 'boolean') {
      state.collapseExpandedEdgeCapsuleOnClick = false;
    }
    if (typeof state.hideEdgeCapsuleCloseButtonOnHover !== 'boolean') {
      state.hideEdgeCapsuleCloseButtonOnHover = false;
    }
    if (state.edgeCapsuleTitleCharacterLimit !== 8 && state.edgeCapsuleTitleCharacterLimit !== 12 &&
      state.edgeCapsuleTitleCharacterLimit !== 16) {
      state.edgeCapsuleTitleCharacterLimit = 0;
    }
    state.titleCharacterLimit = normalizePaperTitleLimit(state.titleCharacterLimit);
    if (typeof state.enablePaperLinks !== 'boolean') {
      state.enablePaperLinks = true;
    }
    if (typeof state.hideLinkedPapersFromCapsules !== 'boolean') {
      state.hideLinkedPapersFromCapsules = false;
    }
    state.overallFontScale = this.normalizeOverallFontScale(state.overallFontScale);
    state.noteTextSize = this.normalizeVisualTextSize(state.noteTextSize);
    state.titleTextSize = this.normalizeVisualTextSize(state.titleTextSize);
    state.capsuleTextSize = this.normalizeVisualTextSize(state.capsuleTextSize);
    if (typeof state.noteTextBold !== 'boolean') {
      state.noteTextBold = false;
    }
    if (typeof state.todoTextBold !== 'boolean') {
      state.todoTextBold = false;
    }
    if (typeof state.titleTextBold !== 'boolean') {
      state.titleTextBold = true;
    }
    if (typeof state.capsuleTextBold !== 'boolean') {
      state.capsuleTextBold = false;
    }
    if (state.resizeGripMode !== RESIZE_GRIP_STANDARD && state.resizeGripMode !== RESIZE_GRIP_HIDDEN) {
      state.resizeGripMode = RESIZE_GRIP_SOFT;
    }
    if (typeof state.showTopBarNewTodoButton !== 'boolean') {
      state.showTopBarNewTodoButton = true;
    }
    if (typeof state.showTopBarNewNoteButton !== 'boolean') {
      state.showTopBarNewNoteButton = true;
    }
    if (typeof state.showTopBarExternalOpenButton !== 'boolean') {
      state.showTopBarExternalOpenButton = true;
    }
    for (let i: number = 0; i < state.papers.length; i++) {
      if (typeof state.papers[i].id !== 'string' || state.papers[i].id.length === 0 ||
        this.hasDuplicatePaperId(state.papers, i, state.papers[i].id)) {
        state.papers[i].id = this.nextId('paper');
      }
      this.normalizePaper(state.papers[i], i);
    }
    if (!state.useCapsuleMode) {
      state.useDeepCapsuleMode = false;
      state.capsuleCollapseAllActive = false;
      state.capsuleStartTop = CAPSULE_EDGE_START_TOP;
      for (let i: number = 0; i < state.papers.length; i++) {
        state.papers[i].isCollapsed = false;
      }
    }
    if (!state.useDeepCapsuleMode || !state.useMasterCapsule || this.countEdgeCapsulePapers(state) === 0) {
      state.capsuleCollapseAllActive = false;
    }
    if (!state.useDeepCapsuleMode || !state.useMasterCapsule) {
      state.capsuleStartTop = CAPSULE_EDGE_START_TOP;
    }
    if (sourceVersion < 3) {
      this.migrateLegacyPixelGeometry(state.papers);
    }
    this.resequencePaperArray(state.papers);
    for (let paperIndex: number = 0; paperIndex < state.papers.length; paperIndex++) {
      const paper: PaperData = state.papers[paperIndex];
      for (let itemIndex: number = 0; itemIndex < paper.items.length; itemIndex++) {
        const linkedId: string | undefined = paper.items[itemIndex].linkedPaperId;
        if (linkedId !== undefined && (linkedId === paper.id || !this.hasPaperId(state.papers, linkedId))) {
          paper.items[itemIndex].linkedPaperId = undefined;
        }
      }
    }
    this.expandIneligibleCapsulePapers(state);
    if (this.countEdgeCapsulePapers(state) === 0) {
      state.capsuleCollapseAllActive = false;
    }
    const normalizedImages: NoteImageAsset[] = [];
    let normalizedImageBytes: number = 0;
    for (let i: number = 0; i < state.noteImages.length; i++) {
      const asset: NoteImageAsset = state.noteImages[i];
      if (this.isValidNoteImage(asset) && this.noteImageHasOwnerReference(state.papers, asset) &&
        !this.hasNoteImageId(normalizedImages, asset.id) &&
        !this.hasNoteImageFileName(normalizedImages, asset.fileName) &&
        normalizedImageBytes + asset.byteLength <= NOTE_IMAGE_TOTAL_MAX_BYTES) {
        normalizedImages.push({
          id: asset.id,
          noteId: asset.noteId,
          fileName: asset.fileName,
          mimeType: asset.mimeType,
          width: asset.width,
          height: asset.height,
          byteLength: asset.byteLength,
          createdAt: asset.createdAt
        });
        normalizedImageBytes += asset.byteLength;
      }
    }
    state.noteImages = normalizedImages;
    state.schemaVersion = SCHEMA_VERSION;
  }

  private normalizePaper(paper: PaperData, fallbackOrder: number): void {
    if (paper.type !== PAPER_TYPE_NOTE) {
      paper.type = PAPER_TYPE_TODO;
    }
    if (typeof paper.title !== 'string') {
      paper.title = '';
    }
    paper.title = cleanPaperTitle(paper.title, TITLE_MAX_LENGTH);

    const legacyX: number = paper.x !== undefined ? paper.x : 120;
    const legacyY: number = paper.y !== undefined ? paper.y : 120;
    const legacyWidth: number = paper.width !== undefined ? paper.width :
      (paper.type === PAPER_TYPE_NOTE ? NOTE_DEFAULT_WIDTH : TODO_DEFAULT_WIDTH);
    const legacyHeight: number = paper.height !== undefined ? paper.height :
      (paper.type === PAPER_TYPE_NOTE ? NOTE_DEFAULT_HEIGHT : TODO_DEFAULT_HEIGHT);

    if (!Number.isFinite(paper.expandedX)) {
      paper.expandedX = legacyX;
    }
    if (!Number.isFinite(paper.expandedY)) {
      paper.expandedY = legacyY;
    }
    if (!Number.isFinite(paper.expandedWidth) || paper.expandedWidth <= 0) {
      paper.expandedWidth = legacyWidth;
    }
    if (!Number.isFinite(paper.expandedHeight) || paper.expandedHeight <= 0) {
      paper.expandedHeight = legacyHeight;
    }
    if (!Number.isFinite(paper.capsuleX)) {
      paper.capsuleX = paper.expandedX;
    }
    if (!Number.isFinite(paper.capsuleY)) {
      paper.capsuleY = paper.expandedY;
    }
    if (!Number.isFinite(paper.capsuleWidth) || paper.capsuleWidth <= 0) {
      paper.capsuleWidth = CAPSULE_WIDTH;
    }
    paper.capsuleWidth = Math.max(CAPSULE_MIN_WIDTH, Math.min(CAPSULE_MAX_WIDTH, paper.capsuleWidth));
    if (paper.edgeSide !== EDGE_SIDE_RIGHT) {
      paper.edgeSide = EDGE_SIDE_RIGHT;
    }
    if (!Number.isFinite(paper.edgeOrder) || paper.edgeOrder < 0) {
      paper.edgeOrder = fallbackOrder;
    }
    // HarmonyOS 版本只维护单屏单队列，旧显示器 ID 必须在迁移时合并。
    paper.edgeDisplayId = DEFAULT_DISPLAY_ID;
    if (paper.items === undefined || !Array.isArray(paper.items)) {
      paper.items = [];
    }
    for (let i: number = 0; i < paper.items.length; i++) {
      const item: PaperItem = paper.items[i];
      if (typeof item.id !== 'string' || item.id.length === 0 ||
        this.hasDuplicateItemId(paper.items, i, item.id)) {
        item.id = this.nextId('item');
      }
      if (typeof item.text !== 'string') {
        item.text = '';
      }
      item.text = truncateText(item.text, TODO_ITEM_MAX_LENGTH);
      if (typeof item.done !== 'boolean') {
        item.done = false;
      }
      item.order = i;
      if (item.linkedPaperId !== undefined &&
        (typeof item.linkedPaperId !== 'string' || item.linkedPaperId.length === 0)) {
        item.linkedPaperId = undefined;
      }
      if (item.quickLaunchUri !== undefined &&
        (typeof item.quickLaunchUri !== 'string' || item.quickLaunchUri.length === 0)) {
        item.quickLaunchUri = undefined;
      }
      if (item.quickLaunchUri === undefined) {
        item.quickLaunchName = undefined;
        item.quickLaunchKind = undefined;
      } else {
        item.quickLaunchUri = truncateText(item.quickLaunchUri, QUICK_LAUNCH_URI_MAX_LENGTH);
        item.quickLaunchName = truncateText(typeof item.quickLaunchName === 'string' ? item.quickLaunchName : '',
          QUICK_LAUNCH_NAME_MAX_LENGTH);
        if (item.quickLaunchKind !== QUICK_LAUNCH_FOLDER) {
          item.quickLaunchKind = QUICK_LAUNCH_FILE;
        }
        item.linkedPaperId = undefined;
      }
    }
    if (typeof paper.content !== 'string') {
      paper.content = '';
    }
    paper.content = truncateText(paper.content, NOTE_MAX_LENGTH);
    if (!Number.isFinite(paper.createdAt)) {
      paper.createdAt = Date.now();
    }
    if (!Number.isFinite(paper.updatedAt)) {
      paper.updatedAt = paper.createdAt;
    }
    if (typeof paper.isVisible !== 'boolean') {
      paper.isVisible = true;
    }
    if (typeof paper.alwaysOnTop !== 'boolean') {
      paper.alwaysOnTop = false;
    }
    if (typeof paper.isCollapsed !== 'boolean') {
      paper.isCollapsed = false;
    }
    if (!Number.isFinite(paper.textZoom) || paper.textZoom < 0.5 || paper.textZoom > 1.5) {
      paper.textZoom = 1;
    }
  }

  private resequenceEdges(): void {
    this.resequencePaperArray(this.ensureState().papers);
  }

  private isValidNoteImage(asset: NoteImageAsset): boolean {
    return asset !== undefined && asset.id !== undefined && /^img_[0-9]+_[0-9]+$/.test(asset.id) &&
      asset.noteId !== undefined && asset.noteId.length > 0 && asset.fileName !== undefined &&
      NoteImageStore.isManagedFileName(asset.fileName) && asset.mimeType !== undefined &&
      NoteImageStore.isSupportedMimeType(asset.mimeType) &&
      asset.fileName === asset.id + NoteImageStore.extensionForMime(asset.mimeType) &&
      Number.isFinite(asset.width) && asset.width > 0 && asset.width <= NOTE_IMAGE_DIMENSION_MAX &&
      Number.isFinite(asset.height) && asset.height > 0 && asset.height <= NOTE_IMAGE_DIMENSION_MAX &&
      Number.isFinite(asset.byteLength) && asset.byteLength > 0 && asset.byteLength <= NOTE_IMAGE_FILE_MAX_BYTES &&
      Number.isFinite(asset.createdAt);
  }

  private hasNoteImageId(assets: NoteImageAsset[], id: string): boolean {
    for (let i: number = 0; i < assets.length; i++) {
      if (assets[i].id === id) {
        return true;
      }
    }
    return false;
  }

  private hasNoteImageFileName(assets: NoteImageAsset[], fileName: string): boolean {
    for (let i: number = 0; i < assets.length; i++) {
      if (assets[i].fileName === fileName) {
        return true;
      }
    }
    return false;
  }

  private noteImageHasOwnerReference(papers: PaperData[], asset: NoteImageAsset): boolean {
    for (let i: number = 0; i < papers.length; i++) {
      if (papers[i].id === asset.noteId && papers[i].type === PAPER_TYPE_NOTE) {
        return papers[i].content.indexOf('(i:' + asset.id + ')') >= 0;
      }
    }
    return false;
  }

  private protectedImageFileNames(): string[] {
    const names: string[] = [];
    const state: AppState = this.ensureState();
    for (let i: number = 0; i < state.noteImages.length; i++) {
      this.pushUniqueManagedFileName(names, state.noteImages[i].fileName);
    }
    if (this.store === null) {
      return names;
    }
    try {
      const raw: string = this.store.getSync(BACKUP_KEY, '') as string;
      if (raw.length === 0) {
        return names;
      }
      const backup: AppState = JSON.parse(raw) as AppState;
      if (backup.noteImages === undefined || !Array.isArray(backup.noteImages)) {
        return names;
      }
      for (let i: number = 0; i < backup.noteImages.length; i++) {
        if (backup.noteImages[i] !== undefined && backup.noteImages[i].fileName !== undefined) {
          this.pushUniqueManagedFileName(names, backup.noteImages[i].fileName);
        }
      }
    } catch (error) {
      console.warn('read protected backup images failed: ' + String(error));
    }
    return names;
  }

  private pushUniqueManagedFileName(names: string[], fileName: string): void {
    if (!NoteImageStore.isManagedFileName(fileName)) {
      return;
    }
    for (let i: number = 0; i < names.length; i++) {
      if (names[i] === fileName) {
        return;
      }
    }
    names.push(fileName);
  }

  private resequencePaperArray(source: PaperData[]): void {
    const papers: PaperData[] = source.slice();
    papers.sort((a: PaperData, b: PaperData): number => a.edgeOrder - b.edgeOrder);
    for (let i: number = 0; i < papers.length; i++) {
      papers[i].edgeOrder = i;
    }
  }

  private nextEdgeOrder(state: AppState): number {
    let maxOrder: number = -1;
    for (let i: number = 0; i < state.papers.length; i++) {
      if (state.papers[i].edgeOrder > maxOrder) {
        maxOrder = state.papers[i].edgeOrder;
      }
    }
    return maxOrder + 1;
  }

  private countEdgeCapsulePapers(state: AppState): number {
    if (!state.useCapsuleMode || !state.useDeepCapsuleMode) {
      return 0;
    }
    let count: number = 0;
    for (let i: number = 0; i < state.papers.length; i++) {
      if (this.canPaperDisplayAsCapsuleInState(state, state.papers[i]) && state.papers[i].isVisible &&
        (state.papers[i].isCollapsed || state.showDeepCapsuleWhileExpanded)) {
        count += 1;
      }
    }
    return count;
  }

  private createDefaultState(): AppState {
    const now: number = Date.now();
    const systemLanguage: string = this.currentSystemLanguage();
    const firstPaper: PaperData = {
      id: this.nextId('paper'),
      type: PAPER_TYPE_TODO,
      title: defaultPaperTitle(PAPER_TYPE_TODO, 1, UI_LANGUAGE_SYSTEM, systemLanguage),
      expandedX: 120,
      expandedY: 120,
      expandedWidth: TODO_DEFAULT_WIDTH,
      expandedHeight: TODO_DEFAULT_HEIGHT,
      capsuleX: 120,
      capsuleY: 120,
      capsuleWidth: CAPSULE_WIDTH,
      edgeSide: EDGE_SIDE_RIGHT,
      edgeOrder: 0,
      edgeDisplayId: DEFAULT_DISPLAY_ID,
      isVisible: true,
      alwaysOnTop: false,
      isCollapsed: false,
      textZoom: 1,
      items: [this.createItem('', 0)],
      content: '',
      createdAt: now,
      updatedAt: now
    };
    return {
      schemaVersion: SCHEMA_VERSION,
      initialized: true,
      papers: [firstPaper],
      noteImages: [],
      autoCompressLargeImages: true,
      globalHotkeysEnabled: false,
      uiLanguage: UI_LANGUAGE_SYSTEM,
      theme: THEME_SYSTEM,
      colorScheme: COLOR_SCHEME_WARM,
      markdownRenderMode: MARKDOWN_ENHANCED,
      useCapsuleMode: true,
      useDeepCapsuleMode: true,
      showDeepCapsuleWhileExpanded: true,
      useMasterCapsule: true,
      capsuleCollapseAllActive: false,
      capsuleStartTop: CAPSULE_EDGE_START_TOP,
      todoVisualSize: TODO_VISUAL_MEDIUM,
      autoClearCompletedTodos: false,
      autoBottomCompleted: false,
      capsuleGap: CAPSULE_GAP_DEFAULT,
      enableAnimations: true,
      rememberEdgeExpandedPosition: true,
      collapseExpandedEdgeCapsuleOnClick: false,
      hideEdgeCapsuleCloseButtonOnHover: false,
      edgeCapsuleTitleCharacterLimit: 0,
      titleCharacterLimit: DEFAULT_PAPER_TITLE_LIMIT,
      enablePaperLinks: true,
      hideLinkedPapersFromCapsules: false,
      overallFontScale: 1,
      noteTextSize: VISUAL_TEXT_MEDIUM,
      noteTextBold: false,
      todoTextBold: false,
      titleTextSize: VISUAL_TEXT_MEDIUM,
      titleTextBold: true,
      capsuleTextSize: VISUAL_TEXT_MEDIUM,
      capsuleTextBold: false,
      resizeGripMode: RESIZE_GRIP_SOFT,
      showTopBarNewTodoButton: true,
      showTopBarNewNoteButton: true,
      showTopBarExternalOpenButton: true
    };
  }

  private createSafeEmptyState(): AppState {
    return {
      schemaVersion: SCHEMA_VERSION,
      initialized: false,
      papers: [],
      noteImages: [],
      autoCompressLargeImages: true,
      globalHotkeysEnabled: false,
      uiLanguage: UI_LANGUAGE_SYSTEM,
      theme: THEME_SYSTEM,
      colorScheme: COLOR_SCHEME_WARM,
      markdownRenderMode: MARKDOWN_ENHANCED,
      useCapsuleMode: true,
      useDeepCapsuleMode: true,
      showDeepCapsuleWhileExpanded: true,
      useMasterCapsule: true,
      capsuleCollapseAllActive: false,
      capsuleStartTop: CAPSULE_EDGE_START_TOP,
      todoVisualSize: TODO_VISUAL_MEDIUM,
      autoClearCompletedTodos: false,
      autoBottomCompleted: false,
      capsuleGap: CAPSULE_GAP_DEFAULT,
      enableAnimations: true,
      rememberEdgeExpandedPosition: true,
      collapseExpandedEdgeCapsuleOnClick: false,
      hideEdgeCapsuleCloseButtonOnHover: false,
      edgeCapsuleTitleCharacterLimit: 0,
      titleCharacterLimit: DEFAULT_PAPER_TITLE_LIMIT,
      enablePaperLinks: true,
      hideLinkedPapersFromCapsules: false,
      overallFontScale: 1,
      noteTextSize: VISUAL_TEXT_MEDIUM,
      noteTextBold: false,
      todoTextBold: false,
      titleTextSize: VISUAL_TEXT_MEDIUM,
      titleTextBold: true,
      capsuleTextSize: VISUAL_TEXT_MEDIUM,
      capsuleTextBold: false,
      resizeGripMode: RESIZE_GRIP_SOFT,
      showTopBarNewTodoButton: true,
      showTopBarNewNoteButton: true,
      showTopBarExternalOpenButton: true
    };
  }

  private ensureState(): AppState {
    if (this.state === null) {
      this.state = this.createSafeEmptyState();
    }
    return this.state;
  }

  private publishSettings(): void {
    const state: AppState = this.ensureState();
    AppStorage.setOrCreate<string>('uiLanguage', state.uiLanguage);
    this.refreshSystemLanguage();
    AppStorage.setOrCreate<string>('theme', state.theme);
    AppStorage.setOrCreate<string>('colorScheme', state.colorScheme);
    AppStorage.setOrCreate<string>('markdownRenderMode', state.markdownRenderMode);
    AppStorage.setOrCreate<boolean>('useCapsuleMode', state.useCapsuleMode);
    AppStorage.setOrCreate<boolean>('useDeepCapsuleMode', state.useDeepCapsuleMode);
    AppStorage.setOrCreate<boolean>('showDeepCapsuleWhileExpanded', state.showDeepCapsuleWhileExpanded);
    AppStorage.setOrCreate<boolean>('useMasterCapsule', state.useMasterCapsule);
    AppStorage.setOrCreate<boolean>('capsuleCollapseAllActive', state.capsuleCollapseAllActive);
    AppStorage.setOrCreate<number>('capsuleStartTop', state.capsuleStartTop);
    AppStorage.setOrCreate<string>('todoVisualSize', state.todoVisualSize);
    AppStorage.setOrCreate<boolean>('autoClearCompletedTodos', state.autoClearCompletedTodos);
    AppStorage.setOrCreate<boolean>('autoBottomCompleted', state.autoBottomCompleted);
    AppStorage.setOrCreate<boolean>('autoCompressLargeImages', state.autoCompressLargeImages);
    AppStorage.setOrCreate<boolean>('globalHotkeysEnabled', state.globalHotkeysEnabled);
    AppStorage.setOrCreate<number>('capsuleGap', state.capsuleGap);
    AppStorage.setOrCreate<boolean>('enableAnimations', state.enableAnimations);
    AppStorage.setOrCreate<boolean>('rememberEdgeExpandedPosition', state.rememberEdgeExpandedPosition);
    AppStorage.setOrCreate<boolean>('collapseExpandedEdgeCapsuleOnClick', state.collapseExpandedEdgeCapsuleOnClick);
    AppStorage.setOrCreate<boolean>('hideEdgeCapsuleCloseButtonOnHover', state.hideEdgeCapsuleCloseButtonOnHover);
    AppStorage.setOrCreate<number>('edgeCapsuleTitleCharacterLimit', state.edgeCapsuleTitleCharacterLimit);
    AppStorage.setOrCreate<number>('titleCharacterLimit', state.titleCharacterLimit);
    AppStorage.setOrCreate<boolean>('enablePaperLinks', state.enablePaperLinks);
    AppStorage.setOrCreate<boolean>('hideLinkedPapersFromCapsules', state.hideLinkedPapersFromCapsules);
    AppStorage.setOrCreate<number>('overallFontScale', state.overallFontScale);
    AppStorage.setOrCreate<string>('noteTextSize', state.noteTextSize);
    AppStorage.setOrCreate<boolean>('noteTextBold', state.noteTextBold);
    AppStorage.setOrCreate<boolean>('todoTextBold', state.todoTextBold);
    AppStorage.setOrCreate<string>('titleTextSize', state.titleTextSize);
    AppStorage.setOrCreate<boolean>('titleTextBold', state.titleTextBold);
    AppStorage.setOrCreate<string>('capsuleTextSize', state.capsuleTextSize);
    AppStorage.setOrCreate<boolean>('capsuleTextBold', state.capsuleTextBold);
    AppStorage.setOrCreate<string>('resizeGripMode', state.resizeGripMode);
    AppStorage.setOrCreate<boolean>('showTopBarNewTodoButton', state.showTopBarNewTodoButton);
    AppStorage.setOrCreate<boolean>('showTopBarNewNoteButton', state.showTopBarNewNoteButton);
    AppStorage.setOrCreate<boolean>('showTopBarExternalOpenButton', state.showTopBarExternalOpenButton);
    this.refreshCapsuleEligibilitySignature(state);
    this.notifyRevision();
  }

  private isPaperLinkedToAnyTodoInState(state: AppState, paperId: string): boolean {
    if (paperId.length === 0) {
      return false;
    }
    for (let paperIndex: number = 0; paperIndex < state.papers.length; paperIndex++) {
      const source: PaperData = state.papers[paperIndex];
      if (source.type !== PAPER_TYPE_TODO) {
        continue;
      }
      for (let itemIndex: number = 0; itemIndex < source.items.length; itemIndex++) {
        if (source.items[itemIndex].linkedPaperId === paperId) {
          return true;
        }
      }
    }
    return false;
  }

  private canPaperDisplayAsCapsuleInState(state: AppState, paper: PaperData): boolean {
    if (!state.useCapsuleMode) {
      return false;
    }
    return !(state.enablePaperLinks && state.hideLinkedPapersFromCapsules &&
      this.isPaperLinkedToAnyTodoInState(state, paper.id));
  }

  private expandIneligibleCapsulePapers(state: AppState): boolean {
    if (!state.enablePaperLinks || !state.hideLinkedPapersFromCapsules) {
      return false;
    }
    let changed: boolean = false;
    for (let i: number = 0; i < state.papers.length; i++) {
      if (state.papers[i].isCollapsed && !this.canPaperDisplayAsCapsuleInState(state, state.papers[i])) {
        state.papers[i].isCollapsed = false;
        state.papers[i].updatedAt = Date.now();
        changed = true;
      }
    }
    return changed;
  }

  private capsuleEligibilitySignatureForState(state: AppState): string {
    const linkedIds: string[] = [];
    for (let paperIndex: number = 0; paperIndex < state.papers.length; paperIndex++) {
      const source: PaperData = state.papers[paperIndex];
      if (source.type !== PAPER_TYPE_TODO) {
        continue;
      }
      for (let itemIndex: number = 0; itemIndex < source.items.length; itemIndex++) {
        const linkedId: string | undefined = source.items[itemIndex].linkedPaperId;
        if (linkedId !== undefined && linkedIds.indexOf(linkedId) < 0) {
          linkedIds.push(linkedId);
        }
      }
    }
    linkedIds.sort();
    return (state.useCapsuleMode ? '1' : '0') + (state.enablePaperLinks ? '1' : '0') +
      (state.hideLinkedPapersFromCapsules ? '1' : '0') + ':' + linkedIds.join('|');
  }

  private refreshCapsuleEligibilitySignature(state: AppState): boolean {
    const next: string = this.capsuleEligibilitySignatureForState(state);
    if (!this.capsuleEligibilitySignatureInitialized) {
      this.capsuleEligibilitySignature = next;
      this.capsuleEligibilitySignatureInitialized = true;
      return false;
    }
    const changed: boolean = this.capsuleEligibilitySignature !== next;
    this.capsuleEligibilitySignature = next;
    return changed;
  }

  refreshSystemLanguage(): void {
    try {
      AppStorage.setOrCreate<string>('systemLanguage', i18n.System.getSystemLanguage());
    } catch (error) {
      AppStorage.setOrCreate<string>('systemLanguage', UI_LANGUAGE_ZH_CN);
    }
  }

  private normalizeUiLanguage(language: string): string {
    if (language === UI_LANGUAGE_ZH_CN || language === UI_LANGUAGE_EN || language === UI_LANGUAGE_JA ||
      language === UI_LANGUAGE_KO) {
      return language;
    }
    return UI_LANGUAGE_SYSTEM;
  }

  private currentSystemLanguage(): string {
    try {
      return i18n.System.getSystemLanguage();
    } catch (error) {
      return UI_LANGUAGE_ZH_CN;
    }
  }

  private normalizeColorScheme(scheme: string): string {
    if (scheme === COLOR_SCHEME_INK || scheme === COLOR_SCHEME_FOREST || scheme === COLOR_SCHEME_SUNSET) {
      return scheme;
    }
    return COLOR_SCHEME_WARM;
  }

  private normalizeVisualTextSize(size: string): string {
    if (size === VISUAL_TEXT_SMALL || size === VISUAL_TEXT_LARGE) {
      return size;
    }
    return VISUAL_TEXT_MEDIUM;
  }

  private normalizeOverallFontScale(scale: number): number {
    if (!Number.isFinite(scale) || scale <= 0) {
      return 1;
    }
    const clamped: number = Math.max(0.8, Math.min(1.2, scale));
    return Math.round(clamped * 20) / 20;
  }

  private hasDuplicateItemId(items: PaperItem[], currentIndex: number, id: string): boolean {
    for (let i: number = 0; i < currentIndex; i++) {
      if (items[i].id === id) {
        return true;
      }
    }
    return false;
  }

  private hasDuplicatePaperId(papers: PaperData[], currentIndex: number, id: string): boolean {
    for (let i: number = 0; i < currentIndex; i++) {
      if (papers[i].id === id) {
        return true;
      }
    }
    return false;
  }

  private hasPaperId(papers: PaperData[], id: string): boolean {
    for (let i: number = 0; i < papers.length; i++) {
      if (papers[i].id === id) {
        return true;
      }
    }
    return false;
  }

  private sanitizePaperLinks(paper: PaperData): void {
    for (let i: number = 0; i < paper.items.length; i++) {
      const linkedId: string | undefined = paper.items[i].linkedPaperId;
      if (linkedId !== undefined && (linkedId === paper.id || this.getPaper(linkedId) === null)) {
        paper.items[i].linkedPaperId = undefined;
      }
    }
  }

  private migrateLegacyPixelGeometry(papers: PaperData[]): void {
    let density: number = 1;
    try {
      density = display.getDefaultDisplaySync().densityPixels;
    } catch (error) {
      console.warn('PaperTodo legacy geometry density lookup failed: ' + String(error));
    }
    if (!Number.isFinite(density) || density <= 0 || Math.abs(density - 1) < 0.001) {
      return;
    }
    for (let i: number = 0; i < papers.length; i++) {
      papers[i].expandedX /= density;
      papers[i].expandedY /= density;
      papers[i].expandedWidth /= density;
      papers[i].expandedHeight /= density;
      papers[i].capsuleX /= density;
      papers[i].capsuleY /= density;
    }
  }

  private notifyRevision(): void {
    this.revision += 1;
    AppStorage.setOrCreate<number>('paperRevision', this.revision);
  }

  private nextId(prefix: string): string {
    this.sequence += 1;
    return prefix + '_' + Date.now().toString(36) + '_' + this.sequence.toString(36);
  }

  private createItem(text: string, order: number): PaperItem {
    return {
      id: this.nextId('item'),
      text: text,
      done: false,
      order: order
    };
  }
}

export const PaperStore: PaperStoreImpl = new PaperStoreImpl();
