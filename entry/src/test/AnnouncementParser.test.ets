import { describe, it, expect } from '@ohos/hypium';
import { ShuYoAnnouncementItem } from '../main/ets/models/ShuYoModels';
import { AnnouncementParser, AnnouncementSourceConfig } from '../main/ets/services/AnnouncementParser';

export default function announcementParserTest(): void {
  describe('AnnouncementParserTest', () => {
    it('parsesAllSixSchoolAnnouncementListFormats', 0, () => {
      const configs: AnnouncementSourceConfig[] = [
        { id: 'shu', name: '上海大学官网', listUrl: 'https://www.shu.edu.cn/tzgg.htm', format: 'shuHome' },
        { id: 'bksy', name: '本科生院', listUrl: 'https://bksy.shu.edu.cn/index/tzgg.htm', format: 'onlyList' },
        { id: 'xgb', name: '本科生处', listUrl: 'https://xgb.shu.edu.cn/xgdt/tzgg.htm', format: 'artList' },
        { id: 'gs', name: '研究生院', listUrl: 'https://gs.shu.edu.cn/xwlb/py.htm', format: 'vsbTable' },
        { id: 'cwc', name: '财务处', listUrl: 'https://cwc.shu.edu.cn/index/tzgg.htm', format: 'centreList' },
        { id: 'lib', name: '图书馆', listUrl: 'https://lib.shu.edu.cn/sho/ggxx.htm', format: 'rightList' }
      ];
      const fixtures: Record<string, string> = {
        'shu': '<div class="ej_main"><div class="list"><ul><li><a href="/info/1.htm">' +
          '<p class="bt">官网通知 &amp; 安排</p><p class="sj">2026.10.06</p><p class="zy">摘要文本</p></a></li></ul></div></div>',
        'bksy': '<div class="only-list"><ul><li><a href="../info/2.htm">本科生通知</a><span>2026年10月6日</span></li></ul></div>',
        'xgb': '<table class="ArtList"><tr><td><a class="linkfont1" href="/info/3.htm">本科生处通知</a></td>' +
          '<td><span class="linkfont1">2026-10-06</span></td></tr></table>',
        'gs': '<table><tr id="line_u1_0"><td><a href="/info/5.htm">研究生培养通知</a></td>' +
          '<td>2026/10/06 09:00:00</td></tr></table>',
        'cwc': '<div class="list-centre-right-down"><ul><li class="clearfix"><a href="/info/6.htm">财务通知</a>' +
          '<p class="list-centre-right-down-p">2026-10-06</p></li></ul></div>',
        'lib': '<div class="right-list"><ul><li><a href="/info/7.htm">图书馆通知</a><span>2026-10-06</span></li></ul></div>'
      };

      for (let i = 0; i < configs.length; i++) {
        const cfg = configs[i];
        const items = AnnouncementParser.parseListHtml(fixtures[cfg.id], cfg.listUrl, cfg);
        expect(items.length).assertEqual(1);
        expect(items[0].dateText).assertEqual('2026-10-06');
        expect(items[0].url.startsWith('https://')).assertTrue();
        expect(items[0].sourceName).assertEqual(cfg.name);
      }
    });

    it('parsesRichDetailWithTextTableImageAndAttachment', 0, () => {
      const baseItem: ShuYoAnnouncementItem = {
        id: 'shu-0',
        title: '默认标题',
        url: 'https://www.shu.edu.cn/info/1001/9999.htm',
        summary: '',
        dateText: '2026-10-01',
        sourceName: '上海大学官网',
        author: '',
        department: '',
        blocks: []
      };
      const detailHtml =
        '<div class="nry">' +
        '  <h1>关于 2026 年秋季学期校车与图书馆开放安排的通知</h1>' +
        '  <div class="xx"><span>发布时间：2026年11月20日</span><span>投稿：校办</span><span>部门：党政办公室</span></div>' +
        '  <div class="v_news_content">' +
        '    <p>第一段正文说明，含&ldquo;引号&rdquo;和常规通知。</p>' +
        '    <table>' +
        '      <tr><th>区域</th><th>开放时间</th><th>备注</th></tr>' +
        '      <tr><td>宝山24H空间</td><td>00:00-24:00</td><td>需预约</td></tr>' +
        '    </table>' +
        '    <p><img src="../../__local/map_preview.png" alt="示意图" /></p>' +
        '    <p><a href="/system/_content/download.jsp?urltype=news.DownloadAttachUrl&amp;fileid=1">附件1：开放时间表.pdf</a></p>' +
        '  </div>' +
        '</div>';

      const parsed = AnnouncementParser.parseDetailHtml(detailHtml, baseItem);
      expect(parsed.title).assertEqual('关于 2026 年秋季学期校车与图书馆开放安排的通知');
      expect(parsed.dateText).assertEqual('2026-11-20');
      expect(parsed.author).assertEqual('校办');
      expect(parsed.department).assertEqual('党政办公室');
      expect(parsed.blocks.length >= 4).assertTrue();

      let hasText = false;
      let hasTable = false;
      let hasImage = false;
      let hasLink = false;
      for (let i = 0; i < parsed.blocks.length; i++) {
        const blk = parsed.blocks[i];
        if (blk.blockType === 'text' && blk.blockValue.includes('第一段正文说明')) {
          hasText = true;
        } else if (blk.blockType === 'table' && blk.rows !== undefined && blk.rows.length === 2) {
          hasTable = blk.rows[1][0] === '宝山24H空间' && blk.rows[1][2] === '需预约';
        } else if (blk.blockType === 'image' && blk.blockValue === 'https://www.shu.edu.cn/__local/map_preview.png') {
          hasImage = true;
        } else if (blk.blockType === 'link' && blk.blockValue.includes('DownloadAttachUrl')) {
          hasLink = true;
        }
      }
      expect(hasText).assertTrue();
      expect(hasTable).assertTrue();
      expect(hasImage).assertTrue();
      expect(hasLink).assertTrue();
    });
  });
}
