import { AppStorageV2 } from '@kit.ArkUI';
import { ShuYoColorPalette, ShuYoThemeSpec, ShuYoThemes } from '../core/ShuYoTheme';
import {
  ShuYoAnnouncementItem,
  ShuYoCampusCardBill,
  ShuYoCampusCardInfo,
  ShuYoCampusSystem,
  ShuYoCourseSession,
  ShuYoHomeLayoutItem,
  ShuYoHomeModuleId,
  ShuYoLibraryBookingRecord,
  ShuYoProgressSummary,
  ShuYoRateHomeData,
  ShuYoScheduleCollection,
  ShuYoScheduleData,
  ShuYoTabId
} from '../models/ShuYoModels';
import { AcademicProgressService } from '../services/AcademicProgressService';
import { AnnouncementService } from '../services/AnnouncementService';
import { CampusCardService } from '../services/CampusCardService';
import { CourseReviewService } from '../services/CourseReviewService';
import { ShuYoCookieJar } from '../services/HttpClientService';
import { PreferencesService } from '../services/PreferencesService';
import { ScheduleService } from '../services/ScheduleService';
import { JsonHelpers } from '../services/JsonHelpers';

@ObservedV2
export class ShuYoAppStore {
  private static readonly keyInitialized: string = 'shuyo_onboarding_done';
  private static readonly keyDemoMode: string = 'shuyo_demo_mode';
  private static readonly keyStudentId: string = 'shuyo_student_id';
  private static readonly keyCampusSystem: string = 'shuyo_campus_system';
  private static readonly keyThemeId: string = 'shuyo_theme_id';
  private static readonly keyFollowSystem: string = 'shuyo_follow_system';
  private static readonly keyUseWebVpn: string = 'shuyo_use_webvpn';
  private static readonly keyHomeLayout: string = 'shuyo_home_layout_v1';
  private static readonly keyCollections: string = 'shuyo_schedule_collections_v1';
  private static readonly keyBookings: string = 'shuyo_library_bookings_v1';

  @Trace isInitialized: boolean = false;
  @Trace hasCompletedOnboarding: boolean = false;
  @Trace isDemoMode: boolean = false;
  @Trace isLoggedIn: boolean = false;
  @Trace studentId: string = '';
  @Trace studentName: string = '';
  @Trace campusSystem: ShuYoCampusSystem = ShuYoCampusSystem.UNDERGRADUATE;
  @Trace themeId: string = ShuYoThemes.defaultId;
  @Trace followSystemTheme: boolean = false;
  @Trace useWebVpn: boolean = false;
  @Trace activeTabIndex: number = 0;
  @Trace currentWeek: number = 1;
  @Trace dataRevision: number = 0;

  @Trace scheduleCollections: ShuYoScheduleCollection[] = [];
  @Trace activeCollectionId: string = 'col-primary';
  @Trace scheduleData: ShuYoScheduleData = ScheduleService.emptySchedule();
  @Trace progressSummary: ShuYoProgressSummary = AcademicProgressService.loadDemoProgress();
  @Trace announcements: ShuYoAnnouncementItem[] = [];
  @Trace cardInfo: ShuYoCampusCardInfo = CampusCardService.loadDemoCardInfo();
  @Trace cardBills: ShuYoCampusCardBill[] = [];
  @Trace homeLayout: ShuYoHomeLayoutItem[] = [];
  @Trace rateHome: ShuYoRateHomeData = {
    recent: [],
    rankingTitle: '综合评分榜',
    rankingItems: [],
    colleges: [],
    questions: []
  };
  @Trace libraryBookings: ShuYoLibraryBookingRecord[] = [];
  @Trace isSyncingSchedule: boolean = false;
  @Trace statusBanner: string = '';

  static instance(): ShuYoAppStore {
    return AppStorageV2.connect(ShuYoAppStore, 'ShuYoAppStore', () => new ShuYoAppStore())!;
  }

  get colors(): ShuYoColorPalette {
    return ShuYoThemes.byId(this.themeId).colors;
  }

  get themeSpec(): ShuYoThemeSpec {
    return ShuYoThemes.byId(this.themeId);
  }

