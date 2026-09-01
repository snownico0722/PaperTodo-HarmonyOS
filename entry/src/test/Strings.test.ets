import { describe, expect, it } from '@ohos/hypium';
import {
  UI_LANGUAGE_EN,
  UI_LANGUAGE_JA,
  UI_LANGUAGE_KO,
  UI_LANGUAGE_SYSTEM,
  UI_LANGUAGE_ZH_CN
} from '../main/ets/common/Models';
import {
  formatText,
  languageLabel,
  normalizeLanguage,
  resolveLanguage,
  supportedLanguages,
  t,
  tf,
  tForSystem
} from '../main/ets/common/Strings';

const V3_3_LOCALIZED_KEYS: string[] = [
  'setting.imageCompression',
  'setting.hideLinkedPapersFromCapsules',
  'setting.globalHotkeys',
  'setting.globalHotkeysHint',
  'section.systemEntry',
  'setting.statusBarEntry',
  'action.retryStatusBar',
  'action.retryingStatusBar',
  'action.exit',
  'status.hotkeysIdle',
  'status.hotkeysActive',
  'status.hotkeysConflict',
  'status.hotkeysUnsupported',
  'status.hotkeysError',
  'status.statusBarActive',
  'status.statusBarUnknown',
  'status.statusBarUnsupported',
  'status.statusBarRetrying',
  'status.statusBarUncertain',
  'status.statusBarResidentError',
  'status.statusBarResidentRemoved',
  'status.statusBarRemoveError',
  'status.statusBarError',
  'status.quickLaunchPickerFailed',
  'status.quickLaunchPermissionFailed',
  'status.quickLaunchOpenFailed',
  'status.quickLaunchMissing',
  'status.quickLaunchDropUnsupported',
  'status.imagePickerFailed',
  'status.imageDropUnsupported',
  'status.imagePasteUnsupported',
  'status.imagePastePermissionFailed',
  'status.imageImporting',
  'status.imageImported',
  'status.imageInputTooLarge',
  'status.imageDimensionsTooLarge',
  'status.imageCompressionDisabled',
  'status.imageAnimatedTooLarge',
  'status.imageStorageFull',
  'status.imageOutputTooLarge',
  'status.imageInvalid',
  'status.imageImportFailed',
  'status.imageImportFailedGeneric',
  'quick.file',
  'quick.folder',
  'quick.unnamed',
  'image.filterLabel',
  'image.alt',
  'image.missing'
];

