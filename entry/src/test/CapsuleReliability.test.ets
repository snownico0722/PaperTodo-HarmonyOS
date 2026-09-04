import { describe, expect, it } from '@ohos/hypium';
import { CapsuleRuntime } from '../main/ets/common/CapsuleRuntime';
import { capsuleViewport } from '../main/ets/common/CapsuleViewport';

export default function capsuleReliabilityTest(): void {
  describe('CapsuleReliabilityTest', () => {
    it('requiresParentAndCurrentLayoutAcknowledgement', 0, () => {
      CapsuleRuntime.retry();
      const request: number = CapsuleRuntime.request();
      CapsuleRuntime.begin('test-ready');
      expect(CapsuleRuntime.confirm('test-ready', request)).assertFalse();
      CapsuleRuntime.parentPrepared('test-ready');
      expect(CapsuleRuntime.confirm('test-ready', request)).assertTrue();
      expect(CapsuleRuntime.isReady()).assertTrue();
      CapsuleRuntime.request();
      expect(CapsuleRuntime.isReady()).assertFalse();
      CapsuleRuntime.end('test-ready');
    });

    it('ignoresStaleOwnersAndLateCompletionAfterFailure', 0, () => {
      CapsuleRuntime.retry();
      const request: number = CapsuleRuntime.request();
      CapsuleRuntime.begin('test-new');
      CapsuleRuntime.parentPrepared('test-new');
      CapsuleRuntime.end('test-old');
      expect(CapsuleRuntime.isOwner('test-new')).assertTrue();
      expect(CapsuleRuntime.confirm('test-old', request)).assertFalse();
      CapsuleRuntime.fail('test-new', 'injected mask failure');
      expect(CapsuleRuntime.confirm('test-new', request)).assertFalse();
      CapsuleRuntime.end('test-new');
      CapsuleRuntime.retry();
    });

    it('invalidatesCancelledCollapseIntents', 0, () => {
      const first: number = CapsuleRuntime.stageCollapse('test-paper');
      const second: number = CapsuleRuntime.stageCollapse('test-paper');
      expect(CapsuleRuntime.ownsCollapse('test-paper', first)).assertFalse();
      expect(CapsuleRuntime.ownsCollapse('test-paper', second)).assertTrue();
      CapsuleRuntime.cancelCollapse('test-paper');
      expect(CapsuleRuntime.isPending('test-paper')).assertFalse();
    });

    it('paginatesEveryMemberWithoutOverflowOrDuplication', 0, () => {
      const first = capsuleViewport(600, 100, 4, true, false, 0);
      let next: number = 0;
      for (let page: number = 0; page < first.pages; page++) {
        const viewport = capsuleViewport(600, 100, 4, true, false, page);
        expect(viewport.fits).assertTrue();
        expect(viewport.height <= 584).assertTrue();
        expect(viewport.start).assertEqual(next);
        next = viewport.end;
      }
      expect(next).assertEqual(100);
    });

    it('retractionUsesOnlyTheMasterSlotAndShrinkingClampsThePage', 0, () => {
      const retracted = capsuleViewport(600, 100, 4, true, true, 99);
      expect(retracted.height).assertEqual(46);
      expect(retracted.end).assertEqual(0);
      expect(retracted.pager).assertFalse();
      expect(capsuleViewport(600, 2, 4, true, false, 99).page).assertEqual(0);
      expect(capsuleViewport(50, 100, 4, true, false, 0).fits).assertFalse();
    });
  });
}
