import { JsonHelpers } from './JsonHelpers';
import { WebVpnProtocol } from './WebVpnProtocol';

export interface ShuYoParsedBookingResponse {
  ok: boolean;
  bookingId: string;
  failureKind: 'none' | 'loginRequired' | 'business' | 'uncertain';
  message: string;
}

/**
 * Pure protocol helpers for SHU library booking (`there.shu.edu.cn` & `office.chaoxing.com`).
 * Zero `@kit.*` imports so offline Hypium Local Tests run directly.
 */
export class LibraryBookingProtocol {
  static extractThereSessionId(html: string): string | undefined {
    const m1 = new RegExp('\\bsessionId\\s*[=:]\\s*("(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\')').exec(html) ??
      new RegExp('["\']sessionId["\']\\s*:\\s*("(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\')').exec(html);
    if (m1 === null || m1[1] === undefined) {
      return undefined;
    }
    const literal = m1[1];
    let session = '';
    if (literal.startsWith('"')) {
      try {
        session = JSON.parse(literal) as string;
      } catch (_err) {
        return undefined;
      }
    } else if (literal.length >= 2) {
      session = literal.substring(1, literal.length - 1);
    } else {
      return undefined;
    }
    if (session.includes('\n') || session.includes('\r') || (session.length > 0 && session.trim().length === 0)) {
      return undefined;
    }
    return session;
  }

  static isThereAnonymousHtml(html: string): boolean {
    return new RegExp('["\']isAnonymous["\']\\s*:\\s*true').test(html);
  }

  static isWeChatRedirect(statusCode: number, location: string): boolean {
    if (statusCode < 300 || statusCode >= 400 || location.length === 0) {
      return false;
    }
    const host = WebVpnProtocol.extractHost(location).toLowerCase();
    return host === 'open.weixin.qq.com' ||
      host === 'weixin.qq.com' ||
      host === 'https-open-weixin-qq-com-443.webvpn.shu.edu.cn';
  }

  static normalizeThereRedirect(baseUrl: string, location: string): string {
    if (location.length === 0) {
      return '';
    }
    const resolved = WebVpnProtocol.resolveUrl(baseUrl, location);
    const host = WebVpnProtocol.extractHost(resolved).toLowerCase();
    const path = WebVpnProtocol.extractPath(resolved);
    const qIdx = resolved.indexOf('?');
    const querySuffix = qIdx >= 0 ? resolved.substring(qIdx) : '';
    if (host === 'there.shu.edu.cn' ||
      host === 'http-there-shu-edu-cn-80.webvpn.shu.edu.cn' ||
      host === 'https-there-shu-edu-cn-443.webvpn.shu.edu.cn') {
      return `${baseUrl}${path}${querySuffix}`;
    }
    return resolved;
  }

  static validateThereRoomBookable(
    rawRoom: Record<string, Object> | undefined,
    expectedAreaId: string
  ): boolean {
    if (rawRoom === undefined) {
      return false;
    }
    const areaId = JsonHelpers.str(rawRoom, 'officeAreaId', '').trim();
    if (areaId !== expectedAreaId) {
      return false;
    }
    if (JsonHelpers.bool(rawRoom, 'disabled', false) ||
      JsonHelpers.bool(rawRoom, 'isBusy', false) ||
      JsonHelpers.bool(rawRoom, 'isBooked', false)) {
      return false;
    }
    const abilities = JsonHelpers.strList(rawRoom, 'abilities');
    return abilities.includes('booking');
  }

  static buildThereBookingPayload(
    rawRoom: Record<string, Object>,
    userId: string,
    userName: string,
    day: string,
    startTime: string,
    endTime: string
  ): Record<string, Object> {
    const timeSlot: Record<string, Object> = {
      'startDate': day,
      'startTime': startTime,
      'endDate': day,
      'endTime': endTime
    };
    const roomsArr: Object[] = [rawRoom];
    const timesArr: Object[] = [timeSlot];
    const membersArr: Object[] = [userId];
    return {
      'rooms': roomsArr,
      'times': timesArr,
      'subject': userName,
      'meetingMembers': membersArr
    };
  }

