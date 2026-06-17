# Исправление ошибки WidgetDataSyncPlugin

## Проблема
Ошибка компиляции: `Cannot find 'WidgetDataSyncPlugin' in scope`

## Решение

### Шаг 1: Добавить файл в Xcode проект

1. Откройте `ios/Runner.xcworkspace` в Xcode
2. В Project Navigator (слева) найдите папку `Runner`
3. Найдите файл `WidgetDataSync.swift` в папке `Runner`
4. Если файл не виден в Project Navigator:
   - Правой кнопкой на папку `Runner` → "Add Files to Runner..."
   - Выберите файл `ios/Runner/WidgetDataSync.swift`
   - Убедитесь, что в диалоге выбрано:
     - ✅ "Copy items if needed" (если нужно)
     - ✅ Target "Runner" отмечен
   - Нажмите "Add"

### Шаг 2: Проверить, что файл добавлен в target

1. Выберите файл `WidgetDataSync.swift` в Project Navigator
2. Откройте File Inspector (правая панель, иконка документа)
3. В разделе "Target Membership" убедитесь, что:
   - ✅ "Runner" отмечен галочкой

### Шаг 3: Пересобрать проект

1. В Xcode: Product → Clean Build Folder (Shift+Cmd+K)
2. Product → Build (Cmd+B)

После этого ошибка должна исчезнуть.
