import { ShuYoAnnouncementBlock, ShuYoAnnouncementItem } from '../models/ShuYoModels';
import { WebVpnProtocol } from './WebVpnProtocol';

export interface AnnouncementSourceConfig {
  id: string;
  name: string;
  listUrl: string;
  format: string;
}

export interface ParsedAnnouncementMeta {
  dateText: string;
  author: string;
  department: string;
}

interface HtmlNode {
  isText: boolean;
  tag: string;
  text: string;
  attrs: Map<string, string>;
  children: HtmlNode[];
}

/**
 * Pure HTML parser for SHU announcement lists and detail pages.
 * Free of `@kit.*` imports so Hypium Local Tests can verify it offline with fixtures.
 */
export class AnnouncementParser {
  private static readonly htmlVoidTags: Set<string> = new Set<string>([
    'img', 'br', 'hr', 'input', 'meta', 'link', 'source',
    'col', 'area', 'base', 'embed', 'param', 'track', 'wbr'
  ]);

  private static readonly htmlBlockTags: Set<string> = new Set<string>([
    'div', 'p', 'li', 'ul', 'ol', 'table', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'blockquote', 'section', 'article', 'pre', 'img'
  ]);

  static parseListHtml(
    html: string,
    baseUrl: string,
    cfg: AnnouncementSourceConfig
  ): ShuYoAnnouncementItem[] {
    if (cfg.format === 'shuHome') {
      return AnnouncementParser.parseShuHome(html, baseUrl, cfg);
    }
    if (cfg.format === 'onlyList') {
      return AnnouncementParser.parseOnlyList(html, baseUrl, cfg);
    }
    if (cfg.format === 'artList') {
      return AnnouncementParser.parseArtList(html, baseUrl, cfg);
    }
    if (cfg.format === 'vsbTable') {
      return AnnouncementParser.parseVsbTable(html, baseUrl, cfg);
    }
    if (cfg.format === 'centreList') {
      return AnnouncementParser.parseCentreList(html, baseUrl, cfg);
    }
    return AnnouncementParser.parseRightList(html, baseUrl, cfg);
  }

  static parseDetailHtml(html: string, item: ShuYoAnnouncementItem): ShuYoAnnouncementItem {
    const rootHtml = AnnouncementParser.extractDivByClass(html, 'nry');
    const titleRaw = rootHtml.length > 0
      ? AnnouncementParser.extractFirstTagText(rootHtml, 'h1')
      : AnnouncementParser.extractFirstTagText(html, 'h1');
    const title = titleRaw.length > 0 ? titleRaw : item.title;

    const metaHtml = rootHtml.length > 0
      ? AnnouncementParser.extractDivByClass(rootHtml, 'xx')
      : AnnouncementParser.extractDivByClass(html, 'xx');
    const meta = AnnouncementParser.parseDetailMetadata(metaHtml);
    const dateText = meta.dateText.length > 0 ? meta.dateText : item.dateText;

    let contentHtml = '';
    if (rootHtml.length > 0) {
      contentHtml = AnnouncementParser.extractDivByClass(rootHtml, 'v_news_content');
    }
    if (contentHtml.length === 0) {
      contentHtml = AnnouncementParser.extractDivByClass(html, 'v_news_content');
    }
    if (contentHtml.length === 0) {
      contentHtml = AnnouncementParser.extractDivById(html, 'vsb_content');
    }
    if (contentHtml.length === 0) {
      contentHtml = AnnouncementParser.extractDivById(html, 'js_content');
    }

    const blocks = AnnouncementParser.parseContentBlocks(contentHtml, item.url, html);
    return {
      id: item.id,
      title: title,
      url: item.url,
      summary: item.summary,
      dateText: dateText,
      sourceName: item.sourceName,
      author: meta.author.length > 0 ? meta.author : item.author,
      department: meta.department.length > 0 ? meta.department : item.department,
      blocks: blocks
    };
  }

