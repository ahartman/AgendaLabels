//
//  LabelsView.swift
//  AgendaAssistent
//
//  Created by André Hartman on 16/12/2020.
//  Copyright © 2020 André Hartman. All rights reserved.
//

import SwiftUI

struct LabelsView: View {
    var body: some View {
        Button(action: {
            Task {
                await LabelsModel().doLabels()
            }
        }, label: {
            HStack {
                Text("Labels")
                Image(systemName: "arrow.up.circle")
            }
        })
    }
}

struct LabelsView_Previews: PreviewProvider {
    static var previews: some View {
        LabelsView()
    }
}
