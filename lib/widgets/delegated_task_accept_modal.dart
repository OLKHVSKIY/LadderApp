import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/repositories/delegated_task_repository.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';

class DelegatedTaskAcceptModal extends StatefulWidget {
  final List<DelegatedTaskInfo> tasks;
  final Function(int taskId) onAccept;
  final Function(int taskId) onDecline;
  final VoidCallback onClose;

  const DelegatedTaskAcceptModal({
    super.key,
    required this.tasks,
    required this.onAccept,
    required this.onDecline,
    required this.onClose,
  });

  @override
  State<DelegatedTaskAcceptModal> createState() => _DelegatedTaskAcceptModalState();
}

class _DelegatedTaskAcceptModalState extends State<DelegatedTaskAcceptModal> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _getSenderName(DelegatedTaskInfo taskInfo) {
    return taskInfo.fromUserName ?? taskInfo.fromUserEmail;
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.4,
          maxChildSize: 0.7,
          builder: (context, scrollController) {
                  final colors = AppColors.of(context);
                  return Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: Column(
                      children: [
                        // Ручка для перетаскивания
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          width: 45,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.divider,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        // Заголовок
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.tasks.length == 1
                                  ? tr('С вами поделились задачей!')
                                  : tr('С вами поделились задачами!'),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                              if (widget.tasks.length > 1)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    tr('{0} задач', [widget.tasks.length]),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colors.textTertiary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Контент задач
                        Expanded(
                          child: SingleChildScrollView(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ...widget.tasks.map((taskInfo) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 24),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Имя отправителя
                                        Padding(
                                          padding: const EdgeInsets.only(left: 4, bottom: 8),
                                          child: Text(
                                            _getSenderName(taskInfo),
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: colors.textPrimary,
                                            ),
                                          ),
                                        ),
                                        // Блок задачи
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: colors.surfaceVariant,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                taskInfo.taskTitle,
                                                textAlign: TextAlign.left,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: colors.textPrimary,
                                                ),
                                              ),
                                              if (taskInfo.taskDescription != null && taskInfo.taskDescription!.isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                Text(
                                                  taskInfo.taskDescription!,
                                                  textAlign: TextAlign.left,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: colors.textSecondary,
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 8),
                                              Text(
                                                tr('Дата: {0}', ['${taskInfo.taskDate.day.toString().padLeft(2, '0')}.${taskInfo.taskDate.month.toString().padLeft(2, '0')}.${taskInfo.taskDate.year}']),
                                                textAlign: TextAlign.left,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: colors.textTertiary,
                                                ),
                                              ),
                                              if (taskInfo.taskTags.isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  spacing: 6,
                                                  alignment: WrapAlignment.start,
                                                  children: taskInfo.taskTags.map((tag) {
                                                    return Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: colors.surfaceVariant,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        tag,
                                                        textAlign: TextAlign.left,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: colors.textSecondary,
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        // Кнопки для задачи
                                        Padding(
                                          padding: const EdgeInsets.only(top: 12),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton(
                                                  onPressed: () {
                                                    HapticFeedback.mediumImpact();
                                                    widget.onDecline(taskInfo.id);
                                                  },
                                                  style: OutlinedButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    side: BorderSide(color: colors.border),
                                                  ),
                                                  child: Text(
                                                    tr('Отменить'),
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                      color: colors.textSecondary,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: ElevatedButton(
                                                  onPressed: () {
                                                    HapticFeedback.mediumImpact();
                                                    widget.onAccept(taskInfo.id);
                                                  },
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: colors.inverseSurface,
                                                    foregroundColor: colors.onInverseSurface,
                                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    tr('Принять'),
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
  }
}
