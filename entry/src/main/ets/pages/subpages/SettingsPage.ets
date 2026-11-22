import { ShuYoConstants } from '../../core/ShuYoConstants';
import { ShuYoThemeSpec, ShuYoThemes } from '../../core/ShuYoTheme';
import { ShuYoCampusSystem } from '../../models/ShuYoModels';
import { PreferencesService } from '../../services/PreferencesService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function SettingsPageBuilder(): void {
  SettingsPage()
}

@ComponentV2
export struct SettingsPage {
  @Local navStack: NavPathStack = new NavPathStack();
  private store: ShuYoAppStore = ShuYoAppStore.instance();

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
    PreferencesService.clearAll();
    this.getUIContext().getPromptAction().showToast({ message: '本地偏好与缓存已清理' });
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
                SymbolGlyph($r('sys.symbol.person'))
                  .fontSize(22)
                  .fontColor([this.store.colors.accent])
                Column({ space: 2 }) {
                  Text(this.store.studentName)
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
              Text(`SHU友 HarmonyOS 原生版 v${ShuYoConstants.appVersion} (ArkUI V2)`)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.store.colors.textSecondary)
              Text(`改编自开源项目 shuosc/ShuYo · Bundle: ${ShuYoConstants.bundleName}`)
                .fontSize(11)
                .fontColor(this.store.colors.textMuted)
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
