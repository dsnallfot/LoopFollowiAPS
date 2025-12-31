//
//  ThemedViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-12-31.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import SwiftUI
import UIKit
import Eureka

final class GradientView: UIView {
    private let gradientLayer = CAGradientLayer()

    init(colors: [CGColor]) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        gradientLayer.colors = colors
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.insertSublayer(gradientLayer, at: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
}

class ThemedViewController: UIViewController {

    private weak var gradientView: GradientView?

    override func viewDidLoad() {
        super.viewDidLoad()
        updateBackgroundForCurrentMode()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // Re-apply theme when switching light/dark
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            updateBackgroundForCurrentMode()
        }
    }

    /// Default theme: gradient in dark mode, solid systemGray6 in light mode.
    /// Subclasses can override if needed, but should call super.
    @objc func updateBackgroundForCurrentMode() {
        // Remove any existing gradient
        gradientView?.removeFromSuperview()
        gradientView = nil

        if traitCollection.userInterfaceStyle == .dark {
            view.backgroundColor = .systemBackground

            let colors: [CGColor] = [
                UIColor.systemBlue.withAlphaComponent(0.15).cgColor,
                UIColor.systemBlue.withAlphaComponent(0.25).cgColor,
                UIColor.systemBlue.withAlphaComponent(0.15).cgColor
            ]

            let gv = GradientView(colors: colors)
            gv.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(gv)
            view.sendSubviewToBack(gv)

            NSLayoutConstraint.activate([
                gv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                gv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                gv.topAnchor.constraint(equalTo: view.topAnchor),
                gv.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])

            gradientView = gv
        } else {
            view.backgroundColor = .systemGray6
        }
    }
}

// MARK: - Theming (Eureka)

/// Same theme logic as `ThemedViewController`, but adapted for Eureka's `FormViewController`.
class ThemedFormViewController: FormViewController {

    private weak var gradientView: GradientView?

    override func viewDidLoad() {
        super.viewDidLoad()
        applyTheme()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            applyTheme()
        }
    }

    @objc func applyTheme() {
        // Remove any existing gradient
        gradientView?.removeFromSuperview()
        gradientView = nil

        if traitCollection.userInterfaceStyle == .dark {
            view.backgroundColor = .systemBackground

            let colors: [CGColor] = [
                UIColor.systemBlue.withAlphaComponent(0.15).cgColor,
                UIColor.systemBlue.withAlphaComponent(0.25).cgColor,
                UIColor.systemBlue.withAlphaComponent(0.15).cgColor
            ]

            let gv = GradientView(colors: colors)
            gv.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(gv)
            view.sendSubviewToBack(gv)

            NSLayoutConstraint.activate([
                gv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                gv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                gv.topAnchor.constraint(equalTo: view.topAnchor),
                gv.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])

            gradientView = gv

            // Eureka forms are rendered in a table view; make it transparent so the gradient shows.
            tableView.backgroundColor = .clear
            tableView.backgroundView = nil
            
            // Make Eureka row cells transparent so the gradient shows through.
            // Limit via appearance(whenContainedInInstancesOf:) so only this VC hierarchy is affected.
            let cellAppearance = UITableViewCell.appearance(whenContainedInInstancesOf: [ThemedFormViewController.self])
            cellAppearance.backgroundColor = .clear

            let baseCellAppearance = BaseCell.appearance(whenContainedInInstancesOf: [ThemedFormViewController.self])
            baseCellAppearance.backgroundColor = .clear

            // Force already-created cells to redraw with the updated appearance.
            tableView.reloadData()
        } else {
            view.backgroundColor = .systemGray6

            // Light mode: keep form looking native. (You can switch to .clear later if you want.)
            tableView.backgroundColor = .systemGray6
            tableView.backgroundView = nil
            
            // Restore default-ish look in light mode.
            let cellAppearance = UITableViewCell.appearance(whenContainedInInstancesOf: [ThemedFormViewController.self])
            cellAppearance.backgroundColor = .systemBackground

            let baseCellAppearance = BaseCell.appearance(whenContainedInInstancesOf: [ThemedFormViewController.self])
            baseCellAppearance.backgroundColor = .systemBackground

            tableView.reloadData()
        }
    }
}

struct ThemeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(UIColor.systemBlue.withAlphaComponent(0.15)),
                        Color(UIColor.systemBlue.withAlphaComponent(0.25)),
                        Color(UIColor.systemBlue.withAlphaComponent(0.15))
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                Color(UIColor.systemGray6)
            }
        }
        .ignoresSafeArea()
    }
}


