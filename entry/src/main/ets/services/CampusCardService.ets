import { http } from '@kit.NetworkKit';
import { ShuYoConstants } from '../core/ShuYoConstants';
import {
  ShuYoCampusCardBill,
  ShuYoCampusCardInfo,
  ShuYoDailySpending
} from '../models/ShuYoModels';
import { AuthService } from './AuthService';
import { HttpClientService, ShuYoCookieJar } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';
import { SecureStorageService } from './SecureStorageService';

interface ShuYoDemoTxItem {
  daysAgo: number;
  hour: number;
  minute: number;
  name: string;
  amount: number;
}

interface ShuYoCardSession {
  token: string;
  studentId: string;
  initialCard?: ShuYoCampusCardInfo;
}

export interface ShuYoCampusCardLiveResult {
  cardInfo: ShuYoCampusCardInfo;
  bills: ShuYoCampusCardBill[];
}

export class CampusCardService {
  private static readonly sessionStorageKey: string = 'shuyo_campus_card_session_v1';
  private static readonly authRequiredPrefix: string = 'AUTH_REQUIRED:';
  private static readonly tokenExpiredPrefix: string = 'TOKEN_EXPIRED:';
  private static readonly maxBillRangeDays: number = 90;
  private static readonly dayMs: number = 86400000;

  private static readonly cardPath: string = '/api/Identity/SchoolCard/GetCardPersonInfo';
  private static readonly billsPath: string = '/api/Identity/SchoolCard/GetCardBillInfo';
  private static readonly loginPath: string = '/api/Identity/User/Login';
  private static readonly profilePath: string = '/api/Identity/User/GetUserInfo';

  private static readonly demoTx: ShuYoDemoTxItem[] = [
    { daysAgo: 0, hour: 12, minute: 15, name: '宝山校区第一食堂', amount: 13.50 },
    { daysAgo: 1, hour: 18, minute: 12, name: '宝山校区第一食堂', amount: 14.00 },
    { daysAgo: 1, hour: 12, minute: 6, name: '宝山校区第二食堂', amount: 11.80 },
    { daysAgo: 2, hour: 8, minute: 45, name: '校园卡充值', amount: -50.00 },
    { daysAgo: 3, hour: 12, minute: 25, name: '宝山校区第一食堂', amount: 14.20 },
    { daysAgo: 4, hour: 16, minute: 33, name: '校园超市', amount: 5.50 },
    { daysAgo: 5, hour: 18, minute: 7, name: '宝山校区第三食堂', amount: 16.50 },
    { daysAgo: 6, hour: 12, minute: 11, name: '宝山校区第二食堂', amount: 12.80 },
    { daysAgo: 9, hour: 13, minute: 1, name: '自助打印', amount: 3.00 },
    { daysAgo: 12, hour: 12, minute: 17, name: '宝山校区第一食堂', amount: 12.50 },
    { daysAgo: 17, hour: 18, minute: 22, name: '宝山校区第三食堂', amount: 15.90 },
    { daysAgo: 21, hour: 10, minute: 16, name: '校园卡充值', amount: -40.00 },
    { daysAgo: 25, hour: 12, minute: 8, name: '宝山校区第二食堂', amount: 10.80 }
  ];

  static isAuthRequiredError(msg: string): boolean {
    return msg.startsWith(CampusCardService.authRequiredPrefix);
  }

  static isTokenExpiredError(msg: string): boolean {
    return msg.startsWith(CampusCardService.tokenExpiredPrefix);
  }

  static stripErrorPrefix(msg: string): string {
    if (msg.startsWith(CampusCardService.authRequiredPrefix)) {
      return msg.substring(CampusCardService.authRequiredPrefix.length);
    }
    if (msg.startsWith(CampusCardService.tokenExpiredPrefix)) {
      return msg.substring(CampusCardService.tokenExpiredPrefix.length);
    }
    return msg;
  }

  static emptyCardInfo(studentId: string = ''): ShuYoCampusCardInfo {
    return {
      studentId: studentId,
      holderName: '',
      cardStatus: '未同步',
      balance: 0,
      validUntil: '',
      isLoaded: false
    };
  }