  private static parseShuHome(
    html: string,
    baseUrl: string,
    cfg: AnnouncementSourceConfig
  ): ShuYoAnnouncementItem[] {
    let section = AnnouncementParser.extractDivByClass(html, 'ej_main');
    if (section.length === 0) {
      section = AnnouncementParser.extractDivByClass(html, 'list');
    }
    if (section.length === 0) {
      section = html;
    }
    const items: ShuYoAnnouncementItem[] = [];
    const seen = new Set<string>();
    const aRe = new RegExp('<a\\b([^>]*)>([\\s\\S]*?)<\\/a>', 'gi');
    let m = aRe.exec(section);
    while (m !== null && items.length < 30) {
      const attrs = m[1];
      const inner = m[2];
      const href = AnnouncementParser.extractAttr(attrs, 'href');
      const btMatch = new RegExp('<p[^>]*class=["\'][^"\']*\\bbt\\b[^"\']*["\'][^>]*>([\\s\\S]*?)<\\/p>', 'i').exec(inner);
      if (btMatch === null || href.length === 0) {
        m = aRe.exec(section);
        continue;
      }
      const title = AnnouncementParser.cleanHtmlText(btMatch[1]);
      const fullUrl = WebVpnProtocol.resolveUrl(baseUrl, href);
      if (title.length === 0 || fullUrl.length === 0 || seen.has(fullUrl)) {
        m = aRe.exec(section);
        continue;
      }
      seen.add(fullUrl);
      const zyMatch = new RegExp('<p[^>]*class=["\'][^"\']*\\bzy\\b[^"\']*["\'][^>]*>([\\s\\S]*?)<\\/p>', 'i').exec(inner);
      const sjMatch = new RegExp('<p[^>]*class=["\'][^"\']*\\bsj\\b[^"\']*["\'][^>]*>([\\s\\S]*?)<\\/p>', 'i').exec(inner);
      const summary = zyMatch !== null ? AnnouncementParser.cleanHtmlText(zyMatch[1]) : '';
      const dateText = AnnouncementParser.normalizeDateString(sjMatch !== null ? AnnouncementParser.cleanHtmlText(sjMatch[1]) : '');
      items.push({
        id: `${cfg.id}-${items.length}`,
        title: title,
        url: fullUrl,
        summary: summary,
        dateText: dateText.length > 0 ? dateText : '校内通知',
        sourceName: cfg.name,
        author: cfg.name,
        department: cfg.name,
        blocks: []
      });
      m = aRe.exec(section);
    }
    return items;
  }

  private static parseOnlyList(
    html: string,
    baseUrl: string,
    cfg: AnnouncementSourceConfig
  ): ShuYoAnnouncementItem[] {
    let section = AnnouncementParser.extractDivByClass(html, 'only-list');
    if (section.length === 0) {
      section = AnnouncementParser.extractDivByClass(html, 'only-list1');
    }
    if (section.length === 0) {
      return [];
    }
    return AnnouncementParser.parseListItemsWithSpanDate(section, baseUrl, cfg);
  }

  private static parseRightList(
    html: string,
    baseUrl: string,
    cfg: AnnouncementSourceConfig
  ): ShuYoAnnouncementItem[] {
    const section = AnnouncementParser.extractDivByClass(html, 'right-list');
    if (section.length === 0) {
      return [];
    }
    return AnnouncementParser.parseListItemsWithSpanDate(section, baseUrl, cfg);
  }

  private static parseListItemsWithSpanDate(
    section: string,
    baseUrl: string,
    cfg: AnnouncementSourceConfig
  ): ShuYoAnnouncementItem[] {
    const items: ShuYoAnnouncementItem[] = [];
    const seen = new Set<string>();
    const liRe = new RegExp('<li\\b[^>]*>([\\s\\S]*?)<\\/li>', 'gi');
    let m = liRe.exec(section);
    while (m !== null && items.length < 30) {
      const inner = m[1];
      const aMatch = new RegExp('<a\\b([^>]*)>([\\s\\S]*?)<\\/a>', 'i').exec(inner);
      if (aMatch === null) {
        m = liRe.exec(section);
        continue;
      }
      const href = AnnouncementParser.extractAttr(aMatch[1], 'href');
      const attrTitle = AnnouncementParser.extractAttr(aMatch[1], 'title');
      const innerTitle = AnnouncementParser.cleanHtmlText(aMatch[2]);
      const title = innerTitle.length > 0 ? innerTitle : AnnouncementParser.decodeEntities(attrTitle).trim();
      const fullUrl = WebVpnProtocol.resolveUrl(baseUrl, href);
      if (title.length === 0 || fullUrl.length === 0 || href.toLowerCase().startsWith('javascript:') || seen.has(fullUrl)) {
        m = liRe.exec(section);
        continue;
      }
      seen.add(fullUrl);
      const spanMatch = new RegExp('<span\\b[^>]*>([\\s\\S]*?)<\\/span>', 'i').exec(inner);
      const rawDate = spanMatch !== null
        ? AnnouncementParser.cleanHtmlText(spanMatch[1])
        : AnnouncementParser.cleanHtmlText(inner);
      const dateText = AnnouncementParser.normalizeDateString(rawDate);
      items.push({
        id: `${cfg.id}-${items.length}`,
        title: title,
        url: fullUrl,
        summary: '',
        dateText: dateText.length > 0 ? dateText : '校内通知',
        sourceName: cfg.name,
        author: cfg.name,
        department: cfg.name,
        blocks: []
      });
      m = liRe.exec(section);
    }
    return items;
  }

