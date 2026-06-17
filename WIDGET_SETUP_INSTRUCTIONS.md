# Инструкция по настройке виджетов для iOS

## Шаг 1: Настройка App Group

1. Откройте проект в Xcode: `ios/Runner.xcworkspace`
2. Выберите target "Runner" в навигаторе проекта
3. Перейдите на вкладку "Signing & Capabilities"
4. Нажмите "+ Capability" и добавьте "App Groups"
5. Создайте новую группу: `group.com.hackflow.ladder` (или используйте существующую)
6. Убедитесь, что группа включена для Runner

## Шаг 2: Создание Widget Extensions

### Для первого виджета (TodayTasksWidget):

1. В Xcode: File → New → Target
2. Выберите "Widget Extension"
3. Название: `TodayTasksWidget`
4. Language: Swift
5. Включите "Include Configuration Intent" (можно отключить, если не нужна настройка)
6. Нажмите "Finish"

7. Замените содержимое `TodayTasksWidget.swift` на код из `ios/Widgets/TodayTasksWidget/TodayTasksWidget.swift`

8. В настройках target "TodayTasksWidget":
   - Signing & Capabilities → добавьте ту же App Group: `group.com.hackflow.ladder`
   - Deployment Target: iOS 14.0 или выше

### Для второго виджета (AddTaskWidget):

1. В Xcode: File → New → Target
2. Выберите "Widget Extension"
3. Название: `AddTaskWidget`
4. Language: Swift
5. Снимите галочки "Include Live Activity", "Include Control", "Include Configuration App Intent"
6. Нажмите "Finish"

7. Замените содержимое `AddTaskWidget.swift` на код из `ios/AddTaskWidget/AddTaskWidget.swift`

8. В настройках target "AddTaskWidget":
   - Signing & Capabilities → добавьте ту же App Group: `group.com.hackflow.ladder`
   - Deployment Target: iOS 14.0 или выше

9. Замените содержимое `AddTaskWidgetBundle.swift` на код из `ios/AddTaskWidget/AddTaskWidgetBundle.swift`

## Шаг 3: Настройка Widget Bundle

После создания обоих виджетов:

1. Откройте `TodayTasksWidgetBundle.swift` в папке `TodayTasksWidget`
2. Замените его содержимое на код из `ios/TodayTasksWidget/TodayTasksWidgetBundle.swift` (уже обновлен)
3. После создания второго виджета, обновите Bundle, чтобы включить оба виджета (или используйте отдельные Bundle файлы для каждого виджета)

## Шаг 4: Настройка URL Scheme

URL Scheme уже добавлен в `ios/Runner/Info.plist`. Если нужно добавить вручную:

1. В target "Runner" → Info → URL Types
2. Добавьте новый URL Type:
   - Identifier: `com.hackflow.ladder`
   - URL Schemes: `ladder`

Или откройте `ios/Runner/Info.plist` и убедитесь, что там есть секция `CFBundleURLTypes` с `ladder` схемой.

## Шаг 5: Добавление WidgetDataSync.swift

1. Добавьте файл `ios/Runner/WidgetDataSync.swift` в проект Runner
2. Убедитесь, что он добавлен в target "Runner"

## Шаг 6: Обновление AppDelegate

Код уже обновлен в `ios/Runner/AppDelegate.swift` для обработки deep links.

## Шаг 7: Тестирование

1. Запустите приложение на симуляторе или устройстве
2. Долгим нажатием на главном экране войдите в режим редактирования
3. Нажмите "+" в левом верхнем углу
4. Найдите ваше приложение в списке виджетов
5. Добавьте виджеты на экран

## Примечания

- Виджеты обновляются автоматически каждые 15 минут (для первого виджета)
- Данные синхронизируются при загрузке задач на странице Tasks
- При нажатии на второй виджет открывается приложение и шторка создания задачи
