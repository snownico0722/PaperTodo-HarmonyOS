export const SCHEMA_VERSION: number = 4;

export const PAPER_TYPE_TODO: string = 'todo';
export const PAPER_TYPE_NOTE: string = 'note';

export const THEME_SYSTEM: string = 'system';
export const THEME_LIGHT: string = 'light';
export const THEME_DARK: string = 'dark';

export const MARKDOWN_OFF: string = 'off';
export const MARKDOWN_BASIC: string = 'basic';
export const MARKDOWN_ENHANCED: string = 'enhanced';

export const TODO_VISUAL_SMALL: string = 'small';
export const TODO_VISUAL_MEDIUM: string = 'medium';
export const TODO_VISUAL_LARGE: string = 'large';
export const TODO_VISUAL_XLARGE: string = 'xlarge';

export const EDGE_SIDE_RIGHT: string = 'right';
export const DEFAULT_DISPLAY_ID: string = 'default';

// Paper / floating capsule geometry is persisted in vp. Convert to physical px only at Window API boundaries.
export const PAPER_MIN_WIDTH: number = 220;
export const PAPER_MIN_HEIGHT: number = 160;
export const TODO_DEFAULT_WIDTH: number = 280;
export const TODO_DEFAULT_HEIGHT: number = 340;
export const NOTE_DEFAULT_WIDTH: number = 320;
export const NOTE_DEFAULT_HEIGHT: number = 360;
export const CAPSULE_WIDTH: number = 108;
export const CAPSULE_HEIGHT: number = 46;
export const CAPSULE_GAP_DEFAULT: number = 4;

export const MAX_PAPERS: number = 100;
export const TITLE_MAX_LENGTH: number = 20;
export const TODO_PASTE_MAX_ITEMS: number = 200;
export const TODO_ITEM_MAX_LENGTH: number = 2000;
export const TODO_HISTORY_LIMIT: number = 100;
export const NOTE_MAX_LENGTH: number = 200000;

export interface PaperItem {
  id: string;
  text: string;
  done: boolean;
  order: number;

  // v2.x: a todo item may point at one note paper. Undefined means unlinked.
  linkedNoteId?: string;
}

export interface PaperData {
  id: string;
  type: string;
  title: string;

  // Logical geometry in vp.
  expandedX: number;
  expandedY: number;
  expandedWidth: number;
  expandedHeight: number;

  // Floating capsule logical position in vp. Edge-docked X/Y are derived, not persisted truth.
  capsuleX: number;
  capsuleY: number;
  edgeSide: string;
  edgeOrder: number;
  edgeDisplayId: string;

  isVisible: boolean;
  alwaysOnTop: boolean;
  isCollapsed: boolean;
  items: PaperItem[];
  content: string;
  createdAt: number;
  updatedAt: number;

  // v1 migration fields. New code never writes these values.
  x?: number;
  y?: number;
  width?: number;
  height?: number;
}

export interface AppState {
  schemaVersion: number;
  initialized: boolean;
  papers: PaperData[];
  theme: string;
  markdownRenderMode: string;
  useCapsuleMode: boolean;
  useDeepCapsuleMode: boolean;
  todoVisualSize: string;
  autoBottomCompleted: boolean;
  autoClearCompletedTodos: boolean;
  enableTodoNoteLinks: boolean;
  showLinkedNoteName: boolean;
  capsuleGap: number;
}
