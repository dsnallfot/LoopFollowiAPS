//
//  ProfileSchedulesView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-02-26.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import SwiftUI

struct ProfileSchedulesView: View {
    @ObservedObject var viewModel = ProfileSchedulesViewModel()
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Targets")) {
                    ForEach(viewModel.targetEntries) { entry in
                        HStack {
                            Text(entry.time)
                                .font(.headline)
                            Spacer()
                            Text(entry.value)
                                .font(.headline)
                        }
                    }
                }
                
                Section(header: Text("Basal")) {
                    ForEach(viewModel.basalEntries) { entry in
                        HStack {
                            Text(entry.time)
                                .font(entry.time == "Total Daily Basal" ? .headline.bold() : .headline)
                            Spacer()
                            Text(entry.value)
                                .font(entry.time == "Total Daily Basal" ? .headline.bold() : .headline)
                        }
                    }
                }

                Section(header: Text("Carb Ratios")) {
                    ForEach(viewModel.carbRatioEntries) { entry in
                        HStack {
                            Text(entry.time)
                                .font(.headline)
                            Spacer()
                            Text(entry.value)
                                .font(.headline)
                        }
                    }
                }

                Section(header: Text("Insulin Sensitivity Factor")) {
                    ForEach(viewModel.isfEntries) { entry in
                        HStack {
                            Text(entry.time)
                                .font(.headline)
                            Spacer()
                            Text(entry.value)
                                .font(.headline)
                        }
                    }
                }

                Section(header: Text("Carb Sensitivity Factor")) {
                    ForEach(viewModel.csfEntries) { entry in
                        HStack {
                            Text(entry.time)
                                .font(.headline)
                            Spacer()
                            Text(entry.value)
                                .font(.headline)
                        }
                    }
                }
                
                Section(header: Text("Minimum Carbs grams/hour")) {
                    ForEach(viewModel.minCarbsEntries) { entry in
                        HStack {
                            Text(entry.time)
                                .font(entry.time == "Average" ? .headline.bold() : .headline)
                            Spacer()
                            Text(entry.value)
                                .font(entry.time == "Average" ? .headline.bold() : .headline)
                        }
                    }
                }
            }
            .navigationBarTitle("Profile Schedules", displayMode: .inline)
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
