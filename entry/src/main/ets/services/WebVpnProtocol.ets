import { ShuYoConstants } from '../core/ShuYoConstants';
import { JsonHelpers } from './JsonHelpers';

export interface ShuYoWebVpnCallbackParams {
  isCallback: boolean;
  code: string;
  state: string;
}

/**
 * Pure URL, Cookie, and gateway payload helpers for SHU WebVPN.
 * Kept free of `@kit.*` imports so offline Hypium Local Tests can run it directly.
 */
export class WebVpnProtocol {
  private static readonly webVpnHostSuffix: string = '.webvpn.shu.edu.cn';
  private static readonly legacySsoHost: string = 'oauth.shu.edu.cn';
  private static readonly webVpnOauthProxyHost: string = 'https-oauth-shu-edu-cn-443.webvpn.shu.edu.cn';

  static extractHost(url: string): string {
    const schemeIdx = url.indexOf('://');
    if (schemeIdx < 0) {
      return '';
    }
    const rest = url.substring(schemeIdx + 3);
    const slashIdx = rest.indexOf('/');
    const qIdx = rest.indexOf('?');
    let endIdx = rest.length;
    if (slashIdx >= 0 && slashIdx < endIdx) {
      endIdx = slashIdx;
    }
    if (qIdx >= 0 && qIdx < endIdx) {
      endIdx = qIdx;
    }
    const hostPort = rest.substring(0, endIdx);
    const atIdx = hostPort.indexOf('@');
    const cleanHostPort = atIdx >= 0 ? hostPort.substring(atIdx + 1) : hostPort;
    const colonIdx = cleanHostPort.indexOf(':');
    return colonIdx >= 0 ? cleanHostPort.substring(0, colonIdx) : cleanHostPort;
  }

  static extractPath(url: string): string {
    const schemeIdx = url.indexOf('://');
    if (schemeIdx < 0) {
      return '/';
    }
    const rest = url.substring(schemeIdx + 3);
    const slashIdx = rest.indexOf('/');
    if (slashIdx < 0) {
      return '/';
    }
    const pathQuery = rest.substring(slashIdx);
    const qIdx = pathQuery.indexOf('?');
    const hashIdx = pathQuery.indexOf('#');
    let endIdx = pathQuery.length;
    if (qIdx >= 0 && qIdx < endIdx) {
      endIdx = qIdx;
    }
    if (hashIdx >= 0 && hashIdx < endIdx) {
      endIdx = hashIdx;
    }
    const path = pathQuery.substring(0, endIdx);
    return path.length > 0 ? path : '/';
  }

  static extractOrigin(url: string): string {
    const schemeIdx = url.indexOf('://');
    if (schemeIdx < 0) {
      return ShuYoConstants.ssoBaseUrl;
    }
    const slashIdx = url.indexOf('/', schemeIdx + 3);
    const qIdx = url.indexOf('?', schemeIdx + 3);
    let endIdx = url.length;
    if (slashIdx >= 0 && slashIdx < endIdx) {
      endIdx = slashIdx;
    }
    if (qIdx >= 0 && qIdx < endIdx) {
      endIdx = qIdx;
    }
    return url.substring(0, endIdx);
  }

  static isShuHost(host: string): boolean {
    const normalized = host.toLowerCase();
    return normalized === 'shu.edu.cn' || normalized.endsWith('.shu.edu.cn');
  }

  static isWebVpnProxiedHost(host: string): boolean {
    return host.trim().toLowerCase().endsWith(WebVpnProtocol.webVpnHostSuffix);
  }

  static isWebVpnPortalHost(host: string): boolean {
    const h = host.trim().toLowerCase();
    return h === 'webvpn.shu.edu.cn' || h === 'www.webvpn.shu.edu.cn';
  }

  static isWebVpnPortalRedirect(statusCode: number, location: string): boolean {
    if (statusCode < 300 || statusCode >= 400 || location.length === 0) {
      return false;
    }
    return WebVpnProtocol.isWebVpnPortalHost(WebVpnProtocol.extractHost(location));
  }

  static upgradeShuHttpUrl(rawUrl: string): string {
    if (!rawUrl.startsWith('http://')) {
      return rawUrl;
    }
    const host = WebVpnProtocol.extractHost(rawUrl);
    if (WebVpnProtocol.isShuHost(host)) {
      return 'https://' + rawUrl.substring(7);
    }
    return rawUrl;
  }

