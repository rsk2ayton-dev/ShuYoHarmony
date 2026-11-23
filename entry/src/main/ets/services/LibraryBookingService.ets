import { http } from '@kit.NetworkKit';
import { ShuYoConstants } from '../core/ShuYoConstants';
import {
  ShuYoLibraryArea,
  ShuYoLibraryBookingRecord,
  ShuYoLibrarySeat,
  ShuYoLibraryVenue
} from '../models/ShuYoModels';
import { AuthService } from './AuthService';
import { HttpClientService, ShuYoCookieJar } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';
import { RawFileService } from './RawFileService';

interface ShuYoVenueMeta {
  roomType: string;
  mobilePath: string;
  isThere: boolean;
}

export interface ShuYoLibrarySlotQueryResult {
  areas: ShuYoLibraryArea[];
  activeArea: ShuYoLibraryArea | undefined;
  isLive: boolean;
  statusText: string;
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
    { id: 'yanchang', name: '延长校区图书馆', campusName: '延长校区', areaNames: ['B区', 'C区'] },
    { id: 'jiading', name: '嘉定校区图书馆', campusName: '嘉定校区', areaNames: ['一楼自修室', '二楼自修区'] }
  ];

  static readonly timeOptions: string[] = [
    '08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
    '12:00', '12:30', '13:00', '13:30', '14:00', '14:30', '15:00', '15:30',
    '16:00', '16:30', '17:00', '17:30', '18:00', '18:30', '19:00', '19:30',
    '20:00', '20:30', '21:00', '21:30', '22:00'
  ];

  private static readonly venueMetaMap: Map<string, ShuYoVenueMeta> = LibraryBookingService.buildVenueMetaMap();
  private static thereSessionIds: Map<string, string> = new Map<string, string>();
  private static liveRawRooms: Map<string, Record<string, Object>> = new Map<string, Record<string, Object>>();

  private static buildVenueMetaMap(): Map<string, ShuYoVenueMeta> {
    const m = new Map<string, ShuYoVenueMeta>();
    m.set('library', { roomType: 'LIB_SEAT', mobilePath: '/mobile/libseat', isThere: true });
    m.set('studySpace', { roomType: 'STATION', mobilePath: '/mobile/seat2021', isThere: true });
    m.set('yanchang', { roomType: 'SEAT', mobilePath: '/mobile/seat-mgr', isThere: true });
    m.set('scienceArt', { roomType: 'CS_SEAT', mobilePath: '/mobile/csseat', isThere: true });
    m.set('qianweichang', { roomType: 'CX_QWC', mobilePath: '', isThere: false });
    m.set('jiading', { roomType: 'CX_JD', mobilePath: '', isThere: false });
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
    return { prefix: '', count: 24, digits: 2 };
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
          : (s === 5 || s === 18);

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

  private static thereBase(useWebVpn: boolean): string {
    return useWebVpn ? ShuYoConstants.thereWebVpnBaseUrl : ShuYoConstants.thereBaseUrl;
  }

  private static normalizeThereRedirect(baseUrl: string, location: string): string {
    if (location.length === 0) {
      return '';
    }
    const resolved = HttpClientService.resolveUrl(baseUrl, location);
    const host = HttpClientService.extractHost(resolved).toLowerCase();
    const path = HttpClientService.extractPath(resolved);
    const qIdx = resolved.indexOf('?');
    const querySuffix = qIdx >= 0 ? resolved.substring(qIdx) : '';
    if (host === ShuYoConstants.thereHost ||
      host === 'http-there-shu-edu-cn-80.webvpn.shu.edu.cn' ||
      host === 'https-there-shu-edu-cn-443.webvpn.shu.edu.cn') {
      return `${baseUrl}${path}${querySuffix}`;
    }
    return resolved;
  }

  private static extractSessionIdFromHtml(html: string): string | undefined {
    const m1 = new RegExp('\\bsessionId\\s*[=:]\\s*"([^"\\r\\n]*)"').exec(html);
    if (m1 !== null) {
      return m1[1];
    }
    const m2 = new RegExp("\\bsessionId\\s*[=:]\\s*'([^'\\r\\n]*)'").exec(html);
    if (m2 !== null) {
      return m2[1];
    }
    return undefined;
  }

  private static async completeThereSsoOAuth(baseUrl: string): Promise<boolean> {
    if (!ShuYoCookieJar.hasCookie(ShuYoConstants.ssoBaseUrl, 'SHU_OAUTH2')) {
      return false;
    }
    const loginResp = await HttpClientService.request(
      http.RequestMethod.GET,
      `${baseUrl}/login?from=web`,
      { 'Accept': 'application/json,text/html,*/*' },
      undefined,
      10000
    );
    if (loginResp.statusCode < 300 || loginResp.statusCode >= 400 || loginResp.location.length === 0) {
      return false;
    }
    const state = AuthService.extractQueryParam(loginResp.location, 'state').trim();
    if (state.length === 0) {
      return false;
    }
    const authUrl =
      `${ShuYoConstants.ssoBaseUrl}/oauth/authorize?response_type=code` +
      `&client_id=${encodeURIComponent(ShuYoConstants.targetThere.clientId)}` +
      `&redirect_uri=${encodeURIComponent(ShuYoConstants.targetThere.redirectUri)}` +
      `&scope=${encodeURIComponent(ShuYoConstants.targetThere.scope)}` +
      `&state=${encodeURIComponent(state)}`;

    const ssoResp = await HttpClientService.request(
      http.RequestMethod.GET,
      authUrl,
      { 'Accept': 'text/html,application/xhtml+xml,*/*' },
      undefined,
      10000
    );
    if (ssoResp.statusCode < 300 || ssoResp.statusCode >= 400 || ssoResp.location.length === 0) {
      return false;
    }
    const callbackUrl = LibraryBookingService.normalizeThereRedirect(baseUrl, ssoResp.location);
    if (!callbackUrl.includes('/login-oauth2') || AuthService.extractQueryParam(callbackUrl, 'code').length === 0) {
      return false;
    }

    const cbResp = await HttpClientService.request(
      http.RequestMethod.GET,
      callbackUrl,
      { 'Accept': 'text/html,application/xhtml+xml,*/*' },
      undefined,
      10000
    );
    if (cbResp.statusCode < 300 || cbResp.statusCode >= 400 || cbResp.location.length === 0) {
      return false;
    }

    let nextUrl = LibraryBookingService.normalizeThereRedirect(baseUrl, cbResp.location);
    for (let hop = 0; hop < 4; hop++) {
      const pageResp = await HttpClientService.request(
        http.RequestMethod.GET,
        nextUrl,
        { 'Accept': 'text/html,application/xhtml+xml,*/*' },
        undefined,
        10000
      );
      if (pageResp.statusCode === 200) {
        return true;
      }
      if (pageResp.statusCode >= 300 && pageResp.statusCode < 400 && pageResp.location.length > 0) {
        nextUrl = LibraryBookingService.normalizeThereRedirect(baseUrl, pageResp.location);
      } else {
        break;
      }
    }
    return false;
  }

  private static async ensureThereSession(venueId: string, useWebVpn: boolean): Promise<string | undefined> {
    const meta = LibraryBookingService.venueMetaMap.get(venueId);
    if (meta === undefined || !meta.isThere) {
      return undefined;
    }
    const cacheKey = `${venueId}|${useWebVpn ? 'vpn' : 'dir'}`;
    const existing = LibraryBookingService.thereSessionIds.get(cacheKey);
    if (existing !== undefined) {
      return existing;
    }

    const baseUrl = LibraryBookingService.thereBase(useWebVpn);
    const entryUrl = `${baseUrl}${meta.mobilePath}`;
    let resp = await HttpClientService.request(
      http.RequestMethod.GET,
      entryUrl,
      {
        'Accept': 'application/json,text/html,*/*',
        'X-Requested-With': 'com.tencent.wework'
      },
      undefined,
      10000
    );

    const needsLogin = (resp.statusCode >= 300 && resp.statusCode < 400) ||
      resp.body.includes('"isAnonymous":true') ||
      resp.body.includes("'isAnonymous':true");
    if (needsLogin) {
      const authed = await LibraryBookingService.completeThereSsoOAuth(baseUrl);
      if (!authed) {
        return undefined;
      }
      resp = await HttpClientService.request(
        http.RequestMethod.GET,
        entryUrl,
        {
          'Accept': 'application/json,text/html,*/*',
          'X-Requested-With': 'com.tencent.wework'
        },
        undefined,
        10000
      );
    }

    if (resp.statusCode !== 200) {
      return undefined;
    }
    const sid = LibraryBookingService.extractSessionIdFromHtml(resp.body);
    if (sid === undefined) {
      return undefined;
    }
    LibraryBookingService.thereSessionIds.set(cacheKey, sid);
    return sid;
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
    const resp = await HttpClientService.request(
      http.RequestMethod.GET,
      `${baseUrl}${pathWithQuery}`,
      LibraryBookingService.buildThereHeaders(venueId, sessionId, useWebVpn, http.RequestMethod.GET),
      undefined,
      10000
    );
    if (resp.statusCode === 401 || resp.statusCode === 403 || resp.statusCode === 302) {
      LibraryBookingService.thereSessionIds.delete(`${venueId}|${useWebVpn ? 'vpn' : 'dir'}`);
      return undefined;
    }
    if (resp.statusCode !== 200) {
      return undefined;
    }
    const obj = JsonHelpers.parseObject(resp.body);
    if (obj === undefined || JsonHelpers.num(obj, 'code', -1) !== 0) {
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
    const fallbackAreas = LibraryBookingService.buildAreasForSlot(venue, day, startTime, endTime, bookings);
    const safeIdx = Math.max(0, Math.min(selectedAreaIdx, Math.max(0, fallbackAreas.length - 1)));
    const fallbackResult: ShuYoLibrarySlotQueryResult = {
      areas: fallbackAreas,
      activeArea: fallbackAreas.length > 0 ? fallbackAreas[safeIdx] : undefined,
      isLive: false,
      statusText: isDemoMode ? '演示模式 · 按所选时段模拟' : '离线平面图 · 按时段模拟（连接校园网查实时）'
    };

    const meta = LibraryBookingService.venueMetaMap.get(venue.id);
    if (isDemoMode || meta === undefined || !meta.isThere) {
      return fallbackResult;
    }
    if (!ShuYoCookieJar.hasCookie(ShuYoConstants.ssoBaseUrl, 'SHU_OAUTH2')) {
      return fallbackResult;
    }

    try {
      const sessionId = await LibraryBookingService.ensureThereSession(venue.id, useWebVpn);
      if (sessionId === undefined) {
        return fallbackResult;
      }
      const areasJson = await LibraryBookingService.thereApiGet(
        venue.id,
        sessionId,
        useWebVpn,
        `/api/v3/booking-status/areas?begin=${encodeURIComponent(day)}&end=${encodeURIComponent(day)}`
      );
      if (areasJson === undefined) {
        return fallbackResult;
      }
      const rawAreaList = JsonHelpers.asArray(areasJson['data']);
      if (rawAreaList.length === 0) {
        return fallbackResult;
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
        return fallbackResult;
      }

      const targetIdx = Math.max(0, Math.min(selectedAreaIdx, liveAreas.length - 1));
      const targetArea = liveAreas[targetIdx];
      const beginParam = encodeURIComponent(`${day} ${startTime}`);
      const endParam = encodeURIComponent(`${day} ${endTime}`);
      const areaDetailJson = await LibraryBookingService.thereApiGet(
        venue.id,
        sessionId,
        useWebVpn,
        `/api/v3/booking-status/areas/${encodeURIComponent(targetArea.id)}?begin=${beginParam}&end=${endParam}`
      );
      if (areaDetailJson === undefined) {
        return fallbackResult;
      }
      const detailData = JsonHelpers.asObject(areaDetailJson['data']);
      const rawRooms = JsonHelpers.asArray(detailData !== undefined ? detailData['rooms'] : undefined);
      const parsedSeats = LibraryBookingService.parseThereRooms(
        venue.id,
        targetArea.id,
        rawRooms,
        day,
        startTime,
        endTime,
        bookings
      );
      if (parsedSeats.length === 0) {
        return fallbackResult;
      }

      let liveFree = 0;
      for (let i = 0; i < parsedSeats.length; i++) {
        const s = parsedSeats[i];
        if (!s.isDisabled && !s.isBusy && !s.isBooked) {
          liveFree++;
        }
      }

      const hydratedArea: ShuYoLibraryArea = {
        id: targetArea.id,
        name: targetArea.name,
        totalCount: parsedSeats.length,
        freeCount: liveFree,
        seats: parsedSeats
      };
      liveAreas[targetIdx] = hydratedArea;

      return {
        areas: liveAreas,
        activeArea: hydratedArea,
        isLive: true,
        statusText: `实时空位 · there.shu.edu.cn（${startTime}-${endTime}）`
      };
    } catch (_err) {
      return fallbackResult;
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

    try {
      const sessionId = await LibraryBookingService.ensureThereSession(venue.id, useWebVpn);
      if (sessionId === undefined) {
        return { ok: false, message: '图书馆实时会话已失效，请重新登录校园账号' };
      }
      const profileJson = await LibraryBookingService.thereApiGet(
        venue.id,
        sessionId,
        useWebVpn,
        '/api/v3/my/profile'
      );
      const profileData = JsonHelpers.asObject(profileJson !== undefined ? profileJson['data'] : undefined);
      const userId = JsonHelpers.str(profileData, 'id', '').trim();
      const userName = JsonHelpers.str(profileData, 'name', 'SHUer').trim();
      const rawRoom = LibraryBookingService.liveRawRooms.get(`${venue.id}|${area.id}|${seat.id}`);
      if (userId.length === 0 || rawRoom === undefined) {
        return { ok: false, message: '未获取到完整用户信息或座位信息，请刷新后重试' };
      }

      const timeSlot: Record<string, Object> = {
        'startDate': day,
        'startTime': startTime,
        'endDate': day,
        'endTime': endTime
      };
      const roomsArr: Object[] = [rawRoom];
      const timesArr: Object[] = [timeSlot];
      const membersArr: Object[] = [userId];
      const payload: Record<string, Object> = {
        'rooms': roomsArr,
        'times': timesArr,
        'subject': userName,
        'meetingMembers': membersArr
      };
      const baseUrl = LibraryBookingService.thereBase(useWebVpn);
      const postResp = await HttpClientService.request(
        http.RequestMethod.POST,
        `${baseUrl}/api/v3/bookings`,
        LibraryBookingService.buildThereHeaders(venue.id, sessionId, useWebVpn, http.RequestMethod.POST),
        JSON.stringify(payload),
        12000
      );
      const postObj = JsonHelpers.parseObject(postResp.body);
      if (postResp.statusCode !== 200 || postObj === undefined || JsonHelpers.num(postObj, 'code', -1) !== 0) {
        const errMsg = JsonHelpers.str(
          postObj,
          'warnMessage',
          JsonHelpers.str(postObj, 'message', '预约失败，该座位可能刚刚被他人预约')
        );
        return { ok: false, message: errMsg };
      }

      const dataArr = JsonHelpers.asArray(postObj['data']);
      const createdObj = dataArr.length > 0 ? JsonHelpers.asObject(dataArr[0]) : undefined;
      const bookingId = JsonHelpers.str(createdObj, 'id', `live-${Date.now()}`);
      const rec: ShuYoLibraryBookingRecord = {
        id: bookingId,
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
        message: `实时预约成功：${area.name} ${seat.seatLabel}号（${startTime}-${endTime}）`,
        record: rec
      };
    } catch (_err) {
      return { ok: false, message: '实时预约请求失败，请检查校园网或 WebVPN 连接' };
    }
  }
}
