import WidgetKit
import SwiftUI

@main
struct LadderWidgets: WidgetBundle {
    var body: some Widget {
        TodayTasksWidget()
        AddTaskWidget()
    }
}
