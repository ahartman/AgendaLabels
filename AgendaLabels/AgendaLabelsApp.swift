//
//  AgendaLabelsApp.swift
//  AgendaAssistent
//
//  Created by André Hartman on 31/12/2020.
//  Copyright © 2020 André Hartman. All rights reserved.
//
import Foundation
import SwiftUI

@main
struct AgendaLabelsApp: App {
    init() {
        Task {
            await LabelsModelAsync().doLabels()
            print("exiting")
            exit(1)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
