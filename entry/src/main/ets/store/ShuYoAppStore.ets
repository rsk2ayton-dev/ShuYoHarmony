import { AppStorageV2 } from '@kit.ArkUI';
import { fileIo, fileUri } from '@kit.CoreFileKit';
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
  ShuYoProgressCourse,
  ShuYoProgressNode,
  ShuYoProgressSummary,
  ShuYoRateHomeData,
  ShuYoScheduleCollection,
  ShuYoScheduleData,
  ShuYoTabId
} from '../models/ShuYoModels';
import { AcademicProgressService } from '../services/AcademicProgressService';
import { AnnouncementService } from '../services/AnnouncementService';
import { CampusCardService } from '../services/CampusCardService';
import { CourseRecordingService } from '../services/CourseRecordingService';
import { CourseReviewService } from '../services/CourseReviewService';
import { ShuYoCookieJar } from '../services/HttpClientService';
import { PreferencesService } from '../services/PreferencesService';
import { ScheduleService } from '../services/ScheduleService';
import { JsonHelpers } from '../services/JsonHelpers';

interface ShuYoCardCachePayload {
  studentId: string;
  cardInfo: ShuYoCampusCardInfo;
  bills: ShuYoCampusCardBill[];
  updatedAt: string;
  rangeDays: number;
}

