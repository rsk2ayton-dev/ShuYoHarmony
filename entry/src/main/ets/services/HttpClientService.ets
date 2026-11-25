import { rcp } from '@kit.RemoteCommunicationKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { ShuYoConstants } from '../core/ShuYoConstants';
import { SecureStorageService } from './SecureStorageService';
import { JsonHelpers } from './JsonHelpers';
import { WebVpnProtocol } from './WebVpnProtocol';

export interface ShuYoHttpResult {
  statusCode: number;
  body: string;
  headers: Record<string, string>;
  location: string;
}

export interface ShuYoStoredCookie {
  name: string;
  value: string;
  domain: string;
  path: string;
}

export class ShuYoCookieJar {
  private static readonly storageKey: string = 'shuyo_cookie_jar_v1';
  private static entries: ShuYoStoredCookie[] = [];
  private static loaded: boolean = false;

  static ensureLoaded(): void {
    if (ShuYoCookieJar.loaded) {
      return;
    }
    ShuYoCookieJar.loaded = true;
    const raw = SecureStorageService.getString(ShuYoCookieJar.storageKey, '');
    if (raw.length === 0) {
      return;
    }
    const list = JsonHelpers.parseArray(raw);
    const out: ShuYoStoredCookie[] = [];
    for (let i = 0; i < list.length; i++) {
      const obj = JsonHelpers.asObject(list[i]);
      if (obj === undefined) {
        continue;
      }
      const name = JsonHelpers.str(obj, 'name');
      const val = JsonHelpers.str(obj, 'value');
      const domain = JsonHelpers.str(obj, 'domain');
      const path = JsonHelpers.str(obj, 'path', '/');
      if (name.length > 0 && domain.length > 0 && val.length > 0) {
        out.push({ name: name, value: val, domain: domain, path: path });
      }
    }
    ShuYoCookieJar.entries = out;
  }

  static persist(): void {
    SecureStorageService.setString(ShuYoCookieJar.storageKey, JSON.stringify(ShuYoCookieJar.entries));
  }

  static clearAll(): void {
    ShuYoCookieJar.entries = [];
    ShuYoCookieJar.loaded = true;
    SecureStorageService.remove(ShuYoCookieJar.storageKey);
  }

  static clearDomain(domain: string): void {
    ShuYoCookieJar.ensureLoaded();
    const target = domain.toLowerCase();
    const next: ShuYoStoredCookie[] = [];
    for (let i = 0; i < ShuYoCookieJar.entries.length; i++) {
      const item = ShuYoCookieJar.entries[i];
      if (!ShuYoCookieJar.domainMatches(target, item.domain)) {
        next.push(item);
      }
    }
    ShuYoCookieJar.entries = next;
    ShuYoCookieJar.persist();
  }

  private static upsertCookieInMemory(cookie: ShuYoStoredCookie, expired: boolean): void {
    const next: ShuYoStoredCookie[] = [];
    for (let i = 0; i < ShuYoCookieJar.entries.length; i++) {
      const item = ShuYoCookieJar.entries[i];
      if (item.name === cookie.name && item.domain === cookie.domain && item.path === cookie.path) {
        continue;
      }
      next.push(item);
    }
    if (!expired && cookie.value.length > 0 && cookie.value !== 'deleteMe') {
      next.push(cookie);
    }
    ShuYoCookieJar.entries = next;
  }

  static setCookie(cookie: ShuYoStoredCookie): void {
    ShuYoCookieJar.ensureLoaded();
    ShuYoCookieJar.upsertCookieInMemory(cookie, false);
    ShuYoCookieJar.persist();
  }

