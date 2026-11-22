import { ShuYoConstants } from '../../core/ShuYoConstants';
import {
  ShuYoCourseSession,
  ShuYoScheduleEditorParam
} from '../../models/ShuYoModels';
import { ScheduleService } from '../../services/ScheduleService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function ScheduleEditorPageBuilder(): void {
  ScheduleEditorPage()
}

@ComponentV2
export struct ScheduleEditorPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local editingId: string = '';
  @Local courseNameInput: string = '';
  @Local teacherInput: string = '';
  @Local locationInput: string = '';
  @Local campusInput: string = '宝山主区';
  @Local weekdayValue: number = 1;
  @Local startSecValue: number = 1;
  @Local endSecValue: number = 2;
  @Local weekTextInput: string = '1-16周';
  @Local creditInput: string = '2.0';
  @Local noteInput: string = '';
  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private readonly weekdayChoices: number[] = [1, 2, 3, 4, 5, 6, 7];

  private loadExisting(sessionId: string, defaultWeekday: number): void {
    this.editingId = sessionId;
    if (sessionId.length === 0) {
      this.weekdayValue = defaultWeekday >= 1 && defaultWeekday <= 7 ? defaultWeekday : 1;
      return;
    }
    for (let i = 0; i < this.store.scheduleData.sessions.length; i++) {
      const s = this.store.scheduleData.sessions[i];
      if (s.id === sessionId) {
        this.courseNameInput = s.courseName;
        this.teacherInput = s.teacherName;
        this.locationInput = s.location;
        this.campusInput = s.campus.length > 0 ? s.campus : '宝山主区';
        this.weekdayValue = s.weekday;
        this.startSecValue = s.startSection;
        this.endSecValue = s.endSection;
        this.weekTextInput = s.weekText.length > 0 ? s.weekText : '1-16周';
        this.creditInput = s.credit;
        this.noteInput = s.note;
        return;
      }
    }
  }

  private saveCourse(): void {
    const trimmedName = this.courseNameInput.trim();
    if (trimmedName.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请填写课程名称' });
      return;
    }
    const startSec = Math.max(1, Math.min(12, this.startSecValue));
    const endSec = Math.max(startSec, Math.min(12, this.endSecValue));
    const secs: number[] = [];
    for (let i = startSec; i <= endSec; i++) {
      secs.push(i);
    }
    const weeks = ScheduleService.parseWeeksText(this.weekTextInput);
    const id = this.editingId.length > 0 ? this.editingId : `manual:${Date.now()}`;
    const session: ShuYoCourseSession = {
      id: id,
      courseName: trimmedName,
      courseCode: '_manual',
      teachingClassId: '',
      teacherName: this.teacherInput.trim(),
      campus: this.campusInput.trim(),
      location: this.locationInput.trim(),
      weekday: this.weekdayValue,
      startSection: startSec,
      endSection: endSec,
      sections: secs,
      weeks: weeks,
      weekText: this.weekTextInput.trim(),
      credit: this.creditInput.trim(),
      note: this.noteInput.trim(),
      isManual: true
    };
    this.store.upsertCourseSession(session);
    this.getUIContext().getPromptAction().showToast({ message: '课程已保存' });
    this.navStack.pop();
  }

  private getDayBg(day: number): string {
    return this.weekdayValue === day ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getDayText(day: number): string {
    return this.weekdayValue === day ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  build() {
    NavDestination() {
      Column() {
        ShuYoTopBar({
          headerTitle: this.editingId.length > 0 ? '编辑课程' : '添加自定义课程',
          subtitleText: '支持周次、单双周与节次自定义',
          showBack: true,
          rightLabel: '保存',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            this.saveCourse();
          }
        })

        Scroll() {
          Column({ space: 14 }) {
            Column({ space: 10 }) {
              Text('课程名称 *')
                .fontSize(13)
                .fontColor(this.store.colors.textSecondary)
              TextInput({ placeholder: '例如：算法设计与分析', text: this.courseNameInput })
                .height(44)
                .backgroundColor(this.store.colors.surfaceAlt)
                .borderRadius(10)
                .onChange((val: string) => {
                  this.courseNameInput = val;
                })

              Text('授课教师')
                .fontSize(13)
                .fontColor(this.store.colors.textSecondary)
              TextInput({ placeholder: '可选', text: this.teacherInput })
                .height(44)
                .backgroundColor(this.store.colors.surfaceAlt)
                .borderRadius(10)
                .onChange((val: string) => {
                  this.teacherInput = val;
                })

              Text('上课教室 / 地点')
                .fontSize(13)
                .fontColor(this.store.colors.textSecondary)
              TextInput({ placeholder: '例如：AJ207', text: this.locationInput })
                .height(44)
                .backgroundColor(this.store.colors.surfaceAlt)
                .borderRadius(10)
                .onChange((val: string) => {
                  this.locationInput = val;
                })
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.border })
            .alignItems(HorizontalAlign.Start)

            // Time card
            Column({ space: 12 }) {
              Text('星期')
                .fontSize(13)
                .fontColor(this.store.colors.textSecondary)
              Row({ space: 6 }) {
                ForEach(this.weekdayChoices, (day: number, idx: number) => {
                  Button(ShuYoConstants.weekdayLabels[day - 1])
                    .layoutWeight(1)
                    .height(34)
                    .fontSize(12)
                    .fontColor(this.getDayText(day))
                    .backgroundColor(this.getDayBg(day))
                    .borderRadius(10)
                    .onClick(() => {
                      this.weekdayValue = day;
                    })
                }, (day: number, idx: number): string => `ed-day-${day}`)
              }
              .width('100%')

              Row({ space: 12 }) {
                Column({ space: 6 }) {
                  Text('起始节次 (1-12)')
                    .fontSize(12)
                    .fontColor(this.store.colors.textSecondary)
                  Row({ space: 8 }) {
                    Button('-')
                      .width(34)
                      .height(34)
                      .backgroundColor(this.store.colors.surfaceAlt)
                      .fontColor(this.store.colors.textPrimary)
                      .onClick(() => {
                        if (this.startSecValue > 1) {
                          this.startSecValue--;
                          if (this.endSecValue < this.startSecValue) {
                            this.endSecValue = this.startSecValue;
                          }
                        }
                      })
                    Text(`第 ${this.startSecValue} 节`)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.store.colors.textPrimary)
                    Button('+')
                      .width(34)
                      .height(34)
                      .backgroundColor(this.store.colors.surfaceAlt)
                      .fontColor(this.store.colors.textPrimary)
                      .onClick(() => {
                        if (this.startSecValue < 12) {
                          this.startSecValue++;
                          if (this.endSecValue < this.startSecValue) {
                            this.endSecValue = this.startSecValue;
                          }
                        }
                      })
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Column({ space: 6 }) {
                  Text('结束节次 (1-12)')
                    .fontSize(12)
                    .fontColor(this.store.colors.textSecondary)
                  Row({ space: 8 }) {
                    Button('-')
                      .width(34)
                      .height(34)
                      .backgroundColor(this.store.colors.surfaceAlt)
                      .fontColor(this.store.colors.textPrimary)
                      .onClick(() => {
                        if (this.endSecValue > this.startSecValue) {
                          this.endSecValue--;
                        }
                      })
                    Text(`第 ${this.endSecValue} 节`)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.store.colors.textPrimary)
                    Button('+')
                      .width(34)
                      .height(34)
                      .backgroundColor(this.store.colors.surfaceAlt)
                      .fontColor(this.store.colors.textPrimary)
                      .onClick(() => {
                        if (this.endSecValue < 12) {
                          this.endSecValue++;
                        }
                      })
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')

              Text('周次（支持 1-16周、1-15周(单)、2,4,6周）')
                .fontSize(13)
                .fontColor(this.store.colors.textSecondary)
              TextInput({ placeholder: '1-16周', text: this.weekTextInput })
                .height(44)
                .backgroundColor(this.store.colors.surfaceAlt)
                .borderRadius(10)
                .onChange((val: string) => {
                  this.weekTextInput = val;
                })

              Text('备注')
                .fontSize(13)
                .fontColor(this.store.colors.textSecondary)
              TextInput({ placeholder: '可选备注信息', text: this.noteInput })
                .height(44)
                .backgroundColor(this.store.colors.surfaceAlt)
                .borderRadius(10)
                .onChange((val: string) => {
                  this.noteInput = val;
                })
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(this.store.colors.surface)
            .border({ width: 1, color: this.store.colors.border })
            .alignItems(HorizontalAlign.Start)

            Button('保存课程安排')
              .width('100%')
              .height(46)
              .fontSize(15)
              .fontColor(this.store.colors.onAccent)
              .backgroundColor(this.store.colors.accent)
              .borderRadius(12)
              .onClick(() => {
                this.saveCourse();
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
      const param = ctx.pathInfo.param as ShuYoScheduleEditorParam | undefined;
      if (param !== undefined) {
        this.loadExisting(param.sessionId, param.defaultWeekday);
      }
    })
  }
}
