//
//  RemoteViewController.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-07-19.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import Foundation
import UIKit
import SwiftUI
import HealthKit
import Combine

class RemoteViewController: UIViewController {

    private var cancellable: AnyCancellable?
    private var hostingController: UIHostingController<AnyView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        cancellable = Storage.shared.remoteType.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateView()
                }
            }

        updateView()
    }

    private func updateView() {
        let remoteType = Storage.shared.remoteType.value

        // Remove existing hosting controller if present
        if let existingHostingController = hostingController {
            existingHostingController.willMove(toParent: nil)
            existingHostingController.view.removeFromSuperview()
            existingHostingController.removeFromParent()
            hostingController = nil
        }

        // Remove existing child view controllers if present
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }

        // Load the new remote type view
        if remoteType == .nightscout {
            let remoteView = TrioNightscoutRemoteView()
            hostingController = UIHostingController(rootView: AnyView(remoteView))
            if let hostingController = hostingController {
                addChild(hostingController)
                view.addSubview(hostingController.view)
                hostingController.view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
                    hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
                ])
                hostingController.didMove(toParent: self)
            }
        } else if remoteType == .trc {
            let trioRemoteControlViewModel = TrioRemoteControlViewModel()
            let trioRemoteControlView = TrioRemoteControlView(viewModel: trioRemoteControlViewModel)
            hostingController = UIHostingController(rootView: AnyView(trioRemoteControlView))
            if let hostingController = hostingController {
                addChild(hostingController)
                view.addSubview(hostingController.view)
                hostingController.view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
                    hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
                ])
                hostingController.didMove(toParent: self)
            }
        } else if remoteType == .sms {
            // Load SMSRemoteViewController
            let storyboard = UIStoryboard(name: "Main", bundle: nil) // Replace "Main" with your storyboard name
            guard let smsRemoteVC = storyboard.instantiateViewController(withIdentifier: "SMSRemoteViewController") as? SMSRemoteViewController else {
                LogManager.shared.log(category: .remote, message: "Error: SMSRemoteViewController could not be instantiated.", isDebug: true)
                return
            }

            // Add as child view controller
            addChild(smsRemoteVC)
            view.addSubview(smsRemoteVC.view)
            smsRemoteVC.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                smsRemoteVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                smsRemoteVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                smsRemoteVC.view.topAnchor.constraint(equalTo: view.topAnchor),
                smsRemoteVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            smsRemoteVC.didMove(toParent: self)
        } else {
            // Default case
            hostingController = UIHostingController(rootView: AnyView(Text("Please select a Remote Type in Settings.")))
            if let hostingController = hostingController {
                addChild(hostingController)
                view.addSubview(hostingController.view)
                hostingController.view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
                    hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
                ])
                hostingController.didMove(toParent: self)
            }
        }
    }
    
    deinit {
        cancellable?.cancel()
    }
}
