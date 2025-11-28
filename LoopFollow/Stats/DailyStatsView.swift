// LoopFollow
// DailyStatsView.swift

import SwiftUI
import UIKit

@available(iOS 16.0, *)
struct DailyStatsView: View {
    @ObservedObject var viewModel: DailyStatsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var exportURL: URL?

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    // Kolumnbredder för raka marginaler
    private let dateWidth: CGFloat = 70
        private let carbsWidth: CGFloat = 40
        private let insulinWidth: CGFloat = 40
        private let meanWidth: CGFloat = 40
        private let lowWidth: CGFloat = 40
        private let tirWidth: CGFloat = 40
        private let stdWidth: CGFloat = 40
        private let profileWidth: CGFloat = 40

        private let columnSpacing: CGFloat = 2

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.rows.isEmpty {
                    ProgressView("Beräknar daglig statistik…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        summarySection
                            .padding(.horizontal, 10)
                            .padding(.top, 8)

                        ScrollView(.horizontal) {
                            VStack(alignment: .leading, spacing: 0) {
                                headerRow
                                    .padding(.vertical, 6)
                                Divider()

                                ScrollView(.vertical) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                                            HStack(spacing: columnSpacing) {
                                                Text(dateFormatter.string(from: row.date))
                                                    .frame(width: dateWidth, alignment: .leading)
                                                    .font(.system(size: 11).monospacedDigit())

                                                numberCell(row.totalCarbs, width: carbsWidth, decimals: 0)
                                                numberCell(row.insulinTDD, width: insulinWidth)
                                                meanCell(row.meanGlucoseMmol)
                                                lowCell(row.lowPercent)
                                                titrCell(row.tightRangePercent)
                                                stdDevCell(stdDev: row.stdDevMmol, mean: row.meanGlucoseMmol)
                                                numberCell(row.profileBasal, width: profileWidth)
                                            }
                                            .padding(.vertical, 4)
                                            .background(index % 2 == 0 ? Color(.systemGray5) : Color.clear)
                                            Divider()
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 12)
                            //.padding(.bottom, 12)
                        }
                    }
                }
            }
            .navigationTitle("Daglig statistik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if let url = viewModel.writeCSVToDisk() {
                            exportURL = url
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Klar") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.loadDailyStats()
            }
            .sheet(
                isPresented: Binding(
                    get: { exportURL != nil },
                    set: { isPresented in
                        if !isPresented {
                            exportURL = nil
                        }
                    }
                )
            ) {
                if let url = exportURL {
                    ActivityView(activityItems: [url])
                }
            }
            .alert("Fel", isPresented: .constant(viewModel.errorMessage != nil), actions: {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
        }
    }

    // MARK: - Subviews

    private var summarySection: some View {
        let daysInScope = viewModel.numberOfDaysInScope
        let daysMeeting = viewModel.numberOfDaysMeetingTitrTarget
        let thresholdPercentString = String(format: "%.0f%%", viewModel.titrTargetThreshold * 100)
        let daysInScopeString = "\(daysInScope)"
        let daysMeetingString = "\(daysMeeting)"

        return Group {
            if daysInScope > 0 {
                Text("Du nådde ditt mål ") +
                Text(thresholdPercentString).fontWeight(.semibold) +
                Text(" inom intervallet 3.9–7.8 mmol/L under ") +
                Text(daysMeetingString).fontWeight(.semibold) +
                Text(" av de senaste ") +
                Text(daysInScopeString).fontWeight(.semibold) +
                Text(" dagarna. ")
            } else {
                Text("Ingen daglig statistik att visa ännu.")
            }
        }
        .font(.system(size: 14))
        .multilineTextAlignment(.leading)
    }

    private var headerRow: some View {
        HStack(spacing: columnSpacing) {
            Text("Datum")
                .frame(width: dateWidth, alignment: .leading)
                .font(.system(size: 11, weight: .semibold))

            Text("KH")
                .frame(width: carbsWidth, alignment: .trailing)
                .font(.system(size: 11, weight: .semibold))

            Text("TDD")
                .frame(width: insulinWidth, alignment: .trailing)
                .font(.system(size: 11, weight: .semibold))

            Text("Medel")
                .frame(width: meanWidth, alignment: .trailing)
                .font(.system(size: 11, weight: .semibold))

            Text("Låg")
                .frame(width: lowWidth, alignment: .trailing)
                .font(.system(size: 11, weight: .semibold))

            Text("TITR")
                .frame(width: tirWidth, alignment: .trailing)
                .font(.system(size: 11, weight: .semibold))

            Text("Std av")
                .frame(width: stdWidth, alignment: .trailing)
                .font(.system(size: 11, weight: .semibold))

            Text("Basal")
                .frame(width: profileWidth, alignment: .trailing)
                .font(.system(size: 11, weight: .semibold))
        }
    }

    private func numberCell(
        _ value: Double?,
        width: CGFloat,
        decimals: Int = 1,
        foregroundColor: Color? = nil
    ) -> some View {
        Group {
            if let value = value {
                Text(String(format: "%.\(decimals)f", value))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(foregroundColor ?? .primary)
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: width, alignment: .trailing)
    }

    private func lowCell(_ value: Double?) -> some View {
        let color: Color
        if let value = value {
            let fraction = value / 100.0
            if fraction <= viewModel.lowGlucoseGreatThreshold {
                color = .green
            } else if fraction <= viewModel.lowGlucoseOKThreshold {
                color = .orange
            } else {
                color = .red
            }
        } else {
            color = .secondary
        }
        return numberCell(value, width: lowWidth, decimals: 1, foregroundColor: color)
    }

    private func titrCell(_ value: Double?) -> some View {
        let color: Color
        if let value = value {
            let fraction = value / 100.0
            color = fraction >= viewModel.titrTargetThreshold ? .green : .red
        } else {
            color = .secondary
        }
        return numberCell(value, width: tirWidth, decimals: 0, foregroundColor: color)
    }

    private func meanCell(_ value: Double?) -> some View {
        let color: Color
        if let value = value {
            if value <= viewModel.bgAverageGreatThreshold {
                color = .green
            } else if value <= viewModel.bgAverageOKThreshold {
                color = .orange
            } else {
                color = .red
            }
        } else {
            color = .secondary
        }
        return numberCell(value, width: meanWidth, decimals: 1, foregroundColor: color)
    }

    private func stdDevCell(stdDev: Double?, mean: Double?) -> some View {
        let color: Color
        if let stdDev = stdDev, stdDev > 0 {
            if stdDev <= viewModel.stdDevGreatThreshold {
                color = .green
            } else if stdDev <= viewModel.stdDevOkThreshold {
                color = .orange
            } else {
                color = .red
            }
        } else {
            color = .secondary
        }
        return numberCell(stdDev, width: stdWidth, decimals: 1, foregroundColor: color)
    }
}

// MARK: - UIActivityViewController bridge

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
