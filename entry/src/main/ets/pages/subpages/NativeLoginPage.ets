import { ShuYoCampusSystem } from '../../models/ShuYoModels';
import { AuthService, ShuYoTwoStepMethod } from '../../services/AuthService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function NativeLoginPageBuilder(): void {
  NativeLoginPage()
}

@ComponentV2
export struct NativeLoginPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local studentIdInput: string = '';
  @Local passwordInput: string = '';
  @Local verifyCodeInput: string = '';
  @Local selectedSystem: ShuYoCampusSystem = ShuYoCampusSystem.UNDERGRADUATE;
  @Local isSubmitting: boolean = false;
  @Local isSendingCode: boolean = false;
  @Local needsTwoStep: boolean = false;
  @Local twoStepMethods: ShuYoTwoStepMethod[] = [];
  @Local selectedMethod: string = 'wecom';
  @Local resendCountdown: number = 0;
  @Local infoMsg: string = '';
  @Local errorMsg: string = '';
  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private countdownTimerId: number = -1;

  aboutToAppear(): void {
    this.selectedSystem = this.store.campusSystem;
  }

  aboutToDisappear(): void {
    this.stopCountdown();
  }

  private getSysBg(sys: ShuYoCampusSystem): string {
    return this.selectedSystem === sys ? this.store.colors.selectedFill : this.store.colors.surfaceAlt;
  }

  private getSysText(sys: ShuYoCampusSystem): string {
    return this.selectedSystem === sys ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private getMethodBg(key: string): string {
    return this.selectedMethod === key ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getMethodText(key: string): string {
    return this.selectedMethod === key ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private getSelectedMethodHint(): string {
    for (let i = 0; i < this.twoStepMethods.length; i++) {
      if (this.twoStepMethods[i].key === this.selectedMethod) {
        const h = this.twoStepMethods[i].hint;
        if (h.length > 0) {
          return `验证通道：${this.twoStepMethods[i].label}（${h}）`;
        }
        return `验证通道：${this.twoStepMethods[i].label}`;
      }
    }
    return '请选择二次验证方式并获取动态验证码';
  }

  private getSendButtonText(): string {
    if (this.isSendingCode) {
      return '发送中...';
    }
    if (this.resendCountdown > 0) {
      return `${this.resendCountdown}s`;
    }
    return '发送验证码';
  }

  private stopCountdown(): void {
    if (this.countdownTimerId !== -1) {
      clearInterval(this.countdownTimerId);
      this.countdownTimerId = -1;
    }
  }

  private startCountdown(seconds: number): void {
    this.stopCountdown();
    this.resendCountdown = seconds;
    this.countdownTimerId = setInterval(() => {
      if (this.resendCountdown <= 1) {
        this.resendCountdown = 0;
        this.stopCountdown();
      } else {
        this.resendCountdown = this.resendCountdown - 1;
      }
    }, 1000);
  }

  private resetToCredentials(): void {
    this.stopCountdown();
    AuthService.clearPendingChallenge();
    this.needsTwoStep = false;
    this.twoStepMethods = [];
    this.verifyCodeInput = '';
    this.resendCountdown = 0;
    this.errorMsg = '';
    this.infoMsg = '';
  }

  private async handleLogin(): Promise<void> {
    if (this.isSubmitting) {
      return;
    }
    this.errorMsg = '';
    this.infoMsg = '';
    this.isSubmitting = true;
    const result = await AuthService.loginWithCredentials(
      this.studentIdInput,
      this.passwordInput,
      this.selectedSystem
    );
    this.isSubmitting = false;

    if (result.requiresTwoStep) {
      this.needsTwoStep = true;
      this.twoStepMethods = result.twoStepMethods;
      this.selectedMethod = result.twoStepMethods.length > 0 ? result.twoStepMethods[0].key : 'wecom';
      this.verifyCodeInput = '';
      this.resendCountdown = 0;
      this.infoMsg = '账号密码校验通过，正在请求发送二次验证码...';
      await this.handleSendCode();
      return;
    }

    if (result.success) {
      this.isSubmitting = true;
      this.infoMsg = '登录成功，正在同步您的真实课程表...';
      const syncMsg = await this.store.completeRealLogin(result.studentId, this.selectedSystem);
      this.isSubmitting = false;
      this.getUIContext().getPromptAction().showToast({ message: syncMsg });
      this.navStack.pop();
      return;
    }

    this.errorMsg = result.message;
  }

  private async handleSendCode(): Promise<void> {
    if (this.isSendingCode || this.resendCountdown > 0) {
      return;
    }
    this.errorMsg = '';
    this.isSendingCode = true;
    const res = await AuthService.sendTwoStepCode(this.selectedMethod);
    this.isSendingCode = false;
    if (res.success) {
      this.infoMsg = res.message;
      this.startCountdown(60);
    } else {
      this.infoMsg = '';
      this.errorMsg = res.message;
    }
  }

  private async handleVerifyCode(): Promise<void> {
    if (this.isSubmitting) {
      return;
    }
    this.errorMsg = '';
    this.infoMsg = '';
    this.isSubmitting = true;
    const result = await AuthService.verifyTwoStepCode(this.selectedMethod, this.verifyCodeInput);
    if (result.success) {
      this.stopCountdown();
      this.infoMsg = '二次验证成功，正在同步您的真实课程表...';
      const syncMsg = await this.store.completeRealLogin(result.studentId, this.selectedSystem);
      this.isSubmitting = false;
      this.getUIContext().getPromptAction().showToast({ message: syncMsg });
      this.navStack.pop();
      return;
    }

    this.isSubmitting = false;
    if (!result.requiresTwoStep) {
      this.stopCountdown();
      this.needsTwoStep = false;
    }
    this.errorMsg = result.message;
  }

  build() {
    NavDestination() {
      Column() {
        ShuYoTopBar({
          headerTitle: '统一身份认证登录',
          subtitleText: 'SHU NewSSO 原生安全登录',
          showBack: true,
          rightLabel: '',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {}
        })

        Scroll() {
          Column({ space: 16 }) {
            // Identity selector
            Row({ space: 10 }) {
              Button('本科生系统')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .fontColor(this.getSysText(ShuYoCampusSystem.UNDERGRADUATE))
                .backgroundColor(this.getSysBg(ShuYoCampusSystem.UNDERGRADUATE))
                .borderRadius(12)
                .enabled(!this.needsTwoStep && !this.isSubmitting)
                .onClick(() => {
                  this.selectedSystem = ShuYoCampusSystem.UNDERGRADUATE;
                })
              Button('研究生系统')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .fontColor(this.getSysText(ShuYoCampusSystem.GRADUATE))
                .backgroundColor(this.getSysBg(ShuYoCampusSystem.GRADUATE))
                .borderRadius(12)
                .enabled(!this.needsTwoStep && !this.isSubmitting)
                .onClick(() => {
                  this.selectedSystem = ShuYoCampusSystem.GRADUATE;
                })
            }
            .width('100%')

            // Credentials / Two-Step Card
            Column({ space: 12 }) {
              if (!this.needsTwoStep) {
                Text('一卡通学号 / 工号')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.store.colors.textSecondary)
                TextInput({ placeholder: '请输入学号', text: this.studentIdInput })
                  .height(46)
                  .borderRadius(10)
                  .backgroundColor(this.store.colors.surfaceAlt)
                  .fontColor(this.store.colors.textPrimary)
                  .enabled(!this.isSubmitting)
                  .onChange((val: string) => {
                    this.studentIdInput = val;
                  })

                Text('统一身份认证密码')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.store.colors.textSecondary)
                TextInput({ placeholder: '请输入密码（本地 RSA 加密传输）', text: this.passwordInput })
                  .type(InputType.Password)
                  .height(46)
                  .borderRadius(10)
                  .backgroundColor(this.store.colors.surfaceAlt)
                  .fontColor(this.store.colors.textPrimary)
                  .enabled(!this.isSubmitting)
                  .onChange((val: string) => {
                    this.passwordInput = val;
                  })
              } else {
                Column({ space: 4 }) {
                  Text('需要二次身份验证')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.store.colors.textPrimary)
                  Text(`当前账号：${this.studentIdInput.trim()}`)
                    .fontSize(12)
                    .fontColor(this.store.colors.textTertiary)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)

                Row({ space: 8 }) {
                  ForEach(this.twoStepMethods, (m: ShuYoTwoStepMethod, idx: number) => {
                    Button(m.label)
                      .layoutWeight(1)
                      .height(36)
                      .fontSize(13)
                      .fontColor(this.getMethodText(m.key))
                      .backgroundColor(this.getMethodBg(m.key))
                      .borderRadius(10)
                      .enabled(!this.isSubmitting && !this.isSendingCode)
                      .onClick(() => {
                        if (this.selectedMethod !== m.key) {
                          this.selectedMethod = m.key;
                          this.resendCountdown = 0;
                          this.stopCountdown();
                          this.errorMsg = '';
                          this.infoMsg = '';
                        }
                      })
                  }, (m: ShuYoTwoStepMethod, idx: number): string => m.key)
                }
                .width('100%')

                Text(this.getSelectedMethodHint())
                  .fontSize(12)
                  .fontColor(this.store.colors.textSecondary)
                  .width('100%')

                Row({ space: 8 }) {
                  TextInput({ placeholder: '请输入6位动态验证码', text: this.verifyCodeInput })
                    .type(InputType.Number)
                    .maxLength(6)
                    .layoutWeight(1)
                    .height(46)
                    .borderRadius(10)
                    .backgroundColor(this.store.colors.surfaceAlt)
                    .fontColor(this.store.colors.textPrimary)
                    .enabled(!this.isSubmitting)
                    .onChange((val: string) => {
                      this.verifyCodeInput = val;
                    })

                  Button(this.getSendButtonText())
                    .height(46)
                    .fontSize(13)
                    .fontColor(this.store.colors.accent)
                    .backgroundColor(this.store.colors.accentSoft)
                    .borderRadius(10)
                    .padding({ left: 14, right: 14 })
                    .enabled(!this.isSubmitting && !this.isSendingCode && this.resendCountdown === 0)
                    .onClick(() => {
                      this.handleSendCode();
                    })
                }
                .width('100%')
              }

              if (this.infoMsg.length > 0) {
                Text(this.infoMsg)
                  .fontSize(13)
                  .fontColor(this.store.colors.accent)
                  .width('100%')
              }

              if (this.errorMsg.length > 0) {
                Text(this.errorMsg)
                  .fontSize(13)
                  .fontColor(this.store.colors.danger)
                  .width('100%')
              }

              if (this.needsTwoStep) {
                Button(this.isSubmitting ? '验证并同步课表中...' : '验证并登录')
                  .width('100%')
                  .height(46)
                  .fontSize(15)
                  .fontColor(this.store.colors.onAccent)
                  .backgroundColor(this.store.colors.accent)
                  .borderRadius(12)
                  .enabled(!this.isSubmitting)
                  .onClick(() => {
                    this.handleVerifyCode();
                  })

                Button('返回修改账号密码')
                  .width('100%')
                  .height(38)
                  .fontSize(13)
                  .fontColor(this.store.colors.textSecondary)
                  .backgroundColor(this.store.colors.surfaceAlt)
                  .borderRadius(10)
                  .enabled(!this.isSubmitting)
                  .onClick(() => {
                    this.resetToCredentials();
                  })
              } else {
                Button(this.isSubmitting ? '正在认证...' : '登录')
                  .width('100%')
                  .height(46)
                  .fontSize(15)
                  .fontColor(this.store.colors.onAccent)
                  .backgroundColor(this.store.colors.accent)
                  .borderRadius(12)
                  .enabled(!this.isSubmitting)
                  .onClick(() => {
                    this.handleLogin();
                  })
              }
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.border })
            .alignItems(HorizontalAlign.Start)

            // Alternative Login Options
            Column({ space: 10 }) {
              Button() {
                Row({ space: 8 }) {
                  SymbolGlyph($r('sys.symbol.qrcode'))
                    .fontSize(18)
                    .fontColor([this.store.colors.textPrimary])
                  Text('使用企业微信扫码登录')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.store.colors.textPrimary)
                }
              }
              .width('100%')
              .height(46)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
              .borderRadius(12)
              .onClick(() => {
                this.store.setCampusSystem(this.selectedSystem);
                this.navStack.pushDestination({ name: 'WeComScanPage' });
              })

              Button('暂不登录，进入演示模式体验全部界面')
                .width('100%')
                .height(44)
                .fontSize(14)
                .fontColor(this.store.colors.accent)
                .backgroundColor(this.store.colors.accentSoft)
                .borderRadius(12)
                .onClick(() => {
                  this.store.enterDemoMode(this.selectedSystem);
                  this.navStack.pop();
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 28 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
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
