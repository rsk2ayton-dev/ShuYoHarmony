import {
  ShuYoCampusSystem,
  ShuYoLoginPageParam,
  ShuYoTabId
} from '../models/ShuYoModels';
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
  private store: ShuYoAppStore = ShuYoAppStore.instance();

  aboutToAppear(): void {
    this.store.initIfNeeded();
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

  @Builder
  private renderTabSymbol(tabId: ShuYoTabId, active: boolean) {
    if (tabId === ShuYoTabId.HOME) {
      SymbolGlyph($r(active ? 'sys.symbol.house_fill' : 'sys.symbol.house'))
        .fontSize(22)
        .fontColor([active ? this.store.colors.navSelected : this.store.colors.navUnselected])
    } else if (tabId === ShuYoTabId.RATE) {
      SymbolGlyph($r(active ? 'sys.symbol.star_fill' : 'sys.symbol.star'))
        .fontSize(22)
        .fontColor([active ? this.store.colors.navSelected : this.store.colors.navUnselected])
    } else if (tabId === ShuYoTabId.PROGRESS) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(22)
        .fontColor([active ? this.store.colors.navSelected : this.store.colors.navUnselected])
    } else {
      SymbolGlyph($r(active ? 'sys.symbol.calendar_fill' : 'sys.symbol.calendar'))
        .fontSize(22)
        .fontColor([active ? this.store.colors.navSelected : this.store.colors.navUnselected])
    }
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
        .borderRadius(16)
        .backgroundColor(this.store.colors.surface)
        .border({ width: 1, color: this.store.colors.border })

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
            .onClick(() => {
              this.openLoginFromOnboard();
            })

          Button('先体验一下（演示模式）')
            .width('100%')
            .height(46)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.store.colors.textPrimary)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.borderStrong })
            .borderRadius(14)
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
    .backgroundColor(this.store.colors.background)
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
        Column() {
          // Tab content
          Stack({ alignContent: Alignment.TopStart }) {
            if (this.getActiveTabId() === ShuYoTabId.HOME) {
              HomeDashboardView({ navStack: this.navStack })
            } else if (this.getActiveTabId() === ShuYoTabId.RATE) {
              RateHomeView({ navStack: this.navStack })
            } else if (this.getActiveTabId() === ShuYoTabId.PROGRESS) {
              AcademicProgressView()
            } else {
              AcademicScheduleView({ navStack: this.navStack })
            }
          }
          .layoutWeight(1)
          .width('100%')

          // Custom bottom navigation bar
          Row() {
            ForEach(this.store.supportedTabs, (tabId: ShuYoTabId, idx: number) => {
              Column({ space: 3 }) {
                this.renderTabSymbol(tabId, this.store.activeTabIndex === idx)
                Text(this.getTabLabel(tabId))
                  .fontSize(11)
                  .fontWeight(this.store.activeTabIndex === idx ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.getTabColor(idx))
              }
              .layoutWeight(1)
              .height(56)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                this.store.setActiveTabIndex(idx);
              })
            }, (tabId: ShuYoTabId, idx: number): string => `${tabId}-${idx}-${this.store.activeTabIndex}-${this.store.dataRevision}`)
          }
          .width('100%')
          .height(60)
          .backgroundColor(this.store.colors.surface)
          .border({ width: { top: 0.5 }, color: this.store.colors.border })
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
