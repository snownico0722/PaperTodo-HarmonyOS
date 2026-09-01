import { describe, expect, it } from '@ohos/hypium';
import {
  AppState,
  CAPSULE_MAX_WIDTH,
  COLOR_SCHEME_WARM,
  DEFAULT_DISPLAY_ID,
  EDGE_SIDE_RIGHT,
  MARKDOWN_ENHANCED,
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  PaperData,
  RESIZE_GRIP_SOFT,
  THEME_SYSTEM,
  TODO_VISUAL_MEDIUM,
  UI_LANGUAGE_SYSTEM,
  VISUAL_TEXT_MEDIUM
} from '../main/ets/common/Models';
import { PaperStore } from '../main/ets/common/PaperStore';

function parsePaper(raw: string): PaperData {
  return JSON.parse(raw) as PaperData;
}

function resetAppearanceDefaults(): void {
  PaperStore.setUiLanguage(UI_LANGUAGE_SYSTEM);
  PaperStore.setTheme(THEME_SYSTEM);
  PaperStore.setColorScheme(COLOR_SCHEME_WARM);
  PaperStore.setMarkdownMode(MARKDOWN_ENHANCED);
  PaperStore.setTodoVisualSize(TODO_VISUAL_MEDIUM);
  PaperStore.setCapsuleGap(4);
  PaperStore.setEdgeCapsuleTitleCharacterLimit(0);
  PaperStore.setOverallFontScale(1);
  PaperStore.setNoteTextAppearance(VISUAL_TEXT_MEDIUM, false);
  PaperStore.setTitleTextAppearance(VISUAL_TEXT_MEDIUM, true);
  PaperStore.setCapsuleTextAppearance(VISUAL_TEXT_MEDIUM, false);
  PaperStore.setResizeGripMode(RESIZE_GRIP_SOFT);
}

