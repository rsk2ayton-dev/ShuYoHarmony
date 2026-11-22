import {
  ShuYoLibraryArea,
  ShuYoLibraryBookingRecord,
  ShuYoLibrarySeat,
  ShuYoLibraryVenue
} from '../models/ShuYoModels';
import { RawFileService } from './RawFileService';

export class LibraryBookingService {
  static readonly venues: ShuYoLibraryVenue[] = [
    { id: 'library', name: '宝山校本部图书馆', campusName: '宝山校区', areaNames: ['二楼东侧', '二楼西侧', '三楼阅览室'] },
    { id: 'studySpace', name: '宝山研习空间', campusName: '宝山校区', areaNames: ['A区', 'B区'] },
    { id: 'qianweichang', name: '钱伟长图书馆', campusName: '宝山校区', areaNames: ['四楼外圈', '四楼内圈'] },
    { id: 'scienceArt', name: '科艺中心共享空间', campusName: '宝山校区', areaNames: ['创作中心A', '创作中心B'] },
    { id: 'yanchang', name: '延长校区图书馆', campusName: '延长校区', areaNames: ['B区', 'C区'] },
    { id: 'jiading', name: '嘉定校区图书馆', campusName: '嘉定校区', areaNames: ['一楼自修室', '二楼自修区'] }
  ];

  static getRulesMarkdown(): string {
    return RawFileService.readText('library_booking/rules.md');
  }

  static getQaMarkdown(): string {
    return RawFileService.readText('library_booking/QA.md');
  }

  static buildAreasForVenue(venue: ShuYoLibraryVenue, bookings: ShuYoLibraryBookingRecord[]): ShuYoLibraryArea[] {
    const areas: ShuYoLibraryArea[] = [];
    for (let i = 0; i < venue.areaNames.length; i++) {
      const areaId = `${venue.id}-${i}`;
      const seats: ShuYoLibrarySeat[] = [];
      let freeCount = 0;
      for (let s = 1; s <= 15; s++) {
        const seatId = `${areaId}-${s}`;
        const label = s < 10 ? `0${s}` : `${s}`;
        const isBusy = s === 3 || s === 8;
        const isDisabled = s === 5;
        let isBooked = false;
        for (let b = 0; b < bookings.length; b++) {
          if (bookings[b].seatId === seatId && bookings[b].status === 'BOOKING') {
            isBooked = true;
            break;
          }
        }
        if (!isBusy && !isDisabled && !isBooked) {
          freeCount++;
        }
        seats.push({
          id: seatId,
          seatLabel: label,
          areaId: areaId,
          isBusy: isBusy,
          isDisabled: isDisabled,
          isBooked: isBooked
        });
      }
      areas.push({
        id: areaId,
        name: venue.areaNames[i],
        totalCount: seats.length,
        freeCount: freeCount,
        seats: seats
      });
    }
    return areas;
  }

  static todayDateStr(): string {
    const d = new Date();
    const y = d.getFullYear();
    const m = d.getMonth() + 1;
    const day = d.getDate();
    return `${y}-${m < 10 ? '0' + m : m}-${day < 10 ? '0' + day : day}`;
  }
}
