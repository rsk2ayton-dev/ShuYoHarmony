import { http } from '@kit.NetworkKit';
import { ShuYoConstants } from '../core/ShuYoConstants';
import {
  ShuYoCampusCardBill,
  ShuYoCampusCardInfo,
  ShuYoDailySpending
} from '../models/ShuYoModels';
import { HttpClientService } from './HttpClientService';
import { JsonHelpers } from './JsonHelpers';

interface ShuYoDemoTxItem {
  daysAgo: number;
  hour: number;
  minute: number;
  name: string;
  amount: number;
}

export class CampusCardService {
  private static readonly demoTx: ShuYoDemoTxItem[] = [
    { daysAgo: 0, hour: 12, minute: 15, name: '宝山校区第一食堂', amount: 13.50 },
    { daysAgo: 1, hour: 18, minute: 12, name: '宝山校区第一食堂', amount: 14.00 },
    { daysAgo: 1, hour: 12, minute: 6, name: '宝山校区第二食堂', amount: 11.80 },
    { daysAgo: 2, hour: 8, minute: 45, name: '校园卡充值', amount: -50.00 },
    { daysAgo: 3, hour: 12, minute: 25, name: '宝山校区第一食堂', amount: 14.20 },
    { daysAgo: 4, hour: 16, minute: 33, name: '校园超市', amount: 5.50 },
    { daysAgo: 5, hour: 18, minute: 7, name: '宝山校区第三食堂', amount: 16.50 },
    { daysAgo: 6, hour: 12, minute: 11, name: '宝山校区第二食堂', amount: 12.80 },
    { daysAgo: 9, hour: 13, minute: 1, name: '自助打印', amount: 3.00 },
    { daysAgo: 12, hour: 12, minute: 17, name: '宝山校区第一食堂', amount: 12.50 },
    { daysAgo: 17, hour: 18, minute: 22, name: '宝山校区第三食堂', amount: 15.90 },
    { daysAgo: 21, hour: 10, minute: 16, name: '校园卡充值', amount: -40.00 },
    { daysAgo: 25, hour: 12, minute: 8, name: '宝山校区第二食堂', amount: 10.80 }
  ];

  static loadDemoCardInfo(): ShuYoCampusCardInfo {
    return {
      studentId: 'DEMO0001',
      holderName: '演示用户',
      cardStatus: '正常',
      balance: 87.60
    };
  }

  static loadDemoBills(): ShuYoCampusCardBill[] {
    const now = new Date();
    const baseMs = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const dayMs = 86400000;
    const out: ShuYoCampusCardBill[] = [];
    for (let i = 0; i < CampusCardService.demoTx.length; i++) {
      const tx = CampusCardService.demoTx[i];
      now.setTime(baseMs - tx.daysAgo * dayMs + (tx.hour * 60 + tx.minute) * 60000);
      const y = now.getFullYear();
      const m = CampusCardService.pad2(now.getMonth() + 1);
      const d = CampusCardService.pad2(now.getDate());
      const hh = CampusCardService.pad2(now.getHours());
      const mm = CampusCardService.pad2(now.getMinutes());
      out.push({
        id: `demo-bill-${i}`,
        merchantName: tx.name,
        payTime: `${y}-${m}-${d} ${hh}:${mm}:00`,
        amount: tx.amount
      });
    }
    return out;
  }

  static summarizeDailySpending(bills: ShuYoCampusCardBill[]): ShuYoDailySpending[] {
    const dayMap = new Map<string, number>();
    for (let i = 0; i < bills.length; i++) {
      const b = bills[i];
      if (b.amount <= 0) {
        continue;
      }
      const dateStr = b.payTime.length >= 10 ? b.payTime.substring(5, 10) : b.payTime;
      const prev = dayMap.get(dateStr) ?? 0;
      dayMap.set(dateStr, prev + b.amount);
    }
    const keys = Array.from(dayMap.keys());
    keys.sort();
    const recentKeys = keys.length > 7 ? keys.slice(keys.length - 7) : keys;
    const out: ShuYoDailySpending[] = [];
    for (let i = 0; i < recentKeys.length; i++) {
      const k = recentKeys[i];
      const val = dayMap.get(k) ?? 0;
      out.push({ dateLabel: k, totalAmount: Number(val.toFixed(2)) });
    }
    return out;
  }

  static async fetchLiveCardInfo(accessToken: string): Promise<ShuYoCampusCardInfo> {
    const url = `${ShuYoConstants.eportalBaseUrl}/api/Identity/SchoolCard/GetCardPersonInfo?access_token=${encodeURIComponent(accessToken)}`;
    const resp = await HttpClientService.request(http.RequestMethod.GET, url);
    const obj = JsonHelpers.parseObject(resp.body);
    if (obj === undefined) {
      throw new Error('校园卡接口返回异常');
    }
    return {
      studentId: JsonHelpers.str(obj, 'account', JsonHelpers.str(obj, 'studentId')),
      holderName: JsonHelpers.str(obj, 'name', '一卡通用户'),
      cardStatus: JsonHelpers.str(obj, 'status', '正常'),
      balance: JsonHelpers.num(obj, 'balance', 0)
    };
  }

  private static pad2(val: number): string {
    return val < 10 ? `0${val}` : `${val}`;
  }
}
