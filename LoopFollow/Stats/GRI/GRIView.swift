// LoopFollow
// GRIView.swift

import SwiftUI

struct GRIView: View {
    @ObservedObject var viewModel: GRIViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Glykemiskt Riskindex (GRI)")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Spacer()
                if let gri = viewModel.gri {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0f", gri))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(griColor(gri))
                        Text(griZone(gri))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("---")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                }
            }

            if let hypo = viewModel.griHypoComponent, let hyper = viewModel.griHyperComponent {
                GRIRiskGridView(
                    hypoComponent: hypo,
                    hyperComponent: hyper,
                    gri: viewModel.gri ?? 0
                )
                .frame(height: 250)
                .allowsHitTesting(false)
                .clipped()
                HStack {
                    Text("Hyper >10 mmol/L (%)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Hypo <3.9 mmol/L (%)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    ZoneLegendItem(color: .green.opacity(0.6), label: "A 0-20")
                    ZoneLegendItem(color: .yellow.opacity(0.6), label: "B 21-40")
                    ZoneLegendItem(color: .orange.opacity(0.6), label: "C 41-60")
                    ZoneLegendItem(color: .red.opacity(0.6), label: "D 61-80")
                    ZoneLegendItem(color: .red.opacity(0.8), label: "E 81-100")
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
        .padding(.horizontal)
        .padding(.bottom)
        .padding(.top, 8)
        .background(Color(.systemBackground.withAlphaComponent(0.3)))
        .cornerRadius(15)
    }

    private func griColor(_ gri: Double) -> Color {
        if gri <= 20 {
            return .green
        } else if gri <= 40 {
            return .yellow
        } else if gri <= 60 {
            return .orange
        } else if gri <= 80 {
            return .red.opacity(0.8)
        } else {
            return .red
        }
    }

    private func griZone(_ gri: Double) -> String {
        if gri <= 20 {
            return "Zon A"
        } else if gri <= 40 {
            return "Zon B"
        } else if gri <= 60 {
            return "Zon C"
        } else if gri <= 80 {
            return "Zon D"
        } else {
            return "Zon E"
        }
    }
}

struct ZoneLegendItem: View {
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
