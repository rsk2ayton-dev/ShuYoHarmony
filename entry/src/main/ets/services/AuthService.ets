import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { ShuYoConstants } from '../core/ShuYoConstants';
import { RsaEncryptor } from '../core/RsaEncryptor';
import { ShuYoCampusSystem } from '../models/ShuYoModels';
import { HttpClientService, ShuYoCookieJar, ShuYoHttpResult } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';

export interface ShuYoTwoStepMethod {
  key: string;
  label: string;
  hint: string;
}

export interface ShuYoLoginOutcome {
  success: boolean;
  requiresTwoStep: boolean;
  twoStepMethods: ShuYoTwoStepMethod[];
  message: string;
  studentId: string;
}

export interface ShuYoSendCodeResult {
  success: boolean;
  message: string;
}

export interface ShuYoWeComQrSession {
  key: string;
  confirmUrl: string;
  state: string;
  graduateAuthorizeUri: string;
}

export interface ShuYoWeComPollResult {
  status: string; // 'waiting' | 'confirmed' | 'succeeded' | 'expired' | 'error'
  authCode: string;
  message: string;
}

export interface ShuYoWeComRedeemResult {
  success: boolean;
  studentId: string;
  message: string;
}

interface ShuYoLoginDiscovery {
  loginUri: string;
  params: string;
  callbackUri: string;
}

export class AuthService {
  private static readonly newssoLoginMarker: string = '/oauth2/login/';
  private static readonly ssoHost: string = 'newsso.shu.edu.cn';
  private static readonly maxRedirects: number = 16;
  private static readonly graduateCallbackPrefix: string = '/gsapp/sys/yjsrzfwapp/oauth_shu/callback/';
  private static readonly graduatePortalUrl: string =
    'https://yjs.shu.edu.cn/gsapp/sys/yjsemaphome/portal/index.do';
  private static readonly graduateUserInfoUrl: string =
    'https://yjs.shu.edu.cn/gsapp/sys/yjsemaphome/modules/pubWork/getUserInfo.do';

  private static pendingLoginUri: string = '';
  private static pendingOrigin: string = '';
  private static pendingParams: string = '';
  private static pendingUsername: string = '';
  private static pendingEncryptedPassword: string = '';
  private static pendingCampusSystem: ShuYoCampusSystem = ShuYoCampusSystem.UNDERGRADUATE;
  private static pendingGraduateAuthorizeUri: string = '';

  static clearPendingChallenge(): void {
    AuthService.pendingLoginUri = '';
    AuthService.pendingOrigin = '';
    AuthService.pendingParams = '';
    AuthService.pendingUsername = '';
    AuthService.pendingEncryptedPassword = '';
    AuthService.pendingCampusSystem = ShuYoCampusSystem.UNDERGRADUATE;
    AuthService.pendingGraduateAuthorizeUri = '';
  }

  static canonicalSsoUrl(rawUrl: string): string {
    const upgraded = HttpClientService.upgradeShuHttpUrl(rawUrl);
    const host = HttpClientService.extractHost(upgraded).toLowerCase();
    const path = HttpClientService.extractPath(upgraded);
    const isLegacyHost = host === 'oauth.shu.edu.cn' ||
      host === 'https-newsso-shu-edu-cn-443.webvpn.shu.edu.cn';
    if (isLegacyHost && (path.startsWith('/oauth/') || path.startsWith('/oauth2/'))) {
      const origin = HttpClientService.extractOrigin(upgraded);
      return ShuYoConstants.ssoBaseUrl + upgraded.substring(origin.length);
    }
    return upgraded;
  }

  static extractQueryParam(rawUrl: string, paramName: string): string {
    const qIdx = rawUrl.indexOf('?');
    if (qIdx < 0) {
      return '';
    }
    const hashIdx = rawUrl.indexOf('#', qIdx);
    const query = hashIdx >= 0 ? rawUrl.substring(qIdx + 1, hashIdx) : rawUrl.substring(qIdx + 1);
    const pairs = query.split('&');
    for (let i = 0; i < pairs.length; i++) {
      const pair = pairs[i];
      const eqIdx = pair.indexOf('=');
      if (eqIdx <= 0) {
        continue;
      }
      try {
        const key = decodeURIComponent(pair.substring(0, eqIdx));
        if (key === paramName) {
          const rawVal = pair.substring(eqIdx + 1).replace(new RegExp('\\+', 'g'), ' ');
          return decodeURIComponent(rawVal);
        }
      } catch (_err) {
        // Ignore malformed query parameter encoding
      }
    }
    return '';
  }

