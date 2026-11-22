import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

export class RawFileService {
  private static appContext: common.Context | undefined = undefined;

  static init(context: common.Context): void {
    RawFileService.appContext = context;
  }

  static readText(relativePath: string): string {
    if (RawFileService.appContext === undefined) {
      return '';
    }
    try {
      const bytes = RawFileService.appContext.resourceManager.getRawFileContentSync(relativePath);
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(bytes);
    } catch (_err) {
      return '';
    }
  }
}
