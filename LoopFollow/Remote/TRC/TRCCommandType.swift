//
//  TRCCommandType.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-10-05.

//

import Foundation

enum TRCCommandType: String {
    case bolus = "bolus"
    case glucose = "glucose"
    case tempTarget = "temp_target"
    case cancelTempTarget = "cancel_temp_target"
    case meal = "meal"
    case deleteMeal = "deleteMeal"
    case deleteGlucose = "deleteGlucose"
    case combo = "combo"
    case startOverride = "start_override"
    case cancelOverride = "cancel_override"
}
