import { describe, expect, it } from '@ohos/hypium';
import { PaperItem } from '../main/ets/common/Models';
import { cloneTodoItems, TodoHistory } from '../main/ets/common/TodoHistory';

function item(id: string, text: string, done: boolean, order: number, linkedPaperId?: string): PaperItem {
  if (linkedPaperId === undefined) {
    return { id: id, text: text, done: done, order: order };
  }
  return { id: id, text: text, done: done, order: order, linkedPaperId: linkedPaperId };
}

export default function todoHistoryTest(): void {
  describe('TodoHistoryTest', () => {
    it('coalescesRapidCapturesWithTheSameKey', 0, () => {
      const history: TodoHistory = new TodoHistory();
      const beforeTyping: PaperItem[] = [item('a', 'A', false, 0, 'paper-original')];
      const afterFirstCharacter: PaperItem[] = [item('a', 'AB', false, 0, 'paper-original')];
      const afterSecondCharacter: PaperItem[] = [item('a', 'ABC', false, 0, 'paper-original')];

      history.capture(beforeTyping, 'text:a');
      history.capture(afterFirstCharacter, 'text:a');

      const restored: PaperItem[] | null = history.undo(afterSecondCharacter);
      expect(restored === null).assertFalse();
      if (restored === null) {
        return;
      }
      expect(restored[0].text).assertEqual('A');
      expect(restored[0].linkedPaperId).assertEqual('paper-original');
      expect(history.canUndo()).assertFalse();
      expect(history.canRedo()).assertTrue();
    });

    it('keepsDifferentCaptureKeysAsSeparateUndoSteps', 0, () => {
      const history: TodoHistory = new TodoHistory();
      const first: PaperItem[] = [item('a', 'A', false, 0)];
      const second: PaperItem[] = [item('a', 'AB', false, 0)];
      const current: PaperItem[] = [item('a', 'ABC', false, 0)];

      history.capture(first, 'text:a');
      history.capture(second, 'text:b');

      const undoOnce: PaperItem[] | null = history.undo(current);
      expect(undoOnce === null).assertFalse();
      if (undoOnce === null) {
        return;
      }
      expect(undoOnce[0].text).assertEqual('AB');

      const undoTwice: PaperItem[] | null = history.undo(undoOnce);
      expect(undoTwice === null).assertFalse();
      if (undoTwice === null) {
        return;
      }
      expect(undoTwice[0].text).assertEqual('A');
    });

    it('breakCoalescingStartsANewUndoStep', 0, () => {
      const history: TodoHistory = new TodoHistory();
      const first: PaperItem[] = [item('a', 'A', false, 0)];
      const second: PaperItem[] = [item('a', 'AB', false, 0)];
      const current: PaperItem[] = [item('a', 'ABC', false, 0)];

      history.capture(first, 'text:a');
      history.breakCoalescing();
      history.capture(second, 'text:a');

      const undoOnce: PaperItem[] | null = history.undo(current);
      expect(undoOnce === null).assertFalse();
      if (undoOnce === null) {
        return;
      }
      expect(undoOnce[0].text).assertEqual('AB');

      const undoTwice: PaperItem[] | null = history.undo(undoOnce);
      expect(undoTwice === null).assertFalse();
      if (undoTwice === null) {
        return;
      }
      expect(undoTwice[0].text).assertEqual('A');
    });

    it('undoAndRedoRestoreWholeSnapshotsIncludingLinks', 0, () => {
      const history: TodoHistory = new TodoHistory();
      const before: PaperItem[] = [
        item('a', 'First', false, 7, 'paper-one'),
        item('b', 'Second', true, 2, 'paper-two')
      ];
      const after: PaperItem[] = [
        item('b', 'Second changed', false, 0, 'paper-three'),
        item('a', 'First changed', true, 1)
      ];

      history.capture(before);
      const undone: PaperItem[] | null = history.undo(after);
      expect(undone === null).assertFalse();
      if (undone === null) {
        return;
      }
      expect(undone.length).assertEqual(2);
      expect(undone[0].id).assertEqual('a');
      expect(undone[0].linkedPaperId).assertEqual('paper-one');
      expect(undone[0].order).assertEqual(0);
      expect(undone[1].id).assertEqual('b');
      expect(undone[1].linkedPaperId).assertEqual('paper-two');
      expect(undone[1].order).assertEqual(1);

      const redone: PaperItem[] | null = history.redo(undone);
      expect(redone === null).assertFalse();
      if (redone === null) {
        return;
      }
      expect(redone[0].id).assertEqual('b');
      expect(redone[0].text).assertEqual('Second changed');
      expect(redone[0].linkedPaperId).assertEqual('paper-three');
      expect(redone[1].id).assertEqual('a');
      expect(redone[1].linkedPaperId === undefined).assertTrue();
      expect(history.canUndo()).assertTrue();
      expect(history.canRedo()).assertFalse();
    });

    it('capturesIndependentCopiesAndPreservesLinkedPaperIds', 0, () => {
      const history: TodoHistory = new TodoHistory();
      const source: PaperItem[] = [item('a', 'Original', false, 8, 'paper-link')];
      history.capture(source);

      source[0].text = 'Mutated after capture';
      source[0].linkedPaperId = 'different-link';
      const restored: PaperItem[] | null = history.undo(source);

      expect(restored === null).assertFalse();
      if (restored === null) {
        return;
      }
      expect(restored[0].text).assertEqual('Original');
      expect(restored[0].linkedPaperId).assertEqual('paper-link');
      expect(restored[0].order).assertEqual(0);
    });

    it('newCaptureClearsRedoAndResetClearsBothStacks', 0, () => {
      const history: TodoHistory = new TodoHistory();
      const before: PaperItem[] = [item('a', 'Before', false, 0)];
      const after: PaperItem[] = [item('a', 'After', false, 0)];

      history.capture(before);
      const restored: PaperItem[] | null = history.undo(after);
      expect(restored === null).assertFalse();
      expect(history.canRedo()).assertTrue();
      history.capture(before);
      expect(history.canRedo()).assertFalse();

      history.reset();
      expect(history.canUndo()).assertFalse();
      expect(history.canRedo()).assertFalse();
      expect(history.undo(before) === null).assertTrue();
      expect(history.redo(before) === null).assertTrue();
    });

    it('cloneTodoItemsCopiesLinksAndNormalizesOrder', 0, () => {
      const source: PaperItem[] = [
        item('a', 'A', false, 20, 'paper-a'),
        item('b', 'B', true, 10)
      ];
      const cloned: PaperItem[] = cloneTodoItems(source);

      expect(cloned === source).assertFalse();
      expect(cloned[0] === source[0]).assertFalse();
      expect(cloned[0].linkedPaperId).assertEqual('paper-a');
      expect(cloned[0].order).assertEqual(0);
      expect(cloned[1].linkedPaperId === undefined).assertTrue();
      expect(cloned[1].order).assertEqual(1);
    });

    it('capturesIndependentQuickLaunchSnapshotsForUndoAndRedo', 0, () => {
      const history: TodoHistory = new TodoHistory();
      const before: PaperItem[] = [{
        id: 'quick',
        text: 'Open specification',
        done: false,
        order: 9,
        quickLaunchUri: 'file://before/specification.md',
        quickLaunchName: 'Specification',
        quickLaunchKind: 'file'
      }];
      const after: PaperItem[] = [{
        id: 'quick',
        text: 'Open assets',
        done: true,
        order: 4,
        quickLaunchUri: 'file://after/assets',
        quickLaunchName: 'Assets',
        quickLaunchKind: 'folder'
      }];

      history.capture(before);
      before[0].quickLaunchUri = 'file://mutated/source';
      before[0].quickLaunchName = 'Mutated source';
      before[0].quickLaunchKind = 'folder';

      const undone: PaperItem[] | null = history.undo(after);
      expect(undone === null).assertFalse();
      if (undone === null) {
        return;
      }
      expect(undone[0].quickLaunchUri).assertEqual('file://before/specification.md');
      expect(undone[0].quickLaunchName).assertEqual('Specification');
      expect(undone[0].quickLaunchKind).assertEqual('file');
      expect(undone[0].order).assertEqual(0);

      undone[0].quickLaunchUri = 'file://mutated/undo-result';
      undone[0].quickLaunchName = 'Mutated undo result';
      const redone: PaperItem[] | null = history.redo(undone);
      expect(redone === null).assertFalse();
      if (redone === null) {
        return;
      }
      expect(redone[0].quickLaunchUri).assertEqual('file://after/assets');
      expect(redone[0].quickLaunchName).assertEqual('Assets');
      expect(redone[0].quickLaunchKind).assertEqual('folder');
      expect(redone[0].order).assertEqual(0);
    });

    it('cloneTodoItemsPreservesAndDetachesQuickLaunchFields', 0, () => {
      const source: PaperItem[] = [{
        id: 'quick',
        text: 'Open file',
        done: false,
        order: 3,
        quickLaunchUri: 'file://document',
        quickLaunchName: 'Document',
        quickLaunchKind: 'file'
      }];
      const cloned: PaperItem[] = cloneTodoItems(source);

      source[0].quickLaunchUri = 'file://changed';
      source[0].quickLaunchName = 'Changed';
      source[0].quickLaunchKind = 'folder';
      expect(cloned[0].quickLaunchUri).assertEqual('file://document');
      expect(cloned[0].quickLaunchName).assertEqual('Document');
      expect(cloned[0].quickLaunchKind).assertEqual('file');
      expect(cloned[0].order).assertEqual(0);
    });

    it('startsANewStepAfterTheTextCoalescingWindowExpires', 0, () => {
      const history: TodoHistory = new TodoHistory();
      const first: PaperItem[] = [item('a', 'A', false, 0)];
      const second: PaperItem[] = [item('a', 'AB', false, 0)];
      const current: PaperItem[] = [item('a', 'ABC', false, 0)];

      history.capture(first, 'text:a');
      const waitStartedAt: number = Date.now();
      while (Date.now() - waitStartedAt <= 820) {
      }
      history.capture(second, 'text:a');

      const undoOnce: PaperItem[] | null = history.undo(current);
      expect(undoOnce === null).assertFalse();
      if (undoOnce === null) {
        return;
      }
      expect(undoOnce[0].text).assertEqual('AB');
      const undoTwice: PaperItem[] | null = history.undo(undoOnce);
      expect(undoTwice === null).assertFalse();
      if (undoTwice === null) {
        return;
      }
      expect(undoTwice[0].text).assertEqual('A');
    });

    it('keepsOnlyTheNewestOneHundredUndoSnapshots', 0, () => {
      const history: TodoHistory = new TodoHistory();
      for (let captureIndex: number = 0; captureIndex < 105; captureIndex++) {
        history.capture([item('a', captureIndex.toString(), false, 0)]);
      }

      let current: PaperItem[] = [item('a', 'current', false, 0)];
      let undoCount: number = 0;
      let oldestRestoredText: string = '';
      for (let undoIndex: number = 0; undoIndex < 101; undoIndex++) {
        const restored: PaperItem[] | null = history.undo(current);
        if (restored === null) {
          break;
        }
        current = restored;
        oldestRestoredText = restored[0].text;
        undoCount += 1;
      }

      expect(undoCount).assertEqual(100);
      expect(oldestRestoredText).assertEqual('5');
      expect(history.canUndo()).assertFalse();
      expect(history.undo(current) === null).assertTrue();
    });

    it('undoRestoresQuickLaunchFieldsAndRedoRestoresTheirRemoval', 0, () => {
      const history: TodoHistory = new TodoHistory();
      const linked: PaperItem[] = [{
        id: 'quick',
        text: 'Open plan',
        done: false,
        order: 0,
        quickLaunchUri: 'file://plan.md',
        quickLaunchName: 'Plan',
        quickLaunchKind: 'file'
      }];
      const unlinked: PaperItem[] = [item('quick', 'Open plan', false, 0)];

      history.capture(linked);
      const restoredLink: PaperItem[] | null = history.undo(unlinked);
      expect(restoredLink === null).assertFalse();
      if (restoredLink === null) {
        return;
      }
      expect(restoredLink[0].quickLaunchUri).assertEqual('file://plan.md');
      expect(restoredLink[0].quickLaunchName).assertEqual('Plan');
      expect(restoredLink[0].quickLaunchKind).assertEqual('file');

      const restoredRemoval: PaperItem[] | null = history.redo(restoredLink);
      expect(restoredRemoval === null).assertFalse();
      if (restoredRemoval === null) {
        return;
      }
      expect(restoredRemoval[0].quickLaunchUri === undefined).assertTrue();
      expect(restoredRemoval[0].quickLaunchName === undefined).assertTrue();
      expect(restoredRemoval[0].quickLaunchKind === undefined).assertTrue();
    });
  });
}
