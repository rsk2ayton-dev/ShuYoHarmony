import { rcp } from '@kit.RemoteCommunicationKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { ShuYoConstants } from '../core/ShuYoConstants';
import { PreferencesService } from './PreferencesService';
import { JsonHelpers } from './JsonHelpers';

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
    const raw = PreferencesService.getString(ShuYoCookieJar.storageKey, '');
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
    PreferencesService.setString(ShuYoCookieJar.storageKey, JSON.stringify(ShuYoCookieJar.entries));
  }

  static clearAll(): void {
    ShuYoCookieJar.entries = [];
    ShuYoCookieJar.loaded = true;
    PreferencesService.remove(ShuYoCookieJar.storageKey);
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
        continue;
      }
      const rawPath = rc.path !== undefined ? rc.path.trim() : '';
      const path = rawPath.startsWith('/') ? rawPath : fallbackPath;
      const val = rc.value !== undefined ? rc.value : '';
      const expired = (rc.maxAge !== undefined && rc.maxAge <= 0) || val.length === 0 || val === 'deleteMe';
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
            } else {
              domainValid = false;
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

  static defaultCookiePath(url: string): string {
    const path = HttpClientService.extractPath(url);
    const lastSlash = path.lastIndexOf('/');
    return lastSlash > 0 ? path.substring(0, lastSlash) : '/';
  }

  static isShuHost(host: string): boolean {
    const normalized = host.toLowerCase();
    return normalized === 'shu.edu.cn' || normalized.endsWith('.shu.edu.cn');
  }

  static upgradeShuHttpUrl(rawUrl: string): string {
    if (!rawUrl.startsWith('http://')) {
      return rawUrl;
    }
    const host = HttpClientService.extractHost(rawUrl);
    if (HttpClientService.isShuHost(host)) {
      return 'https://' + rawUrl.substring(7);
    }
    return rawUrl;
  }

  static resolveUrl(baseUrl: string, relativeOrAbs: string): string {
    const trimmed = relativeOrAbs.trim();
    if (trimmed.length === 0) {
      return HttpClientService.upgradeShuHttpUrl(baseUrl);
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return HttpClientService.upgradeShuHttpUrl(trimmed);
    }
    const schemeEnd = baseUrl.indexOf('://');
    if (schemeEnd < 0) {
      return HttpClientService.upgradeShuHttpUrl(trimmed);
    }
    const scheme = baseUrl.substring(0, schemeEnd);
    if (trimmed.startsWith('//')) {
      return HttpClientService.upgradeShuHttpUrl(`${scheme}:${trimmed}`);
    }
    const origin = HttpClientService.extractOrigin(baseUrl);
    if (trimmed.startsWith('/')) {
      return HttpClientService.upgradeShuHttpUrl(origin + trimmed);
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
      return HttpClientService.upgradeShuHttpUrl(baseUrl.substring(0, cut) + trimmed);
    }
    const basePath = HttpClientService.extractPath(baseUrl);
    const lastSlash = basePath.lastIndexOf('/');
    const baseDir = lastSlash >= 0 ? basePath.substring(0, lastSlash + 1) : '/';
    return HttpClientService.upgradeShuHttpUrl(`${origin}${baseDir}${trimmed}`);
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
    const cookieStr = ShuYoCookieJar.headerFor(targetUrl);
    if (cookieStr.length > 0) {
      headerMap['cookie'] = cookieStr;
    }
    if (extraHeaders !== undefined) {
      const keys = Object.keys(extraHeaders);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        headerMap[k.toLowerCase()] = extraHeaders[k];
      }
    }
    const reqHeaders = headerMap as rcp.RequestHeaders;
    const reqContent: string | undefined = body !== undefined
      ? body
      : (method === http.RequestMethod.POST ? '' : undefined);
    const req = new rcp.Request(targetUrl, HttpClientService.toRcpMethod(method), reqHeaders, reqContent);

    try {
      const resp = await session.fetch(req);
      if (resp.cookies !== undefined && resp.cookies.length > 0) {
        ShuYoCookieJar.saveFromRcpCookies(targetUrl, resp.cookies);
      } else {
        const rawHdrs = resp.headers as Record<string, string | string[] | undefined>;
        const setCookieVal = rawHdrs['set-cookie'];
        if (Array.isArray(setCookieVal)) {
          ShuYoCookieJar.saveFromSetCookieHeaders(targetUrl, setCookieVal);
        } else if (typeof setCookieVal === 'string' && setCookieVal.length > 0) {
          ShuYoCookieJar.saveFromSetCookieHeaders(targetUrl, [setCookieVal]);
        }
      }

      const rawHdrs = resp.headers as Record<string, string | string[] | undefined>;
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
    let lastResult: ShuYoHttpResult = {
      statusCode: 0,
      body: '',
      headers: {},
      location: current
    };
    for (let i = 0; i <= maxRedirects; i++) {
      lastResult = await HttpClientService.request(http.RequestMethod.GET, current, extraHeaders);
      if (lastResult.statusCode >= 300 && lastResult.statusCode < 400 && lastResult.location.length > 0) {
        current = HttpClientService.resolveUrl(current, lastResult.location);
      } else {
        lastResult.location = current;
        return lastResult;
      }
    }
    lastResult.location = current;
    return lastResult;
  }
}
