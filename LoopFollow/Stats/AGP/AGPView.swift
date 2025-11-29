// LoopFollow
// AGPView.swift

import SwiftUI

struct AGPView: View {
    @ObservedObject var viewModel: AGPViewModel

    var body: some View {
        if !viewModel.agpData.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ambulatorisk Glukosprofil (AGP)")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                AGPGraphView(agpData: viewModel.agpData)
                    .frame(height: 200)
                    .allowsHitTesting(false)
                    .clipped()

                // Legend
                HStack(spacing: 16) {
                    LegendItem(color: .gray.opacity(0.6), label: "5e-95e")
                    LegendItem(color: .blue.opacity(0.7), label: "25e-75e")
                    LegendItem(color: .blue, label: "Median")
                }
                .font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray5.withAlphaComponent(0.6)))
            .cornerRadius(15)
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