  private static parseArtList(
    html: string,
    baseUrl: string,
    cfg: AnnouncementSourceConfig
  ): ShuYoAnnouncementItem[] {
    const items: ShuYoAnnouncementItem[] = [];
    const seen = new Set<string>();
    const tableRe = new RegExp('<table\\b[^>]*class=["\'][^"\']*\\bArtList\\b[^"\']*["\'][^>]*>([\\s\\S]*?)<\\/table>', 'gi');
    let m = tableRe.exec(html);
    while (m !== null && items.length < 30) {
      const tableBody = m[1];
      const aRe = new RegExp('<a\\b([^>]*)>([\\s\\S]*?)<\\/a>', 'gi');
      let aMatch = aRe.exec(tableBody);
      let href = '';
      let title = '';
      while (aMatch !== null) {
        const cls = AnnouncementParser.extractAttr(aMatch[1], 'class');
        if (cls.includes('linkfont1') || title.length === 0) {
          href = AnnouncementParser.extractAttr(aMatch[1], 'href');
          const innerT = AnnouncementParser.cleanHtmlText(aMatch[2]);
          const attrT = AnnouncementParser.decodeEntities(AnnouncementParser.extractAttr(aMatch[1], 'title')).trim();
          title = innerT.length > 0 ? innerT : attrT;
          if (cls.includes('linkfont1')) {
            break;
          }
        }
        aMatch = aRe.exec(tableBody);
      }
      const fullUrl = WebVpnProtocol.resolveUrl(baseUrl, href);
      if (title.length > 0 && fullUrl.length > 0 && !seen.has(fullUrl)) {
        seen.add(fullUrl);
        const spanMatch = new RegExp('<span\\b[^>]*class=["\'][^"\']*linkfont1[^"\']*["\'][^>]*>([\\s\\S]*?)<\\/span>', 'i').exec(tableBody);
        const dateSource = spanMatch !== null
          ? AnnouncementParser.cleanHtmlText(spanMatch[1])
          : AnnouncementParser.cleanHtmlText(tableBody);
        const dateText = AnnouncementParser.normalizeDateString(dateSource);
        items.push({
          id: `${cfg.id}-${items.length}`,
          title: title,
          url: fullUrl,
          summary: '',
          dateText: dateText.length > 0 ? dateText : '校内通知',
          sourceName: cfg.name,
          author: cfg.name,
          department: cfg.name,
          blocks: []
        });
      }
      m = tableRe.exec(html);
    }
    return items;
  }

  private static parseVsbTable(
    html: string,
    baseUrl: string,
    cfg: AnnouncementSourceConfig
  ): ShuYoAnnouncementItem[] {
    const items: ShuYoAnnouncementItem[] = [];
    const seen = new Set<string>();
    const trRe = new RegExp('<tr\\b[^>]*id=["\']line_u[^"\']*["\'][^>]*>([\\s\\S]*?)<\\/tr>', 'gi');
    let m = trRe.exec(html);
    while (m !== null && items.length < 30) {
      const rowBody = m[1];
      const aMatch = new RegExp('<a\\b([^>]*)>([\\s\\S]*?)<\\/a>', 'i').exec(rowBody);
      if (aMatch === null) {
        m = trRe.exec(html);
        continue;
      }
      const href = AnnouncementParser.extractAttr(aMatch[1], 'href');
      const title = AnnouncementParser.cleanHtmlText(aMatch[2]);
      const fullUrl = WebVpnProtocol.resolveUrl(baseUrl, href);
      if (title.length === 0 || fullUrl.length === 0 || seen.has(fullUrl)) {
        m = trRe.exec(html);
        continue;
      }
      seen.add(fullUrl);
      const tdMatches: string[] = [];
      const tdRe = new RegExp('<td\\b[^>]*>([\\s\\S]*?)<\\/td>', 'gi');
      let tdM = tdRe.exec(rowBody);
      while (tdM !== null) {
        tdMatches.push(AnnouncementParser.cleanHtmlText(tdM[1]));
        tdM = tdRe.exec(rowBody);
      }
      const rawDate = tdMatches.length > 1 ? tdMatches[1] : AnnouncementParser.cleanHtmlText(rowBody);
      const dateText = AnnouncementParser.normalizeDateString(rawDate);
      items.push({
        id: `${cfg.id}-${items.length}`,
        title: title,
        url: fullUrl,
        summary: '',
        dateText: dateText.length > 0 ? dateText : '校内通知',
        sourceName: cfg.name,
        author: cfg.name,
        department: cfg.name,
        blocks: []
      });
      m = trRe.exec(html);
    }
    return items;
  }

  private static parseCentreList(
    html: string,
    baseUrl: string,
    cfg: AnnouncementSourceConfig
  ): ShuYoAnnouncementItem[] {
    const section = AnnouncementParser.extractDivByClass(html, 'list-centre-right-down');
    if (section.length === 0) {
      return [];
    }
    const items: ShuYoAnnouncementItem[] = [];
    const seen = new Set<string>();
    const liRe = new RegExp('<li\\b[^>]*class=["\'][^"\']*\\bclearfix\\b[^"\']*["\'][^>]*>([\\s\\S]*?)<\\/li>', 'gi');
    let m = liRe.exec(section);
    while (m !== null && items.length < 30) {
      const inner = m[1];
      const aMatch = new RegExp('<a\\b([^>]*)>([\\s\\S]*?)<\\/a>', 'i').exec(inner);
      if (aMatch === null) {
        m = liRe.exec(section);
        continue;
      }
      const href = AnnouncementParser.extractAttr(aMatch[1], 'href');
      const innerTitle = AnnouncementParser.cleanHtmlText(aMatch[2]);
      const attrTitle = AnnouncementParser.decodeEntities(AnnouncementParser.extractAttr(aMatch[1], 'title')).trim();
      const title = innerTitle.length > 0 ? innerTitle : attrTitle;
      const fullUrl = WebVpnProtocol.resolveUrl(baseUrl, href);
      if (title.length === 0 || fullUrl.length === 0 || seen.has(fullUrl)) {
        m = liRe.exec(section);
        continue;
      }
      seen.add(fullUrl);
      const pMatch = new RegExp('<p\\b[^>]*class=["\'][^"\']*list-centre-right-down-p[^"\']*["\'][^>]*>([\\s\\S]*?)<\\/p>', 'i').exec(inner);
      const rawDate = pMatch !== null
        ? AnnouncementParser.cleanHtmlText(pMatch[1])
        : AnnouncementParser.cleanHtmlText(inner);
      const dateText = AnnouncementParser.normalizeDateString(rawDate);
      items.push({
        id: `${cfg.id}-${items.length}`,
        title: title,
        url: fullUrl,
        summary: '',
        dateText: dateText.length > 0 ? dateText : '校内通知',
        sourceName: cfg.name,
        author: cfg.name,
        department: cfg.name,
        blocks: []
      });
      m = liRe.exec(section);
    }
    return items;
  }

