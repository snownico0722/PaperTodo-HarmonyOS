export const SCHEMA_VERSION: number = 4;

export const PAPER_TYPE_TODO: string = 'todo';
export const PAPER_TYPE_NOTE: string = 'note';

export const THEME_SYSTEM: string = 'system';
export const THEME_LIGHT: string = 'light';
export const THEME_DARK: string = 'dark';

export const COLOR_SCHEME_WARM: string = 'warm';
export const COLOR_SCHEME_INK: string = 'ink';
export const COLOR_SCHEME_FOREST: string = 'forest';
export const COLOR_SCHEME_SUNSET: string = 'sunset';

export const MARKDOWN_OFF: string = 'off';
export const MARKDOWN_BASIC: string = 'basic';
export const MARKDOWN_ENHANCED: string = 'enhanced';

export const TODO_VISUAL_SMALL: string = 'small';
export const TODO_VISUAL_MEDIUM: string = 'medium';
export const TODO_VISUAL_LARGE: string = 'large';
export const TODO_VISUAL_XLARGE: string = 'xlarge';

export const VISUAL_TEXT_SMALL: string = 'small';
export const VISUAL_TEXT_MEDIUM: string = 'medium';
export const VISUAL_TEXT_LARGE: string = 'large';

export const RESIZE_GRIP_STANDARD: string = 'standard';
export const RESIZE_GRIP_SOFT: string = 'soft';
export const RESIZE_GRIP_HIDDEN: string = 'hidden';

export const UI_LANGUAGE_SYSTEM: string = 'system';
export const UI_LANGUAGE_ZH_CN: string = 'zh-CN';
export const UI_LANGUAGE_EN: string = 'en';
export const UI_LANGUAGE_JA: string = 'ja';
export const UI_LANGUAGE_KO: string = 'ko';

export const QUICK_LAUNCH_FILE: string = 'file';
export const QUICK_LAUNCH_FOLDER: string = 'folder';

export const EDGE_SIDE_RIGHT: string = 'right';
export const DEFAULT_DISPLAY_ID: string = 'default';

export const PAPER_MIN_WIDTH: number = 180;
export const PAPER_MIN_HEIGHT: number = 160;
export const TODO_DEFAULT_WIDTH: number = 280;
export const TODO_DEFAULT_HEIGHT: number = 340;
export const NOTE_DEFAULT_WIDTH: number = 320;
export const NOTE_DEFAULT_HEIGHT: number = 360;
export const CAPSULE_WIDTH: number = 108;
export const CAPSULE_MIN_WIDTH: number = 76;
export const CAPSULE_MAX_WIDTH: number = 280;
export const CAPSULE_HEIGHT: number = 46;
export const CAPSULE_CLOSE_WIDTH: number = 28;
export const CAPSULE_GAP_DEFAULT: number = 4;
export const EXPANDED_EDGE_INSET: number = 36;

export const MAX_PAPERS: number = 100;
export const TITLE_MAX_LENGTH: number = 20;
export const TODO_PASTE_MAX_ITEMS: number = 200;
export const TODO_ITEM_MAX_LENGTH: number = 2000;
export const NOTE_MAX_LENGTH: number = 200000;
export const QUICK_LAUNCH_URI_MAX_LENGTH: number = 8192;
export const QUICK_LAUNCH_NAME_MAX_LENGTH: number = 256;
export const NOTE_IMAGE_INPUT_MAX_BYTES: number = 32 * 1024 * 1024;
export const NOTE_IMAGE_FILE_MAX_BYTES: number = 8 * 1024 * 1024;
export const NOTE_IMAGE_TOTAL_MAX_BYTES: number = 120 * 1024 * 1024;
export const NOTE_IMAGE_DIMENSION_MAX: number = 4096;
export const NOTE_IMAGE_COMPRESS_DIMENSION: number = 2048;

export interface PaperItem {
  id: string;
  text: string;
  done: boolean;
  order: number;
  linkedPaperId?: string;
  quickLaunchUri?: string;
  quickLaunchName?: string;
  quickLaunchKind?: string;
}

export interface PaperData {
  id: string;
  type: string;
  title: string;

  expandedX: number;
  expandedY: number;
  expandedWidth: number;
  expandedHeight: number;

  capsuleX: number;
  capsuleY: number;
  capsuleWidth: number;
  edgeSide: string;
  edgeOrder: number;
  edgeDisplayId: string;

  isVisible: boolean;
  alwaysOnTop: boolean;
  isCollapsed: boolean;
  textZoom: number;
  items: PaperItem[];
  content: string;
  createdAt: number;
  updatedAt: number;

  // v1 迁移字段。新代码不再写入这些值。
  x?: number;
  y?: number;
  width?: number;
  height?: number;
}

export interface NoteImageAsset {
  id: string;
  noteId: string;
  fileName: string;
  mimeType: string;
  width: number;
  height: number;
  byteLength: number;
  createdAt: number;
}

export interface AppState {
  schemaVersion: number;
  initialized: boolean;
  papers: PaperData[];
  noteImages: NoteImageAsset[];
  autoCompressLargeImages: boolean;
  globalHotkeysEnabled: boolean;
  uiLanguage: string;
  theme: string;
  colorScheme: string;
  markdownRenderMode: string;
  useCapsuleMode: boolean;
  useDeepCapsuleMode: boolean;
  todoVisualSize: string;
  autoClearCompletedTodos: boolean;
  autoBottomCompleted: boolean;
  capsuleGap: number;
  enableAnimations: boolean;
  rememberEdgeExpandedPosition: boolean;
  collapseExpandedEdgeCapsuleOnClick: boolean;
  hideEdgeCapsuleCloseButtonOnHover: boolean;
  edgeCapsuleTitleCharacterLimit: number;
  enablePaperLinks: boolean;
  overallFontScale: number;
  noteTextSize: string;
  noteTextBold: boolean;
  todoTextBold: boolean;
  titleTextSize: string;
  titleTextBold: boolean;
  capsuleTextSize: string;
  capsuleTextBold: boolean;
  resizeGripMode: string;
  showTopBarNewTodoButton: boolean;
  showTopBarNewNoteButton: boolean;
  showTopBarExternalOpenButton: boolean;
}
