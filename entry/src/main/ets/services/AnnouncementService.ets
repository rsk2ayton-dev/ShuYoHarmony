import { ShuYoAnnouncementBlock, ShuYoAnnouncementItem } from '../models/ShuYoModels';
import { HttpClientService } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';
import { RawFileService } from './RawFileService';

export class AnnouncementService {
  static readonly sources: string[] = ['学校主页', '教务处', '学生工作办公室'];

  static loadDemoAnnouncements(): ShuYoAnnouncementItem[] {
    const raw = RawFileService.readText('demo/announcements/announcements.json');
    const obj = JsonHelpers.parseObject(raw);
    const itemsRaw = JsonHelpers.asArray(obj !== undefined ? obj['items'] : undefined);
    const out: ShuYoAnnouncementItem[] = [];
    for (let i = 0; i < itemsRaw.length; i++) {
      const item = JsonHelpers.asObject(itemsRaw[i]);
      if (item === undefined) {
        continue;
      }
      const detail = JsonHelpers.asObject(item['detail']);
      const blocksRaw = JsonHelpers.asArray(detail !== undefined ? detail['blocks'] : undefined);
      const blocks: ShuYoAnnouncementBlock[] = [];
      for (let b = 0; b < blocksRaw.length; b++) {
        const blk = JsonHelpers.asObject(blocksRaw[b]);
        if (blk === undefined) {
          continue;
        }
        blocks.push({
          blockType: JsonHelpers.str(blk, 'type', 'text'),
          blockValue: JsonHelpers.str(blk, 'value')
        });
      }
      const dept = JsonHelpers.str(detail, 'department', '');
      out.push({
        id: `demo-ann-${i}`,
        title: JsonHelpers.str(item, 'title'),
        url: JsonHelpers.str(item, 'url'),
        summary: JsonHelpers.str(item, 'summary'),
        dateText: JsonHelpers.str(item, 'dateText'),
        sourceName: dept.length > 0 ? dept : '学校主页',
        author: JsonHelpers.str(detail, 'author', '公告编辑'),
        department: dept,
        blocks: blocks
      });
    }
    return out;
  }

  static async fetchLiveAnnouncements(sourceName: string): Promise<ShuYoAnnouncementItem[]> {
    const url = sourceName === '教务处'
      ? 'https://jwb.shu.edu.cn/index/tzgg.htm'
      : 'https://www.shu.edu.cn/tzgg.htm';
    const resp = await HttpClientService.getWithRedirects(url, 5);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw new Error(`无法获取公告 (${resp.statusCode})`);
    }
    const results: ShuYoAnnouncementItem[] = [];
    const linkPattern = new RegExp('<a[^>]*href=["\']([^"\']+\\.htm)["\'][^>]*title=["\']([^"\']+)["\'][^>]*>', 'gi');
    let match = linkPattern.exec(resp.body);
    let idx = 0;
    while (match !== null && results.length < 20) {
      const href = HttpClientService.resolveUrl(url, match[1]);
      const title = match[2].trim();
      if (title.length > 4) {
        results.push({
          id: `live-ann-${idx++}`,
          title: title,
          url: href,
          summary: '点击查看通知详情',
          dateText: '校内通知',
          sourceName: sourceName,
          author: sourceName,
          department: sourceName,
          blocks: [
            { blockType: 'text', blockValue: `来源链接：${href}` }
          ]
        });
      }
      match = linkPattern.exec(resp.body);
    }
    return results.length > 0 ? results : AnnouncementService.loadDemoAnnouncements();
  }
}
