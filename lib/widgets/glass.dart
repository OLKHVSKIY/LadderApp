import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../theme/app_colors.dart';

/// Общие настройки Liquid Glass в стиле Apple (iOS 26).
///
/// Используются всеми glass-компонентами приложения, чтобы
/// внешний вид оставался единым.
abstract final class AppGlass {
  /// Настройки для крупных панелей (нижняя навигация, меню).
  ///
  /// Меньше белой заливки и больше преломления/бликов, чтобы
  /// эффект стекла читался даже на белом фоне.
  static const LiquidGlassSettings panel = LiquidGlassSettings(
    // Холодный серый тон вместо чисто белого — панель читается на белом фоне.
    glassColor: Color.fromARGB(64, 196, 202, 212),
    thickness: 28,
    blur: 10,
    chromaticAberration: 0.03,
    lightIntensity: 1.1,
    refractiveIndex: 1.3,
    saturation: 1.6,
  );

  /// Настройки для всплывающих меню (контекстное меню задач/списков).
  ///
  /// Светлее и тоньше панели: почти белый прозрачный тон, меньше преломления,
  /// чтобы меню не выглядело тёмным и тяжёлым на белом фоне.
  static const LiquidGlassSettings menu = LiquidGlassSettings(
    glassColor: Color.fromARGB(56, 230, 232, 236),
    thickness: 14,
    blur: 8,
    chromaticAberration: 0.02,
    lightIntensity: 0.9,
    refractiveIndex: 1.2,
    saturation: 1.3,
  );

  /// Настройки для маленьких элементов (кнопки, крестики).
  static const LiquidGlassSettings control = LiquidGlassSettings(
    glassColor: Color.fromARGB(60, 255, 255, 255),
    thickness: 12,
    blur: 6,
    chromaticAberration: 0.02,
    lightIntensity: 0.8,
    refractiveIndex: 1.2,
    saturation: 1.4,
  );
}

/// Панель в стиле Apple Liquid Glass (squircle-форма, как у iOS 26).
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final LiquidGlassSettings settings;

  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 28,
    this.settings = AppGlass.panel,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlass.withOwnLayer(
      settings: settings,
      shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
      glassContainsChild: false,
      child: child,
    );
  }
}

/// Круглая кнопка в стиле Liquid Glass — для крестиков закрытия,
/// иконок и прочих элементов управления.
///
/// Минимальная область касания соответствует Apple HIG (44x44pt).
class GlassCircleButton extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final double size;
  final double iconSize;

  /// Цвет иконки. Если не задан — берётся по теме: тёмный значок на светлой
  /// теме и белый на тёмной (иначе крестик сливался бы с тёмным фоном).
  final Color? iconColor;

  const GlassCircleButton({
    super.key,
    required this.onTap,
    this.icon = CupertinoIcons.xmark,
    this.size = 30,
    this.iconSize = 15,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedIconColor = iconColor ??
        (AppColors.of(context).isDark
            ? CupertinoColors.white
            : const Color(0xFF3A3A3C));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // Расширяем зону касания до минимума по Apple HIG.
      child: SizedBox(
        width: size < 44 ? 44 : size,
        height: size < 44 ? 44 : size,
        child: Center(
          child: LiquidGlass.withOwnLayer(
            settings: AppGlass.control,
            shape: const LiquidOval(),
            glassContainsChild: false,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: iconSize, color: resolvedIconColor),
            ),
          ),
        ),
      ),
    );
  }
}
