import { describe, expect, it } from '@ohos/hypium';
import {
  findClickableUrl,
  MarkdownInlineToken,
  MarkdownLine,
  MD_KIND_BULLET,
  MD_KIND_CODE,
  MD_KIND_IMAGE,
  MD_KIND_ORDERED,
  MD_KIND_TEXT,
  MD_INLINE_CODE,
  MD_INLINE_LINK,
  parseMarkdownInlineTokens,
  parseMarkdownLines,
  stripInlineMarkers
} from '../main/ets/common/MarkdownLite';
import { MARKDOWN_BASIC, MARKDOWN_ENHANCED } from '../main/ets/common/Models';

export default function markdownLiteTest(): void {
  describe('MarkdownLiteTest', () => {
    it('keepsBalancedUrlDelimitersAndTrimsSentencePunctuation', 0, () => {
      expect(findClickableUrl('Read https://example.com/docs_(v3)).')).assertEqual(
        'https://example.com/docs_(v3)'
      );
      expect(findClickableUrl('中文：https://example.com/路径，')).assertEqual(
        'https://example.com/路径'
      );
      expect(findClickableUrl('See https://example.com/a[b]]!')).assertEqual(
        'https://example.com/a[b]'
      );
    });

    it('trimsMarkdownMarkersFromBareUrls', 0, () => {
      expect(findClickableUrl('**https://example.com/bold**')).assertEqual(
        'https://example.com/bold'
      );
      expect(findClickableUrl('~~https://example.com/done~~')).assertEqual(
        'https://example.com/done'
      );
      expect(findClickableUrl('<https://example.com/angle>')).assertEqual(
        'https://example.com/angle'
      );
    });

    it('ignoresBareUrlsInsideInlineCode', 0, () => {
      const onlyCode: string | undefined = findClickableUrl('run `https://ignored.example/path`');
      expect(onlyCode === undefined).assertTrue();

      expect(findClickableUrl(
        '`https://ignored.example/path` then https://open.example/path'
      )).assertEqual('https://open.example/path');
    });

    it('ignoresLinksInsideMatchingMultiBacktickCodeSpans', 0, () => {
      const onlyCode: string | undefined = findClickableUrl(
        '``https://ignored.example/path ` literal``'
      );
      expect(onlyCode === undefined).assertTrue();
      expect(findClickableUrl(
        '``https://ignored.example/path`` then https://open.example/path'
      )).assertEqual('https://open.example/path');

      const lines: MarkdownLine[] = parseMarkdownLines(
        '``https://ignored.example/path``', MARKDOWN_ENHANCED
      );
      expect(lines[0].linkUrl === undefined).assertTrue();
    });

    it('ignoresMarkdownAndHtmlLinksInsideInlineCode', 0, () => {
      const markdownCode: string | undefined = findClickableUrl(
        '`[inside](https://ignored.example/markdown)`'
      );
      const htmlCode: string | undefined = findClickableUrl(
        '`<a href="https://ignored.example/html">inside</a>`'
      );
      expect(markdownCode === undefined).assertTrue();
      expect(htmlCode === undefined).assertTrue();
    });

    it('doesNotExposeLinksFromFencedCodeBlocks', 0, () => {
      const lines: MarkdownLine[] = parseMarkdownLines(
        'before\n```arkts\nhttps://ignored.example/fenced\n```\nafter https://open.example/page',
        MARKDOWN_ENHANCED
      );

      expect(lines.length).assertEqual(3);
      expect(lines[1].kind).assertEqual(MD_KIND_CODE);
      expect(lines[1].linkUrl === undefined).assertTrue();
      expect(lines[2].linkUrl).assertEqual('https://open.example/page');
    });

    it('keepsFenceMarkersInBasicModeWithoutMakingThemClickable', 0, () => {
      const lines: MarkdownLine[] = parseMarkdownLines(
        '```\nhttps://ignored.example/fenced\n```',
        MARKDOWN_BASIC
      );

      expect(lines.length).assertEqual(3);
      expect(lines[0].kind).assertEqual(MD_KIND_CODE);
      expect(lines[1].kind).assertEqual(MD_KIND_CODE);
      expect(lines[2].kind).assertEqual(MD_KIND_CODE);
      expect(lines[0].linkUrl === undefined).assertTrue();
      expect(lines[1].linkUrl === undefined).assertTrue();
      expect(lines[2].linkUrl === undefined).assertTrue();
    });

    it('scansTildeAndBacktickFencesWithoutParsingTheirContents', 0, () => {
      const tildeLines: MarkdownLine[] = parseMarkdownLines(
        'before\n~~~markdown\n![hidden](i:asset) https://ignored.example\n~~~\nafter',
        MARKDOWN_ENHANCED
      );
      expect(tildeLines.length).assertEqual(3);
      expect(tildeLines[1].kind).assertEqual(MD_KIND_CODE);
      expect(tildeLines[1].text).assertEqual('![hidden](i:asset) https://ignored.example');
      expect(tildeLines[1].linkUrl === undefined).assertTrue();

      const mismatchedFence: MarkdownLine[] = parseMarkdownLines(
        '````\n~~~ remains code\n````', MARKDOWN_ENHANCED
      );
      expect(mismatchedFence.length).assertEqual(1);
      expect(mismatchedFence[0].kind).assertEqual(MD_KIND_CODE);
    });

    it('convertsSupportedSimpleHtmlToReadableText', 0, () => {
      expect(stripInlineMarkers(
        '<strong>Bold</strong> <em>quiet</em> <del>done</del> <u>under</u> <code>x</code>'
      )).assertEqual('Bold quiet done under x');
      expect(stripInlineMarkers(
        '<a class="external" href="https://example.com/page">Example</a>'
      )).assertEqual('Example (https://example.com/page)');
    });

    it('findsSimpleHtmlAnchorTargets', 0, () => {
      expect(findClickableUrl(
        '<a class="external" href="https://example.com/page">Example</a>'
      )).assertEqual('https://example.com/page');
      expect(findClickableUrl(
        "<a href='https://example.com/中文'>中文链接</a>"
      )).assertEqual('https://example.com/中文');
    });

    it('rendersWhitelistedInlineHtmlAsRichTokens', 0, () => {
      const tokens: MarkdownInlineToken[] = parseMarkdownInlineTokens(
        '<strong>Bold <em>quiet</em></strong> <s>done</s> <u>under</u> ' +
          '<code>https://code.example</code> <a href="https://example.com/page"><i>Open</i></a>'
      );
      let boldSeen: boolean = false;
      let italicSeen: boolean = false;
      let strikeSeen: boolean = false;
      let codeSeen: boolean = false;
      let linkSeen: boolean = false;
      for (let i: number = 0; i < tokens.length; i++) {
        const token: MarkdownInlineToken = tokens[i];
        boldSeen = boldSeen || (token.text === 'Bold ' && token.style.bold);
        italicSeen = italicSeen || (token.text === 'quiet' && token.style.bold && token.style.italic);
        strikeSeen = strikeSeen || (token.text === 'done' && token.style.strike);
        codeSeen = codeSeen || (token.text === 'https://code.example' && token.kind === MD_INLINE_CODE &&
          token.linkUrl === undefined);
        linkSeen = linkSeen || (token.text === 'Open' && token.kind === MD_INLINE_LINK && token.style.italic &&
          token.linkUrl === 'https://example.com/page');
      }
      expect(boldSeen).assertTrue();
      expect(italicSeen).assertTrue();
      expect(strikeSeen).assertTrue();
      expect(codeSeen).assertTrue();
      expect(linkSeen).assertTrue();

      const lines: MarkdownLine[] = parseMarkdownLines('<b>same renderer</b>', MARKDOWN_ENHANCED);
      expect(lines[0].inlineTokens !== undefined).assertTrue();
      expect((lines[0].inlineTokens ?? [])[0].text).assertEqual('same renderer');
    });

    it('parsesLocalImageMarkersAndDefaultsToFullWidth', 0, () => {
      const lines: MarkdownLine[] = parseMarkdownLines(
        '![收据](i:image_2026-09-01)\n![  ](i:asset_A1)',
        MARKDOWN_ENHANCED
      );

      expect(lines.length).assertEqual(2);
      expect(lines[0].kind).assertEqual(MD_KIND_IMAGE);
      expect(lines[0].imageId).assertEqual('image_2026-09-01');
      expect(lines[0].imageAlt).assertEqual('收据');
      expect(lines[0].imagePercent).assertEqual(100);
      expect(lines[1].kind).assertEqual(MD_KIND_IMAGE);
      expect(lines[1].imageAlt).assertEqual('');
      expect(lines[1].imagePercent).assertEqual(100);
    });

    it('acceptsBothImagePercentageFormsAndPrefersWidthSuffix', 0, () => {
      const lines: MarkdownLine[] = parseMarkdownLines(
        '![图|75%](i:first)\n![图](i:second){width=35%}\n![图|80%](i:third){width=45%}',
        MARKDOWN_ENHANCED
      );

      expect(lines.length).assertEqual(3);
      expect(lines[0].kind).assertEqual(MD_KIND_IMAGE);
      expect(lines[0].imagePercent).assertEqual(75);
      expect(lines[1].imagePercent).assertEqual(35);
      expect(lines[2].imagePercent).assertEqual(45);
    });

    it('preservesLocalImageDimensionMetadataAndWidthSyntax', 0, () => {
      const lines: MarkdownLine[] = parseMarkdownLines(
        '![wide|320x180](i:wide)\n![tall|120×240](i:tall)\n![fixed](i:fixed){width=280}\n' +
          '![combined|640x360, 75%](i:combined)\n![percent|75%](i:percent){width=40%}',
        MARKDOWN_ENHANCED
      );
      expect(lines.length).assertEqual(5);
      expect(lines[0].kind).assertEqual(MD_KIND_IMAGE);
      expect(lines[0].imageWidth).assertEqual(320);
      expect(lines[0].imageHeight).assertEqual(180);
      expect(lines[0].imagePercent).assertEqual(100);
      expect(lines[1].imageWidth).assertEqual(120);
      expect(lines[1].imageHeight).assertEqual(240);
      expect(lines[2].imageWidth).assertEqual(280);
      expect(lines[2].imageHeight === undefined).assertTrue();
      expect(lines[3].imageWidth).assertEqual(640);
      expect(lines[3].imageHeight).assertEqual(360);
      expect(lines[3].imagePercent).assertEqual(75);
      expect(lines[4].imagePercent).assertEqual(40);
    });

    it('clampsImagePercentagesToSafeBounds', 0, () => {
      const lines: MarkdownLine[] = parseMarkdownLines(
        '![small|1%](i:small)\n![large](i:large){width=999%}\n![edge|10%](i:edge)',
        MARKDOWN_ENHANCED
      );

      expect(lines[0].imagePercent).assertEqual(10);
      expect(lines[1].imagePercent).assertEqual(100);
      expect(lines[2].imagePercent).assertEqual(10);
    });

    it('doesNotParseImageMarkersInsideFencedCodeBlocks', 0, () => {
      const lines: MarkdownLine[] = parseMarkdownLines(
        '```markdown\n![not an attachment|50%](i:hidden)\n```',
        MARKDOWN_ENHANCED
      );

      expect(lines.length).assertEqual(1);
      expect(lines[0].kind).assertEqual(MD_KIND_CODE);
      expect(lines[0].imageId === undefined).assertTrue();
      expect(lines[0].text).assertEqual('![not an attachment|50%](i:hidden)');
    });

    it('keepsMalformedOrInlineImageMarkersAsText', 0, () => {
      const lines: MarkdownLine[] = parseMarkdownLines(
        'prefix ![inline](i:asset) suffix\n![remote](https://example.com/image.png)\n![bad](i:id){width=none}',
        MARKDOWN_ENHANCED
      );

      expect(lines.length).assertEqual(3);
      expect(lines[0].kind).assertEqual(MD_KIND_TEXT);
      expect(lines[1].kind).assertEqual(MD_KIND_TEXT);
      expect(lines[2].kind).assertEqual(MD_KIND_TEXT);
    });

    it('preservesBalancedParenthesesInExplicitMarkdownLinks', 0, () => {
      expect(findClickableUrl(
        '[v3.3 reference](https://example.com/docs_(v3.3))'
      )).assertEqual('https://example.com/docs_(v3.3)');
    });

    it('supportsProtocolCasePortsQueriesAndFragments', 0, () => {
      expect(findClickableUrl(
        'Open [service](HTTPS://Example.COM:8443/api?q=paper%20todo#capsule) now'
      )).assertEqual('HTTPS://Example.COM:8443/api?q=paper%20todo#capsule');
      expect(findClickableUrl('HTTP://example.com/path')).assertEqual('HTTP://example.com/path');
    });

    it('prefersExplicitLinksAndRejectsUnsupportedSchemes', 0, () => {
      expect(findClickableUrl(
        'https://bare.example/first then [chosen](https://explicit.example/second)'
      )).assertEqual('https://explicit.example/second');
      expect(findClickableUrl('ftp://example.com mailto:paper@example.com www.example.com') === undefined).assertTrue();
    });

    it('parsesImagesAcrossWhitespaceAndCrLfBoundaries', 0, () => {
      const lines: MarkdownLine[] = parseMarkdownLines(
        '  ![ first |25%](i:first_id)  \r\n\t![second](i:second-id){width=100%}\t',
        MARKDOWN_ENHANCED
      );

      expect(lines.length).assertEqual(2);
      expect(lines[0].kind).assertEqual(MD_KIND_IMAGE);
      expect(lines[0].imageAlt).assertEqual('first');
      expect(lines[0].imagePercent).assertEqual(25);
      expect(lines[1].kind).assertEqual(MD_KIND_IMAGE);
      expect(lines[1].imageId).assertEqual('second-id');
      expect(lines[1].imagePercent).assertEqual(100);
    });

    it('handlesImagePercentageAndIdentifierBoundaries', 0, () => {
      const lines: MarkdownLine[] = parseMarkdownLines(
        '![zero|0%](i:a)\n![exact|100%](i:A_0-9)\n![over|101%](i:b)\n' +
          '![four digits|1000%](i:c)\n![dot id](i:image.png)\n![slash id](i:path/image)',
        MARKDOWN_ENHANCED
      );

      expect(lines.length).assertEqual(6);
      expect(lines[0].kind).assertEqual(MD_KIND_IMAGE);
      expect(lines[0].imagePercent).assertEqual(10);
      expect(lines[1].kind).assertEqual(MD_KIND_IMAGE);
      expect(lines[1].imageId).assertEqual('A_0-9');
      expect(lines[1].imagePercent).assertEqual(100);
      expect(lines[2].kind).assertEqual(MD_KIND_IMAGE);
      expect(lines[2].imagePercent).assertEqual(100);
      expect(lines[3].kind).assertEqual(MD_KIND_TEXT);
      expect(lines[4].kind).assertEqual(MD_KIND_TEXT);
      expect(lines[5].kind).assertEqual(MD_KIND_TEXT);
    });

    it('doesNotTreatInlineCodeOrEmptyImageIdsAsAttachments', 0, () => {
      const lines: MarkdownLine[] = parseMarkdownLines(
        '`![code](i:hidden)`\n![empty](i:)\n![unicode](i:图片)',
        MARKDOWN_ENHANCED
      );

      expect(lines.length).assertEqual(3);
      expect(lines[0].kind).assertEqual(MD_KIND_TEXT);
      expect(lines[1].kind).assertEqual(MD_KIND_TEXT);
      expect(lines[2].kind).assertEqual(MD_KIND_TEXT);
    });

    it('keepsBalancedLinkRangesInsideNestedBoldMarkup', 0, () => {
      const tokens: MarkdownInlineToken[] = parseMarkdownInlineTokens(
        '**bold [site](https://e.test/x_(y))** and `https://code.test`'
      );

      expect(tokens.length).assertEqual(4);
      expect(tokens[1].kind).assertEqual(MD_INLINE_LINK);
      expect(tokens[1].text).assertEqual('site');
      expect(tokens[1].style.bold).assertTrue();
      expect(tokens[1].linkUrl).assertEqual('https://e.test/x_(y)');
      expect(tokens[1].linkSourceStart).assertEqual(7);
      expect(tokens[1].linkSourceEnd).assertEqual(35);
      expect(tokens[1].linkDisplayStart).assertEqual(5);
      expect(tokens[1].linkDisplayEnd).assertEqual(9);
      expect(tokens[3].kind).assertEqual(MD_INLINE_CODE);
      expect(tokens[3].linkUrl === undefined).assertTrue();
    });

    it('sharesOneLinkDisplayRangeAcrossStyledLabelTokens', 0, () => {
      const tokens: MarkdownInlineToken[] = parseMarkdownInlineTokens(
        '[**bold** and _italic_](https://example.com)'
      );

      expect(tokens.length).assertEqual(3);
      expect(tokens[0].style.bold).assertTrue();
      expect(tokens[2].style.italic).assertTrue();
      for (let i: number = 0; i < tokens.length; i++) {
        expect(tokens[i].kind).assertEqual(MD_INLINE_LINK);
        expect(tokens[i].linkDisplayStart).assertEqual(0);
        expect(tokens[i].linkDisplayEnd).assertEqual(15);
      }
    });

    it('keepsInlineCodeClickableWhenItBelongsToAnOuterLink', 0, () => {
      const tokens: MarkdownInlineToken[] = parseMarkdownInlineTokens(
        '[go `code`](https://example.com)'
      );

      expect(tokens.length).assertEqual(2);
      expect(tokens[0].kind).assertEqual(MD_INLINE_LINK);
      expect(tokens[1].kind).assertEqual(MD_INLINE_CODE);
      expect(tokens[1].style.code).assertTrue();
      expect(tokens[1].style.bold).assertFalse();
      expect(tokens[1].linkUrl).assertEqual('https://example.com');
      expect(tokens[1].linkDisplayStart).assertEqual(0);
      expect(tokens[1].linkDisplayEnd).assertEqual(7);
    });

    it('keepsRichTokensForLiteralAngleCharacters', 0, () => {
      const lines: MarkdownLine[] = parseMarkdownLines(
        '2 < 3 and **bold**; <https://one.example> then https://two.example',
        MARKDOWN_ENHANCED
      );
      expect(lines[0].inlineTokens !== undefined).assertTrue();
      const tokens: MarkdownInlineToken[] = lines[0].inlineTokens ?? [];
      let boldSeen: boolean = false;
      let linkCount: number = 0;
      for (let i: number = 0; i < tokens.length; i++) {
        boldSeen = boldSeen || (tokens[i].text === 'bold' && tokens[i].style.bold);
        if (tokens[i].linkUrl !== undefined) {
          linkCount += 1;
        }
      }
      expect(boldSeen).assertTrue();
      expect(linkCount).assertEqual(2);
    });

    it('matchesEditorListMarkersAndTabWhitespace', 0, () => {
      const lines: MarkdownLine[] = parseMarkdownLines(
        '-\titem\n1)\tordered\n+\tplus\n2)', MARKDOWN_ENHANCED
      );
      expect(lines[0].kind).assertEqual(MD_KIND_BULLET);
      expect(lines[0].text).assertEqual('• item');
      expect(lines[1].kind).assertEqual(MD_KIND_ORDERED);
      expect(lines[2].kind).assertEqual(MD_KIND_BULLET);
      expect(lines[2].text).assertEqual('• plus');
      expect(lines[3].kind).assertEqual(MD_KIND_ORDERED);
    });
  });
}
