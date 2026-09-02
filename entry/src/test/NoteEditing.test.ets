import { describe, expect, it } from '@ohos/hypium';
import {
  applyMarkdownBold,
  applyMarkdownCode,
  applyMarkdownItalic,
  handleMarkdownListEnter,
  insertMarkdownLinePrefix,
  insertMarkdownLink,
  NoteEditResult,
  normalizeNoteSelection
} from '../main/ets/common/NoteEditing';

export default function noteEditingTest(): void {
  describe('NoteEditingTest', () => {
    it('wrapsUnicodeSelectionsWithoutSplittingSurrogatePairs', 0, () => {
      const result: NoteEditResult = applyMarkdownBold('A😀B', { start: 2, end: 3 });
      expect(result.nextText).assertEqual('A**😀**B');
      expect(result.selection.start).assertEqual(3);
      expect(result.selection.end).assertEqual(5);
      expect(result.caret).assertEqual(5);
    });

    it('insertsMarkersAtASafeCollapsedCaret', 0, () => {
      const result: NoteEditResult = applyMarkdownItalic('A😀B', { start: 2, end: 2 });
      expect(result.nextText).assertEqual('A😀**B');
      expect(result.selection.start).assertEqual(4);
      expect(result.selection.end).assertEqual(4);
    });

    it('wrapsNonEmptyLinesAndPreservesMixedLineBoundaries', 0, () => {
      const source: string = 'first\r\n\r\n第二\nthird';
      const result: NoteEditResult = applyMarkdownBold(source, { start: 0, end: source.length });
      expect(result.nextText).assertEqual('**first**\r\n\r\n**第二**\n**third**');
      expect(result.selection.start).assertEqual(0);
      expect(result.selection.end).assertEqual(result.nextText.length);
    });

    it('usesTheSelectedCrLfStyleForMarkdownCodeFences', 0, () => {
      const source: string = 'first\r\nsecond';
      const result: NoteEditResult = applyMarkdownCode(source, { start: 0, end: source.length });
      expect(result.nextText).assertEqual('```\r\nfirst\r\nsecond\r\n```');
    });

    it('insertsALinkAndSelectsItsTarget', 0, () => {
      const result: NoteEditResult = insertMarkdownLink('打开文档', { start: 0, end: 4 }, '链接', 'https://');
      expect(result.nextText).assertEqual('[打开文档](https://)');
      expect(result.nextText.substring(result.selection.start, result.selection.end)).assertEqual('https://');
      expect(result.caret).assertEqual(result.selection.end);
    });

    it('escapesSelectedMarkdownLinkLabelDelimiters', 0, () => {
      const source: string = 'A[one]\\B]';
      const result: NoteEditResult = insertMarkdownLink(source, { start: 0, end: source.length });
      expect(result.nextText).assertEqual('[A\\[one\\]\\\\B\\]](https://)');
      expect(result.nextText.substring(result.selection.start, result.selection.end)).assertEqual('https://');
    });

    it('rejectsCrossLineMarkdownLinkLabels', 0, () => {
      const source: string = 'first\r\nsecond';
      const result: NoteEditResult = insertMarkdownLink(source, { start: 0, end: source.length });
      expect(result.handled).assertFalse();
      expect(result.nextText).assertEqual(source);
      expect(result.selection.start).assertEqual(0);
      expect(result.selection.end).assertEqual(source.length);
    });

    it('insertsLinePrefixesAtLineStartsInsteadOfTheCaret', 0, () => {
      const collapsed: NoteEditResult = insertMarkdownLinePrefix('hello', { start: 3, end: 3 }, '## ');
      expect(collapsed.nextText).assertEqual('## hello');
      expect(collapsed.caret).assertEqual(6);

      const ranged: NoteEditResult = insertMarkdownLinePrefix('one\r\ntwo\nthree', { start: 1, end: 12 }, '> ');
      expect(ranged.nextText).assertEqual('> one\r\n> two\n> three');
    });

    it('doesNotPrefixAnUnselectedLineAtTheRangeEnd', 0, () => {
      const result: NoteEditResult = insertMarkdownLinePrefix('one\ntwo', { start: 0, end: 4 }, '- ');
      expect(result.nextText).assertEqual('- one\ntwo');
    });

    it('continuesBulletsWithTheExistingCrLfDelimiter', 0, () => {
      const source: string = '- 完成😀\r\n下一行';
      const caret: number = '- 完成😀'.length;
      const result: NoteEditResult = handleMarkdownListEnter(source, { start: caret, end: caret });
      expect(result.handled).assertTrue();
      expect(result.nextText).assertEqual('- 完成😀\r\n- \r\n下一行');
      expect(result.caret).assertEqual(caret + 4);
    });

    it('incrementsOrderedListsAndPreservesTheSuffix', 0, () => {
      const result: NoteEditResult = handleMarkdownListEnter('9. abcd', { start: 5, end: 5 });
      expect(result.handled).assertTrue();
      expect(result.nextText).assertEqual('9. ab\n10. cd');
      expect(result.selection.start).assertEqual(10);
      expect(result.selection.end).assertEqual(10);
    });

    it('continuesCheckedTasksAsUncheckedTasks', 0, () => {
      const source: string = '* [x] shipped';
      const result: NoteEditResult = handleMarkdownListEnter(source,
        { start: source.length, end: source.length });
      expect(result.nextText).assertEqual('* [x] shipped\n* [ ] ');
      expect(result.handled).assertTrue();
    });

    it('doesNotContinueListsInsideFencedCodeBlocks', 0, () => {
      const source: string = '```\r\n- code\r\n```\r\n- outside';
      const insideCaret: number = '```\r\n- code'.length;
      const inside: NoteEditResult = handleMarkdownListEnter(source,
        { start: insideCaret, end: insideCaret });
      expect(inside.handled).assertFalse();
      expect(inside.nextText).assertEqual(source);

      const outside: NoteEditResult = handleMarkdownListEnter(source,
        { start: source.length, end: source.length });
      expect(outside.handled).assertTrue();
      expect(outside.nextText).assertEqual(source + '\r\n- ');
    });

    it('removesOnlyTheMarkerOfAnEmptyIndentedListItem', 0, () => {
      const source: string = '  -   ';
      const result: NoteEditResult = handleMarkdownListEnter(source,
        { start: source.length, end: source.length });
      expect(result.nextText).assertEqual('  ');
      expect(result.caret).assertEqual(2);
      expect(result.handled).assertTrue();
    });

    it('leavesRangeReplacementAndNonListEnterToTheEditor', 0, () => {
      const ranged: NoteEditResult = handleMarkdownListEnter('- item', { start: 2, end: 6 });
      const plain: NoteEditResult = handleMarkdownListEnter('plain', { start: 5, end: 5 });
      expect(ranged.handled).assertFalse();
      expect(ranged.nextText).assertEqual('- item');
      expect(plain.handled).assertFalse();
      expect(plain.nextText).assertEqual('plain');
    });

    it('normalizesSelectionsAcrossCrLfAsOneBoundary', 0, () => {
      const source: string = 'a\r\nb';
      expect(normalizeNoteSelection(source, { start: 2, end: 2 }).start).assertEqual(3);
      expect(normalizeNoteSelection(source, { start: 2, end: 3 }).start).assertEqual(1);
      expect(normalizeNoteSelection(source, { start: 2, end: 3 }).end).assertEqual(3);
    });
  });
}