  static isAuthorizedCallback(rawUrl: string): boolean {
    return AuthService.extractQueryParam(rawUrl, 'code').length > 0;
  }

  static extractAcademicStudentId(html: string): string {
    const inputRegex = new RegExp('<input\\b[^>]*>', 'gi');
    let match = inputRegex.exec(html);
    while (match !== null) {
      const tag = match[0];
      if (new RegExp('id\\s*=\\s*["\']sessionUserKey["\']', 'i').test(tag)) {
        const valMatch = new RegExp('value\\s*=\\s*["\']([^"\']*)["\']', 'i').exec(tag);
        if (valMatch !== null && valMatch.length > 1) {
          const val = valMatch[1].trim();
          if (new RegExp('^[A-Za-z0-9]{4,24}$').test(val)) {
            return val;
          }
        }
      }
      match = inputRegex.exec(html);
    }
    return '';
  }

  static isTicketLoginUrl(rawUrl: string): boolean {
    const host = HttpClientService.extractHost(rawUrl).toLowerCase();
    const path = HttpClientService.extractPath(rawUrl);
    return host === ShuYoConstants.jwxtHost && path.endsWith('/jwglxt/ticketlogin');
  }

  static isAcademicSessionUrl(rawUrl: string): boolean {
    const host = HttpClientService.extractHost(rawUrl).toLowerCase();
    const path = HttpClientService.extractPath(rawUrl);
    return host === ShuYoConstants.jwxtHost &&
      path.startsWith('/jwglxt/') &&
      !path.endsWith('/jwglxt/ticketlogin') &&
      !path.endsWith('/jwglxt/xtgl/login_slogin.html');
  }

  static mapSsoErrorCode(code: string): string {
    if (code === 'badPassword') {
      return '学号或密码错误，请检查后重试';
    }
    if (code === 'userNotFound') {
      return '未找到该账号，请确认学号或工号';
    }
    if (code === 'invalidCode') {
      return '验证码错误或已过期，请重新输入';
    }
    if (code === 'userLocked') {
      return '账号已被锁定，请稍后重试';
    }
    if (code === 'ipLimitExceeded') {
      return '登录请求过于频繁，请稍后重试';
    }
    if (code === 'sendError' || code === 'senderror') {
      return '验证码发送过于频繁，请切换验证方式或稍后再试';
    }
    if (code === 'userNotAllowed') {
      return '当前账号无权登录该服务';
    }
    if (code === 'internalServerError') {
      return '学校统一认证服务暂时不可用';
    }
    return code.length > 0 ? `认证失败（${code}）` : '统一身份认证失败，请稍后重试';
  }

  private static requireNewSsoSuccess(resp: ShuYoHttpResult): Record<string, Object> {
    const json = JsonHelpers.parseObject(resp.body);
    if (json === undefined) {
      throw new Error(`学校认证服务返回异常内容（HTTP ${resp.statusCode}）`);
    }
    const msgCode = JsonHelpers.str(json, 'message');
    if (resp.statusCode < 200 || resp.statusCode >= 300 || msgCode !== 'success') {
      throw new Error(AuthService.mapSsoErrorCode(msgCode.length > 0 ? msgCode : `http${resp.statusCode}`));
    }
    return json;
  }

