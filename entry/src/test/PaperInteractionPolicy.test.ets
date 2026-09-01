import { describe, expect, it } from '@ohos/hypium';
import {
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  PaperData,
  PaperItem
} from '../main/ets/common/Models';
import {
  MASTER_ACTION_RELEASE,
  MASTER_ACTION_RETRACT,
  PAPER_ACTION_COLLAPSE,
  PAPER_ACTION_EXPAND,
  PAPER_ACTION_FOCUS,
  PAPER_ACTION_HIDE,
  isPaperEmpty,
  resolveEdgeActivateAction,
  resolveLinkedPaperAction,
  resolveMasterToggleAction,
  resolveSystemCloseAction,
  resolveTopBarDismissAction
} from '../main/ets/common/PaperInteractionPolicy';

function item(text: string, done: boolean = false): PaperItem {
  return {
    id: 'item',
    text: text,
    done: done,
    order: 0
  };
}

function paper(type: string, content: string = '', items: PaperItem[] = []): PaperData {
  return {
    id: 'paper',
    type: type,
    title: 'A title does not make a paper non-empty',
    expandedX: 0,
    expandedY: 0,
    expandedWidth: 280,
    expandedHeight: 340,
    capsuleX: 0,
    capsuleY: 0,
    capsuleWidth: 108,
    edgeSide: 'right',
    edgeOrder: 0,
    edgeDisplayId: 'default',
    isVisible: true,
    alwaysOnTop: false,
    isCollapsed: false,
    textZoom: 1,
    items: items,
    content: content,
    createdAt: 0,
    updatedAt: 0
  };
}

export default function paperInteractionPolicyTest(): void {
  describe('PaperInteractionPolicyTest', () => {
    it('alwaysHidesForThePlatformCloseGesture', 0, () => {
      expect(resolveSystemCloseAction()).assertEqual(PAPER_ACTION_HIDE);
    });

    it('usesTheToolbarShapeButtonForCollapseOnlyWhenAvailable', 0, () => {
      expect(resolveTopBarDismissAction(true)).assertEqual(PAPER_ACTION_COLLAPSE);
      expect(resolveTopBarDismissAction(false)).assertEqual(PAPER_ACTION_HIDE);
    });

    it('preservesTheExpandedEdgeTagActivationSemantics', 0, () => {
      expect(resolveEdgeActivateAction(true, false)).assertEqual(PAPER_ACTION_EXPAND);
      expect(resolveEdgeActivateAction(true, true)).assertEqual(PAPER_ACTION_EXPAND);
      expect(resolveEdgeActivateAction(false, false)).assertEqual(PAPER_ACTION_FOCUS);
      expect(resolveEdgeActivateAction(false, true)).assertEqual(PAPER_ACTION_COLLAPSE);
    });

    it('expandsLinkedPapersThatAreHiddenOrCollapsed', 0, () => {
      expect(resolveLinkedPaperAction(false, false, false)).assertEqual(PAPER_ACTION_EXPAND);
      expect(resolveLinkedPaperAction(false, false, true)).assertEqual(PAPER_ACTION_EXPAND);
      expect(resolveLinkedPaperAction(false, true, false)).assertEqual(PAPER_ACTION_EXPAND);
      expect(resolveLinkedPaperAction(false, true, true)).assertEqual(PAPER_ACTION_EXPAND);
      expect(resolveLinkedPaperAction(true, true, false)).assertEqual(PAPER_ACTION_EXPAND);
      expect(resolveLinkedPaperAction(true, true, true)).assertEqual(PAPER_ACTION_EXPAND);
    });

    it('focusesOrCollapsesAnAlreadyExpandedLinkedPaper', 0, () => {
      expect(resolveLinkedPaperAction(true, false, false)).assertEqual(PAPER_ACTION_FOCUS);
      expect(resolveLinkedPaperAction(true, false, true)).assertEqual(PAPER_ACTION_COLLAPSE);
    });

    it('onlyRetractsOrReleasesTheMasterQueue', 0, () => {
      expect(resolveMasterToggleAction(false)).assertEqual(MASTER_ACTION_RETRACT);
      expect(resolveMasterToggleAction(true)).assertEqual(MASTER_ACTION_RELEASE);
    });

    it('treatsOnlyWhitespaceNoteContentAsEmpty', 0, () => {
      expect(isPaperEmpty(paper(PAPER_TYPE_NOTE, ' \n\t '))).assertTrue();
      expect(isPaperEmpty(paper(PAPER_TYPE_NOTE, '  note  '))).assertFalse();
    });

    it('treatsBlankUnfinishedUnlinkedTodoItemsAsEmpty', 0, () => {
      expect(isPaperEmpty(paper(PAPER_TYPE_TODO))).assertTrue();
      expect(isPaperEmpty(paper(PAPER_TYPE_TODO, '', [item('  '), item('\n')]))).assertTrue();
      expect(isPaperEmpty(paper(PAPER_TYPE_TODO, '', [item('todo')]))).assertFalse();
      expect(isPaperEmpty(paper(PAPER_TYPE_TODO, '', [item('', true)]))).assertFalse();
    });

    it('keepsTodoAssociationsFromBeingDeletedAsEmpty', 0, () => {
      const linked: PaperItem = item('');
      linked.linkedPaperId = 'linked-paper';
      const quickLaunch: PaperItem = item('');
      quickLaunch.quickLaunchUri = 'file://target';
      expect(isPaperEmpty(paper(PAPER_TYPE_TODO, '', [linked]))).assertFalse();
      expect(isPaperEmpty(paper(PAPER_TYPE_TODO, '', [quickLaunch]))).assertFalse();
    });

    it('requiresConfirmationForUnknownPaperKinds', 0, () => {
      expect(isPaperEmpty(paper('future-paper-type'))).assertFalse();
    });
  });
}