  static loadDemoCardInfo(): ShuYoCampusCardInfo {
    return {
      studentId: 'DEMO0001',
      holderName: '演示用户',
      cardStatus: '正常',
      balance: 87.60,
      validUntil: '',
      isLoaded: true
    };
  }

  static loadDemoBills(): ShuYoCampusCardBill[] {
    const now = new Date();
    const baseMs = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
    const out: ShuYoCampusCardBill[] = [];
    for (let i = 0; i < CampusCardService.demoTx.length; i++) {
      const tx = CampusCardService.demoTx[i];
      now.setTime(baseMs - tx.daysAgo * CampusCardService.dayMs + (tx.hour * 60 + tx.minute) * 60000);
      const y = now.getUTCFullYear();
      const m = CampusCardService.pad2(now.getUTCMonth() + 1);
      const d = CampusCardService.pad2(now.getUTCDate());
      const hh = CampusCardService.pad2(now.getUTCHours());
      const mm = CampusCardService.pad2(now.getUTCMinutes());
      out.push({
        id: `demo-bill-${i}`,
        merchantName: tx.name,
        payTime: `${y}-${m}-${d} ${hh}:${mm}:00`,
        amount: tx.amount
      });
    }
    return out;
  }

  static summarizeDailySpending(bills: ShuYoCampusCardBill[]): ShuYoDailySpending[] {
    const dayMap = new Map<string, number>();
    for (let i = 0; i < bills.length; i++) {
      const b = bills[i];
      if (b.amount <= 0) {
        continue;
      }
      const trimmed = b.payTime.trim();
      const dateStr = trimmed.length >= 10 ? trimmed.substring(5, 10) : trimmed;
      const prev = dayMap.get(dateStr) ?? 0;
      dayMap.set(dateStr, prev + b.amount);
    }
    const keys = Array.from(dayMap.keys());
    keys.sort();
    const recentKeys = keys.length > 7 ? keys.slice(keys.length - 7) : keys;
    const out: ShuYoDailySpending[] = [];
    for (let i = 0; i < recentKeys.length; i++) {
      const k = recentKeys[i];
      const val = dayMap.get(k) ?? 0;
      out.push({ dateLabel: k, totalAmount: Number(val.toFixed(2)) });
    }
    return out;
  }

  static computeRecentSpend(bills: ShuYoCampusCardBill[], days: number): number {
    const d = new Date();
    const todayUtcMs = Date.UTC(d.getFullYear(), d.getMonth(), d.getDate());
    const span = days > 1 ? days - 1 : 0;
    d.setTime(todayUtcMs - span * CampusCardService.dayMs);
    const cutoffStr = CampusCardService.formatUtcDay(d);
    let total = 0;
    for (let i = 0; i < bills.length; i++) {
      const b = bills[i];
      if (b.amount > 0) {
        const dayPart = b.payTime.trim().substring(0, 10);
        if (dayPart >= cutoffStr) {
          total += b.amount;
        }
      }
    }
    return total;
  }

  static clearSession(): void {
    SecureStorageService.remove(CampusCardService.sessionStorageKey);
  }

  private static saveSession(studentId: string, accessToken: string): void {
    const obj: Record<string, string> = {
      'studentId': studentId,
      'access_token': accessToken
    };
    SecureStorageService.setString(CampusCardService.sessionStorageKey, JSON.stringify(obj));
  }

  private static loadSavedSession(): ShuYoCardSession | undefined {
    const raw = SecureStorageService.getString(CampusCardService.sessionStorageKey, '');
    if (raw.length === 0) {
      return undefined;
    }
    const obj = JsonHelpers.parseObject(raw);
    if (obj === undefined) {
      CampusCardService.clearSession();
      return undefined;
    }
    const studentId = JsonHelpers.str(obj, 'studentId').trim();
    const token = JsonHelpers.str(obj, 'access_token').trim();
    if (studentId.length === 0 || token.length === 0) {
      CampusCardService.clearSession();
      return undefined;
    }
    return { token: token, studentId: studentId };
  }

