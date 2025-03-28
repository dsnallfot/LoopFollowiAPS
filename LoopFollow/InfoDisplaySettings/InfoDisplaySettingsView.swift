//
//  InfoDisplaySettingsView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-08-05.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import SwiftUI

struct InfoDisplaySettingsView: View {
    @ObservedObject var viewModel: InfoDisplaySettingsViewModel
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Allmänt")) {
                    Toggle(isOn: Binding(
                        get: { UserDefaultsRepository.hideInfoTable.value },
                        set: { UserDefaultsRepository.hideInfoTable.value = $0 }
                    )) {
                        Text("Dölj informationspanelen")
                    }
                }

                Section(header: Text("Inställningar för informationspanel")) {
                    List {
                        ForEach(viewModel.infoSort, id: \.self) { sortedIndex in
                            HStack {
                                Text(viewModel.getName(for: sortedIndex))
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { viewModel.infoVisible[sortedIndex] },
                                    set: { _ in
                                        viewModel.toggleVisibility(for: sortedIndex)
                                    }
                                ))
                                .labelsHidden()
                            }
                        }
                        .onMove(perform: viewModel.move)
                    }
                    .environment(\.editMode, .constant(.active))
                }
            }
            .navigationBarItems(trailing: Button("Klar") {
                presentationMode.wrappedValue.dismiss()
            })
            .onDisappear {
                NotificationCenter.default.post(name: NSNotification.Name("refresh"), object: nil)
            }
        }
    }
}
