import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { ShuYoConstants } from '../core/ShuYoConstants';
import { HttpClientService, ShuYoCookieJar } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';
import { PreferencesService } from './PreferencesService';

export enum ShuYoWebVpnFailure {
  NONE = 'none',
  LOGIN_REQUIRED = 'loginRequired',
  UNREACHABLE = 'unreachable',
  UNCERTAIN = 'uncertain'
}

export interface ShuYoWebVpnResult {
  failure: ShuYoWebVpnFailure;
  message: string;
  userId: string;
}

/**
 * Complete WebVPN login for the school gateway.
 *
 * Mirrors the upstream Flutter handshake:
 *   GET  /api/access/authentication/list?type=Login   -> authType 5 externalId
 *   POST /api/access/auth/start                        -> SSO authorize URL
 *   GET  <authorize...>                                -> /callback/oauth2?code
 *   POST /api/access/auth/finish                       -> issues `webvpn-token`
 *   GET  /api/access/user/info                         -> confirms the identity
 *
 * `webvpn-token` is scoped to webvpn.shu.edu.cn, so proxied hosts never receive
 * it from the cookie jar; callers must attach it explicitly on the gateway.
 */
export class WebVpnAuthService {
  private static readonly deviceIdKey: string = 'shuyo_webvpn_device_id_v1';
  private static readonly authTypeSchoolSso: number = 5;
  private static inFlight: Promise<ShuYoWebVpnResult> | undefined;

  static hasPortalToken(): boolean {
    return ShuYoCookieJar.getCookieValue(ShuYoConstants.webVpnPortal, 'webvpn-token').length > 0;
  }

  static clearSession(): void {
    ShuYoCookieJar.clearDomain('webvpn.shu.edu.cn');
  }

  /** Reuses one handshake when several features start at the same time. */
  static async ensureSession(): Promise<ShuYoWebVpnResult> {
    if (WebVpnAuthService.inFlight !== undefined) {
      return WebVpnAuthService.inFlight;
    }
    const task = WebVpnAuthService.runHandshake();
    WebVpnAuthService.inFlight = task;
    try {
      return await task;
    } finally {
      WebVpnAuthService.inFlight = undefined;
    }
  }

  private static ok(userId: string): ShuYoWebVpnResult {
    return { failure: ShuYoWebVpnFailure.NONE, message: '', userId: userId };
  }

  private static fail(failure: ShuYoWebVpnFailure, message: string): ShuYoWebVpnResult {
    return { failure: failure, message: message, userId: '' };
  }

  private static async runHandshake(): Promise<ShuYoWebVpnResult> {
    if (!ShuYoCookieJar.hasCookie(ShuYoConstants.ssoBaseUrl, 'SHU_OAUTH2')) {
      return WebVpnAuthService.fail(
        ShuYoWebVpnFailure.LOGIN_REQUIRED,
        '开启 WebVPN 需要先登录统一身份认证'
      );
    }
    try {
      const existing = ShuYoCookieJar.getCookieValue(ShuYoConstants.webVpnPortal, 'webvpn-token');
      if (existing.length > 0) {
        const known = await WebVpnAuthService.readUserInfo();
        if (known.failure === ShuYoWebVpnFailure.NONE) {
          return known;
        }
        WebVpnAuthService.clearSession();
      }

      const externalId = await WebVpnAuthService.pickExternalId();
      const state = WebVpnAuthService.encodeState(externalId);
      const startBody: Record<string, Object> = {
        'externalId': externalId,
        'data': WebVpnAuthService.stringifyInner({
          'callbackUrl': `${ShuYoConstants.webVpnPortal}${ShuYoConstants.webVpnCallbackPath}`,
          'state': state
        })
      };
      const startResp = await WebVpnAuthService.postJson(
        ShuYoConstants.webVpnAuthStart,
        startBody,
        `${ShuYoConstants.webVpnPortal}/auth/login`
      );
      if (startResp === undefined) {
        return WebVpnAuthService.fail(ShuYoWebVpnFailure.UNCERTAIN, 'WebVPN 统一认证启动失败 · 请稍后重试');
      }
      const action = JsonHelpers.asObject(startResp['data']);
      const loginUrl = JsonHelpers.str(JsonHelpers.asObject(action !== undefined ? action['action'] : undefined), 'login_url', '').trim();
      if (loginUrl.length === 0) {
        return WebVpnAuthService.fail(ShuYoWebVpnFailure.UNCERTAIN, 'WebVPN 未返回统一认证地址');
      }

      const callback = await WebVpnAuthService.walkAuthorize(loginUrl);
      if (callback.length === 0) {
        return WebVpnAuthService.fail(
          ShuYoWebVpnFailure.LOGIN_REQUIRED,
          'WebVPN 统一认证未完成 · 请先登录校园账号'
        );
      }
      const code = WebVpnAuthService.queryParam(callback, 'code');
      const returnedState = WebVpnAuthService.queryParam(callback, 'state');
      if (code.length === 0 || returnedState.length === 0) {
        return WebVpnAuthService.fail(ShuYoWebVpnFailure.UNCERTAIN, 'WebVPN 授权回调缺少参数 · 请重试');
      }

      const finishBody: Record<string, Object> = {
        'externalId': externalId,
        'data': WebVpnAuthService.stringifyInner({
          'callbackUrl': `${ShuYoConstants.webVpnPortal}${ShuYoConstants.webVpnCallbackPath}`,
          'code': code,
          'deviceId': WebVpnAuthService.deviceId(),
          'state': returnedState
        })
      };
      const finishResp = await WebVpnAuthService.postJson(
        ShuYoConstants.webVpnAuthFinish,
        finishBody,
        `${ShuYoConstants.webVpnPortal}${ShuYoConstants.webVpnCallbackPath}`
      );
      if (finishResp === undefined || JsonHelpers.num(finishResp, 'code', -1) !== 0) {
        return WebVpnAuthService.fail(ShuYoWebVpnFailure.UNCERTAIN, 'WebVPN 登录未完成 · 请重试');
      }
      const confirmed = await WebVpnAuthService.readUserInfo();
      if (confirmed.failure !== ShuYoWebVpnFailure.NONE) {
        return confirmed;
      }
      if (!WebVpnAuthService.hasPortalToken()) {
        return WebVpnAuthService.fail(ShuYoWebVpnFailure.UNCERTAIN, 'WebVPN 未下发网关会话令牌 · 请重试');
      }
      return confirmed;
    } catch (_err) {
      return WebVpnAuthService.fail(
        ShuYoWebVpnFailure.UNREACHABLE,
        '暂时无法连接 WebVPN 网关 · 请检查网络后重试'
      );
    }
  }

