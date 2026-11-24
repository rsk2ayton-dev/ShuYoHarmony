import { curves, uiMaterial } from '@kit.ArkUI';
import { ShuYoColorPalette } from './ShuYoTheme';

/**
 * Shared HarmonyOS flagship spring curves, tactile click feedback,
 * and container enter/sheet transitions for ShuYoHarmony.
 */
export class ShuYoMotion {
  static readonly springCurve: ICurve = curves.springCurve(0, 1, 228, 28);
  static readonly snappySpring: ICurve = curves.springCurve(0, 1, 320, 32);
  static readonly gentleSpring: ICurve = curves.springCurve(0, 1, 180, 26);

  static readonly lightClick: ClickEffect = {
    level: ClickEffectLevel.LIGHT,
    scale: 0.96
  };

  static readonly snappyClick: ClickEffect = {
    level: ClickEffectLevel.LIGHT,
    scale: 0.92
  };

  static cardEnterTransition(delayMs: number = 0): TransitionEffect {
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 12 }))
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: 320,
        delay: delayMs,
        curve: ShuYoMotion.springCurve
      });
  }

  static sheetCardTransition(): TransitionEffect {
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.move(TransitionEdge.BOTTOM))
      .animation({
        duration: 280,
        curve: ShuYoMotion.springCurve
      });
  }
}

/**
 * Cached HarmonyOS ImmersiveMaterial singletons (API 26) and translucent
 * liquid/frosted glass tokens so RenderService reuses caches cleanly.
 */
export class ShuYoGlass {
  private static dockLight: uiMaterial.Material | undefined = undefined;
  private static dockDark: uiMaterial.Material | undefined = undefined;
  private static buttonLight: uiMaterial.Material | undefined = undefined;
  private static buttonDark: uiMaterial.Material | undefined = undefined;
  private static cardLight: uiMaterial.Material | undefined = undefined;
  private static cardDark: uiMaterial.Material | undefined = undefined;
  private static sheetUltraThick: uiMaterial.Material | undefined = undefined;
  private static toastThin: uiMaterial.Material | undefined = undefined;

  static floatingDockMaterial(isDark: boolean): uiMaterial.Material {
    if (isDark) {
      if (ShuYoGlass.dockDark === undefined) {
        ShuYoGlass.dockDark = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          materialColor: '#55141A22',
          applyShadow: true,
          interactive: false,
          lightEffect: { color: undefined }
        });
      }
      return ShuYoGlass.dockDark;
    }
    if (ShuYoGlass.dockLight === undefined) {
      ShuYoGlass.dockLight = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THIN,
        materialColor: '#78FFFFFF',
        applyShadow: true,
        interactive: false,
        lightEffect: { color: undefined }
      });
    }
    return ShuYoGlass.dockLight;
  }

  static interactiveButtonMaterial(isDark: boolean): uiMaterial.Material {
    if (isDark) {
      if (ShuYoGlass.buttonDark === undefined) {
        ShuYoGlass.buttonDark = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: '#441B232E',
          applyShadow: true,
          interactive: true,
          lightEffect: { color: undefined }
        });
      }
      return ShuYoGlass.buttonDark;
    }
    if (ShuYoGlass.buttonLight === undefined) {
      ShuYoGlass.buttonLight = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        materialColor: '#66FFFFFF',
        applyShadow: true,
        interactive: true,
        lightEffect: { color: undefined }
      });
    }
    return ShuYoGlass.buttonLight;
  }

  static floatingCardMaterial(isDark: boolean): uiMaterial.Material {
    if (isDark) {
      if (ShuYoGlass.cardDark === undefined) {
        ShuYoGlass.cardDark = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR,
          materialColor: '#70151B22',
          applyShadow: true,
          interactive: false,
          lightEffect: { color: undefined }
        });
      }
      return ShuYoGlass.cardDark;
    }
    if (ShuYoGlass.cardLight === undefined) {
      ShuYoGlass.cardLight = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        materialColor: '#90FFFFFF',
        applyShadow: true,
        interactive: false,
        lightEffect: { color: undefined }
      });
    }
    return ShuYoGlass.cardLight;
  }

  static sheetMaterial(): uiMaterial.Material {
    if (ShuYoGlass.sheetUltraThick === undefined) {
      ShuYoGlass.sheetUltraThick = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THICK
      });
    }
    return ShuYoGlass.sheetUltraThick;
  }

  static toastMaterial(): uiMaterial.Material {
    if (ShuYoGlass.toastThin === undefined) {
      ShuYoGlass.toastThin = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THIN
      });
    }
    return ShuYoGlass.toastThin;
  }

  static blurColorMode(isDark: boolean): ThemeColorMode {
    return isDark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT;
  }

  static ambientGradientColors(colors: ShuYoColorPalette): [ResourceColor, number][] {
    if (colors.isDark) {
      return [
        ['#0F1824', 0.0],
        [colors.background, 0.42],
        ['#0E151D', 1.0]
      ];
    }
    return [
      ['#EEF5FF', 0.0],
      [colors.background, 0.38],
      ['#F2F7FB', 1.0]
    ];
  }

  static cardSurfaceBg(colors: ShuYoColorPalette): string {
    return colors.isDark ? '#CC171C22' : '#E6FFFFFF';
  }

  static cardGlassBorder(colors: ShuYoColorPalette): string {
    return colors.isDark ? '#2EFFFFFF' : '#B8FFFFFF';
  }

  static floatingDockBlur(isDark: boolean): BackgroundEffectOptions {
    return {
      radius: 28,
      saturation: isDark ? 1.45 : 1.65,
      brightness: isDark ? 0.92 : 1.06,
      color: isDark ? '#B8151B24' : '#B8FFFFFF'
    };
  }

  static floatingCardBlur(isDark: boolean): BackgroundEffectOptions {
    return {
      radius: 22,
      saturation: isDark ? 1.35 : 1.5,
      brightness: isDark ? 0.94 : 1.04,
      color: isDark ? '#C8161C24' : '#D2FFFFFF'
    };
  }
}
