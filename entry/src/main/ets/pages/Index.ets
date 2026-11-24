import {
  ShuYoCampusSystem,
  ShuYoLoginPageParam,
  ShuYoTabId
} from '../models/ShuYoModels';
import { ShuYoGlass, ShuYoMotion } from '../core/ShuYoMotionGlass';
import { NativeSystemService } from '../services/NativeSystemService';
import { ShuYoAppStore } from '../store/ShuYoAppStore';
import { HomeDashboardView } from './tabs/HomeDashboardView';
import { RateHomeView } from './tabs/RateHomeView';
import { AcademicProgressView } from './tabs/AcademicProgressView';
import { AcademicScheduleView } from './tabs/AcademicScheduleView';

@Entry
@ComponentV2
struct Index {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local selectedSystemOnboard: ShuYoCampusSystem = ShuYoCampusSystem.UNDERGRADUATE;
  @Local mountedHome: boolean = true;
  @Local mountedRate: boolean = false;
  @Local mountedProgress: boolean = false;
  @Local mountedSchedule: boolean = false;
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  aboutToAppear(): void {
    this.store.initIfNeeded();
    if (NativeSystemService.consumePendingLaunchTab() === 'schedule') {
      this.store.switchToScheduleTab();
    }
    this.markTabMounted(this.getActiveTabId());
  }

  private markTabMounted(tabId: ShuYoTabId): void {
    if (tabId === ShuYoTabId.HOME) {
      this.mountedHome = true;
    } else if (tabId === ShuYoTabId.RATE) {
      this.mountedRate = true;
    } else if (tabId === ShuYoTabId.PROGRESS) {
      this.mountedProgress = true;
    } else if (tabId === ShuYoTabId.SCHEDULE) {
      this.mountedSchedule = true;
    }
  }

  private switchTabWithMotion(idx: number): void {
    const tabs = this.store.supportedTabs;
    if (idx >= 0 && idx < tabs.length) {
      this.markTabMounted(tabs[idx]);
    }
    this.getUIContext()?.animateTo({
      duration: 260,
      curve: ShuYoMotion.snappySpring
    }, () => {
      this.store.setActiveTabIndex(idx);
    });
  }

  private getTabLabel(tabId: ShuYoTabId): string {
    if (tabId === ShuYoTabId.HOME) {
      return '首页';
    }
    if (tabId === ShuYoTabId.RATE) {
      return '课评';
    }
    if (tabId === ShuYoTabId.PROGRESS) {
      return '学业';
    }
    return '日程';
  }

  private getTabColor(idx: number): string {
    return this.store.activeTabIndex === idx
      ? this.store.colors.navSelected
      : this.store.colors.navUnselected;
  }

  private getSystemBtnBg(sys: ShuYoCampusSystem): string {
    return this.selectedSystemOnboard === sys
      ? this.store.colors.selectedFill
      : this.store.colors.surfaceAlt;
  }

  private getSystemBtnText(sys: ShuYoCampusSystem): string {
    return this.selectedSystemOnboard === sys
      ? this.store.colors.onSelectedFill
      : this.store.colors.textSecondary;
  }

  private getActiveTabId(): ShuYoTabId {
    const tabs = this.store.supportedTabs;
    if (this.store.activeTabIndex >= 0 && this.store.activeTabIndex < tabs.length) {
      return tabs[this.store.activeTabIndex];
    }
    return ShuYoTabId.HOME;
  }

  private openLoginFromOnboard(): void {
    this.store.setCampusSystem(this.selectedSystemOnboard);
    const param: ShuYoLoginPageParam = { sourceLabel: 'onboarding' };
    this.navStack.pushDestination({ name: 'NativeLoginPage', param: param }).catch(() => {});
  }

  private getTabSymbolResource(tabId: ShuYoTabId, active: boolean): Resource {
    if (tabId === ShuYoTabId.HOME) {
      return $r(active ? 'sys.symbol.house_fill' : 'sys.symbol.house');
    }
    if (tabId === ShuYoTabId.RATE) {
      return $r(active ? 'sys.symbol.star_fill' : 'sys.symbol.star');
    }
    if (tabId === ShuYoTabId.PROGRESS) {
      return $r('sys.symbol.doc_text');
    }
    return $r(active ? 'sys.symbol.calendar_fill' : 'sys.symbol.calendar');
  }