  private static makeHtmlElement(tag: string, attrs: Map<string, string>): HtmlNode {
    return {
      isText: false,
      tag: tag,
      text: '',
      attrs: attrs,
      children: []
    };
  }

  private static makeHtmlText(text: string): HtmlNode {
    return {
      isText: true,
      tag: '#text',
      text: text,
      attrs: new Map<string, string>(),
      children: []
    };
  }

  private static parseAttributes(attrRaw: string): Map<string, string> {
    const attrs = new Map<string, string>();
    const len = attrRaw.length;
    let i = 0;
    while (i < len) {
      while (i < len && AnnouncementParser.isSpaceChar(attrRaw.charAt(i))) {
        i++;
      }
      if (i >= len || attrRaw.charAt(i) === '/') {
        break;
      }
      const nameStart = i;
      while (i < len) {
        const ch = attrRaw.charAt(i);
        if (AnnouncementParser.isSpaceChar(ch) || ch === '=' || ch === '/' || ch === '>') {
          break;
        }
        i++;
      }
      const attrName = attrRaw.substring(nameStart, i).toLowerCase();
      while (i < len && AnnouncementParser.isSpaceChar(attrRaw.charAt(i))) {
        i++;
      }
      let attrVal = '';
      if (i < len && attrRaw.charAt(i) === '=') {
        i++;
        while (i < len && AnnouncementParser.isSpaceChar(attrRaw.charAt(i))) {
          i++;
        }
        if (i < len && (attrRaw.charAt(i) === '"' || attrRaw.charAt(i) === "'")) {
          const quote = attrRaw.charAt(i);
          i++;
          const valStart = i;
          while (i < len && attrRaw.charAt(i) !== quote) {
            i++;
          }
          attrVal = attrRaw.substring(valStart, i);
          if (i < len) {
            i++;
          }
        } else {
          const valStart = i;
          while (i < len && !AnnouncementParser.isSpaceChar(attrRaw.charAt(i)) && attrRaw.charAt(i) !== '>') {
            i++;
          }
          attrVal = attrRaw.substring(valStart, i);
        }
      }
      if (attrName.length > 0) {
        attrs.set(attrName, AnnouncementParser.decodeEntities(attrVal).trim());
      }
    }
    return attrs;
  }

  private static isSpaceChar(ch: string): boolean {
    return ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r' || ch === '\f';
  }

