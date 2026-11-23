import { http } from '@kit.NetworkKit';
import { ShuYoConstants } from '../core/ShuYoConstants';
import {
  ShuYoVodCourse,
  ShuYoVodLesson,
  ShuYoVodPlayback,
  ShuYoVodPptSlide,
  ShuYoVodTerm,
  ShuYoVodView
} from '../models/ShuYoModels';
import { HttpClientService, ShuYoCookieJar } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';
import { SecureStorageService } from './SecureStorageService';

interface ShuYoVodSavedSession {
  studentId: string;
  jwtToken: string;
  useWebVpn: boolean;
}

export interface ShuYoVodCatalogData {
  courses: ShuYoVodCourse[];
  liveLessons: ShuYoVodLesson[];
}

export class CourseRecordingService {
  private static readonly sessionStorageKey: string = 'shuyo_vod_session_v1';
  private static readonly authRequiredPrefix: string = 'AUTH_REQUIRED:';
  private static readonly tokenExpiredPrefix: string = 'TOKEN_EXPIRED:';

  static isAuthRequiredError(msg: string): boolean {
    return msg.startsWith(CourseRecordingService.authRequiredPrefix);
  }

  static isTokenExpiredError(msg: string): boolean {
    return msg.startsWith(CourseRecordingService.tokenExpiredPrefix);
  }

  static stripErrorPrefix(msg: string): string {
    if (msg.startsWith(CourseRecordingService.authRequiredPrefix)) {
      return msg.substring(CourseRecordingService.authRequiredPrefix.length);
    }
    if (msg.startsWith(CourseRecordingService.tokenExpiredPrefix)) {
      return msg.substring(CourseRecordingService.tokenExpiredPrefix.length);
    }
    return msg;
  }

  static clearSession(): void {
    SecureStorageService.remove(CourseRecordingService.sessionStorageKey);
  }

  private static saveSession(studentId: string, jwtToken: string, useWebVpn: boolean): void {
    const obj: ShuYoVodSavedSession = {
      studentId: studentId,
      jwtToken: jwtToken,
      useWebVpn: useWebVpn
    };
    SecureStorageService.setString(CourseRecordingService.sessionStorageKey, JSON.stringify(obj));
  }

  private static loadSavedSession(expectedStudentId: string, useWebVpn: boolean): string {
    const raw = SecureStorageService.getString(CourseRecordingService.sessionStorageKey, '');
    if (raw.length === 0) {
      return '';
    }
    const obj = JsonHelpers.parseObject(raw);
    if (obj === undefined) {
      return '';
    }
    const stu = JsonHelpers.str(obj, 'studentId').trim();
    const token = JsonHelpers.str(obj, 'jwtToken').trim();
    const vpn = JsonHelpers.bool(obj, 'useWebVpn', false);
    if (stu === expectedStudentId && vpn === useWebVpn && token.length > 0) {
      return token;
    }
    return '';
  }

  static baseUrl(useWebVpn: boolean): string {
    return useWebVpn ? ShuYoConstants.vodWebVpnBase : ShuYoConstants.vodDirectBase;
  }

  static apiUrl(path: string, queryPairs: string[], useWebVpn: boolean): string {
    const normalized = path.startsWith('/') ? path : `/${path}`;
    const q = queryPairs.length > 0 ? `?${queryPairs.join('&')}` : '';
    return `${CourseRecordingService.baseUrl(useWebVpn)}${ShuYoConstants.vodApiPath}${normalized}${q}`;
  }

  static mapServiceUrl(rawUrl: string, useWebVpn: boolean): string {
    if (!useWebVpn || !rawUrl.startsWith('https://')) {
      return rawUrl;
    }
    const host = HttpClientService.extractHost(rawUrl).toLowerCase();
    const origin = HttpClientService.extractOrigin(rawUrl);
    const suffix = rawUrl.substring(origin.length);
    if (host === ShuYoConstants.vodDirectHost) {
      return `https://${ShuYoConstants.vodWebVpnHost}${suffix}`;
    }
    if (host === ShuYoConstants.vodCasHost) {
      return `https://${ShuYoConstants.vodCasWebVpnHost}${suffix}`;
    }
    if (host === ShuYoConstants.vodMediaHost) {
      return `https://${ShuYoConstants.vodMediaWebVpnHost}${suffix}`;
    }
    if (host === ShuYoConstants.vodLiveHost) {
      return `https://${ShuYoConstants.vodLiveWebVpnHost}${suffix}`;
    }
    return rawUrl;
  }

  private static normalizeAuthRedirectUrl(rawUrl: string, useWebVpn: boolean): string {
    const upgraded = HttpClientService.upgradeShuHttpUrl(rawUrl);
    const host = HttpClientService.extractHost(upgraded).toLowerCase();
    const path = HttpClientService.extractPath(upgraded);
    const isSso = host === 'newsso.shu.edu.cn' ||
      host === 'oauth.shu.edu.cn' ||
      host === 'https-newsso-shu-edu-cn-443.webvpn.shu.edu.cn' ||
      host === 'https-oauth-shu-edu-cn-443.webvpn.shu.edu.cn';
    if (isSso && (path.startsWith('/oauth/') || path.startsWith('/oauth2/'))) {
      const origin = HttpClientService.extractOrigin(upgraded);
      let rewritten = ShuYoConstants.ssoBaseUrl + upgraded.substring(origin.length);
      if (useWebVpn && rewritten.includes(ShuYoConstants.vodCasWebVpnHost)) {
        rewritten = rewritten.replace(
          new RegExp(ShuYoConstants.vodCasWebVpnHost, 'g'),
          ShuYoConstants.vodCasHost
        );
      }
      return rewritten;
    }
    return CourseRecordingService.mapServiceUrl(upgraded, useWebVpn);
  }

