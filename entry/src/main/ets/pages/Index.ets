import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { unifiedDataChannel } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  COLOR_SCHEME_FOREST,
  COLOR_SCHEME_INK,
  COLOR_SCHEME_SUNSET,
  COLOR_SCHEME_WARM,
  MARKDOWN_BASIC,
  MARKDOWN_ENHANCED,
  MARKDOWN_OFF,
  MAX_PAPERS,
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  PaperData,
  RESIZE_GRIP_HIDDEN,
  RESIZE_GRIP_SOFT,
  RESIZE_GRIP_STANDARD,
  THEME_DARK,
  THEME_LIGHT,
  THEME_SYSTEM,
  TODO_VISUAL_LARGE,
  TODO_VISUAL_MEDIUM,
  TODO_VISUAL_SMALL,
  TODO_VISUAL_XLARGE,
  VISUAL_TEXT_LARGE,
  VISUAL_TEXT_MEDIUM,
  VISUAL_TEXT_SMALL
} from '../common/Models';
import { GlobalHotkeys } from '../common/GlobalHotkeys';
import { createPaperLinkDragData } from '../common/PaperLinkDrag';
import { PaperStore } from '../common/PaperStore';
import { formatText, languageLabel, resolveLanguage, supportedLanguages, tForSystem } from '../common/Strings';
import { ThemePalette, resolvePalette } from '../common/ThemePalette';

@Entry
@Component
struct Index {
  @StorageLink('uiLanguage') @Watch('onUiLanguageChanged') uiLanguage: string = 'system';
  @StorageLink('systemLanguage') systemLanguage: string = 'zh-CN';
  @StorageLink('theme') theme: string = THEME_SYSTEM;
  @StorageLink('colorScheme') colorScheme: string = COLOR_SCHEME_WARM;
  @StorageLink('markdownRenderMode') markdownRenderMode: string = MARKDOWN_ENHANCED;
  @StorageLink('useCapsuleMode') useCapsuleMode: boolean = true;
  @StorageLink('useDeepCapsuleMode') useDeepCapsuleMode: boolean = true;
  @StorageLink('todoVisualSize') todoVisualSize: string = TODO_VISUAL_MEDIUM;
  @StorageLink('autoClearCompletedTodos') autoClearCompletedTodos: boolean = false;
  @StorageLink('autoBottomCompleted') autoBottomCompleted: boolean = false;
  @StorageLink('autoCompressLargeImages') autoCompressLargeImages: boolean = true;
  @StorageLink('globalHotkeysEnabled') globalHotkeysEnabled: boolean = false;
  @StorageLink('globalHotkeyStatus') globalHotkeyStatus: string = 'idle';
  @StorageLink('capsuleGap') capsuleGap: number = 4;
  @StorageLink('enableAnimations') enableAnimations: boolean = true;
  @StorageLink('rememberEdgeExpandedPosition') rememberEdgeExpandedPosition: boolean = true;
  @StorageLink('collapseExpandedEdgeCapsuleOnClick') collapseExpandedEdgeCapsuleOnClick: boolean = false;
  @StorageLink('hideEdgeCapsuleCloseButtonOnHover') hideEdgeCapsuleCloseButtonOnHover: boolean = false;
  @StorageLink('edgeCapsuleTitleCharacterLimit') edgeCapsuleTitleCharacterLimit: number = 0;
  @StorageLink('enablePaperLinks') enablePaperLinks: boolean = true;
  @StorageLink('overallFontScale') overallFontScale: number = 1;
  @StorageLink('noteTextSize') noteTextSize: string = VISUAL_TEXT_MEDIUM;
  @StorageLink('noteTextBold') noteTextBold: boolean = false;
  @StorageLink('todoTextBold') todoTextBold: boolean = false;
  @StorageLink('titleTextSize') titleTextSize: string = VISUAL_TEXT_MEDIUM;
  @StorageLink('titleTextBold') titleTextBold: boolean = true;
  @StorageLink('capsuleTextSize') capsuleTextSize: string = VISUAL_TEXT_MEDIUM;
  @StorageLink('capsuleTextBold') capsuleTextBold: boolean = false;
  @StorageLink('resizeGripMode') resizeGripMode: string = RESIZE_GRIP_SOFT;
  @StorageLink('showTopBarNewTodoButton') showTopBarNewTodoButton: boolean = true;
  @StorageLink('showTopBarNewNoteButton') showTopBarNewNoteButton: boolean = true;
  @StorageLink('showTopBarExternalOpenButton') showTopBarExternalOpenButton: boolean = true;
  @StorageLink('paperRevision') @Watch('onPaperRevision') paperRevision: number = 0;
  @StorageLink('systemColorMode') systemColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  @State papers: PaperData[] = [];
  @State confirmDeleteId: string = '';
  @State statusMessage: string = '';
  @State selectedPanel: string = 'papers';