  get supportedTabs(): ShuYoTabId[] {
    if (this.campusSystem === ShuYoCampusSystem.GRADUATE) {
      return [ShuYoTabId.HOME, ShuYoTabId.SCHEDULE];
    }
    return [ShuYoTabId.HOME, ShuYoTabId.RATE, ShuYoTabId.PROGRESS, ShuYoTabId.SCHEDULE];
  }

  initIfNeeded(): void {
    if (this.isInitialized) {
      return;
    }
    this.themeId = PreferencesService.getString(ShuYoAppStore.keyThemeId, ShuYoThemes.defaultId);
    this.followSystemTheme = PreferencesService.getBoolean(ShuYoAppStore.keyFollowSystem, false);
    this.useWebVpn = PreferencesService.getBoolean(ShuYoAppStore.keyUseWebVpn, false);
    const sysRaw = PreferencesService.getString(ShuYoAppStore.keyCampusSystem, ShuYoCampusSystem.UNDERGRADUATE);
    this.campusSystem = sysRaw === ShuYoCampusSystem.GRADUATE
      ? ShuYoCampusSystem.GRADUATE
      : ShuYoCampusSystem.UNDERGRADUATE;

    this.hasCompletedOnboarding = PreferencesService.getBoolean(ShuYoAppStore.keyInitialized, false);
    this.isDemoMode = PreferencesService.getBoolean(ShuYoAppStore.keyDemoMode, false);
    this.studentId = PreferencesService.getString(ShuYoAppStore.keyStudentId, '');
    this.isLoggedIn = this.studentId.length > 0 && !this.isDemoMode;
    this.studentName = this.isDemoMode
      ? '演示同学'
      : (this.isLoggedIn ? this.studentId : '未登录');

    this.loadHomeLayout();
    this.loadCollections();
    this.loadBookings();
    this.loadDataForCurrentMode();
    if (!this.isDemoMode &&
      this.scheduleData.term.studentName.length > 0 &&
      this.scheduleData.term.studentId !== 'DEMO0001') {
      this.studentName = this.scheduleData.term.studentName;
    }
    this.isInitialized = true;
  }

  enterDemoMode(systemChoice?: ShuYoCampusSystem): void {
    if (systemChoice !== undefined) {
      this.campusSystem = systemChoice;
      PreferencesService.setString(ShuYoAppStore.keyCampusSystem, systemChoice);
    }
    this.isDemoMode = true;
    this.isLoggedIn = false;
    this.studentId = 'DEMO0001';
    this.studentName = '演示同学';
    this.hasCompletedOnboarding = true;
    this.activeTabIndex = 0;
    this.currentWeek = 1;

    PreferencesService.setBoolean(ShuYoAppStore.keyInitialized, true);
    PreferencesService.setBoolean(ShuYoAppStore.keyDemoMode, true);
    PreferencesService.setString(ShuYoAppStore.keyStudentId, 'DEMO0001');

    this.scheduleCollections = [];
    PreferencesService.remove(ShuYoAppStore.keyCollections);
    this.loadCollections();
    this.loadDataForCurrentMode();
    this.dataRevision++;
  }

  async completeRealLogin(studentId: string, systemChoice: ShuYoCampusSystem): Promise<string> {
    this.campusSystem = systemChoice;
    this.isDemoMode = false;
    this.isLoggedIn = true;
    this.studentId = studentId;
    this.studentName = studentId;
    this.hasCompletedOnboarding = true;
    this.activeTabIndex = 0;
    this.currentWeek = 1;
    this.statusBanner = '';

    this.scheduleCollections = [];
    this.activeCollectionId = 'col-primary';
    this.scheduleData = ScheduleService.emptySchedule(studentId);
    PreferencesService.remove(ShuYoAppStore.keyCollections);

    PreferencesService.setBoolean(ShuYoAppStore.keyInitialized, true);
    PreferencesService.setBoolean(ShuYoAppStore.keyDemoMode, false);
    PreferencesService.setString(ShuYoAppStore.keyStudentId, studentId);
    PreferencesService.setString(ShuYoAppStore.keyCampusSystem, systemChoice);

    this.loadDataForCurrentMode();
    const syncMsg = await this.syncSchedule();
    this.refreshSecondaryLiveData();
    this.dataRevision++;
    return syncMsg;
  }

