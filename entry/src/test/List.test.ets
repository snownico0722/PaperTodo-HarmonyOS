import capsuleLayoutTest from './CapsuleLayout.test';
import capsuleEligibilityTest from './CapsuleEligibility.test';
import externalMarkdownTest from './ExternalMarkdown.test';
import markdownLiteTest from './MarkdownLite.test';
import noteEditingTest from './NoteEditing.test';
import noteImageStoreTest from './NoteImageStore.test';
import paperInteractionPolicyTest from './PaperInteractionPolicy.test';
import paperStoreDefaultsTest from './PaperStoreDefaults.test';
import paperStoreNormalizationTest from './PaperStoreNormalization.test';
import paperTitlesTest from './PaperTitles.test';
import stringsTest from './Strings.test';
import textSafetyTest from './TextSafety.test';
import todoHistoryTest from './TodoHistory.test';

export default function testsuite(): void {
  capsuleLayoutTest();
  capsuleEligibilityTest();
  externalMarkdownTest();
  markdownLiteTest();
  noteEditingTest();
  noteImageStoreTest();
  paperInteractionPolicyTest();
  paperStoreDefaultsTest();
  paperStoreNormalizationTest();
  paperTitlesTest();
  stringsTest();
  textSafetyTest();
  todoHistoryTest();
}