export default function stringsTest(): void {
  describe('StringsTest', () => {
    it('listsEverySupportedLanguageOnce', 0, () => {
      const languages: string[] = supportedLanguages();
      expect(languages.length).assertEqual(5);
      expect(languages[0]).assertEqual(UI_LANGUAGE_SYSTEM);
      expect(languages[1]).assertEqual(UI_LANGUAGE_ZH_CN);
      expect(languages[2]).assertEqual(UI_LANGUAGE_EN);
      expect(languages[3]).assertEqual(UI_LANGUAGE_JA);
      expect(languages[4]).assertEqual(UI_LANGUAGE_KO);
    });

    it('normalizesLocaleVariantsAndRejectsUnsupportedLocales', 0, () => {
      expect(normalizeLanguage(' zh_Hans_CN ')).assertEqual(UI_LANGUAGE_ZH_CN);
      expect(normalizeLanguage('en-US')).assertEqual(UI_LANGUAGE_EN);
      expect(normalizeLanguage('JA-jp')).assertEqual(UI_LANGUAGE_JA);
      expect(normalizeLanguage('ko_KR')).assertEqual(UI_LANGUAGE_KO);
      expect(normalizeLanguage('default')).assertEqual(UI_LANGUAGE_SYSTEM);
      expect(normalizeLanguage('fr-FR')).assertEqual(UI_LANGUAGE_SYSTEM);
    });

    it('resolvesSystemLanguageWithChineseAsTheSafeFallback', 0, () => {
      expect(resolveLanguage(UI_LANGUAGE_SYSTEM, 'en-GB')).assertEqual(UI_LANGUAGE_EN);
      expect(resolveLanguage(UI_LANGUAGE_SYSTEM, 'ja-JP')).assertEqual(UI_LANGUAGE_JA);
      expect(resolveLanguage(UI_LANGUAGE_SYSTEM, 'fr-FR')).assertEqual(UI_LANGUAGE_ZH_CN);
      expect(resolveLanguage(UI_LANGUAGE_KO, 'en-US')).assertEqual(UI_LANGUAGE_KO);
    });

    it('coversCoreAndImageStringsInEveryConcreteLocale', 0, () => {
      const languages: string[] = [
        UI_LANGUAGE_ZH_CN,
        UI_LANGUAGE_EN,
        UI_LANGUAGE_JA,
        UI_LANGUAGE_KO
      ];
      const keys: string[] = [
        'app.subtitle',
        'setting.capsule',
        'setting.hideLinkedPapersFromCapsules',
        'setting.imageCompression',
        'setting.externalOpenButton',
        'section.systemEntry',
        'setting.statusBarEntry',
        'action.retryStatusBar',
        'action.exit',
        'status.statusBarActive',
        'status.statusBarResidentRemoved',
        'status.quickLaunchOpenFailed',
        'status.quickLaunchDropUnsupported',
        'status.imageImporting',
        'status.imageImported',
        'status.imageInputTooLarge',
        'status.imageDimensionsTooLarge',
        'status.imageCompressionDisabled',
        'status.imageAnimatedTooLarge',
        'status.imageStorageFull',
        'status.imageOutputTooLarge',
        'status.imageInvalid',
        'status.imageImportFailed',
        'image.filterLabel',
        'image.alt',
        'image.missing'
      ];

      for (let languageIndex: number = 0; languageIndex < languages.length; languageIndex++) {
        for (let keyIndex: number = 0; keyIndex < keys.length; keyIndex++) {
          expect(t(languages[languageIndex], keys[keyIndex]).length > 0).assertTrue();
        }
      }
    });

    it('usesSharedGlyphsAndResolvesSystemTranslations', 0, () => {
      expect(t(UI_LANGUAGE_ZH_CN, 'app.name')).assertEqual('PaperTodo');
      expect(t(UI_LANGUAGE_EN, 'glyph.image')).assertEqual('▧');
      expect(t(UI_LANGUAGE_JA, 'markdown.shortEnhanced')).assertEqual('MD+');
      expect(tForSystem(UI_LANGUAGE_SYSTEM, 'ko-KR', 'language.system')).assertEqual('시스템 설정 사용');
    });

    it('formatsNamedPlaceholdersAndLocalizedLabels', 0, () => {
      expect(formatText('Supports {count} papers', 'count', '100')).assertEqual('Supports 100 papers');
      expect(tf(UI_LANGUAGE_EN, 'status.paperLimit', 'count', '100')).assertEqual(
        'Up to 100 papers are supported.'
      );
      expect(languageLabel(UI_LANGUAGE_JA, UI_LANGUAGE_EN)).assertEqual('Japanese');
      expect(languageLabel(UI_LANGUAGE_SYSTEM, UI_LANGUAGE_KO)).assertEqual('시스템 설정 사용');
    });

    it('keepsEveryV33KeyLocalizedAcrossAllCatalogs', 0, () => {
      const localizedLanguages: string[] = [UI_LANGUAGE_EN, UI_LANGUAGE_JA, UI_LANGUAGE_KO];
      for (let keyIndex: number = 0; keyIndex < V3_3_LOCALIZED_KEYS.length; keyIndex++) {
        const key: string = V3_3_LOCALIZED_KEYS[keyIndex];
        const chineseText: string = t(UI_LANGUAGE_ZH_CN, key);
        expect(chineseText.length > 0).assertTrue();
        for (let languageIndex: number = 0; languageIndex < localizedLanguages.length; languageIndex++) {
          const localizedText: string = t(localizedLanguages[languageIndex], key);
          expect(localizedText.length > 0).assertTrue();
          expect(localizedText === chineseText).assertFalse();
        }
      }
    });

    it('keepsErrorPlaceholdersConsistentForNewStatusKeys', 0, () => {
      const errorKeys: string[] = [
        'status.quickLaunchPickerFailed',
        'status.quickLaunchPermissionFailed',
        'status.quickLaunchOpenFailed',
        'status.imagePickerFailed',
        'status.imageImportFailed'
      ];
      const languages: string[] = [UI_LANGUAGE_ZH_CN, UI_LANGUAGE_EN, UI_LANGUAGE_JA, UI_LANGUAGE_KO];
      for (let keyIndex: number = 0; keyIndex < errorKeys.length; keyIndex++) {
        for (let languageIndex: number = 0; languageIndex < languages.length; languageIndex++) {
          const template: string = t(languages[languageIndex], errorKeys[keyIndex]);
          expect(template.indexOf('{error}') >= 0).assertTrue();
          expect(formatText(template, 'error', 'E_TEST').indexOf('{error}') < 0).assertTrue();
          expect(formatText(template, 'error', 'E_TEST').indexOf('E_TEST') >= 0).assertTrue();
        }
      }
    });
  });
}
