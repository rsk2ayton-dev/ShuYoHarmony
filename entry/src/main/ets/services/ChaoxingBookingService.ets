import { http } from '@kit.NetworkKit';
import { ShuYoConstants } from '../core/ShuYoConstants';
import {
  ShuYoLibraryArea,
  ShuYoLibraryBookingRecord,
  ShuYoLibrarySeat,
  ShuYoLibraryVenue
} from '../models/ShuYoModels';
import { HttpClientService, ShuYoCookieJar, ShuYoHttpResult } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';
import { LibraryBookingProtocol } from './LibraryBookingProtocol';

export interface ChaoxingFetchResult {
  areas: ShuYoLibraryArea[];
  activeArea: ShuYoLibraryArea | undefined;
  statusText: string;
}

export interface ChaoxingSubmitResult {
  ok: boolean;
  message: string;
  bookingId: string;
}

/**
 * Chaoxing (`office.chaoxing.com`) library seat client for
 * Qianweichang Library, Jiading Library, and Yanchang Wenhui Library.
 */
export class ChaoxingBookingService {
  private static readonly indexPath: string = '/front/third/apps/seat/index';
  private static readonly selectPath: string = '/front/third/apps/seat/select';
  private static readonly oauthRedirectHost: string = 'zhstsg-jx.5read.com';
  private static readonly submitIntervalMs: number = 10000;
  private static verifiedUid: string = '';
  private static isSubmitting: boolean = false;
  private static lastSubmitAt: number = 0;

  static clearSession(): void {
    ChaoxingBookingService.verifiedUid = '';
    ShuYoCookieJar.clearDomain('chaoxing.com');
    ShuYoCookieJar.clearDomain('office.chaoxing.com');
    ShuYoCookieJar.clearDomain(ChaoxingBookingService.oauthRedirectHost);
  }

  private static getIndexUrl(): string {
    return `${ShuYoConstants.chaoxingBaseUrl}${ChaoxingBookingService.indexPath}?fidEnc=${encodeURIComponent(ShuYoConstants.chaoxingFidEnc)}`;
  }

  static todayDateStr(): string {
    const d = new Date();
    const utcMs = d.getTime() + d.getTimezoneOffset() * 60000;
    const shanghai = new Date(utcMs + 8 * 3600000);
    const y = shanghai.getFullYear();
    const m = shanghai.getMonth() + 1;
    const day = shanghai.getDate();
    return `${y}-${m < 10 ? '0' + m : m}-${day < 10 ? '0' + day : day}`;
  }

