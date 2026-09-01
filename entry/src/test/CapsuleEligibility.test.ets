import { describe, expect, it } from '@ohos/hypium';
import { AppState, PAPER_TYPE_NOTE, PAPER_TYPE_TODO, PaperData } from '../main/ets/common/Models';
import { PaperStore } from '../main/ets/common/PaperStore';

function queueContains(paperId: string): boolean {
  const queue: PaperData[] = PaperStore.listEdgeCapsulePapers();
  for (let i: number = 0; i < queue.length; i++) {
    if (queue[i].id === paperId) {
      return true;
    }
  }
  return false;
}

export default function capsuleEligibilityTest(): void {
  describe('CapsuleEligibilityTest', () => {
    it('excludesOnlyLinkedPapersWhenBothLinkSettingsAreEnabled', 0, () => {
      const previous: AppState = PaperStore.loadState();
      const previousCapsuleMode: boolean = previous.useCapsuleMode;
      const previousDeepCapsuleMode: boolean = previous.useDeepCapsuleMode;
      const previousExpandedCapsules: boolean = previous.showDeepCapsuleWhileExpanded;
      const previousPaperLinks: boolean = previous.enablePaperLinks;
      const previousHideLinked: boolean = previous.hideLinkedPapersFromCapsules;
      let sourceId: string = '';
      let targetId: string = '';
      try {
        PaperStore.setCapsuleMode(true);
        PaperStore.setDeepCapsuleMode(true);
        PaperStore.setShowDeepCapsuleWhileExpanded(true);
        PaperStore.setPaperLinksEnabled(true);
        PaperStore.setHideLinkedPapersFromCapsules(false);

        const source: PaperData | null = PaperStore.createPaper(PAPER_TYPE_TODO);
        const target: PaperData | null = PaperStore.createPaper(PAPER_TYPE_NOTE);
        expect(source === null).assertFalse();
        expect(target === null).assertFalse();
        if (source === null || target === null) {
          return;
        }
        sourceId = source.id;
        targetId = target.id;
        expect(PaperStore.setTodoLink(source.id, source.items[0].id, target.id)).assertTrue();
        expect(PaperStore.isPaperLinkedToAnyTodo(target.id)).assertTrue();
        expect(PaperStore.canPaperDisplayAsCapsule(target)).assertTrue();

        PaperStore.setPaperCollapsed(target.id, true);
        expect(target.isCollapsed).assertTrue();
        expect(queueContains(target.id)).assertTrue();

        PaperStore.setHideLinkedPapersFromCapsules(true);
        expect(PaperStore.canPaperDisplayAsCapsule(target)).assertFalse();
        expect(target.isCollapsed).assertFalse();
        expect(queueContains(target.id)).assertFalse();

        PaperStore.setPaperCollapsed(target.id, true);
        expect(target.isCollapsed).assertFalse();

        PaperStore.setPaperLinksEnabled(false);
        expect(PaperStore.canPaperDisplayAsCapsule(target)).assertTrue();
        expect(queueContains(target.id)).assertTrue();

        PaperStore.setPaperLinksEnabled(true);
        expect(PaperStore.canPaperDisplayAsCapsule(target)).assertFalse();
        expect(PaperStore.setTodoLink(source.id, source.items[0].id, '')).assertTrue();
        expect(PaperStore.isPaperLinkedToAnyTodo(target.id)).assertFalse();
        expect(PaperStore.canPaperDisplayAsCapsule(target)).assertTrue();
        expect(queueContains(target.id)).assertTrue();
      } finally {
        if (sourceId.length > 0) {
          PaperStore.deletePaper(sourceId);
        }
        if (targetId.length > 0) {
          PaperStore.deletePaper(targetId);
        }
        PaperStore.setHideLinkedPapersFromCapsules(previousHideLinked);
        PaperStore.setPaperLinksEnabled(previousPaperLinks);
        PaperStore.setShowDeepCapsuleWhileExpanded(previousExpandedCapsules);
        if (previousCapsuleMode) {
          PaperStore.setCapsuleMode(true);
          PaperStore.setDeepCapsuleMode(previousDeepCapsuleMode);
        } else {
          PaperStore.setCapsuleMode(false);
        }
      }
    });
  });
}