  private static async discoverLoginEntry(campusSystem: ShuYoCampusSystem): Promise<ShuYoLoginDiscovery> {
    let current = campusSystem === ShuYoCampusSystem.GRADUATE
      ? `${ShuYoConstants.yjsBaseUrl}/`
      : `${ShuYoConstants.jwxtBaseUrl}/`;

    for (let i = 0; i < AuthService.maxRedirects; i++) {
      current = HttpClientService.upgradeShuHttpUrl(current);
      if (campusSystem === ShuYoCampusSystem.GRADUATE) {
        const host = HttpClientService.extractHost(current).toLowerCase();
        const path = HttpClientService.extractPath(current);
        if (host === AuthService.ssoHost && path === '/oauth/authorize') {
          AuthService.pendingGraduateAuthorizeUri = current;
        }
      }

      const headers: Record<string, string> = {
        'Accept': 'application/json, text/plain, */*'
      };
      const resp = await HttpClientService.request(http.RequestMethod.GET, current, headers);
      const hasRedirect = resp.statusCode >= 300 && resp.statusCode < 400 && resp.location.length > 0;
      let nextUrl = hasRedirect ? HttpClientService.resolveUrl(current, resp.location) : '';
      if (hasRedirect && campusSystem === ShuYoCampusSystem.GRADUATE) {
        nextUrl = AuthService.canonicalSsoUrl(nextUrl);
      }

      if (campusSystem === ShuYoCampusSystem.GRADUATE && hasRedirect) {
        const nextHost = HttpClientService.extractHost(nextUrl).toLowerCase();
        const nextPath = HttpClientService.extractPath(nextUrl);
        if (nextHost === ShuYoConstants.yjsHost &&
          nextPath.startsWith(AuthService.graduateCallbackPrefix) &&
          AuthService.isAuthorizedCallback(nextUrl)) {
          return { loginUri: '', params: '', callbackUri: nextUrl };
        }
      }

      if (!hasRedirect) {
        if (HttpClientService.extractPath(current).includes(AuthService.newssoLoginMarker)) {
          const canonical = AuthService.canonicalSsoUrl(current);
          const params = AuthService.extractParamsFromUrl(canonical);
          if (params.length > 0) {
            return { loginUri: canonical, params: params, callbackUri: '' };
          }
        }
        throw new Error('无法取得上海大学统一身份认证入口，请检查网络连接后重试');
      }

      if (HttpClientService.extractPath(nextUrl).includes(AuthService.newssoLoginMarker)) {
        const directLogin = AuthService.canonicalSsoUrl(nextUrl);
        const pageResp = await HttpClientService.request(http.RequestMethod.GET, directLogin, {
          'Accept': 'application/json, text/plain, */*'
        });
        const pageHasRedirect = pageResp.statusCode >= 300 &&
          pageResp.statusCode < 400 &&
          pageResp.location.length > 0;
        const pageRedirect = pageHasRedirect
          ? AuthService.canonicalSsoUrl(HttpClientService.resolveUrl(directLogin, pageResp.location))
          : '';
        if (pageRedirect.length > 0 && AuthService.isAuthorizedCallback(pageRedirect)) {
          return { loginUri: '', params: '', callbackUri: pageRedirect };
        }
        const targetLogin = pageRedirect.includes(AuthService.newssoLoginMarker) ? pageRedirect : directLogin;
        const params = AuthService.extractParamsFromUrl(targetLogin);
        if (params.length === 0) {
          throw new Error('统一认证地址缺少登录参数');
        }
        return { loginUri: targetLogin, params: params, callbackUri: '' };
      }

      current = nextUrl;
    }

    throw new Error('统一身份认证入口跳转次数过多');
  }

  private static validateShuUrl(targetUrl: string): void {
    if (!targetUrl.startsWith('https://')) {
      throw new Error('认证服务返回了不安全的跳转地址');
    }
    const host = HttpClientService.extractHost(targetUrl).toLowerCase();
    if (!HttpClientService.isShuHost(host)) {
      throw new Error('认证服务返回了非上海大学的跳转地址');
    }
  }