  private static normalizePathWithSuffix(rawPathWithSuffix: string): string {
    const qIdx = rawPathWithSuffix.indexOf('?');
    const hashIdx = rawPathWithSuffix.indexOf('#');
    let splitIdx = rawPathWithSuffix.length;
    if (qIdx >= 0 && qIdx < splitIdx) {
      splitIdx = qIdx;
    }
    if (hashIdx >= 0 && hashIdx < splitIdx) {
      splitIdx = hashIdx;
    }
    const pathPart = rawPathWithSuffix.substring(0, splitIdx);
    const suffix = rawPathWithSuffix.substring(splitIdx);
    const hasTrailingSlash = pathPart.endsWith('/');
    const rawSegments = pathPart.split('/');
    const stack: string[] = [];
    for (let i = 0; i < rawSegments.length; i++) {
      const seg = rawSegments[i];
      if (seg.length === 0 || seg === '.') {
        continue;
      }
      if (seg === '..') {
        if (stack.length > 0) {
          stack.pop();
        }
      } else {
        stack.push(seg);
      }
    }
    let normalizedPath = '/' + stack.join('/');
    if (hasTrailingSlash && stack.length > 0 && !normalizedPath.endsWith('/')) {
      normalizedPath += '/';
    }
    return normalizedPath + suffix;
  }

  static resolveUrl(baseUrl: string, relativeOrAbs: string): string {
    const trimmed = relativeOrAbs.trim();
    if (trimmed.length === 0) {
      return WebVpnProtocol.upgradeShuHttpUrl(baseUrl);
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return WebVpnProtocol.upgradeShuHttpUrl(trimmed);
    }
    const schemeEnd = baseUrl.indexOf('://');
    if (schemeEnd < 0) {
      return WebVpnProtocol.upgradeShuHttpUrl(trimmed);
    }
    const scheme = baseUrl.substring(0, schemeEnd);
    if (trimmed.startsWith('//')) {
      return WebVpnProtocol.upgradeShuHttpUrl(`${scheme}:${trimmed}`);
    }
    const origin = WebVpnProtocol.extractOrigin(baseUrl);
    if (trimmed.startsWith('/')) {
      const normRootPath = WebVpnProtocol.normalizePathWithSuffix(trimmed);
      return WebVpnProtocol.upgradeShuHttpUrl(origin + normRootPath);
    }
    if (trimmed.startsWith('?')) {
      const qIdx = baseUrl.indexOf('?');
      const hashIdx = baseUrl.indexOf('#');
      let cut = baseUrl.length;
      if (qIdx >= 0 && qIdx < cut) {
        cut = qIdx;
      }
      if (hashIdx >= 0 && hashIdx < cut) {
        cut = hashIdx;
      }
      return WebVpnProtocol.upgradeShuHttpUrl(baseUrl.substring(0, cut) + trimmed);
    }
    const basePath = WebVpnProtocol.extractPath(baseUrl);
    const lastSlash = basePath.lastIndexOf('/');
    const baseDir = lastSlash >= 0 ? basePath.substring(0, lastSlash + 1) : '/';
    const normJoined = WebVpnProtocol.normalizePathWithSuffix(`${baseDir}${trimmed}`);
    return WebVpnProtocol.upgradeShuHttpUrl(`${origin}${normJoined}`);
  }

  /**
   * Mirrors upstream `AcademicNativeAuthService.canonicalSsoUri` so the
   * host-scoped `SHU_OAUTH2` cookie on `newsso.shu.edu.cn` is reused cleanly.
   */
  static canonicalSsoUrl(rawUrl: string): string {
    const upgraded = WebVpnProtocol.upgradeShuHttpUrl(rawUrl.trim());
    const host = WebVpnProtocol.extractHost(upgraded).toLowerCase();
    const path = WebVpnProtocol.extractPath(upgraded);
    const isSsoAlias = host === WebVpnProtocol.legacySsoHost ||
      host === WebVpnProtocol.webVpnOauthProxyHost ||
      host === ShuYoConstants.webVpnNewssoProxyHost;
    if (isSsoAlias && (path.startsWith('/oauth/') || path.startsWith('/oauth2/'))) {
      const origin = WebVpnProtocol.extractOrigin(upgraded);
      return `${ShuYoConstants.ssoBaseUrl}${upgraded.substring(origin.length)}`;
    }
    return upgraded;
  }

