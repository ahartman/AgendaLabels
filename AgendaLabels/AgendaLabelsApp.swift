//
//  AgendaLabelsApp.swift
//  AgendaAssistent
//
//  Created by André Hartman on 31/12/2020.
//  Copyright © 2020 André Hartman. All rights reserved.
//
import Foundation
import SwiftUI
import UserNotifications

@main
struct AgendaLabelsApp: App {
    private var delegate: NotificationDelegate = .init()

    init() {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error = error {
                print("Notificaties: \(error)")
            }
        }
        Task {
            await LabelsModel().doLabels()
            print("Exiting")
            exit(1)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        print("userInfo: \(userInfo)")
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}
