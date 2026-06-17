import WidgetKit
import SwiftUI

struct AddTaskWidget: Widget {
    let kind: String = "AddTaskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AddTaskProvider()) { entry in
            AddTaskEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Добавить задачу")
        .description("Быстрое добавление задачи")
        .supportedFamilies([.systemSmall])
    }
}

struct AddTaskEntry: TimelineEntry {
    let date: Date
}

struct AddTaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> AddTaskEntry {
        AddTaskEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (AddTaskEntry) -> ()) {
        let entry = AddTaskEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = AddTaskEntry(date: Date())
        // Виджет статичный, обновление не требуется часто
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct AddTaskEntryView: View {
    var entry: AddTaskProvider.Entry
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Заголовок "Добавить задачу"
            Text("Добавить задачу")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Spacer()
            
            // "Мои задачи" серым
            Text("Мои задачи")
                .font(.system(size: 13))
                .foregroundColor(.gray)
            
            // Кнопка "+" внизу справа
            HStack {
                Spacer()
                Circle()
                    .fill(Color.red)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text("+")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
        }
        .padding(12)
        .widgetURL(URL(string: "ladder://addTask"))
    }
}

#Preview(as: .systemSmall) {
    AddTaskWidget()
} timeline: {
    AddTaskEntry(date: Date())
}