  private static async authorizeCampusCardViaSso(): Promise<string> {
    if (!ShuYoCookieJar.hasCookie(ShuYoConstants.ssoBaseUrl, 'SHU_OAUTH2')) {
      throw new Error(`${CampusCardService.authRequiredPrefix}统一身份认证会话已过期，请重新登录后同步校园卡`);
    }
    const authUrl =
      `${ShuYoConstants.ssoBaseUrl}/oauth/authorize?response_type=code` +
      `&client_id=${encodeURIComponent(ShuYoConstants.targetCampusCard.clientId)}` +
      `&redirect_uri=${encodeURIComponent(ShuYoConstants.targetCampusCard.redirectUri)}` +
      `&scope=${encodeURIComponent(ShuYoConstants.targetCampusCard.scope)}`;
    const resp = await HttpClientService.request(http.RequestMethod.GET, authUrl, {
      'Accept': 'application/json, text/plain, */*'
    });
    if (resp.statusCode < 300 || resp.statusCode >= 400 || resp.location.length === 0) {
      throw new Error(`SSO 未返回校园卡授权地址（HTTP ${resp.statusCode}）`);
    }
    if (resp.location.includes('/oauth2/login/')) {
      throw new Error(`${CampusCardService.authRequiredPrefix}统一身份认证会话已失效，请重新登录`);
    }
    const callbackUrl = HttpClientService.resolveUrl(authUrl, resp.location);
    const host = HttpClientService.extractHost(callbackUrl).toLowerCase();
    const path = HttpClientService.extractPath(callbackUrl);
    if (!callbackUrl.startsWith('https://') ||
      host !== ShuYoConstants.eportalHost ||
      (path !== '/login' && path !== '/login/') ||
      AuthService.extractQueryParam(callbackUrl, 'error').length > 0) {
      throw new Error('校园卡授权回调无效，请重试');
    }
    const code = AuthService.extractQueryParam(callbackUrl, 'code').trim();
    if (code.length === 0) {
      throw new Error('校园卡授权回调缺少 code，请重试');
    }
    return code;
  }

  private static isAllowedPath(path: string): boolean {
    return path === CampusCardService.cardPath ||
      path === CampusCardService.billsPath ||
      path === CampusCardService.loginPath ||
      path === CampusCardService.profilePath;
  }

  private static async eportalRequest(
    method: http.RequestMethod,
    path: string,
    queryPairs: string[]
  ): Promise<Record<string, Object>> {
    if (!CampusCardService.isAllowedPath(path)) {
      throw new Error('校园卡请求地址无效');
    }
    const queryStr = queryPairs.length > 0 ? `?${queryPairs.join('&')}` : '';
    const url = `${ShuYoConstants.eportalBaseUrl}${path}${queryStr}`;
    const headers: Record<string, string> = {
      'Accept': 'application/json'
    };
    const bodyArg: string | undefined = method === http.RequestMethod.POST ? '' : undefined;
    const resp = await HttpClientService.request(method, url, headers, bodyArg, 15000);
    if (resp.statusCode === 401 || resp.statusCode === 403) {
      throw new Error(`${CampusCardService.tokenExpiredPrefix}校园卡登录状态已失效`);
    }
    if (resp.statusCode !== 200) {
      throw new Error(`校园卡服务暂时不可用（HTTP ${resp.statusCode}）`);
    }
    const payload = JsonHelpers.parseObject(resp.body);
    if (payload === undefined) {
      throw new Error('校园卡数据格式异常，请稍后重试');
    }
    const resType = JsonHelpers.num(payload, 'type', -1);
    const errorCode = JsonHelpers.num(payload, 'errorcode', -1);
    const msg = JsonHelpers.str(payload, 'message').trim();
    if (resType === 3 && errorCode === 500 && msg === '登录失效') {
      throw new Error(`${CampusCardService.tokenExpiredPrefix}校园卡登录状态已失效`);
    }
    if (resType !== 1 || errorCode !== 0) {
      throw new Error(msg.length > 0 ? msg : '校方暂未返回校园卡数据，请稍后重试');
    }
    const data = JsonHelpers.asObject(payload['data']);
    if (data === undefined) {
      throw new Error('校园卡数据格式异常，请稍后重试');
    }
    return data;
  }