interface ShuYoProgressCachePayload {
  studentId: string;
  summary: ShuYoProgressSummary;
  updatedAt: string;
}

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
  private static readonly keyCampusCardCache: string = 'shuyo_campus_card_cache_v1';
  private static readonly keyProgressCache: string = 'shuyo_academic_progress_cache_v1';
  private static readonly keyCustomTermStartDate: string = 'shuyo_schedule_custom_start_date_v1';
  private static readonly keyCustomNickname: string = 'shuyo_custom_nickname_v1';
  private static readonly keyCustomAvatarUri: string = 'shuyo_custom_avatar_uri_v1';

  @Trace isInitialized: boolean = false;
  @Trace hasCompletedOnboarding: boolean = false;
  @Trace isDemoMode: boolean = false;
  @Trace isLoggedIn: boolean = false;
  @Trace studentId: string = '';
  @Trace studentName: string = '';
  @Trace customNickname: string = '';
  @Trace customAvatarUri: string = '';
  @Trace campusSystem: ShuYoCampusSystem = ShuYoCampusSystem.UNDERGRADUATE;
  @Trace themeId: string = ShuYoThemes.defaultId;
  @Trace followSystemTheme: boolean = false;
  @Trace useWebVpn: boolean = false;
  @Trace activeTabIndex: number = 0;
  @Trace currentWeek: number = 1;
  @Trace customTermStartDate: string = '';
  @Trace dataRevision: number = 0;

  @Trace scheduleCollections: ShuYoScheduleCollection[] = [];
  @Trace activeCollectionId: string = 'col-primary';
  @Trace scheduleData: ShuYoScheduleData = ScheduleService.emptySchedule();
  @Trace progressSummary: ShuYoProgressSummary = AcademicProgressService.emptyProgress();
  @Trace isSyncingProgress: boolean = false;
  @Trace progressError: string = '';
  @Trace progressAuthRequired: boolean = false;
  @Trace progressUpdatedAt: string = '';
  @Trace announcements: ShuYoAnnouncementItem[] = [];
  @Trace isSyncingAnnouncements: boolean = false;
  @Trace announcementsError: string = '';
  @Trace cardInfo: ShuYoCampusCardInfo = CampusCardService.emptyCardInfo();
  @Trace cardBills: ShuYoCampusCardBill[] = [];
  @Trace isSyncingCampusCard: boolean = false;
  @Trace campusCardError: string = '';
  @Trace campusCardAuthRequired: boolean = false;
  @Trace campusCardUpdatedAt: string = '';
  @Trace campusCardRangeDays: number = 90;
  @Trace homeLayout: ShuYoHomeLayoutItem[] = [];
  @Trace rateHome: ShuYoRateHomeData = CourseReviewService.emptyHome();
  @Trace isSyncingRate: boolean = false;
  @Trace rateError: string = '';
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

  get displayName(): string {
    const nick = this.customNickname.trim();
    return nick.length > 0 ? nick : this.studentName;
  }

  setCustomNickname(name: string): void {
    const trimmed = name.trim();
    const capped = trimmed.length > 20 ? trimmed.substring(0, 20) : trimmed;
    this.customNickname = capped;
    if (capped.length > 0) {
      PreferencesService.setString(ShuYoAppStore.keyCustomNickname, capped);
    } else {
      PreferencesService.remove(ShuYoAppStore.keyCustomNickname);
    }
    this.dataRevision++;
  }

  setCustomAvatarUri(uri: string): void {
    const trimmed = uri.trim();
    this.customAvatarUri = trimmed;
    if (trimmed.length > 0) {
      PreferencesService.setString(ShuYoAppStore.keyCustomAvatarUri, trimmed);
    } else {
      PreferencesService.remove(ShuYoAppStore.keyCustomAvatarUri);
    }
    this.dataRevision++;
  }

  clearCustomAvatar(): void {
    const prev = this.customAvatarUri;
    if (prev.startsWith('file://')) {
      try {
        const localPath = new fileUri.FileUri(prev).path;
        if (localPath.length > 0) {
          fileIo.unlinkSync(localPath);
        }
      } catch (_err) {
        // Ignore missing or locked file cleanup failure
      }
    }
    this.customAvatarUri = '';
    PreferencesService.remove(ShuYoAppStore.keyCustomAvatarUri);
    this.dataRevision++;
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
    this.customTermStartDate = PreferencesService.getString(ShuYoAppStore.keyCustomTermStartDate, '');
    this.customNickname = PreferencesService.getString(ShuYoAppStore.keyCustomNickname, '').trim();
    const savedAvatar = PreferencesService.getString(ShuYoAppStore.keyCustomAvatarUri, '').trim();
    if (savedAvatar.startsWith('file://')) {
      try {
        const localPath = new fileUri.FileUri(savedAvatar).path;
        fileIo.accessSync(localPath);
        this.customAvatarUri = savedAvatar;
      } catch (_err) {
        this.customAvatarUri = '';
        PreferencesService.remove(ShuYoAppStore.keyCustomAvatarUri);
      }
    } else {
      this.customAvatarUri = savedAvatar;
    }
    this.isLoggedIn = this.studentId.length > 0 && !this.isDemoMode;
    this.studentName = this.isDemoMode
      ? '演示同学'
      : (this.isLoggedIn ? this.studentId : '未登录');

    this.loadHomeLayout();
    this.loadCollections();
    this.loadBookings();
    this.loadDataForCurrentMode();
    this.currentWeek = this.computeActualCurrentWeek();
    if (!this.isDemoMode &&
      this.scheduleData.term.studentName.length > 0 &&
      this.scheduleData.term.studentId !== 'DEMO0001') {
      this.studentName = this.scheduleData.term.studentName;
    }
    this.isInitialized = true;
    if (!this.isDemoMode) {
      this.syncAnnouncements();
      this.syncRateHome();
      if (this.isLoggedIn) {
        this.syncCampusCard();
        if (this.campusSystem === ShuYoCampusSystem.UNDERGRADUATE) {
          this.syncAcademicProgress();
        }
      }
    }
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
    this.campusCardError = '';
    this.campusCardAuthRequired = false;
    this.campusCardUpdatedAt = '演示数据';
    this.progressError = '';
    this.progressAuthRequired = false;
    this.progressUpdatedAt = '演示数据';
    this.announcementsError = '';
    this.rateError = '';

    PreferencesService.setBoolean(ShuYoAppStore.keyInitialized, true);
    PreferencesService.setBoolean(ShuYoAppStore.keyDemoMode, true);
    PreferencesService.setString(ShuYoAppStore.keyStudentId, 'DEMO0001');

    this.scheduleCollections = [];
    PreferencesService.remove(ShuYoAppStore.keyCollections);
    this.loadCollections();
    this.loadDataForCurrentMode();
    this.currentWeek = this.computeActualCurrentWeek();
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
    this.statusBanner = '';

    this.scheduleCollections = [];
    this.activeCollectionId = 'col-primary';
    this.scheduleData = ScheduleService.emptySchedule(studentId);
    PreferencesService.remove(ShuYoAppStore.keyCollections);

    CampusCardService.clearSession();
    CourseRecordingService.clearSession();
    CourseReviewService.clearStudentToken();
    PreferencesService.remove(ShuYoAppStore.keyCampusCardCache);
    PreferencesService.remove(ShuYoAppStore.keyProgressCache);
    this.cardInfo = CampusCardService.emptyCardInfo(studentId);
    this.cardBills = [];
    this.campusCardError = '';
    this.campusCardAuthRequired = false;
    this.campusCardUpdatedAt = '';
    this.campusCardRangeDays = 90;

    this.progressSummary = AcademicProgressService.emptyProgress(studentId);
    this.progressError = '';
    this.progressAuthRequired = false;
    this.progressUpdatedAt = '';
    this.announcementsError = '';
    this.rateError = '';

    PreferencesService.setBoolean(ShuYoAppStore.keyInitialized, true);
    PreferencesService.setBoolean(ShuYoAppStore.keyDemoMode, false);
    PreferencesService.setString(ShuYoAppStore.keyStudentId, studentId);
    PreferencesService.setString(ShuYoAppStore.keyCampusSystem, systemChoice);

    this.loadDataForCurrentMode();
    const syncMsg = await this.syncSchedule();
    this.currentWeek = this.computeActualCurrentWeek();
    this.refreshSecondaryLiveData();
    this.dataRevision++;
    return syncMsg;
  }

  logout(): void {
    ShuYoCookieJar.clearAll();
    CampusCardService.clearSession();
    CourseRecordingService.clearSession();
    CourseReviewService.clearStudentToken();
    this.isLoggedIn = false;
    this.isDemoMode = false;
    this.studentId = '';
    this.studentName = '未登录';
    this.hasCompletedOnboarding = false;
    this.activeTabIndex = 0;
    this.currentWeek = this.computeActualCurrentWeek();
    this.statusBanner = '';
    this.scheduleCollections = [];
    this.activeCollectionId = 'col-primary';
    this.scheduleData = ScheduleService.emptySchedule('');
    this.progressSummary = AcademicProgressService.emptyProgress('');
    this.isSyncingProgress = false;
    this.progressError = '';
    this.progressAuthRequired = false;
    this.progressUpdatedAt = '';
    this.announcements = [];
    this.announcementsError = '';
    this.rateHome = CourseReviewService.emptyHome();
    this.rateError = '';
    this.cardInfo = CampusCardService.emptyCardInfo('');
    this.cardBills = [];
    this.isSyncingCampusCard = false;
    this.campusCardError = '';
    this.campusCardAuthRequired = false;
    this.campusCardUpdatedAt = '';
    PreferencesService.setBoolean(ShuYoAppStore.keyInitialized, false);
    PreferencesService.setBoolean(ShuYoAppStore.keyDemoMode, false);
    PreferencesService.remove(ShuYoAppStore.keyStudentId);
    PreferencesService.remove(ShuYoAppStore.keyCollections);
    PreferencesService.remove(ShuYoAppStore.keyCampusCardCache);
    PreferencesService.remove(ShuYoAppStore.keyProgressCache);
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

  getEffectiveTermStartDate(): string {
    if (this.customTermStartDate.length > 0) {
      return ScheduleService.alignToMonday(this.customTermStartDate);
    }
    return ScheduleService.resolveDefaultCalendarPreset(this.scheduleData.term).startDate;
  }

  getEffectiveTermLabel(): string {
    if (this.customTermStartDate.length > 0) {
      return `自定义起始周（第1周周一 ${this.getEffectiveTermStartDate()}）`;
    }
    const preset = ScheduleService.resolveDefaultCalendarPreset(this.scheduleData.term);
    return `默认校历 · ${preset.label}（${preset.startDate}）`;
  }

  getEffectiveMaxWeek(): number {
    if (this.customTermStartDate.length > 0) {
      return Math.max(this.scheduleData.maxWeek, 18);
    }
    const preset = ScheduleService.resolveDefaultCalendarPreset(this.scheduleData.term);
    return Math.max(this.scheduleData.maxWeek, preset.maxWeek);
  }

  getRawActualWeek(): number {
    const startDate = this.getEffectiveTermStartDate();
    const todayStr = ScheduleService.getTodayDateStr();
    return ScheduleService.computeWeekFromStart(startDate, todayStr);
  }

  computeActualCurrentWeek(): number {
    const raw = this.getRawActualWeek();
    const maxW = this.getEffectiveMaxWeek();
    if (raw < 1) {
      return 1;
    }
    if (raw > maxW) {
      return maxW;
    }
    return raw;
  }

  setCustomTermStartDate(dateStr: string): void {
    const aligned = ScheduleService.alignToMonday(dateStr);
    this.customTermStartDate = aligned;
    PreferencesService.setString(ShuYoAppStore.keyCustomTermStartDate, aligned);
    this.currentWeek = this.computeActualCurrentWeek();
    this.dataRevision++;
  }

  setActualWeekNumber(weekNum: number): void {
    const clamped = Math.max(1, Math.min(20, weekNum));
    const todayStr = ScheduleService.getTodayDateStr();
    const startMonday = ScheduleService.computeStartMondayForActualWeek(clamped, todayStr);
    this.setCustomTermStartDate(startMonday);
  }

  resetTermStartDateToDefault(): void {
    this.customTermStartDate = '';
    PreferencesService.remove(ShuYoAppStore.keyCustomTermStartDate);
    this.currentWeek = this.computeActualCurrentWeek();
    this.dataRevision++;
  }

  setCurrentWeek(week: number): void {
    const maxW = this.getEffectiveMaxWeek();
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
      this.announcementsError = '';
      this.progressSummary = AcademicProgressService.loadDemoProgress();
      this.progressError = '';
      this.progressAuthRequired = false;
      this.progressUpdatedAt = '演示数据';
      this.cardInfo = CampusCardService.loadDemoCardInfo();
      this.cardBills = CampusCardService.loadDemoBills();
      this.campusCardUpdatedAt = '演示数据';
      this.campusCardError = '';
      this.campusCardAuthRequired = false;
      this.rateHome = CourseReviewService.buildDemoHome(this.scheduleData);
      this.rateError = '';
      return;
    }
    this.announcements = [];
    this.rateHome = CourseReviewService.emptyHome();
    this.loadCampusCardCache();
    this.loadProgressCache();
  }

  async refreshSecondaryLiveData(): Promise<void> {
    if (this.isDemoMode) {
      return;
    }
    await Promise.all([
      this.syncCampusCard(),
      this.syncAnnouncements(),
      this.syncRateHome(),
      this.campusSystem === ShuYoCampusSystem.UNDERGRADUATE
        ? this.syncAcademicProgress()
        : Promise.resolve('')
    ]);
  }

  async syncAnnouncements(): Promise<string> {
    if (this.isDemoMode) {
      this.announcements = AnnouncementService.loadDemoAnnouncements();
      this.announcementsError = '';
      this.dataRevision++;
      return '演示公告已刷新';
    }
    if (this.isSyncingAnnouncements) {
      return '正在加载公告...';
    }
    this.isSyncingAnnouncements = true;
    this.announcementsError = '';
    try {
      const liveAnnouncements = await AnnouncementService.fetchLiveAnnouncements('全部');
      this.announcements = liveAnnouncements;
      this.announcementsError = '';
      this.dataRevision++;
      return `已同步 ${liveAnnouncements.length} 条通知公告`;
    } catch (err) {
      const e = err as Error;
      const msg = e.message.length > 0 ? e.message : '无法加载通知公告';
      this.announcementsError = msg;
      return msg;
    } finally {
      this.isSyncingAnnouncements = false;
    }
  }

  async syncAcademicProgress(): Promise<string> {
    if (this.isDemoMode) {
      this.progressSummary = AcademicProgressService.loadDemoProgress();
      this.progressError = '';
      this.progressAuthRequired = false;
      this.progressUpdatedAt = '演示数据';
      this.dataRevision++;
      return '演示学业数据已刷新';
    }
    if (this.isSyncingProgress) {
      return '正在同步学业修读数据...';
    }
    if (!this.isLoggedIn || this.studentId.length === 0) {
      this.progressAuthRequired = true;
      this.progressError = '请先登录上海大学统一身份认证账号';
      return this.progressError;
    }
    if (this.campusSystem !== ShuYoCampusSystem.UNDERGRADUATE) {
      this.progressError = '研究生系统暂不支持培养方案修读明细查询';
      return this.progressError;
    }
    this.isSyncingProgress = true;
    this.progressError = '';
    this.progressAuthRequired = false;
    try {
      const liveProgress = await AcademicProgressService.fetchLiveProgress(this.studentId, this.useWebVpn);
      this.progressSummary = liveProgress;
      this.progressError = '';
      this.progressAuthRequired = false;
      const now = new Date();
      const hh = now.getHours() < 10 ? `0${now.getHours()}` : `${now.getHours()}`;
      const mm = now.getMinutes() < 10 ? `0${now.getMinutes()}` : `${now.getMinutes()}`;
      this.progressUpdatedAt = `${hh}:${mm}`;
      this.persistProgressCache();
      this.dataRevision++;
      return `学业同步成功，GPA ${liveProgress.gpa}`;
    } catch (err) {
      const e = err as Error;
      const rawMsg = e.message.length > 0 ? e.message : '学业修读同步失败，请稍后重试';
      this.progressAuthRequired = AcademicProgressService.isAuthRequiredError(rawMsg);
      const cleanMsg = AcademicProgressService.stripErrorPrefix(rawMsg);
      this.progressError = cleanMsg;
      return cleanMsg;
    } finally {
      this.isSyncingProgress = false;
    }
  }

  async syncRateHome(): Promise<string> {
    if (this.isDemoMode) {
      this.rateHome = CourseReviewService.buildDemoHome(this.scheduleData);
      this.rateError = '';
      this.dataRevision++;
      return '演示评课数据已刷新';
    }
    if (this.isSyncingRate) {
      return '正在加载课程评价...';
    }
    this.isSyncingRate = true;
    this.rateError = '';
    try {
      const liveRate = await CourseReviewService.fetchLiveHome();
      this.rateHome = liveRate;
      this.rateError = '';
      this.dataRevision++;
      return `已加载 ${liveRate.recent.length} 条近期评价`;
    } catch (err) {
      const e = err as Error;
      const msg = e.message.length > 0 ? e.message : '课程评价加载失败，请稍后重试';
      this.rateError = msg;
      return msg;
    } finally {
      this.isSyncingRate = false;
    }
  }

  async syncCampusCard(rangeDays?: number): Promise<string> {
    if (rangeDays !== undefined && rangeDays > 0) {
      this.campusCardRangeDays = rangeDays;
    }
    if (this.isDemoMode) {
      this.cardInfo = CampusCardService.loadDemoCardInfo();
      this.cardBills = CampusCardService.loadDemoBills();
      this.campusCardError = '';
      this.campusCardAuthRequired = false;
      this.campusCardUpdatedAt = '演示数据';
      this.dataRevision++;
      return '演示校园卡已刷新';
    }
    if (this.isSyncingCampusCard) {
      return '正在同步校园卡...';
    }
    if (!this.isLoggedIn || this.studentId.length === 0) {
      this.campusCardAuthRequired = true;
      this.campusCardError = '请先登录上海大学统一身份认证账号';
      return this.campusCardError;
    }

    this.isSyncingCampusCard = true;
    this.campusCardError = '';
    this.campusCardAuthRequired = false;
    try {
      const res = await CampusCardService.fetchLiveCardAndBills(this.studentId, this.campusCardRangeDays);
      this.cardInfo = res.cardInfo;
      this.cardBills = res.bills;
      this.campusCardError = '';
      this.campusCardAuthRequired = false;
      const now = new Date();
      const hh = now.getHours() < 10 ? `0${now.getHours()}` : `${now.getHours()}`;
      const mm = now.getMinutes() < 10 ? `0${now.getMinutes()}` : `${now.getMinutes()}`;
      this.campusCardUpdatedAt = `${hh}:${mm}`;
      this.persistCampusCardCache();
      this.dataRevision++;
      return `校园卡同步成功，余额 ¥${res.cardInfo.balance.toFixed(2)}`;
    } catch (err) {
      const e = err as Error;
      const rawMsg = e.message.length > 0 ? e.message : '校园卡查询失败，请稍后重试';
      this.campusCardAuthRequired = CampusCardService.isAuthRequiredError(rawMsg);
      const cleanMsg = CampusCardService.stripErrorPrefix(rawMsg);
      this.campusCardError = cleanMsg;
      return cleanMsg;
    } finally {
      this.isSyncingCampusCard = false;
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
        this.currentWeek = this.computeActualCurrentWeek();
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
    const rawWeek = this.getRawActualWeek();
    const maxW = this.getEffectiveMaxWeek();
    if (!this.isDemoMode && (rawWeek < 1 || rawWeek > maxW)) {
      return [];
    }
    const targetWeek = rawWeek >= 1 && rawWeek <= maxW ? rawWeek : this.currentWeek;
    const jsDay = new Date().getDay(); // 0=Sun, 1=Mon..6=Sat
    const weekday = jsDay === 0 ? 7 : jsDay;
    const out: ShuYoCourseSession[] = [];
    for (let i = 0; i < this.scheduleData.sessions.length; i++) {
      const s = this.scheduleData.sessions[i];
      if (s.weekday === weekday && (s.weeks.length === 0 || s.weeks.includes(targetWeek))) {
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

  private loadCampusCardCache(): void {
    if (this.isDemoMode || !this.isLoggedIn || this.studentId.length === 0) {
      this.cardInfo = CampusCardService.emptyCardInfo(this.studentId);
      this.cardBills = [];
      this.campusCardUpdatedAt = '';
      return;
    }
    const raw = PreferencesService.getString(ShuYoAppStore.keyCampusCardCache, '');
    if (raw.length === 0) {
      this.cardInfo = CampusCardService.emptyCardInfo(this.studentId);
      this.cardBills = [];
      this.campusCardUpdatedAt = '';
      return;
    }
    const obj = JsonHelpers.parseObject(raw);
    if (obj === undefined) {
      this.cardInfo = CampusCardService.emptyCardInfo(this.studentId);
      this.cardBills = [];
      this.campusCardUpdatedAt = '';
      return;
    }
    const savedId = JsonHelpers.str(obj, 'studentId').trim();
    if (savedId !== this.studentId || savedId === 'DEMO0001') {
      this.cardInfo = CampusCardService.emptyCardInfo(this.studentId);
      this.cardBills = [];
      this.campusCardUpdatedAt = '';
      return;
    }
    const cObj = JsonHelpers.asObject(obj['cardInfo']);
    const balance = JsonHelpers.num(cObj, 'balance', Number.NaN);
    const cardStu = JsonHelpers.str(cObj, 'studentId').trim();
    if (cObj === undefined || cardStu !== this.studentId || !Number.isFinite(balance)) {
      this.cardInfo = CampusCardService.emptyCardInfo(this.studentId);
      this.cardBills = [];
      this.campusCardUpdatedAt = '';
      return;
    }
    this.cardInfo = {
      studentId: cardStu,
      holderName: JsonHelpers.str(cObj, 'holderName', cardStu),
      cardStatus: JsonHelpers.str(cObj, 'cardStatus', '正常'),
      balance: balance,
      validUntil: JsonHelpers.str(cObj, 'validUntil', ''),
      isLoaded: true
    };
    const rawBills = JsonHelpers.asArray(obj['bills']);
    const parsedBills: ShuYoCampusCardBill[] = [];
    for (let i = 0; i < rawBills.length; i++) {
      const bObj = JsonHelpers.asObject(rawBills[i]);
      if (bObj === undefined) {
        continue;
      }
      const merchant = JsonHelpers.str(bObj, 'merchantName').trim();
      const payTime = JsonHelpers.str(bObj, 'payTime').trim();
      const amount = JsonHelpers.num(bObj, 'amount', Number.NaN);
      if (merchant.length > 0 && payTime.length > 0 && Number.isFinite(amount)) {
        parsedBills.push({
          id: JsonHelpers.str(bObj, 'id', `cached-bill-${i}`),
          merchantName: merchant,
          payTime: payTime,
          amount: amount
        });
      }
    }
    this.cardBills = parsedBills;
    this.campusCardUpdatedAt = JsonHelpers.str(obj, 'updatedAt', '');
    const savedRange = JsonHelpers.num(obj, 'rangeDays', 90);
    if (savedRange > 0) {
      this.campusCardRangeDays = savedRange;
    }
  }

  private persistCampusCardCache(): void {
    if (this.isDemoMode || !this.cardInfo.isLoaded || this.studentId.length === 0) {
      return;
    }
    const payload: ShuYoCardCachePayload = {
      studentId: this.studentId,
      cardInfo: this.cardInfo,
      bills: this.cardBills,
      updatedAt: this.campusCardUpdatedAt,
      rangeDays: this.campusCardRangeDays
    };
    PreferencesService.setString(ShuYoAppStore.keyCampusCardCache, JSON.stringify(payload));
  }

  private loadProgressCache(): void {
    if (this.isDemoMode || !this.isLoggedIn || this.studentId.length === 0) {
      this.progressSummary = AcademicProgressService.emptyProgress(this.studentId);
      this.progressUpdatedAt = '';
      return;
    }
    const raw = PreferencesService.getString(ShuYoAppStore.keyProgressCache, '');
    if (raw.length === 0) {
      this.progressSummary = AcademicProgressService.emptyProgress(this.studentId);
      this.progressUpdatedAt = '';
      return;
    }
    const obj = JsonHelpers.parseObject(raw);
    if (obj === undefined) {
      this.progressSummary = AcademicProgressService.emptyProgress(this.studentId);
      this.progressUpdatedAt = '';
      return;
    }
    const savedStu = JsonHelpers.str(obj, 'studentId', '').trim();
    if (savedStu !== this.studentId || savedStu === 'DEMO0001') {
      this.progressSummary = AcademicProgressService.emptyProgress(this.studentId);
      this.progressUpdatedAt = '';
      return;
    }
    const sumObj = JsonHelpers.asObject(obj['summary']);
    if (sumObj === undefined || !JsonHelpers.bool(sumObj, 'isLoaded', false)) {
      this.progressSummary = AcademicProgressService.emptyProgress(this.studentId);
      this.progressUpdatedAt = '';
      return;
    }
    const rObj = JsonHelpers.asObject(sumObj['ranking']);
    const rawNodes = JsonHelpers.asArray(sumObj['nodes']);
    const parsedNodes: ShuYoProgressNode[] = [];
    for (let i = 0; i < rawNodes.length; i++) {
      const nObj = JsonHelpers.asObject(rawNodes[i]);
      if (nObj === undefined) {
        continue;
      }
      const rawCourses = JsonHelpers.asArray(nObj['courses']);
      const parsedCourses: ShuYoProgressCourse[] = [];
      for (let j = 0; j < rawCourses.length; j++) {
        const cObj = JsonHelpers.asObject(rawCourses[j]);
        if (cObj === undefined) {
          continue;
        }
        parsedCourses.push({
          id: JsonHelpers.str(cObj, 'id', ''),
          code: JsonHelpers.str(cObj, 'code', ''),
          name: JsonHelpers.str(cObj, 'name', ''),
          status: JsonHelpers.str(cObj, 'status', '3'),
          statusLabel: JsonHelpers.str(cObj, 'statusLabel', '未修'),
          credits: JsonHelpers.str(cObj, 'credits', '0'),
          grade: JsonHelpers.str(cObj, 'grade', ''),
          gradePoint: JsonHelpers.str(cObj, 'gradePoint', ''),
          academicYear: JsonHelpers.str(cObj, 'academicYear', ''),
          term: JsonHelpers.str(cObj, 'term', ''),
          nature: JsonHelpers.str(cObj, 'nature', ''),
          hours: JsonHelpers.str(cObj, 'hours', '')
        });
      }
      parsedNodes.push({
        id: JsonHelpers.str(nObj, 'id', `node-${i}`),
        parentId: JsonHelpers.str(nObj, 'parentId', ''),
        name: JsonHelpers.str(nObj, 'name', ''),
        requiredCredits: JsonHelpers.num(nObj, 'requiredCredits', 0),
        earnedCredits: JsonHelpers.num(nObj, 'earnedCredits', 0),
        passed: JsonHelpers.bool(nObj, 'passed', false),
        courseKind: JsonHelpers.str(nObj, 'courseKind', '1'),
        isLeaf: JsonHelpers.bool(nObj, 'isLeaf', true),
        courses: parsedCourses
      });
    }
    this.progressSummary = {
      studentId: JsonHelpers.str(sumObj, 'studentId', this.studentId),
      gpa: JsonHelpers.str(sumObj, 'gpa', '--'),
      plannedCourses: JsonHelpers.num(sumObj, 'plannedCourses', 0),
      passedCourses: JsonHelpers.num(sumObj, 'passedCourses', 0),
      ongoingCourses: JsonHelpers.num(sumObj, 'ongoingCourses', 0),
      notTakenCourses: JsonHelpers.num(sumObj, 'notTakenCourses', 0),
      nodes: parsedNodes,
      ranking: {
        academicYear: JsonHelpers.str(rObj, 'academicYear', ''),
        term: JsonHelpers.str(rObj, 'term', ''),
        collegeName: JsonHelpers.str(rObj, 'collegeName', ''),
        majorName: JsonHelpers.str(rObj, 'majorName', ''),
        collegeRank: JsonHelpers.num(rObj, 'collegeRank', 0),
        collegeCount: JsonHelpers.num(rObj, 'collegeCount', 0),
        majorRank: JsonHelpers.num(rObj, 'majorRank', 0),
        majorCount: JsonHelpers.num(rObj, 'majorCount', 0)
      },
      isLoaded: true
    };
    this.progressUpdatedAt = JsonHelpers.str(obj, 'updatedAt', '');
  }

  private persistProgressCache(): void {
    if (this.isDemoMode || !this.progressSummary.isLoaded || this.studentId.length === 0) {
      return;
    }
    const payload: ShuYoProgressCachePayload = {
      studentId: this.studentId,
      summary: this.progressSummary,
      updatedAt: this.progressUpdatedAt
    };
    PreferencesService.setString(ShuYoAppStore.keyProgressCache, JSON.stringify(payload));
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
      { id: ShuYoHomeModuleId.CAMPUS_TOOLS, title: '校园服务', subtitle: '课程录播 / 空教室 / 图书馆 / 校园地图 / 动态口令', enabled: true }
    ];
  }
}
