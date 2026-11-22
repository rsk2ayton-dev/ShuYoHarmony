import { ShuYoConstants } from '../../core/ShuYoConstants';
import { ShuYoThemes } from '../../core/ShuYoTheme';
import {
  ShuYoCourseSession,
  ShuYoScheduleEditorParam,
  ShuYoUntimedCourse
} from '../../models/ShuYoModels';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';

@ComponentV2
export struct AcademicScheduleView {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local selectedSession: ShuYoCourseSession | undefined = undefined;
  @Local showDetailSheet: boolean = false;
  @Local showDayListMode: boolean = false;
  @Local selectedDayFilter: number = 1;
  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private readonly sectionNumbers: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
  private readonly weekdayNumbers: number[] = [1, 2, 3, 4, 5, 6, 7];
  private readonly rowHeight: number = 52;

  aboutToAppear(): void {
    const jsDay = new Date().getDay();
    this.selectedDayFilter = jsDay === 0 ? 7 : jsDay;
  }

  private getWeekList(): number[] {
    const maxW = this.store.scheduleData.maxWeek > 0 ? this.store.scheduleData.maxWeek : 16;
    const arr: number[] = [];
    for (let i = 1; i <= maxW; i++) {
      arr.push(i);
    }
    return arr;
  }

  private getSessionsForCurrentWeek(): ShuYoCourseSession[] {
    const list: ShuYoCourseSession[] = [];
    const week = this.store.currentWeek;
    for (let i = 0; i < this.store.scheduleData.sessions.length; i++) {
      const s = this.store.scheduleData.sessions[i];
      if (s.weeks.length === 0 || s.weeks.includes(week)) {
        list.push(s);
      }
    }
    return list;
  }

