// LoopFollow
// AGPView.swift

import SwiftUI

struct AGPView: View {
    @ObservedObject var viewModel: AGPViewModel

    var body: some View {
        let canToggle = viewModel.canToggleDayByDay

        if !viewModel.agpData.isEmpty {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 8) {

                    // Du bad om ny rubrik: “Glukos dag för dag”
                    // Jag visar den rubriken i day-by-day-läget, och behåller AGP-rubriken i AGP-läget.
                    Text(viewModel.displayMode == .dayByDay
                         ? "Glukos dag för dag"
                         : "Ambulatorisk Glukosprofil (AGP)")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    if viewModel.displayMode == .dayByDay {
                        AGPDayByDayGraphView(series: viewModel.dayByDaySeries)
                            .frame(height: 200)
                            .allowsHitTesting(false)
                            .clipped()

                        HStack(spacing: 12) {
                            ForEach(AGPWeekday.allCases, id: \.self) { day in
                                LegendItem(color: day.color, label: day.shortSv)
                            }
                        }
                        .font(.caption2)

                    } else {
                        AGPGraphView(agpData: viewModel.agpData)
                            .frame(height: 200)
                            .allowsHitTesting(false)
                            .clipped()

                        HStack(spacing: 16) {
                            LegendItem(color: .blue.opacity(0.7), label: "5e-95e")
                            LegendItem(color: .blue.opacity(0.9), label: "25e-75e")
                            LegendItem(color: .primary, label: "Median")
                        }
                        .font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.systemBackground.withAlphaComponent(0.5)))
                .cornerRadius(15)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard canToggle else { return }
                    viewModel.toggleDisplayMode()
                }

                if canToggle {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(8)
                }
            }
            .onChange(of: viewModel.currentInterval.duration) { _ in
                viewModel.enforceModeConstraints()
            }
        }
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .foregroundColor(.secondary)
        }
    }
}
