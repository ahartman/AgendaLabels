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

    init() {
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
