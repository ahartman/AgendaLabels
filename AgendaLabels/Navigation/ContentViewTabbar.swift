//
//  ContentView.swift
//  EventKit.Example
//
//  Created by Filip Němeček on 31/07/2020.
//  Copyright © 2020 Filip Němeček. All rights reserved.
//

import SwiftUI

struct ContentViewTabbar: View {
    var body: some View {
        TabView {
            LabelsView()
                .tabItem{
                    Image(systemName: "gearshape")
                    Text("Labels")
                }
        }
    }
}

struct ContentViewTabbar_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