  private static parseCardFromData(data: Record<string, Object>, expectedStudentId: string): ShuYoCampusCardInfo {
    const schoolCard = JsonHelpers.asObject(data['schoolCard']);
    if (schoolCard === undefined) {
      throw new Error('校园卡返回资料缺失');
    }
    const studentId = JsonHelpers.str(schoolCard, 'PersonNumber').trim();
    const holderName = JsonHelpers.str(schoolCard, 'PersonName').trim();
    const cardStatus = JsonHelpers.str(schoolCard, 'CardStatus', '正常').trim();
    const balance = JsonHelpers.num(schoolCard, 'ZhangHYE', Number.NaN);
    const validUntil = JsonHelpers.str(schoolCard, 'YouXQ').trim();
    if (studentId.length === 0 || !Number.isFinite(balance)) {
      throw new Error('校园卡资料字段异常，请稍后重试');
    }
    if (expectedStudentId.length > 0 && studentId !== expectedStudentId) {
      CampusCardService.clearSession();
      throw new Error(`${CampusCardService.authRequiredPrefix}校园卡身份与当前校园账户不一致，请重新登录`);
    }
    return {
      studentId: studentId,
      holderName: holderName.length > 0 ? holderName : studentId,
      cardStatus: cardStatus.length > 0 ? cardStatus : '正常',
      balance: balance,
      validUntil: validUntil,
      isLoaded: true
    };
  }

  private static async readCardWithToken(
    token: string,
    expectedStudentId: string
  ): Promise<ShuYoCampusCardInfo> {
    const data = await CampusCardService.eportalRequest(
      http.RequestMethod.GET,
      CampusCardService.cardPath,
      [`access_token=${encodeURIComponent(token)}`]
    );
    return CampusCardService.parseCardFromData(data, expectedStudentId);
  }

  private static async ensureSession(
    expectedStudentId: string,
    forceReauth: boolean
  ): Promise<ShuYoCardSession> {
    const targetStudentId = expectedStudentId.trim();
    if (targetStudentId.length === 0) {
      throw new Error(`${CampusCardService.authRequiredPrefix}请先登录上海大学统一身份认证`);
    }

    if (!forceReauth) {
      const saved = CampusCardService.loadSavedSession();
      if (saved !== undefined && saved.studentId === targetStudentId) {
        try {
          const profile = await CampusCardService.eportalRequest(
            http.RequestMethod.POST,
            CampusCardService.profilePath,
            [`access_token=${encodeURIComponent(saved.token)}`]
          );
          const profileId = JsonHelpers.str(profile, 'userid').trim();
          if (profileId === targetStudentId) {
            return saved;
          }
          CampusCardService.clearSession();
        } catch (err) {
          const e = err as Error;
          if (!CampusCardService.isTokenExpiredError(e.message)) {
            throw e;
          }
          CampusCardService.clearSession();
        }
      } else if (saved !== undefined) {
        CampusCardService.clearSession();
      }
    } else {
      CampusCardService.clearSession();
    }

    const authCode = await CampusCardService.authorizeCampusCardViaSso();
    const loginData = await CampusCardService.eportalRequest(
      http.RequestMethod.POST,
      CampusCardService.loginPath,
      [`code=${encodeURIComponent(authCode)}`]
    );
    const token = JsonHelpers.str(loginData, 'access_token').trim();
    const userId = JsonHelpers.str(loginData, 'userid').trim();
    if (token.length === 0 || userId.length === 0) {
      throw new Error('校园卡授权响应格式异常');
    }
    if (userId !== targetStudentId) {
      throw new Error(`${CampusCardService.authRequiredPrefix}校园卡身份与当前账户不一致，请重新登录`);
    }
    const card = await CampusCardService.readCardWithToken(token, userId);
    CampusCardService.saveSession(userId, token);
    return {
      token: token,
      studentId: userId,
      initialCard: card
    };
  }

