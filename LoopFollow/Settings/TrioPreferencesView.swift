//
//  TrioPreferencesView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-02-23.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//
import SwiftUI

struct TrioPreferencesView: View {
    @ObservedObject var viewModel = TrioPreferencesViewModel()
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List(viewModel.preferences) { entry in
                VStack(alignment: .leading) {
                    Text(entry.key)
                        .font(.headline)
                    Text(entry.value)
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
            .navigationBarTitle("Trio Preferences", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