  logout(): void {
    ShuYoCookieJar.clearAll();
    this.isLoggedIn = false;
    this.isDemoMode = false;
    this.studentId = '';
    this.studentName = '未登录';
    this.hasCompletedOnboarding = false;
    this.activeTabIndex = 0;
    this.currentWeek = 1;
    this.statusBanner = '';
    this.scheduleCollections = [];
    this.activeCollectionId = 'col-primary';
    this.scheduleData = ScheduleService.emptySchedule('');
    PreferencesService.setBoolean(ShuYoAppStore.keyInitialized, false);
    PreferencesService.setBoolean(ShuYoAppStore.keyDemoMode, false);
    PreferencesService.remove(ShuYoAppStore.keyStudentId);
    PreferencesService.remove(ShuYoAppStore.keyCollections);
    this.dataRevision++;
  }

  setTheme(themeId: string): void {
    this.themeId = themeId;
    PreferencesService.setString(ShuYoAppStore.keyThemeId, themeId);
    this.dataRevision++;
  }

  setFollowSystemTheme(enabled: boolean): void {
    this.followSystemTheme = enabled;
    PreferencesService.setBoolean(ShuYoAppStore.keyFollowSystem, enabled);
    this.dataRevision++;
  }

  setUseWebVpn(enabled: boolean): void {
    this.useWebVpn = enabled;
    PreferencesService.setBoolean(ShuYoAppStore.keyUseWebVpn, enabled);
    this.dataRevision++;
  }

  setCampusSystem(sys: ShuYoCampusSystem): void {
    this.campusSystem = sys;
    this.activeTabIndex = 0;
    PreferencesService.setString(ShuYoAppStore.keyCampusSystem, sys);
    this.dataRevision++;
  }

  setCurrentWeek(week: number): void {
    const maxW = this.scheduleData.maxWeek > 0 ? this.scheduleData.maxWeek : 16;
    if (week >= 1 && week <= maxW) {
      this.currentWeek = week;
    }
  }

  setActiveTabIndex(idx: number): void {
    const tabs = this.supportedTabs;
    if (idx >= 0 && idx < tabs.length) {
      this.activeTabIndex = idx;
    }
  }

  switchToScheduleTab(): void {
    const tabs = this.supportedTabs;
    for (let i = 0; i < tabs.length; i++) {
      if (tabs[i] === ShuYoTabId.SCHEDULE) {
        this.activeTabIndex = i;
        return;
      }
    }
  }

  loadDataForCurrentMode(): void {
    if (this.isDemoMode) {
      this.announcements = AnnouncementService.loadDemoAnnouncements();
      this.progressSummary = AcademicProgressService.loadDemoProgress();
      this.cardInfo = CampusCardService.loadDemoCardInfo();
      this.cardBills = CampusCardService.loadDemoBills();
      this.rateHome = CourseReviewService.buildDemoHome(this.scheduleData);
      return;
    }
    this.announcements = [];
    this.cardBills = [];
  }

  async refreshSecondaryLiveData(): Promise<void> {
    if (this.isDemoMode) {
      return;
    }
    try {
      const liveAnnouncements = await AnnouncementService.fetchLiveAnnouncements('学校主页');
      if (liveAnnouncements.length > 0) {
        this.announcements = liveAnnouncements;
      }
    } catch (_annErr) {
      // Keep non-blocking
    }

    try {
      const liveRate = await CourseReviewService.fetchLiveHome();
      if (liveRate !== undefined) {
        this.rateHome = liveRate;
      }
    } catch (_rateErr) {
      // Keep fallback data
    }

    if (this.campusSystem === ShuYoCampusSystem.UNDERGRADUATE) {
      try {
        const liveProgress = await AcademicProgressService.fetchLiveProgress();
        this.progressSummary = liveProgress;
      } catch (_progErr) {
        // Keep non-blocking
      }
    }
  }

  async syncSchedule(): Promise<string> {
    if (this.isDemoMode) {
      const demo = ScheduleService.loadDemoSchedule();
      this.replacePrimarySchedule(demo);
      this.statusBanner = '';
      return '演示课表已刷新';
    }
    this.isSyncingSchedule = true;
    this.statusBanner = '';
    try {
      const live = this.campusSystem === ShuYoCampusSystem.GRADUATE
        ? await ScheduleService.fetchGraduateLiveSchedule(this.studentId)
        : await ScheduleService.fetchLiveSchedule();
      this.replacePrimarySchedule(live);
      this.statusBanner = '';
      return `已同步 ${live.sessions.length} 节课程安排`;
    } catch (err) {
      const e = err as Error;
      const msg = e.message.length > 0 ? e.message : '课表同步失败';
      this.statusBanner = msg;
      return `课表同步失败：${msg}`;
    } finally {
      this.isSyncingSchedule = false;
    }
  }

