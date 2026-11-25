import { ShuYoAnnouncementBlock, ShuYoAnnouncementItem } from '../models/ShuYoModels';
import {
  AnnouncementParser,
  AnnouncementSourceConfig
} from './AnnouncementParser';
import { HttpClientService } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';
import { RawFileService } from './RawFileService';

interface SourceFetchOutcome {
  items: ShuYoAnnouncementItem[];
  errorMsg: string;
}

export class AnnouncementService {
  static readonly filterSources: string[] = [
    '全部',
    '上海大学官网',
    '本科生院',
    '本科生处',
    '研究生院',
    '财务处',
    '图书馆'
  ];

  private static readonly sourceConfigs: AnnouncementSourceConfig[] = [
    { id: 'shu', name: '上海大学官网', listUrl: 'https://www.shu.edu.cn/tzgg.htm', format: 'shuHome' },
    { id: 'bksy', name: '本科生院', listUrl: 'https://bksy.shu.edu.cn/index/tzgg.htm', format: 'onlyList' },
    { id: 'xgb', name: '本科生处', listUrl: 'https://xgb.shu.edu.cn/xgdt/tzgg.htm', format: 'artList' },
    { id: 'gs', name: '研究生院', listUrl: 'https://gs.shu.edu.cn/xwlb/py.htm', format: 'vsbTable' },
    { id: 'cwc', name: '财务处', listUrl: 'https://cwc.shu.edu.cn/index/tzgg.htm', format: 'centreList' },
    { id: 'lib', name: '图书馆', listUrl: 'https://lib.shu.edu.cn/sho/ggxx.htm', format: 'rightList' }
  ];

