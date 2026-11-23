import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferencesService } from '../services/PreferencesService';
import { ScheduleWidgetService } from '../services/ScheduleWidgetService';

const TAG: string = 'EntryFormAbility';
const DOMAIN: number = 0xFF00;

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(_want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onAddForm schedule_widget');
    PreferencesService.init(this.context);
    return ScheduleWidgetService.buildFormBindingDataFromPrefs();
  }

  onUpdateForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onUpdateForm formId=%{public}s', formId);
    PreferencesService.init(this.context);
    const data = ScheduleWidgetService.buildFormBindingDataFromPrefs();
    formProvider.updateForm(formId, data).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'updateForm failed: %{public}d %{public}s', err.code, err.message);
    });
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, 'onFormEvent formId=%{public}s message=%{public}s', formId, message);
    this.onUpdateForm(formId);
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm formId=%{public}s', formId);
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
