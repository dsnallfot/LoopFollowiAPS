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
    @State private var searchText: String = ""

    var filteredPreferences: [PreferenceEntry] {
        if searchText.isEmpty {
            return viewModel.preferences
        } else {
            return viewModel.preferences.filter { $0.key.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                // 🔹 Search Bar with Clear Button
                HStack {
                    TextField("Sök inställningar...", text: $searchText)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .padding(.trailing, 8)
                        }
                    }
                }
                .padding(.horizontal)

                List(filteredPreferences) { entry in
                    VStack(alignment: .leading) {
                        Text(entry.key)
                            .font(.headline)
                        Text(entry.value)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationBarTitle("Trio Användarinställningar", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Klar") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
