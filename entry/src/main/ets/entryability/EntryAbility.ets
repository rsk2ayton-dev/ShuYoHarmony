import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { NativeSystemService } from '../services/NativeSystemService';
import { PreferencesService } from '../services/PreferencesService';
import { RawFileService } from '../services/RawFileService';
import { ShuYoAppStore } from '../store/ShuYoAppStore';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    PreferencesService.init(this.context);
    RawFileService.init(this.context);
    NativeSystemService.init(this.context);
    if (want.parameters !== undefined && want.parameters['targetTab'] === 'schedule') {
      NativeSystemService.setPendingLaunchTab('schedule');
    }
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'ShuYo', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'ShuYo', '%{public}s', 'Ability onCreate');
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    if (want.parameters !== undefined && want.parameters['targetTab'] === 'schedule') {
      NativeSystemService.setPendingLaunchTab('schedule');
      ShuYoAppStore.instance().switchToScheduleTab();
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'ShuYo', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'ShuYo', 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'ShuYo', 'Succeeded in loading ShuYo content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'ShuYo', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'ShuYo', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'ShuYo', '%{public}s', 'Ability onBackground');
  }
}
