import markdownLiteTest from './MarkdownLite.test';
import noteEditingTest from './NoteEditing.test';
import noteImageStoreTest from './NoteImageStore.test';
import paperStoreDefaultsTest from './PaperStoreDefaults.test';
import stringsTest from './Strings.test';
import textSafetyTest from './TextSafety.test';
import todoHistoryTest from './TodoHistory.test';

export default function testsuite(): void {
  markdownLiteTest();
  noteEditingTest();
  noteImageStoreTest();
  paperStoreDefaultsTest();
  stringsTest();
  textSafetyTest();
  todoHistoryTest();
}
