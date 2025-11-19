//
//  LogView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-13.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import SwiftUI

struct LogView: View {
    @ObservedObject var viewModel = LogViewModel()
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack {
                Picker("Category", selection: $viewModel.selectedCategory) {
                    Text("Allt").tag(LogManager.Category?.none)
                    ForEach(LogManager.Category.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(LogManager.Category?.some(category))
                    }
                }
                .pickerStyle(MenuPickerStyle())

                SearchBar(
                    text: $viewModel.searchText,
                    placeholder: viewModel.searchResultsIsHighlighted ? "Highlighta i loggen" : "Sök i loggen"
                )
                .padding([.leading, .trailing])

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.filteredLogEntries) { entry in
                            Text(entry.text)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 0)
                                .foregroundColor(
                                    viewModel.searchResultsIsHighlighted &&
                                    !viewModel.searchText.isEmpty &&
                                    entry.text.localizedCaseInsensitiveContains(viewModel.searchText)
                                    ? .blue
                                    : .primary
                                )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationBarTitle("Dagens logg", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        viewModel.searchResultsIsHighlighted.toggle()
                    }) {
                        Image(systemName: viewModel.searchResultsIsHighlighted
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                            .foregroundColor(viewModel.searchResultsIsHighlighted ? .blue : .primary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Klar") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.loadLogEntries()
            }
        }
    }
}
