import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';
import '../widgets/main_header.dart';

/// Страница «Уведомления». Две секции — «Требуют действия» и «Информационные».
/// Пока пустые — здесь будут уведомления приложения.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  // 0 = Требуют действия, 1 = Информационные
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      resizeToAvoidBottomInset: false,
      body: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top - 10,
        ),
        child: Column(
          children: [
            // Хедер: только стрелка «назад» слева, без заголовка.
            MainHeader(
              title: tr('Уведомления'),
              onSearchTap: null,
              onSettingsTap: null,
              hideSearchAndSettings: true,
              showBackButton: true,
              onBack: () => Navigator.of(context).pop(),
              onGreetingToggle: null,
            ),
            // Переключатель секций (как в шторке создания задачи).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: AdaptiveSegmentedControl(
                  labels: [tr('Требуют действия'), tr('Информационные')],
                  selectedIndex: _selectedIndex,
                  onValueChanged: (i) {
                    if (i != _selectedIndex) {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedIndex = i);
                    }
                  },
                ),
              ),
            ),
            Expanded(
              child: _buildEmptyState(colors),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.bell,
            size: 56,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            tr('Нет уведомлений'),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr('Здесь будут ваши уведомления'),
            style: TextStyle(
              fontSize: 14,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
