import {
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  PaperData,
  PaperItem
} from './Models';

export const PAPER_ACTION_HIDE: string = 'hide';
export const PAPER_ACTION_COLLAPSE: string = 'collapse';
export const PAPER_ACTION_EXPAND: string = 'expand';
export const PAPER_ACTION_FOCUS: string = 'focus';
export const MASTER_ACTION_RETRACT: string = 'retract';
export const MASTER_ACTION_RELEASE: string = 'release';

// PaperTodo deliberately gives the platform close gesture a different meaning
// from the paper toolbar's shape control. Alt+F4 / system close always hides.
export function resolveSystemCloseAction(): string {
  return PAPER_ACTION_HIDE;
}

export function resolveTopBarDismissAction(capsuleAvailable: boolean): string {
  return capsuleAvailable ? PAPER_ACTION_COLLAPSE : PAPER_ACTION_HIDE;
}

export function resolveEdgeActivateAction(isCollapsed: boolean,
  collapseExpandedOnSecondClick: boolean): string {
  if (isCollapsed) {
    return PAPER_ACTION_EXPAND;
  }
  return collapseExpandedOnSecondClick ? PAPER_ACTION_COLLAPSE : PAPER_ACTION_FOCUS;
}

export function resolveLinkedPaperAction(targetVisible: boolean, targetCollapsed: boolean,
  collapseExpandedOnSecondClick: boolean): string {
  if (!targetVisible || targetCollapsed) {
    return PAPER_ACTION_EXPAND;
  }
  return collapseExpandedOnSecondClick ? PAPER_ACTION_COLLAPSE : PAPER_ACTION_FOCUS;
}

export function resolveMasterToggleAction(currentlyRetracted: boolean): string {
  return currentlyRetracted ? MASTER_ACTION_RELEASE : MASTER_ACTION_RETRACT;
}

function isTodoItemEmpty(item: PaperItem): boolean {
  return item.text.trim().length === 0 && !item.done && item.linkedPaperId === undefined &&
    item.quickLaunchUri === undefined;
}

// Deletion follows the paper's actual payload, not its generated/default title.
// Unknown paper kinds deliberately count as non-empty so a future schema cannot
// be deleted without confirmation by an older client.
export function isPaperEmpty(paper: PaperData): boolean {
  if (paper.type === PAPER_TYPE_NOTE) {
    return paper.content.trim().length === 0;
  }
  if (paper.type !== PAPER_TYPE_TODO) {
    return false;
  }
  for (let i: number = 0; i < paper.items.length; i++) {
    if (!isTodoItemEmpty(paper.items[i])) {
      return false;
    }
  }
  return true;
}
