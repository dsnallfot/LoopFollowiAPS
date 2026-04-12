//
//  TrioRemoteControlView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-08-25.

//

import SwiftUI

struct TrioRemoteControlView: View {
    @ObservedObject var viewModel: TrioRemoteControlViewModel
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
            NavigationView {
                ZStack {
                    ThemeBackground()
                        .ignoresSafeArea()
                VStack {
                    let columns = [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ]
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        CommandButtonView(command: "Måltid", iconName: "fork.knife", destination: MealView())
                        CommandButtonView(command: "Bolus", iconName: "syringe", destination: BolusView())
                        //CommandButtonView(command: "Tillfälliga mål", iconName: "scope", destination: TempTargetView())
                        CommandButtonView(command: "Override", iconName: "slider.horizontal.3", destination: OverrideView())
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
                .navigationBarTitle("Trio fjärrstyrning", displayMode: .inline)
            }
        }
    }
}

struct CommandButtonView<Destination: View>: View {
    let command: String
    let iconName: String
    let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            VStack {
                Image(systemName: iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                Text(command)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding()
            .background(Color.blue.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(30)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
