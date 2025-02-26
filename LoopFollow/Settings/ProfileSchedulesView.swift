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
    
    @State private var selectedSection: SectionType = .targets // Default section

    enum SectionType: String, CaseIterable {
        case targets = "Targets"
        case basal = "Basal"
        case cr = "CR"
        case isf = "ISF"
        case csf = "CSF"
        case cHr = "C/Hr"

        var displayName: String {
            switch self {
            case .targets: return "Targets"
            case .basal: return "Basal"
            case .cr: return "Carb Ratios"
            case .isf: return "Insulin Sensitivity Factor"
            case .csf: return "Carb Sensitivity Factor"
            case .cHr: return "Minimum Carbs grams/hour"
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                Picker("Select Section", selection: $selectedSection) {
                    ForEach(SectionType.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                List {
                    if selectedSection == .targets {
                        Section(header: Text("Targets")) {
                            ForEach(viewModel.targetEntries) { entry in
                                scheduleRow(entry)
                            }
                        }
                    }

                    if selectedSection == .basal {
                        Section(header: Text("Basal")) {
                            ForEach(viewModel.basalEntries) { entry in
                                scheduleRow(entry, isBold: entry.time == "Total Daily Basal")
                            }
                        }
                    }

                    if selectedSection == .cr {
                        Section(header: Text("Carb Ratios")) {
                            ForEach(viewModel.carbRatioEntries) { entry in
                                scheduleRow(entry)
                            }
                        }
                    }

                    if selectedSection == .isf {
                        Section(header: Text("Insulin Sensitivity Factor")) {
                            ForEach(viewModel.isfEntries) { entry in
                                scheduleRow(entry)
                            }
                        }
                    }

                    if selectedSection == .csf {
                        Section(header: Text("Carb Sensitivity Factor")) {
                            ForEach(viewModel.csfEntries) { entry in
                                scheduleRow(entry)
                            }
                        }
                    }

                    if selectedSection == .cHr {
                        Section(header: Text("Minimum Carbs grams/hour")) {
                            ForEach(viewModel.minCarbsEntries) { entry in
                                scheduleRow(entry, isBold: entry.time == "Average")
                            }
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

    @ViewBuilder
    private func scheduleRow(_ entry: ScheduleEntry, isBold: Bool = false) -> some View {
        HStack {
            Text(entry.time)
                .font(isBold ? .headline.bold() : .subheadline)
            Spacer()
            Text(entry.value)
                .font(isBold ? .headline.bold() : .subheadline)
        }
    }
}