  private static parseHtmlTree(html: string): HtmlNode {
    const root = AnnouncementParser.makeHtmlElement('root', new Map<string, string>());
    const stack: HtmlNode[] = [root];
    const len = html.length;
    let pos = 0;

    while (pos < len) {
      const lt = html.indexOf('<', pos);
      if (lt < 0) {
        if (pos < len) {
          stack[stack.length - 1].children.push(AnnouncementParser.makeHtmlText(html.substring(pos)));
        }
        break;
      }
      if (lt > pos) {
        stack[stack.length - 1].children.push(AnnouncementParser.makeHtmlText(html.substring(pos, lt)));
      }

      if (html.startsWith('<!--', lt)) {
        const endComment = html.indexOf('-->', lt + 4);
        pos = endComment >= 0 ? endComment + 3 : len;
        continue;
      }

      if (html.startsWith('<!', lt) || html.startsWith('<?', lt)) {
        const gtDecl = html.indexOf('>', lt + 2);
        pos = gtDecl >= 0 ? gtDecl + 1 : len;
        continue;
      }

      const gt = AnnouncementParser.findTagClose(html, lt + 1);
      if (gt < 0) {
        stack[stack.length - 1].children.push(AnnouncementParser.makeHtmlText(html.substring(lt)));
        break;
      }

      const tagInside = html.substring(lt + 1, gt).trim();
      pos = gt + 1;
      if (tagInside.length === 0) {
        continue;
      }

      if (tagInside.startsWith('/')) {
        const closeTag = tagInside.substring(1).trim().toLowerCase();
        const spIdx = closeTag.search(new RegExp('\\s'));
        const closeName = spIdx >= 0 ? closeTag.substring(0, spIdx) : closeTag;
        for (let s = stack.length - 1; s >= 1; s--) {
          if (stack[s].tag === closeName) {
            while (stack.length > s) {
              stack.pop();
            }
            break;
          }
        }
        continue;
      }

      const selfClosing = tagInside.endsWith('/');
      const cleanBody = selfClosing ? tagInside.substring(0, tagInside.length - 1).trim() : tagInside;
      const firstWs = cleanBody.search(new RegExp('\\s'));
      const tagName = (firstWs >= 0 ? cleanBody.substring(0, firstWs) : cleanBody).toLowerCase();
      const attrRaw = firstWs >= 0 ? cleanBody.substring(firstWs + 1) : '';
      if (tagName.length === 0) {
        continue;
      }

      if (tagName === 'tr') {
        while (stack.length > 1 && (stack[stack.length - 1].tag === 'td' || stack[stack.length - 1].tag === 'th')) {
          stack.pop();
        }
        if (stack.length > 1 && stack[stack.length - 1].tag === 'tr') {
          stack.pop();
        }
      } else if (tagName === 'td' || tagName === 'th') {
        while (stack.length > 1 && (stack[stack.length - 1].tag === 'td' || stack[stack.length - 1].tag === 'th')) {
          stack.pop();
        }
      }

      const node = AnnouncementParser.makeHtmlElement(tagName, AnnouncementParser.parseAttributes(attrRaw));
      stack[stack.length - 1].children.push(node);

      if (tagName === 'script' || tagName === 'style') {
        if (!selfClosing) {
          const closeRe = new RegExp(`<\\/${tagName}\\s*>`, 'i');
          const restHtml = html.substring(pos);
          const closeMatch = closeRe.exec(restHtml);
          if (closeMatch !== null) {
            const rawCode = restHtml.substring(0, closeMatch.index);
            if (rawCode.length > 0) {
              node.children.push(AnnouncementParser.makeHtmlText(rawCode));
            }
            pos += closeMatch.index + closeMatch[0].length;
          } else {
            pos = len;
          }
        }
        continue;
      }

      if (!selfClosing && !AnnouncementParser.htmlVoidTags.has(tagName)) {
        stack.push(node);
      }
    }

    return root;
  }

  private static findTagClose(html: string, startIdx: number): number {
    let quote = '';
    const len = html.length;
    for (let i = startIdx; i < len; i++) {
      const ch = html.charAt(i);
      if (quote.length > 0) {
        if (ch === quote) {
          quote = '';
        }
      } else if (ch === '"' || ch === "'") {
        quote = ch;
      } else if (ch === '>') {
        return i;
      }
    }
    return -1;
  }

  private static collectNodesByTag(root: HtmlNode, targetTags: string[], stopAtTag: string = ''): HtmlNode[] {
    const out: HtmlNode[] = [];
    const stack: HtmlNode[] = [root];
    while (stack.length > 0) {
      const cur = stack.pop()!;
      if (cur !== root && !cur.isText && stopAtTag.length > 0 && cur.tag === stopAtTag) {
        continue;
      }
      if (cur !== root && !cur.isText && targetTags.includes(cur.tag)) {
        out.push(cur);
      }
      for (let i = cur.children.length - 1; i >= 0; i--) {
        stack.push(cur.children[i]);
      }
    }
    return out;
  }

  private static collectVisibleNodeTextRaw(node: HtmlNode): string {
    if (node.isText) {
      return node.text;
    }
    if (node.tag === 'script' || node.tag === 'style') {
      return '';
    }
    if (node.tag === 'br') {
      return ' ';
    }
    let combined = '';
    for (let i = 0; i < node.children.length; i++) {
      const part = AnnouncementParser.collectVisibleNodeTextRaw(node.children[i]);
      if (part.length > 0) {
        if (combined.length > 0) {
          combined += ' ';
        }
        combined += part;
      }
    }
    return combined;
  }

  private static cleanNodeText(node: HtmlNode): string {
    return AnnouncementParser.decodeEntities(AnnouncementParser.collectVisibleNodeTextRaw(node))
      .replace(new RegExp('\\u00a0', 'g'), ' ')
      .replace(new RegExp('\\s+', 'g'), ' ')
      .trim();
  }

  private static hasDescendantTag(node: HtmlNode, tagName: string): boolean {
    for (let i = 0; i < node.children.length; i++) {
      const child = node.children[i];
      if (!child.isText) {
        if (child.tag === tagName || AnnouncementParser.hasDescendantTag(child, tagName)) {
          return true;
        }
      }
    }
    return false;
  }

  static resolveHttpUrl(baseUrl: string, rawUrl: string): string {
    const trimmed = rawUrl.trim();
    if (trimmed.length === 0 || trimmed.toLowerCase().startsWith('javascript:')) {
      return '';
    }
    const resolved = WebVpnProtocol.resolveUrl(baseUrl, trimmed);
    const lower = resolved.toLowerCase();
    return (lower.startsWith('https://') || lower.startsWith('http://')) ? resolved : '';
  }

