import { ShuYoConstants } from '../../core/ShuYoConstants';
import { ShuYoThemes } from '../../core/ShuYoTheme';
import {
  ShuYoVodCourse,
  ShuYoVodLesson,
  ShuYoVodPlayerParam,
  ShuYoVodTerm
} from '../../models/ShuYoModels';
import { CourseRecordingService } from '../../services/CourseRecordingService';
import { ShuYoAppStore } from '../../store/ShuYoAppStore';
import { ShuYoTopBar } from '../../components/ShuYoCommonViews';

@Builder
export function CourseRecordingsPageBuilder(): void {
  CourseRecordingsPage()
}

@ComponentV2
export struct CourseRecordingsPage {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local terms: ShuYoVodTerm[] = [];
  @Local selectedTermId: number = 0;
  @Local courses: ShuYoVodCourse[] = [];
  @Local liveLessons: ShuYoVodLesson[] = [];
  @Local timetableLessons: ShuYoVodLesson[] = [];
  @Local selectedWeek: number = 1;
  @Local activeMode: string = 'catalog'; // 'catalog' | 'timetable' | 'search'
  @Local catalogFilter: string = '';
  @Local searchKeyword: string = '';
  @Local searchResults: ShuYoVodLesson[] = [];
  @Local searchPlayableOnly: boolean = true;
  @Local isSearching: boolean = false;
  @Local hasSearched: boolean = false;
  @Local isLoading: boolean = false;
  @Local isLoadingTimetable: boolean = false;
  @Local errorMsg: string = '';
  @Local authRequired: boolean = false;

  @Local showEpisodeSheet: boolean = false;
  @Local sheetCourse: ShuYoVodCourse | undefined = undefined;
  @Local sheetLessons: ShuYoVodLesson[] = [];
  @Local isLoadingSheet: boolean = false;

  private store: ShuYoAppStore = ShuYoAppStore.instance();
  private pendingReauthRefresh: boolean = false;

  aboutToAppear(): void {
    this.selectedWeek = this.store.currentWeek > 0 ? this.store.currentWeek : 1;
    this.loadInitialData(false);
  }

  private getCurrentTerm(): ShuYoVodTerm | undefined {
    for (let i = 0; i < this.terms.length; i++) {
      if (this.terms[i].id === this.selectedTermId) {
        return this.terms[i];
      }
    }
    return this.terms.length > 0 ? this.terms[0] : undefined;
  }

  private getSubtitle(): string {
    const t = this.getCurrentTerm();
    if (t !== undefined) {
      return `${t.academicYearLabel} · ${t.seasonLabel}`;
    }
    return this.store.isDemoMode ? '演示模式 · 课堂回放与直播' : '上海大学录播平台 (vod.cc.shu.edu.cn)';
  }

