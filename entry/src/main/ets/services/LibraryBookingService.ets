import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ShuYoConstants } from '../core/ShuYoConstants';
import {
  ShuYoLibraryArea,
  ShuYoLibraryBookingRecord,
  ShuYoLibrarySeat,
  ShuYoLibraryVenue
} from '../models/ShuYoModels';
import { AuthService } from './AuthService';
import { ChaoxingBookingService } from './ChaoxingBookingService';
import { HttpClientService, ShuYoCookieJar, ShuYoHttpResult } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';
import { LibraryBookingProtocol } from './LibraryBookingProtocol';
import { LibraryFloorPlanLayout } from './LibraryFloorPlanLayout';
import { RawFileService } from './RawFileService';
import { ShuYoWebVpnFailure, WebVpnAuthService } from './WebVpnAuthService';
import { WebVpnProtocol } from './WebVpnProtocol';

interface ShuYoVenueMeta {
  roomType: string;
  mobilePath: string;
  isThere: boolean;
  isChaoxing: boolean;
}

export interface ShuYoLibrarySlotQueryResult {
  areas: ShuYoLibraryArea[];
  activeArea: ShuYoLibraryArea | undefined;
  isLive: boolean;
  statusText: string;
  failure?: ShuYoThereFailure;
}

/** Failure taxonomy mirrored from the Flutter client's ThereFailureKind. */
export enum ShuYoThereFailure {
  NONE = 'none',
  LOGIN_REQUIRED = 'loginRequired',
  WEBVPN_EXPIRED = 'webVpnLoginRequired',
  UNREACHABLE = 'unreachable',
  UNCERTAIN = 'uncertain'
}

interface ShuYoThereSession {
  sessionId: string;
  failure: ShuYoThereFailure;
  message: string;
}

export interface ShuYoLibraryBookResult {
  ok: boolean;
  message: string;
  record?: ShuYoLibraryBookingRecord;
}

interface ShuYoAreaSeatBuildSpec {
  prefix: string;
  count: number;
  digits: number;
}

export class LibraryBookingService {
  static readonly venues: ShuYoLibraryVenue[] = [
    { id: 'studySpace', name: '宝山24H学习空间', campusName: '宝山校区', areaNames: ['A区', 'B区', 'C区'] },
    { id: 'library', name: '宝山校本部图书馆', campusName: '宝山校区', areaNames: ['二楼东侧', '二楼西侧', '三楼阅览室'] },
    { id: 'qianweichang', name: '钱伟长图书馆', campusName: '宝山校区', areaNames: ['四楼外圈', '四楼内圈'] },
    { id: 'scienceArt', name: '科艺中心共享空间', campusName: '宝山校区', areaNames: ['创作中心A', '创作中心B'] },
    { id: 'yanchang', name: '延长智能中心', campusName: '延长校区', areaNames: ['B区', 'C区'] },
    { id: 'wenhui', name: '延长文荟馆', campusName: '延长校区', areaNames: ['一楼自修区', '二楼自修区'] },
    { id: 'jiading', name: '嘉定联合馆', campusName: '嘉定校区', areaNames: ['一楼自修室', '二楼自修区'] }
  ];

  static readonly timeOptions: string[] = [
    '08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
    '12:00', '12:30', '13:00', '13:30', '14:00', '14:30', '15:00', '15:30',
    '16:00', '16:30', '17:00', '17:30', '18:00', '18:30', '19:00', '19:30',
    '20:00', '20:30', '21:00', '21:30', '22:00'
  ];

  private static readonly venueMetaMap: Map<string, ShuYoVenueMeta> = LibraryBookingService.buildVenueMetaMap();
  private static readonly thereSubmitIntervalMs: number = 10000;
  private static thereSessionIds: Map<string, string> = new Map<string, string>();
  private static liveRawRooms: Map<string, Record<string, Object>> = new Map<string, Record<string, Object>>();
  private static isThereSubmitting: boolean = false;
  private static lastThereSubmitAt: number = 0;

  static clearSession(): void {
    LibraryBookingService.thereSessionIds.clear();
    LibraryBookingService.liveRawRooms.clear();
    ShuYoCookieJar.clearDomain(ShuYoConstants.thereHost);
    ShuYoCookieJar.clearDomain('https-there-shu-edu-cn-443.webvpn.shu.edu.cn');
    ShuYoCookieJar.clearDomain('http-there-shu-edu-cn-80.webvpn.shu.edu.cn');
  }

  private static buildVenueMetaMap(): Map<string, ShuYoVenueMeta> {
    const m = new Map<string, ShuYoVenueMeta>();
    m.set('library', { roomType: 'LIB_SEAT', mobilePath: '/mobile/libseat', isThere: true, isChaoxing: false });
    m.set('studySpace', { roomType: 'STATION', mobilePath: '/mobile/seat2021', isThere: true, isChaoxing: false });
    m.set('yanchang', { roomType: 'SEAT', mobilePath: '/mobile/seat-mgr', isThere: true, isChaoxing: false });
    m.set('scienceArt', { roomType: 'CS_SEAT', mobilePath: '/mobile/csseat', isThere: true, isChaoxing: false });
    m.set('qianweichang', { roomType: 'CX_QWC', mobilePath: '', isThere: false, isChaoxing: true });
    m.set('wenhui', { roomType: 'CX_WH', mobilePath: '', isThere: false, isChaoxing: true });
    m.set('jiading', { roomType: 'CX_JD', mobilePath: '', isThere: false, isChaoxing: true });
    return m;
  }

  static getRulesMarkdown(): string {
    return RawFileService.readText('library_booking/rules.md');
  }

  static getQaMarkdown(): string {
    return RawFileService.readText('library_booking/QA.md');
  }

  static todayDateStr(): string {
    return LibraryBookingService.formatDateWithOffset(0);
  }

  static tomorrowDateStr(): string {
    return LibraryBookingService.formatDateWithOffset(1);
  }

  private static formatDateWithOffset(offsetDays: number): string {
    const d = new Date();
    const utcMs = d.getTime() + d.getTimezoneOffset() * 60000;
    const shanghai = new Date(utcMs + 8 * 3600000 + offsetDays * 86400000);
    const y = shanghai.getFullYear();
    const m = shanghai.getMonth() + 1;
    const day = shanghai.getDate();
    return `${y}-${m < 10 ? '0' + m : m}-${day < 10 ? '0' + day : day}`;
  }

  static isValidTimeSlot(startTime: string, endTime: string): boolean {
    return endTime > startTime && startTime.length === 5 && endTime.length === 5;
  }

  static hasTimeOverlap(beginA: string, endA: string, beginB: string, endB: string): boolean {
    return beginA < endB && endA > beginB;
  }

  private static getAreaSeatSpec(venueId: string, areaIdx: number): ShuYoAreaSeatBuildSpec {
    if (venueId === 'studySpace') {
      if (areaIdx === 0) {
        return { prefix: 'A', count: 18, digits: 3 };
      }
      if (areaIdx === 1) {
        return { prefix: 'B', count: 171, digits: 3 };
      }
      return { prefix: 'C', count: 109, digits: 3 };
    }
    return { prefix: '', count: 40, digits: 3 };
  }

