import { describe, expect, it } from '@ohos/hypium';
import {
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  PaperData,
  UI_LANGUAGE_EN,
  UI_LANGUAGE_JA,
  UI_LANGUAGE_KO,
  UI_LANGUAGE_SYSTEM,
  UI_LANGUAGE_ZH_CN
} from '../main/ets/common/Models';
import {
  cleanCommittedPaperTitle,
  cleanPaperTitle,
  defaultPaperTitle,
  effectivePaperTitle,
  nextPaperTitleNumber,
  normalizePaperTitleLimit,
  paperTitleNumberFor
} from '../main/ets/common/PaperTitles';
import { PaperStore } from '../main/ets/common/PaperStore';

function makePaper(id: string, type: string, title: string): PaperData {
  return {
    id: id,
    type: type,
    title: title,
    expandedX: 120,
    expandedY: 120,
    expandedWidth: 280,
    expandedHeight: 340,
    capsuleX: 120,
    capsuleY: 120,
    capsuleWidth: 108,
    edgeSide: 'right',
    edgeOrder: 0,
    edgeDisplayId: 'default',
    isVisible: true,
    alwaysOnTop: false,
    isCollapsed: false,
    textZoom: 1,
    items: [],
    content: '',
    createdAt: 1,
    updatedAt: 1
  };
}

export default function paperTitlesTest(): void {
  describe('PaperTitlesTest', () => {
    it('buildsLocalizedDefaultTitlesLikeTheDesktopApp', 0, () => {
      expect(defaultPaperTitle(PAPER_TYPE_TODO, 1, UI_LANGUAGE_ZH_CN, 'en-US')).assertEqual('待办1');
      expect(defaultPaperTitle(PAPER_TYPE_NOTE, 2, UI_LANGUAGE_ZH_CN, 'en-US')).assertEqual('笔记2');
      expect(defaultPaperTitle(PAPER_TYPE_TODO, 3, UI_LANGUAGE_EN, 'zh-CN')).assertEqual('Todo3');
      expect(defaultPaperTitle(PAPER_TYPE_NOTE, 4, UI_LANGUAGE_EN, 'zh-CN')).assertEqual('Note4');
      expect(defaultPaperTitle(PAPER_TYPE_NOTE, 5, UI_LANGUAGE_JA, 'zh-CN')).assertEqual('メモ5');
      expect(defaultPaperTitle(PAPER_TYPE_NOTE, 6, UI_LANGUAGE_KO, 'zh-CN')).assertEqual('메모6');
      expect(defaultPaperTitle(PAPER_TYPE_TODO, 0, UI_LANGUAGE_SYSTEM, 'zh-CN')).assertEqual('待办1');
    });

    it('usesTheSmallestUnusedPositiveNumberPerPaperType', 0, () => {
      const papers: PaperData[] = [
        makePaper('todo-1', PAPER_TYPE_TODO, '待办1'),
        makePaper('todo-3', PAPER_TYPE_TODO, '待办3'),
        makePaper('todo-custom', PAPER_TYPE_TODO, '待办2x'),
        makePaper('note-1', PAPER_TYPE_NOTE, '笔记1')
      ];
      expect(nextPaperTitleNumber(papers, PAPER_TYPE_TODO, UI_LANGUAGE_ZH_CN, 'zh-CN')).assertEqual(2);
      expect(nextPaperTitleNumber(papers, PAPER_TYPE_NOTE, UI_LANGUAGE_ZH_CN, 'zh-CN')).assertEqual(2);
      papers.push(makePaper('todo-2', PAPER_TYPE_TODO, '待办02'));
      expect(nextPaperTitleNumber(papers, PAPER_TYPE_TODO, UI_LANGUAGE_ZH_CN, 'zh-CN')).assertEqual(4);
    });

    it('providesAStableReadOnlyFallbackForLegacyEmptyTitles', 0, () => {
      const first: PaperData = makePaper('first', PAPER_TYPE_TODO, '待办9');
      const note: PaperData = makePaper('note', PAPER_TYPE_NOTE, '');
      const legacyEmpty: PaperData = makePaper('legacy-empty', PAPER_TYPE_TODO, '');
      const papers: PaperData[] = [first, note, legacyEmpty];
      expect(paperTitleNumberFor(legacyEmpty, papers)).assertEqual(2);
      expect(effectivePaperTitle(legacyEmpty, papers, UI_LANGUAGE_ZH_CN, 'zh-CN')).assertEqual('待办2');
      expect(legacyEmpty.title).assertEqual('');
      expect(effectivePaperTitle(first, papers, UI_LANGUAGE_ZH_CN, 'zh-CN')).assertEqual('待办9');
    });

    it('trimsRemovesControlsAndAppliesHardAndUserLimits', 0, () => {
      expect(cleanPaperTitle('\u0000  Paper\nTodo  \u007F')).assertEqual('PaperTodo');
      expect(cleanPaperTitle('1234567890123456789012345')).assertEqual('12345678901234567890');
      expect(normalizePaperTitleLimit(1)).assertEqual(2);
      expect(normalizePaperTitleLimit(30)).assertEqual(20);
      expect(normalizePaperTitleLimit(0)).assertEqual(6);
      expect(cleanCommittedPaperTitle('  1234567  ', 4)).assertEqual('1234');
      expect(cleanCommittedPaperTitle('1234567', 0)).assertEqual('123456');
    });

    it('storesLocalizedTitlesAndInheritsTopmostFromTheSourcePaper', 0, () => {
      let sourceId: string = '';
      let childId: string = '';
      try {
        PaperStore.setUiLanguage(UI_LANGUAGE_EN);
        const source: PaperData | null = PaperStore.createPaper(PAPER_TYPE_TODO);
        expect(source === null).assertFalse();
        if (source === null) {
          return;
        }
        sourceId = source.id;
        expect(source.title.startsWith('Todo')).assertTrue();
        source.alwaysOnTop = true;
        PaperStore.updatePaper(source, false);

        const child: PaperData | null = PaperStore.createPaper(PAPER_TYPE_NOTE, source.id);
        expect(child === null).assertFalse();
        if (child === null) {
          return;
        }
        childId = child.id;
        expect(child.title.startsWith('Note')).assertTrue();
        expect(child.alwaysOnTop).assertTrue();
      } finally {
        if (childId.length > 0) {
          PaperStore.deletePaper(childId);
        }
        if (sourceId.length > 0) {
          PaperStore.deletePaper(sourceId);
        }
        PaperStore.setUiLanguage(UI_LANGUAGE_SYSTEM);
      }
    });
  });
}
