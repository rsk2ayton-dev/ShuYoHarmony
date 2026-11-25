import { describe, it, expect } from '@ohos/hypium';
import { JsonHelpers } from '../main/ets/services/JsonHelpers';
import { LibraryBookingProtocol } from '../main/ets/services/LibraryBookingProtocol';

export default function libraryBookingProtocolTest(): void {
  describe('LibraryBookingProtocolTest', () => {
    it('extractsThereSessionIdFromLegacyModernAndInvalidHtml', 0, () => {
      const legacy = 'window.loginUser={"isAnonymous":false};window.sessionId="SESSION_LIB";';
      expect(LibraryBookingProtocol.extractThereSessionId(legacy)).assertEqual('SESSION_LIB');

      const quotedProp = 'window.loginUser={"isAnonymous":false,"sessionId":"SESSION_24H"};';
      expect(LibraryBookingProtocol.extractThereSessionId(quotedProp)).assertEqual('SESSION_24H');

      const cookieMode = 'var sessionId = ""; var loginUser = {"id":"USER_1","name":"测试用户"};';
      expect(LibraryBookingProtocol.extractThereSessionId(cookieMode)).assertEqual('');

      const blankNonEmpty = 'window.sessionId="   ";';
      expect(LibraryBookingProtocol.extractThereSessionId(blankNonEmpty) === undefined).assertTrue();

      expect(LibraryBookingProtocol.isThereAnonymousHtml('{"isAnonymous":true}')).assertTrue();
      expect(LibraryBookingProtocol.isThereAnonymousHtml('{"id":"USER_1"}')).assertFalse();
    });

    it('normalizesThereRedirectsAndDetectsWeChat', 0, () => {
      expect(
        LibraryBookingProtocol.isWeChatRedirect(
          302,
          'https://https-open-weixin-qq-com-443.webvpn.shu.edu.cn/connect/oauth2/authorize'
        )
      ).assertTrue();
      expect(
        LibraryBookingProtocol.isWeChatRedirect(302, 'https://newsso.shu.edu.cn/oauth/authorize')
      ).assertFalse();

      const webVpnNormalized = LibraryBookingProtocol.normalizeThereRedirect(
        'https://https-there-shu-edu-cn-443.webvpn.shu.edu.cn',
        'http://http-there-shu-edu-cn-80.webvpn.shu.edu.cn/web?authJump=token'
      );
      expect(webVpnNormalized).assertEqual(
        'https://https-there-shu-edu-cn-443.webvpn.shu.edu.cn/web?authJump=token'
      );
    });

    it('validatesThereRoomAndParsesBookingOutcomes', 0, () => {
      const bookableRoom = JsonHelpers.parseObject(
        '{"id":"ROOM_1","name":"B001","officeAreaId":"AREA_B","disabled":false,"isBusy":false,"isBooked":false,"abilities":["booking"]}'
      );
      expect(LibraryBookingProtocol.validateThereRoomBookable(bookableRoom, 'AREA_B')).assertTrue();
      expect(LibraryBookingProtocol.validateThereRoomBookable(bookableRoom, 'AREA_A')).assertFalse();

      const busyRoom = JsonHelpers.parseObject(
        '{"id":"ROOM_2","name":"B002","officeAreaId":"AREA_B","disabled":false,"isBusy":true,"isBooked":false,"abilities":["booking"]}'
      );
      expect(LibraryBookingProtocol.validateThereRoomBookable(busyRoom, 'AREA_B')).assertFalse();

      const noAbilityRoom = JsonHelpers.parseObject(
        '{"id":"ROOM_3","name":"B003","officeAreaId":"AREA_B","disabled":false,"isBusy":false,"isBooked":false,"abilities":["view"]}'
      );
      expect(LibraryBookingProtocol.validateThereRoomBookable(noAbilityRoom, 'AREA_B')).assertFalse();

      const payload = LibraryBookingProtocol.buildThereBookingPayload(
        bookableRoom!,
        'USER_1',
        '张同学',
        '2026-11-25',
        '09:00',
        '12:00'
      );
      expect(JsonHelpers.str(payload, 'subject', '')).assertEqual('张同学');

      const okRes = LibraryBookingProtocol.parseThereBookingResponse(
        200,
        '{"code":0,"data":[{"id":"BK_987654"}]}'
      );
      expect(okRes.ok).assertTrue();
      expect(okRes.bookingId).assertEqual('BK_987654');

      const missingIdRes = LibraryBookingProtocol.parseThereBookingResponse(200, '{"code":0,"data":[]}');
      expect(missingIdRes.ok).assertFalse();
      expect(missingIdRes.failureKind).assertEqual('uncertain');

      const businessRes = LibraryBookingProtocol.parseThereBookingResponse(
        200,
        '{"code":200,"warnMessage":"超过每日预约次数上限"}'
      );
      expect(businessRes.ok).assertFalse();
      expect(businessRes.failureKind).assertEqual('business');
      expect(businessRes.message).assertEqual('超过每日预约次数上限');

      const authLostRes = LibraryBookingProtocol.parseThereBookingResponse(401, '{"code":401}');
      expect(authLostRes.ok).assertFalse();
      expect(authLostRes.failureKind).assertEqual('loginRequired');
    });

    it('buildsChaoxingSignatureAndParsesSubmitResponse', 0, () => {
      const htmlOrderA = '<input type="hidden" id="submit_enc" value="SALT_123" />';
      const htmlOrderB = '<input value="SALT_456" id="submit_enc" type="hidden">';
      expect(LibraryBookingProtocol.extractChaoxingSubmitSalt(htmlOrderA)).assertEqual('SALT_123');
      expect(LibraryBookingProtocol.extractChaoxingSubmitSalt(htmlOrderB)).assertEqual('SALT_456');

      expect(LibraryBookingProtocol.normalizeChaoxingSeatNum('7')).assertEqual('007');
      expect(LibraryBookingProtocol.normalizeChaoxingSeatNum('128')).assertEqual('128');

      // Standard RFC 1321 MD5 test vectors + Chaoxing sign payload format
      expect(LibraryBookingProtocol.md5HexPure('')).assertEqual('d41d8cd98f00b204e9800998ecf8427e');
      expect(LibraryBookingProtocol.md5HexPure('abc')).assertEqual('900150983cd24fb0d6963f7d28e17f72');

      const plain = LibraryBookingProtocol.buildChaoxingSubmitPlain(
        '6508',
        '007',
        '2026-11-25',
        '09:00',
        '12:00',
        '00bae7f2bdea485a',
        'SALT_123'
      );
      expect(plain).assertEqual(
        '[captcha=][day=2026-11-25][deptIdEnc=00bae7f2bdea485a][endTime=12:00][roomId=6508][seatNum=007][startTime=09:00][wyToken=][SALT_123]'
      );
      expect(LibraryBookingProtocol.md5HexPure(plain).length).assertEqual(32);

      const cxOk = LibraryBookingProtocol.parseChaoxingSubmitResponse(
        200,
        '{"success":true,"data":{"seatReserve":{"id":884210}}}'
      );
      expect(cxOk.ok).assertTrue();
      expect(cxOk.bookingId).assertEqual('884210');

      const cxMissingId = LibraryBookingProtocol.parseChaoxingSubmitResponse(
        200,
        '{"success":true,"data":{}}'
      );
      expect(cxMissingId.ok).assertFalse();
      expect(cxMissingId.failureKind).assertEqual('uncertain');

      const cxRejected = LibraryBookingProtocol.parseChaoxingSubmitResponse(
        200,
        '{"success":false,"msg":"该时间段座位已被他人预约"}'
      );
      expect(cxRejected.ok).assertFalse();
      expect(cxRejected.failureKind).assertEqual('business');
      expect(cxRejected.message).assertEqual('该时间段座位已被他人预约');
    });
  });
}
