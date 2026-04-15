//
//  LoadingButtonView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-09-17.

//

import SwiftUI

struct LoadingButtonView: View {
    var buttonText: String
    var progressText: String
    var isLoading: Bool
    var action: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        Section {
            VStack {
                if isLoading {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 10)
                        Text(progressText)
                    }
                    .padding()
                } else {
                    if #available(iOS 26.0, *) {
                        Button(action: {
                            action()
                        }) {
                            Text(buttonText)
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(isDisabled)
                    } else {
                        // Fallback on earlier versions
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowInsets(EdgeInsets())
        }
    }
}
