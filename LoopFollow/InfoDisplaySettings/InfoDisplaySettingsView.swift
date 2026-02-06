//
//  InfoDisplaySettingsView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-08-05.

//

import SwiftUI

@available(iOS 16.0, *)
struct InfoDisplaySettingsView: View {
    @ObservedObject var viewModel: InfoDisplaySettingsViewModel
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            List {
                Section(header: Text("Allmänt")) {
                    Toggle(isOn: Binding(
                        get: { UserDefaultsRepository.hideInfoTable.value },
                        set: { UserDefaultsRepository.hideInfoTable.value = $0 }
                    )) {
                        Text("Dölj informationspanelen")
                    }
                    .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
                }

                Section(header: Text("Inställningar för informationspanel")) {
                    ForEach(viewModel.infoSort, id: \.self) { sortedIndex in
                        HStack {
                            Text(viewModel.getName(for: sortedIndex))
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { viewModel.infoVisible[sortedIndex] },
                                set: { _ in viewModel.toggleVisibility(for: sortedIndex) }
                            ))
                            .labelsHidden()
                        }
                        .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
                    }
                    .onMove(perform: viewModel.move)
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .onDisappear {
            NotificationCenter.default.post(name: NSNotification.Name("refresh"), object: nil)
        }
    }
}
