//
//  PushMessage.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-08-27.

//

import Foundation

struct PushMessage: Encodable {
    struct APS: Encodable {
            let contentAvailable: Int = 1
            let interruptionLevel: String = "time-sensitive"
            let alert: String

            enum CodingKeys: String, CodingKey {
                case contentAvailable = "content-available"
                case interruptionLevel = "interruption-level"
                case alert
            }
        }

    let aps: APS
    var user: String
    var commandType: TRCCommandType
    var bolusAmount: Decimal?
    var glucose: Decimal?
    var target: Int?
    var duration: Int?
    var carbs: Int?
    var protein: Int?
    var fat: Int?
    var notes: String?
    var sharedSecret: String
    var timestamp: TimeInterval
    var overrideName: String?
    var scheduledTime: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case aps
        case user
        case commandType = "command_type"
        case bolusAmount = "bolus_amount"
        case glucose
        case target
        case duration
        case carbs
        case protein
        case fat
        case notes
        case sharedSecret = "shared_secret"
        case timestamp
        case overrideName
        case scheduledTime = "scheduled_time"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(aps, forKey: .aps)
        try container.encode(user, forKey: .user)
        try container.encode(commandType.rawValue, forKey: .commandType)
        try container.encode(bolusAmount, forKey: .bolusAmount)
        try container.encode(glucose, forKey: .glucose)
        try container.encode(target, forKey: .target)
        try container.encode(duration, forKey: .duration)
        try container.encode(carbs, forKey: .carbs)
        try container.encode(protein, forKey: .protein)
        try container.encode(fat, forKey: .fat)
        try container.encode(notes, forKey: .notes)
        try container.encode(sharedSecret, forKey: .sharedSecret)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(overrideName, forKey: .overrideName)
        if let scheduledTime = scheduledTime {
            try container.encode(scheduledTime, forKey: .scheduledTime)
        }
    }
}

