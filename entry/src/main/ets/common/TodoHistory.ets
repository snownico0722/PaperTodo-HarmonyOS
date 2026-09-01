import { PaperItem } from './Models';

const HISTORY_LIMIT: number = 100;
const TEXT_COALESCE_MS: number = 800;

export function cloneTodoItems(items: PaperItem[]): PaperItem[] {
  const result: PaperItem[] = [];
  for (let i: number = 0; i < items.length; i++) {
    const source: PaperItem = items[i];
    result.push({
      id: source.id,
      text: source.text,
      done: source.done,
      order: i,
      linkedPaperId: source.linkedPaperId,
      quickLaunchUri: source.quickLaunchUri,
      quickLaunchName: source.quickLaunchName,
      quickLaunchKind: source.quickLaunchKind
    });
  }
  return result;
}

export class TodoHistory {
  private undoStack: PaperItem[][] = [];
  private redoStack: PaperItem[][] = [];
  private lastCoalesceKey: string = '';
  private lastCaptureAt: number = 0;

  capture(items: PaperItem[], coalesceKey: string = ''): void {
    const now: number = Date.now();
    const coalesced: boolean = coalesceKey.length > 0 &&
      coalesceKey === this.lastCoalesceKey &&
      now - this.lastCaptureAt <= TEXT_COALESCE_MS;
    if (!coalesced) {
      this.undoStack.push(cloneTodoItems(items));
      if (this.undoStack.length > HISTORY_LIMIT) {
        this.undoStack.shift();
      }
    }
    this.redoStack = [];
    this.lastCoalesceKey = coalesceKey;
    this.lastCaptureAt = now;
  }

  undo(current: PaperItem[]): PaperItem[] | null {
    if (this.undoStack.length === 0) {
      return null;
    }
    const snapshot: PaperItem[] | undefined = this.undoStack.pop();
    if (snapshot === undefined) {
      return null;
    }
    this.redoStack.push(cloneTodoItems(current));
    this.breakCoalescing();
    return cloneTodoItems(snapshot);
  }

  redo(current: PaperItem[]): PaperItem[] | null {
    if (this.redoStack.length === 0) {
      return null;
    }
    const snapshot: PaperItem[] | undefined = this.redoStack.pop();
    if (snapshot === undefined) {
      return null;
    }
    this.undoStack.push(cloneTodoItems(current));
    this.breakCoalescing();
    return cloneTodoItems(snapshot);
  }

  canUndo(): boolean {
    return this.undoStack.length > 0;
  }

  canRedo(): boolean {
    return this.redoStack.length > 0;
  }

  reset(): void {
    this.undoStack = [];
    this.redoStack = [];
    this.breakCoalescing();
  }

  breakCoalescing(): void {
    this.lastCoalesceKey = '';
    this.lastCaptureAt = 0;
  }
}
