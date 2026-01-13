//
//  RemoteType.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-08-18.

//

import Foundation

enum RemoteType: String, Codable {
    case none = "None"
    case nightscout = "Nightscout"
    case trc = "Trio Remote Control"
    case sms // New case for SMS Remote Control
}