  private static async readUserInfo(): Promise<ShuYoWebVpnResult> {
    const requestUrl = `${ShuYoConstants.webVpnPortal}${ShuYoConstants.webVpnUserInfoPath}`;
    const resp = await HttpClientService.request(
      http.RequestMethod.GET,
      requestUrl,
      {
        'Accept': 'application/json',
        'Referer': `${ShuYoConstants.webVpnPortal}/site-nav/`
      },
      undefined,
      12000
    );
    if (resp.statusCode === 401 || resp.statusCode === 403) {
      return WebVpnAuthService.fail(ShuYoWebVpnFailure.LOGIN_REQUIRED, 'WebVPN 会话已失效');
    }
    if (resp.statusCode !== 200) {
      return WebVpnAuthService.fail(ShuYoWebVpnFailure.UNCERTAIN, 'WebVPN 身份确认失败');
    }
    const obj = JsonHelpers.parseObject(resp.body);
    if (obj === undefined || JsonHelpers.num(obj, 'code', -1) !== 0) {
      return WebVpnAuthService.fail(ShuYoWebVpnFailure.LOGIN_REQUIRED, 'WebVPN 未能确认登录身份');
    }
    const data = JsonHelpers.asObject(obj['data']);
    const userId = JsonHelpers.str(data, 'userId', '').trim();
    if (userId.length === 0 || userId === '0') {
      return WebVpnAuthService.fail(ShuYoWebVpnFailure.LOGIN_REQUIRED, 'WebVPN 未能确认登录身份');
    }
    return WebVpnAuthService.ok(userId);
  }

  private static directAuthorizeUrl(rawUrl: string): string {
    const trimmed = rawUrl.trim();
    const host = HttpClientService.extractHost(trimmed).toLowerCase();
    if (host === ShuYoConstants.webVpnNewssoProxyHost) {
      const schemeIdx = trimmed.indexOf('://');
      if (schemeIdx >= 0) {
        const afterScheme = trimmed.substring(schemeIdx + 3);
        const slashIdx = afterScheme.indexOf('/');
        const tail = slashIdx >= 0 ? afterScheme.substring(slashIdx) : '/';
        return `${ShuYoConstants.ssoBaseUrl}${tail}`;
      }
    }
    return trimmed;
  }

  private static async fetchAuthListExternalId(listType: string): Promise<string> {
    const url = `${ShuYoConstants.webVpnPortal}/api/access/authentication/list?type=${encodeURIComponent(listType)}`;
    const resp = await HttpClientService.request(
      http.RequestMethod.GET,
      url,
      {
        'Accept': 'application/json',
        'Referer': `${ShuYoConstants.webVpnPortal}/auth/login`
      },
      undefined,
      12000
    );
    if (resp.statusCode !== 200) {
      return '';
    }
    const obj = JsonHelpers.parseObject(resp.body);
    if (obj === undefined || JsonHelpers.num(obj, 'code', -1) !== 0) {
      return '';
    }
    const data = JsonHelpers.asObject(obj['data']);
    const list = JsonHelpers.asArray(data !== undefined ? data['list'] : undefined);
    for (let i = 0; i < list.length; i++) {
      const item = JsonHelpers.asObject(list[i]);
      if (item === undefined) {
        continue;
      }
      if (JsonHelpers.num(item, 'authType', -1) === WebVpnAuthService.authTypeSchoolSso) {
        const externalId = JsonHelpers.str(item, 'externalId', '').trim();
        if (externalId.length > 0) {
          return externalId;
        }
      }
    }
    return '';
  }

