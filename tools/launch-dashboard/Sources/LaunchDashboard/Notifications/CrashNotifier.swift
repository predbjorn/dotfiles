import Foundation
import UserNotifications

final class CrashNotifier {
    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]) { granted, _ in completion(granted) }
    }

    func notifyCrash(label: String, exitCode: Int?) {
        let content = UNMutableNotificationContent()
        content.title = "LaunchAgent crashed"
        content.body = "\(label) exited with code \(exitCode.map(String.init) ?? "?")"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "crash-\(label)",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