  private getTermChipBg(id: number): string {
    return this.selectedTermId === id ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getTermChipText(id: number): string {
    return this.selectedTermId === id ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private getModeTabBg(mode: string): string {
    return this.activeMode === mode ? this.store.colors.accent : this.store.colors.surfaceAlt;
  }

  private getModeTabText(mode: string): string {
    return this.activeMode === mode ? this.store.colors.onAccent : this.store.colors.textSecondary;
  }

  private getWeekChipBg(w: number): string {
    return this.selectedWeek === w ? this.store.colors.selectedFill : this.store.colors.chipFill;
  }

  private getWeekChipText(w: number): string {
    return this.selectedWeek === w ? this.store.colors.onSelectedFill : this.store.colors.textSecondary;
  }

  private getWeekNumbers(): number[] {
    const t = this.getCurrentTerm();
    const maxW = t !== undefined && t.teachingWeekCount > 0 ? t.teachingWeekCount : 16;
    const out: number[] = [];
    for (let w = 1; w <= maxW; w++) {
      out.push(w);
    }
    return out;
  }

  private getFilteredCourses(): ShuYoVodCourse[] {
    const q = this.catalogFilter.trim().toLowerCase();
    if (q.length === 0) {
      return this.courses;
    }
    const out: ShuYoVodCourse[] = [];
    for (let i = 0; i < this.courses.length; i++) {
      const c = this.courses[i];
      if (c.name.toLowerCase().includes(q) ||
        c.code.toLowerCase().includes(q) ||
        c.teacherLabel.toLowerCase().includes(q) ||
        c.teachingClassName.toLowerCase().includes(q)) {
        out.push(c);
      }
    }
    return out;
  }

  private getLessonsForSelectedWeek(): ShuYoVodLesson[] {
    const out: ShuYoVodLesson[] = [];
    for (let i = 0; i < this.timetableLessons.length; i++) {
      const item = this.timetableLessons[i];
      if (item.weekNumber === this.selectedWeek || item.weekNumber === 0) {
        out.push(item);
      }
    }
    out.sort((a: ShuYoVodLesson, b: ShuYoVodLesson): number => {
      if (a.weekday !== b.weekday) {
        return a.weekday - b.weekday;
      }
      return a.sectionNumber - b.sectionNumber;
    });
    return out;
  }

  private getFilteredSearchResults(): ShuYoVodLesson[] {
    if (!this.searchPlayableOnly) {
      return this.searchResults;
    }
    const out: ShuYoVodLesson[] = [];
    for (let i = 0; i < this.searchResults.length; i++) {
      const item = this.searchResults[i];
      if (item.isPlayable || item.isLiveAvailable || item.id > 0) {
        out.push(item);
      }
    }
    return out;
  }

  private getWeekdayText(weekday: number): string {
    const idx = Math.max(0, Math.min(6, weekday - 1));
    return ShuYoConstants.weekdayLabels[idx];
  }

  private getStatusBadgeBg(lesson: ShuYoVodLesson): string {
    if (lesson.isLiveAvailable) {
      return this.store.colors.danger;
    }
    if (lesson.isPlayable) {
      return this.store.colors.accentSoft;
    }
    return this.store.colors.surfaceAlt;
  }

  private getStatusBadgeText(lesson: ShuYoVodLesson): string {
    if (lesson.isLiveAvailable) {
      return this.store.colors.onDanger;
    }
    if (lesson.isPlayable) {
      return this.store.colors.accent;
    }
    return this.store.colors.textTertiary;
  }

  private async loadInitialData(showToast: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    this.errorMsg = '';
    this.authRequired = false;

    try {
      if (this.store.isDemoMode) {
        const demoTerms = CourseRecordingService.loadDemoTerms();
        this.terms = demoTerms;
        if (this.selectedTermId <= 0 && demoTerms.length > 0) {
          this.selectedTermId = demoTerms[0].id;
        }
        const cat = CourseRecordingService.loadDemoCatalog(this.selectedTermId);
        this.courses = cat.courses;
        this.liveLessons = cat.liveLessons;
        this.buildDemoTimetable();
        this.isLoading = false;
        if (showToast) {
          this.showToastSafe('演示录播目录已刷新');
        }
        return;
      }

      if (!this.store.isLoggedIn || this.store.studentId.length === 0) {
        this.isLoading = false;
        this.authRequired = true;
        this.errorMsg = '请先登录上海大学统一身份认证账号以查看课程录播';
        return;
      }

      const fetchedTerms = await CourseRecordingService.fetchLiveTerms(
        this.store.studentId,
        this.store.useWebVpn
      );
      this.terms = fetchedTerms;
      if (fetchedTerms.length === 0) {
        throw new Error('录播平台暂未返回可查询的学期');
      }
      let targetTermId = this.selectedTermId;
      let termExists = false;
      for (let i = 0; i < fetchedTerms.length; i++) {
        if (fetchedTerms[i].id === targetTermId) {
          termExists = true;
          break;
        }
      }
      if (!termExists) {
        targetTermId = fetchedTerms[0].id;
        this.selectedTermId = targetTermId;
      }

      await this.loadCatalogForTerm(targetTermId);
      this.isLoading = false;
      if (showToast) {
        this.showToastSafe(`已同步 ${this.courses.length} 门录播课程`);
      }
    } catch (err) {
      this.isLoading = false;
      const e = err as Error;
      const raw = e.message.length > 0 ? e.message : '加载课程录播失败，请稍后重试';
      this.authRequired = CourseRecordingService.isAuthRequiredError(raw);
      this.errorMsg = CourseRecordingService.stripErrorPrefix(raw);
      if (showToast) {
        this.showToastSafe(this.errorMsg);
      }
    }
  }

  private async loadCatalogForTerm(termId: number): Promise<void> {
    if (this.store.isDemoMode) {
      const cat = CourseRecordingService.loadDemoCatalog(termId);
      this.courses = cat.courses;
      this.liveLessons = cat.liveLessons;
      this.buildDemoTimetable();
      return;
    }
    const cat = await CourseRecordingService.fetchLiveCatalog(
      this.store.studentId,
      termId,
      this.store.useWebVpn
    );
    this.courses = cat.courses;
    this.liveLessons = cat.liveLessons;
    this.timetableLessons = [];
    if (this.activeMode === 'timetable') {
      await this.loadTimetableLessons();
    }
  }

  private buildDemoTimetable(): void {
    const all: ShuYoVodLesson[] = [];
    for (let i = 0; i < this.courses.length; i++) {
      const c = this.courses[i];
      const list = CourseRecordingService.loadDemoLessons(
        c.teachingClassId,
        c.name,
        c.code,
        c.teacherLabel
      );
      for (let j = 0; j < list.length; j++) {
        all.push(list[j]);
      }
    }
    this.timetableLessons = all;
  }

  private async loadTimetableLessons(): Promise<void> {
    if (this.store.isDemoMode) {
      this.buildDemoTimetable();
      return;
    }
    if (this.isLoadingTimetable || this.courses.length === 0) {
      return;
    }
    this.isLoadingTimetable = true;
    try {
      const aggregated: ShuYoVodLesson[] = [];
      const limit = Math.min(this.courses.length, 12);
      for (let i = 0; i < limit; i++) {
        const c = this.courses[i];
        try {
          const list = await CourseRecordingService.fetchLiveCourseLessons(
            this.store.studentId,
            c.teachingClassId,
            c.name,
            c.code,
            c.teacherLabel,
            false,
            this.store.useWebVpn
          );
          for (let j = 0; j < list.length; j++) {
            aggregated.push(list[j]);
          }
        } catch (_courseErr) {
          // Continue loading remaining courses
        }
      }
      this.timetableLessons = aggregated;
    } finally {
      this.isLoadingTimetable = false;
    }
  }

  private async selectTerm(termId: number): Promise<void> {
    if (this.selectedTermId === termId || this.isLoading) {
      return;
    }
    this.selectedTermId = termId;
    this.isLoading = true;
    this.errorMsg = '';
    try {
      await this.loadCatalogForTerm(termId);
    } catch (err) {
      const e = err as Error;
      this.authRequired = CourseRecordingService.isAuthRequiredError(e.message);
      this.errorMsg = CourseRecordingService.stripErrorPrefix(e.message);
    } finally {
      this.isLoading = false;
    }
  }

  private async switchMode(mode: string): Promise<void> {
    this.activeMode = mode;
    if (mode === 'timetable' && this.timetableLessons.length === 0 && this.courses.length > 0) {
      await this.loadTimetableLessons();
    }
  }

  private async handleSearch(): Promise<void> {
    const kw = this.searchKeyword.trim();
    if (kw.length < 2) {
      this.showToastSafe('请输入至少 2 个字符的课程名、教师或课程代码');
      return;
    }
    if (this.isSearching) {
      return;
    }
    this.isSearching = true;
    this.hasSearched = true;
    this.errorMsg = '';
    try {
      if (this.store.isDemoMode) {
        const all: ShuYoVodLesson[] = [];
        for (let i = 0; i < this.courses.length; i++) {
          const c = this.courses[i];
          const list = CourseRecordingService.loadDemoLessons(
            c.teachingClassId,
            c.name,
            c.code,
            c.teacherLabel
          );
          for (let j = 0; j < list.length; j++) {
            const item = list[j];
            const lower = kw.toLowerCase();
            if (item.courseName.toLowerCase().includes(lower) ||
              item.name.toLowerCase().includes(lower) ||
              item.courseCode.toLowerCase().includes(lower) ||
              item.teacherLabel.toLowerCase().includes(lower)) {
              all.push(item);
            }
          }
        }
        this.searchResults = all;
        this.isSearching = false;
        return;
      }

      const results = await CourseRecordingService.searchLiveLessons(
        this.store.studentId,
        this.selectedTermId,
        kw,
        this.store.useWebVpn
      );
      this.searchResults = results;
    } catch (err) {
      const e = err as Error;
      this.authRequired = CourseRecordingService.isAuthRequiredError(e.message);
      this.errorMsg = CourseRecordingService.stripErrorPrefix(e.message);
    } finally {
      this.isSearching = false;
    }
  }

  private async openEpisodeSelector(course: ShuYoVodCourse): Promise<void> {
    this.sheetCourse = course;
    this.sheetLessons = [];
    this.showEpisodeSheet = true;
    this.isLoadingSheet = true;
    try {
      if (this.store.isDemoMode) {
        this.sheetLessons = CourseRecordingService.loadDemoLessons(
          course.teachingClassId,
          course.name,
          course.code,
          course.teacherLabel
        );
        this.isLoadingSheet = false;
        return;
      }
      this.sheetLessons = await CourseRecordingService.fetchLiveCourseLessons(
        this.store.studentId,
        course.teachingClassId,
        course.name,
        course.code,
        course.teacherLabel,
        false,
        this.store.useWebVpn
      );
    } catch (err) {
      const e = err as Error;
      this.showToastSafe(CourseRecordingService.stripErrorPrefix(e.message));
    } finally {
      this.isLoadingSheet = false;
    }
  }

  private openCoursePlayer(
    course: ShuYoVodCourse,
    initialLessonId: number,
    isLive: boolean,
    fromSearch: boolean
  ): void {
    this.showEpisodeSheet = false;
    const param: ShuYoVodPlayerParam = {
      teachingClassId: course.teachingClassId,
      termId: course.termId > 0 ? course.termId : this.selectedTermId,
      courseName: course.name,
      courseCode: course.code,
      teacherLabel: course.teacherLabel,
      initialLessonId: initialLessonId,
      isLive: isLive,
      fromSearch: fromSearch
    };
    this.navStack.pushDestination({ name: 'CourseRecordingPlayerPage', param: param });
  }

  private openLessonPlayer(lesson: ShuYoVodLesson, fromSearch: boolean): void {
    this.showEpisodeSheet = false;
    const param: ShuYoVodPlayerParam = {
      teachingClassId: lesson.teachingClassId,
      termId: this.selectedTermId,
      courseName: lesson.courseName.length > 0 ? lesson.courseName : lesson.name,
      courseCode: lesson.courseCode,
      teacherLabel: lesson.teacherLabel,
      initialLessonId: lesson.id,
      isLive: lesson.isLiveAvailable,
      fromSearch: fromSearch
    };
    this.navStack.pushDestination({ name: 'CourseRecordingPlayerPage', param: param });
  }

  private openRelogin(): void {
    this.pendingReauthRefresh = true;
    this.navStack.pushDestination({ name: 'NativeLoginPage' });
  }

  private showToastSafe(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_err) {
      // Ignore if context detached
    }
  }

  @Builder
  private episodeSheetBuilder() {
    Column({ space: 12 }) {
      if (this.sheetCourse !== undefined) {
        Text(this.sheetCourse.name)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.store.colors.textPrimary)
        Text(`${this.sheetCourse.code} · ${this.sheetCourse.teacherLabel}`)
          .fontSize(12)
          .fontColor(this.store.colors.textTertiary)
      }

      if (this.isLoadingSheet) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(this.store.colors.accent)
          Text('正在加载该课程的录播课次...')
            .fontSize(13)
            .fontColor(this.store.colors.textSecondary)
        }
        .padding(20)
      } else if (this.sheetLessons.length === 0) {
        Text('该教学班暂未生成录播课次')
          .fontSize(13)
          .fontColor(this.store.colors.textTertiary)
          .padding(20)
      } else {
        List({ space: 8 }) {
          ForEach(this.sheetLessons, (lesson: ShuYoVodLesson, idx: number) => {
            ListItem() {
              Row({ space: 10 }) {
                Column({ space: 4 }) {
                  Text(lesson.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.store.colors.textPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`第${lesson.weekNumber}周 ${this.getWeekdayText(lesson.weekday)} ${lesson.sectionLabel} · ${lesson.dateLabel} ${lesson.timeRangeLabel} · ${lesson.classroom}`)
                    .fontSize(11)
                    .fontColor(this.store.colors.textTertiary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text(lesson.statusLabel)
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.getStatusBadgeText(lesson))
                  .backgroundColor(this.getStatusBadgeBg(lesson))
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .borderRadius(8)
              }
              .width('100%')
              .padding(12)
              .borderRadius(12)
              .backgroundColor(this.store.colors.surfaceAlt)
              .onClick(() => {
                this.openLessonPlayer(lesson, false);
              })
            }
          }, (lesson: ShuYoVodLesson, idx: number): string => `sheet-lesson-${lesson.id}-${idx}`)
        }
        .width('100%')
        .height(340)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.store.colors.surface)
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        ShuYoTopBar({
          headerTitle: '课程录播与直播',
          subtitleText: this.getSubtitle(),
          showBack: true,
          rightLabel: this.isLoading ? '加载中' : '刷新',
          rightSymbolName: '',
          onBackTap: () => {
            this.navStack.pop();
          },
          onRightTap: () => {
            if (!this.isLoading) {
              this.loadInitialData(true);
            }
          }
        })

        // Term Selector Strip
        if (this.terms.length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.terms, (t: ShuYoVodTerm, idx: number) => {
                Button(`${t.academicYearLabel} ${t.seasonLabel}`)
                  .height(30)
                  .fontSize(12)
                  .fontColor(this.getTermChipText(t.id))
                  .backgroundColor(this.getTermChipBg(t.id))
                  .borderRadius(15)
                  .padding({ left: 12, right: 12 })
                  .onClick(() => {
                    this.selectTerm(t.id);
                  })
              }, (t: ShuYoVodTerm, idx: number): string => `term-${t.id}`)
            }
            .padding({ left: 16, right: 16 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .height(34)
        }

        // Mode Switcher Tabs
        Row({ space: 8 }) {
          Button('课程目录')
            .layoutWeight(1)
            .height(36)
            .fontSize(13)
            .fontColor(this.getModeTabText('catalog'))
            .backgroundColor(this.getModeTabBg('catalog'))
            .borderRadius(10)
            .onClick(() => {
              this.switchMode('catalog');
            })
          Button('周时间表')
            .layoutWeight(1)
            .height(36)
            .fontSize(13)
            .fontColor(this.getModeTabText('timetable'))
            .backgroundColor(this.getModeTabBg('timetable'))
            .borderRadius(10)
            .onClick(() => {
              this.switchMode('timetable');
            })
          Button('全校搜索')
            .layoutWeight(1)
            .height(36)
            .fontSize(13)
            .fontColor(this.getModeTabText('search'))
            .backgroundColor(this.getModeTabBg('search'))
            .borderRadius(10)
            .onClick(() => {
              this.switchMode('search');
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        // Loading / Error Banner
        if (this.isLoading) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(this.store.colors.accent)
            Text('正在连接上海大学录播平台同步课程目录...')
              .fontSize(12)
              .fontColor(this.store.colors.accent)
              .layoutWeight(1)
          }
          .width('92%')
          .padding(10)
          .borderRadius(10)
          .backgroundColor(this.store.colors.accentSoft)
        } else if (!this.store.isDemoMode && this.errorMsg.length > 0) {
          Column({ space: 10 }) {
            Text(this.errorMsg)
              .fontSize(13)
              .fontColor(this.store.colors.danger)
              .width('100%')
            Row({ space: 10 }) {
              if (this.authRequired) {
                Button('重新登录认证')
                  .layoutWeight(1)
                  .height(36)
                  .fontSize(13)
                  .fontColor(this.store.colors.onAccent)
                  .backgroundColor(this.store.colors.accent)
                  .borderRadius(10)
                  .onClick(() => {
                    this.openRelogin();
                  })
              }
              Button('立即重试')
                .layoutWeight(1)
                .height(36)
                .fontSize(13)
                .fontColor(this.store.colors.textPrimary)
                .backgroundColor(this.store.colors.surfaceAlt)
                .border({ width: 1, color: this.store.colors.border })
                .borderRadius(10)
                .onClick(() => {
                  this.loadInitialData(true);
                })
            }
            .width('100%')
          }
          .width('92%')
          .padding(14)
          .borderRadius(14)
          .backgroundColor(this.store.colors.surface)
          .border({ width: 1, color: this.store.colors.border })
        }

        // Main Body per Mode
        if (this.activeMode === 'catalog') {
          Column({ space: 10 }) {
            TextInput({ placeholder: '筛选本学期课程名 / 课程号 / 授课教师...', text: this.catalogFilter })
              .height(40)
              .borderRadius(10)
              .backgroundColor(this.store.colors.surface)
              .fontColor(this.store.colors.textPrimary)
              .border({ width: 1, color: this.store.colors.border })
              .onChange((val: string) => {
                this.catalogFilter = val;
              })

            if (this.liveLessons.length > 0) {
              Column({ space: 8 }) {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.play_circle'))
                    .fontSize(16)
                    .fontColor([this.store.colors.danger])
                  Text(`正在直播 (${this.liveLessons.length})`)
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.store.colors.danger)
                }
                ForEach(this.liveLessons, (live: ShuYoVodLesson, idx: number) => {
                  Row({ space: 10 }) {
                    Column({ space: 2 }) {
                      Text(live.name)
                        .fontSize(14)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.store.colors.textPrimary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(`${live.teacherLabel} · ${live.classroom} · ${live.timeRangeLabel}`)
                        .fontSize(12)
                        .fontColor(this.store.colors.textSecondary)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Button('进入直播')
                      .height(30)
                      .fontSize(12)
                      .fontColor(this.store.colors.onDanger)
                      .backgroundColor(this.store.colors.danger)
                      .borderRadius(15)
                      .padding({ left: 12, right: 12 })
                      .onClick(() => {
                        this.openLessonPlayer(live, false);
                      })
                  }
                  .width('100%')
                  .padding(12)
                  .borderRadius(12)
                  .backgroundColor(this.store.colors.surface)
                  .border({ width: 1, color: this.store.colors.danger })
                }, (live: ShuYoVodLesson, idx: number): string => `live-${live.id}-${idx}`)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            if (this.getFilteredCourses().length === 0 && !this.isLoading) {
              Column({ space: 8 }) {
                Text('当前学期暂无匹配的录播课程')
                  .fontSize(14)
                  .fontColor(this.store.colors.textTertiary)
                Text('您可以切换到“全校搜索”按课程名或教师检索公开录播')
                  .fontSize(12)
                  .fontColor(this.store.colors.textMuted)
              }
              .width('100%')
              .padding(28)
              .borderRadius(16)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
              .alignItems(HorizontalAlign.Center)
            } else {
              List({ space: 10 }) {
                ForEach(this.getFilteredCourses(), (course: ShuYoVodCourse, idx: number) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Column()
                        .width(5)
                        .height(54)
                        .borderRadius(3)
                        .backgroundColor(ShuYoThemes.courseColorFor(course.name))

                      Column({ space: 4 }) {
                        Row({ space: 6 }) {
                          Text(course.name)
                            .fontSize(16)
                            .fontWeight(FontWeight.Bold)
                            .fontColor(this.store.colors.textPrimary)
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .layoutWeight(1)
                          if (course.isLive) {
                            Text('直播中')
                              .fontSize(10)
                              .fontWeight(FontWeight.Bold)
                              .fontColor(this.store.colors.onDanger)
                              .backgroundColor(this.store.colors.danger)
                              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                              .borderRadius(6)
                          }
                        }
                        .width('100%')

                        Text(`${course.code} · ${course.teacherLabel.length > 0 ? course.teacherLabel : '教师未标注'}`)
                          .fontSize(12)
                          .fontColor(this.store.colors.textSecondary)

                        Text(`${course.teachingClassName} · 共 ${course.lessonCount} 讲录播`)
                          .fontSize(11)
                          .fontColor(this.store.colors.textMuted)
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Column({ space: 6 }) {
                        Button('播放')
                          .height(30)
                          .fontSize(12)
                          .fontColor(this.store.colors.onAccent)
                          .backgroundColor(this.store.colors.accent)
                          .borderRadius(15)
                          .padding({ left: 12, right: 12 })
                          .onClick(() => {
                            this.openCoursePlayer(course, course.liveLessonId, course.isLive, false);
                          })
                        Button('选集')
                          .height(26)
                          .fontSize(11)
                          .fontColor(this.store.colors.textSecondary)
                          .backgroundColor(this.store.colors.surfaceAlt)
                          .borderRadius(13)
                          .padding({ left: 10, right: 10 })
                          .onClick(() => {
                            this.openEpisodeSelector(course);
                          })
                      }
                    }
                    .width('100%')
                    .padding(14)
                    .borderRadius(16)
                    .backgroundColor(this.store.colors.surface)
                    .border({ width: 1, color: this.store.colors.border })
                    .onClick(() => {
                      this.openCoursePlayer(course, course.liveLessonId, course.isLive, false);
                    })
                  }
                }, (course: ShuYoVodCourse, idx: number): string => `vod-course-${course.teachingClassId}-${idx}`)
              }
              .width('100%')
              .layoutWeight(1)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
          .layoutWeight(1)
        } else if (this.activeMode === 'timetable') {
          Column({ space: 10 }) {
            Scroll() {
              Row({ space: 6 }) {
                ForEach(this.getWeekNumbers(), (w: number, idx: number) => {
                  Button(`第${w}周`)
                    .height(28)
                    .fontSize(12)
                    .fontColor(this.getWeekChipText(w))
                    .backgroundColor(this.getWeekChipBg(w))
                    .borderRadius(14)
                    .padding({ left: 10, right: 10 })
                    .onClick(() => {
                      this.selectedWeek = w;
                    })
                }, (w: number, idx: number): string => `vod-week-${w}`)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
            .height(32)

            if (this.isLoadingTimetable) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(this.store.colors.accent)
                Text('正在汇总各教学班的周课次时间表...')
                  .fontSize(12)
                  .fontColor(this.store.colors.textSecondary)
              }
              .padding(16)
            } else if (this.getLessonsForSelectedWeek().length === 0) {
              Column({ space: 6 }) {
                Text(`第 ${this.selectedWeek} 周暂无录播课次记录`)
                  .fontSize(14)
                  .fontColor(this.store.colors.textTertiary)
                Text('可切换其他教学周或在“课程目录”中按课程查看')
                  .fontSize(12)
                  .fontColor(this.store.colors.textMuted)
              }
              .width('100%')
              .padding(28)
              .borderRadius(16)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
              .alignItems(HorizontalAlign.Center)
            } else {
              List({ space: 10 }) {
                ForEach(this.getLessonsForSelectedWeek(), (lesson: ShuYoVodLesson, idx: number) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Column({ space: 2 }) {
                        Text(this.getWeekdayText(lesson.weekday))
                          .fontSize(13)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(this.store.colors.accent)
                        Text(lesson.sectionLabel.length > 0 ? lesson.sectionLabel : '课次')
                          .fontSize(11)
                          .fontColor(this.store.colors.textTertiary)
                      }
                      .width(48)
                      .alignItems(HorizontalAlign.Center)

                      Column({ space: 4 }) {
                        Text(lesson.courseName.length > 0 ? lesson.courseName : lesson.name)
                          .fontSize(15)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(this.store.colors.textPrimary)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(`${lesson.dateLabel} ${lesson.timeRangeLabel} · ${lesson.classroom} · ${lesson.teacherLabel}`)
                          .fontSize(12)
                          .fontColor(this.store.colors.textSecondary)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Text(lesson.statusLabel)
                        .fontSize(11)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.getStatusBadgeText(lesson))
                        .backgroundColor(this.getStatusBadgeBg(lesson))
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .borderRadius(8)
                    }
                    .width('100%')
                    .padding(14)
                    .borderRadius(14)
                    .backgroundColor(this.store.colors.surface)
                    .border({ width: 1, color: this.store.colors.border })
                    .onClick(() => {
                      this.openLessonPlayer(lesson, false);
                    })
                  }
                }, (lesson: ShuYoVodLesson, idx: number): string => `tt-${lesson.id}-${idx}`)
              }
              .width('100%')
              .layoutWeight(1)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
          .layoutWeight(1)
        } else {
          // Search Mode
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              TextInput({ placeholder: '输入课程名称、教师姓名或课程号（至少2字）', text: this.searchKeyword })
                .layoutWeight(1)
                .height(42)
                .borderRadius(10)
                .backgroundColor(this.store.colors.surface)
                .fontColor(this.store.colors.textPrimary)
                .border({ width: 1, color: this.store.colors.border })
                .onChange((val: string) => {
                  this.searchKeyword = val;
                })
                .onSubmit(() => {
                  this.handleSearch();
                })

              Button(this.isSearching ? '搜索中' : '搜索')
                .height(42)
                .fontSize(14)
                .fontColor(this.store.colors.onAccent)
                .backgroundColor(this.store.colors.accent)
                .borderRadius(10)
                .padding({ left: 16, right: 16 })
                .enabled(!this.isSearching)
                .onClick(() => {
                  this.handleSearch();
                })
            }
            .width('100%')

            Row() {
              Text(`当前检索学期：${this.getSubtitle()}`)
                .fontSize(12)
                .fontColor(this.store.colors.textTertiary)
              Blank()
              Button(this.searchPlayableOnly ? '仅显示可播放' : '显示全部状态')
                .height(26)
                .fontSize(11)
                .fontColor(this.searchPlayableOnly ? this.store.colors.accent : this.store.colors.textSecondary)
                .backgroundColor(this.searchPlayableOnly ? this.store.colors.accentSoft : this.store.colors.surfaceAlt)
                .borderRadius(13)
                .padding({ left: 10, right: 10 })
                .onClick(() => {
                  this.searchPlayableOnly = !this.searchPlayableOnly;
                })
            }
            .width('100%')

            if (this.isSearching) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(this.store.colors.accent)
                Text('正在检索全校录播与直播课次...')
                  .fontSize(13)
                  .fontColor(this.store.colors.textSecondary)
              }
              .padding(20)
            } else if (!this.hasSearched) {
              Column({ space: 6 }) {
                Text('支持按课程名、教师或课程代码跨教学班搜索')
                  .fontSize(14)
                  .fontColor(this.store.colors.textSecondary)
                Text('搜索结果可直接打开多视角播放器并查看 AI PPT 课堂笔记')
                  .fontSize(12)
                  .fontColor(this.store.colors.textMuted)
              }
              .width('100%')
              .padding(28)
              .borderRadius(16)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
              .alignItems(HorizontalAlign.Center)
            } else if (this.getFilteredSearchResults().length === 0) {
              Column({ space: 6 }) {
                Text('未找到匹配的录播课次')
                  .fontSize(14)
                  .fontColor(this.store.colors.textTertiary)
                Text('可尝试缩短关键词、切换上方学期或关闭“仅显示可播放”筛选')
                  .fontSize(12)
                  .fontColor(this.store.colors.textMuted)
              }
              .width('100%')
              .padding(28)
              .borderRadius(16)
              .backgroundColor(this.store.colors.surface)
              .border({ width: 1, color: this.store.colors.border })
              .alignItems(HorizontalAlign.Center)
            } else {
              List({ space: 10 }) {
                ForEach(this.getFilteredSearchResults(), (item: ShuYoVodLesson, idx: number) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Column()
                        .width(5)
                        .height(48)
                        .borderRadius(3)
                        .backgroundColor(ShuYoThemes.courseColorFor(item.name))

                      Column({ space: 4 }) {
                        Text(item.name)
                          .fontSize(15)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(this.store.colors.textPrimary)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(`${item.courseCode} · ${item.teacherLabel} · ${item.classroom}`)
                          .fontSize(12)
                          .fontColor(this.store.colors.textSecondary)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(`第${item.weekNumber}周 ${item.sectionLabel} · ${item.dateLabel} ${item.timeRangeLabel}`)
                          .fontSize(11)
                          .fontColor(this.store.colors.textMuted)
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Text(item.statusLabel)
                        .fontSize(11)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.getStatusBadgeText(item))
                        .backgroundColor(this.getStatusBadgeBg(item))
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .borderRadius(8)
                    }
                    .width('100%')
                    .padding(14)
                    .borderRadius(14)
                    .backgroundColor(this.store.colors.surface)
                    .border({ width: 1, color: this.store.colors.border })
                    .onClick(() => {
                      this.openLessonPlayer(item, true);
                    })
                  }
                }, (item: ShuYoVodLesson, idx: number): string => `search-${item.id}-${idx}`)
              }
              .width('100%')
              .layoutWeight(1)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.store.colors.background)
      .bindSheet($$this.showEpisodeSheet, this.episodeSheetBuilder(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: true
      })
    }
    .hideTitleBar(true)
    .onShown(() => {
      if (this.pendingReauthRefresh) {
        this.pendingReauthRefresh = false;
        this.loadInitialData(false);
      }
    })
    .onReady((ctx: NavDestinationContext) => {
      this.navStack = ctx.pathStack;
    })
  }
}
