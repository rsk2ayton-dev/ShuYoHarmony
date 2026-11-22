import { pasteboard } from '@kit.BasicServicesKit';
import { ShuYoOtpToken } from '../../models/ShuYoModels';
import { OtpTokenService } from '../../services/OtpTokenService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function OtpTokenPageBuilder(): void {
  OtpTokenPage()
}

@ComponentV2
export struct OtpTokenPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local token: ShuYoOtpToken = OtpTokenService.fetchDemoToken();
  @Local useWebVpn: boolean = false;
  @Local isRefreshing: boolean = false;
  @Local errorMsg: string = '';
  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private timerId: number = -1;

  aboutToAppear(): void {
    this.useWebVpn = this.store.useWebVpn;
    this.refreshToken();
    this.startCountdown();
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private startCountdown(): void {
    this.timerId = setInterval(() => {
      if (this.token.remaining <= 1) {
        this.refreshToken();
      } else {
        this.token = {
          code: this.token.code,
          account: this.token.account,
          remaining: this.token.remaining - 1,
          period: this.token.period
        };
      }
    }, 1000);
  }

  private async refreshToken(): Promise<void> {
    if (this.isRefreshing) {
      return;
    }
    if (this.store.isDemoMode) {
      this.token = OtpTokenService.fetchDemoToken();
      this.errorMsg = '';
      return;
    }
    this.isRefreshing = true;
    try {
      this.token = await OtpTokenService.fetchLiveToken(this.useWebVpn);
      this.errorMsg = '';
    } catch (err) {
      const e = err as Error;
      this.errorMsg = e.message;
      this.token = OtpTokenService.fetchDemoToken();
    } finally {
      this.isRefreshing = false;
    }
  }

  private copyCode(): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.token.code);
      pasteboard.getSystemPasteboard().setDataSync(data);
      this.getUIContext().getPromptAction().showToast({ message: `已复制口令 ${this.token.code}` });
    } catch (_err) {
      this.getUIContext().getPromptAction().showToast({ message: '复制失败' });
    }
  }

  build() {
    NavDestination() {
      Column({ space: 18 }) {
        ShuYoTopBar({
          headerTitle: '动态口令',
          subtitleText: 'otp.shu.edu.cn',
          showBack: true,
          rightLabel: '',
          rightSymbolName: 'refresh',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            this.refreshToken();
          }
        })

        Column({ space: 18 }) {
          Column({ space: 12 }) {
            Text(this.token.account.length > 0 ? `绑定账号：${this.token.account}` : '校园动态密码')
              .fontSize(13)
              .fontColor(this.store.colors.textTertiary)

            Text(OtpTokenService.formatGroupedCode(this.token.code))
              .fontSize(44)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.store.colors.accent)
              .letterSpacing(3)

            Progress({
              value: this.token.remaining,
              total: this.token.period > 0 ? this.token.period : 30,
              type: ProgressType.Linear
            })
              .width('100%')
              .color(this.token.remaining <= 6 ? this.store.colors.warning : this.store.colors.accent)
              .backgroundColor(this.store.colors.surfaceMuted)
              .style({ strokeWidth: 6 })

            Text(`${this.token.remaining} 秒后自动刷新`)
              .fontSize(12)
              .fontColor(this.store.colors.textMuted)

            Button('点击复制动态口令')
              .width('100%')
              .height(44)
              .fontSize(15)
              .fontColor(this.store.colors.onAccent)
              .backgroundColor(this.store.colors.accent)
              .borderRadius(12)
              .margin({ top: 6 })
              .onClick(() => {
                this.copyCode();
              })
          }
          .width('100%')
          .padding(24)
          .borderRadius(18)
          .backgroundColor(this.store.colors.surface)
          .border({ width: 1, color: this.store.colors.border })
          .alignItems(HorizontalAlign.Center)

          Row() {
            Column({ space: 2 }) {
              Text('通过 WebVPN 访问')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.store.colors.textPrimary)
              Text('校外网络可尝试开启 WebVPN 通道')
                .fontSize(12)
                .fontColor(this.store.colors.textTertiary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.useWebVpn })
              .selectedColor(this.store.colors.accent)
              .onChange((val: boolean) => {
                this.useWebVpn = val;
                this.refreshToken();
              })
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor(this.store.colors.surface)
          .border({ width: 1, color: this.store.colors.border })

          if (this.errorMsg.length > 0) {
            Text(this.errorMsg)
              .fontSize(12)
              .fontColor(this.store.colors.warning)
              .width('100%')
          }
        }
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.store.colors.background)
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.navStack = ctx.pathStack;
    })
  }
}
