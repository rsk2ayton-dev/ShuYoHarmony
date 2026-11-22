export interface ShuYoClassPeriod {
  period: number;
  startTime: string;
  endTime: string;
}

export interface ShuYoWeComOAuthTarget {
  kind: string;
  clientId: string;
  clientName: string;
  scope: string;
  redirectUri: string;
  generateState: boolean;
}

export class ShuYoConstants {
  static readonly appVersion: string = '0.5.1';
  static readonly buildNumber: number = 23;
  static readonly bundleName: string = 'com.rsk2ayton.shuyo.harmony';
  static readonly userAgent: string =
    'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static readonly jwxtBaseUrl: string = 'https://jwxt.shu.edu.cn';
  static readonly jwxtHost: string = 'jwxt.shu.edu.cn';
  static readonly jwxtScheduleIndexPath: string =
    '/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151&layout=default';
  static readonly jwxtScheduleDataPath: string =
    '/jwglxt/kbcx/xskbcx_cxXsgrkb.html?gnmkdm=N2151';

  static readonly yjsHost: string = 'yjs.shu.edu.cn';
  static readonly yjsBaseUrl: string = 'https://yjs.shu.edu.cn';

  static readonly ssoBaseUrl: string = 'https://newsso.shu.edu.cn';
  static readonly tenantId: string = '上海大学';

  static readonly webVpnPortal: string = 'https://webvpn.shu.edu.cn';
  static readonly webVpnUserInfo: string = 'https://webvpn.shu.edu.cn/api/access/user/info';
  static readonly webVpnCallback: string = 'https://webvpn.shu.edu.cn/callback/oauth2';

  static readonly classroomDirectHost: string = 'classroom.cc.shu.edu.cn';
  static readonly classroomDirectBase: string = 'https://classroom.cc.shu.edu.cn';
  static readonly classroomWebVpnHost: string =
    'https-classroom-cc-shu-edu-cn-443.webvpn.shu.edu.cn';
  static readonly classroomWebVpnBase: string =
    'https://https-classroom-cc-shu-edu-cn-443.webvpn.shu.edu.cn';

  static readonly otpDirectHost: string = 'otp.shu.edu.cn';
  static readonly otpWebVpnHost: string = 'https-otp-shu-edu-cn-443.webvpn.shu.edu.cn';
  static readonly otpLandingPath: string = '/Default.aspx';

  static readonly eportalHost: string = 'eportal.shu.edu.cn';
  static readonly eportalBaseUrl: string = 'https://eportal.shu.edu.cn';

  static readonly thereBaseUrl: string = 'https://there.shu.edu.cn';
  static readonly clientBackendBaseUrl: string = 'https://api.shuyo.work';

  static readonly weComAppId: string = 'wxa8dea949443de641';
  static readonly weComAgentId: string = '1000059';
  static readonly weComRedirectUri: string = 'https://newsso.shu.edu.cn/oauth/wecom/qrcode';
  static readonly weComQrConnectBase: string = 'https://open.work.weixin.qq.com/wwopen/sso/qrConnect';
  static readonly weComConfirmBase: string = 'https://open.work.weixin.qq.com/wwopen/sso/confirm2';
  static readonly weComLongPollBase: string = 'https://open.work.weixin.qq.com/wwopen/sso/l/qrConnect';

  static readonly targetAcademic: ShuYoWeComOAuthTarget = {
    kind: 'academic',
    clientId: 'Km5t225E8KECKQ6ZDm5K2P6aS2459Cua',
    clientName: '本科生教务系统',
    scope: 'jw',
    redirectUri: 'https://jwxt.shu.edu.cn/sso/shulogin',
    generateState: true
  };

  static readonly targetWebVpn: ShuYoWeComOAuthTarget = {
    kind: 'webVpn',
    clientId: 'nn7sbb22j2tKE100T024tEp42777p755',
    clientName: 'WebVPN 访问控制系统',
    scope: '',
    redirectUri: 'https://webvpn.shu.edu.cn/callback/oauth2',
    generateState: false
  };

  static readonly weekdayLabels: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  static readonly classPeriods: ShuYoClassPeriod[] = [
    { period: 1, startTime: '08:00', endTime: '08:45' },
    { period: 2, startTime: '08:55', endTime: '09:40' },
    { period: 3, startTime: '10:00', endTime: '10:45' },
    { period: 4, startTime: '10:55', endTime: '11:40' },
    { period: 5, startTime: '13:00', endTime: '13:45' },
    { period: 6, startTime: '13:55', endTime: '14:40' },
    { period: 7, startTime: '15:00', endTime: '15:45' },
    { period: 8, startTime: '15:55', endTime: '16:40' },
    { period: 9, startTime: '18:00', endTime: '18:45' },
    { period: 10, startTime: '18:55', endTime: '19:40' },
    { period: 11, startTime: '20:00', endTime: '20:45' },
    { period: 12, startTime: '20:55', endTime: '21:40' }
  ];

  static getPeriodTimeText(startSec: number, endSec: number): string {
    if (startSec < 1 || startSec > ShuYoConstants.classPeriods.length) {
      return '';
    }
    const endIdx = Math.min(Math.max(endSec, startSec), ShuYoConstants.classPeriods.length);
    const start = ShuYoConstants.classPeriods[startSec - 1].startTime;
    const end = ShuYoConstants.classPeriods[endIdx - 1].endTime;
    return `${start}-${end}`;
  }

  static isClassroomExternalAccessOpen(): boolean {
    const now = new Date();
    const utcMs = now.getTime() + now.getTimezoneOffset() * 60000;
    const shanghaiHour = new Date(utcMs + 8 * 3600000).getHours();
    return shanghaiHour >= 7 && shanghaiHour < 23;
  }
}
