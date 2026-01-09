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

    /// Shared gradient colors used across UIKit + SwiftUI.
    /// Optionally accepts an intensity multiplier for the alpha values (use >1.0 for stronger/darker gradients).
    static func themeGradientColors(intensity: CGFloat = 1.0) -> [CGColor] {
        // Clamp so we never exceed 1.0 alpha.
        func a(_ base: CGFloat) -> CGFloat { min(max(base * intensity, 0.0), 1.0) }
        return [
            UIColor.systemBlue.withAlphaComponent(a(0.15)).cgColor,
            UIColor.systemBlue.withAlphaComponent(a(0.25)).cgColor,
            UIColor.systemBlue.withAlphaComponent(a(0.15)).cgColor
        ]
    }

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

            let colors: [CGColor] = Self.themeGradientColors()

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
            view.backgroundColor = .systemBackground
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

            let colors: [CGColor] = ThemedViewController.themeGradientColors(intensity: 1.0)

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
            view.backgroundColor = .systemBackground

            // Light mode: keep form looking native. (You can switch to .clear later if you want.)
            tableView.backgroundColor = .systemBackground
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

// MARK: - Theming (UITableViewController)

/// Same theme logic as `ThemedViewController`, but adapted for `UITableViewController`.
/// Sets gradient in dark mode and `.systemBackground` in light mode.
class ThemedTableViewController: UITableViewController {

    private weak var gradientView: GradientView?

    override func viewDidLoad() {
        super.viewDidLoad()
        updateBackgroundForCurrentMode()
        // Ensure the root table view can actually show transparency.
        tableView.isOpaque = false
        tableView.backgroundView = nil
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Re-apply theme on appearance; grouped/insetGrouped tables may reset backgrounds.
        updateBackgroundForCurrentMode()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            updateBackgroundForCurrentMode()
        }
    }

    @objc func updateBackgroundForCurrentMode() {
        // Remove any existing gradient
        gradientView?.removeFromSuperview()
        gradientView = nil

        if traitCollection.userInterfaceStyle == .dark {
            // Use tableView.backgroundView for more reliable gradient placement (esp. insetGrouped)
            view.backgroundColor = .clear
            tableView.backgroundColor = .clear
            tableView.isOpaque = false
            tableView.layer.backgroundColor = UIColor.clear.cgColor

            let gv = GradientView(colors: ThemedViewController.themeGradientColors(intensity: 1.0))
            gv.frame = tableView.bounds
            gv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            gv.translatesAutoresizingMaskIntoConstraints = true

            // Put gradient behind all table content
            tableView.backgroundView = gv
            gradientView = gv
        } else {
            view.backgroundColor = .systemBackground
            tableView.backgroundColor = .systemBackground
            tableView.backgroundView = nil
            tableView.isOpaque = true
            tableView.layer.backgroundColor = UIColor.systemBackground.cgColor
            // Ensure gradientView is nil already (cleanup)
            gradientView = nil
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
                Color(UIColor.systemBackground)
            }
        }
        .ignoresSafeArea()
    }
}




// MARK: - UIPickerView Themed Gradient Helper

extension UIPickerView {

    private static let themedGradientTag = 998877
    private static let selectionHighlightTag = 998878

    /// UIPickerView is notoriously hard to make fully transparent (it has internal tinted/blur layers).
    /// This method "fakes" transparency by inserting the app's gradient behind the wheel *inside* the picker.
    /// Use `intensity` > 1.0 for modal sheets (pageSheet) since the system sheet background can lighten the result.
    /// Call after the picker is laid out (e.g. viewDidLayoutSubviews) for best effect.
    func applyThemedBackdrop(for style: UIUserInterfaceStyle, intensity: CGFloat = 1.0, showSelectionHighlight: Bool = true) {
        // Remove any previous themed views we inserted.
        subviews.first(where: { $0.tag == Self.themedGradientTag })?.removeFromSuperview()
        subviews.first(where: { $0.tag == Self.selectionHighlightTag })?.removeFromSuperview()

        guard style == .dark else {
            // Light mode: keep it clean and native-ish.
            backgroundColor = .systemBackground
            return
        }

        // Insert the same gradient used by the VC behind the wheel.
        let gv = GradientView(colors: ThemedViewController.themeGradientColors(intensity: intensity))
        gv.tag = Self.themedGradientTag
        gv.isUserInteractionEnabled = false
        gv.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(gv, at: 0)

        NSLayoutConstraint.activate([
            gv.leadingAnchor.constraint(equalTo: leadingAnchor),
            gv.trailingAnchor.constraint(equalTo: trailingAnchor),
            gv.topAnchor.constraint(equalTo: topAnchor),
            gv.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Optional selection highlight overlay (makes the selected row more obvious)
        if showSelectionHighlight {
            let highlight = UIView()
            highlight.tag = Self.selectionHighlightTag
            highlight.isUserInteractionEnabled = false
            highlight.translatesAutoresizingMaskIntoConstraints = false
            highlight.backgroundColor = UIColor.white.withAlphaComponent(0.05)
            highlight.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
            highlight.layer.borderWidth = 1
            highlight.layer.cornerRadius = 20
            highlight.layer.masksToBounds = true

            // Place above the gradient but below the wheel contents
            insertSubview(highlight, aboveSubview: gv)

            NSLayoutConstraint.activate([
                highlight.centerYAnchor.constraint(equalTo: centerYAnchor),
                highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                highlight.heightAnchor.constraint(equalToConstant: 40)
            ])
        }

        // Attempt to clear internal tinted layers as much as UIKit allows.
        isOpaque = false
        backgroundColor = .clear
        layer.backgroundColor = UIColor.clear.cgColor
        setValue(UIColor.clear, forKey: "backgroundColor")

        for v in subviews {
            // Keep our inserted views as-is
            guard v.tag != Self.themedGradientTag, v.tag != Self.selectionHighlightTag else { continue }
            v.isOpaque = false
            v.backgroundColor = .clear
            v.layer.backgroundColor = UIColor.clear.cgColor
            if let blur = v as? UIVisualEffectView { blur.effect = nil }
            if let tv = v as? UITableView {
                tv.backgroundColor = .clear
                tv.backgroundView = nil
                tv.separatorStyle = .none
            }
        }
    }
}

extension View {
    func themedCardBackground(opacity: CGFloat = 0.1) -> some View {
        self
            .background(
                Color(uiColor: .systemGray)
                    .opacity(opacity)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