  static parseContentBlocks(
    contentHtml: string,
    pageUrl: string,
    fullHtml: string
  ): ShuYoAnnouncementBlock[] {
    const blocks: ShuYoAnnouncementBlock[] = [];
    const seenLinks = new Set<string>();
    const seenImages = new Set<string>();
    const root = AnnouncementParser.parseHtmlTree(contentHtml);

    const addImage = (imgNode: HtmlNode): void => {
      const src = imgNode.attrs.get('orisrc') ??
        imgNode.attrs.get('data-src') ??
        imgNode.attrs.get('src') ??
        imgNode.attrs.get('vurl') ??
        '';
      const imageUrl = AnnouncementParser.resolveHttpUrl(pageUrl, src);
      if (imageUrl.length === 0 || seenImages.has(imageUrl)) {
        return;
      }
      seenImages.add(imageUrl);
      const altRaw = imgNode.attrs.get('alt') ?? imgNode.attrs.get('title') ?? '';
      const altText = AnnouncementParser.cleanHtmlText(altRaw);
      blocks.push({
        blockType: 'image',
        blockValue: imageUrl,
        alt: altText.length > 0 ? altText : undefined
      });
    };

    const addLink = (aNode: HtmlNode): void => {
      const href = aNode.attrs.get('href') ?? '';
      const linkUrl = AnnouncementParser.resolveHttpUrl(pageUrl, href);
      if (linkUrl.length === 0 || seenLinks.has(linkUrl)) {
        return;
      }
      seenLinks.add(linkUrl);
      const labelText = AnnouncementParser.cleanNodeText(aNode);
      blocks.push({
        blockType: 'link',
        blockValue: linkUrl,
        label: labelText.length > 0 ? labelText : '查看附件'
      });
    };

    const scriptNodes = AnnouncementParser.collectNodesByTag(root, ['script']);
    for (let s = 0; s < scriptNodes.length; s++) {
      let code = '';
      for (let c = 0; c < scriptNodes[s].children.length; c++) {
        code += scriptNodes[s].children[c].text;
      }
      const pdfMatch = new RegExp('showVsbpdfIframe\\(\\s*["\']([^"\']+\\.pdf)["\']', 'i').exec(code);
      if (pdfMatch === null) {
        continue;
      }
      const imgInScriptRe = new RegExp('["\']([^"\']+\\.(?:jpg|jpeg|png))["\']', 'gi');
      let imgM = imgInScriptRe.exec(code);
      while (imgM !== null) {
        const imgUrl = AnnouncementParser.resolveHttpUrl(pageUrl, imgM[1]);
        if (imgUrl.length > 0 && !seenImages.has(imgUrl)) {
          seenImages.add(imgUrl);
          blocks.push({
            blockType: 'image',
            blockValue: imgUrl,
            alt: 'PDF 预览页'
          });
        }
        imgM = imgInScriptRe.exec(code);
      }
      const pdfUrl = AnnouncementParser.resolveHttpUrl(pageUrl, pdfMatch[1]);
      if (pdfUrl.length > 0 && !seenLinks.has(pdfUrl)) {
        seenLinks.add(pdfUrl);
        blocks.push({
          blockType: 'link',
          blockValue: pdfUrl,
          label: '查看原始 PDF'
        });
      }
    }

    const visit = (node: HtmlNode): void => {
      if (node.isText) {
        const t = AnnouncementParser.decodeEntities(node.text)
          .replace(new RegExp('\\u00a0', 'g'), ' ')
          .replace(new RegExp('\\s+', 'g'), ' ')
          .trim();
        if (t.length > 0) {
          blocks.push({ blockType: 'text', blockValue: t });
        }
        return;
      }

      const tag = node.tag;
      if (tag === 'script' || tag === 'style') {
        return;
      }

      if (tag === 'table') {
        const trNodes = AnnouncementParser.collectNodesByTag(node, ['tr'], 'table');
        const rows: string[][] = [];
        for (let r = 0; r < trNodes.length; r++) {
          const tr = trNodes[r];
          const cells: string[] = [];
          for (let c = 0; c < tr.children.length; c++) {
            const cellNode = tr.children[c];
            if (!cellNode.isText && (cellNode.tag === 'td' || cellNode.tag === 'th')) {
              cells.push(AnnouncementParser.cleanNodeText(cellNode));
            }
          }
          if (cells.length === 0) {
            const deepCells = AnnouncementParser.collectNodesByTag(tr, ['td', 'th'], 'table');
            for (let c = 0; c < deepCells.length; c++) {
              cells.push(AnnouncementParser.cleanNodeText(deepCells[c]));
            }
          }
          let hasNonEmpty = false;
          for (let c = 0; c < cells.length; c++) {
            if (cells[c].length > 0) {
              hasNonEmpty = true;
              break;
            }
          }
          if (hasNonEmpty) {
            rows.push(cells);
          }
        }
        if (rows.length > 0) {
          blocks.push({
            blockType: 'table',
            blockValue: '',
            rows: rows
          });
        }
        const tableImgs = AnnouncementParser.collectNodesByTag(node, ['img']);
        for (let i = 0; i < tableImgs.length; i++) {
          addImage(tableImgs[i]);
        }
        const tableLinks = AnnouncementParser.collectNodesByTag(node, ['a']);
        for (let i = 0; i < tableLinks.length; i++) {
          addLink(tableLinks[i]);
        }
        return;
      }

      if (tag === 'img') {
        addImage(node);
        return;
      }

      if (tag === 'a') {
        const imgs = AnnouncementParser.collectNodesByTag(node, ['img']);
        for (let i = 0; i < imgs.length; i++) {
          addImage(imgs[i]);
        }
        addLink(node);
        return;
      }

      if (tag === 'p' || tag === 'li' || tag === 'h1' || tag === 'h2' ||
        tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6' || tag === 'blockquote') {
        if (AnnouncementParser.hasDescendantTag(node, 'table')) {
          for (let i = 0; i < node.children.length; i++) {
            visit(node.children[i]);
          }
          return;
        }
        const text = AnnouncementParser.cleanNodeText(node);
        const anchors = AnnouncementParser.collectNodesByTag(node, ['a']);
        const onlySingleLinkText = anchors.length === 1 &&
          AnnouncementParser.cleanNodeText(anchors[0]) === text;
        if (text.length > 0 && !onlySingleLinkText) {
          blocks.push({
            blockType: 'text',
            blockValue: tag === 'li' ? `• ${text}` : text
          });
        }
        const imgs = AnnouncementParser.collectNodesByTag(node, ['img']);
        for (let i = 0; i < imgs.length; i++) {
          addImage(imgs[i]);
        }
        for (let i = 0; i < anchors.length; i++) {
          addLink(anchors[i]);
        }
        return;
      }

      let hasElementChild = false;
      for (let i = 0; i < node.children.length; i++) {
        if (!node.children[i].isText) {
          hasElementChild = true;
          break;
        }
      }
      if (!hasElementChild) {
        const leafText = AnnouncementParser.cleanNodeText(node);
        if (leafText.length > 0) {
          blocks.push({ blockType: 'text', blockValue: leafText });
        }
        return;
      }

      let inlineGroup: HtmlNode[] = [];
      const flushInlineGroup = (): void => {
        if (inlineGroup.length === 0) {
          return;
        }
        const wrapper = AnnouncementParser.makeHtmlElement('span', new Map<string, string>());
        wrapper.children = inlineGroup;
        inlineGroup = [];
        const text = AnnouncementParser.cleanNodeText(wrapper);
        const anchors = AnnouncementParser.collectNodesByTag(wrapper, ['a']);
        const onlySingleLink = anchors.length === 1 &&
          AnnouncementParser.cleanNodeText(anchors[0]) === text;
        if (text.length > 0 && !onlySingleLink) {
          blocks.push({ blockType: 'text', blockValue: text });
        }
        const imgs = AnnouncementParser.collectNodesByTag(wrapper, ['img']);
        for (let k = 0; k < imgs.length; k++) {
          addImage(imgs[k]);
        }
        for (let k = 0; k < anchors.length; k++) {
          addLink(anchors[k]);
        }
      };

      for (let i = 0; i < node.children.length; i++) {
        const child = node.children[i];
        const isBlockLike = !child.isText &&
          (AnnouncementParser.htmlBlockTags.has(child.tag) ||
            AnnouncementParser.hasDescendantTag(child, 'table') ||
            AnnouncementParser.hasDescendantTag(child, 'img'));
        if (isBlockLike) {
          flushInlineGroup();
          visit(child);
        } else {
          inlineGroup.push(child);
        }
      }
      flushInlineGroup();
    };

    for (let i = 0; i < root.children.length; i++) {
      visit(root.children[i]);
    }

    if (blocks.length === 0) {
      const plain = AnnouncementParser.cleanNodeText(root);
      if (plain.length > 0) {
        blocks.push({ blockType: 'text', blockValue: plain });
      }
    }

    const attachRe = new RegExp('<a\\b([^>]*)>([\\s\\S]*?)<\\/a>', 'gi');
    let am = attachRe.exec(fullHtml);
    while (am !== null) {
      const href = AnnouncementParser.extractAttr(am[1], 'href');
      if (href.includes('DownloadAttachUrl')) {
        const resolved = AnnouncementParser.resolveHttpUrl(pageUrl, href);
        if (resolved.length > 0 && !seenLinks.has(resolved)) {
          seenLinks.add(resolved);
          const label = AnnouncementParser.cleanHtmlText(am[2]);
          blocks.push({
            blockType: 'link',
            blockValue: resolved,
            label: label.length > 0 ? label : '查看附件'
          });
        }
      }
      am = attachRe.exec(fullHtml);
    }

    if (blocks.length === 0 && pageUrl.length > 0) {
      blocks.push({
        blockType: 'link',
        blockValue: pageUrl,
        label: '原文链接'
      });
    }
    return blocks;
  }

