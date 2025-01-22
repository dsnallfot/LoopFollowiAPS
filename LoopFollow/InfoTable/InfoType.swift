//
//  InfoType.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-07-11.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import Foundation

enum InfoType: Int, CaseIterable {
    case iob, cob, basal, override, battery, pump, sage, cage, recBolus, minMax, carbsToday, autosens, profile, target, isf, carbRatio, updated, tdd, iage, carbReq

    var name: String {
        switch self {
        case .iob: return "IOB"
        case .cob: return "COB"
        case .basal: return "Basal"
        case .override: return "Override"
        case .battery: return "Trio Batteri"
        case .pump: return "Reservoar"
        case .sage: return "Sensorbyte om"
        case .cage: return "Poddbyte om"
        case .recBolus: return "Behov Insulin"
        case .minMax: return "Min/Max"
        case .carbsToday: return "Kh idag"
        case .autosens: return "Autosens"
        case .profile: return "Profil"
        case .target: return "Målvärde"
        case .isf: return "ISF"
        case .carbRatio: return "CR"
        case .updated: return "Info Uppdaterad"
        case .tdd: return "Total Daglig Dos"
        case .iage: return "Insulinålder"
        case .carbReq: return "Behov Kh"
        }
    }

    var defaultVisible: Bool {
        switch self {
        case .iob, .cob, .basal, .override, .battery, .pump, .sage, .cage, .recBolus, .minMax, .carbsToday, .carbReq:
            return true
        default:
            return false
        }
    }

    var sortOrder: Int {
        return self.rawValue
    }
}
