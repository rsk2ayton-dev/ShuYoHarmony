import { ShuYoConstants } from '../core/ShuYoConstants';
import { ShuYoOtpToken } from '../models/ShuYoModels';
import { HttpClientService } from './HttpClientService';

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

  static async fetchLiveToken(useWebVpn: boolean): Promise<ShuYoOtpToken> {
    const host = useWebVpn ? ShuYoConstants.otpWebVpnHost : ShuYoConstants.otpDirectHost;
    const url = `https://${host}${ShuYoConstants.otpLandingPath}`;
    const resp = await HttpClientService.getWithRedirects(url, 8);
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
