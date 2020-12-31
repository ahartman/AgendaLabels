//
//  ContentViewSidebar.swift
//  EventKit.Example
//
//  Created by André Hartman on 24/11/2020.
//  Copyright © 2020 André Hartman. All rights reserved.
//

import SwiftUI

struct ContentViewSidebar: View {
     var body: some View {
        NavigationView {
            List {
                NavigationLink(destination: LabelsView()) {
                    Text("Labels")
                }
            }
            .navigationBarTitle("Menu")
            LabelsView()
        }
    }
}

struct ContentViewSidebar_Previews: PreviewProvider {
    static var previews: some View {
        ContentViewSidebar()
    }
}
