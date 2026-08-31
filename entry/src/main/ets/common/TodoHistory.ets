import { PaperItem, TODO_HISTORY_LIMIT } from './Models';

export function cloneTodoItems(items: PaperItem[]): PaperItem[] {
  const result: PaperItem[] = [];
  for (let i: number = 0; i < items.length; i++) {
    const source: PaperItem = items[i];
    const copy: PaperItem = {
      id: source.id,
      text: source.text,
      done: source.done,
      order: source.order
    };
    if (source.linkedNoteId !== undefined) {
      copy.linkedNoteId = source.linkedNoteId;
    }
    result.push(copy);
  }
  return result;
}

export class TodoHistory {
  private undoStack: PaperItem[][] = [];
  private redoStack: PaperItem[][] = [];

  record(items: PaperItem[]): void {
    this.undoStack.push(cloneTodoItems(items));
    while (this.undoStack.length > TODO_HISTORY_LIMIT) {
      this.undoStack.shift();
    }
    this.redoStack = [];
  }

  undo(current: PaperItem[]): PaperItem[] | null {
    if (this.undoStack.length === 0) {
      return null;
    }
    const previous: PaperItem[] | undefined = this.undoStack.pop();
    if (previous === undefined) {
      return null;
    }
    this.redoStack.push(cloneTodoItems(current));
    return cloneTodoItems(previous);
  }

  redo(current: PaperItem[]): PaperItem[] | null {
    if (this.redoStack.length === 0) {
      return null;
    }
    const next: PaperItem[] | undefined = this.redoStack.pop();
    if (next === undefined) {
      return null;
    }
    this.undoStack.push(cloneTodoItems(current));
    return cloneTodoItems(next);
  }

  canUndo(): boolean {
    return this.undoStack.length > 0;
  }

  canRedo(): boolean {
    return this.redoStack.length > 0;
  }

  clear(): void {
    this.undoStack = [];
    this.redoStack = [];
  }
}
