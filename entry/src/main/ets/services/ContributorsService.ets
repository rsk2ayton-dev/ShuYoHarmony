import { ShuYoContributor } from '../models/ShuYoModels';
import { JsonHelpers } from './JsonHelpers';
import { RawFileService } from './RawFileService';

export class ContributorsService {
  static loadContributors(): ShuYoContributor[] {
    const raw = RawFileService.readText('contributors/contributors.json');
    const obj = JsonHelpers.parseObject(raw);
    const list = JsonHelpers.asArray(obj !== undefined ? obj['contributors'] : undefined);
    const out: ShuYoContributor[] = [];
    for (let i = 0; i < list.length; i++) {
      const c = JsonHelpers.asObject(list[i]);
      if (c === undefined) {
        continue;
      }
      const login = JsonHelpers.str(c, 'login');
      const name = JsonHelpers.str(c, 'name');
      out.push({
        login: login,
        displayName: name.length > 0 ? name : login,
        avatarUrl: JsonHelpers.str(c, 'avatarUrl'),
        profileUrl: JsonHelpers.str(c, 'profileUrl'),
        commits: JsonHelpers.num(c, 'commits', 0),
        additions: JsonHelpers.num(c, 'additions', 0),
        deletions: JsonHelpers.num(c, 'deletions', 0)
      });
    }
    return out;
  }
}
