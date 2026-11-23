import { ShuYoConstants } from '../../core/ShuYoConstants';
import { ShuYoThemes } from '../../core/ShuYoTheme';
import {
  ShuYoAnnouncementItem,
  ShuYoCampusSystem,
  ShuYoCourseSession,
  ShuYoHomeLayoutItem,
  ShuYoHomeModuleId,
  ShuYoLoginPageParam
} from '../../models/ShuYoModels';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { CampusCardService } from '../../services/CampusCardService';
import { ShuYoSectionHeader } from '../../components/ShuYoCommonViews';

interface ShuYoToolEntry {
  routeName: string;
  label: string;
  subtitle: string;
  symbolKind: string;
}

@ComponentV2
export struct HomeDashboardView {
  @Param navStack: NavPathStack = new NavPathStack();
  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private readonly toolEntries: ShuYoToolEntry[] = [
    { routeName: 'CourseRecordingsPage', label: '课程录播', subtitle: '课堂回放与直播', symbolKind: 'video' },
    { routeName: 'EmptyClassroomPage', label: '空教室', subtitle: '自习室查询', symbolKind: 'building' },
    { routeName: 'LibraryBookingPage', label: '图书馆预约', subtitle: '座位与规则', symbolKind: 'doc' },
    { routeName: 'CampusMapPage', label: '校园地图', subtitle: '三校区导航', symbolKind: 'map' },
    { routeName: 'OtpTokenPage', label: '动态口令', subtitle: '6位安全码', symbolKind: 'key' }
  ];

  private getIdentitySubtitle(): string {
    const sysLabel = this.store.campusSystem === ShuYoCampusSystem.GRADUATE ? '研究生' : '本科生';
    if (this.store.isDemoMode) {
      return `演示模式 · ${sysLabel} · 第${this.store.currentWeek}周`;
    }
    const idPart = this.store.studentId.length > 0 ? this.store.studentId : '未登录';
    return `${idPart} · ${sysLabel} · 第${this.store.currentWeek}周`;
  }

  private getGreetingText(): string {
    const h = new Date().getHours();
    if (h < 11) {
      return '早上好';
    }
    if (h < 14) {
      return '中午好';
    }
    if (h < 18) {
      return '下午好';
    }
    return '晚上好';
  }

  private getTodayWeekdayText(): string {
    const d = new Date().getDay();
    const idx = d === 0 ? 6 : d - 1;
    return ShuYoConstants.weekdayLabels[idx];
  }

  private getMonthSpendText(): string {
    const total = CampusCardService.computeRecentSpend(this.store.cardBills, 30);
    return `¥${total.toFixed(2)}`;
  }

  private getCardBalanceText(): string {
    if (this.store.cardInfo.isLoaded) {
      return `¥${this.store.cardInfo.balance.toFixed(2)}`;
    }
    if (this.store.isSyncingCampusCard) {
      return '同步中...';
    }
    return '暂未同步';
  }

  private getCardSubText(): string {
    if (this.store.cardInfo.isLoaded) {
      return `近30天累计消费 ${this.getMonthSpendText()}`;
    }
    if (this.store.isSyncingCampusCard) {
      return '正在查询校内一卡通余额与账单';
    }
    if (this.store.campusCardError.length > 0) {
      return this.store.campusCardError;
    }
    return '点击进入校园卡页面查询真实余额与账单';
  }

  private getCardBadgeText(): string {
    if (this.store.cardInfo.isLoaded) {
      return this.store.cardInfo.cardStatus;
    }
    return this.store.isSyncingCampusCard ? '同步中' : '未同步';
  }

  private getCardBadgeColor(): string {
    if (this.store.cardInfo.isLoaded) {
      return this.store.colors.success;
    }
    return this.store.colors.textTertiary;
  }

  private getEnabledModules(): ShuYoHomeLayoutItem[] {
    const list: ShuYoHomeLayoutItem[] = [];
    for (let i = 0; i < this.store.homeLayout.length; i++) {
      if (this.store.homeLayout[i].enabled) {
        list.push(this.store.homeLayout[i]);
      }
    }
    return list;
  }

  private openLogin(): void {
    const param: ShuYoLoginPageParam = { sourceLabel: 'home' };
    this.navStack.pushDestination({ name: 'NativeLoginPage', param: param });
  }

