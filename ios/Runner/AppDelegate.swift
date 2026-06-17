import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Регистрируем плагин для синхронизации данных виджетов
    if let controller = window?.rootViewController as? FlutterViewController,
       let registrar = controller.engine.registrar(forPlugin: "WidgetDataSyncPlugin") {
      WidgetDataSyncPlugin.register(with: registrar)
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Обработка URL схемы для открытия из виджета
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    if url.scheme == "ladder" && url.host == "addTask" {
      // Открываем шторку создания задачи через deep link
      if let controller = window?.rootViewController as? FlutterViewController {
        let channel = FlutterMethodChannel(
          name: "com.hackflow.ladder/deep_link",
          binaryMessenger: controller.binaryMessenger
        )
        channel.invokeMethod("openAddTaskPanel", arguments: nil)
      }
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