  replacePrimarySchedule(nextSchedule: ShuYoScheduleData): void {
    this.scheduleData = nextSchedule;
    if (nextSchedule.term.studentName.length > 0 &&
      (this.isDemoMode || nextSchedule.term.studentId !== 'DEMO0001')) {
      this.studentName = nextSchedule.term.studentName;
    }
    const nowIso = new Date().toISOString();
    const updatedCols: ShuYoScheduleCollection[] = [];
    let found = false;
    for (let i = 0; i < this.scheduleCollections.length; i++) {
      const col = this.scheduleCollections[i];
      if (col.id === this.activeCollectionId) {
        updatedCols.push({
          id: col.id,
          title: `${nextSchedule.term.academicYearName} ${nextSchedule.term.termName}`.trim(),
          schedule: nextSchedule,
          isPrimary: col.isPrimary,
          updatedAt: nowIso
        });
        found = true;
      } else {
        updatedCols.push(col);
      }
    }
    if (!found) {
      updatedCols.push({
        id: 'col-primary',
        title: `${nextSchedule.term.academicYearName} ${nextSchedule.term.termName}`.trim(),
        schedule: nextSchedule,
        isPrimary: true,
        updatedAt: nowIso
      });
      this.activeCollectionId = 'col-primary';
    }
    this.scheduleCollections = updatedCols;
    this.persistCollections();
    if (this.isDemoMode) {
      this.rateHome = CourseReviewService.buildDemoHome(this.scheduleData);
    }
    this.dataRevision++;
  }

  upsertCourseSession(session: ShuYoCourseSession): void {
    const nextSessions: ShuYoCourseSession[] = [];
    let replaced = false;
    for (let i = 0; i < this.scheduleData.sessions.length; i++) {
      const s = this.scheduleData.sessions[i];
      if (s.id === session.id) {
        nextSessions.push(session);
        replaced = true;
      } else {
        nextSessions.push(s);
      }
    }
    if (!replaced) {
      nextSessions.push(session);
    }
    const nextData: ShuYoScheduleData = {
      term: this.scheduleData.term,
      sessions: nextSessions,
      untimedCourses: this.scheduleData.untimedCourses,
      fetchedAt: new Date().toISOString(),
      maxWeek: this.scheduleData.maxWeek
    };
    this.replacePrimarySchedule(nextData);
  }

  deleteCourseSession(sessionId: string): void {
    const nextSessions: ShuYoCourseSession[] = [];
    for (let i = 0; i < this.scheduleData.sessions.length; i++) {
      if (this.scheduleData.sessions[i].id !== sessionId) {
        nextSessions.push(this.scheduleData.sessions[i]);
      }
    }
    const nextData: ShuYoScheduleData = {
      term: this.scheduleData.term,
      sessions: nextSessions,
      untimedCourses: this.scheduleData.untimedCourses,
      fetchedAt: new Date().toISOString(),
      maxWeek: this.scheduleData.maxWeek
    };
    this.replacePrimarySchedule(nextData);
  }

  switchCollection(collectionId: string): void {
    for (let i = 0; i < this.scheduleCollections.length; i++) {
      if (this.scheduleCollections[i].id === collectionId) {
        this.activeCollectionId = collectionId;
        this.scheduleData = this.scheduleCollections[i].schedule;
        this.currentWeek = 1;
        this.dataRevision++;
        return;
      }
    }
  }

  addImportedCollection(title: string, schedule: ShuYoScheduleData): void {
    const id = `col-${Date.now()}`;
    const next: ShuYoScheduleCollection[] = [...this.scheduleCollections];
    next.push({
      id: id,
      title: title,
      schedule: schedule,
      isPrimary: false,
      updatedAt: new Date().toISOString()
    });
    this.scheduleCollections = next;
    this.activeCollectionId = id;
    this.scheduleData = schedule;
    this.persistCollections();
    this.dataRevision++;
  }

