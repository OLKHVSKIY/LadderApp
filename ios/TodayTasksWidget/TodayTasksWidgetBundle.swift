import WidgetKit
import SwiftUI

@main
struct TodayTasksWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayTasksWidget()
        // AddTaskWidget будет добавлен после создания второго виджета
    }
}