  private static async fetchBillsWithToken(token: string, rangeDays: number): Promise<ShuYoCampusCardBill[]> {
    const safeDays = rangeDays > 0 ? rangeDays : 90;
    const d = new Date();
    const endUtcMs = Date.UTC(d.getFullYear(), d.getMonth(), d.getDate());
    const startUtcMs = endUtcMs - (safeDays - 1) * CampusCardService.dayMs;
    const out: ShuYoCampusCardBill[] = [];
    let chunkEndMs = endUtcMs;
    let chunkIdx = 0;

    while (chunkEndMs >= startUtcMs) {
      const limitMs = chunkEndMs - (CampusCardService.maxBillRangeDays - 1) * CampusCardService.dayMs;
      const chunkStartMs = limitMs > startUtcMs ? limitMs : startUtcMs;
      d.setTime(chunkStartMs);
      const startStr = CampusCardService.formatUtcDay(d);
      d.setTime(chunkEndMs);
      const endStr = CampusCardService.formatUtcDay(d);

      const data = await CampusCardService.eportalRequest(
        http.RequestMethod.GET,
        CampusCardService.billsPath,
        [
          `access_token=${encodeURIComponent(token)}`,
          `StartDate=${encodeURIComponent(startStr)}`,
          `EndDate=${encodeURIComponent(endStr)}`
        ]
      );
      const rawBills = JsonHelpers.asArray(data['bills']);
      for (let i = 0; i < rawBills.length; i++) {
        const bObj = JsonHelpers.asObject(rawBills[i]);
        if (bObj === undefined) {
          continue;
        }
        const merchant = JsonHelpers.str(bObj, 'billname').trim();
        const payTime = JsonHelpers.str(bObj, 'paytime').trim();
        const amount = JsonHelpers.num(bObj, 'amount', Number.NaN);
        if (merchant.length === 0 || payTime.length === 0 || !Number.isFinite(amount)) {
          continue;
        }
        out.push({
          id: `live-bill-${chunkIdx}-${i}-${payTime}`,
          merchantName: merchant,
          payTime: payTime,
          amount: amount
        });
      }
      chunkIdx++;
      chunkEndMs = chunkStartMs - CampusCardService.dayMs;
    }

    out.sort((a: ShuYoCampusCardBill, b: ShuYoCampusCardBill): number => {
      if (b.payTime > a.payTime) {
        return 1;
      }
      if (b.payTime < a.payTime) {
        return -1;
      }
      return 0;
    });
    return out;
  }

  private static async executeLiveFetch(
    expectedStudentId: string,
    rangeDays: number,
    forceReauth: boolean
  ): Promise<ShuYoCampusCardLiveResult> {
    const session = await CampusCardService.ensureSession(expectedStudentId, forceReauth);
    const cardInfo = session.initialCard !== undefined
      ? session.initialCard
      : await CampusCardService.readCardWithToken(session.token, session.studentId);
    const bills = await CampusCardService.fetchBillsWithToken(session.token, rangeDays);
    return {
      cardInfo: cardInfo,
      bills: bills
    };
  }

  static async fetchLiveCardAndBills(
    expectedStudentId: string,
    rangeDays: number = 90
  ): Promise<ShuYoCampusCardLiveResult> {
    try {
      return await CampusCardService.executeLiveFetch(expectedStudentId, rangeDays, false);
    } catch (firstErr) {
      const fe = firstErr as Error;
      if (!CampusCardService.isTokenExpiredError(fe.message)) {
        throw fe;
      }
      try {
        CampusCardService.clearSession();
        return await CampusCardService.executeLiveFetch(expectedStudentId, rangeDays, true);
      } catch (retryErr) {
        const re = retryErr as Error;
        if (CampusCardService.isTokenExpiredError(re.message)) {
          throw new Error(`${CampusCardService.authRequiredPrefix}校园卡查询需要重新验证校园账户`);
        }
        throw re;
      }
    }
  }

  private static formatUtcDay(d: Date): string {
    const y = d.getUTCFullYear();
    const m = CampusCardService.pad2(d.getUTCMonth() + 1);
    const day = CampusCardService.pad2(d.getUTCDate());
    return `${y}-${m}-${day}`;
  }

  private static pad2(val: number): string {
    return val < 10 ? `0${val}` : `${val}`;
  }
}