  @Builder
  private renderOnboarding() {
    Scroll() {
      Column({ space: 20 }) {
        Column({ space: 12 }) {
          Image($rawfile('images/icon.png'))
            .width(84)
            .height(84)
            .borderRadius(22)
          Text('SHU友')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.store.colors.textPrimary)
          Text('专为上海大学师生设计的校园一站式服务原生鸿蒙应用')
            .fontSize(14)
            .fontColor(this.store.colors.textTertiary)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ top: 36, bottom: 12 })
        .alignItems(HorizontalAlign.Center)

        // Feature summary card
        Column({ space: 12 }) {
          this.featureRow('课表与日程同步', '教务课表自动同步、周视图展示、自定义课程与分享')
          this.featureRow('课程评价与学业', '查看历届评课统计、成绩 GPA 绩点与培养方案进度')
          this.featureRow('校园工具箱', '空教室查询、校园一卡通、图书馆预约、三校区矢量地图与动态口令')
        }
        .width('100%')
        .padding(16)
        .borderRadius(18)
        .backgroundColor(Color.Transparent)
        .systemMaterial(ShuYoGlass.floatingCardMaterial(this.store.colors.isDark))

        // Campus system selection
        Column({ space: 8 }) {
          Text('选择您的学籍身份')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.store.colors.textSecondary)
          Row({ space: 10 }) {
            Button('本科生系统')
              .layoutWeight(1)
              .height(42)
              .fontSize(14)
              .fontColor(this.getSystemBtnText(ShuYoCampusSystem.UNDERGRADUATE))
              .backgroundColor(this.getSystemBtnBg(ShuYoCampusSystem.UNDERGRADUATE))
              .borderRadius(12)
              .clickEffect(ShuYoMotion.lightClick)
              .onClick(() => {
                this.selectedSystemOnboard = ShuYoCampusSystem.UNDERGRADUATE;
              })
            Button('研究生系统')
              .layoutWeight(1)
              .height(42)
              .fontSize(14)
              .fontColor(this.getSystemBtnText(ShuYoCampusSystem.GRADUATE))
              .backgroundColor(this.getSystemBtnBg(ShuYoCampusSystem.GRADUATE))
              .borderRadius(12)
              .clickEffect(ShuYoMotion.lightClick)
              .onClick(() => {
                this.selectedSystemOnboard = ShuYoCampusSystem.GRADUATE;
              })
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 10 }) {
          Button('登录上海大学统一身份认证')
            .width('100%')
            .height(48)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.store.colors.onAccent)
            .backgroundColor(this.store.colors.accent)
            .borderRadius(14)
            .clickEffect(ShuYoMotion.lightClick)
            .onClick(() => {
              this.openLoginFromOnboard();
            })

