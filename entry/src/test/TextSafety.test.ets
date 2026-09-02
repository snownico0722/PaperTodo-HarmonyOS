import { describe, expect, it } from '@ohos/hypium';
import { truncateText } from '../main/ets/common/TextSafety';

export default function textSafetyTest(): void {
  describe('TextSafetyTest', () => {
    it('returnsEmptyForNonPositiveLimits', 0, () => {
      expect(truncateText('PaperTodo', 0)).assertEqual('');
      expect(truncateText('PaperTodo', -3)).assertEqual('');
    });

    it('keepsTextThatAlreadyFitsTheLimit', 0, () => {
      expect(truncateText('纸片', 2)).assertEqual('纸片');
      expect(truncateText('A😀B', 4)).assertEqual('A😀B');
      expect(truncateText('', 10)).assertEqual('');
    });

    it('truncatesAsciiAndBmpTextAtCodeUnitBoundaries', 0, () => {
      expect(truncateText('PaperTodo', 5)).assertEqual('Paper');
      expect(truncateText('桌面纸片', 3)).assertEqual('桌面纸');
    });

    it('neverLeavesADanglingHighSurrogate', 0, () => {
      expect(truncateText('A😀B', 2)).assertEqual('A');
      expect(truncateText('A😀B', 3)).assertEqual('A😀');
      expect(truncateText('😀B', 1)).assertEqual('');
      expect(truncateText('😀B', 2)).assertEqual('😀');
      expect(truncateText('😀😀Z', 3)).assertEqual('😀');
      expect(truncateText('😀😀Z', 4)).assertEqual('😀😀');
    });

    it('preservesACompleteSurrogatePairAtTheExactLimit', 0, () => {
      const result: string = truncateText('任务🧪完成', 4);
      expect(result).assertEqual('任务🧪');
      const finalCodeUnit: number = result.charCodeAt(result.length - 1);
      expect(finalCodeUnit >= 0xDC00 && finalCodeUnit <= 0xDFFF).assertTrue();
    });
  });
}
