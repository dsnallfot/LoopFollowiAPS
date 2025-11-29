// LoopFollow
// DailyStatsView.swift

import SwiftUI
import UIKit

@available(iOS 16.0, *)
struct DailyStatsView: View {
    @ObservedObject var viewModel: DailyStatsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var exportURL: URL?
    @State private var showingTitrSummary: Bool = true

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    // Kolumnbredder för raka marginaler
    private let dateWidth: CGFloat = 66
        private let carbsWidth: CGFloat = 36
        private let insulinWidth: CGFloat = 36
        private let meanWidth: CGFloat = 36
        private let lowWidth: CGFloat = 36
        private let titrWidth: CGFloat = 36
        private let tirWidth: CGFloat = 36
        private let stdWidth: CGFloat = 36
        private let profileWidth: CGFloat = 36
        private let emptyWidth: CGFloat = 11

        private let columnSpacing: CGFloat = 1

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
                                        ForEach(Array(viewModel.rowsWithSufficientGlucose.filter { $0.tightRangePercent != nil }.enumerated()), id: \.element.id) { index, row in
                                            HStack(spacing: columnSpacing) {
                                                Text(dateFormatter.string(from: row.date))
                                                    .frame(width: dateWidth, alignment: .leading)
                                                    .font(.system(size: 10).monospacedDigit())

                                                numberCell(row.totalCarbs, width: carbsWidth, decimals: 0)
                                                numberCell(row.insulinTDD, width: insulinWidth)
                                                meanCell(row.meanGlucoseMmol)
                                                lowCell(row.lowPercent)
                                                titrCell(row.tightRangePercent)
                                                tirCell(row.timeInRangePercent)
                                                stdDevCell(stdDev: row.stdDevMmol, mean: row.meanGlucoseMmol)
                                                numberCell(row.profileBasal, width: profileWidth)
                                                emptyCell(row.emptyInfo, width: emptyWidth)
                                            }
                                            .padding(.vertical, 4)
                                            .background(index % 2 == 0 ? Color(.systemGray5.withAlphaComponent(0.6)) : Color.clear)
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
        let daysMeetingTitr = viewModel.numberOfDaysMeetingTitrTarget
        let daysMeetingTir = viewModel.numberOfDaysMeetingTirTarget
        let titrThresholdPercentString = String(format: "%.0f%%", viewModel.titrTargetThreshold * 100)
        let tirThresholdPercentString = String(format: "%.0f%%", viewModel.tirTargetThreshold * 100)
        let daysInScopeString = "\(daysInScope)"
        let daysMeetingTitrString = "\(daysMeetingTitr)"
        let daysMeetingTirString = "\(daysMeetingTir)"

        return Group {
            if daysInScope > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        VStack(alignment: .leading, spacing: 4) {
                            // Rad 1: “Du nådde ditt mål på XX% tid i ...”
                            HStack(spacing: 0) {
                                Text("Du nådde ditt mål på ")
                                Text(showingTitrSummary ? titrThresholdPercentString : tirThresholdPercentString)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color.green.opacity(0.8))
                                Text(showingTitrSummary ? " tid i tight målområde" : " tid i målområde ")
                            }

                            // Rad 2: intervallet i grått
                            HStack(spacing: 0) {
                            Text(showingTitrSummary ? "(3.9–7.8 mmol/L) " : "(3.9–10.0 mmol/L) ")
                                .foregroundColor(.secondary)
                                Text("under ")
                                Text(showingTitrSummary ? daysMeetingTitrString : daysMeetingTirString)
                                    .fontWeight(.bold)
                                Text(" av de senaste ")
                                Text(daysInScopeString)
                                    .fontWeight(.bold)
                                Text(" dagarna.")
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 10)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)

                    if showingTitrSummary {
                        titrStreakBar
                    } else {
                        tirStreakBar
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingTitrSummary.toggle()
                    }
                }
            } else {
                Text("Ingen daglig statistik att visa ännu.")
            }
        }
        .font(.system(size: 14))
        .multilineTextAlignment(.leading)
    }

    /// Visar en enkel streak/gap-rad där varje dag i perioden representeras av en stapel.
    /// Grön = dag når TITR-målet, transparent = dag under målet.
    /// Endast dagar där vi har TITR-data (tightRangePercent != nil) ritas ut.
    private var titrStreakBar: some View {
        // Sortera dagar i kronologisk ordning (äldst till nyast) för vänster-till-höger-läsning
        // och filtrera bort dagar utan TITR-data.
        let filteredRows = viewModel.rowsWithSufficientGlucose
            .sorted { $0.date < $1.date }
            .filter { $0.tightRangePercent != nil }

        let barHeight: CGFloat = 15
        let barSpacing: CGFloat = 1

        return GeometryReader { geometry in
            let count = max(filteredRows.count, 1)
            let totalSpacing = barSpacing * CGFloat(max(count - 1, 0))
            let barWidth = max((geometry.size.width - totalSpacing) / CGFloat(count), 2)

            HStack(spacing: barSpacing) {
                ForEach(Array(filteredRows.enumerated()), id: \.offset) { _, row in
                    let meetsTarget = ((row.tightRangePercent ?? 0) / 100.0) >= viewModel.titrTargetThreshold

                    Rectangle()
                        .fill(meetsTarget ? Color.green.opacity(0.8) : Color.red.opacity(0.7))
                        .frame(width: barWidth, height: barHeight)
                        .overlay(
                            Rectangle()
                                .stroke(Color.green.opacity(0.2), lineWidth: 0.5)
                        )
                }
            }
        }
        .frame(height: barHeight)
    }
    
    private var tirStreakBar: some View {
        // Sortera dagar i kronologisk ordning (äldst till nyast) för vänster-till-höger-läsning
        // och filtrera bort dagar utan TITR-data.
        let filteredRows = viewModel.rowsWithSufficientGlucose
            .sorted { $0.date < $1.date }
            .filter { $0.timeInRangePercent != nil }

        let barHeight: CGFloat = 15
        let barSpacing: CGFloat = 1

        return GeometryReader { geometry in
            let count = max(filteredRows.count, 1)
            let totalSpacing = barSpacing * CGFloat(max(count - 1, 0))
            let barWidth = max((geometry.size.width - totalSpacing) / CGFloat(count), 2)

            HStack(spacing: barSpacing) {
                ForEach(Array(filteredRows.enumerated()), id: \.offset) { _, row in
                    let meetsTarget = ((row.timeInRangePercent ?? 0) / 100.0) >= viewModel.tirTargetThreshold

                    Rectangle()
                        .fill(meetsTarget ? Color.green.opacity(0.8) : Color.red.opacity(0.7))
                        .frame(width: barWidth, height: barHeight)
                        .overlay(
                            Rectangle()
                                .stroke(Color.green.opacity(0.2), lineWidth: 0.5)
                        )
                }
            }
        }
        .frame(height: barHeight)
    }

    private var headerRow: some View {
        HStack(spacing: columnSpacing) {
            Text("Datum")
                .frame(width: dateWidth, alignment: .leading)
                .font(.system(size: 10, weight: .semibold))

            Text("Kolh")
                .frame(width: carbsWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("TDD")
                .frame(width: insulinWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("Medel")
                .frame(width: meanWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("Låg")
                .frame(width: lowWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("TITR")
                .frame(width: titrWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))
            
            Text("TIR")
                .frame(width: tirWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("Std.av")
                .frame(width: stdWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("Basal")
                .frame(width: profileWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))
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
    
    private func emptyCell(
        _ value: String?,
        width: CGFloat,
        decimals: Int = 0,
        foregroundColor: Color? = nil
    ) -> some View {
        Group {
            if value != nil {
                Text("")
            } else {
                Text("")
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
        //if showingTitrSummary {
            if let value = value {
                let fraction = value / 100.0
                color = fraction >= viewModel.titrTargetThreshold ? .green : .red
            } else {
                color = .secondary
            }
        //} else {
        //    color = .secondary
        //}
        return numberCell(value, width: titrWidth, decimals: 0, foregroundColor: color)
    }
    
    private func tirCell(_ value: Double?) -> some View {
        let color: Color
        //if !showingTitrSummary {
        if let value = value {
            let fraction = value / 100.0
            color = fraction >= viewModel.tirTargetThreshold ? .green : .red
        } else {
            color = .secondary
        }
        //} else {
        //    color = .secondary
        //}
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
