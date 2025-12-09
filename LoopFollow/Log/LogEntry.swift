//
//  LogEntry.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-13.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import Foundation

struct LogEntry: Identifiable {
/// Stabilt ID baserat på radens index i loggfilen (från början av filen).
/// Äldre rader får lägre index, nyare får högre. Detta ändras inte mellan
/// omladdningar så länge filen bara får nya rader appended.
let id: Int
let text: String
}
