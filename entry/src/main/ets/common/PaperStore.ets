import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  AppState,
  CAPSULE_GAP_DEFAULT,
  DEFAULT_DISPLAY_ID,
  EDGE_SIDE_RIGHT,
  MARKDOWN_BASIC,
  MARKDOWN_ENHANCED,
  MARKDOWN_OFF,
  MAX_PAPERS,
  NOTE_DEFAULT_HEIGHT,
  NOTE_DEFAULT_WIDTH,
  NOTE_MAX_LENGTH,
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  PaperData,
  PaperItem,
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
  TODO_VISUAL_XLARGE
} from './Models';

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

    if (this.state === null) {
      const loaded: LoadResult = this.loadInitialState();
      this.state = loaded.state;
      this.persistedJson = loaded.persistedJson;
      this.storageBlocked = this.storageBlocked || loaded.blocked;
      if (loaded.shouldPersist && !this.storageBlocked) {
        this.dirty = true;
        this.flushNow();
      }
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
    const offset: number = (state.papers.length % 8) * 28;
    const startX: number = source !== null ? source.expandedX + 32 : 120 + offset;
    const startY: number = source !== null ? source.expandedY + 32 : 120 + offset;
    const edgeOrder: number = this.nextEdgeOrder(state);
    const paper: PaperData = {
      id: this.nextId('paper'),
      type: isNote ? PAPER_TYPE_NOTE : PAPER_TYPE_TODO,
      title: '',
      expandedX: startX,
      expandedY: startY,
      expandedWidth: isNote ? NOTE_DEFAULT_WIDTH : TODO_DEFAULT_WIDTH,
      expandedHeight: isNote ? NOTE_DEFAULT_HEIGHT : TODO_DEFAULT_HEIGHT,
      capsuleX: startX,
      capsuleY: startY,
      edgeSide: EDGE_SIDE_RIGHT,
      edgeOrder: edgeOrder,
      edgeDisplayId: DEFAULT_DISPLAY_ID,
      isVisible: true,
      alwaysOnTop: false,
      isCollapsed: false,
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
    paper.updatedAt = Date.now();
    const papers: PaperData[] = this.ensureState().papers;
    for (let i: number = 0; i < papers.length; i++) {
      if (papers[i].id === paper.id) {
        papers[i] = paper;
        this.requestSave(immediate);
        return;
      }
    }
    if (papers.length < MAX_PAPERS) {
      papers.push(paper);
      this.requestSave(immediate);
    }
  }

  deletePaper(id: string): void {
    if (this.storageBlocked) {
      return;
    }
    const state: AppState = this.ensureState();
    const next: PaperData[] = [];
    for (let i: number = 0; i < state.papers.length; i++) {
      if (state.papers[i].id !== id) {
        next.push(state.papers[i]);
      }
    }
    state.papers = next;
    this.resequenceEdges();
    this.requestSave(true);
    this.notifyRevision();
  }

  setPaperVisible(id: string, visible: boolean): void {
    const paper: PaperData | null = this.getPaper(id);
    if (paper === null) {
      return;
    }
    paper.isVisible = visible;
    this.updatePaper(paper, true);
    this.notifyRevision();
  }

  setTheme(theme: string): void {
    const state: AppState = this.ensureState();
    state.theme = theme === THEME_LIGHT || theme === THEME_DARK ? theme : THEME_SYSTEM;
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

  setCapsuleGap(gap: number): void {
    const state: AppState = this.ensureState();
    state.capsuleGap = gap === 0 || gap === 8 ? gap : CAPSULE_GAP_DEFAULT;
    this.requestSave(true);
    this.publishSettings();
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
    this.requestSave(false);
    this.notifyRevision();
  }

  createTodoItem(text: string, order: number): PaperItem {
    return this.createItem(text.slice(0, TODO_ITEM_MAX_LENGTH), order);
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
        const recovered: AppState | null = this.parseState(backup);
        if (recovered !== null) {
          return { state: recovered, persistedJson: backup, shouldPersist: true, blocked: false };
        }
      }
      return { state: this.createDefaultState(), persistedJson: '', shouldPersist: true, blocked: false };
    }

    const parsed: AppState | null = this.parseState(raw);
    if (parsed !== null) {
      const normalized: string = JSON.stringify(parsed);
      return { state: parsed, persistedJson: raw, shouldPersist: normalized !== raw, blocked: false };
    }

    if (backup.length > 0) {
      const recovered: AppState | null = this.parseState(backup);
      if (recovered !== null) {
        return { state: recovered, persistedJson: backup, shouldPersist: true, blocked: false };
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
      this.normalizeState(parsed);
      return parsed;
    } catch (error) {
      console.error('PaperTodo state parse failed: ' + String(error));
      return null;
    }
  }

  private normalizeState(state: AppState): void {
    state.schemaVersion = SCHEMA_VERSION;
    state.initialized = true;
    state.theme = state.theme === THEME_LIGHT || state.theme === THEME_DARK ? state.theme : THEME_SYSTEM;
    if (state.markdownRenderMode !== MARKDOWN_OFF && state.markdownRenderMode !== MARKDOWN_BASIC) {
      state.markdownRenderMode = MARKDOWN_ENHANCED;
    }
    if (state.todoVisualSize !== TODO_VISUAL_SMALL && state.todoVisualSize !== TODO_VISUAL_LARGE &&
      state.todoVisualSize !== TODO_VISUAL_XLARGE) {
      state.todoVisualSize = TODO_VISUAL_MEDIUM;
    }
    if (state.autoBottomCompleted === undefined) {
      state.autoBottomCompleted = false;
    }
    if (state.capsuleGap !== 0 && state.capsuleGap !== 8) {
      state.capsuleGap = CAPSULE_GAP_DEFAULT;
    }
    if (state.useCapsuleMode === undefined) {
      state.useCapsuleMode = true;
    }
    if (state.useDeepCapsuleMode === undefined) {
      state.useDeepCapsuleMode = true;
    }

    for (let i: number = 0; i < state.papers.length; i++) {
      this.normalizePaper(state.papers[i], i);
    }
  }

  private normalizePaper(paper: PaperData, fallbackOrder: number): void {
    if (paper.type !== PAPER_TYPE_NOTE) {
      paper.type = PAPER_TYPE_TODO;
    }
    if (paper.title === undefined) {
      paper.title = '';
    }
    paper.title = paper.title.slice(0, TITLE_MAX_LENGTH);

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
    if (paper.edgeSide !== EDGE_SIDE_RIGHT) {
      paper.edgeSide = EDGE_SIDE_RIGHT;
    }
    if (!Number.isFinite(paper.edgeOrder) || paper.edgeOrder < 0) {
      paper.edgeOrder = fallbackOrder;
    }
    if (paper.edgeDisplayId === undefined || paper.edgeDisplayId.length === 0) {
      paper.edgeDisplayId = DEFAULT_DISPLAY_ID;
    }
    if (paper.items === undefined) {
      paper.items = [];
    }
    for (let i: number = 0; i < paper.items.length; i++) {
      const item: PaperItem = paper.items[i];
      if (item.text === undefined) {
        item.text = '';
      }
      item.text = item.text.slice(0, TODO_ITEM_MAX_LENGTH);
      item.order = i;
    }
    if (paper.content === undefined) {
      paper.content = '';
    }
    paper.content = paper.content.slice(0, NOTE_MAX_LENGTH);
    if (!Number.isFinite(paper.createdAt)) {
      paper.createdAt = Date.now();
    }
    if (!Number.isFinite(paper.updatedAt)) {
      paper.updatedAt = paper.createdAt;
    }
  }

  private resequenceEdges(): void {
    const papers: PaperData[] = this.ensureState().papers.slice();
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

  private createDefaultState(): AppState {
    const now: number = Date.now();
    const firstPaper: PaperData = {
      id: this.nextId('paper'),
      type: PAPER_TYPE_TODO,
      title: '',
      expandedX: 120,
      expandedY: 120,
      expandedWidth: TODO_DEFAULT_WIDTH,
      expandedHeight: TODO_DEFAULT_HEIGHT,
      capsuleX: 120,
      capsuleY: 120,
      edgeSide: EDGE_SIDE_RIGHT,
      edgeOrder: 0,
      edgeDisplayId: DEFAULT_DISPLAY_ID,
      isVisible: true,
      alwaysOnTop: false,
      isCollapsed: false,
      items: [this.createItem('', 0)],
      content: '',
      createdAt: now,
      updatedAt: now
    };
    return {
      schemaVersion: SCHEMA_VERSION,
      initialized: true,
      papers: [firstPaper],
      theme: THEME_SYSTEM,
      markdownRenderMode: MARKDOWN_ENHANCED,
      useCapsuleMode: true,
      useDeepCapsuleMode: true,
      todoVisualSize: TODO_VISUAL_MEDIUM,
      autoBottomCompleted: false,
      capsuleGap: CAPSULE_GAP_DEFAULT
    };
  }

  private createSafeEmptyState(): AppState {
    return {
      schemaVersion: SCHEMA_VERSION,
      initialized: false,
      papers: [],
      theme: THEME_SYSTEM,
      markdownRenderMode: MARKDOWN_ENHANCED,
      useCapsuleMode: true,
      useDeepCapsuleMode: true,
      todoVisualSize: TODO_VISUAL_MEDIUM,
      autoBottomCompleted: false,
      capsuleGap: CAPSULE_GAP_DEFAULT
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
    AppStorage.setOrCreate<string>('theme', state.theme);
    AppStorage.setOrCreate<string>('markdownRenderMode', state.markdownRenderMode);
    AppStorage.setOrCreate<boolean>('useCapsuleMode', state.useCapsuleMode);
    AppStorage.setOrCreate<boolean>('useDeepCapsuleMode', state.useDeepCapsuleMode);
    AppStorage.setOrCreate<string>('todoVisualSize', state.todoVisualSize);
    AppStorage.setOrCreate<boolean>('autoBottomCompleted', state.autoBottomCompleted);
    AppStorage.setOrCreate<number>('capsuleGap', state.capsuleGap);
    this.notifyRevision();
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
