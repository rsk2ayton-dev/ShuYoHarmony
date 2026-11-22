export interface ShuYoColorPalette {
  isDark: boolean;
  background: string;
  surface: string;
  surfaceAlt: string;
  surfaceMuted: string;
  border: string;
  borderStrong: string;
  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
  textMuted: string;
  accent: string;
  accentAlt: string;
  accentSoft: string;
  largeAction: string;
  onLargeAction: string;
  onAccent: string;
  onAccentSoft: string;
  navSelected: string;
  navUnselected: string;
  selectedFill: string;
  onSelectedFill: string;
  chipFill: string;
  chipBorder: string;
  danger: string;
  onDanger: string;
  warning: string;
  success: string;
  disabledFill: string;
  scheduleEmptyCell: string;
  scheduleCourseFill: string;
  scheduleCourseText: string;
  scheduleCourseMetaText: string;
}

export interface ShuYoThemeSpec {
  id: string;
  name: string;
  colors: ShuYoColorPalette;
}

export class ShuYoThemes {
  static readonly defaultId: string = 'blue_light';
  static readonly systemDarkId: string = 'default_dark';

  static readonly schedulePalette: string[] = [
    '#5DBA82',
    '#6C96CA',
    '#D2A24B',
    '#D97B70',
    '#9B87C4',
    '#65AEA5',
    '#6EAFD8',
    '#E0A45F',
    '#D58FB0',
    '#7FBA78',
    '#B89ACF',
    '#5EA6C0',
    '#E08B62',
    '#8EA9D5',
    '#B0B85C',
    '#CA8C83'
  ];

