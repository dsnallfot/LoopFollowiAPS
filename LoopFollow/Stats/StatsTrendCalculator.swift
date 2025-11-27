//
//  StatsTrendCalculator.swift
//  LoopFollow


enum StatsTrendArrow: String {
case strongUp = "↑"
case up       = "↗"
case flat     = "→"
case down     = "↘"
case strongDown = "↓"
case none     = ""   // om previous saknas
}

struct StatsTrendCalculator {
static func arrow(current: Double?, previous: Double?) -> StatsTrendArrow {
    guard
        let current = current,
        let previous = previous,
        previous != 0
    else {
        return .none
    }

    let change = (current - previous) / abs(previous) * 100.0

    switch change {
    case let x where x > 50:  return .strongUp
    case let x where x > 20:  return .up
    case let x where x < -50: return .strongDown
    case let x where x < -20: return .down
    default:                  return .flat
    }
}
}
