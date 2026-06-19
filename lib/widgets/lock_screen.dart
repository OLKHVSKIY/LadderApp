import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';

/// Экран блокировки приложения. Полностью перекрывает контент: пока он
/// показан, ничего «под ним» увидеть нельзя.
///
/// [authInProgress] — идёт ли сейчас системный запрос биометрии (тогда
/// прячем кнопку «Повторить», чтобы не плодить параллельные запросы).
/// [onUnlock] — повторная попытка аутентификации.
class LockScreen extends StatelessWidget {
  final bool authInProgress;
  final VoidCallback onUnlock;

  const LockScreen({
    super.key,
    required this.authInProgress,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surface,
                  border: Border.all(color: colors.border, width: 1),
                ),
                child: Icon(
                  CupertinoIcons.lock_fill,
                  size: 42,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                tr('Приложение заблокировано'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr('Подтвердите, что это вы, чтобы продолжить'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: authInProgress ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: authInProgress,
                    child: CupertinoButton(
                      color: colors.inverseSurface,
                      borderRadius: BorderRadius.circular(16),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      onPressed: onUnlock,
                      child: Text(
                        tr('Разблокировать'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: colors.onInverseSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