  private static formatSeatCode(prefix: string, num: number, digits: number): string {
    let nStr = `${num}`;
    while (nStr.length < digits) {
      nStr = `0${nStr}`;
    }
    return `${prefix}${nStr}`;
  }

  private static hashString(input: string): number {
    let h = 2166136261;
    for (let i = 0; i < input.length; i++) {
      h ^= input.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return h >>> 0;
  }

  private static computeSimulatedOccupied(
    venueId: string,
    areaIdx: number,
    seatNum: number,
    day: string,
    startTime: string,
    endTime: string
  ): boolean {
    const startHour = parseInt(startTime.substring(0, 2), 10);
    const peakPercent = (!Number.isNaN(startHour) && startHour >= 13 && startHour <= 17)
      ? 55
      : ((!Number.isNaN(startHour) && startHour >= 9 && startHour <= 12) ? 42 : 28);
    const key = `${venueId}|${areaIdx}|${seatNum}|${day}|${startTime}-${endTime}`;
    const bucket = LibraryBookingService.hashString(key) % 100;
    return bucket < peakPercent;
  }

  static buildAreasForVenue(
    venue: ShuYoLibraryVenue,
    bookings: ShuYoLibraryBookingRecord[]
  ): ShuYoLibraryArea[] {
    return LibraryBookingService.buildAreasForSlot(
      venue,
      LibraryBookingService.todayDateStr(),
      '09:00',
      '12:00',
      bookings
    );
  }

  static buildAreasForSlot(
    venue: ShuYoLibraryVenue,
    day: string,
    startTime: string,
    endTime: string,
    bookings: ShuYoLibraryBookingRecord[]
  ): ShuYoLibraryArea[] {
    const slotBegin = `${day} ${startTime}`;
    const slotEnd = `${day} ${endTime}`;
    const areas: ShuYoLibraryArea[] = [];

    for (let i = 0; i < venue.areaNames.length; i++) {
      const areaId = `${venue.id}-${i}`;
      const spec = LibraryBookingService.getAreaSeatSpec(venue.id, i);
      const seats: ShuYoLibrarySeat[] = [];
      let freeCount = 0;

      for (let s = 1; s <= spec.count; s++) {
        const label = LibraryBookingService.formatSeatCode(spec.prefix, s, spec.digits);
        const seatId = `${areaId}-${label}`;
        const isDisabled = venue.id === 'studySpace'
          ? (s % 47 === 0)
          : (s === 5 || s === 24);

        let isBooked = false;
        for (let b = 0; b < bookings.length; b++) {
          const rec = bookings[b];
          if (rec.status !== 'BOOKING') {
            continue;
          }
          const matchesSeat = rec.seatId === seatId ||
            (rec.areaId === areaId && rec.seatLabel === label);
          if (matchesSeat &&
            rec.day === day &&
            LibraryBookingService.hasTimeOverlap(rec.beginTime, rec.endTime, slotBegin, slotEnd)) {
            isBooked = true;
            break;
          }
        }

        const isBusy = isDisabled
          ? true
          : LibraryBookingService.computeSimulatedOccupied(venue.id, i, s, day, startTime, endTime);

        if (!isDisabled && !isBusy && !isBooked) {
          freeCount++;
        }

        seats.push({
          id: seatId,
          seatLabel: label,
          areaId: areaId,
          isBusy: isBusy,
          isDisabled: isDisabled,
          isBooked: isBooked
        });
      }

      areas.push({
        id: areaId,
        name: venue.areaNames[i],
        totalCount: seats.length,
        freeCount: freeCount,
        seats: seats
      });
    }
    return areas;
  }

  private static mergeStudySpaceOverviewArea(zoneAreas: ShuYoLibraryArea[]): ShuYoLibraryArea {
    const mergedSeats: ShuYoLibrarySeat[] = [];
    let totalFree = 0;
    for (let i = 0; i < zoneAreas.length; i++) {
      const area = zoneAreas[i];
      for (let s = 0; s < area.seats.length; s++) {
        const seat = area.seats[s];
        const parsed = LibraryFloorPlanLayout.normalizeSeatCode(seat.seatLabel, area.name);
        const normalizedLabel = parsed !== undefined
          ? LibraryFloorPlanLayout.formatNormalizedCode(parsed.prefix, parsed.num)
          : seat.seatLabel;
        if (!seat.isDisabled && !seat.isBusy && !seat.isBooked) {
          totalFree++;
        }
        mergedSeats.push({
          id: seat.id,
          seatLabel: normalizedLabel,
          areaId: seat.areaId,
          isBusy: seat.isBusy,
          isDisabled: seat.isDisabled,
          isBooked: seat.isBooked
        });
      }
    }
    return {
      id: 'studySpace-all',
      name: '全馆总览 (A+B+C)',
      totalCount: mergedSeats.length,
      freeCount: totalFree,
      seats: mergedSeats
    };
  }

  private static thereBase(useWebVpn: boolean): string {
    return useWebVpn ? ShuYoConstants.thereWebVpnBaseUrl : ShuYoConstants.thereBaseUrl;
  }

  private static normalizeThereRedirect(baseUrl: string, location: string): string {
    return LibraryBookingProtocol.normalizeThereRedirect(baseUrl, location);
  }

  private static extractSessionIdFromHtml(html: string): string | undefined {
    return LibraryBookingProtocol.extractThereSessionId(html);
  }

  private static async completeThereSsoOAuth(
    baseUrl: string,
    useWebVpn: boolean
  ): Promise<ShuYoThereSession> {
    const unreachableFail: ShuYoThereSession = {
      sessionId: '',
      failure: ShuYoThereFailure.UNREACHABLE,
      message: '暂时无法连接预约系统 · 校外请开启 WebVPN 或连接校园网'
    };
    const webVpnExpired: ShuYoThereSession = {
      sessionId: '',
      failure: ShuYoThereFailure.WEBVPN_EXPIRED,
      message: 'WebVPN 会话已失效 · 请关闭 WebVPN 直连校园网，或重新登录 WebVPN'
    };
    if (!ShuYoCookieJar.hasCookie(ShuYoConstants.ssoBaseUrl, 'SHU_OAUTH2')) {
      return {
        sessionId: '',
        failure: ShuYoThereFailure.LOGIN_REQUIRED,
        message: '图书馆预约需要登录统一身份认证 · 请先在首页完成登录'
      };
    }

    try {
      const loginUrl = `${baseUrl}/login?from=web`;
      const loginResp = await HttpClientService.request(
        http.RequestMethod.GET,
        loginUrl,
        LibraryBookingService.withGatewayCookie(loginUrl, { 'Accept': 'application/json,text/html,*/*' }),
        undefined,
        12000
      );
      const loginLoc = LibraryBookingService.resolveThereLocation(loginUrl, loginResp.location);
      LibraryBookingService.logThere(
        'oauth/login',
        `status=${loginResp.statusCode} hasLoc=${loginLoc.length > 0}`
      );
      if (useWebVpn && LibraryBookingService.isWebVpnPortalRedirect(loginLoc)) {
        return webVpnExpired;
      }
      if (loginResp.statusCode < 300 || loginResp.statusCode >= 400 || loginLoc.length === 0) {
        return {
          sessionId: '',
          failure: loginResp.statusCode === 0 ? ShuYoThereFailure.UNREACHABLE : ShuYoThereFailure.UNCERTAIN,
          message: loginResp.statusCode === 0
            ? unreachableFail.message
            : '图书馆预约暂时无法启动登录，请稍后重试'
        };
      }
      const state = AuthService.extractQueryParam(loginLoc, 'state').trim();
      if (state.length === 0) {
        return {
          sessionId: '',
          failure: ShuYoThereFailure.UNCERTAIN,
          message: '图书馆预约未返回授权参数 · 请稍后重试'
        };
      }

      const loginLocPath = WebVpnProtocol.extractPath(loginLoc);
      const authUrl = loginLocPath.includes('/oauth/authorize')
        ? WebVpnProtocol.canonicalSsoUrl(loginLoc)
        : (
          `${ShuYoConstants.ssoBaseUrl}/oauth/authorize?response_type=code` +
          `&client_id=${encodeURIComponent(ShuYoConstants.targetThere.clientId)}` +
          `&redirect_uri=${encodeURIComponent(ShuYoConstants.targetThere.redirectUri)}` +
          `&scope=${encodeURIComponent(ShuYoConstants.targetThere.scope)}` +
          `&state=${encodeURIComponent(state)}`
        );
      const ssoResp = await HttpClientService.request(
        http.RequestMethod.GET,
        authUrl,
        { 'Accept': 'text/html,application/xhtml+xml,*/*' },
        undefined,
        12000
      );
      const ssoLoc = LibraryBookingService.resolveThereLocation(authUrl, ssoResp.location);
      LibraryBookingService.logThere(
        'oauth/sso',
        `status=${ssoResp.statusCode} hasLoc=${ssoLoc.length > 0}`
      );
      if (ssoLoc.includes('/oauth2/login/')) {
        return {
          sessionId: '',
          failure: ShuYoThereFailure.LOGIN_REQUIRED,
          message: '统一身份认证已失效 · 请在「设置」退出后重新登录校园账号'
        };
      }
      if (ssoResp.statusCode < 300 || ssoResp.statusCode >= 400 || ssoLoc.length === 0) {
        return {
          sessionId: '',
          failure: ssoResp.statusCode === 0 ? ShuYoThereFailure.UNREACHABLE : ShuYoThereFailure.UNCERTAIN,
          message: '统一身份认证未返回预约授权回调 · 请稍后重试'
        };
      }
      const callbackUrl = LibraryBookingService.normalizeThereRedirect(baseUrl, ssoLoc);
      const returnedState = AuthService.extractQueryParam(callbackUrl, 'state');
      if (HttpClientService.extractPath(callbackUrl) !== '/login-oauth2' ||
        AuthService.extractQueryParam(callbackUrl, 'code').length === 0 ||
        returnedState !== state) {
        return {
          sessionId: '',
          failure: ShuYoThereFailure.UNCERTAIN,
          message: '图书馆预约授权回调无效或状态不匹配 · 请重试'
        };
      }

      const cbResp = await HttpClientService.request(
        http.RequestMethod.GET,
        callbackUrl,
        LibraryBookingService.withGatewayCookie(callbackUrl, { 'Accept': 'text/html,application/xhtml+xml,*/*' }),
        undefined,
        12000
      );
      const cbLoc = LibraryBookingService.resolveThereLocation(callbackUrl, cbResp.location);
      LibraryBookingService.logThere(
        'oauth/callback',
        `status=${cbResp.statusCode} hasLoc=${cbLoc.length > 0}`
      );
      if (useWebVpn && LibraryBookingService.isWebVpnPortalRedirect(cbLoc)) {
        return webVpnExpired;
      }
      if (cbResp.statusCode < 300 || cbResp.statusCode >= 400 || cbLoc.length === 0) {
        return {
          sessionId: '',
          failure: ShuYoThereFailure.UNCERTAIN,
          message: '图书馆预约未能建立业务会话 · 请重试'
        };
      }

      let nextUrl = LibraryBookingService.normalizeThereRedirect(baseUrl, cbLoc);
      if (HttpClientService.extractPath(nextUrl) !== '/web') {
        return {
          sessionId: '',
          failure: ShuYoThereFailure.UNCERTAIN,
          message: '图书馆预约授权跳转路径异常 · 请重试'
        };
      }

      for (let hop = 0; hop < 4; hop++) {
        const pageResp = await HttpClientService.request(
          http.RequestMethod.GET,
          nextUrl,
          LibraryBookingService.withGatewayCookie(nextUrl, { 'Accept': 'text/html,application/xhtml+xml,*/*' }),
          undefined,
          12000
        );
        const hopLoc = LibraryBookingService.resolveThereLocation(nextUrl, pageResp.location);
        LibraryBookingService.logThere(
          'oauth/web',
          `hop=${hop} status=${pageResp.statusCode} hasLoc=${hopLoc.length > 0}`
        );
        if (useWebVpn && LibraryBookingService.isWebVpnPortalRedirect(hopLoc)) {
          return webVpnExpired;
        }
        if (pageResp.statusCode === 200) {
          return { sessionId: '', failure: ShuYoThereFailure.NONE, message: '' };
        }
        if (pageResp.statusCode >= 300 && pageResp.statusCode < 400 && hopLoc.length > 0) {
          const normalizedHop = LibraryBookingService.normalizeThereRedirect(baseUrl, hopLoc);
          const hopPath = HttpClientService.extractPath(normalizedHop);
          if (hopPath.startsWith('/login')) {
            return {
              sessionId: '',
              failure: ShuYoThereFailure.UNCERTAIN,
              message: '图书馆预约会话兑换失败 · 请重试'
            };
          }
          nextUrl = normalizedHop;
        } else {
          break;
        }
      }
      return {
        sessionId: '',
        failure: ShuYoThereFailure.UNCERTAIN,
        message: '图书馆预约登录跳转次数过多 · 请稍后重试'
      };
    } catch (_err) {
      return unreachableFail;
    }
  }

  private static logThere(stage: string, detail: string): void {
    hilog.info(0x5348, 'ShuYoThere', '%{public}s | %{public}s', stage, detail);
  }

  private static resolveThereLocation(baseUrl: string, rawLocation: string): string {
    if (rawLocation.length === 0) {
      return '';
    }
    return HttpClientService.resolveUrl(baseUrl, rawLocation);
  }

  /**
   * The mobile entry is a WeCom H5 page. Sending its WebView marker from a plain
   * app request can route the server into a WeChat OAuth branch, so the entry is
   * probed once with the marker and once without it.
   */
  private static isWeChatRedirect(statusCode: number, location: string): boolean {
    return LibraryBookingProtocol.isWeChatRedirect(statusCode, location);
  }

  private static isWebVpnPortalRedirect(location: string): boolean {
    return WebVpnProtocol.isWebVpnPortalHost(WebVpnProtocol.extractHost(location));
  }

  private static isThereLoginRedirect(baseUrl: string, statusCode: number, location: string): boolean {
    if (statusCode === 401) {
      return true;
    }
    if (statusCode < 300 || statusCode >= 400 || location.length === 0) {
      return false;
    }
    const host = HttpClientService.extractHost(location).toLowerCase();
    const baseHost = HttpClientService.extractHost(baseUrl).toLowerCase();
    const path = HttpClientService.extractPath(location);
    if (host === baseHost && (path === '/login' || path === '/login-oauth2')) {
      return true;
    }
    return host.endsWith('.shu.edu.cn') &&
      (path.startsWith('/oauth/') || path.startsWith('/oauth2/') || path === '/login');
  }

  /**
   * The WebVPN gateway authenticates with the portal's `webvpn-token` cookie, which
   * is scoped to webvpn.shu.edu.cn and therefore never sent to the proxied host.
   */
  private static withGatewayCookie(requestUrl: string, headers: Record<string, string>): Record<string, string> {
    const host = HttpClientService.extractHost(requestUrl).toLowerCase();
    if (!host.endsWith('.webvpn.shu.edu.cn')) {
      return headers;
    }
    if (ShuYoCookieJar.getCookieValue(requestUrl, 'webvpn-token').length > 0) {
      return headers;
    }
    const portalToken = ShuYoCookieJar.getCookieValue(ShuYoConstants.webVpnPortal, 'webvpn-token');
    if (portalToken.length === 0) {
      return headers;
    }
    const jarCookie = ShuYoCookieJar.headerFor(requestUrl);
    headers['Cookie'] = jarCookie.length > 0
      ? `webvpn-token=${portalToken}; ${jarCookie}`
      : `webvpn-token=${portalToken}`;
    return headers;
  }

  private static async probeThereEntry(
    venueId: string,
    useWebVpn: boolean,
    withWeComHeader: boolean
  ): Promise<ShuYoHttpResult> {
    const meta = LibraryBookingService.venueMetaMap.get(venueId);
    const baseUrl = LibraryBookingService.thereBase(useWebVpn);
    const entryUrl = meta !== undefined ? `${baseUrl}${meta.mobilePath}` : baseUrl;
    const headers: Record<string, string> = {
      'Accept': 'application/json,text/html,*/*'
    };
    if (withWeComHeader) {
      headers['X-Requested-With'] = 'com.tencent.wework';
    }
    return HttpClientService.request(
      http.RequestMethod.GET,
      entryUrl,
      LibraryBookingService.withGatewayCookie(entryUrl, headers),
      undefined,
      12000
    );
  }

  private static async verifyThereProfile(
    venueId: string,
    sessionId: string,
    useWebVpn: boolean
  ): Promise<ShuYoThereFailure> {
    const profileJson = await LibraryBookingService.thereApiGet(
      venueId,
      sessionId,
      useWebVpn,
      '/api/v3/my/profile'
    );
    if (profileJson === undefined) {
      return ShuYoThereFailure.UNCERTAIN;
    }
    const profileData = JsonHelpers.asObject(profileJson['data']);
    if (profileData === undefined || JsonHelpers.str(profileData, 'id', '').trim().length === 0) {
      return ShuYoThereFailure.LOGIN_REQUIRED;
    }
    if (JsonHelpers.bool(profileData, 'isAnonymous', false)) {
      return ShuYoThereFailure.LOGIN_REQUIRED;
    }
    return ShuYoThereFailure.NONE;
  }

  private static async ensureThereSession(venueId: string, useWebVpn: boolean): Promise<ShuYoThereSession> {
    const meta = LibraryBookingService.venueMetaMap.get(venueId);
    if (meta === undefined || !meta.isThere) {
      return { sessionId: '', failure: ShuYoThereFailure.UNCERTAIN, message: '该场馆暂不支持实时空位查询' };
    }
    const cacheKey = `${venueId}|${useWebVpn ? 'vpn' : 'dir'}`;
    const existing = LibraryBookingService.thereSessionIds.get(cacheKey);
    if (existing !== undefined) {
      return { sessionId: existing, failure: ShuYoThereFailure.NONE, message: '' };
    }

    const baseUrl = LibraryBookingService.thereBase(useWebVpn);
    const entryUrl = `${baseUrl}${meta.mobilePath}`;
    const webVpnExpired: ShuYoThereSession = {
      sessionId: '',
      failure: ShuYoThereFailure.WEBVPN_EXPIRED,
      message: 'WebVPN 会话已失效 · 请关闭 WebVPN 直连校园网，或重新登录 WebVPN'
    };

    if (useWebVpn) {
      const vpn = await WebVpnAuthService.ensureSession();
      if (vpn.failure !== ShuYoWebVpnFailure.NONE) {
        LibraryBookingService.logThere(
          'webvpn/failed',
          `room=${meta.roomType} kind=${vpn.failure}`
        );
        if (vpn.failure === ShuYoWebVpnFailure.LOGIN_REQUIRED) {
          return {
            sessionId: '',
            failure: ShuYoThereFailure.WEBVPN_EXPIRED,
            message: `${vpn.message} · 也可关闭 WebVPN 用校园网直连`
          };
        }
        return {
          sessionId: '',
          failure: vpn.failure === ShuYoWebVpnFailure.UNREACHABLE
            ? ShuYoThereFailure.UNREACHABLE
            : ShuYoThereFailure.UNCERTAIN,
          message: `${vpn.message} · 也可关闭 WebVPN 用校园网直连`
        };
      }
    }

    let resp: ShuYoHttpResult;
    try {
      resp = await LibraryBookingService.probeThereEntry(venueId, useWebVpn, true);
    } catch (_err) {
      LibraryBookingService.logThere('entry/unreachable', `room=${meta.roomType} transport=${useWebVpn ? 'webvpn' : 'direct'}`);
      return {
        sessionId: '',
        failure: ShuYoThereFailure.UNREACHABLE,
        message: '暂时无法连接预约系统 · 校外请点「开 WebVPN」或连接校园网'
      };
    }
    let location = LibraryBookingService.resolveThereLocation(entryUrl, resp.location);
    if (LibraryBookingService.isWeChatRedirect(resp.statusCode, location)) {
      LibraryBookingService.logThere(
        'entry/wecom-retry',
        `room=${meta.roomType} status=${resp.statusCode}`
      );
      try {
        resp = await LibraryBookingService.probeThereEntry(venueId, useWebVpn, false);
      } catch (_err) {
        return {
          sessionId: '',
          failure: ShuYoThereFailure.UNREACHABLE,
          message: '暂时无法连接预约系统 · 校外请点「开 WebVPN」或连接校园网'
        };
      }
      location = LibraryBookingService.resolveThereLocation(entryUrl, resp.location);
    }
    if (useWebVpn && LibraryBookingService.isWebVpnPortalRedirect(location)) {
      return webVpnExpired;
    }

    const initialWeChatRedirect = LibraryBookingService.isWeChatRedirect(resp.statusCode, location);
    const anonymous = LibraryBookingProtocol.isThereAnonymousHtml(resp.body);
    if (initialWeChatRedirect || anonymous || LibraryBookingService.isThereLoginRedirect(baseUrl, resp.statusCode, location)) {
      if (initialWeChatRedirect) {
        LibraryBookingService.logThere('entry/wechat-pre-oauth', `room=${meta.roomType}`);
      }
      const oauthRes = await LibraryBookingService.completeThereSsoOAuth(baseUrl, useWebVpn);
      if (oauthRes.failure !== ShuYoThereFailure.NONE) {
        return oauthRes;
      }
      try {
        resp = await LibraryBookingService.probeThereEntry(venueId, useWebVpn, true);
        location = LibraryBookingService.resolveThereLocation(entryUrl, resp.location);
        if (LibraryBookingService.isWeChatRedirect(resp.statusCode, location)) {
          resp = await LibraryBookingService.probeThereEntry(venueId, useWebVpn, false);
          location = LibraryBookingService.resolveThereLocation(entryUrl, resp.location);
        }
      } catch (_err) {
        return {
          sessionId: '',
          failure: ShuYoThereFailure.UNREACHABLE,
          message: '暂时无法连接预约系统 · 校外请点「开 WebVPN」或连接校园网'
        };
      }
      if (useWebVpn && LibraryBookingService.isWebVpnPortalRedirect(location)) {
        return webVpnExpired;
      }
      if (LibraryBookingService.isWeChatRedirect(resp.statusCode, location)) {
        LibraryBookingService.logThere('entry/wechat-after-oauth', `room=${meta.roomType} status=${resp.statusCode}`);
        return {
          sessionId: '',
          failure: ShuYoThereFailure.UNCERTAIN,
          message: '预约入口仍跳转至微信授权，当前客户端暂时无法完成该认证'
        };
      }
    }

    if (resp.statusCode !== 200) {
      LibraryBookingService.logThere(
        'entry/failed',
        `room=${meta.roomType} status=${resp.statusCode} transport=${useWebVpn ? 'webvpn' : 'direct'}`
      );
      return {
        sessionId: '',
        failure: resp.statusCode === 0 ? ShuYoThereFailure.UNREACHABLE : ShuYoThereFailure.UNCERTAIN,
        message: resp.statusCode === 0
          ? '暂时无法连接预约系统 · 请连接校园网或开启 WebVPN 后重试'
          : `预约入口返回 HTTP ${resp.statusCode} · 请检查校园网或 WebVPN 后重试`
      };
    }
    if (LibraryBookingProtocol.isThereAnonymousHtml(resp.body)) {
      return {
        sessionId: '',
        failure: ShuYoThereFailure.LOGIN_REQUIRED,
        message: '图书馆预约需要登录校园账号'
      };
    }
    const sessionId = LibraryBookingService.extractSessionIdFromHtml(resp.body);
    if (sessionId === undefined) {
      return {
        sessionId: '',
        failure: ShuYoThereFailure.UNCERTAIN,
        message: '预约页面未返回可识别的会话 · 请稍后重试'
      };
    }
    const verified = await LibraryBookingService.verifyThereProfile(venueId, sessionId, useWebVpn);
    if (verified !== ShuYoThereFailure.NONE) {
      LibraryBookingService.logThere(
        'entry/profile',
        `room=${meta.roomType} result=${verified}`
      );
      return {
        sessionId: '',
        failure: verified,
        message: verified === ShuYoThereFailure.LOGIN_REQUIRED
          ? '预约系统未确认登录状态 · 请重新登录校园账号'
          : '预约系统暂时无法确认会话 · 请稍后重试'
      };
    }
    LibraryBookingService.thereSessionIds.set(cacheKey, sessionId);
    LibraryBookingService.logThere(
      'entry/ok',
      `room=${meta.roomType} transport=${useWebVpn ? 'webvpn' : 'direct'} ` +
        `mode=${sessionId.length > 0 ? 'header' : 'cookie'}`
    );
    return { sessionId: sessionId, failure: ShuYoThereFailure.NONE, message: '' };
  }

  private static buildThereHeaders(
    venueId: string,
    sessionId: string,
    useWebVpn: boolean,
    method: http.RequestMethod
  ): Record<string, string> {
    const meta = LibraryBookingService.venueMetaMap.get(venueId)!;
    const baseUrl = LibraryBookingService.thereBase(useWebVpn);
    const headers: Record<string, string> = {
      'Accept': 'application/json,text/html,*/*',
      'Content-Type': 'application/json',
      'x-room-type': meta.roomType,
      'x-hys-platform': 'UNDEFINE',
      'x-lang': 'zh',
      'X-Requested-With': 'com.tencent.wework',
      'Referer': `${baseUrl}${meta.mobilePath}`
    };
    if (sessionId.length > 0) {
      headers['x-hys-session'] = sessionId;
    }
    if (method !== http.RequestMethod.GET) {
      headers['Origin'] = baseUrl;
    }
    return headers;
  }

  private static async thereApiGet(
    venueId: string,
    sessionId: string,
    useWebVpn: boolean,
    pathWithQuery: string
  ): Promise<Record<string, Object> | undefined> {
    const baseUrl = LibraryBookingService.thereBase(useWebVpn);
    const requestUrl = `${baseUrl}${pathWithQuery}`;
    const headers = LibraryBookingService.withGatewayCookie(
      requestUrl,
      LibraryBookingService.buildThereHeaders(venueId, sessionId, useWebVpn, http.RequestMethod.GET)
    );
    const resp = await HttpClientService.request(
      http.RequestMethod.GET,
      requestUrl,
      headers,
      undefined,
      12000
    );
    const route = pathWithQuery.split('?')[0];
    if (resp.statusCode === 401 || resp.statusCode === 403 || resp.statusCode === 302) {
      LibraryBookingService.thereSessionIds.delete(`${venueId}|${useWebVpn ? 'vpn' : 'dir'}`);
      LibraryBookingService.logThere('api/session-lost', `route=${route} status=${resp.statusCode}`);
      return undefined;
    }
    if (resp.statusCode !== 200) {
      LibraryBookingService.logThere('api/failed', `route=${route} status=${resp.statusCode}`);
      return undefined;
    }
    const obj = JsonHelpers.parseObject(resp.body);
    if (obj === undefined) {
      LibraryBookingService.logThere('api/unparsable', `route=${route} chars=${resp.body.length}`);
      return undefined;
    }
    const code = JsonHelpers.num(obj, 'code', -1);
    if (code !== 0) {
      const message = JsonHelpers.str(obj, 'warnMessage', JsonHelpers.str(obj, 'message', ''));
      LibraryBookingService.logThere('api/rejected', `route=${route} code=${code} msg=${message.length}`);
      return undefined;
    }
    return obj;
  }

  private static parseThereRooms(
    venueId: string,
    areaId: string,
    rawRooms: Object[],
    day: string,
    startTime: string,
    endTime: string,
    bookings: ShuYoLibraryBookingRecord[]
  ): ShuYoLibrarySeat[] {
    const slotBegin = `${day} ${startTime}`;
    const slotEnd = `${day} ${endTime}`;
    const out: ShuYoLibrarySeat[] = [];

    for (let i = 0; i < rawRooms.length; i++) {
      const rObj = JsonHelpers.asObject(rawRooms[i]);
      if (rObj === undefined) {
        continue;
      }
      const id = JsonHelpers.str(rObj, 'id', '').trim();
      const name = JsonHelpers.str(rObj, 'name', id).trim();
      if (id.length === 0 && name.length === 0) {
        continue;
      }
      const seatId = id.length > 0 ? id : name;
      const seatLabel = name.length > 0 ? name : id;
      LibraryBookingService.liveRawRooms.set(`${venueId}|${areaId}|${seatId}`, rObj);

      const isDisabled = JsonHelpers.bool(rObj, 'disabled', false);
      const isBusyRemote = JsonHelpers.bool(rObj, 'isBusy', false);
      let isBooked = JsonHelpers.bool(rObj, 'isBooked', false);
      if (!isBooked) {
        for (let b = 0; b < bookings.length; b++) {
          const rec = bookings[b];
          if (rec.status === 'BOOKING' &&
            rec.areaId === areaId &&
            (rec.seatId === seatId || rec.seatLabel === seatLabel) &&
            rec.day === day &&
            LibraryBookingService.hasTimeOverlap(rec.beginTime, rec.endTime, slotBegin, slotEnd)) {
            isBooked = true;
            break;
          }
        }
      }

      const abilities = JsonHelpers.strList(rObj, 'abilities');
      const canBook = abilities.length === 0 || abilities.includes('booking');
      const isBusy = isBusyRemote || (!isDisabled && !isBooked && !canBook);

      out.push({
        id: seatId,
        seatLabel: seatLabel,
        areaId: areaId,
        isBusy: isBusy,
        isDisabled: isDisabled,
        isBooked: isBooked
      });
    }

    return out;
  }

  private static async fetchThereSingleAreaSeats(
    venueId: string,
    sessionId: string,
    useWebVpn: boolean,
    targetArea: ShuYoLibraryArea,
    day: string,
    startTime: string,
    endTime: string,
    bookings: ShuYoLibraryBookingRecord[]
  ): Promise<ShuYoLibraryArea | undefined> {
    const beginParam = encodeURIComponent(`${day} ${startTime}`);
    const endParam = encodeURIComponent(`${day} ${endTime}`);
    const areaDetailJson = await LibraryBookingService.thereApiGet(
      venueId,
      sessionId,
      useWebVpn,
      `/api/v3/booking-status/areas/${encodeURIComponent(targetArea.id)}?begin=${beginParam}&end=${endParam}`
    );
    if (areaDetailJson === undefined) {
      return undefined;
    }
    const detailData = JsonHelpers.asObject(areaDetailJson['data']);
    const rawRooms = JsonHelpers.asArray(detailData !== undefined ? detailData['rooms'] : undefined);
    const parsedSeats = LibraryBookingService.parseThereRooms(
      venueId,
      targetArea.id,
      rawRooms,
      day,
      startTime,
      endTime,
      bookings
    );
    if (parsedSeats.length === 0) {
      return undefined;
    }

    let liveFree = 0;
    for (let i = 0; i < parsedSeats.length; i++) {
      const s = parsedSeats[i];
      if (!s.isDisabled && !s.isBusy && !s.isBooked) {
        liveFree++;
      }
    }

    return {
      id: targetArea.id,
      name: targetArea.name,
      totalCount: parsedSeats.length,
      freeCount: liveFree,
      seats: parsedSeats
    };
  }

  static async fetchAreasAndSeatsForSlot(
    venue: ShuYoLibraryVenue,
    selectedAreaIdx: number,
    day: string,
    startTime: string,
    endTime: string,
    bookings: ShuYoLibraryBookingRecord[],
    isDemoMode: boolean,
    useWebVpn: boolean
  ): Promise<ShuYoLibrarySlotQueryResult> {
    const isOverview = venue.id === 'studySpace' && selectedAreaIdx < 0;
    const fallbackAreas = LibraryBookingService.buildAreasForSlot(venue, day, startTime, endTime, bookings);
    const safeIdx = Math.max(0, Math.min(selectedAreaIdx, Math.max(0, fallbackAreas.length - 1)));
    const fallbackActive = isOverview
      ? LibraryBookingService.mergeStudySpaceOverviewArea(fallbackAreas)
      : (fallbackAreas.length > 0 ? fallbackAreas[safeIdx] : undefined);

    const meta = LibraryBookingService.venueMetaMap.get(venue.id);
    const defaultStatus = isDemoMode
      ? '演示模式 · 按所选时段模拟'
      : '未登录统一身份认证 · 显示模拟空位（登录后查询实时）';
    const fallbackResult: ShuYoLibrarySlotQueryResult = {
      areas: fallbackAreas,
      activeArea: fallbackActive,
      isLive: false,
      statusText: defaultStatus,
      failure: isDemoMode ? ShuYoThereFailure.NONE : ShuYoThereFailure.LOGIN_REQUIRED
    };

    if (isDemoMode || meta === undefined) {
      return fallbackResult;
    }
    if (!ShuYoCookieJar.hasCookie(ShuYoConstants.ssoBaseUrl, 'SHU_OAUTH2')) {
      return fallbackResult;
    }

    if (meta.isChaoxing) {
      if (day !== LibraryBookingService.todayDateStr()) {
        return {
          areas: fallbackAreas,
          activeArea: fallbackActive,
          isLive: false,
          statusText: `${venue.name}超星系统仅支持预约当天 · 当前展示模拟空位`
        };
      }
      try {
        const cxRes = await ChaoxingBookingService.fetchAreasAndSeats(
          venue,
          safeIdx,
          day,
          startTime,
          endTime,
          bookings
        );
        if (cxRes !== undefined) {
          return {
            areas: cxRes.areas,
            activeArea: cxRes.activeArea,
            isLive: true,
            statusText: cxRes.statusText
          };
        }
      } catch (_err) {
        return {
          areas: fallbackAreas,
          activeArea: fallbackActive,
          isLive: false,
          statusText: `${venue.name}超星系统查询异常 · 点击「刷新空位」重试`,
          failure: ShuYoThereFailure.UNCERTAIN
        };
      }
      return {
        areas: fallbackAreas,
        activeArea: fallbackActive,
        isLive: false,
        statusText: `${venue.name}超星系统未返回座位数据 · 请确认已登录校园账号`,
        failure: ShuYoThereFailure.LOGIN_REQUIRED
      };
    }

    if (!meta.isThere) {
      return fallbackResult;
    }

    try {
      const session = await LibraryBookingService.ensureThereSession(venue.id, useWebVpn);
      if (session.failure !== ShuYoThereFailure.NONE) {
        return {
          areas: fallbackAreas,
          activeArea: fallbackActive,
          isLive: false,
          statusText: session.message,
          failure: session.failure
        };
      }
      const sessionId = session.sessionId;
      const areasJson = await LibraryBookingService.thereApiGet(
        venue.id,
        sessionId,
        useWebVpn,
        `/api/v3/booking-status/areas?begin=${encodeURIComponent(day)}&end=${encodeURIComponent(day)}`
      );
      if (areasJson === undefined) {
        return {
          areas: fallbackAreas,
          activeArea: fallbackActive,
          isLive: false,
          statusText: '实时空位查询失败 · 点击「刷新空位」重试',
          failure: ShuYoThereFailure.UNCERTAIN
        };
      }
      const rawAreaList = JsonHelpers.asArray(areasJson['data']);
      if (rawAreaList.length === 0) {
        return {
          areas: fallbackAreas,
          activeArea: fallbackActive,
          isLive: false,
          statusText: `${venue.name}该时段暂无可预约分区`,
          failure: ShuYoThereFailure.NONE
        };
      }

      const liveAreas: ShuYoLibraryArea[] = [];
      for (let i = 0; i < rawAreaList.length; i++) {
        const aObj = JsonHelpers.asObject(rawAreaList[i]);
        if (aObj === undefined) {
          continue;
        }
        const aId = JsonHelpers.str(aObj, 'id', '').trim();
        const aName = JsonHelpers.str(aObj, 'name', '').trim();
        if (aId.length === 0 || aName.length === 0) {
          continue;
        }
        const totalCnt = JsonHelpers.num(aObj, 'totalResourceCount', 0);
        const freeCnt = JsonHelpers.num(aObj, 'freeResourceCount', totalCnt);
        liveAreas.push({
          id: aId,
          name: aName,
          totalCount: totalCnt,
          freeCount: freeCnt,
          seats: []
        });
      }

      if (liveAreas.length === 0) {
        return {
          areas: fallbackAreas,
          activeArea: fallbackActive,
          isLive: false,
          statusText: `${venue.name}实时分区数据为空 · 点击「刷新空位」重试`,
          failure: ShuYoThereFailure.UNCERTAIN
        };
      }

      if (isOverview) {
        const hydratedZones = await Promise.all(
          liveAreas.map((areaItem: ShuYoLibraryArea): Promise<ShuYoLibraryArea | undefined> =>
            LibraryBookingService.fetchThereSingleAreaSeats(
              venue.id,
              sessionId,
              useWebVpn,
              areaItem,
              day,
              startTime,
              endTime,
              bookings
            )
          )
        );
        const validZones: ShuYoLibraryArea[] = [];
        for (let i = 0; i < liveAreas.length; i++) {
          const hz = hydratedZones[i];
          if (hz !== undefined) {
            liveAreas[i] = hz;
            validZones.push(hz);
          }
        }
        if (validZones.length === 0) {
          return {
            areas: fallbackAreas,
            activeArea: fallbackActive,
            isLive: false,
            statusText: '实时座位数据为空 · 点击「刷新空位」重试',
            failure: ShuYoThereFailure.UNCERTAIN
          };
        }
        const overviewArea = LibraryBookingService.mergeStudySpaceOverviewArea(validZones);
        return {
          areas: liveAreas,
          activeArea: overviewArea,
          isLive: true,
          statusText: `实时空位 · 全馆总览（${startTime}-${endTime}）`
        };
      }

      const targetIdx = Math.max(0, Math.min(selectedAreaIdx, liveAreas.length - 1));
      const targetArea = liveAreas[targetIdx];
      const hydratedArea = await LibraryBookingService.fetchThereSingleAreaSeats(
        venue.id,
        sessionId,
        useWebVpn,
        targetArea,
        day,
        startTime,
        endTime,
        bookings
      );
      if (hydratedArea === undefined) {
        return {
          areas: liveAreas,
          activeArea: targetArea,
          isLive: false,
          statusText: `${targetArea.name}座位明细查询失败 · 点击「刷新空位」重试`,
          failure: ShuYoThereFailure.UNCERTAIN
        };
      }
      liveAreas[targetIdx] = hydratedArea;

      return {
        areas: liveAreas,
        activeArea: hydratedArea,
        isLive: true,
        statusText: `实时空位 · there.shu.edu.cn（${startTime}-${endTime}）`
      };
    } catch (_err) {
      LibraryBookingService.logThere('slot/exception', `${venue.id}`);
      return {
        areas: fallbackAreas,
        activeArea: fallbackActive,
        isLive: false,
        statusText: '暂时无法连接预约系统 · 校外请开启 WebVPN 或连接校园网后重试',
        failure: ShuYoThereFailure.UNREACHABLE
      };
    }
  }

  static async createBooking(
    venue: ShuYoLibraryVenue,
    area: ShuYoLibraryArea,
    seat: ShuYoLibrarySeat,
    day: string,
    startTime: string,
    endTime: string,
    isLiveMode: boolean,
    useWebVpn: boolean
  ): Promise<ShuYoLibraryBookResult> {
    if (seat.isDisabled || seat.isBusy || seat.isBooked) {
      return { ok: false, message: '该座位当前时段已被占用或不可用' };
    }

    if (!isLiveMode) {
      const rec: ShuYoLibraryBookingRecord = {
        id: `bk-${Date.now()}`,
        venueId: venue.id,
        venueName: venue.name,
        areaId: area.id,
        areaName: area.name,
        seatId: seat.id,
        seatLabel: seat.seatLabel,
        day: day,
        beginTime: `${day} ${startTime}`,
        endTime: `${day} ${endTime}`,
        status: 'BOOKING'
      };
      return {
        ok: true,
        message: `已预约 ${venue.name} ${area.name} ${seat.seatLabel}号（${startTime}-${endTime}）`,
        record: rec
      };
    }

    const meta = LibraryBookingService.venueMetaMap.get(venue.id);
    if (meta !== undefined && meta.isChaoxing) {
      const cxSubmit = await ChaoxingBookingService.submitBooking(venue, area, seat, day, startTime, endTime);
      if (!cxSubmit.ok) {
        return { ok: false, message: cxSubmit.message };
      }
      const rec: ShuYoLibraryBookingRecord = {
        id: cxSubmit.bookingId,
        venueId: venue.id,
        venueName: venue.name,
        areaId: area.id,
        areaName: area.name,
        seatId: seat.id,
        seatLabel: seat.seatLabel,
        day: day,
        beginTime: `${day} ${startTime}`,
        endTime: `${day} ${endTime}`,
        status: 'BOOKING'
      };
      return {
        ok: true,
        message: cxSubmit.message,
        record: rec
      };
    }

    if (LibraryBookingService.isThereSubmitting) {
      return { ok: false, message: '预约正在提交，请等待结果' };
    }
    if (Date.now() - LibraryBookingService.lastThereSubmitAt < LibraryBookingService.thereSubmitIntervalMs) {
      return { ok: false, message: '同一用户提交过于频繁，请稍后重试' };
    }

    LibraryBookingService.isThereSubmitting = true;
    const realAreaId = seat.areaId.length > 0 ? seat.areaId : area.id;
    const cacheKey = `${venue.id}|${useWebVpn ? 'vpn' : 'dir'}`;
    try {
      let session = await LibraryBookingService.ensureThereSession(venue.id, useWebVpn);
      if (session.failure !== ShuYoThereFailure.NONE) {
        return { ok: false, message: session.message };
      }
      let sessionId = session.sessionId;
      let profileJson = await LibraryBookingService.thereApiGet(
        venue.id,
        sessionId,
        useWebVpn,
        '/api/v3/my/profile'
      );
      if (profileJson === undefined) {
        LibraryBookingService.thereSessionIds.delete(cacheKey);
        session = await LibraryBookingService.ensureThereSession(venue.id, useWebVpn);
        if (session.failure !== ShuYoThereFailure.NONE) {
          return { ok: false, message: session.message };
        }
        sessionId = session.sessionId;
        profileJson = await LibraryBookingService.thereApiGet(
          venue.id,
          sessionId,
          useWebVpn,
          '/api/v3/my/profile'
        );
      }
      const profileData = JsonHelpers.asObject(profileJson !== undefined ? profileJson['data'] : undefined);
      const userId = JsonHelpers.str(profileData, 'id', '').trim();
      const userName = JsonHelpers.str(profileData, 'name', 'SHUer').trim();
      if (userId.length === 0) {
        return { ok: false, message: '未获取到预约账户信息，请重新登录校园账号' };
      }
      if (JsonHelpers.bool(profileData, 'disableBooking', false)) {
        return { ok: false, message: '当前账户不可预约' };
      }

      // Refresh the selected interval immediately before submitting so `rawRoom`
      // carries current availability, abilities, and exact metadata.
      const beginParam = encodeURIComponent(`${day} ${startTime}`);
      const endParam = encodeURIComponent(`${day} ${endTime}`);
      const areaDetailJson = await LibraryBookingService.thereApiGet(
        venue.id,
        sessionId,
        useWebVpn,
        `/api/v3/booking-status/areas/${encodeURIComponent(realAreaId)}?begin=${beginParam}&end=${endParam}`
      );
      let freshRawRoom: Record<string, Object> | undefined = undefined;
      if (areaDetailJson !== undefined) {
        const detailData = JsonHelpers.asObject(areaDetailJson['data']);
        const rawRooms = JsonHelpers.asArray(detailData !== undefined ? detailData['rooms'] : undefined);
        for (let i = 0; i < rawRooms.length; i++) {
          const candidate = JsonHelpers.asObject(rawRooms[i]);
          if (candidate === undefined) {
            continue;
          }
          const cId = JsonHelpers.str(candidate, 'id', '').trim();
          const cName = JsonHelpers.str(candidate, 'name', '').trim();
          if (cId === seat.id || (cId.length === 0 && cName === seat.seatLabel)) {
            freshRawRoom = candidate;
            LibraryBookingService.liveRawRooms.set(`${venue.id}|${realAreaId}|${seat.id}`, candidate);
            break;
          }
        }
      } else {
        freshRawRoom = LibraryBookingService.liveRawRooms.get(`${venue.id}|${realAreaId}|${seat.id}`);
      }

      if (!LibraryBookingProtocol.validateThereRoomBookable(freshRawRoom, realAreaId)) {
        return { ok: false, message: '所选座位已不可预约，请刷新后重选' };
      }

      LibraryBookingService.lastThereSubmitAt = Date.now();
      const payload = LibraryBookingProtocol.buildThereBookingPayload(
        freshRawRoom!,
        userId,
        userName,
        day,
        startTime,
        endTime
      );
      const baseUrl = LibraryBookingService.thereBase(useWebVpn);
      const bookingUrl = `${baseUrl}/api/v3/bookings`;
      const postResp = await HttpClientService.request(
        http.RequestMethod.POST,
        bookingUrl,
        LibraryBookingService.withGatewayCookie(
          bookingUrl,
          LibraryBookingService.buildThereHeaders(venue.id, sessionId, useWebVpn, http.RequestMethod.POST)
        ),
        JSON.stringify(payload),
        12000
      );
      const parsed = LibraryBookingProtocol.parseThereBookingResponse(postResp.statusCode, postResp.body);
      if (parsed.failureKind === 'loginRequired') {
        LibraryBookingService.thereSessionIds.delete(cacheKey);
      }
      if (!parsed.ok) {
        return { ok: false, message: parsed.message };
      }

      const rec: ShuYoLibraryBookingRecord = {
        id: parsed.bookingId,
        venueId: venue.id,
        venueName: venue.name,
        areaId: realAreaId,
        areaName: area.name,
        seatId: seat.id,
        seatLabel: seat.seatLabel,
        day: day,
        beginTime: `${day} ${startTime}`,
        endTime: `${day} ${endTime}`,
        status: 'BOOKING'
      };
      return {
        ok: true,
        message: `实时预约成功：${area.name} ${seat.seatLabel}号（${startTime}-${endTime}）`,
        record: rec
      };
    } catch (_err) {
      return { ok: false, message: '预约结果尚未确认，请先查看我的预约，勿直接重试' };
    } finally {
      LibraryBookingService.isThereSubmitting = false;
    }
  }

  static async cancelBooking(
    record: ShuYoLibraryBookingRecord,
    isLiveMode: boolean,
    useWebVpn: boolean
  ): Promise<ShuYoLibraryBookResult> {
    if (!isLiveMode || record.id.startsWith('bk-')) {
      return { ok: true, message: '已取消演示预约' };
    }
    if (record.id.startsWith('cx:')) {
      const parts = record.id.split(':');
      const reserveId = parts[parts.length - 1];
      const cxRes = await ChaoxingBookingService.cancelBooking(reserveId);
      return { ok: cxRes.ok, message: cxRes.message };
    }
    try {
      const session = await LibraryBookingService.ensureThereSession(record.venueId, useWebVpn);
      if (session.failure !== ShuYoThereFailure.NONE) {
        return { ok: false, message: session.message };
      }
      const detailJson = await LibraryBookingService.thereApiGet(
        record.venueId,
        session.sessionId,
        useWebVpn,
        `/api/v3/bookings/${encodeURIComponent(record.id)}?showChecks=true`
      );
      const detailData = JsonHelpers.asObject(detailJson !== undefined ? detailJson['data'] : undefined);
      const abilities = JsonHelpers.strList(detailData, 'abilities');
      const baseUrl = LibraryBookingService.thereBase(useWebVpn);
      let actionPath = '';
      let actionMethod = http.RequestMethod.DELETE;
      if (abilities.includes('cancel')) {
        actionPath = `/api/v3/bookings/${encodeURIComponent(record.id)}/cancel`;
        actionMethod = http.RequestMethod.DELETE;
      } else if (abilities.includes('close')) {
        actionPath = `/api/v3/bookings/${encodeURIComponent(record.id)}/finish`;
        actionMethod = http.RequestMethod.PUT;
      } else {
        return { ok: false, message: '当前预约不可取消或退座' };
      }
      const actionUrl = `${baseUrl}${actionPath}`;
      const resp = await HttpClientService.request(
        actionMethod,
        actionUrl,
        LibraryBookingService.withGatewayCookie(
          actionUrl,
          LibraryBookingService.buildThereHeaders(record.venueId, session.sessionId, useWebVpn, actionMethod)
        ),
        undefined,
        12000
      );
      const obj = JsonHelpers.parseObject(resp.body);
      if (resp.statusCode === 200 && obj !== undefined && JsonHelpers.num(obj, 'code', -1) === 0) {
        return { ok: true, message: '已取消图书馆座位预约' };
      }
      const errMsg = JsonHelpers.str(obj, 'warnMessage', JsonHelpers.str(obj, 'message', '取消预约失败，请稍后重试'));
      return { ok: false, message: errMsg };
    } catch (_err) {
      return { ok: false, message: '取消预约请求异常，请刷新我的预约确认' };
    }
  }
}
