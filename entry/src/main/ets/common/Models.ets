export const PAPER_TYPE_TODO: string = 'todo';
export const PAPER_TYPE_NOTE: string = 'note';

export const THEME_SYSTEM: string = 'system';
export const THEME_LIGHT: string = 'light';
export const THEME_DARK: string = 'dark';

export const MARKDOWN_OFF: string = 'off';
export const MARKDOWN_BASIC: string = 'basic';
export const MARKDOWN_ENHANCED: string = 'enhanced';

export const PAPER_MIN_WIDTH: number = 220;
export const PAPER_MIN_HEIGHT: number = 160;
export const TODO_DEFAULT_WIDTH: number = 280;
export const TODO_DEFAULT_HEIGHT: number = 340;
export const NOTE_DEFAULT_WIDTH: number = 320;
export const NOTE_DEFAULT_HEIGHT: number = 360;
export const CAPSULE_WIDTH: number = 108;
export const CAPSULE_HEIGHT: number = 46;

export interface PaperItem {
  id: string;
  text: string;
  done: boolean;
  order: number;
}

export interface PaperData {
  id: string;
  type: string;
  title: string;
  x: number;
  y: number;
  width: number;
  height: number;
  isVisible: boolean;
  alwaysOnTop: boolean;
  isCollapsed: boolean;
  items: PaperItem[];
  content: string;
  createdAt: number;
  updatedAt: number;
}

export interface AppState {
  papers: PaperData[];
  theme: string;
  markdownRenderMode: string;
  useCapsuleMode: boolean;
  useDeepCapsuleMode: boolean;
}