export default function paperStoreNormalizationTest(): void {
  describe('PaperStoreNormalizationTest', () => {
    it('normalizesInvalidAppearanceSettingsThroughPublicEntrypoints', 0, () => {
      try {
        PaperStore.setUiLanguage('unsupported');
        PaperStore.setTheme('sepia');
        PaperStore.setColorScheme('future');
        PaperStore.setMarkdownMode('future');
        PaperStore.setTodoVisualSize('huge');
        PaperStore.setCapsuleGap(3);
        PaperStore.setEdgeCapsuleTitleCharacterLimit(99);
        PaperStore.setOverallFontScale(Number.NaN);
        PaperStore.setNoteTextAppearance('tiny', false);
        PaperStore.setTitleTextAppearance('huge', true);
        PaperStore.setCapsuleTextAppearance('giant', false);
        PaperStore.setResizeGripMode('future');

        const state: AppState = PaperStore.loadState();
        expect(state.uiLanguage).assertEqual(UI_LANGUAGE_SYSTEM);
        expect(state.theme).assertEqual(THEME_SYSTEM);
        expect(state.colorScheme).assertEqual(COLOR_SCHEME_WARM);
        expect(state.markdownRenderMode).assertEqual(MARKDOWN_ENHANCED);
        expect(state.todoVisualSize).assertEqual(TODO_VISUAL_MEDIUM);
        expect(state.capsuleGap).assertEqual(4);
        expect(state.edgeCapsuleTitleCharacterLimit).assertEqual(0);
        expect(state.overallFontScale).assertEqual(1);
        expect(state.noteTextSize).assertEqual(VISUAL_TEXT_MEDIUM);
        expect(state.titleTextSize).assertEqual(VISUAL_TEXT_MEDIUM);
        expect(state.capsuleTextSize).assertEqual(VISUAL_TEXT_MEDIUM);
        expect(state.resizeGripMode).assertEqual(RESIZE_GRIP_SOFT);
      } finally {
        resetAppearanceDefaults();
      }
    });

    it('clampsAndRoundsFontScaleAtBothBoundaries', 0, () => {
      try {
        PaperStore.setOverallFontScale(0.1);
        expect(PaperStore.loadState().overallFontScale).assertEqual(0.8);
        PaperStore.setOverallFontScale(1.26);
        expect(PaperStore.loadState().overallFontScale).assertEqual(1.2);
        PaperStore.setOverallFontScale(1.071);
        expect(PaperStore.loadState().overallFontScale).assertEqual(1.05);
      } finally {
        PaperStore.setOverallFontScale(1);
      }
    });

    it('normalizesLegacyPaperFieldsWithoutPreferences', 0, () => {
      try {
        const paper: PaperData = parsePaper('{"id":"normalization-paper","type":"unknown",' +
          '"title":"1234567890123456789012345","x":41,"y":52,"width":301,"height":411,' +
          '"capsuleWidth":999,"edgeSide":"left","edgeOrder":7,"edgeDisplayId":"external-display",' +
          '"items":[{"id":"same","text":"first","done":"yes","order":91},' +
          '{"id":"same","text":"second","done":true,"order":43}],' +
          '"content":5,"isVisible":"yes","alwaysOnTop":"yes","isCollapsed":"yes","textZoom":9}');
        PaperStore.updatePaper(paper, true);

        const normalized: PaperData | null = PaperStore.getPaper('normalization-paper');
        expect(normalized === null).assertFalse();
        if (normalized === null) {
          return;
        }
        expect(normalized.type).assertEqual(PAPER_TYPE_TODO);
        expect(normalized.title).assertEqual('12345678901234567890');
        expect(normalized.expandedX).assertEqual(41);
        expect(normalized.expandedY).assertEqual(52);
        expect(normalized.expandedWidth).assertEqual(301);
        expect(normalized.expandedHeight).assertEqual(411);
        expect(normalized.capsuleX).assertEqual(41);
        expect(normalized.capsuleY).assertEqual(52);
        expect(normalized.capsuleWidth).assertEqual(CAPSULE_MAX_WIDTH);
        expect(normalized.edgeSide).assertEqual(EDGE_SIDE_RIGHT);
        expect(normalized.edgeDisplayId).assertEqual(DEFAULT_DISPLAY_ID);
        expect(normalized.edgeOrder).assertEqual(7);
        expect(normalized.items[0].done).assertFalse();
        expect(normalized.items[0].order).assertEqual(0);
        expect(normalized.items[1].order).assertEqual(1);
        expect(normalized.items[0].id === normalized.items[1].id).assertFalse();
        expect(normalized.content).assertEqual('');
        expect(normalized.isVisible).assertTrue();
        expect(normalized.alwaysOnTop).assertFalse();
        expect(normalized.isCollapsed).assertFalse();
        expect(normalized.textZoom).assertEqual(1);
      } finally {
        PaperStore.deletePaper('normalization-paper');
      }
    });

    it('repairsLinksAndMakesQuickLaunchMutuallyExclusive', 0, () => {
      let targetId: string = '';
      try {
        const target: PaperData | null = PaperStore.createPaper(PAPER_TYPE_NOTE);
        expect(target === null).assertFalse();
        if (target === null) {
          return;
        }
        targetId = target.id;
        const paper: PaperData = parsePaper('{"id":"normalization-links","type":"todo","title":"",' +
          '"expandedX":1,"expandedY":2,"expandedWidth":280,"expandedHeight":340,' +
          '"capsuleX":3,"capsuleY":4,"capsuleWidth":108,"edgeSide":"right","edgeOrder":8,' +
          '"edgeDisplayId":"default","isVisible":true,"alwaysOnTop":false,"isCollapsed":false,' +
          '"textZoom":1,"items":[' +
          '{"id":"valid","text":"","done":false,"order":0,"linkedPaperId":"' + target.id + '"},' +
          '{"id":"self","text":"","done":false,"order":1,"linkedPaperId":"normalization-links"},' +
          '{"id":"missing","text":"","done":false,"order":2,"linkedPaperId":"gone"},' +
          '{"id":"quick","text":"","done":false,"order":3,"linkedPaperId":"' + target.id + '",' +
          '"quickLaunchUri":"file://document","quickLaunchKind":"invalid"}],' +
          '"content":"","createdAt":10,"updatedAt":20}');
        PaperStore.updatePaper(paper, true);

        const normalized: PaperData | null = PaperStore.getPaper('normalization-links');
        expect(normalized === null).assertFalse();
        if (normalized === null) {
          return;
        }
        expect(normalized.items[0].linkedPaperId).assertEqual(target.id);
        expect(normalized.items[1].linkedPaperId === undefined).assertTrue();
        expect(normalized.items[2].linkedPaperId === undefined).assertTrue();
        expect(normalized.items[3].linkedPaperId === undefined).assertTrue();
        expect(normalized.items[3].quickLaunchName).assertEqual('');
        expect(normalized.items[3].quickLaunchKind).assertEqual('file');
      } finally {
        PaperStore.deletePaper('normalization-links');
        if (targetId.length > 0) {
          PaperStore.deletePaper(targetId);
        }
      }
    });

    it('forcesEveryNewPaperIntoTheSingleRightQueue', 0, () => {
      let paperId: string = '';
      try {
        const paper: PaperData | null = PaperStore.createPaper('future-paper-type');
        expect(paper === null).assertFalse();
        if (paper === null) {
          return;
        }
        paperId = paper.id;
        expect(paper.type).assertEqual(PAPER_TYPE_TODO);
        expect(paper.edgeSide).assertEqual(EDGE_SIDE_RIGHT);
        expect(paper.edgeDisplayId).assertEqual(DEFAULT_DISPLAY_ID);
      } finally {
        if (paperId.length > 0) {
          PaperStore.deletePaper(paperId);
        }
      }
    });
  });
}
