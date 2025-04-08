//
//  TrioOrefView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-04-08.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import SwiftUI

struct TrioOrefView: View {
    @ObservedObject var viewModel = TrioOrefViewModel()
    @Environment(\.presentationMode) var presentationMode
    @State private var searchText: String = ""

    var filteredEntries: [Oref2Entry] {
        if searchText.isEmpty {
            return viewModel.orefEntries
        } else {
            return viewModel.orefEntries.filter {
                $0.key.localizedCaseInsensitiveContains(searchText) ||
                $0.value.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    TextField("Sök Oref-variabler...", text: $searchText)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .padding(.trailing, 8)
                        }
                    }
                }
                .padding(.horizontal)

                List(filteredEntries) { entry in
                    VStack(alignment: .leading) {
                        Text(entry.key).font(.headline)
                        Text(entry.value).font(.subheadline)
                    }.padding(.vertical, 4)
                }
            }
            .navigationBarTitle(viewModel.formattedTitle, displayMode: .inline)
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
