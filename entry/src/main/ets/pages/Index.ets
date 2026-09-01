import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  COLOR_SCHEME_FOREST,
  COLOR_SCHEME_INK,
  COLOR_SCHEME_ROSE,
  COLOR_SCHEME_WARM,
  MARKDOWN_BASIC,
  MARKDOWN_ENHANCED,
  MARKDOWN_OFF,
  MAX_PAPERS,
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  PaperData,
  THEME_DARK,
  THEME_LIGHT,
  THEME_SYSTEM,
  TODO_VISUAL_LARGE,
  TODO_VISUAL_MEDIUM,
  TODO_VISUAL_SMALL,
  TODO_VISUAL_XLARGE
} from '../common/Models';
import { PaperStore } from '../common/PaperStore';

@Entry
@Component
struct Index {
  @StorageLink('theme') theme: string = THEME_SYSTEM;
  @StorageLink('colorScheme') colorScheme: string = COLOR_SCHEME_WARM;
  @StorageLink('markdownRenderMode') markdownRenderMode: string = MARKDOWN_ENHANCED;
  @StorageLink('useCapsuleMode') useCapsuleMode: boolean = true;
  @StorageLink('useDeepCapsuleMode') useDeepCapsuleMode: boolean = true;
  @StorageLink('todoVisualSize') todoVisualSize: string = TODO_VISUAL_MEDIUM;
  @StorageLink('autoBottomCompleted') autoBottomCompleted: boolean = false;
  @StorageLink('autoClearCompletedTodos') autoClearCompletedTodos: boolean = false;
  @StorageLink('enableTodoNoteLinks') enableTodoNoteLinks: boolean = true;
  @StorageLink('showLinkedNoteName') showLinkedNoteName: boolean = false;
  @StorageLink('capsuleGap') capsuleGap: number = 4;
  @StorageLink('paperRevision') @Watch('onPaperRevision') paperRevision: number = 0;
  @StorageLink('systemColorMode') systemColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  @State papers: PaperData[] = [];
  @State confirmDeleteId: string = '';
  @State statusMessage: string = '';

