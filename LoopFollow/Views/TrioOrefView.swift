//
//  TrioOrefView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-04-08.

//

import SwiftUI
import UIKit
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
            sb.searchTextField.backgroundColor = UIColor.systemGray.withAlphaComponent(0.15)
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
struct TrioOrefView: View {
    @ObservedObject var viewModel = TrioOrefViewModel()
    @State private var searchText: String = ""

    var filteredEntries: [Oref2Entry] {
        if searchText.isEmpty {
            return viewModel.orefEntries
        } else {
            return viewModel.orefEntries.filter {
                $0.key.localizedCaseInsensitiveContains(searchText) ||
                $0.value.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                PinnedSearchBar(text: $searchText, placeholder: "Sök Oref-variabler...")

                List(filteredEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.key)
                            .font(.headline)
                        Text(entry.value)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .navigationTitle(viewModel.formattedTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