  static saveFromRcpCookies(url: string, cookies: rcp.ResponseCookie[]): void {
    const host = HttpClientService.extractHost(url).toLowerCase();
    if (host.length === 0 || cookies.length === 0) {
      return;
    }
    ShuYoCookieJar.ensureLoaded();
    const fallbackPath = host === ShuYoConstants.yjsHost
      ? HttpClientService.defaultCookiePath(url)
      : '/';

    for (let i = 0; i < cookies.length; i++) {
      const rc = cookies[i];
      const name = rc.name.trim();
      if (name.length === 0) {
        continue;
      }
      let domain = rc.domain !== undefined ? rc.domain.trim().toLowerCase() : '';
      if (domain.startsWith('.')) {
        domain = domain.substring(1);
      }
      if (domain.length === 0) {
        domain = host;
      } else if (!ShuYoCookieJar.domainMatches(host, domain)) {
        const remapped = ShuYoCookieJar.remapWebVpnCookieDomain(host, domain);
        if (remapped.length > 0) {
          domain = remapped;
        } else {
          continue;
        }
      }
      const rawPath = rc.path !== undefined ? rc.path.trim() : '';
      const path = rawPath.startsWith('/') ? rawPath : fallbackPath;
      const val = rc.value !== undefined ? rc.value : '';
      const expired = (rc.maxAge !== undefined && rc.maxAge < 0) || val.length === 0 || val === 'deleteMe';
      ShuYoCookieJar.upsertCookieInMemory({
        name: name,
        value: val,
        domain: domain,
        path: path
      }, expired);
    }
    ShuYoCookieJar.persist();
  }

  static saveFromSetCookieHeaders(url: string, setCookies: string[]): void {
    const host = HttpClientService.extractHost(url).toLowerCase();
    if (host.length === 0 || setCookies.length === 0) {
      return;
    }
    ShuYoCookieJar.ensureLoaded();
    const fallbackPath = host === ShuYoConstants.yjsHost
      ? HttpClientService.defaultCookiePath(url)
      : '/';

    for (let i = 0; i < setCookies.length; i++) {
      const line = setCookies[i];
      const parts = line.split(';');
      if (parts.length === 0) {
        continue;
      }
      const pair = parts[0].trim();
      const eqIdx = pair.indexOf('=');
      if (eqIdx <= 0) {
        continue;
      }
      const name = pair.substring(0, eqIdx).trim();
      const val = pair.substring(eqIdx + 1).trim();
      let domain = host;
      let path = fallbackPath;
      let expired = val.length === 0 || val === 'deleteMe';
      let domainValid = true;

      for (let j = 1; j < parts.length; j++) {
        const attr = parts[j].trim();
        const attrLower = attr.toLowerCase();
        if (attrLower.startsWith('domain=')) {
          let d = attr.substring(7).trim().toLowerCase();
          if (d.startsWith('.')) {
            d = d.substring(1);
          }
          if (d.length > 0) {
            if (ShuYoCookieJar.domainMatches(host, d)) {
              domain = d;
              domainValid = true;
            } else {
              const remapped = ShuYoCookieJar.remapWebVpnCookieDomain(host, d);
              if (remapped.length > 0) {
                domain = remapped;
                domainValid = true;
              } else {
                domainValid = false;
              }
            }
          }
        } else if (attrLower.startsWith('path=')) {
          const p = attr.substring(5).trim();
          if (p.startsWith('/')) {
            path = p;
          }
        } else if (attrLower.startsWith('max-age=')) {
          const maxAgeNum = parseInt(attr.substring(8).trim(), 10);
          if (Number.isFinite(maxAgeNum) && maxAgeNum <= 0) {
            expired = true;
          }
        }
      }

      if (!domainValid || name.length === 0) {
        continue;
      }
      ShuYoCookieJar.upsertCookieInMemory({
        name: name,
        value: val,
        domain: domain,
        path: path
      }, expired);
    }
    ShuYoCookieJar.persist();
  }

  private static matchingCookies(url: string): ShuYoStoredCookie[] {
    ShuYoCookieJar.ensureLoaded();
    const host = HttpClientService.extractHost(url).toLowerCase();
    const path = HttpClientService.extractPath(url);
    const matched: ShuYoStoredCookie[] = [];
    for (let i = 0; i < ShuYoCookieJar.entries.length; i++) {
      const c = ShuYoCookieJar.entries[i];
      if (ShuYoCookieJar.domainMatches(host, c.domain) && ShuYoCookieJar.pathMatches(path, c.path)) {
        matched.push(c);
      }
    }
    matched.sort((a: ShuYoStoredCookie, b: ShuYoStoredCookie): number => {
      if (b.path.length !== a.path.length) {
        return b.path.length - a.path.length;
      }
      return b.domain.length - a.domain.length;
    });
    return matched;
  }

  static hasCookie(url: string, name: string): boolean {
    return ShuYoCookieJar.getCookieValue(url, name).length > 0;
  }