  static parseDetailMetadata(metaHtml: string): ParsedAnnouncementMeta {
    let dateText = '';
    let author = '';
    let department = '';
    if (metaHtml.length === 0) {
      return { dateText: '', author: '', department: '' };
    }
    const spanRe = new RegExp('<span\\b[^>]*>([\\s\\S]*?)<\\/span>', 'gi');
    let m = spanRe.exec(metaHtml);
    while (m !== null) {
      const text = AnnouncementParser.cleanHtmlText(m[1]);
      if (text.startsWith('发布时间：')) {
        const parsed = AnnouncementParser.normalizeDateString(text.substring('发布时间：'.length));
        dateText = parsed.length > 0 ? parsed : text.substring('发布时间：'.length).trim();
      } else if (text.startsWith('投稿：')) {
        author = text.substring('投稿：'.length).trim();
      } else if (text.startsWith('部门：')) {
        department = text.substring('部门：'.length).trim();
      }
      m = spanRe.exec(metaHtml);
    }
    return {
      dateText: dateText,
      author: author,
      department: department
    };
  }

  static extractDivByClass(html: string, className: string): string {
    const startRe = new RegExp(`<div\\b[^>]*class=["'][^"']*\\b${className}\\b[^"']*["'][^>]*>`, 'i');
    const m = startRe.exec(html);
    if (m === null) {
      return '';
    }
    return AnnouncementParser.extractBalancedDiv(html, m.index);
  }