  private static async pickExternalId(): Promise<string> {
    const primary = await WebVpnAuthService.fetchAuthListExternalId('0');
    if (primary.length > 0) {
      return primary;
    }
    const secondary = await WebVpnAuthService.fetchAuthListExternalId('Login');
    if (secondary.length > 0) {
      return secondary;
    }
    return ShuYoConstants.webVpnExternalIdFallback;
  }

  /** Follows the SSO authorize chain until the gateway callback is reached. */
  private static async walkAuthorize(loginUrl: string): Promise<string> {
    let current = WebVpnAuthService.directAuthorizeUrl(loginUrl);
    for (let hop = 0; hop < 8; hop++) {
      const resp = await HttpClientService.request(
        http.RequestMethod.GET,
        current,
        {
          'Accept': 'text/html,application/xhtml+xml,*/*',
          'Referer': ShuYoConstants.webVpnPortal
        },
        undefined,
        12000
      );
      const next = resp.location.length > 0 ? HttpClientService.resolveUrl(current, resp.location) : '';
      if (next.length === 0) {
        return '';
      }
      const host = HttpClientService.extractHost(next).toLowerCase();
      const path = HttpClientService.extractPath(next);
      if (host === 'webvpn.shu.edu.cn' &&
        path === ShuYoConstants.webVpnCallbackPath &&
        WebVpnAuthService.queryParam(next, 'code').length > 0) {
        return next;
      }
      if (path.includes('/oauth2/login/') || path === '/login' || path.endsWith('/login')) {
        return '';
      }
      current = WebVpnAuthService.directAuthorizeUrl(next);
    }
    return '';
  }

  private static async postJson(
    path: string,
    body: Record<string, Object>,
    referer: string
  ): Promise<Record<string, Object> | undefined> {
    const resp = await HttpClientService.request(
      http.RequestMethod.POST,
      `${ShuYoConstants.webVpnPortal}${path}`,
      {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Referer': referer
      },
      JSON.stringify(body),
      12000
    );
    if (resp.statusCode !== 200) {
      return undefined;
    }
    return JsonHelpers.parseObject(resp.body);
  }

  private static stringifyInner(fields: Record<string, string>): string {
    return JSON.stringify(fields);
  }

  private static encodeState(externalId: string): string {
    const payload: Record<string, string> = { 'externalId': externalId };
    const bytes = new util.TextEncoder().encodeInto(JSON.stringify(payload));
    return new util.Base64Helper().encodeToStringSync(bytes);
  }

  private static queryParam(url: string, name: string): string {
    const qIdx = url.indexOf('?');
    if (qIdx < 0) {
      return '';
    }
    const hashIdx = url.indexOf('#', qIdx);
    const query = hashIdx >= 0 ? url.substring(qIdx + 1, hashIdx) : url.substring(qIdx + 1);
    const parts = query.split('&');
    for (let i = 0; i < parts.length; i++) {
      const eq = parts[i].indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const key = decodeURIComponent(parts[i].substring(0, eq));
      if (key !== name) {
        continue;
      }
      const value = parts[i].substring(eq + 1).replace(/\+/g, ' ');
      try {
        return decodeURIComponent(value);
      } catch (_err) {
        return value;
      }
    }
    return '';
  }

  /** Stable 32-hex pseudo visitor id: the gateway treats a changing id as a new device. */
  private static deviceId(): string {
    const saved = PreferencesService.getString(WebVpnAuthService.deviceIdKey, '').trim();
    if (new RegExp('^[0-9a-f]{32}$').test(saved)) {
      return saved;
    }
    let hex = '';
    try {
      const blob = cryptoFramework.createRandom().generateRandomSync(16);
      for (let i = 0; i < blob.data.length; i++) {
        const part = blob.data[i].toString(16);
        hex += part.length === 1 ? `0${part}` : part;
      }
    } catch (_err) {
      hex = '';
    }
    if (hex.length !== 32) {
      hex = '';
      for (let i = 0; i < 16; i++) {
        const part = Math.floor(Math.random() * 256).toString(16);
        hex += part.length === 1 ? `0${part}` : part;
      }
    }
    PreferencesService.setString(WebVpnAuthService.deviceIdKey, hex);
    return hex;
  }
}
