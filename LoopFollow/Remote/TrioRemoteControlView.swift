//
//  TrioRemoteControlView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-08-25.

//

import SwiftUI

@available(iOS 16.0, *)
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
                        CommandButtonView(command: "Måltid och Bolus", iconName: "fork.knife", destination: MealView(), color: Color(UIColor.insulin))
                        //CommandButtonView(command: "Bolus", iconName: "syringe", destination: BolusView(), color: Color(UIColor.insulin))
                        //CommandButtonView(command: "Tillfälliga mål", iconName: "scope", destination: TempTargetView(), color: .mint)
                        CommandButtonView(command: "Override", iconName: "slider.horizontal.3", destination: OverrideView(), color: .purple)
                        CommandButtonView(command: "Snabbval", iconName: "plus.square.on.square", destination: ComboView(), color: .green)
                        CommandButtonView(command: "Fingerstick", iconName: "drop", destination: ManualGlucoseView(), color: .red)
                        ShortcutButtonView(command: "Hälsologgning", iconName: "list.clipboard", color: .gray)
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
    let color: Color

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
            .background(color.opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(25)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ShortcutButtonView: View {
    let command: String
    let iconName: String
    let color: Color

    var body: some View {
        Button(action: {
            let urlString = "shortcuts://run-shortcut?name=Hälsologgning"
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }) {
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
            .background(color.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(25)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