  aboutToAppear(): void {
    PaperStore.initialize(this.hostContext());
    this.refresh();
    if (PaperStore.hasStorageError()) {
      this.statusMessage = this.text('status.storageProtectionDetected');
    }
  }

  aboutToDisappear(): void {
    PaperStore.flushNow();
  }

  onPageShow(): void {
    this.refresh();
  }

  private onPaperRevision(): void {
    this.refresh();
  }

  private onUiLanguageChanged(): void {
    this.statusMessage = PaperStore.hasStorageError() ? this.text('status.storageProtectionDetected') : '';
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private refresh(): void {
    this.papers = PaperStore.listPapers();
  }

  private text(key: string): string {
    return tForSystem(this.uiLanguage, this.systemLanguage, key);
  }

  private formatted(key: string, name: string, value: string): string {
    return formatText(this.text(key), name, value);
  }

  private enabledLabel(enabled: boolean): string {
    return this.text(enabled ? 'value.enabled' : 'value.disabled');
  }

  private visibleLabel(visible: boolean): string {
    return this.text(visible ? 'value.visible' : 'value.hidden');
  }

  private isDark(): boolean {
    if (this.theme === THEME_DARK) {
      return true;
    }
    if (this.theme === THEME_LIGHT) {
      return false;
    }
    return this.systemColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private palette(): ThemePalette {
    return resolvePalette(this.colorScheme, this.isDark());
  }

  private pageBackgroundColor(): string {
    return this.palette().pageBackground;
  }

  private cardColor(): string {
    return this.palette().paper;
  }

  private textColor(): string {
    return this.palette().text;
  }

  private mutedColor(): string {
    return this.palette().muted;
  }

  private cardBorderColor(): string {
    return this.palette().border;
  }

  private primaryButtonColor(): string {
    return this.palette().primary;
  }

  private primaryButtonTextColor(): string {
    return this.palette().primaryText;
  }

  private startPaper(paperId: string, command: string = 'show'): void {
    const want: Want = {
      bundleName: 'com.snownico.papertodo',
      moduleName: 'entry',
      abilityName: 'PaperAbility',
      parameters: {
        paperId: paperId,
        paperCommand: command
      }
    };
    this.hostContext().startAbility(want).catch((error: BusinessError): void => {
      this.statusMessage = this.formatted('status.openPaperFailed', 'error', error.message);
    });
  }

  private isPaperOpen(id: string): boolean {
    return AppStorage.get<boolean>('paperOpen:' + id) === true;
  }

  private createPaper(type: string): void {
    const paper: PaperData | null = PaperStore.createPaper(type);
    if (paper === null) {
      this.statusMessage = PaperStore.hasStorageError() ?
        this.text('status.createBlockedByProtection') :
        this.formatted('status.paperLimit', 'count', MAX_PAPERS.toString());
      return;
    }
    this.statusMessage = '';
    this.refresh();
    this.startPaper(paper.id);
  }

  private showPaper(paper: PaperData): void {
    PaperStore.setPaperVisible(paper.id, true);
    this.refresh();
    this.startPaper(paper.id, 'show');
  }

  private hidePaper(paper: PaperData): void {
    PaperStore.setPaperVisible(paper.id, false);
    if (this.isPaperOpen(paper.id)) {
      this.startPaper(paper.id, 'hide');
    }
    this.refresh();
  }

  private showAll(): void {
    const snapshot: PaperData[] = PaperStore.listPapers();
    for (let i: number = 0; i < snapshot.length; i++) {
      PaperStore.setPaperVisible(snapshot[i].id, true);
      this.startPaper(snapshot[i].id, 'show');
    }
    this.refresh();
  }

  private hideAll(): void {
    const snapshot: PaperData[] = PaperStore.listPapers();
    for (let i: number = 0; i < snapshot.length; i++) {
      const paper: PaperData = snapshot[i];
      PaperStore.setPaperVisible(paper.id, false);
      if (this.isPaperOpen(paper.id)) {
        this.startPaper(paper.id, 'hide');
      }
    }
    this.refresh();
  }

  private deletePaper(paper: PaperData): void {
    if (this.confirmDeleteId !== paper.id) {
      this.confirmDeleteId = paper.id;
      return;
    }
    this.confirmDeleteId = '';
    if (this.isPaperOpen(paper.id)) {
      this.startPaper(paper.id, 'delete');
    } else {
      PaperStore.deletePaper(paper.id);
    }
    setTimeout((): void => this.refresh(), 80);
  }

  private cycleTheme(): void {
    if (this.theme === THEME_SYSTEM) {
      PaperStore.setTheme(THEME_LIGHT);
    } else if (this.theme === THEME_LIGHT) {
      PaperStore.setTheme(THEME_DARK);
    } else {
      PaperStore.setTheme(THEME_SYSTEM);
    }
  }

  private cycleLanguage(): void {
    const languages: string[] = supportedLanguages();
    let selectedIndex: number = 0;
    for (let i: number = 0; i < languages.length; i++) {
      if (languages[i] === this.uiLanguage) {
        selectedIndex = i;
        break;
      }
    }
    PaperStore.setUiLanguage(languages[(selectedIndex + 1) % languages.length]);
  }

  private currentLanguageLabel(): string {
    return languageLabel(this.uiLanguage, resolveLanguage(this.uiLanguage, this.systemLanguage));
  }

  private themeLabel(): string {
    if (this.theme === THEME_LIGHT) {
      return this.text('value.light');
    }
    if (this.theme === THEME_DARK) {
      return this.text('value.dark');
    }
    return this.text('value.system');
  }

  private cycleColorScheme(): void {
    if (this.colorScheme === COLOR_SCHEME_WARM) {
      PaperStore.setColorScheme(COLOR_SCHEME_INK);
    } else if (this.colorScheme === COLOR_SCHEME_INK) {
      PaperStore.setColorScheme(COLOR_SCHEME_FOREST);
    } else if (this.colorScheme === COLOR_SCHEME_FOREST) {
      PaperStore.setColorScheme(COLOR_SCHEME_SUNSET);
    } else {
      PaperStore.setColorScheme(COLOR_SCHEME_WARM);
    }
  }

  private colorSchemeLabel(): string {
    if (this.colorScheme === COLOR_SCHEME_INK) {
      return this.text('value.ink');
    }
    if (this.colorScheme === COLOR_SCHEME_FOREST) {
      return this.text('value.forest');
    }
    if (this.colorScheme === COLOR_SCHEME_SUNSET) {
      return this.text('value.sunset');
    }
    return this.text('value.warmPaper');
  }

  private cycleMarkdownMode(): void {
    if (this.markdownRenderMode === MARKDOWN_OFF) {
      PaperStore.setMarkdownMode(MARKDOWN_BASIC);
    } else if (this.markdownRenderMode === MARKDOWN_BASIC) {
      PaperStore.setMarkdownMode(MARKDOWN_ENHANCED);
    } else {
      PaperStore.setMarkdownMode(MARKDOWN_OFF);
    }
  }

  private markdownLabel(): string {
    if (this.markdownRenderMode === MARKDOWN_OFF) {
      return this.text('value.markdownOff');
    }
    if (this.markdownRenderMode === MARKDOWN_BASIC) {
      return this.text('value.markdownBasic');
    }
    return this.text('value.markdownEnhanced');
  }

  private toggleCapsule(): void {
    PaperStore.setCapsuleMode(!this.useCapsuleMode);
  }

  private toggleDeepCapsule(): void {
    PaperStore.setDeepCapsuleMode(!this.useDeepCapsuleMode);
  }

  private cycleTodoVisualSize(): void {
    if (this.todoVisualSize === TODO_VISUAL_SMALL) {
      PaperStore.setTodoVisualSize(TODO_VISUAL_MEDIUM);
    } else if (this.todoVisualSize === TODO_VISUAL_MEDIUM) {
      PaperStore.setTodoVisualSize(TODO_VISUAL_LARGE);
    } else if (this.todoVisualSize === TODO_VISUAL_LARGE) {
      PaperStore.setTodoVisualSize(TODO_VISUAL_XLARGE);
    } else {
      PaperStore.setTodoVisualSize(TODO_VISUAL_SMALL);
    }
  }

  private todoVisualSizeLabel(): string {
    if (this.todoVisualSize === TODO_VISUAL_SMALL) {
      return this.text('value.small');
    }
    if (this.todoVisualSize === TODO_VISUAL_LARGE) {
      return this.text('value.large');
    }
    if (this.todoVisualSize === TODO_VISUAL_XLARGE) {
      return this.text('value.extraLarge');
    }
    return this.text('value.medium');
  }

  private toggleAutoBottomCompleted(): void {
    PaperStore.setAutoBottomCompleted(!this.autoBottomCompleted);
  }

  private toggleAutoClearCompleted(): void {
    PaperStore.setAutoClearCompleted(!this.autoClearCompletedTodos);
  }

  private toggleAutoCompressImages(): void {
    PaperStore.setAutoCompressLargeImages(!this.autoCompressLargeImages);
  }

  private toggleGlobalHotkeys(): void {
    const enabled: boolean = !this.globalHotkeysEnabled;
    PaperStore.setGlobalHotkeysEnabled(enabled);
    GlobalHotkeys.setEnabled(enabled);
  }

  private globalHotkeyStatusLabel(): string {
    if (this.globalHotkeyStatus === 'active') {
      return this.text('status.hotkeysActive');
    }
    if (this.globalHotkeyStatus === 'conflict') {
      return this.text('status.hotkeysConflict');
    }
    if (this.globalHotkeyStatus === 'unsupported') {
      return this.text('status.hotkeysUnsupported');
    }
    if (this.globalHotkeyStatus === 'error') {
      return this.text('status.hotkeysError');
    }
    return this.text('status.hotkeysIdle');
  }

  private cycleCapsuleGap(): void {
    if (this.capsuleGap === 0) {
      PaperStore.setCapsuleGap(4);
    } else if (this.capsuleGap === 4) {
      PaperStore.setCapsuleGap(8);
    } else {
      PaperStore.setCapsuleGap(0);
    }
  }

  private toggleAnimations(): void {
    PaperStore.setAnimationsEnabled(!this.enableAnimations);
  }

  private toggleRememberExpandedPosition(): void {
    PaperStore.setRememberEdgeExpandedPosition(!this.rememberEdgeExpandedPosition);
  }

  private toggleRepeatEdgeClick(): void {
    PaperStore.setCollapseExpandedEdgeCapsuleOnClick(!this.collapseExpandedEdgeCapsuleOnClick);
  }

  private toggleHoverCloseButton(): void {
    PaperStore.setHideEdgeCapsuleCloseButtonOnHover(!this.hideEdgeCapsuleCloseButtonOnHover);
  }

  private cycleEdgeTitleLimit(): void {
    if (this.edgeCapsuleTitleCharacterLimit === 0) {
      PaperStore.setEdgeCapsuleTitleCharacterLimit(8);
    } else if (this.edgeCapsuleTitleCharacterLimit === 8) {
      PaperStore.setEdgeCapsuleTitleCharacterLimit(12);
    } else if (this.edgeCapsuleTitleCharacterLimit === 12) {
      PaperStore.setEdgeCapsuleTitleCharacterLimit(16);
    } else {
      PaperStore.setEdgeCapsuleTitleCharacterLimit(0);
    }
  }

  private edgeTitleLimitLabel(): string {
    return this.edgeCapsuleTitleCharacterLimit === 0 ? this.text('value.all') :
      this.formatted('value.characters', 'count', this.edgeCapsuleTitleCharacterLimit.toString());
  }

  private togglePaperLinks(): void {
    PaperStore.setPaperLinksEnabled(!this.enablePaperLinks);
  }

  private cycleOverallFontScale(): void {
    const next: number = this.overallFontScale >= 1.2 ? 0.8 : this.overallFontScale + 0.05;
    PaperStore.setOverallFontScale(next);
  }

  private nextVisualTextSize(size: string): string {
    if (size === VISUAL_TEXT_SMALL) {
      return VISUAL_TEXT_MEDIUM;
    }
    if (size === VISUAL_TEXT_MEDIUM) {
      return VISUAL_TEXT_LARGE;
    }
    return VISUAL_TEXT_SMALL;
  }

  private visualTextSizeLabel(size: string): string {
    if (size === VISUAL_TEXT_SMALL) {
      return this.text('value.small');
    }
    if (size === VISUAL_TEXT_LARGE) {
      return this.text('value.large');
    }
    return this.text('value.medium');
  }

  private cycleNoteTextSize(): void {
    PaperStore.setNoteTextAppearance(this.nextVisualTextSize(this.noteTextSize), this.noteTextBold);
  }

  private toggleNoteTextBold(): void {
    PaperStore.setNoteTextAppearance(this.noteTextSize, !this.noteTextBold);
  }

  private toggleTodoTextBold(): void {
    PaperStore.setTodoTextBold(!this.todoTextBold);
  }

  private cycleTitleTextSize(): void {
    PaperStore.setTitleTextAppearance(this.nextVisualTextSize(this.titleTextSize), this.titleTextBold);
  }

  private toggleTitleTextBold(): void {
    PaperStore.setTitleTextAppearance(this.titleTextSize, !this.titleTextBold);
  }

  private cycleCapsuleTextSize(): void {
    PaperStore.setCapsuleTextAppearance(this.nextVisualTextSize(this.capsuleTextSize), this.capsuleTextBold);
  }

  private toggleCapsuleTextBold(): void {
    PaperStore.setCapsuleTextAppearance(this.capsuleTextSize, !this.capsuleTextBold);
  }

  private cycleResizeGrip(): void {
    if (this.resizeGripMode === RESIZE_GRIP_STANDARD) {
      PaperStore.setResizeGripMode(RESIZE_GRIP_SOFT);
    } else if (this.resizeGripMode === RESIZE_GRIP_SOFT) {
      PaperStore.setResizeGripMode(RESIZE_GRIP_HIDDEN);
    } else {
      PaperStore.setResizeGripMode(RESIZE_GRIP_STANDARD);
    }
  }

  private resizeGripLabel(): string {
    if (this.resizeGripMode === RESIZE_GRIP_STANDARD) {
      return this.text('value.resizeStandard');
    }
    if (this.resizeGripMode === RESIZE_GRIP_HIDDEN) {
      return this.text('value.resizeHidden');
    }
    return this.text('value.resizeSoft');
  }

  private toggleNewTodoButton(): void {
    PaperStore.setTopBarButtons(!this.showTopBarNewTodoButton, this.showTopBarNewNoteButton);
  }

  private toggleNewNoteButton(): void {
    PaperStore.setTopBarButtons(this.showTopBarNewTodoButton, !this.showTopBarNewNoteButton);
  }

  private toggleExternalOpenButton(): void {
    PaperStore.setExternalOpenButton(!this.showTopBarExternalOpenButton);
  }

  private restoreBackup(): void {
    PaperStore.flushNow();
    const current: PaperData[] = PaperStore.listPapers();
    if (!PaperStore.restoreBackup()) {
      this.statusMessage = this.text('status.noValidBackup');
      return;
    }
    for (let i: number = 0; i < current.length; i++) {
      if (this.isPaperOpen(current[i].id)) {
        this.startPaper(current[i].id, 'close');
      }
    }
    GlobalHotkeys.setEnabled(PaperStore.loadState().globalHotkeysEnabled);
    this.statusMessage = this.text('status.backupRestored');
    this.refresh();
    setTimeout((): void => {
      const restored: PaperData[] = PaperStore.listPapers();
      for (let i: number = 0; i < restored.length; i++) {
        if (restored[i].isVisible) {
          this.startPaper(restored[i].id, 'show');
        }
      }
    }, 180);
  }

  private paperTitle(paper: PaperData): string {
    if (paper.title.trim().length > 0) {
      return paper.title.trim();
    }
    if (paper.type === PAPER_TYPE_NOTE) {
      const firstLine: string = paper.content.split('\n')[0].trim();
      return firstLine.length > 0 ? firstLine : this.text('paper.unnamedNote');
    }
    for (let i: number = 0; i < paper.items.length; i++) {
      if (paper.items[i].text.trim().length > 0) {
        return paper.items[i].text.trim();
      }
    }
    return this.text('paper.unnamedTodo');
  }

  private paperMeta(paper: PaperData): string {
    const parts: string[] = [];
    parts.push(this.text(paper.type === PAPER_TYPE_NOTE ? 'paper.notePaper' : 'paper.todoPaper'));
    parts.push(this.text(paper.isVisible ? 'paper.visible' : 'paper.hidden'));
    if (paper.alwaysOnTop) {
      parts.push(this.text('paper.topmost'));
    }
    if (paper.isCollapsed) {
      parts.push(this.text('paper.capsule'));
    }
    return parts.join(' · ');
  }

  private beginPaperLinkDrag(event: DragEvent, paper: PaperData): DragItemInfo {
    const data: unifiedDataChannel.UnifiedData = createPaperLinkDragData(
      paper.id,
      paper.type,
      this.paperTitle(paper)
    );
    event.setData(data);
    event.dragBehavior = DragBehavior.COPY;
    return { extraInfo: paper.id };
  }

  @Builder
  private SettingButton(label: string, action: () => void) {
    Button(label)
      .height(48)
      .constraintSize({ maxWidth: '100%' })
      .fontSize(11)
      .labelStyle({
        overflow: TextOverflow.Ellipsis,
        maxLines: 2,
        minFontSize: 10,
        maxFontSize: 11,
        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST
      })
      .fontColor(this.textColor())
      .backgroundColor(this.cardColor())
      .border({ width: 1, color: this.cardBorderColor() })
      .borderRadius(9)
      .margin({ right: 6, bottom: 8 })
      .onClick(action)
  }

  @Builder
  private PanelTab(label: string, panel: string) {
    Button(label)
      .layoutWeight(1)
      .height(34)
      .fontSize(11)
      .labelStyle({
        overflow: TextOverflow.Ellipsis,
        maxLines: 1,
        minFontSize: 9,
        maxFontSize: 11,
        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST
      })
      .fontColor(this.selectedPanel === panel ? this.primaryButtonTextColor() : this.textColor())
      .backgroundColor(this.selectedPanel === panel ? this.primaryButtonColor() : this.cardColor())
      .border({ width: 1, color: this.cardBorderColor() })
      .borderRadius(9)
      .onClick((): void => {
        this.selectedPanel = panel;
      })
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text(this.text('app.name'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontSize(30)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.textColor())
          Text(this.text('app.subtitle'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontSize(12)
            .fontColor(this.mutedColor())
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
        .alignItems(HorizontalAlign.Start)
        Button(this.text('action.newTodo'))
          .height(40)
          .fontSize(13)
          .labelStyle({
            overflow: TextOverflow.Ellipsis,
            maxLines: 1,
            minFontSize: 10,
            maxFontSize: 13,
            heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST
          })
          .fontColor(this.primaryButtonTextColor())
          .backgroundColor(this.primaryButtonColor())
          .borderRadius(10)
          .margin({ left: 8 })
          .onClick((): void => this.createPaper(PAPER_TYPE_TODO))
        Button(this.text('action.newNote'))
          .height(40)
          .fontSize(13)
          .labelStyle({
            overflow: TextOverflow.Ellipsis,
            maxLines: 1,
            minFontSize: 10,
            maxFontSize: 13,
            heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST
          })
          .fontColor(this.primaryButtonTextColor())
          .backgroundColor(this.primaryButtonColor())
          .borderRadius(10)
          .margin({ left: 8 })
          .onClick((): void => this.createPaper(PAPER_TYPE_NOTE))
      }
      .width('100%')

      Row({ space: 6 }) {
        this.PanelTab(this.text('tab.papers'), 'papers')
        this.PanelTab(this.text('tab.basic'), 'behavior')
        this.PanelTab(this.text('tab.capsule'), 'capsule')
        this.PanelTab(this.text('tab.visual'), 'visual')
      }
      .width('100%')
      .margin({ top: 14 })

      if (this.selectedPanel === 'papers') {
        Row({ space: 8 }) {
          Button(this.text('action.showAll'))
            .height(36)
            .fontSize(12)
            .onClick((): void => this.showAll())
          Button(this.text('action.hideAll'))
            .height(36)
            .fontSize(12)
            .onClick((): void => this.hideAll())
          Blank()
          Button(this.text('action.restoreBackup'))
            .height(36)
            .fontSize(12)
            .fontColor(this.mutedColor())
            .backgroundColor(Color.Transparent)
            .onClick((): void => this.restoreBackup())
        }
        .width('100%')
        .margin({ top: 12 })
      }

      if (this.selectedPanel === 'behavior') {
        Scroll() {
          Column() {
            Text(this.text('section.basicBehavior'))
              .width('100%')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.mutedColor())
              .margin({ bottom: 6 })
            Flex({ wrap: FlexWrap.Wrap }) {
              this.SettingButton(this.text('setting.language') + this.currentLanguageLabel(),
                (): void => this.cycleLanguage())
              this.SettingButton(this.text('setting.theme') + this.themeLabel(), (): void => this.cycleTheme())
              this.SettingButton(this.text('setting.colorScheme') + this.colorSchemeLabel(),
                (): void => this.cycleColorScheme())
              this.SettingButton(this.text('setting.markdown') + this.markdownLabel(),
                (): void => this.cycleMarkdownMode())
              this.SettingButton(this.text('setting.todoSize') + this.todoVisualSizeLabel(),
                (): void => this.cycleTodoVisualSize())
              this.SettingButton(this.text('setting.clearAfterComplete') +
                this.enabledLabel(this.autoClearCompletedTodos), (): void => this.toggleAutoClearCompleted())
              this.SettingButton(this.text('setting.completedToBottom') + this.enabledLabel(this.autoBottomCompleted),
                (): void => this.toggleAutoBottomCompleted())
              this.SettingButton(this.text('setting.imageCompression') +
                this.enabledLabel(this.autoCompressLargeImages), (): void => this.toggleAutoCompressImages())
              this.SettingButton(this.text('setting.globalHotkeys') +
                this.enabledLabel(this.globalHotkeysEnabled), (): void => this.toggleGlobalHotkeys())
              this.SettingButton(this.text('setting.paperLinks') + this.enabledLabel(this.enablePaperLinks),
                (): void => this.togglePaperLinks())
              this.SettingButton(this.text('setting.animations') + this.enabledLabel(this.enableAnimations),
                (): void => this.toggleAnimations())
              this.SettingButton(this.text('setting.newTodoButton') +
                this.visibleLabel(this.showTopBarNewTodoButton), (): void => this.toggleNewTodoButton())
              this.SettingButton(this.text('setting.newNoteButton') +
                this.visibleLabel(this.showTopBarNewNoteButton), (): void => this.toggleNewNoteButton())
              this.SettingButton(this.text('setting.externalOpenButton') +
                this.visibleLabel(this.showTopBarExternalOpenButton), (): void => this.toggleExternalOpenButton())
            }
            .width('100%')
            Text(this.globalHotkeyStatusLabel())
              .width('100%')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.textColor())
              .margin({ top: 8 })
            Text(this.text('setting.globalHotkeysHint'))
              .width('100%')
              .fontSize(11)
              .fontColor(this.mutedColor())
              .margin({ top: 4 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: 4 })
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ top: 12 })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }

      if (this.selectedPanel === 'capsule') {
        Scroll() {
          Column() {
            Text(this.text('section.singleScreenRightQueue'))
              .width('100%')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.mutedColor())
              .margin({ bottom: 6 })
            Flex({ wrap: FlexWrap.Wrap }) {
              this.SettingButton(this.text('setting.capsule') + this.enabledLabel(this.useCapsuleMode),
                (): void => this.toggleCapsule())
              this.SettingButton(this.text('setting.autoDockEdge') + this.enabledLabel(this.useDeepCapsuleMode),
                (): void => this.toggleDeepCapsule())
              this.SettingButton(this.text('setting.capsuleGap') + this.capsuleGap.toString(),
                (): void => this.cycleCapsuleGap())
              this.SettingButton(this.text('setting.rememberExpandedPosition') +
                this.enabledLabel(this.rememberEdgeExpandedPosition),
                (): void => this.toggleRememberExpandedPosition())
              this.SettingButton(this.text('setting.collapseOnSecondClick') +
                this.enabledLabel(this.collapseExpandedEdgeCapsuleOnClick), (): void => this.toggleRepeatEdgeClick())
              this.SettingButton(this.text('setting.hideCloseOnHover') +
                this.enabledLabel(this.hideEdgeCapsuleCloseButtonOnHover),
                (): void => this.toggleHoverCloseButton())
              this.SettingButton(this.text('setting.edgeTitle') + this.edgeTitleLimitLabel(),
                (): void => this.cycleEdgeTitleLimit())
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: 4 })
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ top: 12 })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }

      if (this.selectedPanel === 'visual') {
        Scroll() {
          Column() {
            Text(this.text('section.visual'))
              .width('100%')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.mutedColor())
              .margin({ bottom: 6 })
            Flex({ wrap: FlexWrap.Wrap }) {
              this.SettingButton(this.text('setting.overallFontSize') +
                Math.round(this.overallFontScale * 100).toString() + '%',
                (): void => this.cycleOverallFontScale())
              this.SettingButton(this.text('setting.noteFontSize') + this.visualTextSizeLabel(this.noteTextSize),
                (): void => this.cycleNoteTextSize())
              this.SettingButton(this.text('setting.noteBold') + this.enabledLabel(this.noteTextBold),
                (): void => this.toggleNoteTextBold())
              this.SettingButton(this.text('setting.todoBold') + this.enabledLabel(this.todoTextBold),
                (): void => this.toggleTodoTextBold())
              this.SettingButton(this.text('setting.titleFontSize') + this.visualTextSizeLabel(this.titleTextSize),
                (): void => this.cycleTitleTextSize())
              this.SettingButton(this.text('setting.titleBold') + this.enabledLabel(this.titleTextBold),
                (): void => this.toggleTitleTextBold())
              this.SettingButton(this.text('setting.capsuleFontSize') +
                this.visualTextSizeLabel(this.capsuleTextSize), (): void => this.cycleCapsuleTextSize())
              this.SettingButton(this.text('setting.capsuleBold') + this.enabledLabel(this.capsuleTextBold),
                (): void => this.toggleCapsuleTextBold())
              this.SettingButton(this.text('setting.resizeHandle') + this.resizeGripLabel(),
                (): void => this.cycleResizeGrip())
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: 4 })
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ top: 12 })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }

      if (this.statusMessage.length > 0) {
        Text(this.statusMessage)
          .width('100%')
          .fontSize(12)
          .fontColor(PaperStore.hasStorageError() ? '#B42318' : this.mutedColor())
          .margin({ top: 6 })
      }

      if (this.selectedPanel === 'papers' && this.papers.length === 0) {
        Column() {
          Text(this.text(PaperStore.hasStorageError() ? 'empty.storageProtectionTitle' : 'empty.noPapersTitle'))
            .fontSize(18)
            .fontColor(this.textColor())
          Text(this.text(PaperStore.hasStorageError() ? 'empty.storageProtectionBody' : 'empty.noPapersBody'))
            .fontSize(13)
            .fontColor(this.mutedColor())
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.selectedPanel === 'papers') {
        List({ space: 8 }) {
          ForEach(this.papers, (paper: PaperData) => {
            ListItem() {
              Row() {
                Text('⠿')
                  .width(28)
                  .height(40)
                  .textAlign(TextAlign.Center)
                  .fontSize(15)
                  .fontColor(this.mutedColor())
                  .backgroundColor(this.pageBackgroundColor())
                  .borderRadius(8)
                  .margin({ right: 6 })
                  .draggable(true)
                  .onDragStart((event: DragEvent): DragItemInfo => this.beginPaperLinkDrag(event, paper))
                Text(paper.type === PAPER_TYPE_NOTE ? '✎' : '☑')
                  .width(28)
                  .fontSize(18)
                  .fontColor(this.textColor())
                Column() {
                  Text(this.paperTitle(paper))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .fontSize(14)
                    .fontColor(this.textColor())
                  Text(this.paperMeta(paper))
                    .fontSize(11)
                    .fontColor(this.mutedColor())
                    .margin({ top: 3 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Button(this.text(paper.isVisible ? 'action.focus' : 'action.show'))
                  .height(32)
                  .fontSize(11)
                  .onClick((): void => this.showPaper(paper))
                if (paper.isVisible) {
                  Button(this.text('action.hide'))
                    .height(32)
                    .fontSize(11)
                    .margin({ left: 6 })
                    .onClick((): void => this.hidePaper(paper))
                }
                if (this.confirmDeleteId === paper.id) {
                  Button(this.text('action.cancel'))
                    .height(32)
                    .fontSize(11)
                    .margin({ left: 6 })
                    .onClick((): void => {
                      this.confirmDeleteId = '';
                    })
                  Button(this.text('action.confirmDelete'))
                    .height(32)
                    .fontSize(11)
                    .fontColor('#FFFFFF')
                    .backgroundColor('#B42318')
                    .margin({ left: 6 })
                    .onClick((): void => this.deletePaper(paper))
                } else {
                  Button('×')
                    .width(32)
                    .height(32)
                    .fontSize(13)
                    .fontColor(this.mutedColor())
                    .backgroundColor(Color.Transparent)
                    .margin({ left: 6 })
                    .onClick((): void => this.deletePaper(paper))
                }
              }
              .width('100%')
              .height(62)
              .padding({ left: 12, right: 8 })
              .backgroundColor(this.cardColor())
              .border({ width: 1, color: this.cardBorderColor() })
              .borderRadius(12)
            }
          }, (paper: PaperData): string => paper.id)
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ top: 12 })
        .scrollBar(BarState.Off)
      }

      Text(this.text('footer.autosave'))
        .width('100%')
        .fontSize(11)
        .fontColor(this.mutedColor())
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor(this.pageBackgroundColor())
  }
}
