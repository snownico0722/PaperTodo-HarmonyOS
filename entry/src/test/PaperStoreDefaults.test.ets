import { describe, expect, it } from '@ohos/hypium';
import {
  CAPSULE_WIDTH,
  COLOR_SCHEME_WARM,
  DEFAULT_DISPLAY_ID,
  EDGE_SIDE_RIGHT,
  MARKDOWN_ENHANCED,
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  PaperData,
  RESIZE_GRIP_SOFT,
  SCHEMA_VERSION,
  THEME_SYSTEM,
  TODO_VISUAL_MEDIUM,
  UI_LANGUAGE_SYSTEM,
  VISUAL_TEXT_MEDIUM
} from '../main/ets/common/Models';
import { PaperStore } from '../main/ets/common/PaperStore';

export default function paperStoreDefaultsTest(): void {
  describe('PaperStoreDefaultsTest', () => {
    it('keepsEveryPersistedSettingOnTheDocumentedSafeDefault', 0, () => {
      const state = PaperStore.loadState();
      expect(state.schemaVersion).assertEqual(SCHEMA_VERSION);
      expect(state.initialized).assertFalse();
      expect(state.noteImages.length).assertEqual(0);
      expect(state.autoCompressLargeImages).assertTrue();
      expect(state.globalHotkeysEnabled).assertFalse();
      expect(state.uiLanguage).assertEqual(UI_LANGUAGE_SYSTEM);
      expect(state.theme).assertEqual(THEME_SYSTEM);
      expect(state.colorScheme).assertEqual(COLOR_SCHEME_WARM);
      expect(state.markdownRenderMode).assertEqual(MARKDOWN_ENHANCED);
      expect(state.useCapsuleMode).assertTrue();
      expect(state.useDeepCapsuleMode).assertTrue();
      expect(state.todoVisualSize).assertEqual(TODO_VISUAL_MEDIUM);
      expect(state.autoClearCompletedTodos).assertFalse();
      expect(state.autoBottomCompleted).assertFalse();
      expect(state.capsuleGap).assertEqual(4);
      expect(state.enableAnimations).assertTrue();
      expect(state.rememberEdgeExpandedPosition).assertTrue();
      expect(state.collapseExpandedEdgeCapsuleOnClick).assertFalse();
      expect(state.hideEdgeCapsuleCloseButtonOnHover).assertFalse();
      expect(state.edgeCapsuleTitleCharacterLimit).assertEqual(0);
      expect(state.enablePaperLinks).assertTrue();
      expect(state.overallFontScale).assertEqual(1);
      expect(state.noteTextSize).assertEqual(VISUAL_TEXT_MEDIUM);
      expect(state.noteTextBold).assertFalse();
      expect(state.todoTextBold).assertFalse();
      expect(state.titleTextSize).assertEqual(VISUAL_TEXT_MEDIUM);
      expect(state.titleTextBold).assertTrue();
      expect(state.capsuleTextSize).assertEqual(VISUAL_TEXT_MEDIUM);
      expect(state.capsuleTextBold).assertFalse();
      expect(state.resizeGripMode).assertEqual(RESIZE_GRIP_SOFT);
      expect(state.showTopBarNewTodoButton).assertTrue();
      expect(state.showTopBarNewNoteButton).assertTrue();
      expect(state.showTopBarExternalOpenButton).assertTrue();
    });

    it('createsNewPapersInTheSingleDefaultQueue', 0, () => {
      const todo: PaperData | null = PaperStore.createPaper(PAPER_TYPE_TODO);
      const note: PaperData | null = PaperStore.createPaper(PAPER_TYPE_NOTE);
      expect(todo === null).assertFalse();
      expect(note === null).assertFalse();
      if (todo === null || note === null) {
        return;
      }
      expect(todo.edgeSide).assertEqual(EDGE_SIDE_RIGHT);
      expect(todo.edgeDisplayId).assertEqual(DEFAULT_DISPLAY_ID);
      expect(todo.capsuleWidth).assertEqual(CAPSULE_WIDTH);
      expect(todo.textZoom).assertEqual(1);
      expect(note.edgeSide).assertEqual(EDGE_SIDE_RIGHT);
      expect(note.edgeDisplayId).assertEqual(DEFAULT_DISPLAY_ID);
      expect(note.items.length).assertEqual(0);
    });
  });
}
