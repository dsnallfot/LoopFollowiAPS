//
//  TrioPreferencesView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-02-23.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import SwiftUI
import UIKit
@available(iOS 16.0, *)
private struct PreferenceKeyItem: Identifiable {
    let key: String
    var id: String { key }
}
private struct PinnedSearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(spacing: 0) {
            UISearchBarRepresentable(text: $text, placeholder: placeholder)
                .frame(height: 44)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 2)

            //Divider()
                //.overlay(Color(UIColor.separator))
        }
        .background(Color.clear)
    }
}

private struct UISearchBarRepresentable: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let sb = UISearchBar(frame: .zero)
        sb.delegate = context.coordinator
        sb.placeholder = placeholder
        sb.autocapitalizationType = .none
        sb.autocorrectionType = .no
        sb.searchBarStyle = .minimal
        sb.returnKeyType = .done
        sb.enablesReturnKeyAutomatically = false
        if #available(iOS 13.0, *) {
            sb.searchTextField.backgroundColor = UIColor.systemGray.withAlphaComponent(0.1)
        }
        return sb
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            text = searchText
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            // Keep binding in sync if user taps away
            text = searchBar.text ?? ""
        }
    }
}

@available(iOS 16.0, *)
struct TrioPreferencesView: View {
    @ObservedObject var viewModel = TrioPreferencesViewModel()
    @State private var searchText: String = ""
    @State private var selectedPreferenceKeyForLog: PreferenceKeyItem?

    var filteredPreferences: [PreferenceEntry] {
        if searchText.isEmpty {
            return viewModel.preferences
        } else {
            return viewModel.preferences.filter { $0.key.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                PinnedSearchBar(text: $searchText, placeholder: "Sök inställningar...")

                List(filteredPreferences) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.key)
                            .font(.headline)
                        Text(entry.value)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                    .onTapGesture {
                        selectedPreferenceKeyForLog = PreferenceKeyItem(key: entry.key)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .sheet(item: $selectedPreferenceKeyForLog) { item in
                SettingsLogModal(initialSearchText: item.key)
            }
        }
    }
}

@available(iOS 16.0, *)
private struct SettingsLogModal: UIViewControllerRepresentable {
    let initialSearchText: String

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = TrioSettingsLogView(initialSearchText: initialSearchText)
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        if let vc = uiViewController.viewControllers.first as? TrioSettingsLogView {
            vc.setSearchTextAndFilter(initialSearchText)
        }
    }
}
