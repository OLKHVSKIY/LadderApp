import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';
import '../widgets/main_header.dart';

/// Страница «Политика конфиденциальности».
/// Описывает, какие данные приложение собирает и какие — нет.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MainHeader(
              title: tr('Конфиденциальность'),
              onSearchTap: null,
              onSettingsTap: null,
              hideSearchAndSettings: true,
              showBackButton: true,
              onBack: () => Navigator.of(context).pop(),
              onGreetingToggle: null,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _para(colors, tr('Мы уважаем вашу конфиденциальность. Все ваши задачи, привычки, события и заметки хранятся локально на вашем устройстве.')),
                    _heading(colors, tr('Что мы собираем')),
                    _para(colors, tr('Имя и адрес электронной почты, указанные при входе — для доступа к вашему аккаунту.')),
                    _para(colors, tr('Содержимое, которое вы создаёте (задачи, заметки, привычки, события), хранится на устройстве.')),
                    _heading(colors, tr('Что мы НЕ собираем')),
                    _para(colors, tr('Мы не отслеживаем ваше местоположение, не читаем содержимое ваших данных и не передаём их третьим лицам в рекламных целях.')),
                    _heading(colors, tr('Ваши права')),
                    _para(colors, tr('Вы можете в любой момент экспортировать копию своих данных или удалить аккаунт. Экспорт доступен в настройках.')),
                    _heading(colors, tr('Контакты')),
                    _para(colors, tr('По вопросам конфиденциальности свяжитесь с нами через раздел поддержки.')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(AppColors colors, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
      ),
    );
  }

  Widget _para(AppColors colors, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