  static getCookieValue(url: string, name: string): string {
    const matched = ShuYoCookieJar.matchingCookies(url);
    for (let i = 0; i < matched.length; i++) {
      if (matched[i].name === name && matched[i].value.length > 0) {
        return matched[i].value;
      }
    }
    return '';
  }

  static headerFor(url: string): string {
    const matched = ShuYoCookieJar.matchingCookies(url);
    const seen = new Set<string>();
    const pairs: string[] = [];
    for (let i = 0; i < matched.length; i++) {
      const c = matched[i];
      if (!seen.has(c.name) && c.value.length > 0) {
        seen.add(c.name);
        pairs.push(`${c.name}=${c.value}`);
      }
    }
    return pairs.join('; ');
  }

  private static domainMatches(host: string, cookieDomain: string): boolean {
    const d = cookieDomain.toLowerCase();
    return host === d || host.endsWith('.' + d);
  }

  private static remapWebVpnCookieDomain(requestHost: string, cookieDomain: string): string {
    return WebVpnProtocol.remapWebVpnCookieDomain(requestHost, cookieDomain);
  }

  private static pathMatches(requestPath: string, cookiePath: string): boolean {
    const reqP = requestPath.length > 0 ? requestPath : '/';
    const cp = cookiePath.length > 0 ? cookiePath : '/';
    if (cp === '/' || reqP === cp) {
      return true;
    }
    const prefix = cp.endsWith('/') ? cp : cp + '/';
    return reqP.startsWith(prefix);
  }
}

export class HttpClientService {
  static extractHost(url: string): string {
    return WebVpnProtocol.extractHost(url);
  }

  static extractPath(url: string): string {
    return WebVpnProtocol.extractPath(url);
  }

  static extractOrigin(url: string): string {
    return WebVpnProtocol.extractOrigin(url);
  }

  static defaultCookiePath(url: string): string {
    const path = HttpClientService.extractPath(url);
    const lastSlash = path.lastIndexOf('/');
    return lastSlash > 0 ? path.substring(0, lastSlash) : '/';
  }

  static isShuHost(host: string): boolean {
    return WebVpnProtocol.isShuHost(host);
  }

  static upgradeShuHttpUrl(rawUrl: string): string {
    return WebVpnProtocol.upgradeShuHttpUrl(rawUrl);
  }

  static resolveUrl(baseUrl: string, relativeOrAbs: string): string {
    return WebVpnProtocol.resolveUrl(baseUrl, relativeOrAbs);
  }

  private static toRcpMethod(method: http.RequestMethod): rcp.HttpMethod {
    if (method === http.RequestMethod.POST) {
      return 'POST';
    }
    if (method === http.RequestMethod.PUT) {
      return 'PUT';
    }
    if (method === http.RequestMethod.DELETE) {
      return 'DELETE';
    }
    if (method === http.RequestMethod.HEAD) {
      return 'HEAD';
    }
    if (method === http.RequestMethod.OPTIONS) {
      return 'OPTIONS';
    }
    return 'GET';
  }

  private static decodeResponseBody(resp: rcp.Response): string {
    const str = resp.toString();
    if (str !== null) {
      return str;
    }
    if (resp.body !== undefined) {
      try {
        const decoder = util.TextDecoder.create('utf-8');
        return decoder.decodeToString(new Uint8Array(resp.body));
      } catch (_err) {
        return '';
      }
    }
    return '';
  }

