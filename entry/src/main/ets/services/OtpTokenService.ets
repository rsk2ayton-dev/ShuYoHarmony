import { http } from '@kit.NetworkKit';
import { ShuYoConstants } from '../core/ShuYoConstants';
import { ShuYoOtpToken } from '../models/ShuYoModels';
import { HttpClientService, ShuYoHttpResult } from './HttpClientService';
import { ShuYoWebVpnFailure, WebVpnAuthService } from './WebVpnAuthService';
import { WebVpnProtocol } from './WebVpnProtocol';

export class OtpTokenService {
  static fetchDemoToken(): ShuYoOtpToken {
    const period = 30;
    const nowSec = Math.floor(Date.now() / 1000);
    const rotation = Math.floor(nowSec / period);
    const remaining = period - (nowSec % period);
    const rawCode = String((rotation * 7919 + 123456) % 1000000);
    const padded = rawCode.padStart(6, '0');
    return {
      code: padded,
      account: 'DEMO0001',
      remaining: remaining,
      period: period
    };
  }

  private static async walkOtpRedirects(startUrl: string, useWebVpn: boolean): Promise<ShuYoHttpResult> {
    let current = startUrl;
    let lastResp: ShuYoHttpResult = { statusCode: 0, body: '', headers: {}, location: current };
    for (let hop = 0; hop < 12; hop++) {
      lastResp = await HttpClientService.request(http.RequestMethod.GET, current, {
        'Accept': 'text/html,application/xhtml+xml,*/*'
      });
      if (lastResp.statusCode >= 300 && lastResp.statusCode < 400 && lastResp.location.length > 0) {
        const nextRaw = HttpClientService.resolveUrl(current, lastResp.location);
        if (useWebVpn && WebVpnProtocol.isWebVpnPortalRedirect(lastResp.statusCode, nextRaw)) {
          lastResp.location = nextRaw;
          return lastResp;
        }
        const canonical = WebVpnProtocol.canonicalSsoUrl(nextRaw);
        const nextPath = WebVpnProtocol.extractPath(canonical);
        if (nextPath.includes('/oauth2/login/')) {
          throw new Error('动态口令会话未登录或已过期，请先登录统一身份认证');
        }
        current = canonical;
      } else {
        lastResp.location = current;
        return lastResp;
      }
    }
    lastResp.location = current;
    return lastResp;
  }

  static async fetchLiveToken(useWebVpn: boolean): Promise<ShuYoOtpToken> {
    if (useWebVpn) {
      const vpn = await WebVpnAuthService.ensureSession();
      if (vpn.failure !== ShuYoWebVpnFailure.NONE) {
        throw new Error(vpn.message);
      }
    }
    const host = useWebVpn ? ShuYoConstants.otpWebVpnHost : ShuYoConstants.otpDirectHost;
    const url = `https://${host}${ShuYoConstants.otpLandingPath}`;
    let resp = await OtpTokenService.walkOtpRedirects(url, useWebVpn);
    if (useWebVpn &&
      (resp.statusCode === 401 ||
        resp.statusCode === 403 ||
        WebVpnProtocol.isWebVpnPortalRedirect(resp.statusCode, resp.location))) {
      WebVpnAuthService.clearSession();
      const retryVpn = await WebVpnAuthService.ensureSession();
      if (retryVpn.failure !== ShuYoWebVpnFailure.NONE) {
        throw new Error(retryVpn.message);
      }
      resp = await OtpTokenService.walkOtpRedirects(url, useWebVpn);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw new Error(`无法访问动态口令系统 (${resp.statusCode})`);
    }
    const parsed = OtpTokenService.parseHtml(resp.body, resp.headers['refresh']);
    if (parsed === undefined) {
      throw new Error('动态口令会话未登录或已过期，请先登录统一身份认证');
    }
    return parsed;
  }

  static parseHtml(html: string, refreshHeader?: string): ShuYoOtpToken | undefined {
    const codeMatch = new RegExp('id=["\']DataList1_LabelNum_\\d+["\'][^>]*>\\s*(\\d{4,8})\\s*<').exec(html);
    if (codeMatch === null || codeMatch[1].length !== 6) {
      return undefined;
    }
    const accMatch = new RegExp('id=["\']DataList1_LabelAccount_\\d+["\'][^>]*>\\s*([^<]*?)\\s*<').exec(html);
    const remMatch = new RegExp('let\\s+remainingSeconds\\s*=\\s*(\\d+)\\s*;').exec(html);
    const perMatch = new RegExp('const\\s+totalSeconds\\s*=\\s*(\\d+)\\s*;').exec(html);

    const period = perMatch !== null ? parseInt(perMatch[1], 10) : 30;
    let remaining = period;
    if (refreshHeader !== undefined && refreshHeader.trim().length > 0) {
      const h = parseInt(refreshHeader.trim(), 10);
      if (Number.isFinite(h)) {
        remaining = h;
      }
    } else if (remMatch !== null) {
      remaining = parseInt(remMatch[1], 10);
    }
    const clampedRemaining = Math.min(Math.max(remaining, 0), period);

    return {
      code: codeMatch[1],
      account: accMatch !== null ? accMatch[1].trim() : '',
      remaining: clampedRemaining,
      period: period
    };
  }

  static formatGroupedCode(code: string): string {
    if (code.length === 6) {
      return `${code.substring(0, 3)} ${code.substring(3)}`;
    }
    return code;
  }
}