  static readonly all: ShuYoThemeSpec[] = [
    {
      id: 'blue_light',
      name: '浅色',
      colors: {
        isDark: false,
        background: '#FAFAFA',
        surface: '#FFFFFF',
        surfaceAlt: '#F3F6FA',
        surfaceMuted: '#E8EDF3',
        border: '#E1E7EF',
        borderStrong: '#CBD5E1',
        textPrimary: '#17202A',
        textSecondary: '#435160',
        textTertiary: '#667587',
        textMuted: '#929EAC',
        accent: '#3478D4',
        accentAlt: '#5B6F95',
        accentSoft: '#E8F1FC',
        largeAction: '#2F70C7',
        onLargeAction: '#FFFFFF',
        onAccent: '#FFFFFF',
        onAccentSoft: '#174EA6',
        navSelected: '#111827',
        navUnselected: '#748196',
        selectedFill: '#1F2937',
        onSelectedFill: '#FFFFFF',
        chipFill: '#F1F5F9',
        chipBorder: '#DCE5EF',
        danger: '#C74339',
        onDanger: '#FFFFFF',
        warning: '#A86F20',
        success: '#2F855A',
        disabledFill: '#E4EAF1',
        scheduleEmptyCell: '#EBEBEB',
        scheduleCourseFill: '#FFFFFF',
        scheduleCourseText: '#202423',
        scheduleCourseMetaText: '#59625D'
      }
    },
    {
      id: 'default_dark',
      name: '深色',
      colors: {
        isDark: true,
        background: '#0D0D0D',
        surface: '#151719',
        surfaceAlt: '#1B2025',
        surfaceMuted: '#222A31',
        border: '#26313A',
        borderStrong: '#364651',
        textPrimary: '#F0F4F7',
        textSecondary: '#D0DAE2',
        textTertiary: '#9AA9B4',
        textMuted: '#75848E',
        accent: '#41AEF2',
        accentAlt: '#2994F2',
        accentSoft: '#102B3D',
        largeAction: '#0678BF',
        onLargeAction: '#FFFFFF',
        onAccent: '#FFFFFF',
        onAccentSoft: '#96D7FF',
        navSelected: '#F0F4F7',
        navUnselected: '#87949C',
        selectedFill: '#F0F4F7',
        onSelectedFill: '#0D0D0D',
        chipFill: '#151719',
        chipBorder: '#303B44',
        danger: '#E36C61',
        onDanger: '#FFFFFF',
        warning: '#D6A85A',
        success: '#78B76F',
        disabledFill: '#252B31',
        scheduleEmptyCell: '#333D45',
        scheduleCourseFill: '#F0F4F7',
        scheduleCourseText: '#17202A',
        scheduleCourseMetaText: '#435360'
      }
    },
    {
      id: 'paper_light',
      name: '纸白',
      colors: {
        isDark: false,
        background: '#F7F7F4',
        surface: '#FFFFFF',
        surfaceAlt: '#F0F1EE',
        surfaceMuted: '#E8EAE6',
        border: '#E1E2DE',
        borderStrong: '#D1D4CF',
        textPrimary: '#191B1B',
        textSecondary: '#3E4542',
        textTertiary: '#69736E',
        textMuted: '#929A95',
        accent: '#237A57',
        accentAlt: '#496F9F',
        accentSoft: '#DDEDE5',
        largeAction: '#237A57',
        onLargeAction: '#FFFFFF',
        onAccent: '#FFFFFF',
        onAccentSoft: '#14543B',
        navSelected: '#111313',
        navUnselected: '#77817B',
        selectedFill: '#202624',
        onSelectedFill: '#FFFFFF',
        chipFill: '#F1F2EF',
        chipBorder: '#DDE0DA',
        danger: '#C74339',
        onDanger: '#FFFFFF',
        warning: '#B27622',
        success: '#2C8A58',
        disabledFill: '#E2E4DF',
        scheduleEmptyCell: '#E6E8E3',
        scheduleCourseFill: '#FFFFFF',
        scheduleCourseText: '#202423',
        scheduleCourseMetaText: '#59625D'
      }
    },
    {
      id: 'ink_teal',
      name: '墨青',
      colors: {
        isDark: true,
        background: '#071210',
        surface: '#101C19',
        surfaceAlt: '#14231F',
        surfaceMuted: '#1B2C27',
        border: '#223730',
        borderStrong: '#345046',
        textPrimary: '#EAF2EE',
        textSecondary: '#C6D5CE',
        textTertiary: '#91A39B',
        textMuted: '#6E8178',
        accent: '#58C7B4',
        accentAlt: '#D9A955',
        accentSoft: '#173D37',
        largeAction: '#58C7B4',
        onLargeAction: '#031714',
        onAccent: '#031714',
        onAccentSoft: '#85DFD0',
        navSelected: '#EAF2EE',
        navUnselected: '#7F938A',
        selectedFill: '#EAF2EE',
        onSelectedFill: '#071210',
        chipFill: '#101C19',
        chipBorder: '#345046',
        danger: '#E36C61',
        onDanger: '#FFFFFF',
        warning: '#D9A955',
        success: '#76D199',
        disabledFill: '#22302C',
        scheduleEmptyCell: '#2B4039',
        scheduleCourseFill: '#EAF2EE',
        scheduleCourseText: '#14231F',
        scheduleCourseMetaText: '#3B524A'
      }
    },
    {
      id: 'graphite_coral',
      name: '石墨珊瑚',
      colors: {
        isDark: true,
        background: '#101010',
        surface: '#181818',
        surfaceAlt: '#202020',
        surfaceMuted: '#292929',
        border: '#2E2E2E',
        borderStrong: '#414141',
        textPrimary: '#F0EFED',
        textSecondary: '#D2D0CD',
        textTertiary: '#A19D98',
        textMuted: '#7F7A75',
        accent: '#E2624B',
        accentAlt: '#78B7A6',
        accentSoft: '#3B201B',
        largeAction: '#E2624B',
        onLargeAction: '#FFFFFF',
        onAccent: '#FFFFFF',
        onAccentSoft: '#FFA190',
        navSelected: '#F0EFED',
        navUnselected: '#8E8984',
        selectedFill: '#F0EFED',
        onSelectedFill: '#101010',
        chipFill: '#181818',
        chipBorder: '#414141',
        danger: '#E2624B',
        onDanger: '#FFFFFF',
        warning: '#D7A04B',
        success: '#78B76F',
        disabledFill: '#2D2D2D',
        scheduleEmptyCell: '#4A4743',
        scheduleCourseFill: '#F4F0EC',
        scheduleCourseText: '#24201D',
        scheduleCourseMetaText: '#5B524B'
      }
    },
    {
      id: 'morning_coral',
      name: '晨白珊瑚',
      colors: {
        isDark: false,
        background: '#FCF8F5',
        surface: '#FFFFFF',
        surfaceAlt: '#F4EFEB',
        surfaceMuted: '#EDE5DF',
        border: '#E4DAD3',
        borderStrong: '#D2C4BA',
        textPrimary: '#24201F',
        textSecondary: '#514A45',
        textTertiary: '#7B7068',
        textMuted: '#9B9189',
        accent: '#D85D49',
        accentAlt: '#438C7C',
        accentSoft: '#F8DED8',
        largeAction: '#D85D49',
        onLargeAction: '#FFFFFF',
        onAccent: '#FFFFFF',
        onAccentSoft: '#8F3225',
        navSelected: '#24201F',
        navUnselected: '#877D75',
        selectedFill: '#2A2523',
        onSelectedFill: '#FFFFFF',
        chipFill: '#F4EFEB',
        chipBorder: '#E2D7CE',
        danger: '#C74339',
        onDanger: '#FFFFFF',
        warning: '#AD7627',
        success: '#438C58',
        disabledFill: '#E8DFD8',
        scheduleEmptyCell: '#ECE2DA',
        scheduleCourseFill: '#FFFFFF',
        scheduleCourseText: '#24201F',
        scheduleCourseMetaText: '#665D56'
      }
    },
    {
      id: 'material3_light',
      name: 'Material 3 浅色',
      colors: {
        isDark: false,
        background: '#FEF7FF',
        surface: '#FFFFFF',
        surfaceAlt: '#F3EDF7',
        surfaceMuted: '#E6E0E9',
        border: '#CAC4D0',
        borderStrong: '#79747E',
        textPrimary: '#1D1B20',
        textSecondary: '#49454F',
        textTertiary: '#625B71',
        textMuted: '#79747E',
        accent: '#6750A4',
        accentAlt: '#625B71',
        accentSoft: '#EADDFF',
        largeAction: '#6750A4',
        onLargeAction: '#FFFFFF',
        onAccent: '#FFFFFF',
        onAccentSoft: '#21005D',
        navSelected: '#1D1B20',
        navUnselected: '#49454F',
        selectedFill: '#E8DEF8',
        onSelectedFill: '#1D192B',
        chipFill: '#F3EDF7',
        chipBorder: '#CAC4D0',
        danger: '#B3261E',
        onDanger: '#FFFFFF',
        warning: '#7D5260',
        success: '#2E7D32',
        disabledFill: '#E6E0E9',
        scheduleEmptyCell: '#EDE7F6',
        scheduleCourseFill: '#FFFFFF',
        scheduleCourseText: '#1D1B20',
        scheduleCourseMetaText: '#49454F'
      }
    },
    {
      id: 'material3_dark',
      name: 'Material 3 深色',
      colors: {
        isDark: true,
        background: '#141218',
        surface: '#1D1B20',
        surfaceAlt: '#211F26',
        surfaceMuted: '#2B2930',
        border: '#49454F',
        borderStrong: '#938F99',
        textPrimary: '#E6E0E9',
        textSecondary: '#CAC4D0',
        textTertiary: '#938F99',
        textMuted: '#79747E',
        accent: '#D0BCFF',
        accentAlt: '#CCC2DC',
        accentSoft: '#4F378B',
        largeAction: '#D0BCFF',
        onLargeAction: '#381E72',
        onAccent: '#381E72',
        onAccentSoft: '#EADDFF',
        navSelected: '#E6E0E9',
        navUnselected: '#CAC4D0',
        selectedFill: '#4A4458',
        onSelectedFill: '#E8DEF8',
        chipFill: '#211F26',
        chipBorder: '#49454F',
        danger: '#F2B8B5',
        onDanger: '#601410',
        warning: '#EFB8C8',
        success: '#81C784',
        disabledFill: '#2B2930',
        scheduleEmptyCell: '#2B2930',
        scheduleCourseFill: '#211F26',
        scheduleCourseText: '#E6E0E9',
        scheduleCourseMetaText: '#CAC4D0'
      }
    }
  ];

  static byId(id: string): ShuYoThemeSpec {
    for (let i = 0; i < ShuYoThemes.all.length; i++) {
      if (ShuYoThemes.all[i].id === id) {
        return ShuYoThemes.all[i];
      }
    }
    return ShuYoThemes.all[0];
  }

  static courseColorFor(courseKey: string): string {
    let hash = 0;
    for (let i = 0; i < courseKey.length; i++) {
      hash = (hash * 31 + courseKey.charCodeAt(i)) & 0x7fffffff;
    }
    return ShuYoThemes.schedulePalette[hash % ShuYoThemes.schedulePalette.length];
  }
}