  private static readonly detailCache: Map<string, ShuYoAnnouncementItem> =
    new Map<string, ShuYoAnnouncementItem>();

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
      const blocks = AnnouncementService.parseDemoBlocks(blocksRaw);
      const dept = JsonHelpers.str(detail, 'department', '');
      out.push({
        id: `demo-ann-${i}`,
        title: JsonHelpers.str(item, 'title'),
        url: JsonHelpers.str(item, 'url'),
        summary: JsonHelpers.str(item, 'summary'),
        dateText: JsonHelpers.str(item, 'dateText'),
        sourceName: dept.length > 0 ? dept : '上海大学官网',
        author: JsonHelpers.str(detail, 'author', '公告编辑'),
        department: dept,
        blocks: blocks
      });
    }
    return out;
  }

  private static parseDemoBlocks(blocksRaw: Object[]): ShuYoAnnouncementBlock[] {
    const blocks: ShuYoAnnouncementBlock[] = [];
    for (let b = 0; b < blocksRaw.length; b++) {
      const blk = JsonHelpers.asObject(blocksRaw[b]);
      if (blk === undefined) {
        continue;
      }
      const rawRows = JsonHelpers.asArray(blk['rows']);
      const parsedRows: string[][] = [];
      for (let r = 0; r < rawRows.length; r++) {
        const rowArr = JsonHelpers.asArray(rawRows[r]);
        const rowCells: string[] = [];
        for (let c = 0; c < rowArr.length; c++) {
          const cellVal = rowArr[c];
          rowCells.push(cellVal !== undefined && cellVal !== null ? String(cellVal) : '');
        }
        if (rowCells.length > 0) {
          parsedRows.push(rowCells);
        }
      }
      const altStr = JsonHelpers.str(blk, 'alt', '');
      const labelStr = JsonHelpers.str(blk, 'label', '');
      blocks.push({
        blockType: JsonHelpers.str(blk, 'type', 'text'),
        blockValue: JsonHelpers.str(blk, 'value'),
        alt: altStr.length > 0 ? altStr : undefined,
        label: labelStr.length > 0 ? labelStr : undefined,
        rows: parsedRows.length > 0 ? parsedRows : undefined
      });
    }
    return blocks;
  }

  private static findSourceConfig(sourceName: string): AnnouncementSourceConfig {
    if (sourceName === '学校主页') {
      return AnnouncementService.sourceConfigs[0];
    }
    for (let i = 0; i < AnnouncementService.sourceConfigs.length; i++) {
      if (AnnouncementService.sourceConfigs[i].name === sourceName) {
        return AnnouncementService.sourceConfigs[i];
      }
    }
    return AnnouncementService.sourceConfigs[0];
  }

  static async fetchLiveAnnouncements(sourceName: string): Promise<ShuYoAnnouncementItem[]> {
    if (sourceName === '全部') {
      const targets: AnnouncementSourceConfig[] = [
        AnnouncementService.sourceConfigs[0],
        AnnouncementService.sourceConfigs[1]
      ];
      const outcomes: SourceFetchOutcome[] = await Promise.all(
        targets.map((cfg: AnnouncementSourceConfig): Promise<SourceFetchOutcome> =>
          AnnouncementService.fetchSingleSourceSafe(cfg)
        )
      );
      const merged: ShuYoAnnouncementItem[] = [];
      const seenUrls = new Set<string>();
      let firstErr = '';
      let successCount = 0;
      for (let i = 0; i < outcomes.length; i++) {
        if (outcomes[i].errorMsg.length === 0) {
          successCount++;
          const list = outcomes[i].items;
          for (let j = 0; j < list.length; j++) {
            const it = list[j];
            if (!seenUrls.has(it.url)) {
              seenUrls.add(it.url);
              merged.push(it);
            }
          }
        } else if (firstErr.length === 0) {
          firstErr = outcomes[i].errorMsg;
        }
      }
      if (successCount === 0) {
        throw new Error(firstErr.length > 0 ? firstErr : '通知公告加载失败，请稍后重试');
      }
      merged.sort((a: ShuYoAnnouncementItem, b: ShuYoAnnouncementItem): number =>
        AnnouncementParser.compareDateDesc(a.dateText, b.dateText)
      );
      return merged.slice(0, 30);
    }

    const cfg = AnnouncementService.findSourceConfig(sourceName);
    return await AnnouncementService.fetchSingleSource(cfg);
  }

  private static async fetchSingleSourceSafe(cfg: AnnouncementSourceConfig): Promise<SourceFetchOutcome> {
    try {
      const items = await AnnouncementService.fetchSingleSource(cfg);
      return { items: items, errorMsg: '' };
    } catch (err) {
      const e = err as Error;
      return {
        items: [],
        errorMsg: e.message.length > 0 ? e.message : '公告请求失败'
      };
    }
  }

  private static async fetchSingleSource(cfg: AnnouncementSourceConfig): Promise<ShuYoAnnouncementItem[]> {
    const resp = await HttpClientService.getWithRedirects(cfg.listUrl, 6, {
      'accept': 'text/html,application/xhtml+xml'
    });
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw new Error(`无法获取「${cfg.name}」公告 (${resp.statusCode})`);
    }
    const items = AnnouncementParser.parseListHtml(resp.body, cfg.listUrl, cfg);
    if (items.length === 0) {
      throw new Error(`「${cfg.name}」公告页面暂未解析到内容`);
    }
    return items.slice(0, 30);
  }

  static async fetchLiveDetail(item: ShuYoAnnouncementItem): Promise<ShuYoAnnouncementItem> {
    if (item.url.length === 0) {
      return item;
    }
    const cached = AnnouncementService.detailCache.get(item.url);
    if (cached !== undefined && cached.blocks.length > 0) {
      return cached;
    }
    const resp = await HttpClientService.getWithRedirects(item.url, 6, {
      'accept': 'text/html,application/xhtml+xml'
    });
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw new Error(`公告正文加载失败 (${resp.statusCode})`);
    }
    const detailed = AnnouncementParser.parseDetailHtml(resp.body, item);
    AnnouncementService.detailCache.set(item.url, detailed);
    return detailed;
  }

  static decodeEntities(text: string): string {
    return AnnouncementParser.decodeEntities(text);
  }
}
