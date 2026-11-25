import { describe, it, expect } from '@ohos/hypium';
import { WebVpnProtocol } from '../main/ets/services/WebVpnProtocol';

export default function webVpnProtocolTest(): void {
  describe('WebVpnProtocolTest', () => {
    it('canonicalSsoUrlRewritesAllLegacyAndProxyHosts', 0, () => {
      const legacy = WebVpnProtocol.canonicalSsoUrl(
        'https://oauth.shu.edu.cn/oauth/authorize?client_id=test&state=abc'
      );
      expect(legacy).assertEqual('https://newsso.shu.edu.cn/oauth/authorize?client_id=test&state=abc');

      const oauthProxy = WebVpnProtocol.canonicalSsoUrl(
        'https://https-oauth-shu-edu-cn-443.webvpn.shu.edu.cn/oauth/authorize?response_type=code'
      );
      expect(oauthProxy).assertEqual('https://newsso.shu.edu.cn/oauth/authorize?response_type=code');

      const newssoProxy = WebVpnProtocol.canonicalSsoUrl(
        'http://https-newsso-shu-edu-cn-443.webvpn.shu.edu.cn/oauth2/login/ctx123'
      );
      expect(newssoProxy).assertEqual('https://newsso.shu.edu.cn/oauth2/login/ctx123');

      const unrelated = WebVpnProtocol.canonicalSsoUrl('https://https-there-shu-edu-cn-443.webvpn.shu.edu.cn/api/v3/my/profile');
      expect(unrelated).assertEqual('https://https-there-shu-edu-cn-443.webvpn.shu.edu.cn/api/v3/my/profile');
    });

    it('remapWebVpnCookieDomainMapsProxiedHostsSafely', 0, () => {
      expect(
        WebVpnProtocol.remapWebVpnCookieDomain('https-there-shu-edu-cn-443.webvpn.shu.edu.cn', '.shu.edu.cn')
      ).assertEqual('https-there-shu-edu-cn-443.webvpn.shu.edu.cn');

      expect(
        WebVpnProtocol.remapWebVpnCookieDomain('https-there-shu-edu-cn-443.webvpn.shu.edu.cn', 'there.shu.edu.cn')
      ).assertEqual('https-there-shu-edu-cn-443.webvpn.shu.edu.cn');

      expect(
        WebVpnProtocol.remapWebVpnCookieDomain('https-classroom-cc-shu-edu-cn-443.webvpn.shu.edu.cn', 'classroom.cc.shu.edu.cn')
      ).assertEqual('https-classroom-cc-shu-edu-cn-443.webvpn.shu.edu.cn');

      expect(
        WebVpnProtocol.remapWebVpnCookieDomain('https-there-shu-edu-cn-443.webvpn.shu.edu.cn', 'evil.com')
      ).assertEqual('');

      expect(
        WebVpnProtocol.remapWebVpnCookieDomain('there.shu.edu.cn', 'there.shu.edu.cn')
      ).assertEqual('');
    });

    it('buildGatewayCookieHeaderAttachesTokenOnlyToProxiedHosts', 0, () => {
      const proxiedEmpty = WebVpnProtocol.buildGatewayCookieHeader(
        'https://https-there-shu-edu-cn-443.webvpn.shu.edu.cn/api/v3/my/profile',
        '',
        'TOKEN_123'
      );
      expect(proxiedEmpty).assertEqual('webvpn-token=TOKEN_123');

      const proxiedWithSession = WebVpnProtocol.buildGatewayCookieHeader(
        'https://https-classroom-cc-shu-edu-cn-443.webvpn.shu.edu.cn/course/findSection',
        'JSESSIONID=ABC',
        'TOKEN_123'
      );
      expect(proxiedWithSession).assertEqual('webvpn-token=TOKEN_123; JSESSIONID=ABC');

      const proxiedAlreadyHas = WebVpnProtocol.buildGatewayCookieHeader(
        'https://https-otp-shu-edu-cn-443.webvpn.shu.edu.cn/Default.aspx',
        'webvpn-token=EXISTING; ASP.NET_SessionId=XYZ',
        'TOKEN_123'
      );
      expect(proxiedAlreadyHas).assertEqual('webvpn-token=EXISTING; ASP.NET_SessionId=XYZ');

      const directHost = WebVpnProtocol.buildGatewayCookieHeader(
        'https://newsso.shu.edu.cn/oauth/authorize',
        'SHU_OAUTH2=DIRECT',
        'TOKEN_123'
      );
      expect(directHost).assertEqual('SHU_OAUTH2=DIRECT');
    });

    it('parsesAnonymizedGatewayHandshakePayloads', 0, () => {
      const authListJson = '{"code":0,"data":{"list":[{"authType":1,"externalId":"other"},{"authType":5,"externalId":"YJrvSXWl"}]}}';
      expect(WebVpnProtocol.pickSchoolSsoExternalId(authListJson)).assertEqual('YJrvSXWl');

      const startJson = '{"code":0,"data":{"action":{"login_url":"https://https-oauth-shu-edu-cn-443.webvpn.shu.edu.cn/oauth/authorize?client_id=c1"}}}';
      expect(WebVpnProtocol.extractStartLoginUrl(startJson)).assertEqual(
        'https://https-oauth-shu-edu-cn-443.webvpn.shu.edu.cn/oauth/authorize?client_id=c1'
      );

      const cb = WebVpnProtocol.parseCallbackParams(
        'https://webvpn.shu.edu.cn/callback/oauth2?code=CODE_XYZ&state=STATE_ABC'
      );
      expect(cb.isCallback).assertTrue();
      expect(cb.code).assertEqual('CODE_XYZ');
      expect(cb.state).assertEqual('STATE_ABC');

      expect(WebVpnProtocol.parseUserInfoUserId(200, '{"code":0,"data":{"userId":"24120001"}}')).assertEqual('24120001');
      expect(WebVpnProtocol.parseUserInfoUserId(200, '{"code":0,"data":{"userId":"0"}}')).assertEqual('');
      expect(WebVpnProtocol.isWebVpnPortalRedirect(302, 'https://webvpn.shu.edu.cn/auth/login')).assertTrue();
      expect(WebVpnProtocol.isWebVpnPortalRedirect(200, 'https://webvpn.shu.edu.cn/auth/login')).assertFalse();
    });
  });
}
