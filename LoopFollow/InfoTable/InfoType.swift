//
//  InfoType.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-07-11.

//

import Foundation

enum InfoType: Int, CaseIterable {
    case iob, cob, basal, override, battery, pump, sage, cage, recBolus, minMax, carbsToday, autosens, profile, target, isf, carbRatio, updated, tdd, iage, carbReq, af, smbRatio, pumpStatus, smbStatus, SMBUAMmin, autosensMinMax, maxSMB, overridePercentage, bgi, dev, totIob, btPing, btPingHealth, sensorStatus, sensorTrend, tirNeeded, dbSize, websocket, dexcomShareStatus

    var name: String {
        switch self {
        case .iob: return "IOB"
        case .cob: return "COB"
        case .basal: return "Basal"
        case .override: return "Override"
        case .battery: return "Trio batteri"
        case .pump: return "Reservoar"
        case .sage: return "Sensorbyte om"
        case .cage: return "Poddbyte om"
        case .recBolus: return "Behov insulin"
        case .minMax: return "BG min/max"
        case .carbsToday: return "Kh idag"
        case .autosens: return "Autosens"
        case .profile: return "Profil"
        case .target: return "Målvärde"
        case .isf: return "ISF"
        case .carbRatio: return "CR"
        case .updated: return "Trio status"
        case .tdd: return "Total daglig dos"
        case .iage: return "Insulinålder"
        case .carbReq: return "Behov kh"
        case .af: return "Justeringsfaktor"
        case .smbRatio: return "SMB ratio"
        case .pumpStatus: return "Poddstatus"
        case .smbStatus: return "SMB status"
        case .SMBUAMmin: return "SMB/UAM min"
        case .autosensMinMax: return "Autosens min/max"
        case .maxSMB: return "Max SMB"
        case .overridePercentage: return "Profil procent"
        case .bgi: return "BGI (5m)"
        case .dev: return "Dev (30m)"
        case .totIob: return "IOB + Basal IOB"
        case .btPing: return "BLE heartbeat"
        case .btPingHealth: return "Heartbeats idag"
        case .sensorStatus: return "Sensorstatus"
        case .sensorTrend: return "Sensortrend"
        case .tirNeeded: return "TIR kvar→mål"
        case .dbSize: return "Mongo DB"
        case .websocket: return "NS Websocket"
        case .dexcomShareStatus: return "Dexcom share"
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