  aboutToAppear(): void {
    PaperStore.initialize(this.hostContext());
    this.refresh();
    if (PaperStore.hasStorageError()) {
      this.statusMessage = this.localized($r('app.string.status_storage_protect'));
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

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private localized(resource: Resource, ...args: Array<string | number>): string {
    return this.hostContext().resourceManager.getStringSync(resource, ...args);
  }

  private refresh(): void {
    this.papers = PaperStore.listPapers();
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

  private pageBackgroundColor(): string {
    return this.isDark() ? '#171715' : '#F2F2EE';
  }

  private cardColor(): string {
    return this.isDark() ? '#262520' : '#FFF9DE';
  }

  private textColor(): string {
    return this.isDark() ? '#F2EBD7' : '#28251F';
  }

  private mutedColor(): string {
    return this.isDark() ? '#AAA491' : '#746D5D';
  }

  private cardBorderColor(): string {
    return this.isDark() ? '#4E4A40' : '#D8CDA5';
  }

  private primaryButtonColor(): string {
    return this.isDark() ? '#E8DFCA' : '#3D3A32';
  }

  private primaryButtonTextColor(): string {
    return this.isDark() ? '#26231E' : '#FFFFFF';
  }

  private startPaper(paperId: string, command: string = 'show'): void {
    const want: Want = {
      bundleName: 'com.papertodo.app',
      moduleName: 'entry',
      abilityName: 'PaperAbility',
      parameters: {
        paperId: paperId,
        paperCommand: command
      }
    };
    try {
      this.hostContext().startAbility(want).catch((error: BusinessError): void => {
        this.statusMessage = this.localized($r('app.string.status_open_paper_failed'), error.message);
      });
    } catch (error) {
      this.statusMessage = this.localized($r('app.string.status_open_paper_failed'), String(error));
    }
  }

  private isPaperOpen(id: string): boolean {
    return AppStorage.get<boolean>('paperOpen:' + id) === true;
  }

  private createPaper(type: string): void {
    const paper: PaperData | null = PaperStore.createPaper(type);
    if (paper === null) {
      this.statusMessage = PaperStore.hasStorageError() ?
        this.localized($r('app.string.status_create_blocked')) :
        this.localized($r('app.string.status_max_papers'), MAX_PAPERS);
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

  private themeLabel(): string {
    if (this.theme === THEME_LIGHT) {
      return this.localized($r('app.string.theme_light'));
    }
    if (this.theme === THEME_DARK) {
      return this.localized($r('app.string.theme_dark'));
    }
    return this.localized($r('app.string.theme_system'));
  }

  private cycleColorScheme(): void {
    if (this.colorScheme === COLOR_SCHEME_WARM) {
      PaperStore.setColorScheme(COLOR_SCHEME_INK);
    } else if (this.colorScheme === COLOR_SCHEME_INK) {
      PaperStore.setColorScheme(COLOR_SCHEME_FOREST);
    } else if (this.colorScheme === COLOR_SCHEME_FOREST) {
      PaperStore.setColorScheme(COLOR_SCHEME_ROSE);
    } else {
      PaperStore.setColorScheme(COLOR_SCHEME_WARM);
    }
  }

  private colorSchemeLabel(): string {
    if (this.colorScheme === COLOR_SCHEME_INK) {
      return this.localized($r('app.string.scheme_ink'));
    }
    if (this.colorScheme === COLOR_SCHEME_FOREST) {
      return this.localized($r('app.string.scheme_forest'));
    }
    if (this.colorScheme === COLOR_SCHEME_ROSE) {
      return this.localized($r('app.string.scheme_rose'));
    }
    return this.localized($r('app.string.scheme_warm'));
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
      return this.localized($r('app.string.markdown_off'));
    }
    if (this.markdownRenderMode === MARKDOWN_BASIC) {
      return this.localized($r('app.string.markdown_basic'));
    }
    return this.localized($r('app.string.markdown_enhanced'));
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
      return this.localized($r('app.string.size_small'));
    }
    if (this.todoVisualSize === TODO_VISUAL_LARGE) {
      return this.localized($r('app.string.size_large'));
    }
    if (this.todoVisualSize === TODO_VISUAL_XLARGE) {
      return this.localized($r('app.string.size_xlarge'));
    }
    return this.localized($r('app.string.size_medium'));
  }

  private stateLabel(enabled: boolean): string {
    return this.localized(enabled ? $r('app.string.state_on') : $r('app.string.state_off'));
  }

  private toggleAutoBottomCompleted(): void {
    PaperStore.setAutoBottomCompleted(!this.autoBottomCompleted);
  }

  private toggleAutoClearCompleted(): void {
    PaperStore.setAutoClearCompletedTodos(!this.autoClearCompletedTodos);
  }

  private toggleTodoNoteLinks(): void {
    PaperStore.setEnableTodoNoteLinks(!this.enableTodoNoteLinks);
  }

  private toggleLinkedNoteName(): void {
    PaperStore.setShowLinkedNoteName(!this.showLinkedNoteName);
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

  private restoreBackup(): void {
    PaperStore.flushNow();
    if (!PaperStore.hasValidBackup()) {
      this.statusMessage = this.localized($r('app.string.status_no_backup'));
      return;
    }

    const current: PaperData[] = PaperStore.listPapers();
    for (let i: number = 0; i < current.length; i++) {
      if (this.isPaperOpen(current[i].id)) {
        this.startPaper(current[i].id, 'close');
      }
    }
    this.statusMessage = this.localized($r('app.string.status_switch_backup'));

    setTimeout((): void => {
      if (!PaperStore.restoreBackup()) {
        this.statusMessage = this.localized($r('app.string.status_restore_failed'));
        for (let i: number = 0; i < current.length; i++) {
          if (current[i].isVisible) {
            this.startPaper(current[i].id, 'show');
          }
        }
        return;
      }

      this.statusMessage = this.localized($r('app.string.status_restore_success'));
      this.refresh();
      const restored: PaperData[] = PaperStore.listPapers();
      for (let i: number = 0; i < restored.length; i++) {
        if (restored[i].isVisible) {
          this.startPaper(restored[i].id, 'show');
        }
      }
    }, 220);
  }

  private paperTitle(paper: PaperData): string {
    if (paper.title.trim().length > 0) {
      return paper.title.trim();
    }
    if (paper.type === PAPER_TYPE_NOTE) {
      const firstLine: string = paper.content.split('\n')[0].trim();
      return firstLine.length > 0 ? firstLine : this.localized($r('app.string.untitled_note'));
    }
    for (let i: number = 0; i < paper.items.length; i++) {
      if (paper.items[i].text.trim().length > 0) {
        return paper.items[i].text.trim();
      }
    }
    return this.localized($r('app.string.untitled_todo'));
  }

  private paperMeta(paper: PaperData): string {
    const parts: string[] = [];
    parts.push(this.localized(paper.type === PAPER_TYPE_NOTE ?
      $r('app.string.meta_note_paper') : $r('app.string.meta_todo_paper')));
    parts.push(this.localized(paper.isVisible ? $r('app.string.meta_visible') : $r('app.string.meta_hidden')));
    if (paper.alwaysOnTop) {
      parts.push(this.localized($r('app.string.meta_topmost')));
    }
    if (paper.isCollapsed) {
      parts.push(this.localized($r('app.string.meta_capsule')));
    }
    return parts.join(' · ');
  }

  @Builder
  private SettingButton(label: ResourceStr, action: () => void) {
    Button(label)
      .height(34)
      .fontSize(11)
      .fontColor(this.textColor())
      .backgroundColor(this.cardColor())
      .border({ width: 1, color: this.cardBorderColor() })
      .borderRadius(9)
      .margin({ right: 6, bottom: 6 })
      .onClick(action)
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('PaperTodo')
            .fontSize(30)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.textColor())
          Text($r('app.string.manager_subtitle'))
            .fontSize(12)
            .fontColor(this.mutedColor())
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Button($r('app.string.new_todo'))
          .height(40)
          .fontSize(13)
          .fontColor(this.primaryButtonTextColor())
          .backgroundColor(this.primaryButtonColor())
          .borderRadius(10)
          .onClick((): void => this.createPaper(PAPER_TYPE_TODO))
        Button($r('app.string.new_note'))
          .height(40)
          .fontSize(13)
          .fontColor(this.primaryButtonTextColor())
          .backgroundColor(this.primaryButtonColor())
          .borderRadius(10)
          .margin({ left: 8 })
          .onClick((): void => this.createPaper(PAPER_TYPE_NOTE))
      }
      .width('100%')

      Row({ space: 8 }) {
        Button($r('app.string.show_all'))
          .height(36)
          .fontSize(12)
          .onClick((): void => this.showAll())
        Button($r('app.string.hide_all'))
          .height(36)
          .fontSize(12)
          .onClick((): void => this.hideAll())
        Blank()
        Button($r('app.string.restore_backup'))
          .height(36)
          .fontSize(12)
          .fontColor(this.mutedColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.restoreBackup())
      }
      .width('100%')
      .margin({ top: 16 })

      Flex({ wrap: FlexWrap.Wrap }) {
        this.SettingButton($r('app.string.setting_theme', this.themeLabel()), (): void => this.cycleTheme())
        this.SettingButton($r('app.string.setting_color_scheme', this.colorSchemeLabel()), (): void => this.cycleColorScheme())
        this.SettingButton($r('app.string.setting_markdown', this.markdownLabel()), (): void => this.cycleMarkdownMode())
        this.SettingButton($r('app.string.setting_todo_size', this.todoVisualSizeLabel()), (): void => this.cycleTodoVisualSize())
        this.SettingButton($r('app.string.setting_completed_bottom', this.stateLabel(this.autoBottomCompleted)),
          (): void => this.toggleAutoBottomCompleted())
        this.SettingButton($r('app.string.setting_clear_completed', this.stateLabel(this.autoClearCompletedTodos)),
          (): void => this.toggleAutoClearCompleted())
        this.SettingButton($r('app.string.setting_todo_note_links', this.stateLabel(this.enableTodoNoteLinks)),
          (): void => this.toggleTodoNoteLinks())
        if (this.enableTodoNoteLinks) {
          this.SettingButton($r('app.string.setting_show_linked_note_title', this.stateLabel(this.showLinkedNoteName)),
            (): void => this.toggleLinkedNoteName())
        }
        this.SettingButton($r('app.string.setting_capsule', this.stateLabel(this.useCapsuleMode)),
          (): void => this.toggleCapsule())
        this.SettingButton($r('app.string.setting_auto_edge', this.stateLabel(this.useDeepCapsuleMode)),
          (): void => this.toggleDeepCapsule())
        this.SettingButton($r('app.string.setting_capsule_gap', this.capsuleGap), (): void => this.cycleCapsuleGap())
      }
      .width('100%')
      .margin({ top: 10 })

      if (this.statusMessage.length > 0) {
        Text(this.statusMessage)
          .width('100%')
          .fontSize(12)
          .fontColor(PaperStore.hasStorageError() ? '#B42318' : this.mutedColor())
          .margin({ top: 6 })
      }

      if (this.papers.length === 0) {
        Column() {
          Text(PaperStore.hasStorageError() ?
            $r('app.string.empty_storage_protection') : $r('app.string.empty_no_papers'))
            .fontSize(18)
            .fontColor(this.textColor())
          Text(PaperStore.hasStorageError() ?
            $r('app.string.empty_storage_protection_hint') : $r('app.string.empty_no_papers_hint'))
            .fontSize(13)
            .fontColor(this.mutedColor())
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.papers, (paper: PaperData) => {
            ListItem() {
              Row() {
                Text(paper.type === PAPER_TYPE_NOTE ? '✎' : '☑')
                  .width(34)
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
                Button(paper.isVisible ? $r('app.string.focus') : $r('app.string.show'))
                  .height(32)
                  .fontSize(11)
                  .onClick((): void => this.showPaper(paper))
                if (paper.isVisible) {
                  Button($r('app.string.hide'))
                    .height(32)
                    .fontSize(11)
                    .margin({ left: 6 })
                    .onClick((): void => this.hidePaper(paper))
                }
                if (this.confirmDeleteId === paper.id) {
                  Button($r('app.string.cancel'))
                    .height(32)
                    .fontSize(11)
                    .margin({ left: 6 })
                    .onClick((): void => {
                      this.confirmDeleteId = '';
                    })
                  Button($r('app.string.confirm_delete'))
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

      Text($r('app.string.manager_tip_todo'))
        .width('100%')
        .fontSize(11)
        .fontColor(this.mutedColor())
        .margin({ top: 8 })
      Text($r('app.string.manager_tip_save'))
        .width('100%')
        .fontSize(11)
        .fontColor(this.mutedColor())
        .margin({ top: 3 })
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor(this.pageBackgroundColor())
  }
}
