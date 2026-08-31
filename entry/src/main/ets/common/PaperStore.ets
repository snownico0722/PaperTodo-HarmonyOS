import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  AppState,
  CAPSULE_HEIGHT,
  MARKDOWN_BASIC,
  MARKDOWN_ENHANCED,
  MARKDOWN_OFF,
  NOTE_DEFAULT_HEIGHT,
  NOTE_DEFAULT_WIDTH,
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  PaperData,
  PaperItem,
  THEME_DARK,
  THEME_LIGHT,
  THEME_SYSTEM,
  TODO_DEFAULT_HEIGHT,
  TODO_DEFAULT_WIDTH
} from './Models';

const STORE_NAME: string = 'PaperTodoState';
const STATE_KEY: string = 'state_json';
const BACKUP_KEY: string = 'state_backup_json';

export class PaperStore {
  private static store: preferences.Preferences | null = null;
  private static sequence: number = 0;

  static initialize(context: Context): void {
    if (this.store === null) {
      const options: preferences.Options = { name: STORE_NAME };
      this.store = preferences.getPreferencesSync(context, options);
    }

    let state: AppState = this.loadStateInternal();
    if (state.papers.length === 0) {
      state = this.createDefaultState();
      this.saveStateInternal(state, false);
    }
    this.publishSettings(state);
  }

  static loadState(): AppState {
    return this.loadStateInternal();
  }

  static listPapers(): PaperData[] {
    return this.loadStateInternal().papers;
  }

  static getPaper(id: string): PaperData | null {
    const state: AppState = this.loadStateInternal();
    for (let i: number = 0; i < state.papers.length; i++) {
      if (state.papers[i].id === id) {
        return state.papers[i];
      }
    }
    return null;
  }

  static createPaper(type: string): PaperData {
    const state: AppState = this.loadStateInternal();
    const isNote: boolean = type === PAPER_TYPE_NOTE;
    const now: number = Date.now();
    const offset: number = (state.papers.length % 8) * 28;
    const paper: PaperData = {
      id: this.nextId('paper'),
      type: isNote ? PAPER_TYPE_NOTE : PAPER_TYPE_TODO,
      title: '',
      x: 120 + offset,
      y: 120 + offset,
      width: isNote ? NOTE_DEFAULT_WIDTH : TODO_DEFAULT_WIDTH,
      height: isNote ? NOTE_DEFAULT_HEIGHT : TODO_DEFAULT_HEIGHT,
      isVisible: true,
      alwaysOnTop: false,
      isCollapsed: false,
      items: isNote ? [] : [this.createItem('', 0)],
      content: '',
      createdAt: now,
      updatedAt: now
    };
    state.papers.push(paper);
    this.saveStateInternal(state, true);
    return paper;
  }

  static updatePaper(paper: PaperData): void {
    const state: AppState = this.loadStateInternal();
    paper.updatedAt = Date.now();
    for (let i: number = 0; i < state.papers.length; i++) {
      if (state.papers[i].id === paper.id) {
        state.papers[i] = paper;
        this.saveStateInternal(state, true);
        return;
      }
    }
    state.papers.push(paper);
    this.saveStateInternal(state, true);
  }

  static deletePaper(id: string): void {
    const state: AppState = this.loadStateInternal();
    const next: PaperData[] = [];
    for (let i: number = 0; i < state.papers.length; i++) {
      if (state.papers[i].id !== id) {
        next.push(state.papers[i]);
      }
    }
    state.papers = next;
    this.saveStateInternal(state, true);
  }

  static setPaperVisible(id: string, visible: boolean): void {
    const paper: PaperData | null = this.getPaper(id);
    if (paper === null) {
      return;
    }
    paper.isVisible = visible;
    this.updatePaper(paper);
  }

  static setTheme(theme: string): void {
    const state: AppState = this.loadStateInternal();
    if (theme !== THEME_LIGHT && theme !== THEME_DARK) {
      state.theme = THEME_SYSTEM;
    } else {
      state.theme = theme;
    }
    this.saveStateInternal(state, true);
    this.publishSettings(state);
  }

  static setMarkdownMode(mode: string): void {
    const state: AppState = this.loadStateInternal();
    if (mode !== MARKDOWN_OFF && mode !== MARKDOWN_BASIC) {
      state.markdownRenderMode = MARKDOWN_ENHANCED;
    } else {
      state.markdownRenderMode = mode;
    }
    this.saveStateInternal(state, true);
    this.publishSettings(state);
  }

  static setCapsuleMode(enabled: boolean): void {
    const state: AppState = this.loadStateInternal();
    state.useCapsuleMode = enabled;
    if (!enabled) {
      for (let i: number = 0; i < state.papers.length; i++) {
        state.papers[i].isCollapsed = false;
      }
    }
    this.saveStateInternal(state, true);
    this.publishSettings(state);
  }

  static setDeepCapsuleMode(enabled: boolean): void {
    const state: AppState = this.loadStateInternal();
    state.useDeepCapsuleMode = enabled;
    this.saveStateInternal(state, true);
    this.publishSettings(state);
  }