  private static async verifyJwtToken(
    jwtToken: string,
    expectedStudentId: string,
    useWebVpn: boolean
  ): Promise<boolean> {
    if (jwtToken.length === 0) {
      return false;
    }
    const verifyUrl = CourseRecordingService.apiUrl('/v1/currentuser', [], useWebVpn);
    const resp = await HttpClientService.request(http.RequestMethod.GET, verifyUrl, {
      'Accept': 'application/json',
      'jwt-token': jwtToken
    });
    if (resp.statusCode !== 200) {
      return false;
    }
    const obj = JsonHelpers.parseObject(resp.body);
    if (obj === undefined) {
      return false;
    }
    if (JsonHelpers.str(obj, 'status') !== '200' ||
      obj['ok'] === false ||
      obj['dataOk'] === false) {
      return false;
    }
    const userObj = JsonHelpers.asObject(obj['data']);
    const userCode = JsonHelpers.str(userObj, 'userCode').trim();
    const userId = JsonHelpers.str(userObj, 'id').trim();
    return userId.length > 0 && userCode === expectedStudentId;
  }

  private static async authorizeVodViaSso(
    expectedStudentId: string,
    useWebVpn: boolean
  ): Promise<string> {
    if (!ShuYoCookieJar.hasCookie(ShuYoConstants.ssoBaseUrl, 'SHU_OAUTH2')) {
      throw new Error(`${CourseRecordingService.authRequiredPrefix}统一身份认证会话已失效，请重新登录后使用课程录播`);
    }
    const base = CourseRecordingService.baseUrl(useWebVpn);
    const returnUri = `${base}${ShuYoConstants.vodUiPath}/?type=cas`;
    let current = CourseRecordingService.apiUrl(
      '/oauth2/authorize',
      [`json=0`, `returnUri=${encodeURIComponent(returnUri)}`],
      useWebVpn
    );

    let landedPlatform = false;
    for (let i = 0; i < 16; i++) {
      current = CourseRecordingService.normalizeAuthRedirectUrl(current, useWebVpn);
      const host = HttpClientService.extractHost(current).toLowerCase();
      const path = HttpClientService.extractPath(current);
      if ((host === 'newsso.shu.edu.cn' || host === 'oauth.shu.edu.cn') &&
        (path === '/login' || path === '/login/' || path.startsWith('/oauth2/login/'))) {
        throw new Error(`${CourseRecordingService.authRequiredPrefix}统一身份认证会话已过期，请重新登录`);
      }
      if (host === 'webvpn.shu.edu.cn') {
        throw new Error('WebVPN 会话未就绪，请关闭 WebVPN 开关或重新登录');
      }
      const targetHost = useWebVpn ? ShuYoConstants.vodWebVpnHost : ShuYoConstants.vodDirectHost;
      if (host === targetHost && path.startsWith(ShuYoConstants.vodUiPath)) {
        landedPlatform = true;
        break;
      }

      const resp = await HttpClientService.request(http.RequestMethod.GET, current, {
        'Accept': 'application/json, text/plain, */*'
      });
      if ((host === 'newsso.shu.edu.cn' || host === 'oauth.shu.edu.cn') && resp.statusCode === 401) {
        throw new Error(`${CourseRecordingService.authRequiredPrefix}统一身份认证会话已过期，请重新登录`);
      }
      if (resp.statusCode >= 300 && resp.statusCode < 400 && resp.location.length > 0) {
        current = HttpClientService.resolveUrl(current, resp.location);
        continue;
      }
      if (resp.body.includes('/oauth2/login/')) {
        throw new Error(`${CourseRecordingService.authRequiredPrefix}统一身份认证会话已过期，请重新登录`);
      }
      throw new Error(`录播平台认证未完成（HTTP ${resp.statusCode}），请确认校园网连接或重试`);
    }

    if (!landedPlatform) {
      throw new Error('录播平台单点登录跳转次数过多，请稍后重试');
    }

    const authMeUrl = CourseRecordingService.apiUrl('/authority/me', [], useWebVpn);
    const meResp = await HttpClientService.request(http.RequestMethod.GET, authMeUrl, {
      'Accept': 'application/json, text/plain, */*'
    });
    if (meResp.statusCode !== 200) {
      throw new Error(`录播平台权限校验失败（HTTP ${meResp.statusCode}）`);
    }

    const tokenUrl = CourseRecordingService.apiUrl('/oauth2/token', [], useWebVpn);
    const tokenResp = await HttpClientService.request(http.RequestMethod.GET, tokenUrl, {
      'Accept': 'application/json, text/plain, */*'
    });
    if (tokenResp.statusCode !== 200) {
      throw new Error(`录播平台令牌兑换失败（HTTP ${tokenResp.statusCode}）`);
    }
    const tokenJson = JsonHelpers.parseObject(tokenResp.body);
    const resObj = tokenJson !== undefined
      ? (JsonHelpers.asObject(tokenJson['result']) ?? tokenJson)
      : undefined;
    const jwt = JsonHelpers.str(resObj, 'jwt_token').trim();
    if (jwt.length === 0) {
      throw new Error('录播平台未返回有效的登录凭据，请稍后重试');
    }

    const verified = await CourseRecordingService.verifyJwtToken(jwt, expectedStudentId, useWebVpn);
    if (!verified) {
      throw new Error(`${CourseRecordingService.authRequiredPrefix}录播平台登录身份与当前账号不一致，请重新登录`);
    }
    CourseRecordingService.saveSession(expectedStudentId, jwt, useWebVpn);
    return jwt;
  }

  private static async ensureJwtToken(
    expectedStudentId: string,
    useWebVpn: boolean,
    forceReauth: boolean
  ): Promise<string> {
    const cleanId = expectedStudentId.trim();
    if (cleanId.length === 0) {
      throw new Error(`${CourseRecordingService.authRequiredPrefix}请先登录上海大学统一身份认证账号`);
    }
    if (!forceReauth) {
      const saved = CourseRecordingService.loadSavedSession(cleanId, useWebVpn);
      if (saved.length > 0) {
        const ok = await CourseRecordingService.verifyJwtToken(saved, cleanId, useWebVpn);
        if (ok) {
          return saved;
        }
      }
    }
    CourseRecordingService.clearSession();
    return CourseRecordingService.authorizeVodViaSso(cleanId, useWebVpn);
  }

