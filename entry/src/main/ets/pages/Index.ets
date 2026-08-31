import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
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
  @StorageLink('markdownRenderMode') markdownRenderMode: string = MARKDOWN_ENHANCED;
  @StorageLink('useCapsuleMode') useCapsuleMode: boolean = true;
  @StorageLink('useDeepCapsuleMode') useDeepCapsuleMode: boolean = true;
  @StorageLink('todoVisualSize') todoVisualSize: string = TODO_VISUAL_MEDIUM;
  @StorageLink('autoBottomCompleted') autoBottomCompleted: boolean = false;
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
      this.statusMessage = '检测到主数据与备份均异常，已进入数据保护状态，不会用空白数据覆盖原存储。';
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
    const paper: PaperData | null = PaperStore.createPaper(type);
    if (paper === null) {
      this.statusMessage = PaperStore.hasStorageError() ?
        '数据处于保护状态，暂不允许新建纸片。' :
        '最多支持 ' + MAX_PAPERS.toString() + ' 张纸片。';
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
      return '小';
    }
    if (this.todoVisualSize === TODO_VISUAL_LARGE) {
      return '大';
    }
    if (this.todoVisualSize === TODO_VISUAL_XLARGE) {
      return '特大';
    }
    return '中';
  }

  private toggleAutoBottomCompleted(): void {
    PaperStore.setAutoBottomCompleted(!this.autoBottomCompleted);
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
    const current: PaperData[] = PaperStore.listPapers();
    for (let i: number = 0; i < current.length; i++) {
      if (this.isPaperOpen(current[i].id)) {
        this.startPaper(current[i].id, 'close');
      }
    }
    if (!PaperStore.restoreBackup()) {
      this.statusMessage = '没有可恢复的有效备份';
      return;
    }
    this.statusMessage = '已恢复上一份成功保存的自动备份';
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
  private SettingButton(label: string, action: () => void) {
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
          Text('纸片控制中心 · 基础行为已按 3.x 经验收敛')
            .fontSize(12)
            .fontColor(this.mutedColor())
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Button('☑ 新建待办')
          .height(40)
          .fontSize(13)
          .fontColor(this.primaryButtonTextColor())
          .backgroundColor(this.primaryButtonColor())
          .borderRadius(10)
          .onClick((): void => this.createPaper(PAPER_TYPE_TODO))
        Button('✎ 新建笔记')
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
        Button('显示全部')
          .height(36)
          .fontSize(12)
          .onClick((): void => this.showAll())
        Button('隐藏全部')
          .height(36)
          .fontSize(12)
          .onClick((): void => this.hideAll())
        Blank()
        Button('恢复备份')
          .height(36)
          .fontSize(12)
          .fontColor(this.mutedColor())
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.restoreBackup())
      }
      .width('100%')
      .margin({ top: 16 })

      Flex({ wrap: FlexWrap.Wrap }) {
        this.SettingButton('主题：' + this.themeLabel(), (): void => this.cycleTheme())
        this.SettingButton('Markdown：' + this.markdownLabel(), (): void => this.cycleMarkdownMode())
        this.SettingButton('胶囊：' + (this.useCapsuleMode ? '开启' : '关闭'), (): void => this.toggleCapsule())
        this.SettingButton('自动贴边：' + (this.useDeepCapsuleMode ? '开启' : '关闭'), (): void => this.toggleDeepCapsule())
        this.SettingButton('待办大小：' + this.todoVisualSizeLabel(), (): void => this.cycleTodoVisualSize())
        this.SettingButton('完成项置底：' + (this.autoBottomCompleted ? '开启' : '关闭'),
          (): void => this.toggleAutoBottomCompleted())
        this.SettingButton('胶囊间距：' + this.capsuleGap.toString(), (): void => this.cycleCapsuleGap())
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
          Text(PaperStore.hasStorageError() ? '数据保护模式' : '桌面上还没有纸片')
            .fontSize(18)
            .fontColor(this.textColor())
          Text(PaperStore.hasStorageError() ?
            '原数据未被覆盖。请先尝试恢复备份。' :
            '新建一张待办纸或笔记纸即可开始。')
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
                    .onClick((): void => {
                      this.confirmDeleteId = '';
                    })
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

      Text('编辑先更新内存；空闲约 1 秒落盘，持续输入最长约 10 秒强制保存，并保留上一份成功状态。')
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
