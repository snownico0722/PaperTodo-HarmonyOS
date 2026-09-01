import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DesktopShell } from '../common/DesktopShell';
import { PAPER_TYPE_NOTE, PAPER_TYPE_TODO } from '../common/Models';
import { TrayService } from '../common/TrayService';

@Entry
@Component
struct Recovery {
  @StorageLink('recoveryReason') recoveryReason: string = '';
  @StorageLink('statusBarStatus') statusBarStatus: string = 'unknown';
  @State retrying: boolean = false;

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private retryStatusBar(): void {
    this.retrying = true;
    TrayService.install(this.hostContext()).then((installed: boolean): void => {
      if (installed) {
        DesktopShell.startResident(this.hostContext());
      }
      this.retrying = false;
    }).catch((_error: Error): void => {
      this.retrying = false;
    });
  }

  build() {
    Column({ space: 14 }) {
      Row() {
        Text('PaperTodo')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
        Blank()
        Button('×')
          .width(34)
          .height(30)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.hostContext().terminateSelf().catch((_error: BusinessError): void => {});
          })
      }
      .width('100%')
      .gesture(PanGesture({ direction: PanDirection.All }))

      Text('桌面入口需要恢复')
        .width('100%')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
      Text(this.recoveryReason.length > 0 ? this.recoveryReason : '状态栏入口暂时不可用。')
        .width('100%')
        .fontSize(12)
        .fontColor('#6B665C')
        .maxLines(3)
      Text('状态：' + this.statusBarStatus)
        .width('100%')
        .fontSize(10)
        .fontColor('#8A8274')

      Row({ space: 8 }) {
        Button(this.retrying ? '正在重试…' : '重试任务栏入口')
          .layoutWeight(1)
          .enabled(!this.retrying)
          .onClick((): void => this.retryStatusBar())
        Button('设置')
          .onClick((): void => {
            DesktopShell.openSettings(this.hostContext());
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('☑ 新建待办')
          .layoutWeight(1)
          .onClick((): void => {
            DesktopShell.createPaper(this.hostContext(), PAPER_TYPE_TODO);
          })
        Button('✎ 新建笔记')
          .layoutWeight(1)
          .onClick((): void => {
            DesktopShell.createPaper(this.hostContext(), PAPER_TYPE_NOTE);
          })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .backgroundColor('#FFF7D7')
    .border({ width: 1, color: '#DDD2A9' })
    .borderRadius(16)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }
}