  static parseThereBookingResponse(statusCode: number, body: string): ShuYoParsedBookingResponse {
    if (statusCode === 401 || statusCode === 403 || (statusCode >= 300 && statusCode < 400)) {
      return {
        ok: false,
        bookingId: '',
        failureKind: 'loginRequired',
        message: '图书馆预约登录状态已失效，请重新登录校园账号'
      };
    }
    if (statusCode !== 200) {
      return {
        ok: false,
        bookingId: '',
        failureKind: 'uncertain',
        message: `图书馆预约服务暂时不可用（HTTP ${statusCode}），请先查看我的预约确认`
      };
    }
    const obj = JsonHelpers.parseObject(body);
    if (obj === undefined) {
      return {
        ok: false,
        bookingId: '',
        failureKind: 'uncertain',
        message: '图书馆预约服务返回了无法识别的内容，请先查看我的预约'
      };
    }
    const code = JsonHelpers.num(obj, 'code', -1);
    if (code !== 0) {
      const warnMsg = JsonHelpers.str(obj, 'warnMessage', '').trim();
      const msg = JsonHelpers.str(obj, 'message', '').trim();
      const noticeMsg = JsonHelpers.str(obj, 'noticeMessage', '').trim();
      const errMsg = warnMsg.length > 0
        ? warnMsg
        : (msg.length > 0 ? msg : (noticeMsg.length > 0 ? noticeMsg : '图书馆预约服务拒绝了本次操作'));
      return {
        ok: false,
        bookingId: '',
        failureKind: 'business',
        message: errMsg
      };
    }
    const dataArr = JsonHelpers.asArray(obj['data']);
    const firstObj = dataArr.length > 0 ? JsonHelpers.asObject(dataArr[0]) : undefined;
    const bookingId = JsonHelpers.str(firstObj, 'id', '').trim();
    if (bookingId.length === 0) {
      return {
        ok: false,
        bookingId: '',
        failureKind: 'uncertain',
        message: '预约结果尚未确认，请先查看我的预约'
      };
    }
    return {
      ok: true,
      bookingId: bookingId,
      failureKind: 'none',
      message: ''
    };
  }

  static extractChaoxingSubmitSalt(html: string): string {
    const m1 = new RegExp('id=["\']submit_enc["\'][^>]*\\bvalue=["\']([^"\']+)["\']', 'i').exec(html);
    if (m1 !== null && m1[1].trim().length > 0) {
      return m1[1].trim();
    }
    const m2 = new RegExp('value=["\']([^"\']+)["\'][^>]*\\bid=["\']submit_enc["\']', 'i').exec(html);
    return m2 !== null ? m2[1].trim() : '';
  }

  static normalizeChaoxingSeatNum(raw: string): string {
    const trimmed = raw.trim();
    const num = parseInt(trimmed, 10);
    if (!Number.isFinite(num) || num <= 0) {
      return trimmed;
    }
    let out = `${num}`;
    while (out.length < 3) {
      out = `0${out}`;
    }
    return out;
  }

  static buildChaoxingSubmitPlain(
    roomId: string,
    seatNum: string,
    day: string,
    startTime: string,
    endTime: string,
    fidEnc: string,
    salt: string
  ): string {
    return `[captcha=]` +
      `[day=${day}]` +
      `[deptIdEnc=${fidEnc}]` +
      `[endTime=${endTime}]` +
      `[roomId=${roomId}]` +
      `[seatNum=${seatNum}]` +
      `[startTime=${startTime}]` +
      `[wyToken=]` +
      `[${salt}]`;
  }

  static parseChaoxingSubmitResponse(statusCode: number, body: string): ShuYoParsedBookingResponse {
    if (statusCode !== 200) {
      return {
        ok: false,
        bookingId: '',
        failureKind: 'uncertain',
        message: `超星预约提交异常（HTTP ${statusCode}），请先查看我的预约确认`
      };
    }
    const env = JsonHelpers.parseObject(body);
    if (env === undefined) {
      return {
        ok: false,
        bookingId: '',
        failureKind: 'uncertain',
        message: '超星预约返回格式异常，请查看我的预约确认'
      };
    }
    if (!JsonHelpers.bool(env, 'success', false)) {
      const msg = JsonHelpers.str(env, 'msg', '').trim();
      const message = JsonHelpers.str(env, 'message', '').trim();
      const errMsg = msg.length > 0 ? msg : (message.length > 0 ? message : '该座位已被预约或当前不可约');
      return {
        ok: false,
        bookingId: '',
        failureKind: 'business',
        message: errMsg
      };
    }
    const resData = JsonHelpers.asObject(env['data']);
    const seatReserve = JsonHelpers.asObject(resData !== undefined ? resData['seatReserve'] : undefined);
    const reserveId = JsonHelpers.str(seatReserve, 'id', '').trim();
    if (reserveId.length === 0) {
      return {
        ok: false,
        bookingId: '',
        failureKind: 'uncertain',
        message: '预约结果尚未确认，请先查看我的预约，勿直接重试'
      };
    }
    return {
      ok: true,
      bookingId: reserveId,
      failureKind: 'none',
      message: ''
    };
  }