  @Builder
  private renderToolIcon(kind: string) {
    if (kind === 'video') {
      SymbolGlyph($r('sys.symbol.play_circle'))
        .fontSize(22)
        .fontColor([this.store.colors.accent])
    } else if (kind === 'building') {
      SymbolGlyph($r('sys.symbol.building'))
        .fontSize(22)
        .fontColor([this.store.colors.accent])
    } else if (kind === 'doc') {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(22)
        .fontColor([this.store.colors.accent])
    } else if (kind === 'map') {
      SymbolGlyph($r('sys.symbol.map'))
        .fontSize(22)
        .fontColor([this.store.colors.accent])
    } else {
      SymbolGlyph($r('sys.symbol.key'))
        .fontSize(22)
        .fontColor([this.store.colors.accent])
    }
  }

  @Builder
  private renderTodayCourseCard() {
    Column({ space: 12 }) {
      ShuYoSectionHeader({
        sectionTitle: `今日课程 (${this.getTodayWeekdayText()})`,
        actionLabel: '完整课表',
        onActionTap: () => {
          this.store.switchToScheduleTab();
        }
      })

      if (this.store.sessionsForToday().length === 0) {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.calendar'))
            .fontSize(20)
            .fontColor([this.store.colors.textMuted])
          Text('今天没有排课，祝学习生活愉快')
            .fontSize(14)
            .fontColor(this.store.colors.textTertiary)
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      } else {
        Column({ space: 8 }) {
          ForEach(this.store.sessionsForToday(), (session: ShuYoCourseSession, idx: number) => {
            Row({ space: 10 }) {
              Column()
                .width(4)
                .height(38)
                .borderRadius(2)
                .backgroundColor(ShuYoThemes.courseColorFor(session.courseName))

              Column({ space: 2 }) {
                Text(session.courseName)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.store.colors.textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${session.location.length > 0 ? session.location : '待定教室'} · ${session.teacherName}`)
                  .fontSize(12)
                  .fontColor(this.store.colors.textTertiary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column({ space: 2 }) {
                Text(`第${session.startSection}-${session.endSection}节`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.store.colors.accent)
                Text(ShuYoConstants.getPeriodTimeText(session.startSection, session.endSection))
                  .fontSize(11)
                  .fontColor(this.store.colors.textMuted)
              }
              .alignItems(HorizontalAlign.End)
            }
            .width('100%')
            .padding(10)
            .borderRadius(12)
            .backgroundColor(this.store.colors.surfaceAlt)
            .onClick(() => {
              this.store.switchToScheduleTab();
            })
          }, (session: ShuYoCourseSession, idx: number): string => `${session.id}-${idx}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(this.store.colors.surface)
    .border({ width: 1, color: this.store.colors.border })
  }

  @Builder
  private renderCampusCardSummary() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.creditcard'))
            .fontSize(16)
            .fontColor([this.store.colors.accent])
          Text('校园一卡通')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.store.colors.textSecondary)
        }
        Text(this.getCardBalanceText())
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.store.colors.textPrimary)
        Text(this.getCardSubText())
          .fontSize(12)
          .fontColor(this.store.colors.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column({ space: 4 }) {
        Text(this.getCardBadgeText())
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getCardBadgeColor())
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(10)
          .backgroundColor(this.store.colors.surfaceAlt)
        Row({ space: 4 }) {
          Text('明细')
            .fontSize(12)
            .fontColor(this.store.colors.accent)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([this.store.colors.accent])
        }
        .margin({ top: 6 })
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(this.store.colors.surface)
    .border({ width: 1, color: this.store.colors.border })
    .onClick(() => {
      this.navStack.pushDestination({ name: 'CampusCardPage' });
    })
  }

  @Builder
  private renderAnnouncementsCard() {
    Column({ space: 10 }) {
      ShuYoSectionHeader({
        sectionTitle: '通知公告',
        actionLabel: '查看全部',
        onActionTap: () => {
          this.navStack.pushDestination({ name: 'AnnouncementsPage' });
        }
      })

      ForEach(this.store.announcements.slice(0, 3), (item: ShuYoAnnouncementItem, idx: number) => {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.bell'))
            .fontSize(16)
            .fontColor([this.store.colors.accent])
          Column({ space: 2 }) {
            Text(item.title)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.store.colors.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${item.sourceName} · ${item.dateText}`)
              .fontSize(12)
              .fontColor(this.store.colors.textTertiary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 8, bottom: 8, left: 10, right: 10 })
        .borderRadius(10)
        .backgroundColor(this.store.colors.surfaceAlt)
        .onClick(() => {
          this.navStack.pushDestination({ name: 'AnnouncementsPage' });
        })
      }, (item: ShuYoAnnouncementItem, idx: number): string => `${item.id}-${idx}`)
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(this.store.colors.surface)
    .border({ width: 1, color: this.store.colors.border })
  }

  @Builder
  private renderCampusToolsCard() {
    Column({ space: 12 }) {
      ShuYoSectionHeader({
        sectionTitle: '校园服务',
        actionLabel: '',
        onActionTap: () => {}
      })

      Grid() {
        ForEach(this.toolEntries, (tool: ShuYoToolEntry, idx: number) => {
          GridItem() {
            Column({ space: 6 }) {
              this.renderToolIcon(tool.symbolKind)
              Text(tool.label)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.store.colors.textPrimary)
              Text(tool.subtitle)
                .fontSize(11)
                .fontColor(this.store.colors.textTertiary)
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .backgroundColor(this.store.colors.surfaceAlt)
            .alignItems(HorizontalAlign.Start)
            .onClick(() => {
              this.navStack.pushDestination({ name: tool.routeName });
            })
          }
        }, (tool: ShuYoToolEntry, idx: number): string => `${tool.routeName}-${idx}`)
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
      .height(272)
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(this.store.colors.surface)
    .border({ width: 1, color: this.store.colors.border })
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        // Header bar
        Row({ space: 10 }) {
          Image($rawfile('images/icon.png'))
            .width(38)
            .height(38)
            .borderRadius(10)
          Column({ space: 2 }) {
            Text(`${this.getGreetingText()}，${this.store.studentName}`)
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.store.colors.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.getIdentitySubtitle())
              .fontSize(12)
              .fontColor(this.store.colors.textTertiary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
              .fontSize(18)
              .fontColor([this.store.colors.textPrimary])
          }
          .width(36)
          .height(36)
          .backgroundColor(this.store.colors.surface)
          .border({ width: 1, color: this.store.colors.border })
          .onClick(() => {
            this.navStack.pushDestination({ name: 'HomeLayoutPage' });
          })

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(18)
              .fontColor([this.store.colors.textPrimary])
          }
          .width(36)
          .height(36)
          .backgroundColor(this.store.colors.surface)
          .border({ width: 1, color: this.store.colors.border })
          .onClick(() => {
            this.navStack.pushDestination({ name: 'SettingsPage' });
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.store.isDemoMode) {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.info_circle'))
              .fontSize(18)
              .fontColor([this.store.colors.accent])
            Text('当前为演示模式，部分数据为本地示例。')
              .fontSize(13)
              .fontColor(this.store.colors.textSecondary)
              .layoutWeight(1)
            Button('去登录')
              .height(28)
              .fontSize(12)
              .fontColor(this.store.colors.onAccent)
              .backgroundColor(this.store.colors.accent)
              .borderRadius(14)
              .padding({ left: 12, right: 12 })
              .onClick(() => {
                this.openLogin();
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .borderRadius(12)
          .backgroundColor(this.store.colors.accentSoft)
        }

        ForEach(this.getEnabledModules(), (mod: ShuYoHomeLayoutItem, idx: number) => {
          if (mod.id === ShuYoHomeModuleId.TODAY_COURSE) {
            this.renderTodayCourseCard()
          } else if (mod.id === ShuYoHomeModuleId.CAMPUS_CARD) {
            this.renderCampusCardSummary()
          } else if (mod.id === ShuYoHomeModuleId.ANNOUNCEMENTS) {
            this.renderAnnouncementsCard()
          } else if (mod.id === ShuYoHomeModuleId.CAMPUS_TOOLS) {
            this.renderCampusToolsCard()
          }
        }, (mod: ShuYoHomeLayoutItem, idx: number): string => `${mod.id}-${idx}-${this.store.dataRevision}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.store.colors.background)
    .scrollBar(BarState.Off)
  }
}