  static remapWebVpnCookieDomain(requestHost: string, cookieDomain: string): string {
    const hostLower = requestHost.trim().toLowerCase();
    if (!hostLower.endsWith(WebVpnProtocol.webVpnHostSuffix)) {
      return '';
    }
    let dashedProxy = hostLower.substring(0, hostLower.length - WebVpnProtocol.webVpnHostSuffix.length);
    if (dashedProxy.startsWith('https-')) {
      dashedProxy = dashedProxy.substring(6);
    } else if (dashedProxy.startsWith('http-')) {
      dashedProxy = dashedProxy.substring(5);
    }
    dashedProxy = dashedProxy.replace(new RegExp('-\\d+$'), '');
    let cleanCookie = cookieDomain.trim().toLowerCase();
    if (cleanCookie.startsWith('.')) {
      cleanCookie = cleanCookie.substring(1);
    }
    if (cleanCookie.length === 0 || dashedProxy.length === 0) {
      return '';
    }
    const dashedCookie = cleanCookie.replace(new RegExp('\\.', 'g'), '-');
    if (dashedProxy === dashedCookie || dashedProxy.endsWith(`-${dashedCookie}`)) {
      return hostLower;
    }
    return '';
  }

  /**
   * Attaches `webvpn-token` only to proxied `*.webvpn.shu.edu.cn` hosts so
   * the gateway authenticates requests without leaking the token to direct hosts.
   */
  static buildGatewayCookieHeader(requestUrl: string, existingCookieHeader: string, portalToken: string): string {
    const cleanExisting = existingCookieHeader.trim();
    const token = portalToken.trim();
    if (token.length === 0) {
      return cleanExisting;
    }
    const host = WebVpnProtocol.extractHost(requestUrl).toLowerCase();
    if (!WebVpnProtocol.isWebVpnProxiedHost(host)) {
      return cleanExisting;
    }
    const parts = cleanExisting.length > 0 ? cleanExisting.split(';') : [];
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].trim().startsWith('webvpn-token=')) {
        return cleanExisting;
      }
    }
    return cleanExisting.length > 0
      ? `webvpn-token=${token}; ${cleanExisting}`
      : `webvpn-token=${token}`;
  }

  static queryParam(url: string, name: string): string {
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
      let key = '';
      try {
        key = decodeURIComponent(parts[i].substring(0, eq));
      } catch (_err) {
        key = parts[i].substring(0, eq);
      }
      if (key !== name) {
        continue;
      }
      const value = parts[i].substring(eq + 1).replace(new RegExp('\\+', 'g'), ' ');
      try {
        return decodeURIComponent(value);
      } catch (_err) {
        return value;
      }
    }
    return '';
  }

  static pickSchoolSsoExternalId(body: string): string {
    const obj = JsonHelpers.parseObject(body);
    if (obj === undefined || JsonHelpers.num(obj, 'code', -1) !== 0) {
      return '';
    }
    const data = JsonHelpers.asObject(obj['data']);
    const list = JsonHelpers.asArray(data !== undefined ? data['list'] : undefined);
    for (let i = 0; i < list.length; i++) {
      const item = JsonHelpers.asObject(list[i]);
      if (item !== undefined && JsonHelpers.num(item, 'authType', -1) === 5) {
        const ext = JsonHelpers.str(item, 'externalId', '').trim();
        if (ext.length > 0) {
          return ext;
        }
      }
    }
    return '';
  }

  static extractStartLoginUrl(body: string): string {
    const obj = JsonHelpers.parseObject(body);
    if (obj === undefined || JsonHelpers.num(obj, 'code', -1) !== 0) {
      return '';
    }
    const data = JsonHelpers.asObject(obj['data']);
    const action = JsonHelpers.asObject(data !== undefined ? data['action'] : undefined);
    return JsonHelpers.str(action, 'login_url', '').trim();
  }

  static parseCallbackParams(url: string): ShuYoWebVpnCallbackParams {
    const host = WebVpnProtocol.extractHost(url).toLowerCase();
    const path = WebVpnProtocol.extractPath(url);
    const code = WebVpnProtocol.queryParam(url, 'code').trim();
    const state = WebVpnProtocol.queryParam(url, 'state').trim();
    const isCallback = host === 'webvpn.shu.edu.cn' &&
      path === ShuYoConstants.webVpnCallbackPath &&
      code.length > 0 &&
      state.length > 0;
    return {
      isCallback: isCallback,
      code: code,
      state: state
    };
  }

  static parseUserInfoUserId(statusCode: number, body: string): string {
    if (statusCode !== 200) {
      return '';
    }
    const obj = JsonHelpers.parseObject(body);
    if (obj === undefined || JsonHelpers.num(obj, 'code', -1) !== 0) {
      return '';
    }
    const data = JsonHelpers.asObject(obj['data']);
    const userId = JsonHelpers.str(data, 'userId', '').trim();
    return userId.length > 0 && userId !== '0' ? userId : '';
  }
}