  static getCollapsedIndex(id: string): number {
    const state: AppState = this.loadStateInternal();
    let collapsedIndex: number = 0;
    for (let i: number = 0; i < state.papers.length; i++) {
      const paper: PaperData = state.papers[i];
      if (paper.id === id) {
        return collapsedIndex;
      }
      if (paper.isVisible && paper.isCollapsed) {
        collapsedIndex += 1;
      }
    }
    return collapsedIndex;
  }

  static createTodoItem(text: string, order: number): PaperItem {
    return this.createItem(text, order);
  }

  static restoreBackup(): boolean {
    if (this.store === null) {
      return false;
    }
    try {
      const backup: string = this.store.getSync(BACKUP_KEY, '') as string;
      if (backup.length === 0) {
        return false;
      }
      const state: AppState = JSON.parse(backup) as AppState;
      if (state.papers === undefined) {
        return false;
      }
      this.store.putSync(STATE_KEY, backup);
      this.store.flushSync();
      this.publishSettings(state);
      return true;
    } catch (error) {
      console.error('PaperTodo restore backup failed: ' + String(error));
      return false;
    }
  }

  private static loadStateInternal(): AppState {
    if (this.store === null) {
      return this.createDefaultState();
    }

    try {
      const raw: string = this.store.getSync(STATE_KEY, '') as string;
      if (raw.length === 0) {
        return this.createDefaultState();
      }
      const parsed: AppState = JSON.parse(raw) as AppState;
      if (parsed.papers === undefined) {
        return this.createDefaultState();
      }
      this.normalizeState(parsed);
      return parsed;
    } catch (error) {
      console.error('PaperTodo state parse failed: ' + String(error));
      try {
        const backup: string = this.store.getSync(BACKUP_KEY, '') as string;
        if (backup.length > 0) {
          const parsedBackup: AppState = JSON.parse(backup) as AppState;
          this.normalizeState(parsedBackup);
          return parsedBackup;
        }
      } catch (backupError) {
        console.error('PaperTodo backup parse failed: ' + String(backupError));
      }
      return this.createDefaultState();
    }
  }

  private static saveStateInternal(state: AppState, makeBackup: boolean): void {
    if (this.store === null) {
      return;
    }
    try {
      if (makeBackup) {
        const current: string = this.store.getSync(STATE_KEY, '') as string;
        if (current.length > 0) {
          this.store.putSync(BACKUP_KEY, current);
        }
      }
      this.store.putSync(STATE_KEY, JSON.stringify(state));
      this.store.flushSync();
    } catch (error) {
      console.error('PaperTodo state save failed: ' + String(error));
    }
  }

  private static createDefaultState(): AppState {
    const now: number = Date.now();
    const firstPaper: PaperData = {
      id: this.nextId('paper'),
      type: PAPER_TYPE_TODO,
      title: '',
      x: 120,
      y: 120,
      width: TODO_DEFAULT_WIDTH,
      height: TODO_DEFAULT_HEIGHT,
      isVisible: true,
      alwaysOnTop: false,
      isCollapsed: false,
      items: [this.createItem('', 0)],
      content: '',
      createdAt: now,
      updatedAt: now
    };
    return {
      papers: [firstPaper],
      theme: THEME_SYSTEM,
      markdownRenderMode: MARKDOWN_ENHANCED,
      useCapsuleMode: true,
      useDeepCapsuleMode: true
    };
  }

  private static normalizeState(state: AppState): void {
    if (state.theme !== THEME_LIGHT && state.theme !== THEME_DARK && state.theme !== THEME_SYSTEM) {
      state.theme = THEME_SYSTEM;
    }
    if (state.markdownRenderMode !== MARKDOWN_OFF &&
      state.markdownRenderMode !== MARKDOWN_BASIC &&
      state.markdownRenderMode !== MARKDOWN_ENHANCED) {
      state.markdownRenderMode = MARKDOWN_ENHANCED;
    }
    for (let i: number = 0; i < state.papers.length; i++) {
      const paper: PaperData = state.papers[i];
      if (paper.type !== PAPER_TYPE_NOTE) {
        paper.type = PAPER_TYPE_TODO;
      }
      if (paper.items === undefined) {
        paper.items = [];
      }
      if (paper.createdAt === undefined) {
        paper.createdAt = Date.now();
      }
      if (paper.updatedAt === undefined) {
        paper.updatedAt = paper.createdAt;
      }
    }
  }

  private static publishSettings(state: AppState): void {
    AppStorage.setOrCreate<string>('theme', state.theme);
    AppStorage.setOrCreate<string>('markdownRenderMode', state.markdownRenderMode);
    AppStorage.setOrCreate<boolean>('useCapsuleMode', state.useCapsuleMode);
    AppStorage.setOrCreate<boolean>('useDeepCapsuleMode', state.useDeepCapsuleMode);
  }

  private static nextId(prefix: string): string {
    this.sequence += 1;
    return prefix + '_' + Date.now().toString(36) + '_' + this.sequence.toString(36);
  }

  private static createItem(text: string, order: number): PaperItem {
    return {
      id: this.nextId('item'),
      text: text,
      done: false,
      order: order
    };
  }
}
