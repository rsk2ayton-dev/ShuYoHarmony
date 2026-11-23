import { bundleManager, common, OpenLinkOptions } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { i18n, intl } from '@kit.LocalizationKit';
import { UIContext } from '@kit.ArkUI';
import { ShuYoConstants } from '../core/ShuYoConstants';

export interface ShuYoBundleMeta {
  versionName: string;
  versionCode: number;
  bundleName: string;
}

/**
 * Bridges platform system capabilities via native HarmonyOS Kits:
 * - @kit.AbilityKit (bundleManager, openLink)
 * - @kit.ShareKit (systemShare panel)
 * - @kit.LocalizationKit (Chinese lunar calendar)
 * - @kit.BasicServicesKit (pasteboard fallback)
 */
export class NativeSystemService {
  private static abilityContext: common.UIAbilityContext | undefined = undefined;
  private static pendingLaunchTab: string = '';

  private static readonly lunarMonthNames: string[] = [
    '正月', '二月', '三月', '四月', '五月', '六月',
    '七月', '八月', '九月', '十月', '冬月', '腊月'
  ];

  private static readonly lunarDayNames: string[] = [
    '', '初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
    '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
    '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十'
  ];

  static init(context: common.UIAbilityContext): void {
    NativeSystemService.abilityContext = context;
  }

  static getContext(): common.UIAbilityContext | undefined {
    return NativeSystemService.abilityContext;
  }

  static setPendingLaunchTab(tab: string): void {
    NativeSystemService.pendingLaunchTab = tab;
  }

  static consumePendingLaunchTab(): string {
    const val = NativeSystemService.pendingLaunchTab;
    NativeSystemService.pendingLaunchTab = '';
    return val;
  }

  static getBundleMeta(): ShuYoBundleMeta {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return {
        versionName: info.versionName.length > 0 ? info.versionName : ShuYoConstants.appVersion,
        versionCode: info.versionCode > 0 ? info.versionCode : ShuYoConstants.buildNumber,
        bundleName: info.name.length > 0 ? info.name : ShuYoConstants.bundleName
      };
    } catch (_err) {
      return {
        versionName: ShuYoConstants.appVersion,
        versionCode: ShuYoConstants.buildNumber,
        bundleName: ShuYoConstants.bundleName
      };
    }
  }

  static copyToClipboard(text: string): boolean {
    if (text.length === 0) {
      return false;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setDataSync(data);
      return true;
    } catch (_err) {
      return false;
    }
  }

  private static resolveAbilityContext(uiContext?: UIContext): common.UIAbilityContext | undefined {
    if (uiContext !== undefined) {
      try {
        const hostCtx = uiContext.getHostContext();
        if (hostCtx !== undefined) {
          return hostCtx as common.UIAbilityContext;
        }
      } catch (_err) {
        // Ignore host context resolution failure
      }
    }
    return NativeSystemService.abilityContext;
  }

  static async openExternalUrl(url: string, uiContext?: UIContext): Promise<boolean> {
    const trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      if (uiContext !== undefined) {
        uiContext.getPromptAction().showToast({ message: '仅支持打开 http/https 链接' });
      }
      return false;
    }

    const ctx = NativeSystemService.resolveAbilityContext(uiContext);
    if (ctx !== undefined) {
      try {
        const opts: OpenLinkOptions = { appLinkingOnly: false };
        await ctx.openLink(trimmed, opts);
        return true;
      } catch (_err) {
        // Fall back to clipboard copy below
      }
    }

    NativeSystemService.copyToClipboard(trimmed);
    if (uiContext !== undefined) {
      uiContext.getPromptAction().showToast({ message: '已复制链接到剪贴板，请在浏览器中打开' });
    }
    return false;
  }

  static async shareText(
    title: string,
    content: string,
    description: string,
    uiContext?: UIContext
  ): Promise<boolean> {
    const trimmed = content.trim();
    if (trimmed.length === 0) {
      return false;
    }
    // Keep Share Kit IPC payload well within the 200 KB cap
    const safeContent = trimmed.length > 60000 ? trimmed.substring(0, 60000) : trimmed;
    const ctx = NativeSystemService.resolveAbilityContext(uiContext);
    if (ctx !== undefined) {
      try {
        const data = new systemShare.SharedData({
          utd: utd.UniformDataType.PLAIN_TEXT,
          content: safeContent,
          title: title,
          description: description
        });
        const controller = new systemShare.ShareController(data);
        await controller.show(ctx, {
          previewMode: systemShare.SharePreviewMode.DEFAULT,
          selectionMode: systemShare.SelectionMode.SINGLE
        });
        return true;
      } catch (_err) {
        // Fall through to clipboard copy fallback
      }
    }

    NativeSystemService.copyToClipboard(trimmed);
    if (uiContext !== undefined) {
      uiContext.getPromptAction().showToast({ message: '系统分享不可用，已复制内容到剪贴板' });
    }
    return false;
  }

  static async shareLink(
    title: string,
    url: string,
    description: string,
    uiContext?: UIContext
  ): Promise<boolean> {
    const trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return false;
    }
    const ctx = NativeSystemService.resolveAbilityContext(uiContext);
    if (ctx !== undefined) {
      try {
        const data = new systemShare.SharedData({
          utd: utd.UniformDataType.HYPERLINK,
          content: trimmed,
          title: title,
          description: description
        });
        const controller = new systemShare.ShareController(data);
        await controller.show(ctx, {
          previewMode: systemShare.SharePreviewMode.DEFAULT,
          selectionMode: systemShare.SelectionMode.SINGLE
        });
        return true;
      } catch (_err) {
        // Fall through to clipboard copy fallback
      }
    }

    NativeSystemService.copyToClipboard(trimmed);
    if (uiContext !== undefined) {
      uiContext.getPromptAction().showToast({ message: '已复制链接到剪贴板' });
    }
    return false;
  }

  static getTodayLunarLabel(): string {
    const now = new Date();
    try {
      const lunarLocale = new intl.Locale('zh-Hans-CN', { calendar: 'chinese' });
      const fmt = new intl.DateTimeFormat(lunarLocale.toString(), {
        month: 'long',
        day: 'numeric'
      });
      const formatted = fmt.format(now).trim();
      if (formatted.length > 0 && /[\u4e00-\u9fa5]/.test(formatted)) {
        const cleaned = formatted.replace(/^\d{4}年?/, '').trim();
        if (cleaned.length > 0) {
          return cleaned.startsWith('农历') ? cleaned : `农历${cleaned}`;
        }
      }
    } catch (_err) {
      // Fall through to i18n.getCalendar fallback
    }

    try {
      const cal = i18n.getCalendar('zh-Hans', 'chinese');
      cal.setTime(now);
      const monthIdx = cal.get('month');
      const dayNum = cal.get('date');
      const monthText = monthIdx >= 0 && monthIdx < NativeSystemService.lunarMonthNames.length
        ? NativeSystemService.lunarMonthNames[monthIdx]
        : '';
      const dayText = dayNum >= 1 && dayNum < NativeSystemService.lunarDayNames.length
        ? NativeSystemService.lunarDayNames[dayNum]
        : '';
      if (monthText.length > 0 && dayText.length > 0) {
        return `农历${monthText}${dayText}`;
      }
    } catch (_err) {
      // Ignore unsupported calendar lookup
    }
    return '';
  }
}