  deleteCollection(collectionId: string): void {
    if (this.scheduleCollections.length <= 1) {
      return;
    }
    const next: ShuYoScheduleCollection[] = [];
    for (let i = 0; i < this.scheduleCollections.length; i++) {
      if (this.scheduleCollections[i].id !== collectionId) {
        next.push(this.scheduleCollections[i]);
      }
    }
    this.scheduleCollections = next;
    if (this.activeCollectionId === collectionId && next.length > 0) {
      this.activeCollectionId = next[0].id;
      this.scheduleData = next[0].schedule;
    }
    this.persistCollections();
    this.dataRevision++;
  }

  updateHomeLayout(items: ShuYoHomeLayoutItem[]): void {
    this.homeLayout = [...items];
    PreferencesService.setString(ShuYoAppStore.keyHomeLayout, JSON.stringify(items));
    this.dataRevision++;
  }

  resetHomeLayout(): void {
    this.homeLayout = ShuYoAppStore.defaultHomeLayout();
    PreferencesService.setString(ShuYoAppStore.keyHomeLayout, JSON.stringify(this.homeLayout));
    this.dataRevision++;
  }

  addLibraryBooking(rec: ShuYoLibraryBookingRecord): void {
    const next: ShuYoLibraryBookingRecord[] = [rec];
    for (let i = 0; i < this.libraryBookings.length; i++) {
      next.push(this.libraryBookings[i]);
    }
    this.libraryBookings = next;
    PreferencesService.setString(ShuYoAppStore.keyBookings, JSON.stringify(next));
    this.dataRevision++;
  }

  cancelLibraryBooking(bookingId: string): void {
    const next: ShuYoLibraryBookingRecord[] = [];
    for (let i = 0; i < this.libraryBookings.length; i++) {
      const b = this.libraryBookings[i];
      if (b.id === bookingId) {
        next.push({
          id: b.id,
          venueId: b.venueId,
          venueName: b.venueName,
          areaId: b.areaId,
          areaName: b.areaName,
          seatId: b.seatId,
          seatLabel: b.seatLabel,
          day: b.day,
          beginTime: b.beginTime,
          endTime: b.endTime,
          status: 'CANCEL'
        });
      } else {
        next.push(b);
      }
    }
    this.libraryBookings = next;
    PreferencesService.setString(ShuYoAppStore.keyBookings, JSON.stringify(next));
    this.dataRevision++;
  }

  sessionsForToday(): ShuYoCourseSession[] {
    const jsDay = new Date().getDay(); // 0=Sun, 1=Mon..6=Sat
    const weekday = jsDay === 0 ? 7 : jsDay;
    const out: ShuYoCourseSession[] = [];
    for (let i = 0; i < this.scheduleData.sessions.length; i++) {
      const s = this.scheduleData.sessions[i];
      if (s.weekday === weekday && (s.weeks.length === 0 || s.weeks.includes(this.currentWeek))) {
        out.push(s);
      }
    }
    out.sort((a: ShuYoCourseSession, b: ShuYoCourseSession): number => a.startSection - b.startSection);
    return out;
  }

  private loadCollections(): void {
    const raw = PreferencesService.getString(ShuYoAppStore.keyCollections, '');
    if (raw.length > 0) {
      const arr = JsonHelpers.parseArray(raw);
      const loaded: ShuYoScheduleCollection[] = [];
      for (let i = 0; i < arr.length; i++) {
        const obj = JsonHelpers.asObject(arr[i]);
        if (obj === undefined) {
          continue;
        }
        const sched = ScheduleService.importScheduleCode(JSON.stringify(obj['schedule'] ?? {}));
        if (sched !== undefined) {
          if (!this.isDemoMode &&
            (sched.term.studentId === 'DEMO0001' || sched.term.studentName === '演示同学')) {
            continue;
          }
          loaded.push({
            id: JsonHelpers.str(obj, 'id', `col-${i}`),
            title: JsonHelpers.str(obj, 'title', '课表'),
            schedule: sched,
            isPrimary: JsonHelpers.bool(obj, 'isPrimary', i === 0),
            updatedAt: JsonHelpers.str(obj, 'updatedAt')
          });
        }
      }
      if (loaded.length > 0) {
        this.scheduleCollections = loaded;
        this.activeCollectionId = loaded[0].id;
        this.scheduleData = loaded[0].schedule;
        return;
      }
    }
    if (this.isDemoMode) {
      const demo = ScheduleService.loadDemoSchedule();
      this.scheduleCollections = ScheduleService.createDefaultCollections(demo);
      this.activeCollectionId = this.scheduleCollections[0].id;
      this.scheduleData = demo;
      return;
    }
    this.scheduleCollections = [];
    this.activeCollectionId = 'col-primary';
    this.scheduleData = ScheduleService.emptySchedule(this.studentId);
  }

