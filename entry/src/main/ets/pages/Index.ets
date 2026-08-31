import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  AppState,
  MARKDOWN_BASIC,
  MARKDOWN_ENHANCED,
  MARKDOWN_OFF,
  PAPER_TYPE_NOTE,
  PAPER_TYPE_TODO,
  PaperData,
  THEME_DARK,
  THEME_LIGHT,
  THEME_SYSTEM
} from '../common/Models';
import { PaperStore } from '../common/PaperStore';

@Entry
@Component
struct Index {
  @StorageLink('theme') theme: string = THEME_SYSTEM;
  @StorageLink('markdownRenderMode') markdownRenderMode: string = MARKDOWN_ENHANCED;
  @StorageLink('useCapsuleMode') useCapsuleMode: boolean = true;
  @StorageLink('useDeepCapsuleMode') useDeepCapsuleMode: boolean = true;
  @StorageLink('systemColorMode') systemColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  @State papers: PaperData[] = [];
  @State confirmDeleteId: string = '';
  @State statusMessage: string = '';

  aboutToAppear(): void {
    PaperStore.initialize(this.hostContext());
    this.refresh();
  }

  onPageShow(): void {
    this.refresh();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
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

  private backgroundColor(): string {
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

  private borderColor(): string {
    return this.isDark() ? '#4E4A40' : '#D8CDA5';
  }

  private buttonColor(): string {
    return this.isDark() ? '#E8DFCA' : '#3D3A32';
  }

  private buttonTextColor(): string {
    return this.isDark() ? '#26231E' : '#FFFFFF';
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
      this.statusMessage = '打开纸片失败：' + error.message;
    });
  }

  private isPaperOpen(id: string): boolean {
    return AppStorage.get<boolean>('paperOpen:' + id) === true;
  }

