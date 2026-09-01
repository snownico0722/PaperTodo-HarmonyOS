import { describe, expect, it } from '@ohos/hypium';
import {
  EXTERNAL_MARKDOWN_DEPENDENCY_URI_BUDGET,
  ExternalMarkdownDocument,
  rewriteExternalMarkdown
} from '../main/ets/common/ExternalMarkdown';

export default function externalMarkdownTest(): void {
  describe('ExternalMarkdown', (): void => {
    it('rewrites owned image references and deduplicates streams', 0, (): void => {
      const result: ExternalMarkdownDocument = rewriteExternalMarkdown(
        '![image|75%](i:img_1)\n![again](i:img_1){width=50%}',
        (id: string): string => id === 'img_1' ? 'file://paper/image.png' : ''
      );
      expect(result.content).assertEqual(
        '![image|75%](file://paper/image.png)\n![again](file://paper/image.png){width=50%}');
      expect(result.dependencyUris.length).assertEqual(1);
    });

    it('leaves missing and fenced references untouched', 0, (): void => {
      const result: ExternalMarkdownDocument = rewriteExternalMarkdown(
        '![missing](i:other)\n```md\n![code](i:owned)\n```\n![ok](i:owned)',
        (id: string): string => id === 'owned' ? 'file://paper/owned.png' : ''
      );
      expect(result.content).assertEqual(
        '![missing](i:other)\n```md\n![code](i:owned)\n```\n![ok](file://paper/owned.png)');
      expect(result.dependencyUris.length).assertEqual(1);
    });

    it('preserves CRLF line endings', 0, (): void => {
      const result: ExternalMarkdownDocument = rewriteExternalMarkdown(
        'before\r\n![image](i:owned)\r\nafter',
        (_id: string): string => 'file://paper/image.png'
      );
      expect(result.content).assertEqual('before\r\n![image](file://paper/image.png)\r\nafter');
    });

    it('rejects dependency URI payloads beyond the safe budget', 0, (): void => {
      let largeUri: string = 'file://';
      while (largeUri.length <= EXTERNAL_MARKDOWN_DEPENDENCY_URI_BUDGET) {
        largeUri += '0123456789';
      }
      let threw: boolean = false;
      try {
        rewriteExternalMarkdown('![image](i:owned)', (_id: string): string => largeUri);
      } catch (_error) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
  });
}
