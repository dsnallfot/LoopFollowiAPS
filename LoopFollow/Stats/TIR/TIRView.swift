// LoopFollow
// TIRView.swift

import SwiftUI

struct TIRView: View {
    @ObservedObject var viewModel: TIRViewModel

    var body: some View {
        Button(action: {
            viewModel.toggleTIRMode()
        }) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(viewModel.showTITR ? "Tid inom tight målområde" : "Tid inom målområde")
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Spacer()
                        if let inRangeValue = viewModel.tirData.first(where: { $0.period == .average })?.inRange {
                            Text(formatRange(inRangeValue))
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !viewModel.tirData.isEmpty {
                        TIRGraphView(tirData: viewModel.tirData)
                            .frame(height: 250)
                            .allowsHitTesting(false)
                            .clipped()
                        
                        // Threshold values depending on TIR/TITR mode
                        let highThreshold = viewModel.showTITR ? 7.8 : 10.0   // upper range for "Inom mål"
                        let high = viewModel.showTITR ? 7.9 : 10.1           // lower range for "Högt"
                        
                        VStack(alignment: .leading, spacing: 8) {
                            if let average = viewModel.tirData.first(where: { $0.period == .average }) {
                                TIRLegendItem(
                                    color: .purple,
                                    label: "Akut högt  (> 13.9 mmol/L)",
                                    percentage: average.veryHigh
                                )
                                TIRLegendItem(
                                    color: .blue,
                                    label: String(format: "Högt  (%.1f - 13.9 mmol/L)", high),
                                    percentage: average.high
                                )
                                TIRLegendItem(
                                    color: .green,
                                    label: String(format: "Inom mål  (3.9 - %.1f mmol/L)", highThreshold),
                                    percentage: average.inRange
                                )
                                TIRLegendItem(
                                    color: .orange,
                                    label: "Lågt  (3.1 - 3.8 mmol/L)",
                                    percentage: average.low
                                )
                                TIRLegendItem(
                                    color: .red,
                                    label: "Akut lågt  (< 3.1 mmol/L)",
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
            .background(Color(.systemGray5))
            .cornerRadius(20)
        }
        .buttonStyle(PlainButtonStyle())
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
}

struct TIRLegendItem: View {
    let color: Color
    let label: String
    let percentage: Double

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(color)
                .frame(width: 16, height: 16)
            Text(String(format: "%.1f%%", percentage))
                .foregroundColor(.primary)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}
