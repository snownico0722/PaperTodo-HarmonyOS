import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import {
  COLOR_SCHEME_FOREST,
  COLOR_SCHEME_INK,
  COLOR_SCHEME_SUNSET,
  COLOR_SCHEME_WARM,
  MARKDOWN_BASIC,
  MARKDOWN_ENHANCED,
  MARKDOWN_OFF,
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
import { DesktopShell, PAPER_COMMAND_CLOSE } from '../common/DesktopShell';
import { GlobalHotkeys } from '../common/GlobalHotkeys';
import { PaperStore } from '../common/PaperStore';
import { formatText, languageLabel, resolveLanguage, supportedLanguages, tForSystem } from '../common/Strings';
import { ThemePalette, resolvePalette } from '../common/ThemePalette';
import { TrayService } from '../common/TrayService';

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
  @StorageLink('showDeepCapsuleWhileExpanded') showDeepCapsuleWhileExpanded: boolean = true;
  @StorageLink('useMasterCapsule') useMasterCapsule: boolean = true;
  @StorageLink('titleCharacterLimit') titleCharacterLimit: number = 6;
  @StorageLink('todoVisualSize') todoVisualSize: string = TODO_VISUAL_MEDIUM;
  @StorageLink('autoClearCompletedTodos') autoClearCompletedTodos: boolean = false;
  @StorageLink('autoBottomCompleted') autoBottomCompleted: boolean = false;
  @StorageLink('autoCompressLargeImages') autoCompressLargeImages: boolean = true;
  @StorageLink('globalHotkeysEnabled') globalHotkeysEnabled: boolean = false;
  @StorageLink('globalHotkeyStatus') globalHotkeyStatus: string = 'idle';
  @StorageLink('statusBarStatus') statusBarStatus: string = 'unknown';
  @StorageLink('capsuleGap') capsuleGap: number = 4;
  @StorageLink('enableAnimations') enableAnimations: boolean = true;
  @StorageLink('rememberEdgeExpandedPosition') rememberEdgeExpandedPosition: boolean = true;
  @StorageLink('collapseExpandedEdgeCapsuleOnClick') collapseExpandedEdgeCapsuleOnClick: boolean = false;
  @StorageLink('hideEdgeCapsuleCloseButtonOnHover') hideEdgeCapsuleCloseButtonOnHover: boolean = false;
  @StorageLink('edgeCapsuleTitleCharacterLimit') edgeCapsuleTitleCharacterLimit: number = 0;
  @StorageLink('enablePaperLinks') enablePaperLinks: boolean = true;
  @StorageLink('hideLinkedPapersFromCapsules') hideLinkedPapersFromCapsules: boolean = false;
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
  @StorageLink('systemColorMode') systemColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  @StorageLink('capsuleRuntimeError') capsuleRuntimeError: string = '';
  @StorageLink('saveExitBlocked') saveExitBlocked: boolean = false;
  @State retryingCapsules: boolean = false;
  @State statusMessage: string = '';
  @State selectedPanel: string = 'general';
  @State retryingStatusBar: boolean = false;
  private settingsWindow: window.Window | null = null;

  aboutToAppear(): void {
    PaperStore.initialize(this.hostContext());
    window.getLastWindow(this.hostContext()).then((win: window.Window): void => {
      this.settingsWindow = win;
    }).catch((error: BusinessError): void => {
      console.error('resolve settings window failed: ' + error.message);
    });
    if (PaperStore.hasStorageError()) {
      this.statusMessage = this.text('status.storageProtectionDetected');
    }
  }

  aboutToDisappear(): void {
    PaperStore.flushNow();
    this.settingsWindow = null;
  }

  private onUiLanguageChanged(): void {
    this.statusMessage = PaperStore.hasStorageError() ? this.text('status.storageProtectionDetected') : '';
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
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

  private syncCapsules(): void {
    DesktopShell.syncCapsules(this.hostContext()).catch((error: Error): void => {
      console.error('PaperTodo capsule settings sync failed: ' + error.message);
    });
  }

  private restorePapers(): void {
    DesktopShell.restoreAllPapers(this.hostContext()).catch((error: Error): void => {
      this.statusMessage = error.message;
    });
  }

  private retryCapsules(): void {
    this.retryingCapsules = true;
    DesktopShell.retryCapsules(this.hostContext()).catch((error: Error): void => {
      this.statusMessage = error.message;
    }).finally((): void => { this.retryingCapsules = false; });
  }

  private retrySave(): void {
    this.saveExitBlocked = !PaperStore.flushNow();
  }

  private closeSettings(): void {
    PaperStore.flushNow();
    const win: window.Window | null = this.settingsWindow;
    if (win === null) {
      console.warn('minimize settings skipped: settings window is unavailable');
      return;
    }
    win.minimize().catch((error: BusinessError): void => {
      console.error('minimize settings failed: ' + error.message);
    });
  }

  private startSettingsMove(event: TouchEvent): void {
    if (event.type !== TouchType.Down) {
      return;
    }
    const win: window.Window | null = this.settingsWindow;
    if (win === null) {
      return;
    }
    win.startMoving().catch((error: BusinessError): void => {
      console.error('start native settings move failed: ' + error.message);
    });
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
    TrayService.refreshMenu(this.hostContext()).catch((error: Error): void => {
      console.error('refresh status bar menu language failed: ' + error.message);
    });
  }

  private currentLanguageLabel(): string {
    return languageLabel(this.uiLanguage, resolveLanguage(this.uiLanguage, this.systemLanguage));
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
    this.syncCapsules();
  }

  private toggleDeepCapsule(): void {
    PaperStore.setDeepCapsuleMode(!this.useDeepCapsuleMode);
    this.syncCapsules();
  }

  private toggleExpandedCapsule(): void {
    PaperStore.setShowDeepCapsuleWhileExpanded(!this.showDeepCapsuleWhileExpanded);
    this.syncCapsules();
  }

  private toggleMasterCapsule(): void {
    PaperStore.setMasterCapsuleEnabled(!this.useMasterCapsule);
    this.syncCapsules();
  }

  private cycleCapsuleGap(): void {
    if (this.capsuleGap === 0) {
      PaperStore.setCapsuleGap(4);
    } else if (this.capsuleGap === 4) {
      PaperStore.setCapsuleGap(8);
    } else {
      PaperStore.setCapsuleGap(0);
    }
    this.syncCapsules();
  }

  private cycleTitleCharacterLimit(): void {
    PaperStore.setTitleCharacterLimit(this.titleCharacterLimit >= 20 ? 2 : this.titleCharacterLimit + 1);
    this.syncCapsules();
  }

  private titleCharacterLimitLabel(): string {
    return this.formatted('value.characters', 'count', this.titleCharacterLimit.toString());
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
    this.syncCapsules();
  }

  private edgeTitleLimitLabel(): string {
    return this.edgeCapsuleTitleCharacterLimit === 0 ? this.text('value.all') :
      this.formatted('value.characters', 'count', this.edgeCapsuleTitleCharacterLimit.toString());
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

  private statusBarStatusLabel(): string {
    const status: string = this.statusBarStatus;
    if (status === 'active') {
      return this.text('status.statusBarActive');
    }
    if (status === 'removed') {
      return this.text('status.statusBarResidentRemoved');
    }
    if (status.startsWith('unsupported:')) {
      return this.text('status.statusBarUnsupported');
    }
    if (status.startsWith('retrying:')) {
      return this.text('status.statusBarRetrying');
    }
    if (status.startsWith('uncertain:')) {
      return this.text('status.statusBarUncertain');
    }
    if (status.startsWith('resident error:')) {
      return status.indexOf('removed') >= 0 ? this.text('status.statusBarResidentRemoved') :
        this.text('status.statusBarResidentError');
    }
    if (status.startsWith('remove error:')) {
      return this.text('status.statusBarRemoveError');
    }
    if (status.startsWith('error:')) {
      return this.text('status.statusBarError');
    }
    return this.text('status.statusBarUnknown');
  }

  private retryStatusBar(): void {
    if (this.retryingStatusBar) {
      return;
    }
    this.retryingStatusBar = true;
    const context: common.UIAbilityContext = this.hostContext();
    AppStorage.setOrCreate<string>('statusBarStatus', 'retrying: settings');
    TrayService.install(context).then((installed: boolean): void => {
      if (!installed) {
        if (!this.statusBarStatus.startsWith('error:') && !this.statusBarStatus.startsWith('unsupported:')) {
          AppStorage.setOrCreate<string>('statusBarStatus', 'error: retry installation failed');
        }
        this.retryingStatusBar = false;
        return;
      }
      DesktopShell.startResident(context).then((residentStarted: boolean): void => {
        if (residentStarted) {
          AppStorage.setOrCreate<string>('statusBarStatus', 'active');
          this.retryingStatusBar = false;
          return;
        }
        AppStorage.setOrCreate<string>('statusBarStatus', 'resident error: removing status bar item');
        TrayService.remove(context).then((removed: boolean): void => {
          AppStorage.setOrCreate<string>('statusBarStatus', removed ? 'resident error: removed' :
            'resident error: remove failed');
          this.retryingStatusBar = false;
        }).catch((_error: Error): void => {
          AppStorage.setOrCreate<string>('statusBarStatus', 'resident error: remove failed');
          this.retryingStatusBar = false;
        });
      }).catch((_error: Error): void => {
        AppStorage.setOrCreate<string>('statusBarStatus', 'resident error: removing status bar item');
        TrayService.remove(context).then((removed: boolean): void => {
          AppStorage.setOrCreate<string>('statusBarStatus', removed ? 'resident error: removed' :
            'resident error: remove failed');
          this.retryingStatusBar = false;
        }).catch((_removeError: Error): void => {
          AppStorage.setOrCreate<string>('statusBarStatus', 'resident error: remove failed');
          this.retryingStatusBar = false;
        });
      });
    }).catch((_error: Error): void => {
      AppStorage.setOrCreate<string>('statusBarStatus', 'error: retry installation failed');
      this.retryingStatusBar = false;
    });
  }

  private toggleAnimations(): void {
    PaperStore.setAnimationsEnabled(!this.enableAnimations);
  }

  private toggleRememberExpandedPosition(): void {
    PaperStore.setRememberEdgeExpandedPosition(!this.rememberEdgeExpandedPosition);
    this.syncCapsules();
  }

  private toggleRepeatEdgeClick(): void {
    PaperStore.setCollapseExpandedEdgeCapsuleOnClick(!this.collapseExpandedEdgeCapsuleOnClick);
    this.syncCapsules();
  }

  private toggleHoverCloseButton(): void {
    PaperStore.setHideEdgeCapsuleCloseButtonOnHover(!this.hideEdgeCapsuleCloseButtonOnHover);
    this.syncCapsules();
  }

  private togglePaperLinks(): void {
    PaperStore.setPaperLinksEnabled(!this.enablePaperLinks);
    this.syncCapsules();
  }

  private toggleHideLinkedPapersFromCapsules(): void {
    PaperStore.setHideLinkedPapersFromCapsules(!this.hideLinkedPapersFromCapsules);
    this.syncCapsules();
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
    const context: common.UIAbilityContext = this.hostContext();
    for (let i: number = 0; i < current.length; i++) {
      DesktopShell.startPaper(context, current[i].id, PAPER_COMMAND_CLOSE);
      DesktopShell.startEdge(context, current[i].id, PAPER_COMMAND_CLOSE);
    }
    DesktopShell.startMaster(context, PAPER_COMMAND_CLOSE);
    GlobalHotkeys.setEnabled(PaperStore.loadState().globalHotkeysEnabled);
    this.statusMessage = this.text('status.backupRestored');
    setTimeout((): void => this.syncCapsules(), 180);
  }

  @Builder
  private SettingButton(label: string, action: () => void) {
    Button(label)
      .height(48)
      .constraintSize({ minWidth: 176, maxWidth: 268 })
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

  @Builder
  private SectionTitle(label: string) {
    Text(label)
      .width('100%')
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.mutedColor())
      .margin({ top: 10, bottom: 6 })
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
          Text(this.text('app.settingsSubtitle'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontSize(12)
            .fontColor(this.mutedColor())
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .onTouch((event: TouchEvent): void => this.startSettingsMove(event))

        Button(this.text('glyph.close'))
          .width(34)
          .height(34)
          .fontSize(18)
          .fontColor(this.textColor())
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.text('action.closeSettings'))
          .onClick((): void => this.closeSettings())
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row({ space: 6 }) {
        this.PanelTab(this.text('tab.general'), 'general')
        this.PanelTab(this.text('tab.visual'), 'visual')
        this.PanelTab(this.text('tab.shortcuts'), 'shortcuts')
      }
      .width('100%')
      .margin({ top: 14 })

      Row({ space: 8 }) {
        Button(this.text('action.restorePapers'))
          .height(30).fontSize(11)
          .onClick((): void => this.restorePapers())
        if (this.capsuleRuntimeError.length > 0) {
          Button(this.text('action.retryCapsules'))
            .height(30).fontSize(11).enabled(!this.retryingCapsules)
            .onClick((): void => this.retryCapsules())
        }
        if (this.saveExitBlocked) {
          Button(this.text('action.retrySave'))
            .height(30).fontSize(11)
            .onClick((): void => this.retrySave())
        }
      }
      .width('100%').margin({ top: 8, bottom: 4 })
      if (this.capsuleRuntimeError.length > 0) {
        Text(this.text('status.capsuleRecovery') + '\n' + this.capsuleRuntimeError)
          .width('100%').fontSize(11).fontColor(this.textColor())
          .maxLines(3).margin({ bottom: 4 })
      }
      if (this.saveExitBlocked) {
        Text(this.text('status.exitSaveFailed'))
          .width('100%').fontSize(11).fontColor(this.textColor())
          .margin({ bottom: 4 })
      }

      if (this.selectedPanel === 'general') {
        Scroll() {
          Column() {
            this.SectionTitle(this.text('section.generalBehavior'))
            Flex({ wrap: FlexWrap.Wrap }) {
              this.SettingButton(this.text('setting.language') + this.currentLanguageLabel(),
                (): void => this.cycleLanguage())
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
              this.SettingButton(this.text('setting.paperLinks') + this.enabledLabel(this.enablePaperLinks),
                (): void => this.togglePaperLinks())
              this.SettingButton(this.text('setting.hideLinkedPapersFromCapsules') +
                this.enabledLabel(this.hideLinkedPapersFromCapsules),
                (): void => this.toggleHideLinkedPapersFromCapsules())
              this.SettingButton(this.text('setting.animations') + this.enabledLabel(this.enableAnimations),
                (): void => this.toggleAnimations())
            }
            .width('100%')

            this.SectionTitle(this.text('section.systemEntry'))
            Row({ space: 8 }) {
              Column() {
                Text(this.text('setting.statusBarEntry'))
                  .width('100%')
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.textColor())
                Text(this.statusBarStatusLabel())
                  .width('100%')
                  .fontSize(10)
                  .fontColor(this.mutedColor())
                  .margin({ top: 2 })
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Button(this.retryingStatusBar ? this.text('action.retryingStatusBar') :
                this.text('action.retryStatusBar'))
                .height(34)
                .fontSize(11)
                .fontColor(this.primaryButtonTextColor())
                .backgroundColor(this.primaryButtonColor())
                .borderRadius(8)
                .enabled(!this.retryingStatusBar)
                .onClick((): void => this.retryStatusBar())
            }
            .width('100%')
            .padding({ left: 10, right: 8, top: 8, bottom: 8 })
            .backgroundColor(this.cardColor())
            .border({ width: 1, color: this.cardBorderColor() })
            .borderRadius(9)

            this.SectionTitle(this.text('section.paperToolbar'))
            Flex({ wrap: FlexWrap.Wrap }) {
              this.SettingButton(this.text('setting.newTodoButton') +
                this.visibleLabel(this.showTopBarNewTodoButton), (): void => this.toggleNewTodoButton())
              this.SettingButton(this.text('setting.newNoteButton') +
                this.visibleLabel(this.showTopBarNewNoteButton), (): void => this.toggleNewNoteButton())
              this.SettingButton(this.text('setting.externalOpenButton') +
                this.visibleLabel(this.showTopBarExternalOpenButton), (): void => this.toggleExternalOpenButton())
              this.SettingButton(this.text('setting.titleCharacters') + this.titleCharacterLimitLabel(),
                (): void => this.cycleTitleCharacterLimit())
            }
            .width('100%')

            this.SectionTitle(this.text('section.capsuleBehavior'))
            Flex({ wrap: FlexWrap.Wrap }) {
              this.SettingButton(this.text('setting.capsule') + this.enabledLabel(this.useCapsuleMode),
                (): void => this.toggleCapsule())
              this.SettingButton(this.text('setting.deepCapsule') + this.enabledLabel(this.useDeepCapsuleMode),
                (): void => this.toggleDeepCapsule())
              this.SettingButton(this.text('setting.expandedDeepCapsule') +
                this.enabledLabel(this.showDeepCapsuleWhileExpanded), (): void => this.toggleExpandedCapsule())
              this.SettingButton(this.text('setting.masterCapsule') + this.enabledLabel(this.useMasterCapsule),
                (): void => this.toggleMasterCapsule())
              this.SettingButton(this.text('setting.capsuleGap') + this.capsuleGap.toString(),
                (): void => this.cycleCapsuleGap())
              this.SettingButton(this.text('setting.edgeTitle') + this.edgeTitleLimitLabel(),
                (): void => this.cycleEdgeTitleLimit())
              this.SettingButton(this.text('setting.rememberExpandedPosition') +
                this.enabledLabel(this.rememberEdgeExpandedPosition),
                (): void => this.toggleRememberExpandedPosition())
              this.SettingButton(this.text('setting.collapseOnSecondClick') +
                this.enabledLabel(this.collapseExpandedEdgeCapsuleOnClick), (): void => this.toggleRepeatEdgeClick())
              this.SettingButton(this.text('setting.hideCloseOnHover') +
                this.enabledLabel(this.hideEdgeCapsuleCloseButtonOnHover),
                (): void => this.toggleHoverCloseButton())
            }
            .width('100%')

            this.SectionTitle(this.text('section.data'))
            Flex({ wrap: FlexWrap.Wrap }) {
              this.SettingButton(this.text('action.restoreBackup'), (): void => this.restoreBackup())
            }
            .width('100%')
            Text(this.text('setting.backupHint'))
              .width('100%')
              .fontSize(11)
              .fontColor(this.mutedColor())
              .margin({ top: 2, bottom: 4 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: 4 })
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ top: 2 })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }

      if (this.selectedPanel === 'visual') {
        Scroll() {
          Column() {
            this.SectionTitle(this.text('section.visual'))
            Flex({ wrap: FlexWrap.Wrap }) {
              this.SettingButton(this.text('setting.theme') + this.themeLabel(), (): void => this.cycleTheme())
              this.SettingButton(this.text('setting.colorScheme') + this.colorSchemeLabel(),
                (): void => this.cycleColorScheme())
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
        .margin({ top: 2 })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }

      if (this.selectedPanel === 'shortcuts') {
        Scroll() {
          Column() {
            this.SectionTitle(this.text('section.shortcuts'))
            Flex({ wrap: FlexWrap.Wrap }) {
              this.SettingButton(this.text('setting.globalHotkeys') +
                this.enabledLabel(this.globalHotkeysEnabled), (): void => this.toggleGlobalHotkeys())
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
        .margin({ top: 2 })
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

    }
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor(this.pageBackgroundColor())
  }
}