          Button('先体验一下（演示模式）')
            .width('100%')
            .height(46)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.store.colors.textPrimary)
            .backgroundColor(ShuYoGlass.cardSurfaceBg(this.store.colors))
            .border({ width: 1, color: this.store.colors.borderStrong })
            .borderRadius(14)
            .clickEffect(ShuYoMotion.lightClick)
            .onClick(() => {
              this.store.enterDemoMode(this.selectedSystemOnboard);
            })
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .width('100%')
      .padding({ left: 22, right: 22, bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 165,
      colors: ShuYoGlass.ambientGradientColors(this.store.colors)
    })
    .scrollBar(BarState.Off)
  }

  @Builder
  private featureRow(titleText: string, descText: string) {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.checkmark_circle'))
        .fontSize(20)
        .fontColor([this.store.colors.accent])
      Column({ space: 2 }) {
        Text(titleText)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.store.colors.textPrimary)
        Text(descText)
          .fontSize(12)
          .fontColor(this.store.colors.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Navigation(this.navStack) {
      if (!this.store.hasCompletedOnboarding) {
        this.renderOnboarding()
      } else {
        Stack({ alignContent: Alignment.Bottom }) {
          // Persistent lazy-mounted tabs layered over ambient gradient wash
          Stack({ alignContent: Alignment.TopStart }) {
            if (this.mountedHome || this.getActiveTabId() === ShuYoTabId.HOME) {
              Column() {
                HomeDashboardView({ navStack: this.navStack })
              }
              .width('100%')
              .height('100%')
              .visibility(this.getActiveTabId() === ShuYoTabId.HOME ? Visibility.Visible : Visibility.None)
              .opacity(this.getActiveTabId() === ShuYoTabId.HOME ? 1 : 0)
              .animation({ duration: 200, curve: Curve.FastOutSlowIn })
              .onAppear(() => {
                this.mountedHome = true;
              })
            }

            if (this.mountedRate || this.getActiveTabId() === ShuYoTabId.RATE) {
              Column() {
                RateHomeView({ navStack: this.navStack })
              }
              .width('100%')
              .height('100%')
              .visibility(this.getActiveTabId() === ShuYoTabId.RATE ? Visibility.Visible : Visibility.None)
              .opacity(this.getActiveTabId() === ShuYoTabId.RATE ? 1 : 0)
              .animation({ duration: 200, curve: Curve.FastOutSlowIn })
              .onAppear(() => {
                this.mountedRate = true;
              })
            }

            if (this.mountedProgress || this.getActiveTabId() === ShuYoTabId.PROGRESS) {
              Column() {
                AcademicProgressView({ navStack: this.navStack })
              }
              .width('100%')
              .height('100%')
              .visibility(this.getActiveTabId() === ShuYoTabId.PROGRESS ? Visibility.Visible : Visibility.None)
              .opacity(this.getActiveTabId() === ShuYoTabId.PROGRESS ? 1 : 0)
              .animation({ duration: 200, curve: Curve.FastOutSlowIn })
              .onAppear(() => {
                this.mountedProgress = true;
              })
            }

            if (this.mountedSchedule || this.getActiveTabId() === ShuYoTabId.SCHEDULE) {
              Column() {
                AcademicScheduleView({ navStack: this.navStack })
              }
              .width('100%')
              .height('100%')
              .visibility(this.getActiveTabId() === ShuYoTabId.SCHEDULE ? Visibility.Visible : Visibility.None)
              .opacity(this.getActiveTabId() === ShuYoTabId.SCHEDULE ? 1 : 0)
              .animation({ duration: 200, curve: Curve.FastOutSlowIn })
              .onAppear(() => {
                this.mountedSchedule = true;
              })
            }
          }
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 165,
            colors: ShuYoGlass.ambientGradientColors(this.store.colors)
          })

          // Floating HarmonyOS 7.0 liquid glass bottom dock
          Row() {
            ForEach(this.store.supportedTabs, (tabId: ShuYoTabId, idx: number) => {
              Column({ space: 2 }) {
                SymbolGlyph(this.getTabSymbolResource(tabId, this.store.activeTabIndex === idx))
                  .fontSize(21)
                  .fontColor([this.getTabColor(idx)])
                  .scale({
                    x: this.store.activeTabIndex === idx ? 1.08 : 1.0,
                    y: this.store.activeTabIndex === idx ? 1.08 : 1.0
                  })
                  .animation({ duration: 240, curve: ShuYoMotion.snappySpring })
                Text(this.getTabLabel(tabId))
                  .fontSize(10.5)
                  .fontWeight(this.store.activeTabIndex === idx ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(this.getTabColor(idx))
              }
              .layoutWeight(1)
              .height(50)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .borderRadius(22)
              .backgroundColor(
                this.store.activeTabIndex === idx
                  ? (this.store.colors.isDark ? '#30FFFFFF' : '#EBFFFFFF')
                  : Color.Transparent
              )
              .animation({ duration: 240, curve: ShuYoMotion.snappySpring })
              .clickEffect(ShuYoMotion.snappyClick)
              .onClick(() => {
                this.switchTabWithMotion(idx);
              })
            }, (tabId: ShuYoTabId): string => tabId)
          }
          .height(62)
          .borderRadius(31)
          .margin({ left: 16, right: 16, bottom: 10 })
          .padding({ left: 8, right: 8 })
          .alignItems(VerticalAlign.Center)
          .backgroundColor(Color.Transparent)
          .backgroundEffect(ShuYoGlass.floatingDockBlur(this.store.colors.isDark))
          .border({
            width: 1,
            color: this.store.colors.isDark ? '#38FFFFFF' : '#E6FFFFFF'
          })
          .shadow({
            radius: 24,
            color: this.store.colors.isDark ? '#66000000' : '#1E0F172A',
            offsetX: 0,
            offsetY: 8
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.store.colors.background)
      }
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
    .backgroundColor(this.store.colors.background)
  }
}
