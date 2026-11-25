import webVpnProtocolTest from './WebVpnProtocol.test';
import libraryBookingProtocolTest from './LibraryBookingProtocol.test';
import announcementParserTest from './AnnouncementParser.test';

export default function testsuite(): void {
  webVpnProtocolTest();
  libraryBookingProtocolTest();
  announcementParserTest();
}