  private createPaper(type: string): void {
    const paper: PaperData = PaperStore.createPaper(type);
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

  private cancelDelete(): void {
    this.confirmDeleteId = '';
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
      return '浅色';
    }
    if (this.theme === THEME_DARK) {
      return '深色';
    }
    return '跟随系统';
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
      return '不启用';
    }
    if (this.markdownRenderMode === MARKDOWN_BASIC) {
      return '启用';
    }
    return '增强';
  }

  private toggleCapsule(): void {
    const next: boolean = !this.useCapsuleMode;
    PaperStore.setCapsuleMode(next);
    if (!next) {
      this.restartVisiblePapers();
    }
    this.refresh();
  }

  private toggleDeepCapsule(): void {
    PaperStore.setDeepCapsuleMode(!this.useDeepCapsuleMode);
  }

  private restoreBackup(): void {
    const openSnapshot: PaperData[] = PaperStore.listPapers();
    for (let i: number = 0; i < openSnapshot.length; i++) {
      if (this.isPaperOpen(openSnapshot[i].id)) {
        this.startPaper(openSnapshot[i].id, 'close');
      }
    }

    if (!PaperStore.restoreBackup()) {
      this.statusMessage = '没有可恢复的备份';
      return;
    }

    this.statusMessage = '已恢复上一份自动备份';
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

  private restartVisiblePapers(): void {
    const snapshot: PaperData[] = PaperStore.listPapers();
    for (let i: number = 0; i < snapshot.length; i++) {
      if (snapshot[i].isVisible && this.isPaperOpen(snapshot[i].id)) {
        this.startPaper(snapshot[i].id, 'close');
      }
    }
    setTimeout((): void => {
      const next: PaperData[] = PaperStore.listPapers();
      for (let i: number = 0; i < next.length; i++) {
        if (next[i].isVisible) {
          this.startPaper(next[i].id, 'show');
        }
      }
    }, 160);
  }

  private paperTitle(paper: PaperData): string {
    if (paper.title.trim().length > 0) {
      return paper.title.trim();
    }
    if (paper.type === PAPER_TYPE_NOTE) {
      const firstLine: string = paper.content.split('\n')[0].trim();
      return firstLine.length > 0 ? firstLine : '未命名笔记';
    }
    for (let i: number = 0; i < paper.items.length; i++) {
      if (paper.items[i].text.trim().length > 0) {
        return paper.items[i].text.trim();
      }
    }
    return '未命名待办';
  }

  private paperMeta(paper: PaperData): string {
    const parts: string[] = [];
    parts.push(paper.type === PAPER_TYPE_NOTE ? '笔记纸' : '待办纸');
    parts.push(paper.isVisible ? '显示' : '隐藏');
    if (paper.alwaysOnTop) {
      parts.push('置顶');
    }
    if (paper.isCollapsed) {
      parts.push('胶囊');
    }
    return parts.join(' · ');
  }

  @Builder
  private SettingChip(label: string, value: string, action: () => void) {
    Button(label + '：' + value)
      .height(36)
      .fontSize(12)
      .fontColor(this.textColor())
      .backgroundColor(this.cardColor())
      .border({ width: 1, color: this.borderColor() })
      .borderRadius(10)
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
          Text('纸片控制中心 · PC 启动后会自动退到后台')
            .fontSize(12)
            .fontColor(this.mutedColor())
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Button('☑ 新建待办')
          .height(40)
          .fontSize(13)
          .fontColor(this.buttonTextColor())
          .backgroundColor(this.buttonColor())
          .borderRadius(10)
          .onClick((): void => this.createPaper(PAPER_TYPE_TODO))
        Button('✎ 新建笔记')
          .height(40)
          .fontSize(13)
          .fontColor(this.buttonTextColor())
          .backgroundColor(this.buttonColor())
          .borderRadius(10)
          .margin({ left: 8 })
          .onClick((): void => this.createPaper(PAPER_TYPE_NOTE))
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('显示全部')
          .height(36)
          .fontSize(12)
          .onClick((): void => this.showAll())
        Button('隐藏全部')
          .height(36)
          .fontSize(12)
          .onClick((): void => this.hideAll())
        this.SettingChip('主题', this.themeLabel(), (): void => this.cycleTheme())
        this.SettingChip('Markdown', this.markdownLabel(), (): void => this.cycleMarkdownMode())
        this.SettingChip('胶囊', this.useCapsuleMode ? '开启' : '关闭', (): void => this.toggleCapsule())
        this.SettingChip('自动贴边', this.useDeepCapsuleMode ? '开启' : '关闭', (): void => this.toggleDeepCapsule())
        Blank()
        Button('恢复备份')
          .height(36)
          .fontSize(12)
          .fontColor(this.mutedColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.restoreBackup())
      }
      .width('100%')
      .margin({ top: 18 })

      if (this.statusMessage.length > 0) {
        Text(this.statusMessage)
          .width('100%')
          .fontSize(12)
          .fontColor(this.mutedColor())
          .margin({ top: 8 })
      }

      if (this.papers.length === 0) {
        Column() {
          Text('桌面上还没有纸片')
            .fontSize(18)
            .fontColor(this.textColor())
          Text('新建一张待办纸或笔记纸即可开始。')
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

                Button(paper.isVisible ? '聚焦' : '显示')
                  .height(32)
                  .fontSize(11)
                  .onClick((): void => this.showPaper(paper))

                if (paper.isVisible) {
                  Button('隐藏')
                    .height(32)
                    .fontSize(11)
                    .margin({ left: 6 })
                    .onClick((): void => this.hidePaper(paper))
                }

                if (this.confirmDeleteId === paper.id) {
                  Button('取消')
                    .height(32)
                    .fontSize(11)
                    .margin({ left: 6 })
                    .onClick((): void => this.cancelDelete())
                  Button('确认删除')
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
              .border({ width: 1, color: this.borderColor() })
              .borderRadius(12)
            }
          }, (paper: PaperData): string => paper.id)
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ top: 16 })
        .scrollBar(BarState.Off)
      }

      Text('数据自动保存到 HarmonyOS Preferences，并保留上一份自动备份。')
        .width('100%')
        .fontSize(11)
        .fontColor(this.mutedColor())
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor(this.backgroundColor())
  }
}
