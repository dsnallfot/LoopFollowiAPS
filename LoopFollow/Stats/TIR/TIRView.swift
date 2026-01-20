// LoopFollow
// TIRView.swift

import SwiftUI

struct TIRView: View {
    @ObservedObject var viewModel: TIRViewModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(viewModel.showTITR ? "Tid i (tight) målområde" : "Tid i målområde")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Spacer()
                    let graphData = (viewModel.graphMode == .hours) ? viewModel.tirData : viewModel.tirWeekdayData
                    if let inRangeValue = graphData.first(where: { $0.period == .average })?.inRange {
                        Text(formatRange(inRangeValue))
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }

                if !viewModel.tirData.isEmpty {
                    let graphData = (viewModel.graphMode == .hours) ? viewModel.tirData : viewModel.tirWeekdayData
                    let order = (viewModel.graphMode == .hours) ? TIRPeriod.displayOrder : TIRPeriod.weekdayDisplayOrder

                    TIRGraphView(tirData: graphData, displayOrder: order)
                        .frame(height: 200)
                        .allowsHitTesting(false)
                        .clipped()

                    // Threshold values depending on TIR/TITR mode
                    let highThreshold = viewModel.showTITR ? 7.8 : 10.0   // upper range for "Inom mål"
                    let high = viewModel.showTITR ? 7.8 : 10.0           // lower range for "Högt"

                    VStack(alignment: .leading, spacing: 4) {
                        if let average = graphData.first(where: { $0.period == .average }) {
                            let dayMinutes = viewModel.averageDayMinutes
                            let timeVeryHigh = average.veryHigh * dayMinutes / 100
                            let timeHigh = average.high * dayMinutes / 100
                            let timeInRange = average.inRange * dayMinutes / 100
                            let timeLow = average.low * dayMinutes / 100
                            let timeVeryLow = average.veryLow * dayMinutes / 100

                            TIRLegendItem(
                                color: .purple.opacity(0.7),
                                label: "Akut högt",
                                detailLabel: "(över 13.9 mmol/L)",
                                timeLabel: formatMinutesPerDay(timeVeryHigh),
                                percentage: average.veryHigh
                            )
                            TIRLegendItem(
                                color: .blue.opacity(0.7),
                                label: "Högt",
                                detailLabel: String(format: "(%.1f - 13.9 mmol/L)", high),
                                timeLabel: formatMinutesPerDay(timeHigh),
                                percentage: average.high
                            )
                            TIRLegendItem(
                                color: .green.opacity(0.7),
                                label: "Inom mål",
                                detailLabel: String(format: "(3.8 - %.1f mmol/L)", highThreshold),
                                timeLabel: formatMinutesPerDay(timeInRange),
                                percentage: average.inRange
                            )
                            TIRLegendItem(
                                color: .orange.opacity(0.7),
                                label: "Lågt",
                                detailLabel: "(3.1 - 3.8 mmol/L)",
                                timeLabel: formatMinutesPerDay(timeLow),
                                percentage: average.low
                            )
                            TIRLegendItem(
                                color: .red.opacity(0.7),
                                label: "Akut lågt",
                                detailLabel: "(under 3.1 mmol/L)",
                                timeLabel: formatMinutesPerDay(timeVeryLow),
                                percentage: average.veryLow
                            )
                        }
                    }
                    .font(.caption2)
                } else {
                    Text("Ingen data tillgänlig")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(height: 250)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.5))
                .padding(8)
        }
        .background(Color(.systemBackground.withAlphaComponent(0.5)))
        .cornerRadius(15)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.toggleGraphMode()
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            viewModel.toggleTIRMode()
        }
    }

    private func formatRange(_: Double) -> String {
        let lowThreshold: Double
        let highThreshold: Double

        if UserDefaultsRepository.units.value == "mg/dL" {
            lowThreshold = 70.0
            highThreshold = viewModel.showTITR ? 140.0 : 180.0
        } else {
            lowThreshold = 3.9
            highThreshold = viewModel.showTITR ? 7.8 : 10.0
        }

        return String(format: "%.1f – %.1f %@", lowThreshold, highThreshold, UserDefaultsRepository.units.value)
    }
    
    private func formatMinutesPerDay(_ minutes: Double) -> String {
        let totalMinutes = Int(round(minutes))
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        
        if hours > 0 {
            // Visa t.ex. "12h 45m", "3h 2m", "6h 0m"
            return "\(hours)h \(mins)m"
        } else {
            // Bara minuter: "43m", "5m"
            return "\(mins)m"
        }
    }
}

struct TIRLegendItem: View {
    let color: Color
    let label: String
    let detailLabel: String
    let timeLabel: String
    let percentage: Double

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(color)
                .frame(width: 10, height: 10, alignment: .leading)
                //.frame(width: 14, alignment: .leading)
            Text(String(format: "%.1f %%", percentage))
                .foregroundColor(.primary)
                .frame(width: 48, alignment: .leading)
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .leading)
            Text(detailLabel)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Spacer()
            Text(timeLabel)
                .foregroundColor(.primary)
                .frame(width: 60, alignment: .trailing)

        }
    }
}