  private static buildTwoStepMethods(methodsObj: Record<string, Object> | undefined): ShuYoTwoStepMethod[] {
    if (methodsObj === undefined) {
      return [];
    }
    const out: ShuYoTwoStepMethod[] = [];
    const wecomRaw = methodsObj['wecom'];
    if (wecomRaw !== undefined && wecomRaw !== null) {
      out.push({
        key: 'wecom',
        label: '企业微信',
        hint: String(wecomRaw)
      });
    }
    const smsRaw = methodsObj['sms'];
    if (smsRaw !== undefined && smsRaw !== null) {
      out.push({
        key: 'sms',
        label: '短信验证码',
        hint: String(smsRaw)
      });
    }
    const keys = Object.keys(methodsObj);
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      if (k !== 'wecom' && k !== 'sms') {
        const val = methodsObj[k];
        out.push({
          key: k,
          label: k,
          hint: val !== undefined && val !== null ? String(val) : ''
        });
      }
    }
    return out;
  }

  private static async completePostSsoLogin(
    callbackUri: string,
    refererUri: string,
    campusSystem: ShuYoCampusSystem,
    fallbackStudentId: string
  ): Promise<string> {
    if (campusSystem === ShuYoCampusSystem.GRADUATE) {
      return AuthService.completeGraduateLogin(callbackUri, refererUri, fallbackStudentId);
    }
    return AuthService.completeAcademicLogin(callbackUri, refererUri, fallbackStudentId);
  }

  private static async completeAcademicLogin(
    callbackUri: string,
    refererUri: string,
    fallbackStudentId: string
  ): Promise<string> {
    let current = AuthService.canonicalSsoUrl(HttpClientService.upgradeShuHttpUrl(callbackUri));
    let ticketReloaded = false;
    let lastBody = '';
    let referer = refererUri;

    for (let i = 0; i < AuthService.maxRedirects; i++) {
      AuthService.validateShuUrl(current);
      const headers: Record<string, string> = {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      };
      if (referer.length > 0) {
        headers['Referer'] = referer;
      }
      const resp = await HttpClientService.request(http.RequestMethod.GET, current, headers);
      lastBody = resp.body;
      const hasRedirect = resp.statusCode >= 300 && resp.statusCode < 400 && resp.location.length > 0;
      if (hasRedirect) {
        referer = current;
        current = AuthService.canonicalSsoUrl(HttpClientService.resolveUrl(current, resp.location));
        if (current.includes(AuthService.newssoLoginMarker)) {
          throw new Error('教务系统单点登录未能完成，请重试');
        }
        continue;
      }

      if (!ticketReloaded && AuthService.isTicketLoginUrl(current)) {
        ticketReloaded = true;
        referer = current;
        current = `${ShuYoConstants.jwxtBaseUrl}/jwglxt/xtgl/index_initMenu.html?jsdm=xs&_t=${Date.now()}&echarts=1`;
        continue;
      }

      if (!AuthService.isAcademicSessionUrl(current)) {
        throw new Error('教务系统登录未完成，请重试');
      }

      let verifiedId = AuthService.extractAcademicStudentId(lastBody);
      if (verifiedId.length === 0) {
        const identityUrl = `${ShuYoConstants.jwxtBaseUrl}/jwglxt/xtgl/index_initMenu.html?jsdm=xs&echarts=1`;
        const idResp = await HttpClientService.request(http.RequestMethod.GET, identityUrl, {
          'Accept': 'text/html,application/xhtml+xml',
          'Referer': current
        });
        verifiedId = AuthService.extractAcademicStudentId(idResp.body);
      }
      if (verifiedId.length === 0) {
        throw new Error('未能确认本科生教务登录账号，请重新登录');
      }
      return verifiedId;
    }

    if (fallbackStudentId.length > 0) {
      throw new Error('教务系统登录跳转次数过多');
    }
    throw new Error('教务系统登录跳转次数过多');
  }

  private static async completeGraduateLogin(
    callbackUri: string,
    refererUri: string,
    fallbackStudentId: string
  ): Promise<string> {
    let current = AuthService.canonicalSsoUrl(HttpClientService.upgradeShuHttpUrl(callbackUri));
    let referer = refererUri;

    for (let i = 0; i < AuthService.maxRedirects; i++) {
      AuthService.validateShuUrl(current);
      const headers: Record<string, string> = {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      };
      if (referer.length > 0) {
        headers['Referer'] = referer;
      }
      const resp = await HttpClientService.request(http.RequestMethod.GET, current, headers);
      const hasRedirect = resp.statusCode >= 300 && resp.statusCode < 400 && resp.location.length > 0;
      const nextUrl = hasRedirect
        ? AuthService.canonicalSsoUrl(HttpClientService.resolveUrl(current, resp.location))
        : '';

      if (current.includes(AuthService.newssoLoginMarker) ||
        nextUrl.includes(AuthService.newssoLoginMarker) ||
        resp.statusCode === 401) {
        throw new Error('研究生系统统一认证未能完成，请重新登录');
      }

      if (hasRedirect) {
        referer = current;
        current = nextUrl;
        continue;
      }

      if (resp.statusCode === 200 &&
        HttpClientService.extractHost(current).toLowerCase() === ShuYoConstants.yjsHost &&
        ShuYoCookieJar.hasCookie(AuthService.graduateUserInfoUrl, 'GS_SESSIONID')) {
        const infoResp = await HttpClientService.request(
          http.RequestMethod.POST,
          AuthService.graduateUserInfoUrl,
          {
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'Referer': AuthService.graduatePortalUrl,
            'Origin': ShuYoConstants.yjsBaseUrl,
            'X-Requested-With': 'XMLHttpRequest'
          }
        );
        const infoJson = JsonHelpers.parseObject(infoResp.body);
        const codeStr = JsonHelpers.str(infoJson, 'code');
        const dataObj = infoJson !== undefined ? JsonHelpers.asObject(infoJson['data']) : undefined;
        const userId = JsonHelpers.str(dataObj, 'userId').trim();
        if ((codeStr === '0') && userId.length > 0) {
          return userId;
        }
        throw new Error('未能确认研究生系统登录账号，请重新登录');
      }

      throw new Error('未能确认研究生系统会话，请稍后重试');
    }

    if (fallbackStudentId.length > 0) {
      throw new Error('研究生系统登录跳转次数过多');
    }
    throw new Error('研究生系统登录跳转次数过多');
  }

  static async loginWithCredentials(
    username: string,
    password: string,
    campusSystem: ShuYoCampusSystem
  ): Promise<ShuYoLoginOutcome> {
    const trimmedUser = username.trim();
    if (trimmedUser.length === 0 || password.length === 0) {
      return {
        success: false,
        requiresTwoStep: false,
        twoStepMethods: [],
        message: '请输入学号和密码',
        studentId: ''
      };
    }

    try {
      AuthService.clearPendingChallenge();
      ShuYoCookieJar.clearAll();
      AuthService.pendingCampusSystem = campusSystem;

      const discovery = await AuthService.discoverLoginEntry(campusSystem);
      if (discovery.callbackUri.length > 0) {
        const verifiedId = await AuthService.completePostSsoLogin(
          discovery.callbackUri,
          discovery.loginUri,
          campusSystem,
          trimmedUser
        );
        return {
          success: true,
          requiresTwoStep: false,
          twoStepMethods: [],
          message: '登录成功',
          studentId: verifiedId
        };
      }

      const encrypted = RsaEncryptor.encryptPassword(password);
      const origin = HttpClientService.extractOrigin(discovery.loginUri);
      const postUrl = `${origin}/oauth/userLogin`;
      const payload: Record<string, string> = {
        'username': trimmedUser,
        'password': encrypted,
        'tenantId': ShuYoConstants.tenantId,
        'params': discovery.params
      };
      const reqHeaders: Record<string, string> = {
        'Content-Type': 'application/json; charset=UTF-8',
        'Accept': 'application/json, text/plain, */*',
        'Referer': discovery.loginUri,
        'Origin': origin
      };
      const resp = await HttpClientService.request(
        http.RequestMethod.POST,
        postUrl,
        reqHeaders,
        JSON.stringify(payload)
      );
      const json = AuthService.requireNewSsoSuccess(resp);

      const twoStep = JsonHelpers.bool(json, 'twoStepRequired', false);
      if (twoStep) {
        const methodsObj = JsonHelpers.asObject(json['twoStepMethods']);
        const methods = AuthService.buildTwoStepMethods(methodsObj);
        if (methods.length === 0) {
          throw new Error('学校未返回可用的二次验证方式');
        }
        AuthService.pendingLoginUri = discovery.loginUri;
        AuthService.pendingOrigin = origin;
        AuthService.pendingParams = discovery.params;
        AuthService.pendingUsername = trimmedUser;
        AuthService.pendingEncryptedPassword = encrypted;
        AuthService.pendingCampusSystem = campusSystem;
        return {
          success: false,
          requiresTwoStep: true,
          twoStepMethods: methods,
          message: '需要进行二次身份验证',
          studentId: trimmedUser
        };
      }

      const rawRedirect = JsonHelpers.str(json, 'redirectUri', JsonHelpers.str(json, 'redirectUrl', ''));
      const redirectTarget = rawRedirect.length > 0
        ? AuthService.canonicalSsoUrl(HttpClientService.resolveUrl(discovery.loginUri, rawRedirect))
        : AuthService.pendingGraduateAuthorizeUri;
      if (redirectTarget.length === 0) {
        throw new Error('登录成功，但学校未返回系统授权地址');
      }

      const verifiedId = await AuthService.completePostSsoLogin(
        redirectTarget,
        discovery.loginUri,
        campusSystem,
        trimmedUser
      );
      AuthService.clearPendingChallenge();
      return {
        success: true,
        requiresTwoStep: false,
        twoStepMethods: [],
        message: '登录成功',
        studentId: verifiedId
      };
    } catch (err) {
      const e = err as Error;
      return {
        success: false,
        requiresTwoStep: false,
        twoStepMethods: [],
        message: e.message.length > 0 ? e.message : '无法连接学校认证服务，请稍后再试',
        studentId: ''
      };
    }
  }

  static async sendTwoStepCode(method: string): Promise<ShuYoSendCodeResult> {
    if (AuthService.pendingLoginUri.length === 0 || AuthService.pendingOrigin.length === 0) {
      return {
        success: false,
        message: '二次验证会话已失效，请重新登录'
      };
    }
    try {
      const sendUrl = `${AuthService.pendingOrigin}/oauth/twoStep/send`;
      const payload: Record<string, string> = {
        'method': method
      };
      const headers: Record<string, string> = {
        'Content-Type': 'application/json; charset=UTF-8',
        'Accept': 'application/json, text/plain, */*',
        'Referer': AuthService.pendingLoginUri,
        'Origin': AuthService.pendingOrigin
      };
      const resp = await HttpClientService.request(
        http.RequestMethod.POST,
        sendUrl,
        headers,
        JSON.stringify(payload)
      );
      AuthService.requireNewSsoSuccess(resp);
      return {
        success: true,
        message: method === 'wecom' ? '验证码已发送至企业微信，请查收' : '短信验证码已发送至绑定手机'
      };
    } catch (err) {
      const e = err as Error;
      return {
        success: false,
        message: e.message.length > 0 ? e.message : '验证码发送失败，请稍后重试'
      };
    }
  }

  static async verifyTwoStepCode(method: string, code: string): Promise<ShuYoLoginOutcome> {
    const trimmedCode = code.trim();
    if (trimmedCode.length === 0) {
      return {
        success: false,
        requiresTwoStep: true,
        twoStepMethods: [],
        message: '请输入验证码',
        studentId: ''
      };
    }
    if (AuthService.pendingLoginUri.length === 0 || AuthService.pendingParams.length === 0) {
      return {
        success: false,
        requiresTwoStep: false,
        twoStepMethods: [],
        message: '二次验证会话已过期，请重新登录',
        studentId: ''
      };
    }

    try {
      const verifyUrl = `${AuthService.pendingOrigin}/oauth/twoStep/verify`;
      const payload: Record<string, string> = {
        'username': AuthService.pendingUsername,
        'password': AuthService.pendingEncryptedPassword,
        'tenantId': ShuYoConstants.tenantId,
        'params': AuthService.pendingParams,
        'code': trimmedCode,
        'method': method
      };
      const reqHeaders: Record<string, string> = {
        'Content-Type': 'application/json; charset=UTF-8',
        'Accept': 'application/json, text/plain, */*',
        'Referer': AuthService.pendingLoginUri,
        'Origin': AuthService.pendingOrigin
      };
      const resp = await HttpClientService.request(
        http.RequestMethod.POST,
        verifyUrl,
        reqHeaders,
        JSON.stringify(payload)
      );
      const json = AuthService.requireNewSsoSuccess(resp);

      const rawRedirect = JsonHelpers.str(json, 'redirectUri', JsonHelpers.str(json, 'redirectUrl', ''));
      const redirectTarget = rawRedirect.length > 0
        ? AuthService.canonicalSsoUrl(HttpClientService.resolveUrl(AuthService.pendingLoginUri, rawRedirect))
        : AuthService.pendingGraduateAuthorizeUri;
      if (redirectTarget.length === 0) {
        throw new Error('验证成功，但学校未返回授权地址');
      }

      const verifiedId = await AuthService.completePostSsoLogin(
        redirectTarget,
        AuthService.pendingLoginUri,
        AuthService.pendingCampusSystem,
        AuthService.pendingUsername
      );
      AuthService.clearPendingChallenge();
      return {
        success: true,
        requiresTwoStep: false,
        twoStepMethods: [],
        message: '验证成功',
        studentId: verifiedId
      };
    } catch (err) {
      const e = err as Error;
      return {
        success: false,
        requiresTwoStep: true,
        twoStepMethods: [],
        message: e.message.length > 0 ? e.message : '验证失败，请稍后重试',
        studentId: ''
      };
    }
  }

  static encodeOAuthParams(params: Record<string, string>): string {
    const json = JSON.stringify(params);
    const encoder = new util.TextEncoder();
    const bytes = encoder.encodeInto(json);
    const base64Helper = new util.Base64Helper();
    const b64 = base64Helper.encodeToStringSync(bytes);
    return b64.replace(new RegExp('\\+', 'g'), '-')
      .replace(new RegExp('/', 'g'), '_')
      .replace(new RegExp('=', 'g'), '');
  }

  static async startWeComQrSession(campusSystem: ShuYoCampusSystem): Promise<ShuYoWeComQrSession> {
    ShuYoCookieJar.clearAll();
    AuthService.clearPendingChallenge();
    let state = '';
    let graduateAuthorizeUri = '';
    if (campusSystem === ShuYoCampusSystem.GRADUATE) {
      const discovery = await AuthService.discoverLoginEntry(ShuYoCampusSystem.GRADUATE);
      state = discovery.params;
      graduateAuthorizeUri = AuthService.pendingGraduateAuthorizeUri;
    } else {
      const stateObj: Record<string, string> = {
        'responseType': 'code',
        'clientId': ShuYoConstants.targetAcademic.clientId,
        'clientName': ShuYoConstants.targetAcademic.clientName,
        'scope': ShuYoConstants.targetAcademic.scope,
        'redirectUri': ShuYoConstants.targetAcademic.redirectUri,
        'state': ''
      };
      state = AuthService.encodeOAuthParams(stateObj);
    }

    const url =
      `${ShuYoConstants.weComQrConnectBase}?appid=${ShuYoConstants.weComAppId}` +
      `&agentid=${ShuYoConstants.weComAgentId}` +
      `&redirect_uri=${encodeURIComponent(ShuYoConstants.weComRedirectUri)}` +
      `&state=${encodeURIComponent(state)}&lang=zh&version=1.2.7&login_type=jssdk`;
    const resp = await HttpClientService.request(http.RequestMethod.GET, url);
    const match = new RegExp('qrImg\\?key=([0-9a-fA-F]+)').exec(resp.body);
    if (match === null || match.length < 2) {
      throw new Error('无法获取企业微信登录二维码');
    }
    const key = match[1];
    const confirmUrl = `${ShuYoConstants.weComConfirmBase}?k=${encodeURIComponent(key)}&notretry=yes`;
    return {
      key: key,
      confirmUrl: confirmUrl,
      state: state,
      graduateAuthorizeUri: graduateAuthorizeUri
    };
  }

  static async pollWeComQrStatus(key: string): Promise<ShuYoWeComPollResult> {
    const url =
      `${ShuYoConstants.weComLongPollBase}?callback=jsonpCallback&key=${encodeURIComponent(key)}` +
      `&redirect_uri=${encodeURIComponent(ShuYoConstants.weComRedirectUri)}&lastStatus=&_=${Date.now()}`;
    const headers: Record<string, string> = {
      'Referer': ShuYoConstants.weComQrConnectBase
    };
    const resp = await HttpClientService.request(http.RequestMethod.GET, url, headers, undefined, 15000);
    const jsonpMatch = new RegExp('jsonpCallback\\((\\{.*?\\})\\)').exec(resp.body);
    if (jsonpMatch === null || jsonpMatch.length < 2) {
      return { status: 'waiting', authCode: '', message: '等待扫码' };
    }
    const obj = JsonHelpers.parseObject(jsonpMatch[1]);
    if (obj === undefined) {
      return { status: 'waiting', authCode: '', message: '等待扫码' };
    }
    const statusStr = JsonHelpers.str(obj, 'status', '');
    if (statusStr === 'QRCODE_SCAN_SUCC') {
      const authCode = JsonHelpers.str(obj, 'auth_code', '');
      return { status: 'succeeded', authCode: authCode, message: '扫码确认成功' };
    }
    if (statusStr === 'QRCODE_SCAN_ING') {
      return { status: 'confirmed', authCode: '', message: '已扫码，请在企业微信确认登录' };
    }
    if (statusStr === 'QRCODE_SCAN_FAIL' || statusStr === 'QRCODE_SCAN_ERR') {
      return { status: 'expired', authCode: '', message: '二维码已过期' };
    }
    return { status: 'waiting', authCode: '', message: '等待手机扫描二维码' };
  }

  static async redeemWeComAuthCode(
    session: ShuYoWeComQrSession,
    authCode: string,
    campusSystem: ShuYoCampusSystem
  ): Promise<ShuYoWeComRedeemResult> {
    try {
      const redeemUrl =
        `${ShuYoConstants.weComRedirectUri}?code=${encodeURIComponent(authCode)}` +
        `&state=${encodeURIComponent(session.state)}&appid=${ShuYoConstants.weComAppId}`;
      const redeemResp = await HttpClientService.request(http.RequestMethod.GET, redeemUrl, {
        'Accept': 'application/json, text/plain, */*'
      });
      if (redeemResp.statusCode < 300 ||
        redeemResp.statusCode >= 400 ||
        redeemResp.location.includes('wecomAuthFailed')) {
        return {
          success: false,
          studentId: '',
          message: `企业微信授权失败（HTTP ${redeemResp.statusCode}）`
        };
      }

      if (campusSystem === ShuYoCampusSystem.GRADUATE) {
        const redirectTarget = AuthService.canonicalSsoUrl(
          HttpClientService.resolveUrl(redeemUrl, redeemResp.location)
        );
        const startTarget = redirectTarget.includes(AuthService.graduateCallbackPrefix)
          ? redirectTarget
          : (session.graduateAuthorizeUri.length > 0 ? session.graduateAuthorizeUri : redirectTarget);
        const verifiedId = await AuthService.completeGraduateLogin(startTarget, redeemUrl, '');
        return {
          success: true,
          studentId: verifiedId,
          message: '扫码登录成功'
        };
      }

      const authUrl =
        `${ShuYoConstants.ssoBaseUrl}/oauth/authorize?response_type=code` +
        `&client_id=${encodeURIComponent(ShuYoConstants.targetAcademic.clientId)}` +
        `&redirect_uri=${encodeURIComponent(ShuYoConstants.targetAcademic.redirectUri)}` +
        `&scope=${encodeURIComponent(ShuYoConstants.targetAcademic.scope)}` +
        `&state=${encodeURIComponent(session.state)}`;
      const authResp = await HttpClientService.request(http.RequestMethod.GET, authUrl, {
        'Accept': 'application/json, text/plain, */*'
      });
      if (authResp.statusCode < 300 ||
        authResp.statusCode >= 400 ||
        authResp.location.length === 0 ||
        authResp.location.includes(AuthService.newssoLoginMarker)) {
        return {
          success: false,
          studentId: '',
          message: '企业微信会话未能复用，请重试'
        };
      }
      const callbackUri = AuthService.canonicalSsoUrl(HttpClientService.resolveUrl(authUrl, authResp.location));
      const verifiedId = await AuthService.completeAcademicLogin(callbackUri, authUrl, '');
      return {
        success: true,
        studentId: verifiedId,
        message: '扫码登录成功'
      };
    } catch (err) {
      const e = err as Error;
      return {
        success: false,
        studentId: '',
        message: e.message.length > 0 ? e.message : '换取校园会话失败'
      };
    }
  }

  private static extractParamsFromUrl(url: string): string {
    const marker = AuthService.newssoLoginMarker;
    const idx = url.indexOf(marker);
    if (idx < 0) {
      return '';
    }
    const rest = url.substring(idx + marker.length);
    const qIdx = rest.indexOf('?');
    const seg = qIdx >= 0 ? rest.substring(0, qIdx) : rest;
    const slashIdx = seg.indexOf('/');
    return slashIdx >= 0 ? seg.substring(0, slashIdx) : seg;
  }
}
