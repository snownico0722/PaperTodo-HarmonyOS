import { describe, expect, it } from '@ohos/hypium';
import {
  capsuleSlotTop,
  normalizeCapsuleGap,
  normalizeCapsuleStartTopMargin
} from '../main/ets/common/CapsuleLayout';

export default function capsuleLayoutTest(): void {
  describe('CapsuleLayoutTest', () => {
    it('normalizesTheSupportedQueueGaps', 0, () => {
      expect(normalizeCapsuleGap(0)).assertEqual(0);
      expect(normalizeCapsuleGap(4)).assertEqual(4);
      expect(normalizeCapsuleGap(8)).assertEqual(8);
      expect(normalizeCapsuleGap(5)).assertEqual(4);
    });

    it('fallsBackForNonFiniteQueueGaps', 0, () => {
      expect(normalizeCapsuleGap(Number.NaN)).assertEqual(4);
      expect(normalizeCapsuleGap(Number.POSITIVE_INFINITY)).assertEqual(4);
      expect(normalizeCapsuleGap(Number.NEGATIVE_INFINITY)).assertEqual(4);
    });

    it('keepsTheDefaultStartWhenTheQueueFits', 0, () => {
      expect(normalizeCapsuleStartTopMargin(48, 900, 3, 4, true)).assertEqual(48);
    });

    it('clampsTheQueueStartToTheAvailableArea', 0, () => {
      expect(normalizeCapsuleStartTopMargin(999, 900, 3, 4, true)).assertEqual(696);
      expect(normalizeCapsuleStartTopMargin(-100, 900, 3, 4, true)).assertEqual(8);
      expect(normalizeCapsuleStartTopMargin(48, 100, 2, 4, true)).assertEqual(8);
    });

    it('usesTheDefaultStartForNonFiniteRequests', 0, () => {
      expect(normalizeCapsuleStartTopMargin(Number.NaN, 900, 3, 4, true)).assertEqual(48);
      expect(normalizeCapsuleStartTopMargin(Number.POSITIVE_INFINITY, 900, 3, 4, true)).assertEqual(48);
      expect(normalizeCapsuleStartTopMargin(Number.NEGATIVE_INFINITY, 900, 3, 4, true)).assertEqual(48);
    });

    it('treatsNonFiniteAreasAndCountsAsUnavailable', 0, () => {
      expect(normalizeCapsuleStartTopMargin(90, Number.NaN, 3, 4, true)).assertEqual(90);
      expect(normalizeCapsuleStartTopMargin(90, Number.POSITIVE_INFINITY, 3, 4, true)).assertEqual(90);
      expect(normalizeCapsuleStartTopMargin(90, 300, Number.NaN, 4, true)).assertEqual(90);
      expect(normalizeCapsuleStartTopMargin(90, 300, Number.POSITIVE_INFINITY, 4, true)).assertEqual(90);
      expect(normalizeCapsuleStartTopMargin(90, 300, -2, 4, true)).assertEqual(90);
    });

    it('floorsFractionalMemberCountsBeforeClamping', 0, () => {
      expect(normalizeCapsuleStartTopMargin(999, 300, 2.9, 4, true)).assertEqual(146);
    });

    it('reservesMasterSpaceAtTheBottomBoundary', 0, () => {
      expect(normalizeCapsuleStartTopMargin(999, 300, 3, 4, false)).assertEqual(146);
      expect(normalizeCapsuleStartTopMargin(999, 300, 3, 4, true)).assertEqual(96);
      expect(normalizeCapsuleStartTopMargin(92, 200, 2, 8, false)).assertEqual(92);
      expect(normalizeCapsuleStartTopMargin(93, 200, 2, 8, false)).assertEqual(92);
    });

    it('doesNotInventAMasterSlotForAnEmptyQueue', 0, () => {
      expect(normalizeCapsuleStartTopMargin(90, 100, 0, 4, true)).assertEqual(90);
    });

    it('reservesSlotZeroOnlyWhenTheMasterCapsuleIsVisible', 0, () => {
      expect(capsuleSlotTop(48, 0, 4, true)).assertEqual(98);
      expect(capsuleSlotTop(48, 1, 4, true)).assertEqual(148);
      expect(capsuleSlotTop(48, 0, 4, false)).assertEqual(48);
    });

    it('normalizesSlotIndicesAndGaps', 0, () => {
      expect(capsuleSlotTop(48, -2, 4, false)).assertEqual(48);
      expect(capsuleSlotTop(48, 1.9, 4, false)).assertEqual(98);
      expect(capsuleSlotTop(48, 1, Number.NaN, false)).assertEqual(98);
      expect(capsuleSlotTop(48, 1, Number.POSITIVE_INFINITY, false)).assertEqual(98);
    });
  });
}