  static extractDivById(html: string, idValue: string): string {
    const startRe = new RegExp(`<div\\b[^>]*id=["']${idValue}["'][^>]*>`, 'i');
    const m = startRe.exec(html);
    if (m === null) {
      return '';
    }
    return AnnouncementParser.extractBalancedDiv(html, m.index);
  }

  private static extractBalancedDiv(html: string, divStartIdx: number): string {
    const tagRe = new RegExp('<(\\/)?div\\b[^>]*>', 'gi');
    tagRe.lastIndex = divStartIdx;
    let depth = 0;
    let m = tagRe.exec(html);
    while (m !== null) {
      const isClosing = m[1] === '/';
      if (isClosing) {
        depth--;
        if (depth <= 0) {
          return html.substring(divStartIdx, tagRe.lastIndex);
        }
      } else {
        depth++;
      }
      m = tagRe.exec(html);
    }
    return html.substring(divStartIdx, Math.min(html.length, divStartIdx + 30000));
  }

  static extractFirstTagText(html: string, tagName: string): string {
    const re = new RegExp(`<${tagName}\\b[^>]*>([\\s\\S]*?)<\\/${tagName}>`, 'i');
    const m = re.exec(html);
    return m !== null ? AnnouncementParser.cleanHtmlText(m[1]) : '';
  }

  private static extractAttr(attrs: string, attrName: string): string {
    const re = new RegExp(`\\b${attrName}\\s*=\\s*["']([^"']*)["']`, 'i');
    const m = re.exec(attrs);
    return m !== null ? m[1].trim() : '';
  }

  private static cleanHtmlText(fragment: string): string {
    const noTags = fragment
      .replace(new RegExp('<br\\s*\\/?>', 'gi'), ' ')
      .replace(new RegExp('<[^>]+>', 'g'), ' ');
    return AnnouncementParser.decodeEntities(noTags)
      .replace(new RegExp('\\u00a0', 'g'), ' ')
      .replace(new RegExp('\\s+', 'g'), ' ')
      .trim();
  }

  static decodeEntities(text: string): string {
    let res = text
      .replace(new RegExp('&nbsp;', 'gi'), ' ')
      .replace(new RegExp('&amp;', 'gi'), '&')
      .replace(new RegExp('&lt;', 'gi'), '<')
      .replace(new RegExp('&gt;', 'gi'), '>')
      .replace(new RegExp('&quot;', 'gi'), '"')
      .replace(new RegExp('&apos;|&#39;', 'gi'), "'")
      .replace(new RegExp('&ldquo;', 'gi'), '“')
      .replace(new RegExp('&rdquo;', 'gi'), '”')
      .replace(new RegExp('&mdash;', 'gi'), '—')
      .replace(new RegExp('&hellip;', 'gi'), '…');
    res = res.replace(new RegExp('&#x([0-9a-fA-F]+);', 'g'), (_all: string, hex: string): string => {
      const code = parseInt(hex, 16);
      return Number.isFinite(code) && code > 0 ? String.fromCharCode(code) : '';
    });
    res = res.replace(new RegExp('&#(\\d+);', 'g'), (_all: string, dec: string): string => {
      const code = parseInt(dec, 10);
      return Number.isFinite(code) && code > 0 ? String.fromCharCode(code) : '';
    });
    return res;
  }

  static normalizeDateString(raw: string): string {
    const m = new RegExp('(\\d{4})[.\\-/年](\\d{1,2})[.\\-/月](\\d{1,2})').exec(raw);
    if (m === null) {
      return '';
    }
    const y = m[1];
    const mo = m[2].length === 1 ? `0${m[2]}` : m[2];
    const d = m[3].length === 1 ? `0${m[3]}` : m[3];
    return `${y}-${mo}-${d}`;
  }

  static compareDateDesc(aDate: string, bDate: string): number {
    const normA = AnnouncementParser.normalizeDateString(aDate);
    const normB = AnnouncementParser.normalizeDateString(bDate);
    if (normA.length === 0 && normB.length === 0) {
      return 0;
    }
    if (normA.length === 0) {
      return 1;
    }
    if (normB.length === 0) {
      return -1;
    }
    if (normA > normB) {
      return -1;
    }
    if (normA < normB) {
      return 1;
    }
    return 0;
  }
}
