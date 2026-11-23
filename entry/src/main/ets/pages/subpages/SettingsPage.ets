import { common } from '@kit.AbilityKit';
import { ShuYoThemeSpec, ShuYoThemes } from '../../core/ShuYoTheme';
import { ShuYoCampusSystem } from '../../models/ShuYoModels';
import { CampusCardService } from '../../services/CampusCardService';
import { CourseRecordingService } from '../../services/CourseRecordingService';
import { CourseReviewService } from '../../services/CourseReviewService';
import { ShuYoCookieJar } from '../../services/HttpClientService';
import { NativeSystemService, ShuYoBundleMeta } from '../../services/NativeSystemService';
import { PreferencesService } from '../../services/PreferencesService';
import { ScheduleWidgetService } from '../../services/ScheduleWidgetService';
import { SecureStorageService } from '../../services/SecureStorageService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function SettingsPageBuilder(): void {
  SettingsPage()
}

@ComponentV2
export struct SettingsPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local showNicknameSheet: boolean = false;
  @Local draftNickname: string = '';
  @Local bundleMeta: ShuYoBundleMeta = NativeSystemService.getBundleMeta();
  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private readonly leadMinuteOptions: number[] = [10, 15, 20, 30];

  private openNicknameEditor(): void {
    this.draftNickname = this.store.customNickname.length > 0
      ? this.store.customNickname
      : this.store.studentName;
    this.showNicknameSheet = true;
  }

  private saveNickname(): void {
    this.store.setCustomNickname(this.draftNickname);
    this.showNicknameSheet = false;
    this.getUIContext().getPromptAction().showToast({
      message: this.store.customNickname.length > 0 ? '昵称已更新' : '已恢复默认姓名'
    });
  }

  private resetNickname(): void {
    this.store.setCustomNickname('');
    this.showNicknameSheet = false;
    this.getUIContext().getPromptAction().showToast({ message: '已恢复默认姓名' });
  }

  @Builder
  private nicknameSheetBuilder() {
    Column({ space: 14 }) {
      Text('修改个人昵称')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.store.colors.textPrimary)

      Text(`系统姓名：${this.store.studentName}（留空将显示系统默认姓名）`)
        .fontSize(12)
        .fontColor(this.store.colors.textTertiary)

      TextInput({ placeholder: '输入自定义昵称（最多 20 字）', text: this.draftNickname })
        .height(44)
        .maxLength(20)
        .fontSize(15)
        .fontColor(this.store.colors.textPrimary)
        .backgroundColor(this.store.colors.surfaceAlt)
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .onChange((val: string) => {
          this.draftNickname = val;
        })

      Row({ space: 10 }) {
        Button('恢复默认')
          .height(42)
          .fontSize(14)
          .fontColor(this.store.colors.textSecondary)
          .backgroundColor(this.store.colors.surfaceAlt)
          .border({ width: 1, color: this.store.colors.border })
          .borderRadius(12)
          .padding({ left: 14, right: 14 })
          .onClick(() => {
            this.resetNickname();
          })

        Button('保存昵称')
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor(this.store.colors.onAccent)
          .backgroundColor(this.store.colors.accent)
          .borderRadius(12)
          .onClick(() => {
            this.saveNickname();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 28 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.store.colors.surface)
  }

  private getIdentityStatus(): string {
    if (this.store.isDemoMode) {
      return '演示模式 (DEMO0001)';
    }
    if (this.store.isLoggedIn) {
      return `已登录 (${this.store.studentId})`;
    }
    return '未登录';
  }

  private getSysBg(sys: ShuYoCampusSystem): string {
    return this.store.campusSystem === sys ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getSysText(sys: ShuYoCampusSystem): string {
    return this.store.campusSystem === sys ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      title: '退出当前账号',
      message: '退出后将清除本地认证会话并返回欢迎引导页，确定继续吗？',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '退出登录',
        action: () => {
          this.store.logout();
          this.navStack.clear();
        }
      }
    });
  }

  private clearCache(): void {
    ShuYoCookieJar.clearAll();
    CampusCardService.clearSession();
    CourseRecordingService.clearSession();
    CourseReviewService.clearStudentToken();
    PreferencesService.clearAll();
    this.store.refreshNativeIntegrations();
    this.getUIContext().getPromptAction().showToast({ message: '本地偏好、会话与缓存已清理' });
  }

  private async handleReminderToggle(val: boolean): Promise<void> {
    if (val === this.store.reminderEnabled) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const msg = await this.store.setReminderEnabled(val, ctx);
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  private async handleLeadSelect(mins: number): Promise<void> {
    if (mins === this.store.reminderLeadMinutes) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const msg = await this.store.setReminderLeadMinutes(mins, ctx);
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  private async handleReloadWidgets(): Promise<void> {
    this.store.refreshNativeIntegrations();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const count = await ScheduleWidgetService.reloadWidgets(ctx);
    this.getUIContext().getPromptAction().showToast({
      message: count > 0 ? `已刷新 ${count} 张桌面课表卡片` : '桌面卡片快照已更新，可从桌面添加“今日课表”'
    });
  }

  build() {
    NavDestination() {
      Column() {
        ShuYoTopBar({
          headerTitle: '设置与外观',
          subtitleText: 'SHU友 原生鸿蒙版',
          showBack: true,
          rightLabel: '',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {}
        })

        Scroll() {
          Column({ space: 14 }) {
            // Account Card
            Column({ space: 12 }) {
              Row({ space: 10 }) {
                if (this.store.customAvatarUri.length > 0) {
                  Image(this.store.customAvatarUri)
                    .width(46)
                    .height(46)
                    .borderRadius(23)
                    .objectFit(ImageFit.Cover)
                    .onClick(() => {
                      this.navStack.pushDestination({ name: 'AvatarCropPage' });
                    })
                } else {
                  Column() {
                    SymbolGlyph($r('sys.symbol.person'))
                      .fontSize(22)
                      .fontColor([this.store.colors.accent])
                  }
                  .width(46)
                  .height(46)
                  .borderRadius(23)
                  .backgroundColor(this.store.colors.accentSoft)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .onClick(() => {
                    this.navStack.pushDestination({ name: 'AvatarCropPage' });
                  })
                }
                Column({ space: 2 }) {
                  Text(this.store.displayName)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.store.colors.textPrimary)
                  Text(this.getIdentityStatus())
                    .fontSize(12)
                    .fontColor(this.store.colors.textTertiary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button(this.store.isDemoMode ? '登录账号' : '切换账号')
                  .height(32)
                  .fontSize(12)
                  .fontColor(this.store.colors.onAccent)
                  .backgroundColor(this.store.colors.accent)
                  .borderRadius(16)
                  .padding({ left: 12, right: 12 })
                  .onClick(() => {
                    this.navStack.pushDestination({ name: 'NativeLoginPage' });
                  })
              }
              .width('100%')

              Row({ space: 8 }) {
                Button('修改昵称')
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(12)
                  .fontColor(this.store.colors.textPrimary)
                  .backgroundColor(this.store.colors.surfaceAlt)
                  .border({ width: 1, color: this.store.colors.border })
                  .borderRadius(10)
                  .onClick(() => {
                    this.openNicknameEditor();
                  })

                Button('更换头像')
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(12)
                  .fontColor(this.store.colors.accent)
                  .backgroundColor(this.store.colors.accentSoft)
                  .borderRadius(10)
                  .onClick(() => {
                    this.navStack.pushDestination({ name: 'AvatarCropPage' });
                  })
              }
              .width('100%')

              Row({ space: 10 }) {
                Text('学籍系统')
                  .fontSize(13)
                  .fontColor(this.store.colors.textSecondary)
                Blank()
                Button('本科生')
                  .height(30)
                  .fontSize(12)
                  .fontColor(this.getSysText(ShuYoCampusSystem.UNDERGRADUATE))
                  .backgroundColor(this.getSysBg(ShuYoCampusSystem.UNDERGRADUATE))
                  .borderRadius(14)
                  .padding({ left: 12, right: 12 })
                  .onClick(() => {
                    this.store.setCampusSystem(ShuYoCampusSystem.UNDERGRADUATE);
                  })
                Button('研究生')
                  .height(30)
                  .fontSize(12)
                  .fontColor(this.getSysText(ShuYoCampusSystem.GRADUATE))
                  .backgroundColor(this.getSysBg(ShuYoCampusSystem.GRADUATE))
                  .borderRadius(14)
                  .padding({ left: 12, right: 12 })
                  .onClick(() => {
                    this.store.setCampusSystem(ShuYoCampusSystem.GRADUATE);
                  })
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.border })
            .bindSheet($$this.showNicknameSheet, this.nicknameSheetBuilder(), {
              height: SheetSize.FIT_CONTENT,
              dragBar: true,
              showClose: true
            })

            // Theme Picker Card
            Column({ space: 12 }) {
              Text('主题配色')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.textPrimary)

              Grid() {
                ForEach(ShuYoThemes.all, (spec: ShuYoThemeSpec, idx: number) => {
                  GridItem() {
                    Column({ space: 6 }) {
                      Row({ space: 4 }) {
                        Column()
                          .width(14)
                          .height(14)
                          .borderRadius(7)
                          .backgroundColor(spec.colors.background)
                          .border({ width: 0.5, color: spec.colors.borderStrong })
                        Column()
                          .width(14)
                          .height(14)
                          .borderRadius(7)
                          .backgroundColor(spec.colors.accent)
                      }
                      Text(spec.name)
                        .fontSize(11)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .fontWeight(this.store.themeId === spec.id ? FontWeight.Bold : FontWeight.Normal)
                        .fontColor(this.store.colors.textPrimary)
                    }
                    .width('100%')
                    .padding(10)
                    .borderRadius(12)
                    .backgroundColor(this.store.themeId === spec.id ? this.store.colors.accentSoft : this.store.colors.surfaceAlt)
                    .border({
                      width: this.store.themeId === spec.id ? 1.5 : 1,
                      color: this.store.themeId === spec.id ? this.store.colors.accent : this.store.colors.border
                    })
                    .onClick(() => {
                      this.store.setTheme(spec.id);
                    })
                  }
                }, (spec: ShuYoThemeSpec, idx: number): string => `thm-${spec.id}-${this.store.themeId}`)
              }
              .columnsTemplate('1fr 1fr 1fr')
              .columnsGap(8)
              .rowsGap(8)
              .width('100%')
              .height(222)
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.border })
            .alignItems(HorizontalAlign.Start)

            // Native HarmonyOS Kits Card
            Column({ space: 12 }) {
              Text('鸿蒙原生系统能力 (Beta)')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.textPrimary)

              Row() {
                Column({ space: 2 }) {
                  Text('课前系统代理提醒')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.store.colors.textPrimary)
                  Text(this.store.reminderStatusText.length > 0
                    ? this.store.reminderStatusText
                    : '基于 BackgroundTasksKit 自动调度未来 7 天上课提醒')
                    .fontSize(12)
                    .fontColor(this.store.colors.textTertiary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.store.reminderEnabled })
                  .selectedColor(this.store.colors.accent)
                  .onChange((val: boolean) => {
                    this.handleReminderToggle(val);
                  })
              }
              .width('100%')

              Row({ space: 6 }) {
                Text('提前时间')
                  .fontSize(12)
                  .fontColor(this.store.colors.textSecondary)
                Blank()
                ForEach(this.leadMinuteOptions, (mins: number) => {
                  Button(`${mins}分`)
                    .height(26)
                    .fontSize(11)
                    .fontColor(
                      this.store.reminderLeadMinutes === mins
                        ? this.store.colors.onSelectedFill
                        : this.store.colors.textSecondary
                    )
                    .backgroundColor(
                      this.store.reminderLeadMinutes === mins
                        ? this.store.colors.selectedFill
                        : this.store.colors.chipFill
                    )
                    .borderRadius(13)
                    .padding({ left: 10, right: 10 })
                    .onClick(() => {
                      this.handleLeadSelect(mins);
                    })
                }, (mins: number): string => `lead-${mins}`)
              }
              .width('100%')

              Divider().color(this.store.colors.border)

              Row() {
                Column({ space: 2 }) {
                  Text('桌面万能卡片 (Form Kit)')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.store.colors.textPrimary)
                  Text('支持桌面 2×2 / 2×4 今日课表卡片及定时更新')
                    .fontSize(12)
                    .fontColor(this.store.colors.textTertiary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Button('刷新卡片')
                  .height(30)
                  .fontSize(12)
                  .fontColor(this.store.colors.accent)
                  .backgroundColor(this.store.colors.accentSoft)
                  .borderRadius(15)
                  .padding({ left: 12, right: 12 })
                  .onClick(() => {
                    this.handleReloadWidgets();
                  })
              }
              .width('100%')

              Divider().color(this.store.colors.border)

              Row() {
                Text('敏感会话加密存储')
                  .fontSize(13)
                  .fontColor(this.store.colors.textSecondary)
                Blank()
                Text(SecureStorageService.isHardwareBacked() ? 'Asset Store Kit 保护中' : '兼容存储模式')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(
                    SecureStorageService.isHardwareBacked()
                      ? this.store.colors.success
                      : this.store.colors.textTertiary
                  )
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.border })
            .alignItems(HorizontalAlign.Start)

            // Network & Layout Card
            Column({ space: 12 }) {
              Row() {
                Column({ space: 2 }) {
                  Text('默认启用 WebVPN')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.store.colors.textPrimary)
                  Text('校外访问空教室与动态口令默认走校园 WebVPN')
                    .fontSize(12)
                    .fontColor(this.store.colors.textTertiary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.store.useWebVpn })
                  .selectedColor(this.store.colors.accent)
                  .onChange((val: boolean) => {
                    this.store.setUseWebVpn(val);
                  })
              }
              .width('100%')

              Divider().color(this.store.colors.border)

              Row() {
                Text('首页模块排版设置')
                  .fontSize(14)
                  .fontColor(this.store.colors.textPrimary)
                Blank()
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([this.store.colors.textMuted])
              }
              .width('100%')
              .height(36)
              .onClick(() => {
                this.navStack.pushDestination({ name: 'HomeLayoutPage' });
              })

              Divider().color(this.store.colors.border)

              Row() {
                Text('项目贡献者')
                  .fontSize(14)
                  .fontColor(this.store.colors.textPrimary)
                Blank()
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([this.store.colors.textMuted])
              }
              .width('100%')
              .height(36)
              .onClick(() => {
                this.navStack.pushDestination({ name: 'ContributorsPage' });
              })

              Divider().color(this.store.colors.border)

              Row() {
                Text('清除本地缓存')
                  .fontSize(14)
                  .fontColor(this.store.colors.warning)
                Blank()
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(16)
                  .fontColor([this.store.colors.warning])
              }
              .width('100%')
              .height(36)
              .onClick(() => {
                this.clearCache();
              })
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.border })

            // About & Logout
            Column({ space: 6 }) {
              Text(`SHU友 HarmonyOS 原生版 v${this.bundleMeta.versionName} · Build ${this.bundleMeta.versionCode}`)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.store.colors.textSecondary)
              Text(`改编自开源项目 shuosc/ShuYo · Bundle: ${this.bundleMeta.bundleName}`)
                .fontSize(11)
                .fontColor(this.store.colors.textMuted)
              Text('查看 ShuYoHarmony 开源仓库')
                .fontSize(12)
                .fontColor(this.store.colors.accent)
                .onClick(() => {
                  NativeSystemService.openExternalUrl('https://github.com/rsk2ayton-dev/ShuYoHarmony', this.getUIContext());
                })
            }
            .width('100%')
            .padding(12)
            .alignItems(HorizontalAlign.Center)

            Button('退出当前会话 / 重新选择身份')
              .width('100%')
              .height(44)
              .fontSize(14)
              .fontColor(this.store.colors.onDanger)
              .backgroundColor(this.store.colors.danger)
              .borderRadius(12)
              .onClick(() => {
                this.confirmLogout();
              })
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