  private getSessionsForDay(weekday: number): ShuYoCourseSession[] {
    const all = this.getSessionsForCurrentWeek();
    const out: ShuYoCourseSession[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].weekday === weekday) {
        out.push(all[i]);
      }
    }
    out.sort((a: ShuYoCourseSession, b: ShuYoCourseSession): number => a.startSection - b.startSection);
    return out;
  }

  private getUntimedForCurrentWeek(): ShuYoUntimedCourse[] {
    const week = this.store.currentWeek;
    const out: ShuYoUntimedCourse[] = [];
    for (let i = 0; i < this.store.scheduleData.untimedCourses.length; i++) {
      const u = this.store.scheduleData.untimedCourses[i];
      if (u.weeks.length === 0 || u.weeks.includes(week)) {
        out.push(u);
      }
    }
    return out;
  }

  private getWeekChipBg(w: number): string {
    return this.store.currentWeek === w ? this.store.colors.accent : this.store.colors.chipFill;
  }

  private getWeekChipText(w: number): string {
    return this.store.currentWeek === w ? this.store.colors.onAccent : this.store.colors.textSecondary;
  }

  private getDayTabBg(d: number): string {
    return this.selectedDayFilter === d ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getDayTabText(d: number): string {
    return this.selectedDayFilter === d ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private getCardTop(s: ShuYoCourseSession): number {
    const start = s.startSection >= 1 ? s.startSection : 1;
    return (start - 1) * this.rowHeight + 2;
  }

  private getCardHeight(s: ShuYoCourseSession): number {
    const start = s.startSection >= 1 ? s.startSection : 1;
    const end = s.endSection >= start ? s.endSection : start;
    const span = end - start + 1;
    return span * this.rowHeight - 4;
  }

  private openAddCourse(): void {
    const param: ShuYoScheduleEditorParam = {
      sessionId: '',
      defaultWeekday: this.selectedDayFilter
    };
    this.navStack.pushDestination({ name: 'ScheduleEditorPage', param: param });
  }

  private openEditCourse(sessionId: string, weekday: number): void {
    this.showDetailSheet = false;
    const param: ShuYoScheduleEditorParam = {
      sessionId: sessionId,
      defaultWeekday: weekday
    };
    this.navStack.pushDestination({ name: 'ScheduleEditorPage', param: param });
  }

  private async handleSync(): Promise<void> {
    const msg = await this.store.syncSchedule();
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  private getEmptyTitle(): string {
    return this.store.isLoggedIn ? '尚未同步到课程表数据' : '尚未登录校园账号';
  }

  private getEmptySubtitle(): string {
    if (!this.store.isDemoMode && this.store.statusBanner.length > 0) {
      return this.store.statusBanner;
    }
    if (this.store.isLoggedIn) {
      return '点击“立即同步课表”从学校系统获取本学期个人课程安排';
    }
    return '使用上海大学统一身份认证登录后即可自动同步真实课表（支持二步验证）';
  }

  @Builder
  private courseDetailSheetBuilder() {
    Column({ space: 14 }) {
      if (this.selectedSession !== undefined) {
        Text(this.selectedSession.courseName)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.store.colors.textPrimary)

        Column({ space: 8 }) {
          this.detailRow('上课时间',
            `${ShuYoConstants.weekdayLabels[Math.max(0, Math.min(6, this.selectedSession.weekday - 1))]} 第${this.selectedSession.startSection}-${this.selectedSession.endSection}节 (${ShuYoConstants.getPeriodTimeText(this.selectedSession.startSection, this.selectedSession.endSection)})`)
          this.detailRow('上课地点',
            this.selectedSession.location.length > 0 ? `${this.selectedSession.campus} ${this.selectedSession.location}` : '未指定')
          this.detailRow('授课教师', this.selectedSession.teacherName.length > 0 ? this.selectedSession.teacherName : '未指定')
          this.detailRow('上课周次', this.selectedSession.weekText.length > 0 ? this.selectedSession.weekText : '全学期')
          if (this.selectedSession.courseCode.length > 0) {
            this.detailRow('课程代码', this.selectedSession.courseCode)
          }
          if (this.selectedSession.credit.length > 0) {
            this.detailRow('学分', this.selectedSession.credit)
          }
          if (this.selectedSession.note.length > 0) {
            this.detailRow('备注', this.selectedSession.note)
          }
        }
        .width('100%')
        .padding(14)
        .borderRadius(14)
        .backgroundColor(this.store.colors.surfaceAlt)

        Row({ space: 12 }) {
          Button('编辑课程')
            .layoutWeight(1)
            .height(42)
            .fontSize(14)
            .fontColor(this.store.colors.onAccent)
            .backgroundColor(this.store.colors.accent)
            .borderRadius(12)
            .onClick(() => {
              if (this.selectedSession !== undefined) {
                this.openEditCourse(this.selectedSession.id, this.selectedSession.weekday);
              }
            })

          Button('删除')
            .width(96)
            .height(42)
            .fontSize(14)
            .fontColor(this.store.colors.onDanger)
            .backgroundColor(this.store.colors.danger)
            .borderRadius(12)
            .onClick(() => {
              if (this.selectedSession !== undefined) {
                this.store.deleteCourseSession(this.selectedSession.id);
                this.showDetailSheet = false;
                this.getUIContext().getPromptAction().showToast({ message: '已删除该课程安排' });
              }
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 28 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.store.colors.surface)
  }

  @Builder
  private detailRow(label: string, val: string) {
    Row({ space: 10 }) {
      Text(label)
        .width(72)
        .fontSize(13)
        .fontColor(this.store.colors.textTertiary)
      Text(val)
        .layoutWeight(1)
        .fontSize(14)
        .fontColor(this.store.colors.textPrimary)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Column({ space: 8 }) {
      // Top Header
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(`第 ${this.store.currentWeek} 周`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.store.colors.textPrimary)
          Text(`${this.store.scheduleData.term.academicYearName} ${this.store.scheduleData.term.termName}`)
            .fontSize(12)
            .fontColor(this.store.colors.textTertiary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .onClick(() => {
          this.navStack.pushDestination({ name: 'ScheduleCollectionPage' });
        })

        Button(this.showDayListMode ? '周视图' : '列表')
          .height(32)
          .fontSize(12)
          .fontColor(this.store.colors.textPrimary)
          .backgroundColor(this.store.colors.surface)
          .border({ width: 1, color: this.store.colors.border })
          .borderRadius(16)
          .padding({ left: 10, right: 10 })
          .onClick(() => {
            this.showDayListMode = !this.showDayListMode;
          })

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.upload'))
            .fontSize(16)
            .fontColor([this.store.colors.textPrimary])
        }
        .width(34)
        .height(34)
        .backgroundColor(this.store.colors.surface)
        .border({ width: 1, color: this.store.colors.border })
        .onClick(() => {
          this.navStack.pushDestination({ name: 'ScheduleSharePage' });
        })

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(16)
            .fontColor([this.store.colors.textPrimary])
        }
        .width(34)
        .height(34)
        .backgroundColor(this.store.colors.surface)
        .border({ width: 1, color: this.store.colors.border })
        .onClick(() => {
          this.handleSync();
        })

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(16)
            .fontColor([this.store.colors.onAccent])
        }
        .width(34)
        .height(34)
        .backgroundColor(this.store.colors.accent)
        .onClick(() => {
          this.openAddCourse();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })

      // Week Selector Strip
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.getWeekList(), (w: number, idx: number) => {
            Button(`第${w}周`)
              .height(28)
              .fontSize(12)
              .fontColor(this.getWeekChipText(w))
              .backgroundColor(this.getWeekChipBg(w))
              .borderRadius(14)
              .padding({ left: 10, right: 10 })
              .onClick(() => {
                this.store.setCurrentWeek(w);
              })
          }, (w: number, idx: number): string => `week-${w}`)
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(32)

      if (this.store.isSyncingSchedule) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(this.store.colors.accent)
          Text('正在从教务系统同步真实课表...')
            .fontSize(12)
            .fontColor(this.store.colors.accent)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        .backgroundColor(this.store.colors.accentSoft)
      } else if (!this.store.isDemoMode && this.store.statusBanner.length > 0) {
        Row({ space: 8 }) {
          Text(this.store.statusBanner)
            .fontSize(12)
            .fontColor(this.store.colors.danger)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Button('重试')
            .height(26)
            .fontSize(11)
            .fontColor(this.store.colors.onAccent)
            .backgroundColor(this.store.colors.accent)
            .borderRadius(13)
            .padding({ left: 10, right: 10 })
            .onClick(() => {
              this.handleSync();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        .backgroundColor(this.store.colors.surfaceAlt)
      }

      if (!this.store.isDemoMode &&
        !this.store.isSyncingSchedule &&
        this.store.scheduleData.sessions.length === 0) {
        Column() {
          Column({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(44)
              .fontColor([this.store.colors.accent])
            Text(this.getEmptyTitle())
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.store.colors.textPrimary)
            Text(this.getEmptySubtitle())
              .fontSize(13)
              .fontColor(this.store.colors.textSecondary)
              .textAlign(TextAlign.Center)
            Row({ space: 12 }) {
              if (this.store.isLoggedIn) {
                Button('立即同步课表')
                  .layoutWeight(1)
                  .height(42)
                  .fontSize(14)
                  .fontColor(this.store.colors.onAccent)
                  .backgroundColor(this.store.colors.accent)
                  .borderRadius(12)
                  .onClick(() => {
                    this.handleSync();
                  })
                Button('重新登录')
                  .layoutWeight(1)
                  .height(42)
                  .fontSize(14)
                  .fontColor(this.store.colors.textPrimary)
                  .backgroundColor(this.store.colors.surfaceAlt)
                  .border({ width: 1, color: this.store.colors.border })
                  .borderRadius(12)
                  .onClick(() => {
                    this.navStack.pushDestination({ name: 'NativeLoginPage' });
                  })
              } else {
                Button('前往统一认证登录')
                  .layoutWeight(1)
                  .height(42)
                  .fontSize(14)
                  .fontColor(this.store.colors.onAccent)
                  .backgroundColor(this.store.colors.accent)
                  .borderRadius(12)
                  .onClick(() => {
                    this.navStack.pushDestination({ name: 'NativeLoginPage' });
                  })
                Button('手动添加课程')
                  .layoutWeight(1)
                  .height(42)
                  .fontSize(14)
                  .fontColor(this.store.colors.textPrimary)
                  .backgroundColor(this.store.colors.surfaceAlt)
                  .border({ width: 1, color: this.store.colors.border })
                  .borderRadius(12)
                  .onClick(() => {
                    this.openAddCourse();
                  })
              }
            }
            .width('100%')
          }
          .width('100%')
          .padding(24)
          .borderRadius(18)
          .backgroundColor(this.store.colors.surface)
          .border({ width: 1, color: this.store.colors.border })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 28 })
        .layoutWeight(1)
      } else if (this.showDayListMode) {
        // Day selector + list view
        Row({ space: 6 }) {
          ForEach(this.weekdayNumbers, (dayNum: number, idx: number) => {
            Button(ShuYoConstants.weekdayLabels[dayNum - 1])
              .layoutWeight(1)
              .height(30)
              .fontSize(12)
              .fontColor(this.getDayTabText(dayNum))
              .backgroundColor(this.getDayTabBg(dayNum))
              .borderRadius(10)
              .onClick(() => {
                this.selectedDayFilter = dayNum;
              })
          }, (dayNum: number, idx: number): string => `daybtn-${dayNum}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        List({ space: 10 }) {
          ForEach(this.getSessionsForDay(this.selectedDayFilter), (s: ShuYoCourseSession, idx: number) => {
            ListItem() {
              Row({ space: 12 }) {
                Column()
                  .width(5)
                  .height(44)
                  .borderRadius(3)
                  .backgroundColor(ShuYoThemes.courseColorFor(s.courseName))
                Column({ space: 3 }) {
                  Text(s.courseName)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.store.colors.textPrimary)
                  Text(`第${s.startSection}-${s.endSection}节 · ${s.location} · ${s.teacherName}`)
                    .fontSize(12)
                    .fontColor(this.store.colors.textTertiary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding(14)
              .borderRadius(14)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
              .onClick(() => {
                this.selectedSession = s;
                this.showDetailSheet = true;
              })
            }
          }, (s: ShuYoCourseSession, idx: number): string => `list-${s.id}-${idx}`)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 16 })
      } else {
        // 7-day Timetable Grid Header
        Row() {
          Text('节')
            .width(34)
            .fontSize(11)
            .textAlign(TextAlign.Center)
            .fontColor(this.store.colors.textMuted)
          ForEach(this.weekdayNumbers, (dayNum: number, idx: number) => {
            Text(ShuYoConstants.weekdayLabels[dayNum - 1])
              .layoutWeight(1)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .textAlign(TextAlign.Center)
              .fontColor(this.store.colors.textSecondary)
          }, (dayNum: number, idx: number): string => `hdr-${dayNum}`)
        }
        .width('100%')
        .padding({ left: 6, right: 6, top: 4, bottom: 4 })

        // Timetable Body
        Scroll() {
          Column({ space: 12 }) {
            Row() {
              // Left Period Index Column
              Column() {
                ForEach(this.sectionNumbers, (sec: number, idx: number) => {
                  Column({ space: 1 }) {
                    Text(String(sec))
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.store.colors.textSecondary)
                    Text(ShuYoConstants.classPeriods[sec - 1].startTime)
                      .fontSize(8)
                      .fontColor(this.store.colors.textMuted)
                  }
                  .width(34)
                  .height(this.rowHeight)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                }, (sec: number, idx: number): string => `sec-${sec}`)
              }
              .width(34)

              // 7 Day Columns
              ForEach(this.weekdayNumbers, (dayNum: number, idx: number) => {
                Stack({ alignContent: Alignment.TopStart }) {
                  // Background grid cells
                  Column() {
                    ForEach(this.sectionNumbers, (sec: number, rIdx: number) => {
                      Row()
                        .width('100%')
                        .height(this.rowHeight)
                        .border({ width: { bottom: 0.5, right: 0.5 }, color: this.store.colors.border })
                    }, (sec: number, rIdx: number): string => `bg-${dayNum}-${sec}`)
                  }
                  .width('100%')

                  // Course Blocks
                  ForEach(this.getSessionsForDay(dayNum), (session: ShuYoCourseSession, sIdx: number) => {
                    Column({ space: 2 }) {
                      Text(session.courseName)
                        .fontSize(10)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#FFFFFF')
                        .maxLines(3)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (session.location.length > 0) {
                        Text(session.location)
                          .fontSize(9)
                          .fontColor('#FFFFFF')
                          .opacity(0.92)
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                    }
                    .width('94%')
                    .height(this.getCardHeight(session))
                    .margin({ left: '3%' })
                    .position({ x: 0, y: this.getCardTop(session) })
                    .padding(4)
                    .borderRadius(7)
                    .backgroundColor(ShuYoThemes.courseColorFor(session.courseName))
                    .alignItems(HorizontalAlign.Start)
                    .onClick(() => {
                      this.selectedSession = session;
                      this.showDetailSheet = true;
                    })
                  }, (session: ShuYoCourseSession, sIdx: number): string => `blk-${session.id}-${sIdx}-${this.store.currentWeek}-${this.store.dataRevision}`)
                }
                .layoutWeight(1)
                .height(this.rowHeight * 12)
              }, (dayNum: number, idx: number): string => `col-${dayNum}-${this.store.currentWeek}-${this.store.dataRevision}`)
            }
            .width('100%')
            .padding({ left: 6, right: 6 })
            .alignItems(VerticalAlign.Top)

            if (this.getUntimedForCurrentWeek().length > 0) {
              Column({ space: 8 }) {
                Text('实践 / 未排定时间课程')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.store.colors.textSecondary)
                ForEach(this.getUntimedForCurrentWeek(), (u: ShuYoUntimedCourse, idx: number) => {
                  Column({ space: 3 }) {
                    Text(`${u.courseName} (${u.credit}学分)`)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.store.colors.textPrimary)
                    Text(u.summary.length > 0 ? u.summary : `${u.teacherName} · ${u.weekText}`)
                      .fontSize(11)
                      .fontColor(this.store.colors.textTertiary)
                  }
                  .width('100%')
                  .padding(10)
                  .borderRadius(10)
                  .backgroundColor(this.store.colors.surface)
                  .border({ width: 1, color: this.store.colors.border })
                  .alignItems(HorizontalAlign.Start)
                }, (u: ShuYoUntimedCourse, idx: number): string => `${u.id}-${idx}`)
              }
              .width('100%')
              .padding({ left: 14, right: 14, bottom: 20 })
              .alignItems(HorizontalAlign.Start)
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.store.colors.background)
    .bindSheet($$this.showDetailSheet, this.courseDetailSheetBuilder(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: true
    })
  }
}
