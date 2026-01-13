//
//  ObservableValue.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-07-25.

//

import Foundation
import Combine
import HealthKit
import SwiftUI

class ObservableValue<T>: ObservableObject {
    @Published var value: T

    init(default: T) {
        self.value = `default`
    }

    func set(_ newValue: T) {
        LogManager.shared.log(category: .general, message: "Setting new observable value: \(newValue)", isDebug: true)
        DispatchQueue.main.async {
            self.value = newValue
        }
    }
}