  private static async vodApiRequestOnce(
    jwtToken: string,
    path: string,
    queryPairs: string[],
    postBodyObj: Record<string, Object> | undefined,
    useWebVpn: boolean
  ): Promise<Object> {
    const url = CourseRecordingService.apiUrl(path, queryPairs, useWebVpn);
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'jwt-token': jwtToken
    };
    let method = http.RequestMethod.GET;
    let bodyStr: string | undefined = undefined;
    if (postBodyObj !== undefined) {
      method = http.RequestMethod.POST;
      headers['Content-Type'] = 'application/json; charset=UTF-8';
      bodyStr = JSON.stringify(postBodyObj);
    }
    const resp = await HttpClientService.request(method, url, headers, bodyStr, 15000);
    if (resp.statusCode === 401 || (resp.statusCode >= 300 && resp.statusCode < 400)) {
      throw new Error(`${CourseRecordingService.tokenExpiredPrefix}录播会话已过期`);
    }
    if (resp.statusCode === 403) {
      throw new Error('当前账号没有该课程录播的访问权限');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw new Error(`录播平台请求失败（HTTP ${resp.statusCode}）`);
    }
    const trimmed = resp.body.trim();
    if (trimmed.startsWith('<')) {
      if (new RegExp('newsso\\.shu|oauth2?/|#/login|统一身份认证|webvpn', 'i').test(trimmed)) {
        throw new Error(`${CourseRecordingService.tokenExpiredPrefix}录播会话已过期`);
      }
      throw new Error('录播平台返回了非预期页面');
    }
    if (trimmed.startsWith('[')) {
      return JsonHelpers.parseArray(trimmed);
    }
    const obj = JsonHelpers.parseObject(trimmed);
    if (obj === undefined) {
      throw new Error('录播平台返回的数据格式异常');
    }
    const status = JsonHelpers.num(obj, 'status', 0);
    const code = JsonHelpers.num(obj, 'code', 0);
    if (status === 401 || status === 10013 || status === 10014 ||
      code === 401 || code === 10013 || code === 10014) {
      throw new Error(`${CourseRecordingService.tokenExpiredPrefix}录播会话已过期`);
    }
    if (status === 403 || code === 403) {
      throw new Error('当前账号没有该课程录播的观看权限');
    }
    const isEmptyPpt = path === '/v1/course/ai/ppt' &&
      status === 200 &&
      obj['ok'] === true &&
      obj['dataOk'] === false &&
      obj['data'] === null;
    if ((status !== 0 && status !== 200) ||
      (code !== 0 && code !== 200) ||
      obj['ok'] === false ||
      (obj['dataOk'] === false && !isEmptyPpt)) {
      throw new Error('录播平台暂时无法完成该请求，请稍后重试');
    }
    return obj;
  }

  private static async vodApiRequest(
    studentId: string,
    path: string,
    queryPairs: string[],
    postBodyObj: Record<string, Object> | undefined,
    useWebVpn: boolean
  ): Promise<Object> {
    const token = await CourseRecordingService.ensureJwtToken(studentId, useWebVpn, false);
    try {
      return await CourseRecordingService.vodApiRequestOnce(token, path, queryPairs, postBodyObj, useWebVpn);
    } catch (firstErr) {
      const fe = firstErr as Error;
      if (!CourseRecordingService.isTokenExpiredError(fe.message)) {
        throw fe;
      }
      const freshToken = await CourseRecordingService.ensureJwtToken(studentId, useWebVpn, true);
      return CourseRecordingService.vodApiRequestOnce(freshToken, path, queryPairs, postBodyObj, useWebVpn);
    }
  }

  // ==================== Parsers ====================

  private static parseTimeMs(val: Object | undefined | null): number {
    if (val === undefined || val === null) {
      return 0;
    }
    if (typeof val === 'number') {
      return Number.isFinite(val) ? Math.floor(val) : 0;
    }
    if (typeof val === 'string') {
      const trimmed = val.trim();
      if (trimmed.length === 0) {
        return 0;
      }
      const numVal = Number(trimmed);
      if (Number.isFinite(numVal) && numVal > 1000000000) {
        return Math.floor(numVal);
      }
      const normalized = trimmed.replace(' ', 'T');
      const parsed = Date.parse(normalized);
      return Number.isFinite(parsed) ? parsed : 0;
    }
    return 0;
  }

  private static formatTimeRangeAndWeekday(
    beginMs: number,
    endMs: number
  ): string[] {
    if (beginMs <= 0) {
      return ['', '', '1'];
    }
    const d = new Date();
    d.setTime(beginMs);
    const m = CourseRecordingService.pad2(d.getMonth() + 1);
    const day = CourseRecordingService.pad2(d.getDate());
    const bh = CourseRecordingService.pad2(d.getHours());
    const bm = CourseRecordingService.pad2(d.getMinutes());
    const jsDay = d.getDay();
    const weekday = jsDay === 0 ? 7 : jsDay;
    const dateLabel = `${m}-${day}`;
    let timeRange = `${bh}:${bm}`;
    if (endMs > beginMs) {
      d.setTime(endMs);
      const eh = CourseRecordingService.pad2(d.getHours());
      const em = CourseRecordingService.pad2(d.getMinutes());
      timeRange = `${bh}:${bm}-${eh}:${em}`;
    }
    return [dateLabel, timeRange, `${weekday}`];
  }

  static formatDurationLabel(sec: number): string {
    const safe = sec > 0 && Number.isFinite(sec) ? Math.floor(sec) : 0;
    const mins = Math.floor(safe / 60);
    const rem = safe % 60;
    return `${CourseRecordingService.pad2(mins)}:${CourseRecordingService.pad2(rem)}`;
  }

  private static stripHtmlTags(raw: string): string {
    if (raw.length === 0) {
      return '';
    }
    return raw.replace(new RegExp('<[^>]*>', 'g'), '').replace(new RegExp('\\s+', 'g'), ' ').trim();
  }

  private static parseTerm(obj: Record<string, Object>): ShuYoVodTerm {
    const id = JsonHelpers.num(obj, 'id', 0);
    const year = JsonHelpers.str(obj, 'acyeCode').trim();
    const termNum = JsonHelpers.num(obj, 'acteTerm', 0);
    const isCurrent = JsonHelpers.bool(obj, 'currentTerm', false);
    const startYearStr = year.split('-')[0];
    const startYear = parseInt(startYearStr, 10);
    const usesHistorical = Number.isFinite(startYear) && startYear < 2025;

    let seasonLabel = `第${termNum}学期`;
    if (usesHistorical) {
      if (termNum === 1) {
        seasonLabel = '秋季学期';
      } else if (termNum === 2) {
        seasonLabel = '冬季学期';
      } else if (termNum === 3) {
        seasonLabel = '春季学期';
      } else if (termNum === 4) {
        seasonLabel = '夏季学期';
      }
    } else {
      if (termNum === 1) {
        seasonLabel = '秋季学期';
      } else if (termNum === 2) {
        seasonLabel = '春季学期';
      } else if (termNum === 3) {
        seasonLabel = '夏季学期';
      }
    }

    let weekCount = 16;
    if (usesHistorical) {
      weekCount = (termNum === 1 || termNum === 2 || termNum === 3) ? 10 : 12;
    } else {
      weekCount = (termNum === 1 || termNum === 2) ? 16 : 4;
    }

    const yearParts = year.split('-');
    const shortParts: string[] = [];
    for (let i = 0; i < yearParts.length; i++) {
      const yp = yearParts[i].trim();
      shortParts.push(yp.length === 4 ? yp.substring(2) : yp);
    }
    const academicYearLabel = year.length > 0 ? `${shortParts.join('-')}学年` : '其他学年';

    return {
      id: id,
      name: year.length > 0 ? `${year}学年第${termNum}学期` : `第${termNum}学期`,
      academicYear: year,
      termNumber: termNum,
      isCurrent: isCurrent,
      academicYearLabel: academicYearLabel,
      seasonLabel: seasonLabel,
      startDateMs: CourseRecordingService.parseTimeMs(obj['acteBeginDate']),
      endDateMs: CourseRecordingService.parseTimeMs(obj['acteEndDate']),
      teachingWeekCount: weekCount
    };
  }

  private static parseCourse(obj: Record<string, Object>): ShuYoVodCourse {
    const subjName = CourseRecordingService.stripHtmlTags(JsonHelpers.str(obj, 'subjName'));
    const teclName = CourseRecordingService.stripHtmlTags(JsonHelpers.str(obj, 'teclName'));
    const name = subjName.length > 0 ? subjName : teclName;
    const rawTeachers = JsonHelpers.asArray(obj['teacNames']);
    const teacherSet = new Set<string>();
    for (let i = 0; i < rawTeachers.length; i++) {
      const t = CourseRecordingService.stripHtmlTags(String(rawTeachers[i] ?? ''));
      if (t.length > 0) {
        teacherSet.add(t);
      }
    }
    const teacherNames = Array.from(teacherSet);
    return {
      teachingClassId: JsonHelpers.num(obj, 'teclId', JsonHelpers.num(obj, 'id', 0)),
      termId: JsonHelpers.num(obj, 'acteId', 0),
      name: name,
      teachingClassName: teclName,
      code: CourseRecordingService.stripHtmlTags(JsonHelpers.str(obj, 'subjCode')),
      teacherNames: teacherNames,
      teacherLabel: teacherNames.join('、'),
      lessonCount: JsonHelpers.num(obj, 'courTimes', 0),
      coverUrl: JsonHelpers.str(obj, 'teclImgUrl').trim(),
      isLive: false,
      liveLessonId: 0
    };
  }

  private static parseLesson(
    obj: Record<string, Object>,
    fallbackCourseName: string,
    fallbackCode: string,
    fallbackTeacher: string,
    isLiveRecord: boolean
  ): ShuYoVodLesson {
    const id = JsonHelpers.num(obj, 'id', 0);
    const teclId = JsonHelpers.num(obj, 'teclId', 0);
    const subjName = CourseRecordingService.stripHtmlTags(
      JsonHelpers.str(obj, 'subjName', JsonHelpers.str(obj, 'teclName', fallbackCourseName))
    );
    const code = CourseRecordingService.stripHtmlTags(JsonHelpers.str(obj, 'subjCode', fallbackCode));
    const rawTeachers = JsonHelpers.asArray(obj['teacNames']);
    const tList: string[] = [];
    for (let i = 0; i < rawTeachers.length; i++) {
      const t = CourseRecordingService.stripHtmlTags(String(rawTeachers[i] ?? ''));
      if (t.length > 0 && !tList.includes(t)) {
        tList.push(t);
      }
    }
    const teacherLabel = tList.length > 0 ? tList.join('、') : fallbackTeacher;
    const sectionNum = JsonHelpers.num(obj, 'letiNumber', 0);
    const sectionLabel = sectionNum > 0 ? `第${sectionNum}节` : '';
    const weekNo = JsonHelpers.num(obj, 'weekNo', JsonHelpers.num(obj, 'weekNumber', 0));
    const classroom = CourseRecordingService.stripHtmlTags(JsonHelpers.str(obj, 'clroName'));
    const watchPercent = JsonHelpers.str(obj, 'watchPercent').trim();

    const beginMs = CourseRecordingService.parseTimeMs(obj['courBeginTime']);
    const endMs = CourseRecordingService.parseTimeMs(obj['courEndTime']);
    const formatted = CourseRecordingService.formatTimeRangeAndWeekday(beginMs, endMs);
    const dateLabel = formatted[0];
    const timeRangeLabel = formatted[1];
    const weekday = parseInt(formatted[2], 10);

    let isPlayable = false;
    let isLiveAvailable = false;
    let isGenerating = false;
    let isListed = false;

    if (isLiveRecord) {
      const livePlayable = JsonHelpers.num(obj, 'liveType', -1) === 0 &&
        JsonHelpers.num(obj, 'liveEnable', -1) !== 0 &&
        JsonHelpers.num(obj, 'courLiveOpen', -1) !== 0 &&
        JsonHelpers.num(obj, 'livevodEnable', -1) !== 0;
      const liveEndMs = CourseRecordingService.parseTimeMs(obj['liveEndTime']);
      const nowMs = Date.now();
      isPlayable = livePlayable;
      isLiveAvailable = livePlayable && (liveEndMs <= 0 || nowMs < liveEndMs);
      isListed = true;
    } else {
      const vodStatus = JsonHelpers.num(obj, 'vodStatus', -1);
      const vodEnable = JsonHelpers.num(obj, 'vodEnable', -1);
      const vodDelete = JsonHelpers.num(obj, 'vodDeleteStatus', -1);
      isListed = vodEnable === 1 && vodDelete === 0;
      isPlayable = vodStatus === 5 && isListed;
      isGenerating = isListed &&
        (JsonHelpers.num(obj, 'vodDisplayStatus', 0) === 1 ||
          JsonHelpers.num(obj, 'vodStatusShow', 0) === 4);
    }

    let statusLabel = '录播回放';
    if (isLiveRecord) {
      statusLabel = isLiveAvailable ? '正在直播' : '直播已结束';
    } else if (isGenerating && !isPlayable) {
      statusLabel = '回放生成中';
    } else if (isPlayable) {
      statusLabel = '录播回放';
    } else if (id > 0 && teclId > 0) {
      statusLabel = '查看录播';
    } else {
      statusLabel = '暂不可看';
    }

    return {
      id: id,
      teachingClassId: teclId,
      name: subjName.length > 0 ? subjName : fallbackCourseName,
      courseName: fallbackCourseName.length > 0 ? fallbackCourseName : subjName,
      courseCode: code,
      teacherLabel: teacherLabel,
      beginTimeMs: beginMs,
      endTimeMs: endMs,
      dateLabel: dateLabel,
      timeRangeLabel: timeRangeLabel,
      weekNumber: weekNo,
      weekday: weekday >= 1 && weekday <= 7 ? weekday : 1,
      sectionNumber: sectionNum > 0 ? sectionNum : 1,
      sectionLabel: sectionLabel,
      classroom: classroom,
      watchPercent: watchPercent,
      isPlayable: isPlayable,
      isLive: isLiveRecord,
      isLiveAvailable: isLiveAvailable,
      isGenerating: isGenerating,
      isListed: isListed,
      statusLabel: statusLabel
    };
  }

  private static viewLabelFor(viewNumber: number): string {
    if (viewNumber === 1) {
      return '教师视角 1';
    }
    if (viewNumber === 2) {
      return '教师视角 2';
    }
    if (viewNumber === 3) {
      return '学生视角 1';
    }
    if (viewNumber === 4) {
      return '学生视角 2';
    }
    if (viewNumber === 5) {
      return 'PPT 画面';
    }
    if (viewNumber === 6) {
      return '电子白板';
    }
    if (viewNumber === 7) {
      return '合成画面';
    }
    return `视角 ${viewNumber}`;
  }

  // ==================== Public Live API Methods ====================

  static async fetchLiveTerms(studentId: string, useWebVpn: boolean): Promise<ShuYoVodTerm[]> {
    const raw = await CourseRecordingService.vodApiRequest(
      studentId,
      '/v1/list/termYear',
      [],
      undefined,
      useWebVpn
    );
    const list = JsonHelpers.asArray(raw);
    const out: ShuYoVodTerm[] = [];
    for (let i = 0; i < list.length; i++) {
      const obj = JsonHelpers.asObject(list[i]);
      if (obj === undefined) {
        continue;
      }
      const term = CourseRecordingService.parseTerm(obj);
      if (term.id > 0 && term.termNumber >= 1) {
        out.push(term);
      }
    }
    out.sort((a: ShuYoVodTerm, b: ShuYoVodTerm): number => {
      if (a.isCurrent !== b.isCurrent) {
        return a.isCurrent ? -1 : 1;
      }
      return b.id - a.id;
    });
    return out;
  }

  static async fetchLiveCatalog(
    studentId: string,
    termId: number,
    useWebVpn: boolean
  ): Promise<ShuYoVodCatalogData> {
    const courseResp = await CourseRecordingService.vodApiRequest(
      studentId,
      '/v1/group_subject_vod_list/t-1',
      [
        `acteId=${termId}`,
        `page.pageIndex=1`,
        `page.pageSize=100`,
        `page.orders[0].field=updateTime`,
        `page.orders[0].asc=false`
      ],
      undefined,
      useWebVpn
    );
    const courseObj = JsonHelpers.asObject(courseResp);
    const courseData = JsonHelpers.asObject(courseObj !== undefined ? courseObj['data'] : undefined);
    const courseRecords = JsonHelpers.asArray(courseData !== undefined ? courseData['records'] : undefined);

    const courseMap = new Map<number, ShuYoVodCourse>();
    const courseOrder: number[] = [];
    for (let i = 0; i < courseRecords.length; i++) {
      const rec = JsonHelpers.asObject(courseRecords[i]);
      if (rec === undefined) {
        continue;
      }
      const c = CourseRecordingService.parseCourse(rec);
      if (c.teachingClassId > 0 && c.name.length > 0 && !courseMap.has(c.teachingClassId)) {
        courseMap.set(c.teachingClassId, c);
        courseOrder.push(c.teachingClassId);
      }
    }

    const liveLessons: ShuYoVodLesson[] = [];
    try {
      const liveResp = await CourseRecordingService.vodApiRequest(
        studentId,
        '/v1/vod_live/t-1',
        [
          `acteId=${termId}`,
          `liveType=0`,
          `page.pageIndex=1`,
          `page.pageSize=100`,
          `page.orders[0].field=courBeginTime`,
          `page.orders[0].asc=false`
        ],
        undefined,
        useWebVpn
      );
      const liveObj = JsonHelpers.asObject(liveResp);
      const liveData = JsonHelpers.asObject(liveObj !== undefined ? liveObj['data'] : undefined);
      const liveRecords = JsonHelpers.asArray(liveData !== undefined ? liveData['records'] : undefined);
      for (let i = 0; i < liveRecords.length; i++) {
        const rec = JsonHelpers.asObject(liveRecords[i]);
        if (rec === undefined) {
          continue;
        }
        const lesson = CourseRecordingService.parseLesson(rec, '', '', '', true);
        if (lesson.id > 0 && lesson.teachingClassId > 0 && lesson.isLiveAvailable) {
          liveLessons.push(lesson);
          const existing = courseMap.get(lesson.teachingClassId);
          if (existing !== undefined) {
            existing.isLive = true;
            existing.liveLessonId = lesson.id;
          } else {
            const liveCourse = CourseRecordingService.parseCourse(rec);
            liveCourse.isLive = true;
            liveCourse.liveLessonId = lesson.id;
            courseMap.set(liveCourse.teachingClassId, liveCourse);
            courseOrder.unshift(liveCourse.teachingClassId);
          }
        }
      }
    } catch (_liveErr) {
      // Keep catalog usable if live query fails
    }

    const courses: ShuYoVodCourse[] = [];
    for (let i = 0; i < courseOrder.length; i++) {
      const c = courseMap.get(courseOrder[i]);
      if (c !== undefined && c.isLive) {
        courses.push(c);
      }
    }
    for (let i = 0; i < courseOrder.length; i++) {
      const c = courseMap.get(courseOrder[i]);
      if (c !== undefined && !c.isLive) {
        courses.push(c);
      }
    }

    return {
      courses: courses,
      liveLessons: liveLessons
    };
  }

  static async fetchLiveCourseLessons(
    studentId: string,
    teachingClassId: number,
    courseName: string,
    courseCode: string,
    teacherLabel: string,
    fromSearch: boolean,
    useWebVpn: boolean
  ): Promise<ShuYoVodLesson[]> {
    const endpoint = fromSearch ? '/v1/subject_vod_list/preview' : '/v1/subject_vod_list_new';
    const resp = await CourseRecordingService.vodApiRequest(
      studentId,
      endpoint,
      [
        `teclIds=${teachingClassId}`,
        `schoolOpenStatusFlag=false`,
        `page.pageIndex=1`,
        `page.pageSize=100`,
        `page.orders[0].field=courBeginTime`,
        `page.orders[0].asc=true`
      ],
      undefined,
      useWebVpn
    );
    const obj = JsonHelpers.asObject(resp);
    const data = JsonHelpers.asObject(obj !== undefined ? obj['data'] : undefined);
    const records = JsonHelpers.asArray(data !== undefined ? data['records'] : undefined);
    const out: ShuYoVodLesson[] = [];
    for (let i = 0; i < records.length; i++) {
      const rec = JsonHelpers.asObject(records[i]);
      if (rec === undefined) {
        continue;
      }
      const lesson = CourseRecordingService.parseLesson(rec, courseName, courseCode, teacherLabel, false);
      if (lesson.id > 0) {
        out.push(lesson);
      }
    }
    out.sort((a: ShuYoVodLesson, b: ShuYoVodLesson): number => a.beginTimeMs - b.beginTimeMs);
    return out;
  }

  static async searchLiveLessons(
    studentId: string,
    termId: number,
    keyword: string,
    useWebVpn: boolean
  ): Promise<ShuYoVodLesson[]> {
    const clean = keyword.trim();
    if (clean.length < 2) {
      throw new Error('请输入至少 2 个字符的课程名、教师或课程号');
    }
    const bodyObj: Record<string, Object> = {
      'acteId': termId,
      'keyword': clean,
      'queryType': 0,
      'maxSearchCount': 50
    };
    const resp = await CourseRecordingService.vodApiRequest(
      studentId,
      '/v1/course/source/search',
      [],
      bodyObj,
      useWebVpn
    );
    const obj = JsonHelpers.asObject(resp);
    const data = JsonHelpers.asObject(obj !== undefined ? obj['data'] : undefined);
    const records = JsonHelpers.asArray(data !== undefined ? data['courseSourceList'] : undefined);
    const out: ShuYoVodLesson[] = [];
    const seenIds = new Set<number>();

    for (let i = 0; i < records.length; i++) {
      const rec = JsonHelpers.asObject(records[i]);
      if (rec === undefined) {
        continue;
      }
      const statusStr = JsonHelpers.str(rec, 'courseStatus');
      if (statusStr !== '0' && statusStr !== '2') {
        continue;
      }
      const isLive = statusStr === '0';
      const lesson = CourseRecordingService.parseLesson(rec, '', '', '', isLive);
      if (lesson.id > 0 && lesson.teachingClassId > 0 && !seenIds.has(lesson.id)) {
        seenIds.add(lesson.id);
        out.push(lesson);
      }
    }
    return out;
  }

  static async fetchLivePlayback(
    studentId: string,
    teachingClassId: number,
    lessonId: number,
    fallbackTitle: string,
    isLive: boolean,
    useWebVpn: boolean
  ): Promise<ShuYoVodPlayback> {
    if (isLive) {
      const resp = await CourseRecordingService.vodApiRequest(
        studentId,
        '/v1/course_vod_videoinfos',
        [`courseId=${lessonId}`, `playType=3`],
        undefined,
        useWebVpn
      );
      const obj = JsonHelpers.asObject(resp);
      const data = JsonHelpers.asObject(obj !== undefined ? obj['data'] : undefined);
      const rawViews = JsonHelpers.asArray(data !== undefined ? data['courseDeviceViewDtoList'] : undefined);
      const views: ShuYoVodView[] = [];
      for (let i = 0; i < rawViews.length; i++) {
        const vObj = JsonHelpers.asObject(rawViews[i]);
        if (vObj === undefined) {
          continue;
        }
        const devStatus = JsonHelpers.num(vObj, 'deviceStatus', -1);
        if (devStatus !== 0 && devStatus !== 1) {
          continue;
        }
        const hlsUrl = JsonHelpers.str(vObj, 'chanNameMainHlsPlayUrl').trim();
        const mainUrl = JsonHelpers.str(vObj, 'chanNameMainPlayUrl').trim();
        let src = hlsUrl.length > 0 ? hlsUrl : mainUrl;
        if (src.length === 0) {
          continue;
        }
        const token = JsonHelpers.str(vObj, 'mainTokenStr').trim();
        if (token.length > 0 && !src.includes('account_token=')) {
          const sep = src.includes('?') ? '&' : '?';
          src = `${src}${sep}account_token=${encodeURIComponent(token)}`;
        }
        views.push({
          viewNumber: JsonHelpers.num(vObj, 'deviViewNum', i + 1),
          label: `直播视角 ${views.length + 1}`,
          url: CourseRecordingService.mapServiceUrl(src, useWebVpn)
        });
      }
      if (views.length === 0) {
        throw new Error('直播设备当前未提供可播放的 HLS 画面');
      }
      return {
        lessonId: lessonId,
        teachingClassId: teachingClassId,
        title: JsonHelpers.str(data, 'courName', fallbackTitle),
        views: views,
        lastPositionSec: 0,
        isLive: true,
        description: JsonHelpers.str(data, 'description', JsonHelpers.str(data, 'teclDescription'))
      };
    }

    const resp = await CourseRecordingService.vodApiRequest(
      studentId,
      '/v1/course_vod_urls_new',
      [`courseId=${lessonId}`],
      undefined,
      useWebVpn
    );
    const obj = JsonHelpers.asObject(resp);
    const data = JsonHelpers.asObject(obj !== undefined ? obj['data'] : undefined);
    const rawViews = JsonHelpers.asArray(data !== undefined ? data['courseVodViewList'] : undefined);
    const views: ShuYoVodView[] = [];
    for (let i = 0; i < rawViews.length; i++) {
      const vObj = JsonHelpers.asObject(rawViews[i]);
      if (vObj === undefined) {
        continue;
      }
      const rawUrl = JsonHelpers.str(vObj, 'url').trim();
      if (rawUrl.length === 0) {
        continue;
      }
      const viewNum = JsonHelpers.num(vObj, 'viewNum', i + 1);
      views.push({
        viewNumber: viewNum,
        label: CourseRecordingService.viewLabelFor(viewNum),
        url: CourseRecordingService.mapServiceUrl(rawUrl, useWebVpn)
      });
    }
    if (views.length === 0) {
      throw new Error('这节课暂无可播放的录播视频流');
    }
    const lastSec = JsonHelpers.num(data, 'lastPlayTime', 0);
    return {
      lessonId: lessonId,
      teachingClassId: teachingClassId,
      title: JsonHelpers.str(data, 'courName', fallbackTitle),
      views: views,
      lastPositionSec: lastSec > 0 ? lastSec : 0,
      isLive: false,
      description: JsonHelpers.str(data, 'description', JsonHelpers.str(data, 'teclDescription'))
    };
  }

  static async fetchLivePptSlides(
    studentId: string,
    lessonId: number,
    useWebVpn: boolean
  ): Promise<ShuYoVodPptSlide[]> {
    const resp = await CourseRecordingService.vodApiRequest(
      studentId,
      '/v1/course/ai/ppt',
      [`courseId=${lessonId}`],
      undefined,
      useWebVpn
    );
    const obj = JsonHelpers.asObject(resp);
    if (obj === undefined || obj['data'] === null || obj['data'] === undefined) {
      return [];
    }
    const data = JsonHelpers.asObject(obj['data']);
    const docs = JsonHelpers.asArray(data !== undefined ? data['docList'] : undefined);
    const out: ShuYoVodPptSlide[] = [];
    const base = CourseRecordingService.baseUrl(useWebVpn);

    for (let i = 0; i < docs.length; i++) {
      const dObj = JsonHelpers.asObject(docs[i]);
      if (dObj === undefined || dObj['showFlag'] === false) {
        continue;
      }
      const ocrText = JsonHelpers.str(dObj, 'ocrText').trim();
      if (ocrText.length === 0) {
        continue;
      }
      const docId = JsonHelpers.str(dObj, 'pptDocId', `slide-${i}`).trim();
      const rawImg = JsonHelpers.str(dObj, 'imageUrl').trim();
      const resolvedImg = rawImg.length > 0
        ? CourseRecordingService.mapServiceUrl(HttpClientService.resolveUrl(base, rawImg), useWebVpn)
        : '';
      const seekSec = Math.max(0, Math.round(JsonHelpers.num(dObj, 'imageSeekTime', 0)));
      out.push({
        id: docId,
        imageUrl: resolvedImg,
        positionSec: seekSec,
        timeLabel: CourseRecordingService.formatDurationLabel(seekSec),
        text: ocrText
      });
    }
    out.sort((a: ShuYoVodPptSlide, b: ShuYoVodPptSlide): number => a.positionSec - b.positionSec);
    return out;
  }

  // ==================== Demo Mode Data ====================

  static loadDemoTerms(): ShuYoVodTerm[] {
    return [
      {
        id: 20261,
        name: '2026-2027学年第1学期',
        academicYear: '2026-2027',
        termNumber: 1,
        isCurrent: true,
        academicYearLabel: '26-27学年',
        seasonLabel: '秋季学期',
        startDateMs: 1756684800000,
        endDateMs: 1767139200000,
        teachingWeekCount: 16
      },
      {
        id: 20252,
        name: '2025-2026学年第2学期',
        academicYear: '2025-2026',
        termNumber: 2,
        isCurrent: false,
        academicYearLabel: '25-26学年',
        seasonLabel: '春季学期',
        startDateMs: 1740960000000,
        endDateMs: 1751241600000,
        teachingWeekCount: 16
      }
    ];
  }

  static loadDemoCatalog(termId: number): ShuYoVodCatalogData {
    const courses: ShuYoVodCourse[] = [
      {
        teachingClassId: 9001,
        termId: termId,
        name: '操作系统原理',
        teachingClassName: '操作系统原理(01班)',
        code: 'CS3021',
        teacherNames: ['陈老师'],
        teacherLabel: '陈老师',
        lessonCount: 12,
        coverUrl: '',
        isLive: true,
        liveLessonId: 900103
      },
      {
        teachingClassId: 9002,
        termId: termId,
        name: '计算机网络',
        teachingClassName: '计算机网络(02班)',
        code: 'CS3015',
        teacherNames: ['李老师', '王老师'],
        teacherLabel: '李老师、王老师',
        lessonCount: 16,
        coverUrl: '',
        isLive: false,
        liveLessonId: 0
      },
      {
        teachingClassId: 9003,
        termId: termId,
        name: '高等数学A(一)',
        teachingClassName: '高等数学A(一)(05班)',
        code: 'MATH1001',
        teacherNames: ['张老师'],
        teacherLabel: '张老师',
        lessonCount: 24,
        coverUrl: '',
        isLive: false,
        liveLessonId: 0
      }
    ];
    const liveLessons: ShuYoVodLesson[] = [
      {
        id: 900103,
        teachingClassId: 9001,
        name: '操作系统原理 第3讲：进程调度与实时系统',
        courseName: '操作系统原理',
        courseCode: 'CS3021',
        teacherLabel: '陈老师',
        beginTimeMs: 1758502800000,
        endTimeMs: 1758508200000,
        dateLabel: '今日',
        timeRangeLabel: '10:00-11:40',
        weekNumber: 3,
        weekday: 2,
        sectionNumber: 3,
        sectionLabel: '第3节',
        classroom: '宝山 D205',
        watchPercent: '直播中',
        isPlayable: true,
        isLive: true,
        isLiveAvailable: true,
        isGenerating: false,
        isListed: true,
        statusLabel: '正在直播'
      }
    ];
    return {
      courses: courses,
      liveLessons: liveLessons
    };
  }

  static loadDemoLessons(
    teachingClassId: number,
    courseName: string,
    courseCode: string,
    teacherLabel: string
  ): ShuYoVodLesson[] {
    const name = courseName.length > 0 ? courseName : '操作系统原理';
    const code = courseCode.length > 0 ? courseCode : 'CS3021';
    const teacher = teacherLabel.length > 0 ? teacherLabel : '陈老师';
    const baseId = teachingClassId * 100;
    return [
      {
        id: baseId + 1,
        teachingClassId: teachingClassId,
        name: `${name} 第1讲：课程导论与体系结构`,
        courseName: name,
        courseCode: code,
        teacherLabel: teacher,
        beginTimeMs: 1757293200000,
        endTimeMs: 1757298600000,
        dateLabel: '09-08',
        timeRangeLabel: '08:00-09:40',
        weekNumber: 1,
        weekday: 1,
        sectionNumber: 1,
        sectionLabel: '第1节',
        classroom: '宝山 D205',
        watchPercent: '100%',
        isPlayable: true,
        isLive: false,
        isLiveAvailable: false,
        isGenerating: false,
        isListed: true,
        statusLabel: '录播回放'
      },
      {
        id: baseId + 2,
        teachingClassId: teachingClassId,
        name: `${name} 第2讲：内核态与系统调用机制`,
        courseName: name,
        courseCode: code,
        teacherLabel: teacher,
        beginTimeMs: 1757898000000,
        endTimeMs: 1757903400000,
        dateLabel: '09-15',
        timeRangeLabel: '08:00-09:40',
        weekNumber: 2,
        weekday: 1,
        sectionNumber: 1,
        sectionLabel: '第1节',
        classroom: '宝山 D205',
        watchPercent: '65%',
        isPlayable: true,
        isLive: false,
        isLiveAvailable: false,
        isGenerating: false,
        isListed: true,
        statusLabel: '录播回放'
      },
      {
        id: baseId + 3,
        teachingClassId: teachingClassId,
        name: `${name} 第3讲：进程调度与上下文切换`,
        courseName: name,
        courseCode: code,
        teacherLabel: teacher,
        beginTimeMs: 1758502800000,
        endTimeMs: 1758508200000,
        dateLabel: '09-22',
        timeRangeLabel: '10:00-11:40',
        weekNumber: 3,
        weekday: 2,
        sectionNumber: 3,
        sectionLabel: '第3节',
        classroom: '宝山 D205',
        watchPercent: '20%',
        isPlayable: true,
        isLive: teachingClassId === 9001,
        isLiveAvailable: teachingClassId === 9001,
        isGenerating: false,
        isListed: true,
        statusLabel: teachingClassId === 9001 ? '正在直播' : '录播回放'
      },
      {
        id: baseId + 4,
        teachingClassId: teachingClassId,
        name: `${name} 第4讲：虚拟内存与页表管理`,
        courseName: name,
        courseCode: code,
        teacherLabel: teacher,
        beginTimeMs: 1759107600000,
        endTimeMs: 1759113000000,
        dateLabel: '09-29',
        timeRangeLabel: '13:00-14:40',
        weekNumber: 4,
        weekday: 4,
        sectionNumber: 5,
        sectionLabel: '第5节',
        classroom: '宝山 BJ203',
        watchPercent: '',
        isPlayable: false,
        isLive: false,
        isLiveAvailable: false,
        isGenerating: true,
        isListed: true,
        statusLabel: '回放生成中'
      }
    ];
  }

  static loadDemoPlayback(
    teachingClassId: number,
    lessonId: number,
    title: string,
    isLive: boolean
  ): ShuYoVodPlayback {
    return {
      lessonId: lessonId,
      teachingClassId: teachingClassId,
      title: title,
      views: [
        {
          viewNumber: 1,
          label: '教师视角 1',
          url: 'https://vrmvod.cc.shu.edu.cn:40443/demo/teacher_view_1.mp4'
        },
        {
          viewNumber: 5,
          label: 'PPT 画面',
          url: 'https://vrmvod.cc.shu.edu.cn:40443/demo/ppt_view.mp4'
        },
        {
          viewNumber: 6,
          label: '电子白板',
          url: 'https://vrmvod.cc.shu.edu.cn:40443/demo/board_view.mp4'
        },
        {
          viewNumber: 7,
          label: '合成画面',
          url: 'https://vrmvod.cc.shu.edu.cn:40443/demo/composite_view.mp4'
        }
      ],
      lastPositionSec: 120,
      isLive: isLive,
      description: '支持教师机位、PPT 课件、电子白板与合成画面多路切换及双画面同屏对比播放。'
    };
  }

  static loadDemoPptSlides(lessonId: number): ShuYoVodPptSlide[] {
    return [
      {
        id: `demo-ppt-${lessonId}-1`,
        imageUrl: '',
        positionSec: 45,
        timeLabel: '00:45',
        text: '第一章 课程导论与操作系统核心抽象：进程（Process）、虚拟地址空间（Virtual Address Space）、文件系统（File System）。'
      },
      {
        id: `demo-ppt-${lessonId}-2`,
        imageUrl: '',
        positionSec: 420,
        timeLabel: '07:00',
        text: '内核态（Kernel Mode）与用户态（User Mode）切换流程：Trap 指令 -> 保存寄存器上下文 -> 查系统调用表 -> 执行内核例程。'
      },
      {
        id: `demo-ppt-${lessonId}-3`,
        imageUrl: '',
        positionSec: 1080,
        timeLabel: '18:00',
        text: '调度算法对比：CFS 完全公平调度器、虚拟运行时间 vruntime 计算与红黑树队列组织。'
      },
      {
        id: `demo-ppt-${lessonId}-4`,
        imageUrl: '',
        positionSec: 2150,
        timeLabel: '35:50',
        text: '课后思考题与实验安排：阅读 xv6 第 2 章源码，完成 sys_trace 系统调用扩展实验。'
      }
    ];
  }

  private static pad2(val: number): string {
    return val < 10 ? `0${val}` : `${val}`;
  }
}