  private static encodeForm(fields: Record<string, string>): string {
    const keys = Object.keys(fields);
    const parts: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(fields[k])}`);
    }
    return parts.join('&');
  }

  private static secureExchangeRedirect(rawUrl: string): string {
    const trimmed = rawUrl.trim();
    if (!trimmed.toLowerCase().startsWith('http://')) {
      return trimmed;
    }
    const host = HttpClientService.extractHost(trimmed).toLowerCase();
    const knownHost = host === ChaoxingBookingService.oauthRedirectHost ||
      host === 'chaoxing.com' ||
      host.endsWith('.chaoxing.com');
    if (!knownHost) {
      return trimmed;
    }
    const rest = trimmed.substring(7);
    const slashIdx = rest.indexOf('/');
    const authority = slashIdx >= 0 ? rest.substring(0, slashIdx) : rest;
    const tail = slashIdx >= 0 ? rest.substring(slashIdx) : '';
    if (authority.includes('@')) {
      return trimmed;
    }
    const colonIdx = authority.indexOf(':');
    if (colonIdx >= 0 && authority.substring(colonIdx + 1) !== '80') {
      return trimmed;
    }
    return `https://${host}${tail}`;
  }

  private static isChaoxingHost(host: string): boolean {
    const h = host.toLowerCase();
    return h === 'chaoxing.com' || h.endsWith('.chaoxing.com');
  }

  private static isAllowedExchangeUrl(url: string): boolean {
    if (!url.toLowerCase().startsWith('https://')) {
      return false;
    }
    const host = HttpClientService.extractHost(url).toLowerCase();
    return host === ChaoxingBookingService.oauthRedirectHost || ChaoxingBookingService.isChaoxingHost(host);
  }

  private static buildHeaders(isAjax: boolean, refererUrl: string, hasForm: boolean): Record<string, string> {
    const hdrs: Record<string, string> = {
      'Accept': isAjax
        ? 'application/json, text/javascript, */*; q=0.01'
        : 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    };
    if (isAjax) {
      hdrs['X-Requested-With'] = 'XMLHttpRequest';
    }
    if (refererUrl.length > 0) {
      hdrs['Referer'] = refererUrl;
    }
    if (hasForm) {
      hdrs['Origin'] = ShuYoConstants.chaoxingBaseUrl;
      hdrs['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8';
    }
    return hdrs;
  }

  private static async getFollowChaoxingRedirects(
    url: string,
    refererUrl: string
  ): Promise<ShuYoHttpResult> {
    let current = url;
    for (let hop = 0; hop < 8; hop++) {
      const resp = await HttpClientService.request(
        http.RequestMethod.GET,
        current,
        ChaoxingBookingService.buildHeaders(false, refererUrl, false),
        undefined,
        12000
      );
      if (resp.statusCode >= 300 && resp.statusCode < 400 && resp.location.length > 0) {
        const nextUrl = HttpClientService.resolveUrl(current, resp.location);
        const nextHost = HttpClientService.extractHost(nextUrl).toLowerCase();
        if (nextHost !== 'office.chaoxing.com' || !nextUrl.toLowerCase().startsWith('https://')) {
          return resp;
        }
        current = nextUrl;
        continue;
      }
      resp.location = current;
      return resp;
    }
    return {
      statusCode: 0,
      body: '',
      headers: {},
      location: current
    };
  }

  private static extractVerifiedUid(html: string): string {
    const m = new RegExp('userLoginInfo\\s*=\\s*(\\{[\\s\\S]*?\\})\\s*\\|\\|\\s*\\{\\}').exec(html);
    if (m === null) {
      return '';
    }
    const infoObj = JsonHelpers.parseObject(m[1]);
    const userInfo = JsonHelpers.asObject(infoObj !== undefined ? infoObj['userInfo'] : undefined);
    return JsonHelpers.str(userInfo, 'uid', '').trim();
  }

  private static async verifyOfficeSession(): Promise<boolean> {
    const resp = await ChaoxingBookingService.getFollowChaoxingRedirects(
      ChaoxingBookingService.getIndexUrl(),
      ChaoxingBookingService.getIndexUrl()
    );
    if (resp.statusCode !== 200) {
      ChaoxingBookingService.verifiedUid = '';
      return false;
    }
    const uid = ChaoxingBookingService.extractVerifiedUid(resp.body);
    ChaoxingBookingService.verifiedUid = uid;
    return uid.length > 0;
  }

  private static async exchangeSso(): Promise<boolean> {
    if (!ShuYoCookieJar.hasCookie(ShuYoConstants.ssoBaseUrl, 'SHU_OAUTH2')) {
      return false;
    }
    const authUrl =
      `${ShuYoConstants.ssoBaseUrl}/oauth/authorize` +
      `?client_id=${encodeURIComponent(ShuYoConstants.targetChaoxing.clientId)}` +
      `&response_type=code` +
      `&scope=${encodeURIComponent(ShuYoConstants.targetChaoxing.scope)}` +
      `&redirect_uri=${encodeURIComponent(ShuYoConstants.targetChaoxing.redirectUri)}` +
      `&state=`;

    const ssoResp = await HttpClientService.request(
      http.RequestMethod.GET,
      authUrl,
      ChaoxingBookingService.buildHeaders(false, '', false),
      undefined,
      12000
    );
    if (ssoResp.statusCode < 300 || ssoResp.statusCode >= 400 || ssoResp.location.length === 0) {
      return false;
    }
    const initialNext = HttpClientService.resolveUrl(authUrl, ssoResp.location);
    if (HttpClientService.extractHost(initialNext).toLowerCase() !== ChaoxingBookingService.oauthRedirectHost ||
      !initialNext.includes('code=')) {
      return false;
    }

    let nextUrl = initialNext;
    for (let hop = 0; hop < 10; hop++) {
      const target = ChaoxingBookingService.secureExchangeRedirect(nextUrl);
      if (!ChaoxingBookingService.isAllowedExchangeUrl(target)) {
        return false;
      }
      const hopResp = await HttpClientService.request(
        http.RequestMethod.GET,
        target,
        ChaoxingBookingService.buildHeaders(false, '', false),
        undefined,
        12000
      );
      if (hopResp.statusCode >= 300 && hopResp.statusCode < 400 && hopResp.location.length > 0) {
        nextUrl = HttpClientService.resolveUrl(target, hopResp.location);
        continue;
      }
      const finalHost = HttpClientService.extractHost(target).toLowerCase();
      return hopResp.statusCode === 200 && ChaoxingBookingService.isChaoxingHost(finalHost);
    }
    return false;
  }

  static async ensureSession(): Promise<boolean> {
    if (ChaoxingBookingService.verifiedUid.length > 0 ||
      ShuYoCookieJar.headerFor(ChaoxingBookingService.getIndexUrl()).length > 0) {
      if (await ChaoxingBookingService.verifyOfficeSession()) {
        return true;
      }
    }
    const exchanged = await ChaoxingBookingService.exchangeSso();
    if (!exchanged) {
      return false;
    }
    return await ChaoxingBookingService.verifyOfficeSession();
  }

  private static matchesVenue(venueId: string, roomObj: Record<string, Object>): boolean {
    const label = `${JsonHelpers.str(roomObj, 'secondLevelName', '')} ${JsonHelpers.str(roomObj, 'thirdLevelName', '')}`;
    if (venueId === 'qianweichang') {
      return label.includes('钱伟长');
    }
    if (venueId === 'jiading') {
      return label.includes('嘉定');
    }
    if (venueId === 'wenhui') {
      return label.includes('延长') || label.includes('文荟');
    }
    return false;
  }

  private static normalizeSeatNum(raw: string): string {
    return LibraryBookingProtocol.normalizeChaoxingSeatNum(raw);
  }

  private static hasLocalBookingOverlap(
    bookings: ShuYoLibraryBookingRecord[],
    areaId: string,
    seatLabel: string,
    day: string,
    startTime: string,
    endTime: string
  ): boolean {
    const slotBegin = `${day} ${startTime}`;
    const slotEnd = `${day} ${endTime}`;
    for (let i = 0; i < bookings.length; i++) {
      const rec = bookings[i];
      if (rec.status !== 'BOOKING') {
        continue;
      }
      const matchSeat = rec.areaId === areaId &&
        (rec.seatId === seatLabel || rec.seatLabel === seatLabel);
      if (matchSeat && rec.day === day && rec.beginTime < slotEnd && rec.endTime > slotBegin) {
        return true;
      }
    }
    return false;
  }

  static async fetchAreasAndSeats(
    venue: ShuYoLibraryVenue,
    selectedAreaIdx: number,
    day: string,
    startTime: string,
    endTime: string,
    bookings: ShuYoLibraryBookingRecord[]
  ): Promise<ChaoxingFetchResult | undefined> {
    if (day !== ChaoxingBookingService.todayDateStr()) {
      return undefined;
    }
    const ok = await ChaoxingBookingService.ensureSession();
    if (!ok) {
      return undefined;
    }

    const indexUrl = ChaoxingBookingService.getIndexUrl();
    const roomListUrl =
      `${ShuYoConstants.chaoxingBaseUrl}/data/apps/seat/room/list` +
      `?time=&cpage=1&pageSize=100&firstLevelName=&secondLevelName=&thirdLevelName=` +
      `&day=${encodeURIComponent(day)}&deptIdEnc=${encodeURIComponent(ShuYoConstants.chaoxingFidEnc)}`;
    const listResp = await HttpClientService.request(
      http.RequestMethod.GET,
      roomListUrl,
      ChaoxingBookingService.buildHeaders(true, indexUrl, false),
      undefined,
      12000
    );
    if (listResp.statusCode !== 200) {
      return undefined;
    }
    const listEnvelope = JsonHelpers.parseObject(listResp.body);
    if (listEnvelope === undefined || !JsonHelpers.bool(listEnvelope, 'success', false)) {
      return undefined;
    }
    const listData = JsonHelpers.asObject(listEnvelope['data']);
    const rawRooms = JsonHelpers.asArray(listData !== undefined ? listData['seatRoomList'] : undefined);

    const areas: ShuYoLibraryArea[] = [];
    for (let i = 0; i < rawRooms.length; i++) {
      const rObj = JsonHelpers.asObject(rawRooms[i]);
      if (rObj === undefined || !ChaoxingBookingService.matchesVenue(venue.id, rObj)) {
        continue;
      }
      const roomId = JsonHelpers.str(rObj, 'id', '').trim();
      const areaName = JsonHelpers.str(rObj, 'thirdLevelName', '阅览室').trim();
      if (roomId.length === 0) {
        continue;
      }
      const capacity = Math.max(0, JsonHelpers.num(rObj, 'capacity', 0));
      areas.push({
        id: roomId,
        name: areaName,
        totalCount: capacity,
        freeCount: capacity,
        seats: []
      });
    }
    if (areas.length === 0) {
      return undefined;
    }

    const safeIdx = Math.max(0, Math.min(selectedAreaIdx, areas.length - 1));
    const targetArea = areas[safeIdx];

    const infoBody = ChaoxingBookingService.encodeForm({
      'id': targetArea.id,
      'toDay': day,
      'fidEnc': ShuYoConstants.chaoxingFidEnc,
      'queryReserve': 'true'
    });
    const usedBody = ChaoxingBookingService.encodeForm({
      'roomId': targetArea.id,
      'startTime': startTime,
      'endTime': endTime,
      'day': day,
      'fidEnc': ShuYoConstants.chaoxingFidEnc
    });

    const pairRes = await Promise.all([
      HttpClientService.request(
        http.RequestMethod.POST,
        `${ShuYoConstants.chaoxingBaseUrl}/data/apps/seat/room/info`,
        ChaoxingBookingService.buildHeaders(true, indexUrl, true),
        infoBody,
        12000
      ),
      HttpClientService.request(
        http.RequestMethod.POST,
        `${ShuYoConstants.chaoxingBaseUrl}/data/apps/seat/getusedseatnums`,
        ChaoxingBookingService.buildHeaders(true, indexUrl, true),
        usedBody,
        12000
      )
    ]);

    const infoResp = pairRes[0];
    const usedResp = pairRes[1];
    if (infoResp.statusCode !== 200 || usedResp.statusCode !== 200) {
      return undefined;
    }
    const infoEnv = JsonHelpers.parseObject(infoResp.body);
    const usedEnv = JsonHelpers.parseObject(usedResp.body);
    if (infoEnv === undefined || !JsonHelpers.bool(infoEnv, 'success', false) ||
      usedEnv === undefined || !JsonHelpers.bool(usedEnv, 'success', false)) {
      return undefined;
    }

    const infoData = JsonHelpers.asObject(infoEnv['data']);
    const seatRoom = JsonHelpers.asObject(infoData !== undefined ? infoData['seatRoom'] : undefined);
    const capacity = JsonHelpers.num(seatRoom, 'capacity', targetArea.totalCount);
    const startNum = Math.max(1, JsonHelpers.num(seatRoom, 'startSeatNum', 1));
    if (capacity <= 0) {
      return undefined;
    }

    const usedData = JsonHelpers.asObject(usedEnv['data']);
    const seatReserves = JsonHelpers.asArray(usedData !== undefined ? usedData['seatReserves'] : undefined);
    const usedSet = new Set<string>();
    for (let i = 0; i < seatReserves.length; i++) {
      const resObj = JsonHelpers.asObject(seatReserves[i]);
      const rawSeatNum = JsonHelpers.str(resObj, 'seatNum', '').trim();
      if (rawSeatNum.length > 0) {
        usedSet.add(ChaoxingBookingService.normalizeSeatNum(rawSeatNum));
      }
    }

    const seats: ShuYoLibrarySeat[] = [];
    let freeCount = 0;
    for (let n = startNum; n < startNum + capacity; n++) {
      const code = ChaoxingBookingService.normalizeSeatNum(`${n}`);
      const isBooked = ChaoxingBookingService.hasLocalBookingOverlap(
        bookings,
        targetArea.id,
        code,
        day,
        startTime,
        endTime
      );
      const isBusy = usedSet.has(code);
      if (!isBusy && !isBooked) {
        freeCount++;
      }
      seats.push({
        id: code,
        seatLabel: code,
        areaId: targetArea.id,
        isBusy: isBusy,
        isDisabled: false,
        isBooked: isBooked
      });
    }

    const hydrated: ShuYoLibraryArea = {
      id: targetArea.id,
      name: targetArea.name,
      totalCount: seats.length,
      freeCount: freeCount,
      seats: seats
    };
    areas[safeIdx] = hydrated;

    return {
      areas: areas,
      activeArea: hydrated,
      statusText: `实时空位 · 超星图书馆（${startTime}-${endTime}）`
    };
  }

  static async submitBooking(
    venue: ShuYoLibraryVenue,
    area: ShuYoLibraryArea,
    seat: ShuYoLibrarySeat,
    day: string,
    startTime: string,
    endTime: string
  ): Promise<ChaoxingSubmitResult> {
    if (day !== ChaoxingBookingService.todayDateStr()) {
      return { ok: false, message: `${venue.name}超星系统仅支持预约当天时段`, bookingId: '' };
    }
    if (ChaoxingBookingService.isSubmitting) {
      return { ok: false, message: '预约正在提交，请等待结果', bookingId: '' };
    }
    if (Date.now() - ChaoxingBookingService.lastSubmitAt < ChaoxingBookingService.submitIntervalMs) {
      return { ok: false, message: '同一用户 10 秒内只能提交一次，请稍后重试', bookingId: '' };
    }
    ChaoxingBookingService.isSubmitting = true;
    try {
      const ok = await ChaoxingBookingService.ensureSession();
      if (!ok) {
        return { ok: false, message: '超星图书馆会话已失效，请重新登录校园账号', bookingId: '' };
      }

      const indexUrl = ChaoxingBookingService.getIndexUrl();
      const selectUrl =
        `${ShuYoConstants.chaoxingBaseUrl}${ChaoxingBookingService.selectPath}` +
        `?deptIdEnc=${encodeURIComponent(ShuYoConstants.chaoxingFidEnc)}` +
        `&id=${encodeURIComponent(area.id)}` +
        `&day=${encodeURIComponent(day)}` +
        `&backLevel=2` +
        `&fidEnc=${encodeURIComponent(ShuYoConstants.chaoxingFidEnc)}`;

      const selectResp = await ChaoxingBookingService.getFollowChaoxingRedirects(selectUrl, indexUrl);
      if (selectResp.statusCode !== 200) {
        return { ok: false, message: '无法打开超星选座页面，请稍后重试', bookingId: '' };
      }
      if (selectResp.location.includes('/front/apps/reserve/error')) {
        return { ok: false, message: '当前区域暂时不可预约', bookingId: '' };
      }

      const salt = LibraryBookingProtocol.extractChaoxingSubmitSalt(selectResp.body);
      if (salt.length === 0) {
        return { ok: false, message: '未获取到选座校验参数，请刷新后重试', bookingId: '' };
      }

      const seatNum = ChaoxingBookingService.normalizeSeatNum(seat.seatLabel);
      const plain = LibraryBookingProtocol.buildChaoxingSubmitPlain(
        area.id,
        seatNum,
        day,
        startTime,
        endTime,
        ShuYoConstants.chaoxingFidEnc,
        salt
      );
      const enc = ChaoxingBookingService.md5Hex(plain);

      const formBody = ChaoxingBookingService.encodeForm({
        'captcha': '',
        'day': day,
        'deptIdEnc': ShuYoConstants.chaoxingFidEnc,
        'endTime': endTime,
        'roomId': area.id,
        'seatNum': seatNum,
        'startTime': startTime,
        'wyToken': '',
        'enc': enc
      });

      ChaoxingBookingService.lastSubmitAt = Date.now();
      const submitResp = await HttpClientService.request(
        http.RequestMethod.POST,
        `${ShuYoConstants.chaoxingBaseUrl}/data/apps/seat/submit`,
        ChaoxingBookingService.buildHeaders(true, selectUrl, true),
        formBody,
        15000
      );
      const parsed = LibraryBookingProtocol.parseChaoxingSubmitResponse(submitResp.statusCode, submitResp.body);
      if (!parsed.ok) {
        return { ok: false, message: parsed.message, bookingId: '' };
      }
      return {
        ok: true,
        message: `实时预约成功：${venue.name} ${area.name} ${seatNum}号（${startTime}-${endTime}）`,
        bookingId: `cx:${venue.id}:${parsed.bookingId}`
      };
    } catch (_err) {
      return { ok: false, message: '预约提交结果未确认，请先查看我的预约，勿直接重试', bookingId: '' };
    } finally {
      ChaoxingBookingService.isSubmitting = false;
    }
  }

  static async cancelBooking(reserveId: string): Promise<ChaoxingSubmitResult> {
    const cleanId = reserveId.trim();
    if (!new RegExp('^\\d+$').test(cleanId)) {
      return { ok: false, message: '超星预约编号无效，无法取消', bookingId: '' };
    }
    const ok = await ChaoxingBookingService.ensureSession();
    if (!ok) {
      return { ok: false, message: '超星图书馆会话已失效，请重新登录校园账号', bookingId: '' };
    }
    const indexUrl = ChaoxingBookingService.getIndexUrl();
    const cancelUrl = `${ShuYoConstants.chaoxingBaseUrl}/data/apps/seat/cancel?id=${encodeURIComponent(cleanId)}`;
    const resp = await HttpClientService.request(
      http.RequestMethod.GET,
      cancelUrl,
      ChaoxingBookingService.buildHeaders(true, indexUrl, false),
      undefined,
      12000
    );
    const env = JsonHelpers.parseObject(resp.body);
    if (resp.statusCode === 200 && env !== undefined && JsonHelpers.bool(env, 'success', false)) {
      return { ok: true, message: '已取消超星图书馆座位预约', bookingId: cleanId };
    }
    const errMsg = JsonHelpers.str(env, 'msg', JsonHelpers.str(env, 'message', '取消超星预约失败'));
    return { ok: false, message: errMsg, bookingId: '' };
  }

  private static md5Hex(plain: string): string {
    return LibraryBookingProtocol.md5HexPure(plain);
  }
}
