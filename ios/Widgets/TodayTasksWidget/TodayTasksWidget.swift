import WidgetKit
import SwiftUI

struct TodayTasksWidget: Widget {
    let kind: String = "TodayTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayTasksProvider()) { entry in
            TodayTasksEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Сегодня")
        .description("Показывает задачи на сегодня")
        .supportedFamilies([.systemSmall])
    }
}

struct TodayTasksEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
    let taskCount: Int
}

struct TaskItem {
    let title: String
}

struct TodayTasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayTasksEntry {
        TodayTasksEntry(
            date: Date(),
            tasks: [
                TaskItem(title: "Пример задачи 1"),
                TaskItem(title: "Пример задачи 2"),
                TaskItem(title: "Пример задачи 3"),
                TaskItem(title: "Пример задачи 4")
            ],
            taskCount: 4
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayTasksEntry) -> ()) {
        let entry = loadTasks()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = loadTasks()
        // Обновляем каждые 15 минут
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
  private func loadTasks() -> TodayTasksEntry {
    // Загружаем данные из App Group
    guard let sharedDefaults = UserDefaults(suiteName: "group.com.hackflow.ladder") else {
      return TodayTasksEntry(date: Date(), tasks: [], taskCount: 0)
    }
    
    let taskCount = sharedDefaults.integer(forKey: "todayTaskCount")
    var tasks: [TaskItem] = []
    
    // Загружаем первые 4 задачи
    for i in 0..<min(4, taskCount) {
      if let taskTitle = sharedDefaults.string(forKey: "todayTask_\(i)") {
        tasks.append(TaskItem(title: taskTitle))
      }
    }
    
    return TodayTasksEntry(
      date: Date(),
      tasks: tasks,
      taskCount: taskCount
    )
  }
}

struct TodayTasksEntryView: View {
    var entry: TodayTasksProvider.Entry
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Заголовок "Сегодня" + количество
            HStack {
                Text("Сегодня \(entry.taskCount)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Spacer()
            }
            
            // Список задач
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(entry.tasks.enumerated()), id: \.offset) { index, task in
                    Text(task.title)
                        .font(.system(size: 13))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            
            Spacer()
        }
        .padding(12)
    }
}

#Preview(as: .systemSmall) {
    TodayTasksWidget()
} timeline: {
    TodayTasksEntry(
        date: Date(),
        tasks: [
            TaskItem(title: "Задача 1"),
            TaskItem(title: "Задача 2"),
            TaskItem(title: "Задача 3"),
            TaskItem(title: "Задача 4")
        ],
        taskCount: 4
    )
}
