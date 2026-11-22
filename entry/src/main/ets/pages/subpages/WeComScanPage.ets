import { AuthService, ShuYoWeComQrSession } from '../../services/AuthService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function WeComScanPageBuilder(): void {
  WeComScanPage()
}

@ComponentV2
export struct WeComScanPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local qrSession: ShuYoWeComQrSession | undefined = undefined;
  @Local statusText: string = '正在加载企业微信二维码...';
  @Local isLoading: boolean = true;
  @Local isExpired: boolean = false;
  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private pollTimerId: number = -1;
  private isDisposed: boolean = false;

  aboutToAppear(): void {
    this.isDisposed = false;
    this.loadQrSession();
  }

  aboutToDisappear(): void {
    this.isDisposed = true;
    this.stopPolling();
  }

  private stopPolling(): void {
    if (this.pollTimerId !== -1) {
      clearTimeout(this.pollTimerId);
      this.pollTimerId = -1;
    }
  }

  private async loadQrSession(): Promise<void> {
    this.stopPolling();
    this.isLoading = true;
    this.isExpired = false;
    this.statusText = '正在获取企业微信扫码会话...';
    try {
      const sess = await AuthService.startWeComQrSession(this.store.campusSystem);
      if (this.isDisposed) {
        return;
      }
      this.qrSession = sess;
      this.isLoading = false;
      this.statusText = '请使用手机企业微信扫描下方二维码';
      this.scheduleNextPoll();
    } catch (err) {
      if (this.isDisposed) {
        return;
      }
      const e = err as Error;
      this.isLoading = false;
      this.isExpired = true;
      this.statusText = `获取二维码失败：${e.message}`;
    }
  }

  private scheduleNextPoll(): void {
    if (this.isDisposed) {
      return;
    }
    this.stopPolling();
    this.pollTimerId = setTimeout(() => {
      this.pollOnce();
    }, 1500);
  }

  private async pollOnce(): Promise<void> {
    if (this.isDisposed || this.qrSession === undefined) {
      return;
    }
    try {
      const res = await AuthService.pollWeComQrStatus(this.qrSession.key);
      if (this.isDisposed) {
        return;
      }
      this.statusText = res.message;
      if (res.status === 'succeeded' && res.authCode.length > 0) {
        this.stopPolling();
        this.statusText = '扫码确认成功，正在换取校园会话...';
        const redeem = await AuthService.redeemWeComAuthCode(
          this.qrSession,
          res.authCode,
          this.store.campusSystem
        );
        if (this.isDisposed) {
          return;
        }
        if (redeem.success) {
          this.statusText = '登录成功，正在同步真实课表...';
          const syncMsg = await this.store.completeRealLogin(redeem.studentId, this.store.campusSystem);
          if (this.isDisposed) {
            return;
          }
          this.getUIContext().getPromptAction().showToast({ message: syncMsg });
          this.navStack.pop();
          return;
        }
        this.statusText = redeem.message;
        this.isExpired = true;
        return;
      }
      if (res.status === 'expired') {
        this.isExpired = true;
        return;
      }
      this.scheduleNextPoll();
    } catch (_err) {
      if (!this.isDisposed) {
        this.scheduleNextPoll();
      }
    }
  }

  build() {
    NavDestination() {
      Column() {
        ShuYoTopBar({
          headerTitle: '企业微信扫码登录',
          subtitleText: '上海大学统一身份认证',
          showBack: true,
          rightLabel: '刷新',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            this.loadQrSession();
          }
        })

        Column({ space: 18 }) {
          Column({ space: 14 }) {
            if (this.isLoading) {
              LoadingProgress()
                .width(44)
                .height(44)
                .color(this.store.colors.accent)
            } else if (this.qrSession !== undefined && !this.isExpired) {
              QRCode(this.qrSession.confirmUrl)
                .width(210)
                .height(210)
                .color('#111111')
                .backgroundColor('#FFFFFF')
            } else {
              SymbolGlyph($r('sys.symbol.qrcode'))
                .fontSize(64)
                .fontColor([this.store.colors.textMuted])
            }

            Text(this.statusText)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isExpired ? this.store.colors.danger : this.store.colors.textPrimary)
              .textAlign(TextAlign.Center)

            if (this.isExpired) {
              Button('重新生成二维码')
                .height(38)
                .fontSize(13)
                .fontColor(this.store.colors.onAccent)
                .backgroundColor(this.store.colors.accent)
                .borderRadius(19)
                .padding({ left: 18, right: 18 })
                .onClick(() => {
                  this.loadQrSession();
                })
            }
          }
          .width('100%')
          .padding(24)
          .borderRadius(18)
          .backgroundColor(this.store.colors.surface)
          .border({ width: 1, color: this.store.colors.border })
          .alignItems(HorizontalAlign.Center)

          Text('提示：打开企业微信 → 右上角“+” → 扫一扫，确认登录即可同步教务与校园服务会话。')
            .fontSize(12)
            .fontColor(this.store.colors.textTertiary)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding(20)
        .layoutWeight(1)
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
