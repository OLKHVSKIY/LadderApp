import Flutter
import UIKit
import WidgetKit

public class WidgetDataSyncPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.hackflow.ladder/widget_data_sync", binaryMessenger: registrar.messenger())
    let instance = WidgetDataSyncPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "syncTodayTasks":
      syncTodayTasks(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  private func syncTodayTasks(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let taskCount = args["taskCount"] as? Int,
          let tasks = args["tasks"] as? [String] else {
      result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
      return
    }
    
    // Сохраняем в App Group
    if let sharedDefaults = UserDefaults(suiteName: "group.com.hackflow.ladder") {
      sharedDefaults.set(taskCount, forKey: "todayTaskCount")
      
      // Сохраняем задачи
      for (index, task) in tasks.enumerated() {
        sharedDefaults.set(task, forKey: "todayTask_\(index)")
      }
      
      // Очищаем оставшиеся слоты
      for index in tasks.count..<4 {
        sharedDefaults.removeObject(forKey: "todayTask_\(index)")
      }
      
      // Обновляем виджеты
      if #available(iOS 14.0, *) {
        WidgetCenter.shared.reloadAllTimelines()
      }
      
      result(true)
    } else {
      result(FlutterError(code: "APP_GROUP_ERROR", message: "Failed to access App Group", details: nil))
    }
  }
}