  private persistCollections(): void {
    PreferencesService.setString(ShuYoAppStore.keyCollections, JSON.stringify(this.scheduleCollections));
  }

  private loadBookings(): void {
    const raw = PreferencesService.getString(ShuYoAppStore.keyBookings, '');
    if (raw.length === 0) {
      this.libraryBookings = [];
      return;
    }
    const arr = JsonHelpers.parseArray(raw);
    const out: ShuYoLibraryBookingRecord[] = [];
    for (let i = 0; i < arr.length; i++) {
      const obj = JsonHelpers.asObject(arr[i]);
      if (obj === undefined) {
        continue;
      }
      out.push({
        id: JsonHelpers.str(obj, 'id'),
        venueId: JsonHelpers.str(obj, 'venueId'),
        venueName: JsonHelpers.str(obj, 'venueName'),
        areaId: JsonHelpers.str(obj, 'areaId'),
        areaName: JsonHelpers.str(obj, 'areaName'),
        seatId: JsonHelpers.str(obj, 'seatId'),
        seatLabel: JsonHelpers.str(obj, 'seatLabel'),
        day: JsonHelpers.str(obj, 'day'),
        beginTime: JsonHelpers.str(obj, 'beginTime'),
        endTime: JsonHelpers.str(obj, 'endTime'),
        status: JsonHelpers.str(obj, 'status', 'BOOKING')
      });
    }
    this.libraryBookings = out;
  }

  private loadHomeLayout(): void {
    const raw = PreferencesService.getString(ShuYoAppStore.keyHomeLayout, '');
    if (raw.length > 0) {
      const arr = JsonHelpers.parseArray(raw);
      const out: ShuYoHomeLayoutItem[] = [];
      for (let i = 0; i < arr.length; i++) {
        const obj = JsonHelpers.asObject(arr[i]);
        if (obj === undefined) {
          continue;
        }
        const idStr = JsonHelpers.str(obj, 'id');
        let modId: ShuYoHomeModuleId | undefined = undefined;
        if (idStr === ShuYoHomeModuleId.TODAY_COURSE) {
          modId = ShuYoHomeModuleId.TODAY_COURSE;
        } else if (idStr === ShuYoHomeModuleId.CAMPUS_CARD) {
          modId = ShuYoHomeModuleId.CAMPUS_CARD;
        } else if (idStr === ShuYoHomeModuleId.ANNOUNCEMENTS) {
          modId = ShuYoHomeModuleId.ANNOUNCEMENTS;
        } else if (idStr === ShuYoHomeModuleId.CAMPUS_TOOLS) {
          modId = ShuYoHomeModuleId.CAMPUS_TOOLS;
        }
        if (modId !== undefined) {
          out.push({
            id: modId,
            title: JsonHelpers.str(obj, 'title'),
            subtitle: JsonHelpers.str(obj, 'subtitle'),
            enabled: JsonHelpers.bool(obj, 'enabled', true)
          });
        }
      }
      if (out.length === 4) {
        this.homeLayout = out;
        return;
      }
    }
    this.homeLayout = ShuYoAppStore.defaultHomeLayout();
  }

  static defaultHomeLayout(): ShuYoHomeLayoutItem[] {
    return [
      { id: ShuYoHomeModuleId.TODAY_COURSE, title: '今日课程', subtitle: '查看当日课程与上课时间', enabled: true },
      { id: ShuYoHomeModuleId.CAMPUS_CARD, title: '校园卡', subtitle: '余额展示与消费记录', enabled: true },
      { id: ShuYoHomeModuleId.ANNOUNCEMENTS, title: '通知公告', subtitle: '学校与教务重要通知', enabled: true },
      { id: ShuYoHomeModuleId.CAMPUS_TOOLS, title: '校园服务', subtitle: '空教室 / 图书馆 / 校园地图 / 动态口令', enabled: true }
    ];
  }
}