  static utf8Bytes(text: string): Uint8Array {
    const out: number[] = [];
    for (let i = 0; i < text.length; i++) {
      let codePoint = text.charCodeAt(i);
      if (codePoint < 0x80) {
        out.push(codePoint);
      } else if (codePoint < 0x800) {
        out.push(0xc0 | (codePoint >> 6));
        out.push(0x80 | (codePoint & 0x3f));
      } else if (codePoint >= 0xd800 && codePoint <= 0xdbff && i + 1 < text.length) {
        const next = text.charCodeAt(i + 1);
        if (next >= 0xdc00 && next <= 0xdfff) {
          codePoint = ((codePoint - 0xd800) << 10) + (next - 0xdc00) + 0x10000;
          out.push(0xf0 | (codePoint >> 18));
          out.push(0x80 | ((codePoint >> 12) & 0x3f));
          out.push(0x80 | ((codePoint >> 6) & 0x3f));
          out.push(0x80 | (codePoint & 0x3f));
          i++;
        } else {
          out.push(0xe0 | (codePoint >> 12));
          out.push(0x80 | ((codePoint >> 6) & 0x3f));
          out.push(0x80 | (codePoint & 0x3f));
        }
      } else {
        out.push(0xe0 | (codePoint >> 12));
        out.push(0x80 | ((codePoint >> 6) & 0x3f));
        out.push(0x80 | (codePoint & 0x3f));
      }
    }
    return new Uint8Array(out);
  }

  static md5HexPure(plain: string): string {
    return LibraryBookingProtocol.pureMd5Hex(LibraryBookingProtocol.utf8Bytes(plain));
  }

  static pureMd5Hex(input: Uint8Array): string {
    const k: number[] = [
      0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
      0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
      0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
      0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
      0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
      0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
      0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
      0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
    ];
    const s: number[] = [
      7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
      5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
      4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
      6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    ];

    const bitLen = input.length * 8;
    const padLen = ((input.length + 8) >> 6) * 64 + 64;
    const padded = new Uint8Array(padLen);
    padded.set(input);
    padded[input.length] = 0x80;
    padded[padLen - 8] = bitLen & 0xff;
    padded[padLen - 7] = (bitLen >>> 8) & 0xff;
    padded[padLen - 6] = (bitLen >>> 16) & 0xff;
    padded[padLen - 5] = (bitLen >>> 24) & 0xff;
    const hiBits = Math.floor(bitLen / 4294967296);
    padded[padLen - 4] = hiBits & 0xff;
    padded[padLen - 3] = (hiBits >>> 8) & 0xff;
    padded[padLen - 2] = (hiBits >>> 16) & 0xff;
    padded[padLen - 1] = (hiBits >>> 24) & 0xff;

    let a0 = 0x67452301;
    let b0 = 0xefcdab89;
    let c0 = 0x98badcfe;
    let d0 = 0x10325476;

    for (let offset = 0; offset < padLen; offset += 64) {
      const m: number[] = [];
      for (let j = 0; j < 16; j++) {
        const idx = offset + j * 4;
        m.push(
          padded[idx] |
          (padded[idx + 1] << 8) |
          (padded[idx + 2] << 16) |
          (padded[idx + 3] << 24)
        );
      }

      let a = a0;
      let b = b0;
      let c = c0;
      let d = d0;

      for (let i = 0; i < 64; i++) {
        let f = 0;
        let g = 0;
        if (i < 16) {
          f = (b & c) | ((~b) & d);
          g = i;
        } else if (i < 32) {
          f = (d & b) | ((~d) & c);
          g = (5 * i + 1) % 16;
        } else if (i < 48) {
          f = b ^ c ^ d;
          g = (3 * i + 5) % 16;
        } else {
          f = c ^ (b | (~d));
          g = (7 * i) % 16;
        }
        const temp = d;
        d = c;
        c = b;
        const sum = (a + f + k[i] + m[g]) | 0;
        const shift = s[i];
        const rot = (sum << shift) | (sum >>> (32 - shift));
        b = (b + rot) | 0;
        a = temp;
      }

      a0 = (a0 + a) | 0;
      b0 = (b0 + b) | 0;
      c0 = (c0 + c) | 0;
      d0 = (d0 + d) | 0;
    }

    const words = [a0, b0, c0, d0];
    const hexChars = '0123456789abcdef';
    let out = '';
    for (let w = 0; w < 4; w++) {
      const val = words[w];
      for (let byteIdx = 0; byteIdx < 4; byteIdx++) {
        const b = (val >>> (byteIdx * 8)) & 0xff;
        out += hexChars.charAt((b >> 4) & 0x0f) + hexChars.charAt(b & 0x0f);
      }
    }
    return out;
  }
}
