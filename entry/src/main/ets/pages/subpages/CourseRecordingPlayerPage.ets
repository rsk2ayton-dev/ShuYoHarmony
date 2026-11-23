import { ShuYoConstants } from '../../core/ShuYoConstants';
import {
  ShuYoVodLesson,
  ShuYoVodPlayback,
  ShuYoVodPlayerParam,
  ShuYoVodPptSlide,
  ShuYoVodView
} from '../../models/ShuYoModels';
import { CourseRecordingService } from '../../services/CourseRecordingService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function CourseRecordingPlayerPageBuilder(): void {
  CourseRecordingPlayerPage()
}

@ComponentV2
export struct CourseRecordingPlayerPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local teachingClassId: number = 0;
  @Local termId: number = 0;
  @Local courseName: string = '课程录播';
  @Local courseCode: string = '';
  @Local teacherLabel: string = '';
  @Local fromSearch: boolean = false;

  @Local lessons: ShuYoVodLesson[] = [];
  @Local activeLessonId: number = 0;
  @Local activeIsLive: boolean = false;
  @Local sortAscending: boolean = true;

  @Local playback: ShuYoVodPlayback | undefined = undefined;
  @Local primaryViewIdx: number = 0;
  @Local secondaryViewIdx: number = 1;
  @Local dualViewEnabled: boolean = false;

  @Local isPlaying: boolean = false;
  @Local currentSec: number = 0;
  @Local durationSec: number = 2700;
  @Local playbackSpeed: number = 1.0;

  @Local activeTab: string = 'episodes'; // 'episodes' | 'notes' | 'overview'
  @Local pptSlides: ShuYoVodPptSlide[] = [];
  @Local isLoadingLessons: boolean = false;
  @Local isLoadingPlayback: boolean = false;
  @Local isLoadingPpt: boolean = false;
  @Local playbackError: string = '';
  @Local pptError: string = '';

  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private primaryController: VideoController = new VideoController();
  private secondaryController: VideoController = new VideoController();
  private readonly speedOptions: number[] = [0.75, 1.0, 1.25, 1.5, 2.0];

  private initFromParam(param: ShuYoVodPlayerParam | undefined): void {
    if (param !== undefined) {
      this.teachingClassId = param.teachingClassId;
      this.termId = param.termId;
      this.courseName = param.courseName.length > 0 ? param.courseName : '课程录播';
      this.courseCode = param.courseCode;
      this.teacherLabel = param.teacherLabel;
      this.activeLessonId = param.initialLessonId;
      this.activeIsLive = param.isLive;
      this.fromSearch = param.fromSearch;
    }
    this.loadCourseAndInitialPlayback();
  }

  private getViews(): ShuYoVodView[] {
    if (this.playback === undefined) {
      return [];
    }
    return this.playback.views;
  }

  private getPrimaryView(): ShuYoVodView | undefined {
    const list = this.getViews();
    if (list.length === 0) {
      return undefined;
    }
    const idx = Math.max(0, Math.min(list.length - 1, this.primaryViewIdx));
    return list[idx];
  }

  private getSecondaryView(): ShuYoVodView | undefined {
    const list = this.getViews();
    if (list.length <= 1) {
      return undefined;
    }
    const idx = Math.max(0, Math.min(list.length - 1, this.secondaryViewIdx));
    return list[idx];
  }

  private getPrimaryVideoUrl(): string {
    const v = this.getPrimaryView();
    return v !== undefined ? v.url : '';
  }

  private getSecondaryVideoUrl(): string {
    const v = this.getSecondaryView();
    return v !== undefined ? v.url : '';
  }

  private getPrimaryViewLabel(): string {
    const v = this.getPrimaryView();
    return v !== undefined ? v.label : '主画面';
  }

  private getSecondaryViewLabel(): string {
    const v = this.getSecondaryView();
    return v !== undefined ? v.label : '副画面';
  }

  private getActiveLesson(): ShuYoVodLesson | undefined {
    for (let i = 0; i < this.lessons.length; i++) {
      if (this.lessons[i].id === this.activeLessonId) {
        return this.lessons[i];
      }
    }
    return this.lessons.length > 0 ? this.lessons[0] : undefined;
  }

  private getSortedLessons(): ShuYoVodLesson[] {
    const copy: ShuYoVodLesson[] = [];
    for (let i = 0; i < this.lessons.length; i++) {
      copy.push(this.lessons[i]);
    }
    if (!this.sortAscending) {
      copy.reverse();
    }
    return copy;
  }

  private getTimeProgressText(): string {
    const cur = CourseRecordingService.formatDurationLabel(this.currentSec);
    const tot = CourseRecordingService.formatDurationLabel(this.durationSec);
    return `${cur} / ${tot}`;
  }

  private getMaxDuration(): number {
    return this.durationSec > 10 ? this.durationSec : 2700;
  }

  private getViewChipBg(idx: number): string {
    return this.primaryViewIdx === idx ? this.store.colors.accent : this.store.colors.chipFill;
  }

  private getViewChipText(idx: number): string {
    return this.primaryViewIdx === idx ? this.store.colors.onAccent : this.store.colors.textSecondary;
  }

  private getSpeedChipBg(spd: number): string {
    return Math.abs(this.playbackSpeed - spd) < 0.01 ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getSpeedChipText(spd: number): string {
    return Math.abs(this.playbackSpeed - spd) < 0.01 ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private getTabBg(tab: string): string {
    return this.activeTab === tab ? this.store.colors.selectedFill : this.store.colors.surfaceAlt;
  }

  private getTabText(tab: string): string {
    return this.activeTab === tab ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private getWeekdayText(weekday: number): string {
    const idx = Math.max(0, Math.min(6, weekday - 1));
    return ShuYoConstants.weekdayLabels[idx];
  }

  private async loadCourseAndInitialPlayback(): Promise<void> {
    this.isLoadingLessons = true;
    try {
      if (this.store.isDemoMode) {
        this.lessons = CourseRecordingService.loadDemoLessons(
          this.teachingClassId > 0 ? this.teachingClassId : 9001,
          this.courseName,
          this.courseCode,
          this.teacherLabel
        );
      } else {
        this.lessons = await CourseRecordingService.fetchLiveCourseLessons(
          this.store.studentId,
          this.teachingClassId,
          this.courseName,
          this.courseCode,
          this.teacherLabel,
          this.fromSearch,
          this.store.useWebVpn
        );
      }
      if (this.activeLessonId <= 0 && this.lessons.length > 0) {
        let chosen = this.lessons[this.lessons.length - 1];
        for (let i = this.lessons.length - 1; i >= 0; i--) {
          if (this.lessons[i].isLiveAvailable || this.lessons[i].isPlayable) {
            chosen = this.lessons[i];
            break;
          }
        }
        this.activeLessonId = chosen.id;
        this.activeIsLive = chosen.isLiveAvailable;
      }
    } catch (err) {
      const e = err as Error;
      this.playbackError = CourseRecordingService.stripErrorPrefix(e.message);
    } finally {
      this.isLoadingLessons = false;
    }

    if (this.activeLessonId > 0) {
      await this.loadLessonPlaybackAndNotes(this.activeLessonId, this.activeIsLive);
    }
  }

  private async loadLessonPlaybackAndNotes(lessonId: number, isLive: boolean): Promise<void> {
    this.activeLessonId = lessonId;
    this.activeIsLive = isLive;
    this.isLoadingPlayback = true;
    this.playbackError = '';
    this.primaryViewIdx = 0;
    this.secondaryViewIdx = 1;

    const activeLesson = this.getActiveLesson();
    const title = activeLesson !== undefined ? activeLesson.name : this.courseName;

    try {
      if (this.store.isDemoMode) {
        this.playback = CourseRecordingService.loadDemoPlayback(
          this.teachingClassId > 0 ? this.teachingClassId : 9001,
          lessonId,
          title,
          isLive
        );
        this.currentSec = this.playback.lastPositionSec;
      } else {
        const pb = await CourseRecordingService.fetchLivePlayback(
          this.store.studentId,
          this.teachingClassId,
          lessonId,
          title,
          isLive,
          this.store.useWebVpn
        );
        this.playback = pb;
        this.currentSec = pb.lastPositionSec;
      }
    } catch (err) {
      const e = err as Error;
      this.playbackError = CourseRecordingService.stripErrorPrefix(e.message);
    } finally {
      this.isLoadingPlayback = false;
    }

    this.loadPptNotesForLesson(lessonId);
  }

  private async loadPptNotesForLesson(lessonId: number): Promise<void> {
    this.isLoadingPpt = true;
    this.pptError = '';
    try {
      if (this.store.isDemoMode) {
        this.pptSlides = CourseRecordingService.loadDemoPptSlides(lessonId);
      } else {
        this.pptSlides = await CourseRecordingService.fetchLivePptSlides(
          this.store.studentId,
          lessonId,
          this.store.useWebVpn
        );
      }
    } catch (err) {
      const e = err as Error;
      this.pptError = CourseRecordingService.stripErrorPrefix(e.message);
    } finally {
      this.isLoadingPpt = false;
    }
  }

  private seekToSeconds(targetSec: number): void {
    const clamped = Math.max(0, Math.min(this.getMaxDuration(), Math.floor(targetSec)));
    this.currentSec = clamped;
    this.primaryController.setCurrentTime(clamped, SeekMode.Accurate);
    if (this.dualViewEnabled) {
      this.secondaryController.setCurrentTime(clamped, SeekMode.Accurate);
    }
  }

  private togglePlayPause(): void {
    if (this.isPlaying) {
      this.primaryController.pause();
      if (this.dualViewEnabled) {
        this.secondaryController.pause();
      }
      this.isPlaying = false;
    } else {
      this.primaryController.start();
      if (this.dualViewEnabled) {
        this.secondaryController.start();
      }
      this.isPlaying = true;
    }
  }

  private cycleSecondaryView(): void {
    const views = this.getViews();
    if (views.length <= 1) {
      return;
    }
    let next = (this.secondaryViewIdx + 1) % views.length;
    if (next === this.primaryViewIdx) {
      next = (next + 1) % views.length;
    }
    this.secondaryViewIdx = next;
  }

  build() {
    NavDestination() {
      Column({ space: 0 }) {
        ShuYoTopBar({
          headerTitle: this.courseName,
          subtitleText: `${this.courseCode} · ${this.teacherLabel}`,
          showBack: true,
          rightLabel: this.activeIsLive ? '直播' : '刷新',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            if (this.activeLessonId > 0) {
              this.loadLessonPlaybackAndNotes(this.activeLessonId, this.activeIsLive);
            }
          }
        })

        // Video Player Surface (Primary + Optional Dual-View Secondary)
        Column({ space: 4 }) {
          Stack({ alignContent: Alignment.BottomStart }) {
            if (this.getPrimaryVideoUrl().length > 0 && !this.store.isDemoMode) {
              Video({
                src: this.getPrimaryVideoUrl(),
                currentProgressRate: this.playbackSpeed,
                controller: this.primaryController
              })
                .width('100%')
                .height(this.dualViewEnabled ? 160 : 216)
                .autoPlay(true)
                .controls(false)
                .objectFit(ImageFit.Contain)
                .backgroundColor('#000000')
                .onPrepared((event: PreparedInfo) => {
                  if (event.duration > 0) {
                    this.durationSec = event.duration;
                  }
                  if (this.currentSec > 0 && !this.activeIsLive) {
                    this.primaryController.setCurrentTime(this.currentSec, SeekMode.Accurate);
                  }
                })
                .onUpdate((event: PlaybackInfo) => {
                  this.currentSec = event.time;
                })
                .onStart(() => {
                  this.isPlaying = true;
                })
                .onPause(() => {
                  this.isPlaying = false;
                })
            } else {
              // Demo Mode or fallback preview surface
              Column({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.play_circle'))
                  .fontSize(42)
                  .fontColor(['#FFFFFF'])
                Text(this.playback !== undefined ? this.playback.title : this.courseName)
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.store.isDemoMode
                  ? `当前机位：${this.getPrimaryViewLabel()} · ${this.getTimeProgressText()}`
                  : (this.isLoadingPlayback ? '正在获取加密视频流地址...' : (this.playbackError.length > 0 ? this.playbackError : '准备播放')))
                  .fontSize(12)
                  .fontColor('#CCFFFFFF')
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .height(this.dualViewEnabled ? 150 : 210)
              .padding(16)
              .backgroundColor('#121824')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }

            Row({ space: 6 }) {
              Text(this.getPrimaryViewLabel())
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .backgroundColor('#99000000')
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(6)
              if (this.activeIsLive) {
                Text('LIVE 实时流')
                  .fontSize(10)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
                  .backgroundColor(this.store.colors.danger)
                  .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                  .borderRadius(6)
              }
            }
            .padding(8)
          }
          .width('100%')

          // Optional Secondary Video (Dual-View Split Mode)
          if (this.dualViewEnabled && this.getViews().length > 1) {
            Stack({ alignContent: Alignment.BottomStart }) {
              if (this.getSecondaryVideoUrl().length > 0 && !this.store.isDemoMode) {
                Video({
                  src: this.getSecondaryVideoUrl(),
                  currentProgressRate: this.playbackSpeed,
                  controller: this.secondaryController
                })
                  .width('100%')
                  .height(145)
                  .autoPlay(true)
                  .controls(false)
                  .objectFit(ImageFit.Contain)
                  .muted(true)
                  .backgroundColor('#000000')
              } else {
                Column({ space: 4 }) {
                  Text(`同屏副画面：${this.getSecondaryViewLabel()}`)
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF')
                  Text('已静音同步跟随主画面进度，点击右下角可切换副画面机位')
                    .fontSize(11)
                    .fontColor('#B3FFFFFF')
                }
                .width('100%')
                .height(125)
                .backgroundColor('#1C2536')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              }

              Row({ space: 8 }) {
                Text(`副画面：${this.getSecondaryViewLabel()}`)
                  .fontSize(11)
                  .fontColor('#FFFFFF')
                  .backgroundColor('#99000000')
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(6)
                Button('切换副机位')
                  .height(22)
                  .fontSize(10)
                  .fontColor('#FFFFFF')
                  .backgroundColor(this.store.colors.accent)
                  .borderRadius(11)
                  .padding({ left: 8, right: 8 })
                  .onClick(() => {
                    this.cycleSecondaryView();
                  })
              }
              .padding(8)
            }
            .width('100%')
          }
        }
        .width('100%')
        .backgroundColor('#000000')

        // Transport & View Controls Card
        Column({ space: 8 }) {
          // Seek Slider + Time Row
          Row({ space: 8 }) {
            Button(this.isPlaying ? '暂停' : '播放')
              .height(28)
              .fontSize(12)
              .fontColor(this.store.colors.onAccent)
              .backgroundColor(this.store.colors.accent)
              .borderRadius(14)
              .padding({ left: 10, right: 10 })
              .onClick(() => {
                this.togglePlayPause();
              })

            Button('-15s')
              .height(26)
              .fontSize(11)
              .fontColor(this.store.colors.textSecondary)
              .backgroundColor(this.store.colors.surfaceAlt)
              .borderRadius(13)
              .padding({ left: 8, right: 8 })
              .onClick(() => {
                this.seekToSeconds(this.currentSec - 15);
              })

            Slider({
              value: this.currentSec,
              min: 0,
              max: this.getMaxDuration(),
              step: 1
            })
              .layoutWeight(1)
              .selectedColor(this.store.colors.accent)
              .onChange((val: number, mode: SliderChangeMode) => {
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  this.seekToSeconds(val);
                }
              })

            Button('+15s')
              .height(26)
              .fontSize(11)
              .fontColor(this.store.colors.textSecondary)
              .backgroundColor(this.store.colors.surfaceAlt)
              .borderRadius(13)
              .padding({ left: 8, right: 8 })
              .onClick(() => {
                this.seekToSeconds(this.currentSec + 15);
              })

            Text(this.getTimeProgressText())
              .fontSize(11)
              .fontColor(this.store.colors.textTertiary)
          }
          .width('100%')

          // Multi-View Camera Angle Strip + Dual-View & Fullscreen
          if (this.getViews().length > 0) {
            Scroll() {
              Row({ space: 6 }) {
                ForEach(this.getViews(), (v: ShuYoVodView, idx: number) => {
                  Button(v.label)
                    .height(28)
                    .fontSize(11)
                    .fontColor(this.getViewChipText(idx))
                    .backgroundColor(this.getViewChipBg(idx))
                    .borderRadius(14)
                    .padding({ left: 10, right: 10 })
                    .onClick(() => {
                      this.primaryViewIdx = idx;
                      if (this.secondaryViewIdx === idx && this.getViews().length > 1) {
                        this.secondaryViewIdx = (idx + 1) % this.getViews().length;
                      }
                    })
                }, (v: ShuYoVodView, idx: number): string => `view-${v.viewNumber}-${idx}`)

                if (this.getViews().length > 1) {
                  Button(this.dualViewEnabled ? '关闭双画面' : '双画面同屏')
                    .height(28)
                    .fontSize(11)
                    .fontColor(this.dualViewEnabled ? this.store.colors.onSelectedFill : this.store.colors.accent)
                    .backgroundColor(this.dualViewEnabled ? this.store.colors.selectedFill : this.store.colors.accentSoft)
                    .borderRadius(14)
                    .padding({ left: 10, right: 10 })
                    .onClick(() => {
                      this.dualViewEnabled = !this.dualViewEnabled;
                    })
                }

                Button('全屏')
                  .height(28)
                  .fontSize(11)
                  .fontColor(this.store.colors.textPrimary)
                  .backgroundColor(this.store.colors.surfaceAlt)
                  .borderRadius(14)
                  .padding({ left: 10, right: 10 })
                  .onClick(() => {
                    this.primaryController.requestFullscreen(true);
                  })
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
            .height(30)
          }

          // Playback Speed Row
          Row({ space: 6 }) {
            Text('倍速')
              .fontSize(11)
              .fontColor(this.store.colors.textTertiary)
            ForEach(this.speedOptions, (spd: number, idx: number) => {
              Button(`${spd}x`)
                .height(24)
                .fontSize(11)
                .fontColor(this.getSpeedChipText(spd))
                .backgroundColor(this.getSpeedChipBg(spd))
                .borderRadius(12)
                .padding({ left: 8, right: 8 })
                .onClick(() => {
                  this.playbackSpeed = spd;
                })
            }, (spd: number, idx: number): string => `spd-${spd}`)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .backgroundColor(this.store.colors.surface)
        .border({ width: { bottom: 1 }, color: this.store.colors.border })

        // Bottom Tabs Header ('选集' | 'AI 笔记 (PPT)' | '课程详情')
        Row({ space: 8 }) {
          Button(`选集 (${this.lessons.length})`)
            .layoutWeight(1)
            .height(34)
            .fontSize(13)
            .fontColor(this.getTabText('episodes'))
            .backgroundColor(this.getTabBg('episodes'))
            .borderRadius(10)
            .onClick(() => {
              this.activeTab = 'episodes';
            })
          Button(`AI 笔记 (${this.pptSlides.length})`)
            .layoutWeight(1)
            .height(34)
            .fontSize(13)
            .fontColor(this.getTabText('notes'))
            .backgroundColor(this.getTabBg('notes'))
            .borderRadius(10)
            .onClick(() => {
              this.activeTab = 'notes';
            })
          Button('课程信息')
            .layoutWeight(1)
            .height(34)
            .fontSize(13)
            .fontColor(this.getTabText('overview'))
            .backgroundColor(this.getTabBg('overview'))
            .borderRadius(10)
            .onClick(() => {
              this.activeTab = 'overview';
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 8, bottom: 6 })

        // Bottom Tab Content
        if (this.activeTab === 'episodes') {
          Column({ space: 8 }) {
            Row() {
              Text('课次列表')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.store.colors.textSecondary)
              Blank()
              Button(this.sortAscending ? '按时间正序 ↑' : '按时间倒序 ↓')
                .height(26)
                .fontSize(11)
                .fontColor(this.store.colors.textSecondary)
                .backgroundColor(this.store.colors.surfaceAlt)
                .borderRadius(13)
                .padding({ left: 10, right: 10 })
                .onClick(() => {
                  this.sortAscending = !this.sortAscending;
                })
            }
            .width('100%')

            if (this.isLoadingLessons) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(this.store.colors.accent)
                Text('正在加载教学班课次...')
                  .fontSize(13)
                  .fontColor(this.store.colors.textSecondary)
              }
              .padding(16)
            } else if (this.getSortedLessons().length === 0) {
              Text('暂无可播放的录播课次')
                .fontSize(13)
                .fontColor(this.store.colors.textTertiary)
                .padding(20)
            } else {
              List({ space: 8 }) {
                ForEach(this.getSortedLessons(), (item: ShuYoVodLesson, idx: number) => {
                  ListItem() {
                    Row({ space: 10 }) {
                      Column({ space: 4 }) {
                        Text(item.name)
                          .fontSize(14)
                          .fontWeight(item.id === this.activeLessonId ? FontWeight.Bold : FontWeight.Medium)
                          .fontColor(item.id === this.activeLessonId ? this.store.colors.accent : this.store.colors.textPrimary)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(`第${item.weekNumber}周 ${this.getWeekdayText(item.weekday)} ${item.sectionLabel} · ${item.dateLabel} ${item.timeRangeLabel} · ${item.classroom}`)
                          .fontSize(11)
                          .fontColor(this.store.colors.textTertiary)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Text(item.id === this.activeLessonId ? '当前播放' : item.statusLabel)
                        .fontSize(11)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(item.id === this.activeLessonId ? this.store.colors.onAccent : this.store.colors.accent)
                        .backgroundColor(item.id === this.activeLessonId ? this.store.colors.accent : this.store.colors.accentSoft)
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .borderRadius(8)
                    }
                    .width('100%')
                    .padding(12)
                    .borderRadius(12)
                    .backgroundColor(this.store.colors.surface)
                    .border({
                      width: 1,
                      color: item.id === this.activeLessonId ? this.store.colors.accent : this.store.colors.border
                    })
                    .onClick(() => {
                      if (item.id !== this.activeLessonId) {
                        this.loadLessonPlaybackAndNotes(item.id, item.isLiveAvailable);
                      }
                    })
                  }
                }, (item: ShuYoVodLesson, idx: number): string => `ep-${item.id}-${idx}`)
              }
              .width('100%')
              .layoutWeight(1)
            }
          }
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 16 })
          .layoutWeight(1)
        } else if (this.activeTab === 'notes') {
          // AI PPT OCR Notes Panel
          Column({ space: 8 }) {
            if (this.isLoadingPpt) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(this.store.colors.accent)
                Text('正在加载本节课 AI PPT 识别笔记...')
                  .fontSize(13)
                  .fontColor(this.store.colors.textSecondary)
              }
              .padding(16)
            } else if (this.pptError.length > 0) {
              Column({ space: 8 }) {
                Text(this.pptError)
                  .fontSize(13)
                  .fontColor(this.store.colors.danger)
                Button('重试加载笔记')
                  .height(32)
                  .fontSize(12)
                  .fontColor(this.store.colors.onAccent)
                  .backgroundColor(this.store.colors.accent)
                  .borderRadius(16)
                  .onClick(() => {
                    this.loadPptNotesForLesson(this.activeLessonId);
                  })
              }
              .width('100%')
              .padding(20)
              .alignItems(HorizontalAlign.Center)
            } else if (this.pptSlides.length === 0) {
              Column({ space: 6 }) {
                Text('本节课暂未生成 AI PPT 课堂笔记')
                  .fontSize(14)
                  .fontColor(this.store.colors.textTertiary)
                Text('当课堂包含 PPT 投屏并通过校方 OCR 提取后将在此展示，点击时间点可直接跳转视频')
                  .fontSize(12)
                  .fontColor(this.store.colors.textMuted)
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .padding(24)
              .borderRadius(14)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
              .alignItems(HorizontalAlign.Center)
            } else {
              List({ space: 10 }) {
                ForEach(this.pptSlides, (slide: ShuYoVodPptSlide, idx: number) => {
                  ListItem() {
                    Column({ space: 8 }) {
                      Row() {
                        Text(`PPT 节点 #${idx + 1}`)
                          .fontSize(12)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(this.store.colors.textSecondary)
                        Blank()
                        Button(`跳转 ${slide.timeLabel}`)
                          .height(24)
                          .fontSize(11)
                          .fontColor(this.store.colors.accent)
                          .backgroundColor(this.store.colors.accentSoft)
                          .borderRadius(12)
                          .padding({ left: 10, right: 10 })
                          .onClick(() => {
                            this.seekToSeconds(slide.positionSec);
                          })
                      }
                      .width('100%')

                      if (slide.imageUrl.length > 0) {
                        Image(slide.imageUrl)
                          .width('100%')
                          .height(140)
                          .objectFit(ImageFit.Contain)
                          .borderRadius(8)
                          .backgroundColor(this.store.colors.surfaceAlt)
                      }

                      Text(slide.text)
                        .fontSize(13)
                        .fontColor(this.store.colors.textPrimary)
                        .lineHeight(20)
                    }
                    .width('100%')
                    .padding(12)
                    .borderRadius(12)
                    .backgroundColor(this.store.colors.surface)
                    .border({ width: 1, color: this.store.colors.border })
                    .alignItems(HorizontalAlign.Start)
                    .onClick(() => {
                      this.seekToSeconds(slide.positionSec);
                    })
                  }
                }, (slide: ShuYoVodPptSlide, idx: number): string => `${slide.id}-${idx}`)
              }
              .width('100%')
              .layoutWeight(1)
            }
          }
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 16 })
          .layoutWeight(1)
        } else {
          // Course Overview Tab
          Scroll() {
            Column({ space: 10 }) {
              Column({ space: 8 }) {
                Text(this.courseName)
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.store.colors.textPrimary)
                Text(`课程代码：${this.courseCode.length > 0 ? this.courseCode : '未标注'}`)
                  .fontSize(13)
                  .fontColor(this.store.colors.textSecondary)
                Text(`授课教师：${this.teacherLabel.length > 0 ? this.teacherLabel : '未标注'}`)
                  .fontSize(13)
                  .fontColor(this.store.colors.textSecondary)
                Text(`可用机位：${this.getViews().length} 路视角（支持双画面同屏与 0.75x-2.0x 变速）`)
                  .fontSize(13)
                  .fontColor(this.store.colors.textSecondary)
                if (this.playback !== undefined && this.playback.description.length > 0) {
                  Text(this.playback.description)
                    .fontSize(12)
                    .fontColor(this.store.colors.textTertiary)
                    .margin({ top: 4 })
                }
              }
              .width('100%')
              .padding(16)
              .borderRadius(14)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ left: 14, right: 14, bottom: 16 })
          }
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.store.colors.background)
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.navStack = ctx.pathStack;
      const param = ctx.pathInfo.param as ShuYoVodPlayerParam | undefined;
      this.initFromParam(param);
    })
  }
}