  static async request(
    method: http.RequestMethod,
    url: string,
    extraHeaders?: Record<string, string>,
    body?: string,
    timeoutMs: number = 15000
  ): Promise<ShuYoHttpResult> {
    const targetUrl = HttpClientService.upgradeShuHttpUrl(url);
    const timeoutCfg: rcp.Timeout = {
      connectMs: timeoutMs,
      transferMs: timeoutMs
    };
    const transferCfg: rcp.TransferConfiguration = {
      autoRedirect: false,
      timeout: timeoutCfg
    };
    const reqCfg: rcp.Configuration = {
      transfer: transferCfg
    };
    const sessionCfg: rcp.SessionConfiguration = {
      requestConfiguration: reqCfg
    };
    const session = rcp.createSession(sessionCfg);

    const headerMap: Record<string, string | string[] | undefined> = {};
    headerMap['user-agent'] = ShuYoConstants.userAgent;
    let cookieVal = ShuYoCookieJar.headerFor(targetUrl);
    if (extraHeaders !== undefined) {
      const keys = Object.keys(extraHeaders);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        const lowerK = k.toLowerCase();
        if (lowerK === 'cookie') {
          const overrideCookie = extraHeaders[k].trim();
          if (overrideCookie.length > 0) {
            cookieVal = overrideCookie;
          }
        } else {
          headerMap[lowerK] = extraHeaders[k];
        }
      }
    }
    const gatewayCookie = WebVpnProtocol.buildGatewayCookieHeader(
      targetUrl,
      cookieVal,
      ShuYoCookieJar.getCookieValue(ShuYoConstants.webVpnPortal, 'webvpn-token')
    );
    if (gatewayCookie.length > 0) {
      headerMap['cookie'] = gatewayCookie;
    }
    const reqHeaders = headerMap as rcp.RequestHeaders;
    const reqContent: string | undefined = body !== undefined
      ? body
      : (method === http.RequestMethod.POST ? '' : undefined);
    const req = new rcp.Request(targetUrl, HttpClientService.toRcpMethod(method), reqHeaders, reqContent);

    try {
      const resp = await session.fetch(req);
      const rawHdrs = resp.headers as Record<string, string | string[] | undefined>;
      const setCookieVal = rawHdrs['set-cookie'];
      if (Array.isArray(setCookieVal) && setCookieVal.length > 0) {
        ShuYoCookieJar.saveFromSetCookieHeaders(targetUrl, setCookieVal);
      } else if (typeof setCookieVal === 'string' && setCookieVal.length > 0) {
        ShuYoCookieJar.saveFromSetCookieHeaders(targetUrl, [setCookieVal]);
      } else if (resp.cookies !== undefined && resp.cookies.length > 0) {
        ShuYoCookieJar.saveFromRcpCookies(targetUrl, resp.cookies);
      }

      const normalizedHeaders: Record<string, string> = {};
      let location = '';
      const hKeys = Object.keys(rawHdrs);
      for (let i = 0; i < hKeys.length; i++) {
        const hk = hKeys[i];
        const hv = rawHdrs[hk];
        const lowerK = hk.toLowerCase();
        if (lowerK === 'set-cookie') {
          continue;
        }
        if (typeof hv === 'string') {
          normalizedHeaders[lowerK] = hv;
          if (lowerK === 'location') {
            location = hv;
          }
        } else if (Array.isArray(hv) && hv.length > 0) {
          normalizedHeaders[lowerK] = hv.join(', ');
          if (lowerK === 'location') {
            location = hv[0];
          }
        }
      }

      const bodyStr = HttpClientService.decodeResponseBody(resp);
      return {
        statusCode: resp.statusCode,
        body: bodyStr,
        headers: normalizedHeaders,
        location: location
      };
    } finally {
      try {
        session.close();
      } catch (_closeErr) {
        // Ignore close failure
      }
    }
  }

  static async getWithRedirects(
    url: string,
    maxRedirects: number = 12,
    extraHeaders?: Record<string, string>
  ): Promise<ShuYoHttpResult> {
    let current = HttpClientService.upgradeShuHttpUrl(url);
    const startedProxied = WebVpnProtocol.isWebVpnProxiedHost(HttpClientService.extractHost(current));
    let lastResult: ShuYoHttpResult = {
      statusCode: 0,
      body: '',
      headers: {},
      location: current
    };
    for (let i = 0; i <= maxRedirects; i++) {
      lastResult = await HttpClientService.request(http.RequestMethod.GET, current, extraHeaders);
      if (lastResult.statusCode >= 300 && lastResult.statusCode < 400 && lastResult.location.length > 0) {
        const nextUrl = HttpClientService.resolveUrl(current, lastResult.location);
        if (startedProxied && WebVpnProtocol.isWebVpnPortalRedirect(lastResult.statusCode, nextUrl)) {
          lastResult.location = nextUrl;
          return lastResult;
        }
        current = nextUrl;
      } else {
        lastResult.location = current;
        return lastResult;
      }
    }
    lastResult.location = current;
    return lastResult;
  }
}
