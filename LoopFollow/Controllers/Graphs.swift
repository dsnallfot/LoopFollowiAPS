//
//  Graphs.swift
//  LoopFollow
//
//  Created by Jon Fawcett on 6/16/20.
//  Copyright © 2020 Jon Fawcett. All rights reserved.
//

import Foundation
import Charts
import UIKit

import Charts

enum GraphDataIndex: Int {
    case bg = 0
    case prediction = 1
    case basal = 2
    case bolus = 3
    case carbs = 4
    case basalScheduled = 5
    case override = 6
    case bgCheck = 7
    case suspend = 8
    case resumePump = 9
    case sensorStart = 10
    case note = 11
    case ztPrediction = 12
    case iobPrediction = 13
    case cobPrediction = 14
    case uamPrediction = 15
    case smb = 16
    case tempTarget = 17
    case pump = 18
    case training = 19
    case warningEvent = 20
}

extension GraphDataIndex {
    var description: String {
        switch self {
        case .bg: return "BG"
        case .prediction: return "Prediction"
        case .basal: return "Basal"
        case .bolus: return "Bolus"
        case .carbs: return "Carbs"
        case .basalScheduled: return "Basal Scheduled"
        case .override: return "Override"
        case .bgCheck: return "BG Check"
        case .suspend: return "Suspend"
        case .resumePump: return "Resume Pump"
        case .sensorStart: return "Sensor Start"
        case .note: return "Note"
        case .ztPrediction: return "ZT Prediction"
        case .iobPrediction: return "IOB Prediction"
        case .cobPrediction: return "COB Prediction"
        case .uamPrediction: return "UAM Prediction"
        case .smb: return "SMB"
        case .tempTarget: return "Temp Target"
        case .pump: return "Pump Change"
        case .training: return "Träning"
        case .warningEvent: return "Varning"
        }
    }
}

class CompositeRenderer: LineChartRenderer {
    let tempTargetRenderer: TempTargetRenderer
    let triangleRenderer: TriangleRenderer
    let bgCheckRenderer: BGCheckRenderer
    let inRangeBandRenderer: InRangeBandRenderer
    let trainingSessionRenderer: TrainingSessionRenderer

    init(
        dataProvider: LineChartDataProvider?,
        animator: Animator?,
        viewPortHandler: ViewPortHandler?,
        tempTargetDataSetIndex: Int,
        warningDataSetIndex: Int,
        bgCheckDataSetIndex: Int,
        trainingDataSetIndex: Int
    ) {
        // Säkerställ att Charts alltid får giltiga objekt
        let provider = dataProvider!
        let animator = animator!
        let viewPortHandler = viewPortHandler!

        self.tempTargetRenderer = TempTargetRenderer(
            dataProvider: provider,
            animator: animator,
            viewPortHandler: viewPortHandler,
            tempTargetDataSetIndex: tempTargetDataSetIndex
        )

        self.triangleRenderer = TriangleRenderer(
            dataProvider: provider,
            animator: animator,
            viewPortHandler: viewPortHandler,
            warningDataSetIndex: warningDataSetIndex
        )

        self.bgCheckRenderer = BGCheckRenderer(
            dataProvider: provider,
            animator: animator,
            viewPortHandler: viewPortHandler,
            bgCheckDataSetIndex: bgCheckDataSetIndex
        )
        
        self.trainingSessionRenderer = TrainingSessionRenderer(
            dataProvider: provider,
            animator: animator,
            viewPortHandler: viewPortHandler,
            trainingDataSetIndex: trainingDataSetIndex
        )

        self.inRangeBandRenderer = InRangeBandRenderer(
            dataProvider: provider,
            animator: animator,
            viewPortHandler: viewPortHandler
        )

        super.init(
            dataProvider: provider,
            animator: animator,
            viewPortHandler: viewPortHandler
        )
    }

    override func drawExtras(context: CGContext) {
        super.drawExtras(context: context)
        inRangeBandRenderer.drawExtras(context: context)
        tempTargetRenderer.drawExtras(context: context)
        bgCheckRenderer.drawExtras(context: context)
        trainingSessionRenderer.drawExtras(context: context)
        // Daniel: Do not draw those triangles for smbs //
        triangleRenderer.drawExtras(context: context)
    }
}

class TriangleRenderer: LineChartRenderer {
    let warningDataSetIndex: Int
    
    init(dataProvider: LineChartDataProvider?, animator: Animator?, viewPortHandler: ViewPortHandler?, warningDataSetIndex: Int) {
        self.warningDataSetIndex = warningDataSetIndex
        super.init(dataProvider: dataProvider!, animator: animator!, viewPortHandler: viewPortHandler!)
    }
    
    override func drawExtras(context: CGContext) {
        super.drawExtras(context: context)
        
        guard let dataProvider = dataProvider else { return }
        
        if dataProvider.lineData?.dataSets.count ?? 0 > warningDataSetIndex, let lineDataSet = dataProvider.lineData?.dataSets[warningDataSetIndex] as? LineChartDataSet {
            let trans = dataProvider.getTransformer(forAxis: lineDataSet.axisDependency)
            let phaseY = animator.phaseY
            
            for j in 0 ..< lineDataSet.entryCount {
                guard let e = lineDataSet.entryForIndex(j) else { continue }
                
                let pt = trans.pixelForValues(x: e.x, y: e.y * phaseY)
                
                context.saveGState()
                context.beginPath()
                context.move(to: CGPoint(x: pt.x, y: pt.y - 6))
                context.addLine(to: CGPoint(x: pt.x - 6, y: pt.y + 6))
                context.addLine(to: CGPoint(x: pt.x + 6, y: pt.y + 6))
                context.closePath()
                
                context.setFillColor(lineDataSet.circleColors.first!.cgColor)
                context.fillPath()
                
                context.restoreGState()
            }
        }
    }
}

class TempTargetChartDataEntry: ChartDataEntry {
    var xStart: Double = 0.0
    var xEnd: Double = 0.0
    var yTop: Double = 0.0
    var yBottom: Double = 0.0

    required init() {
        super.init()
    }

    init(xStart: Double, xEnd: Double, yTop: Double, yBottom: Double, data: Any?) {
        self.xStart = xStart
        self.xEnd = xEnd
        self.yTop = yTop
        self.yBottom = yBottom

        super.init(x: xStart, y: yTop)
        self.data = data
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = TempTargetChartDataEntry(
            xStart: xStart,
            xEnd: xEnd,
            yTop: yTop,
            yBottom: yBottom,
            data: data
        )
        return copy
    }
}

class BGCheckLineChartDataEntry: ChartDataEntry {
    var xStart: Double = 0.0
    var xEnd: Double = 0.0

    required init() { super.init() }

    init(xStart: Double, xEnd: Double, y: Double, data: Any?) {
        self.xStart = xStart
        self.xEnd = xEnd
        super.init(x: xStart, y: y)
        self.data = data
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        BGCheckLineChartDataEntry(xStart: xStart, xEnd: xEnd, y: y, data: data)
    }
}

class TrainingSessionChartDataEntry: ChartDataEntry {
    var xStart: Double = 0.0
    var xEnd: Double = 0.0

    required init() { super.init() }

    init(xStart: Double, xEnd: Double, y: Double, data: Any?) {
        self.xStart = xStart
        self.xEnd = xEnd
        super.init(x: xStart, y: y)
        self.data = data
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        TrainingSessionChartDataEntry(xStart: xStart, xEnd: xEnd, y: y, data: data)
    }
}

class TempTargetRenderer: LineChartRenderer {
    let tempTargetDataSetIndex: Int

    init(dataProvider: LineChartDataProvider?, animator: Animator?, viewPortHandler: ViewPortHandler?, tempTargetDataSetIndex: Int) {
        self.tempTargetDataSetIndex = tempTargetDataSetIndex
        super.init(dataProvider: dataProvider!, animator: animator!, viewPortHandler: viewPortHandler!)
    }

    override func drawExtras(context: CGContext) {
        super.drawExtras(context: context)

        guard let dataProvider = dataProvider else { return }

        if dataProvider.lineData?.dataSets.count ?? 0 > tempTargetDataSetIndex,
           let lineDataSet = dataProvider.lineData?.dataSets[tempTargetDataSetIndex] as? LineChartDataSet {

            let trans = dataProvider.getTransformer(forAxis: lineDataSet.axisDependency)
            let phaseY = animator.phaseY

            for i in 0 ..< lineDataSet.entryCount {
                guard let entry = lineDataSet.entryForIndex(i) as? TempTargetChartDataEntry else { continue }

                let xStart = entry.xStart
                let xEnd = entry.xEnd
                let yTop = entry.yTop * phaseY
                let yBottom = entry.yBottom * phaseY

                let leftTop = trans.pixelForValues(x: xStart, y: yTop)
                let rightBottom = trans.pixelForValues(x: xEnd, y: yBottom)

                var rect = CGRect(x: leftTop.x, y: leftTop.y, width: rightBottom.x - leftTop.x, height: rightBottom.y - leftTop.y)
                if rect.width < 0 {
                    rect.origin.x += rect.width
                    rect.size.width = abs(rect.width)
                }
                if rect.height < 0 {
                    rect.origin.y += rect.height
                    rect.size.height = abs(rect.height)
                }

                context.saveGState()
                context.setFillColor(NSUIColor.systemPurple.withAlphaComponent(0.5).cgColor)
                context.fill(rect)
                context.restoreGState()
            }
        }
    }
}

class InRangeBandRenderer: LineChartRenderer {

    override func drawExtras(context: CGContext) {
        super.drawExtras(context: context)

        guard let dataProvider = dataProvider else { return }

        // In-range-gränser i *data*-värden (mg/dL eller mmol*18)
        let yLow = Double(UserDefaultsRepository.lowLine.value)
        let yHigh = Double(UserDefaultsRepository.highLine.value)

        // Om de av någon anledning är fel, rita inget
        guard yHigh > yLow else { return }

        // Vi utgår från högra Y-axeln, där BG ligger
        let trans = dataProvider.getTransformer(forAxis: .right)

        // Använd det synliga X-intervallet så bandet följer zoom/scroll
        let xMin = dataProvider.lowestVisibleX
        let xMax = dataProvider.highestVisibleX

        let leftTop = trans.pixelForValues(x: xMin, y: yHigh)
        let rightBottom = trans.pixelForValues(x: xMax, y: yLow)

        var rect = CGRect(
            x: leftTop.x,
            y: leftTop.y,
            width: rightBottom.x - leftTop.x,
            height: rightBottom.y - leftTop.y
        )

        // Normalisera ifall något blir negativt
        if rect.width < 0 {
            rect.origin.x += rect.width
            rect.size.width = -rect.width
        }
        if rect.height < 0 {
            rect.origin.y += rect.height
            rect.size.height = -rect.height
        }

        context.saveGState()
        context.setFillColor(UIColor.systemGreen.withAlphaComponent(0.1).cgColor)
        context.fill(rect)
        context.restoreGState()
    }
}

class BGCheckRenderer: LineChartRenderer {
    let bgCheckDataSetIndex: Int

    init(dataProvider: LineChartDataProvider?, animator: Animator?, viewPortHandler: ViewPortHandler?, bgCheckDataSetIndex: Int) {
        self.bgCheckDataSetIndex = bgCheckDataSetIndex
        super.init(dataProvider: dataProvider!, animator: animator!, viewPortHandler: viewPortHandler!)
    }

    override func drawExtras(context: CGContext) {
        super.drawExtras(context: context)

        guard let dataProvider = dataProvider else { return }
        guard (dataProvider.lineData?.dataSets.count ?? 0) > bgCheckDataSetIndex,
              let dataSet = dataProvider.lineData?.dataSets[bgCheckDataSetIndex] as? LineChartDataSet else { return }

        let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
        let phaseY = animator.phaseY

        let strokeUIColor: UIColor = dataSet.colors.first ?? .systemRed

        context.saveGState()
        context.setLineCap(.round)

        let dotAlpha: CGFloat = 1.0
        let tailAlpha: CGFloat = 0.7
        let lineWidth: CGFloat = 6  // “elongated dot”-känsla
        let dotRadius: CGFloat = 5.5

        for i in 0 ..< dataSet.entryCount {
            guard let entry = dataSet.entryForIndex(i) as? BGCheckLineChartDataEntry else { continue }

            let yVal = entry.y * phaseY
            let p1 = trans.pixelForValues(x: entry.xStart, y: yVal)
            let p2 = trans.pixelForValues(x: entry.xEnd, y: yVal)

            // Skip if completely outside viewport
            if (p1.x < viewPortHandler.contentLeft && p2.x < viewPortHandler.contentLeft) ||
               (p1.x > viewPortHandler.contentRight && p2.x > viewPortHandler.contentRight) {
                continue
            }

            // 1) Solid start dot
            context.setAlpha(dotAlpha)
            context.setFillColor(strokeUIColor.withAlphaComponent(dotAlpha).cgColor)
            let dotRect = CGRect(x: p1.x - dotRadius, y: p1.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
            context.fillEllipse(in: dotRect)

            // 2) Faded tail segment
            context.setAlpha(tailAlpha)
            context.setStrokeColor(strokeUIColor.withAlphaComponent(tailAlpha).cgColor)
            context.setLineWidth(lineWidth)

            context.beginPath()
            context.move(to: p1)
            context.addLine(to: p2)
            context.strokePath()
        }

        context.restoreGState()
    }
}

class TrainingSessionRenderer: LineChartRenderer {
    let trainingDataSetIndex: Int

    init(dataProvider: LineChartDataProvider?, animator: Animator?, viewPortHandler: ViewPortHandler?, trainingDataSetIndex: Int) {
        self.trainingDataSetIndex = trainingDataSetIndex
        super.init(dataProvider: dataProvider!, animator: animator!, viewPortHandler: viewPortHandler!)
    }

    override func drawExtras(context: CGContext) {
        super.drawExtras(context: context)

        guard let dataProvider = dataProvider else { return }
        guard (dataProvider.lineData?.dataSets.count ?? 0) > trainingDataSetIndex,
              let dataSet = dataProvider.lineData?.dataSets[trainingDataSetIndex] as? LineChartDataSet else { return }

        let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
        let phaseY = animator.phaseY

        context.saveGState()
        context.setLineCap(.round)
        context.setStrokeColor(UIColor.systemGreen.withAlphaComponent(0.65).cgColor)
        context.setLineWidth(10)

        for i in 0 ..< dataSet.entryCount {
            guard let entry = dataSet.entryForIndex(i) as? TrainingSessionChartDataEntry else { continue }

            let yVal = entry.y * phaseY
            let p1 = trans.pixelForValues(x: entry.xStart, y: yVal)
            let p2 = trans.pixelForValues(x: entry.xEnd, y: yVal)

            // Skip om helt utanför viewport
            if (p1.x < viewPortHandler.contentLeft && p2.x < viewPortHandler.contentLeft) ||
               (p1.x > viewPortHandler.contentRight && p2.x > viewPortHandler.contentRight) {
                continue
            }

            context.beginPath()
            context.move(to: p1)
            context.addLine(to: p2)
            context.strokePath()
        }

        context.restoreGState()
    }
}

let ScaleXMax:Float = 150.0
extension MainViewController {
    func updateChartRenderers() {
        let tempTargetDataIndex = GraphDataIndex.tempTarget.rawValue
        let warningDataIndex = GraphDataIndex.warningEvent.rawValue
        let bgCheckDataIndex = GraphDataIndex.bgCheck.rawValue
        let trainingDataIndex = GraphDataIndex.training.rawValue

        let compositeRenderer = CompositeRenderer(
            dataProvider: BGChart,
            animator: BGChart.chartAnimator,
            viewPortHandler: BGChart.viewPortHandler,
            tempTargetDataSetIndex: tempTargetDataIndex,
            warningDataSetIndex: warningDataIndex,
            bgCheckDataSetIndex: bgCheckDataIndex,
            trainingDataSetIndex: trainingDataIndex
        )
        BGChart.renderer = compositeRenderer

        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
    }
    /*
    func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
        if chartView == BGChartFull {
            BGChart.moveViewToX(entry.x)
        }
        if entry.data as? String == "hide"{
            BGChart.highlightValue(nil, callDelegate: false)
        }
        
    }*/
    
    // MARK: - Meal Analysis helpers for graph taps

    enum MealAnalysisSource {
        case override
        case meal
        case bgCheck
        case pumpChange
        case sensorChange
        case lowTreatment
    }

    /// Bygger ett minimalt events-array för MealAnalysisView baserat på de
    /// inlästa graf-dataseten (SMB, Bolus, Kolhydrater, BG Check + Temp Basal).
    func buildEventsForMealAnalysis() -> [Event] {
        var events: [Event] = []

        // Poddbyten
        for pumpChange in pumpChangeGraphData {
            var seconds = Double(pumpChange.date)

            // Heuristik: om värdet ser ut som millisekunder (större än ~år 2286 i sekunder),
            // dela med 1000.
            if seconds > 10_000_000_000 {
                seconds = seconds / 1000.0
            }

            let date = Date(timeIntervalSince1970: seconds)

            events.append(
                Event(
                    date: date,
                    eventType: "Site Change",
                    amount: 0.0,
                    foodType: nil
                )
            )
        }
        
        // SMB events (auto micro-boluser)
        for smb in smbData {
            let date = Date(timeIntervalSince1970: Double(smb.date))
            let amount = smb.value
            events.append(
                Event(
                    date: date,
                    eventType: "SMB",
                    amount: amount,
                    foodType: nil
                )
            )
        }

        // Manuella boluser
        for bolus in bolusData {
            let date = Date(timeIntervalSince1970: Double(bolus.date))
            let amount = bolus.value
            events.append(
                Event(
                    date: date,
                    eventType: "Bolus",
                    amount: amount,
                    foodType: nil
                )
            )
        }

        // Kolhydrater / måltider – vi mappar till samma eventType som i TreatmentsTableView
        for carb in carbData {
            let date = Date(timeIntervalSince1970: Double(carb.date))
            let amount = carb.value

            let rawFood = carb.foodType ?? ""
            let foodType = rawFood.isEmpty ? nil : rawFood

            events.append(
                Event(
                    date: date,
                    eventType: "Carb Correction",
                    amount: amount,
                    foodType: foodType
                )
            )
        }

        // BG Check (fingerstick). Approximerar mmol baserat på användarens enheter.
        for check in bgCheckData {
            let date = Date(timeIntervalSince1970: Double(check.date))
            let raw = Double(check.sgv)
            let mmol: Double
            if UserDefaultsRepository.units.value == "mmol/L" {
                // I mmol-läge antar vi att sgv redan är mmol.
                mmol = raw
            } else {
                // I mg/dL-läge: konvertera till mmol.
                mmol = raw / 18.0
            }

            events.append(
                Event(
                    date: date,
                    eventType: "BG Check",
                    amount: mmol,
                    foodType: nil
                )
            )
        }

        // Temp Basal → använd samma källa som du använder för temp basal-pulserna.
        // Byt `tempBasalGraphData` och fälten nedan till dina faktiska namn
        // (t.ex. `tempBasalData`, `tempBasalPulses`, `rate`/`absolute` etc).
        for temp in basalData {
            let date = Date(timeIntervalSince1970: Double(temp.date))

            let rate = temp.basalRate

            events.append(
                Event(
                    date: date,
                    eventType: "Temp Basal",
                    amount: rate,
                    foodType: nil
                )
            )
        }

        // Sortera kronologiskt för säkerhets skull
        events.sort { $0.date < $1.date }
        return events
    }

    /// Öppnar MealAnalysisView i en formSheet med given starttid och källa.
    func presentMealAnalysis(for start: Date, source: MealAnalysisSource) {
        let events = buildEventsForMealAnalysis()

        let title: String
        let end: Date // Finns tillgängligt som option ifall man vill styra sluttid för ngt specifikt event
        let adjustedStart: Date
        let segment: Int?
        switch source {
        case .override:
            title = "Analys override"
            adjustedStart = start - 30
            end = adjustedStart + 60 * 180
            segment = 2
        case .meal:
            title = "Analys måltid"
            adjustedStart = start - 30
            end = adjustedStart + 60 * 180
            segment = 2
        case .bgCheck:
            title = "Analys stick"
            adjustedStart = start - 60 * 20
            end = adjustedStart + 60 * 180
            segment = 2
        case .pumpChange:
            title = "Analys podd"
            adjustedStart = start - 60 * 180
            end = start + 60 * 180
            segment = 3
        case .sensorChange:
            title = "Analys sensor"
            adjustedStart = start - 30
            end = adjustedStart + 60 * 360
            segment = 3
        case .lowTreatment:
            title = "Analys dextro"
            adjustedStart = start - 60 * 20
            end = adjustedStart + 60 * 180
            segment = 2
        }

        let analysisVC = MealAnalysisView(
            events: events,
            initialStart: adjustedStart,
            initialEnd: end,
            modalWithTimestamp: true,
            modalTitleString: title,
            preSelectedSegment: segment
        )
        let nav = UINavigationController(rootViewController: analysisVC)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true, completion: nil)
    }
    
    func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
        // 1. Om man klickar i den lilla grafen → skrolla den stora grafen till samma X
        if chartView == BGChartFull {
            BGChart.moveViewToX(entry.x)
        }

        // 2. "hide"-punkter används bara för att rensa highlight, inget popup-fönster här.
        if let dataString = entry.data as? String, dataString == "hide" {
            BGChart.highlightValue(nil, callDelegate: false)
            return
        }

        // 3. BG-linjen i huvudgrafen → Trio-besluts-popup (utan ordinarie marker-popup)
        if chartView == BGChart, highlight.dataSetIndex == GraphDataIndex.bg.rawValue {
            // Ta bort highlight/marker direkt så att standard-pill-popup inte visas.
            BGChart.highlightValue(nil, callDelegate: false)
            BGChartFull.highlightValue(nil, callDelegate: false)

            showTrioDecisionAlert(for: entry.x)
            return
        }

        // 4. För övriga punkter (bolus/kolhydrater/fingerstick/pumpbyte) vill vi öppna MealAnalysisView.
        guard chartView == BGChart || chartView == BGChartFull else { return }
        guard let dataString = entry.data as? String else { return }

        let analysisStart = Date(timeIntervalSince1970: entry.x)
        let analysisStartOffset = Date(timeIntervalSince1970: entry.x) - 60 * 20 //visa vad som hände 20 min före sticket och tiden framåt

        // Fingerstick / BG Check (updateBGCheckGraph använder "Fingerstick\n...")
        if dataString.contains("Fingerstick") {
            presentMealAnalysis(for: analysisStartOffset, source: .bgCheck)
            return
        }

        // Pumpbyte (updatePumpChange använder line1: "Pumpbyte")
        if dataString.contains("Pumpbyte") {
            // Ta bort highlight/marker direkt så att standard-pill-popup inte visas.
            BGChart.highlightValue(nil, callDelegate: false)
            BGChartFull.highlightValue(nil, callDelegate: false)
            presentMealAnalysis(for: analysisStart, source: .pumpChange)
            return
        }
        
        // Sensorbyte (updatePumpChange använder line1: "Pumpbyte")
        if dataString.contains("Sensorbyte") {
            // Ta bort highlight/marker direkt så att standard-pill-popup inte visas.
            BGChart.highlightValue(nil, callDelegate: false)
            BGChartFull.highlightValue(nil, callDelegate: false)
            presentMealAnalysis(for: analysisStart, source: .sensorChange)
            return
        }

        // Dextro / lågbehandling – identifieras via 🍬 i måltidstexten.
        if dataString.contains("🍬") {
            BGChart.highlightValue(nil, callDelegate: false)
            BGChartFull.highlightValue(nil, callDelegate: false)
            presentMealAnalysis(for: analysisStart, source: .lowTreatment)
            return
        }

        // Måltid / kolhydrater – uppfångas via texten vi satte i updateCarbGraph
        // ("Kolhydrater ...", eller "Fett/Protein ...").
        if dataString.contains("Kolhydrater") || dataString.contains("Fett/Protein") {
            // Ta bort highlight/marker direkt så att standard-pill-popup inte visas.
            BGChart.highlightValue(nil, callDelegate: false)
            BGChartFull.highlightValue(nil, callDelegate: false)
            presentMealAnalysis(for: analysisStart, source: .meal)
            return
        }

        // Override
        if dataString.contains("Varaktighet") {
            presentMealAnalysis(for: analysisStart, source: .override)
            return
        }
    }
    
    func chartScaled(_ chartView: ChartViewBase, scaleX: CGFloat, scaleY: CGFloat) {
        // dont store huge values
        var scale: Float = Float(BGChart.scaleX)
        if(scale > ScaleXMax ) {
            scale = ScaleXMax
        }
        UserDefaultsRepository.chartScaleX.value = Float(scale)
    }
    
    private func makeTrainingSessionEntries(from entries: [DataStructs.noteStruct]) -> [TrainingSessionChartDataEntry] {
        guard !entries.isEmpty else { return [] }

        let sortedEntries = entries.sorted { $0.date < $1.date }

        let defaultSessionLength: Double = 6 * 60 * 60
        let overlayY = sortedEntries.map { Double($0.sgv) }.min() ?? 18.0

        var result: [TrainingSessionChartDataEntry] = []
        var currentStart: DataStructs.noteStruct?
        var currentSessionLine2: String?

        for entry in sortedEntries {
            let note = entry.note.lowercased()

            if note.contains("meta quest spel startades") {
                currentStart = entry
                currentSessionLine2 = "Meta Quest-spelsession"
                continue
            }

            if note.contains("träning startades") {
                currentStart = entry
                currentSessionLine2 = "Övrig träning"
                continue
            }

            if note.contains("meta quest spel avslutades"),
               let start = currentStart,
               let line2 = currentSessionLine2,
               line2 == "Meta Quest-spelsession",
               entry.date >= start.date {

                result.append(
                    TrainingSessionChartDataEntry(
                        xStart: start.date,
                        xEnd: entry.date,
                        y: overlayY,
                        data: formatPillTextExtraLine(
                            line1: "Träning",
                            line2: line2,
                            time: start.date
                        )
                    )
                )

                currentStart = nil
                currentSessionLine2 = nil
            }

            if note.contains("träning avslutades"),
               let start = currentStart,
               let line2 = currentSessionLine2,
               line2 == "Övrig träning",
               entry.date >= start.date {

                result.append(
                    TrainingSessionChartDataEntry(
                        xStart: start.date,
                        xEnd: entry.date,
                        y: overlayY,
                        data: formatPillTextExtraLine(
                            line1: "Träning",
                            line2: line2,
                            time: start.date
                        )
                    )
                )

                currentStart = nil
                currentSessionLine2 = nil
            }
        }

        // Pågående session: rita 6h framåt från senaste start
        if let start = currentStart, let line2 = currentSessionLine2 {
            result.append(
                TrainingSessionChartDataEntry(
                    xStart: start.date,
                    xEnd: start.date + defaultSessionLength,
                    y: overlayY,
                    data: formatPillTextExtraLine(
                        line1: "Träning pågår",
                        line2: line2,
                        time: start.date
                    )
                )
            )
        }

        return result
    }
    
// Daniel: Test even mmol yaxis tick marks
    func createGraph(){
        // Create the BG Graph Data
        let bgChartEntry = [ChartDataEntry]()
        let maxBG: Float = UserDefaultsRepository.minBGScale.value
        
        // Setup BG line details
        let lineBG = LineChartDataSet(entries:bgChartEntry, label: "")
        lineBG.circleRadius = CGFloat(globalVariables.dotBG)
        lineBG.circleColors = [NSUIColor.systemGreen]
        lineBG.drawCircleHoleEnabled = false
        lineBG.axisDependency = YAxis.AxisDependency.right
        lineBG.highlightEnabled = true
        lineBG.drawValuesEnabled = false
        
        if UserDefaultsRepository.showLines.value {
            lineBG.lineWidth = 2.5//2
        } else {
            lineBG.lineWidth = 0
        }
        if UserDefaultsRepository.showDots.value {
            lineBG.drawCirclesEnabled = true
        } else {
            lineBG.drawCirclesEnabled = false
        }
        lineBG.setDrawHighlightIndicators(false)
        lineBG.valueFont.withSize(50)
        
        // Setup Prediction line details
        let predictionChartEntry = [ChartDataEntry]()
        let linePrediction = LineChartDataSet(entries:predictionChartEntry, label: "")
        linePrediction.circleRadius = CGFloat(globalVariables.dotBG)
        linePrediction.circleColors = [NSUIColor.systemPurple]
        linePrediction.colors = [NSUIColor.systemPurple]
        linePrediction.drawCircleHoleEnabled = false
        linePrediction.axisDependency = YAxis.AxisDependency.right
        linePrediction.highlightEnabled = true
        linePrediction.drawValuesEnabled = false
        
        if UserDefaultsRepository.showLines.value {
            linePrediction.lineWidth = 0//2
        } else {
            linePrediction.lineWidth = 0
        }
        if UserDefaultsRepository.showDots.value {
            linePrediction.drawCirclesEnabled = true
        } else {
            linePrediction.drawCirclesEnabled = false
        }
        linePrediction.setDrawHighlightIndicators(false)
        linePrediction.valueFont.withSize(50)
        
        // create Basal graph data
        let chartEntry = [ChartDataEntry]()
        let maxBasal = UserDefaultsRepository.minBasalScale.value
        let lineBasal = LineChartDataSet(entries:chartEntry, label: "")
        lineBasal.setDrawHighlightIndicators(false)
        lineBasal.setColor(NSUIColor.systemBlue, alpha: 0.3)
        lineBasal.lineWidth = 0
        lineBasal.drawFilledEnabled = true
        lineBasal.fillColor = NSUIColor.systemBlue
        lineBasal.fillAlpha = 0.3
        lineBasal.drawCirclesEnabled = false
        lineBasal.axisDependency = YAxis.AxisDependency.left
        lineBasal.highlightEnabled = true
        lineBasal.drawValuesEnabled = false
        lineBasal.fillFormatter = basalFillFormatter()
        
        // Boluses
        let chartEntryBolus = [ChartDataEntry]()
        let lineBolus = LineChartDataSet(entries:chartEntryBolus, label: "")
        lineBolus.circleRadius = CGFloat(globalVariables.dotBolus)
        lineBolus.circleColors = [NSUIColor.systemBlue.withAlphaComponent(0.75)]
        lineBolus.drawCircleHoleEnabled = false
        lineBolus.setDrawHighlightIndicators(false)
        lineBolus.setColor(NSUIColor.systemBlue, alpha: 1.0)
        lineBolus.lineWidth = 0
        lineBolus.axisDependency = YAxis.AxisDependency.right
        lineBolus.valueFormatter = ChartYDataValueFormatter()
        lineBolus.valueTextColor = NSUIColor.label
        lineBolus.fillColor = NSUIColor.systemBlue
        lineBolus.fillAlpha = 0.6
        
            lineBolus.drawCirclesEnabled = true
            lineBolus.drawFilledEnabled = false
        
        if UserDefaultsRepository.showValues.value  {
            lineBolus.drawValuesEnabled = true
            lineBolus.highlightEnabled = true
        } else {
            lineBolus.drawValuesEnabled = false
            lineBolus.highlightEnabled = true
        }
        
        // Carbs
        let chartEntryCarbs = [ChartDataEntry]()
        let lineCarbs = LineChartDataSet(entries:chartEntryCarbs, label: "")
        lineCarbs.circleRadius = CGFloat(globalVariables.dotCarb)
        lineCarbs.circleColors = [NSUIColor.systemOrange.withAlphaComponent(0.75)]
        lineCarbs.drawCircleHoleEnabled = false
        lineCarbs.setDrawHighlightIndicators(false)
        lineCarbs.setColor(NSUIColor.systemBlue, alpha: 1.0)
        lineCarbs.lineWidth = 0
        lineCarbs.axisDependency = YAxis.AxisDependency.right
        lineCarbs.valueFormatter = ChartYDataValueFormatter()
        lineCarbs.valueTextColor = NSUIColor.label
        lineCarbs.fillColor = NSUIColor.systemOrange
        lineCarbs.fillAlpha = 0.6
       
            lineCarbs.drawCirclesEnabled = true
            lineCarbs.drawFilledEnabled = false
        
        if UserDefaultsRepository.showValues.value {
            lineCarbs.drawValuesEnabled = true
            lineCarbs.highlightEnabled = true
        } else {
            lineCarbs.drawValuesEnabled = false
            lineCarbs.highlightEnabled = true
        }
        
        // create Scheduled Basal graph data
        let chartBasalScheduledEntry = [ChartDataEntry]()
        let lineBasalScheduled = LineChartDataSet(entries:chartBasalScheduledEntry, label: "")
        lineBasalScheduled.setDrawHighlightIndicators(false)
        lineBasalScheduled.setColor(NSUIColor.systemBlue, alpha: 0.8)
        lineBasalScheduled.lineWidth = 2
        lineBasalScheduled.drawFilledEnabled = false
        lineBasalScheduled.drawCirclesEnabled = false
        lineBasalScheduled.axisDependency = YAxis.AxisDependency.left
        lineBasalScheduled.highlightEnabled = false
        lineBasalScheduled.drawValuesEnabled = false
        lineBasalScheduled.lineDashLengths = [10.0, 5.0]
        
        // create Override graph data
        let chartOverrideEntry = [ChartDataEntry]()
        let lineOverride = LineChartDataSet(entries:chartOverrideEntry, label: "")
        lineOverride.setDrawHighlightIndicators(false)
        lineOverride.lineWidth = 0
        lineOverride.drawFilledEnabled = true
        lineOverride.fillFormatter = OverrideFillFormatter()
        lineOverride.fillColor = NSUIColor.systemPurple.withAlphaComponent(0.7)
        lineOverride.fillAlpha = 0.6
        lineOverride.drawCirclesEnabled = false
        lineOverride.axisDependency = YAxis.AxisDependency.right
        lineOverride.highlightEnabled = true
        lineOverride.drawValuesEnabled = false
        
        // BG Check
        let chartEntryBGCheck = [ChartDataEntry]()
        let lineBGCheck = LineChartDataSet(entries:chartEntryBGCheck, label: "")
        lineBGCheck.circleRadius = CGFloat(globalVariables.dotOther)
        lineBGCheck.circleColors = [NSUIColor.systemRed.withAlphaComponent(1.0)]
        lineBGCheck.drawCircleHoleEnabled = false
        lineBGCheck.setDrawHighlightIndicators(false)
        lineBGCheck.setColor(NSUIColor.systemRed, alpha: 1.0)
        lineBGCheck.drawCirclesEnabled = false
        lineBGCheck.lineWidth = 0
        lineBGCheck.highlightEnabled = true
        lineBGCheck.axisDependency = YAxis.AxisDependency.right
        lineBGCheck.valueFormatter = ChartYDataValueFormatter()
        lineBGCheck.drawValuesEnabled = false
        
        // Suspend Pump
        let chartEntrySuspend = [ChartDataEntry]()
        let lineSuspend = LineChartDataSet(entries:chartEntrySuspend, label: "")
        lineSuspend.circleRadius = CGFloat(globalVariables.dotOther)
        lineSuspend.circleColors = [NSUIColor.systemTeal.withAlphaComponent(0.75)]
        lineSuspend.drawCircleHoleEnabled = false
        lineSuspend.setDrawHighlightIndicators(false)
        lineSuspend.setColor(NSUIColor.systemGray2, alpha: 1.0)
        lineSuspend.drawCirclesEnabled = true
        lineSuspend.lineWidth = 0
        lineSuspend.highlightEnabled = true
        lineSuspend.axisDependency = YAxis.AxisDependency.right
        lineSuspend.valueFormatter = ChartYDataValueFormatter()
        lineSuspend.drawValuesEnabled = false
        
        // Resume Pump
        let chartEntryResume = [ChartDataEntry]()
        let lineResume = LineChartDataSet(entries:chartEntryResume, label: "")
        lineResume.circleRadius = CGFloat(globalVariables.dotOther)
        lineResume.circleColors = [NSUIColor.systemTeal.withAlphaComponent(0.75)]
        lineResume.drawCircleHoleEnabled = false
        lineResume.setDrawHighlightIndicators(false)
        lineResume.setColor(NSUIColor.systemGray4, alpha: 1.0)
        lineResume.drawCirclesEnabled = true
        lineResume.lineWidth = 0
        lineResume.highlightEnabled = true
        lineResume.axisDependency = YAxis.AxisDependency.right
        lineResume.valueFormatter = ChartYDataValueFormatter()
        lineResume.drawValuesEnabled = false
        
        // Training
        let chartEntryTraining = [ChartDataEntry]()
        let lineTraining = LineChartDataSet(entries:chartEntryTraining, label: "")
        lineTraining.circleRadius = CGFloat(globalVariables.dotOther)
        lineTraining.circleColors = [NSUIColor.systemGreen.withAlphaComponent(0.65)]
        lineTraining.drawCircleHoleEnabled = false
        lineTraining.setDrawHighlightIndicators(false)
        lineTraining.setColor(NSUIColor.systemGreen, alpha: 1.0)
        lineTraining.drawCirclesEnabled = true
        lineTraining.lineWidth = 0
        lineTraining.highlightEnabled = true
        lineTraining.axisDependency = YAxis.AxisDependency.right
        lineTraining.valueFormatter = ChartYDataValueFormatter()
        lineTraining.drawValuesEnabled = false
        
        // Warning
        let chartEntryWarning = [ChartDataEntry]()
        let lineWarning = LineChartDataSet(entries:chartEntryWarning, label: "")
        lineWarning.circleRadius = CGFloat(globalVariables.dotOther)
        lineWarning.circleColors = [NSUIColor.systemYellow.withAlphaComponent(1.0)]
        lineWarning.drawCircleHoleEnabled = false
        lineWarning.setDrawHighlightIndicators(false)
        lineWarning.setColor(NSUIColor.clear)
        lineWarning.drawCirclesEnabled = false
        lineWarning.lineWidth = 0
        lineWarning.highlightEnabled = true
        lineWarning.axisDependency = YAxis.AxisDependency.right
        lineWarning.valueFormatter = ChartYDataValueFormatter()
        lineWarning.drawValuesEnabled = false
        
        // Sensor Start
        let chartEntrySensor = [ChartDataEntry]()
        let lineSensor = LineChartDataSet(entries:chartEntrySensor, label: "")
        lineSensor.circleRadius = CGFloat(globalVariables.dotOther)
        lineSensor.circleColors = [NSUIColor.systemTeal.withAlphaComponent(0.75)]
        lineSensor.drawCircleHoleEnabled = false
        lineSensor.setDrawHighlightIndicators(false)
        lineSensor.setColor(NSUIColor.systemGray3, alpha: 1.0)
        lineSensor.drawCirclesEnabled = true
        lineSensor.lineWidth = 0
        lineSensor.highlightEnabled = true
        lineSensor.axisDependency = YAxis.AxisDependency.right
        lineSensor.valueFormatter = ChartYDataValueFormatter()
        lineSensor.drawValuesEnabled = false
        
        // Pump Change
        var chartEntryPump = [ChartDataEntry]()
        let linePump = LineChartDataSet(entries:chartEntryPump, label: "")
        linePump.circleRadius = CGFloat(globalVariables.dotOther)
        linePump.circleColors = [NSUIColor.systemTeal.withAlphaComponent(0.75)]
        linePump.drawCircleHoleEnabled = false
        linePump.setDrawHighlightIndicators(false)
        linePump.setColor(NSUIColor.systemGray3, alpha: 1.0)
        linePump.drawCirclesEnabled = true
        linePump.lineWidth = 0
        linePump.highlightEnabled = true
        linePump.axisDependency = YAxis.AxisDependency.right
        linePump.valueFormatter = ChartYDataValueFormatter()
        linePump.drawValuesEnabled = false
        
        // Notes
        let chartEntryNote = [ChartDataEntry]()
        let lineNote = LineChartDataSet(entries:chartEntryNote, label: "")
        lineNote.circleRadius = CGFloat(globalVariables.dotOther)
        lineNote.circleColors = [NSUIColor.label.withAlphaComponent(0.3)]
        lineNote.drawCircleHoleEnabled = false
        lineNote.setDrawHighlightIndicators(false)
        lineNote.setColor(NSUIColor.white, alpha: 1.0)
        lineNote.drawCirclesEnabled = true
        lineNote.lineWidth = 0
        lineNote.highlightEnabled = true
        lineNote.axisDependency = YAxis.AxisDependency.right
        lineNote.valueFormatter = ChartYDataValueFormatter()
        lineNote.drawValuesEnabled = false

        // Setup COB Prediction line details
        let COBpredictionChartEntry = [ChartDataEntry]()
        let COBlinePrediction = LineChartDataSet(entries:COBpredictionChartEntry, label: "")
        COBlinePrediction.circleRadius = CGFloat(globalVariables.dotBG)
        COBlinePrediction.circleColors = [NSUIColor.systemPurple]
        COBlinePrediction.colors = [NSUIColor.systemPurple]
        COBlinePrediction.drawCircleHoleEnabled = true
        COBlinePrediction.axisDependency = YAxis.AxisDependency.right
        COBlinePrediction.highlightEnabled = false
        COBlinePrediction.drawValuesEnabled = false
        
        if UserDefaultsRepository.showLines.value {
            COBlinePrediction.lineWidth = 0//2
        } else {
            COBlinePrediction.lineWidth = 0
        }
        if UserDefaultsRepository.showDots.value {
            COBlinePrediction.drawCirclesEnabled = true
        } else {
            COBlinePrediction.drawCirclesEnabled = false
        }
        COBlinePrediction.setDrawHighlightIndicators(false)
        COBlinePrediction.valueFont.withSize(50)
        
        // Setup IOB Prediction line details
        let IOBpredictionChartEntry = [ChartDataEntry]()
        let IOBlinePrediction = LineChartDataSet(entries:IOBpredictionChartEntry, label: "")
        IOBlinePrediction.circleRadius = CGFloat(globalVariables.dotBG)
        IOBlinePrediction.circleColors = [NSUIColor.systemPurple]
        IOBlinePrediction.colors = [NSUIColor.systemPurple]
        IOBlinePrediction.drawCircleHoleEnabled = true
        IOBlinePrediction.axisDependency = YAxis.AxisDependency.right
        IOBlinePrediction.highlightEnabled = false
        IOBlinePrediction.drawValuesEnabled = false
        
        if UserDefaultsRepository.showLines.value {
            IOBlinePrediction.lineWidth = 0//2
        } else {
            IOBlinePrediction.lineWidth = 0
        }
        if UserDefaultsRepository.showDots.value {
            IOBlinePrediction.drawCirclesEnabled = true
        } else {
            IOBlinePrediction.drawCirclesEnabled = false
        }
        IOBlinePrediction.setDrawHighlightIndicators(false)
        IOBlinePrediction.valueFont.withSize(50)
        
        // Setup UAM Prediction line details
        let UAMpredictionChartEntry = [ChartDataEntry]()
        let UAMlinePrediction = LineChartDataSet(entries:UAMpredictionChartEntry, label: "")
        UAMlinePrediction.circleRadius = CGFloat(globalVariables.dotBG)
        UAMlinePrediction.circleColors = [NSUIColor.systemPurple]
        UAMlinePrediction.colors = [NSUIColor.systemPurple]
        UAMlinePrediction.drawCircleHoleEnabled = true
        UAMlinePrediction.axisDependency = YAxis.AxisDependency.right
        UAMlinePrediction.highlightEnabled = false
        UAMlinePrediction.drawValuesEnabled = false
        
        if UserDefaultsRepository.showLines.value {
            UAMlinePrediction.lineWidth = 0//2
        } else {
            UAMlinePrediction.lineWidth = 0
        }
        if UserDefaultsRepository.showDots.value {
            UAMlinePrediction.drawCirclesEnabled = true
        } else {
            UAMlinePrediction.drawCirclesEnabled = false
        }
        UAMlinePrediction.setDrawHighlightIndicators(false)
        UAMlinePrediction.valueFont.withSize(50)
        
        // Setup ZT Prediction line details
        let ZTpredictionChartEntry = [ChartDataEntry]()
        let ZTlinePrediction = LineChartDataSet(entries:ZTpredictionChartEntry, label: "")
        ZTlinePrediction.circleRadius = CGFloat(globalVariables.dotBG)
        ZTlinePrediction.circleColors = [NSUIColor.systemPurple]
        ZTlinePrediction.colors = [NSUIColor.systemPurple]
        ZTlinePrediction.drawCircleHoleEnabled = true
        ZTlinePrediction.axisDependency = YAxis.AxisDependency.right
        ZTlinePrediction.highlightEnabled = false
        ZTlinePrediction.drawValuesEnabled = false
        
        if UserDefaultsRepository.showLines.value {
            ZTlinePrediction.lineWidth = 0//2
        } else {
            ZTlinePrediction.lineWidth = 0
        }
        if UserDefaultsRepository.showDots.value {
            ZTlinePrediction.drawCirclesEnabled = true
        } else {
            ZTlinePrediction.drawCirclesEnabled = false
        }
        ZTlinePrediction.setDrawHighlightIndicators(false)
        ZTlinePrediction.valueFont.withSize(50)

        // SMB
        let chartEntrySmb = [ChartDataEntry]()
        let lineSmb = LineChartDataSet(entries: chartEntrySmb, label: "")
        lineSmb.circleRadius = CGFloat(globalVariables.dotBolus)
        lineSmb.circleColors = [NSUIColor.systemBlue.withAlphaComponent(0.75)]
        lineSmb.drawCircleHoleEnabled = true
        lineSmb.setDrawHighlightIndicators(false)
        lineSmb.setColor(NSUIColor.systemBlue, alpha: 1.0)
        lineSmb.lineWidth = 0
        lineSmb.axisDependency = YAxis.AxisDependency.right
        lineSmb.valueFormatter = ChartYDataValueFormatter()
        lineSmb.valueTextColor = NSUIColor.label
        lineSmb.fillColor = NSUIColor.systemBlue
        lineSmb.fillAlpha = 0.6
        
        lineSmb.drawCirclesEnabled = true
        lineSmb.drawFilledEnabled = false
        
        if UserDefaultsRepository.showValues.value {
            lineSmb.drawValuesEnabled = true
            lineSmb.highlightEnabled = true
        } else {
            lineSmb.drawValuesEnabled = false
            lineSmb.highlightEnabled = true
        }

        // TempTarget graph data
        let chartTempTargetEntry = [ChartDataEntry]()
        let lineTempTarget = LineChartDataSet(entries:chartTempTargetEntry, label: "")
        lineTempTarget.setDrawHighlightIndicators(false)
        lineTempTarget.lineWidth = 0
        lineTempTarget.drawFilledEnabled = false
        lineTempTarget.fillColor = NSUIColor.systemPurple
        lineTempTarget.fillAlpha = 0.6
        lineTempTarget.drawCirclesEnabled = false
        lineTempTarget.axisDependency = YAxis.AxisDependency.right
        lineTempTarget.highlightEnabled = true
        lineTempTarget.drawValuesEnabled = false

        // Setup the chart data of all lines
        let data = LineChartData()
        
        data.append(lineBG) // Dataset 0
        data.append(linePrediction) // Dataset 1
        data.append(lineBasal) // Dataset 2
        data.append(lineBolus) // Dataset 3
        data.append(lineCarbs) // Dataset 4
        data.append(lineBasalScheduled) // Dataset 5
        data.append(lineOverride) // Dataset 6
        data.append(lineBGCheck) // Dataset 7
        data.append(lineSuspend) // Dataset 8
        data.append(lineResume) // Dataset 9
        data.append(lineSensor) // Dataset 10
        data.append(lineNote) // Dataset 11
        data.append(ZTlinePrediction) // Dataset 12
        data.append(IOBlinePrediction) // Dataset 13
        data.append(COBlinePrediction) // Dataset 14
        data.append(UAMlinePrediction) // Dataset 15
        data.append(lineSmb) // Dataset 16
        data.append(lineTempTarget) // Dataset 17
        data.append(linePump) // Dataset 18
        data.append(lineTraining) // Dataset 19
        data.append(lineWarning) // Dataset 20
        
        // Pulses for Temp Basal deliveries as small circles at bottom
        let basalPulseEntries: [ChartDataEntry] = []
        let basalPulseSet = LineChartDataSet(entries: basalPulseEntries, label: "TempBasal Pulses")
        basalPulseSet.axisDependency = .left
        basalPulseSet.drawCirclesEnabled = true
        basalPulseSet.drawCircleHoleEnabled = false
        basalPulseSet.circleRadius = 3.5
        basalPulseSet.circleColors = [NSUIColor.systemBlue.withAlphaComponent(0.6)]
        basalPulseSet.lineWidth = 0
        basalPulseSet.drawValuesEnabled = false
        basalPulseSet.highlightEnabled = false
        basalPulseSet.highlightColor = .clear
        basalPulseSet.highlightLineWidth = 0
        data.append(basalPulseSet)

        data.setValueFont(UIFont.systemFont(ofSize: 10))
        
        // Add marker popups for bolus and carbs
        let marker = PillMarker(color: .secondarySystemBackground, font: UIFont.boldSystemFont(ofSize: 14), textColor: .label)
        BGChart.marker = marker
        
        // Clear limit lines so they don't add multiples when changing the settings
        BGChart.rightAxis.removeAllLimitLines()
        
        //Add lower red line based on low alert value
        let ll = ChartLimitLine()
        ll.limit = Double(UserDefaultsRepository.lowLine.value)
        ll.lineColor = NSUIColor.systemRed.withAlphaComponent(0.7)
        ll.lineDashLengths = [1, 1]
        ll.lineWidth = 1.0
        BGChart.rightAxis.addLimitLine(ll)
        
        //Add upper purple line based on high alert value
        let ul = ChartLimitLine()
        ul.limit = Double(UserDefaultsRepository.highLine.value)
        ul.lineDashLengths = [1, 1]
        ul.lineWidth = 1.0
        if UserDefaultsRepository.colorBGText.value {
            ul.lineColor = NSUIColor.systemPurple.withAlphaComponent(0.7)
        } else {
            ul.lineColor = NSUIColor.systemYellow.withAlphaComponent(0.7)
        }
        BGChart.rightAxis.addLimitLine(ul)
        
        //Daniel: Add mid green line based on target value
        let tl = ChartLimitLine()
        tl.limit = Double(UserDefaultsRepository.targetLine.value)
        tl.lineColor = NSUIColor.systemGreen.withAlphaComponent(0.7)
        tl.lineWidth = 1.0
        tl.lineDashLengths = [1, 1]
        BGChart.rightAxis.addLimitLine(tl)
        
        // Add vertical lines as configured
        createVerticalLines()
        startGraphNowTimer()
        
        // Setup the main graph overall details:
        BGChart.xAxis.valueFormatter = ChartXValueFormatter()
        BGChart.xAxis.granularity = 1800
        BGChart.xAxis.labelTextColor = NSUIColor.label
        BGChart.xAxis.labelPosition = XAxis.LabelPosition.bottom
        BGChart.xAxis.drawGridLinesEnabled = false
        BGChart.xAxis.drawLimitLinesBehindDataEnabled = true

        BGChart.leftAxis.enabled = true
        BGChart.leftAxis.labelTextColor = NSUIColor.secondaryLabel
        BGChart.leftAxis.labelPosition = YAxis.LabelPosition.insideChart
        BGChart.leftAxis.labelFont = UIFont.boldSystemFont(ofSize: 10)
        BGChart.leftAxis.axisMaximum = maxBasal
        BGChart.leftAxis.axisMinimum = 0
        BGChart.leftAxis.drawGridLinesEnabled = false
        BGChart.leftAxis.granularityEnabled = true
        BGChart.leftAxis.granularity = 0.5
        BGChart.leftAxis.drawLimitLinesBehindDataEnabled = true
        BGChart.leftAxis.axisLineColor = .clear

        BGChart.rightAxis.labelTextColor = NSUIColor.secondaryLabel
        BGChart.rightAxis.labelPosition = YAxis.LabelPosition.insideChart
        BGChart.rightAxis.labelFont = UIFont.boldSystemFont(ofSize: 10)
        BGChart.rightAxis.axisMinimum = 0.0
        BGChart.rightAxis.drawLimitLinesBehindDataEnabled = true
        BGChart.rightAxis.axisLineColor = .clear

        if UserDefaultsRepository.units.value == "mmol/L" {
            let forcedMax = ceil(Double(maxBG) / 72.0) * 72.0
            BGChart.rightAxis.axisMaximum = forcedMax
            BGChart.rightAxis.gridLineDashLengths = [2.0, 2.0]
            BGChart.rightAxis.drawGridLinesEnabled = false
            BGChart.rightAxis.gridColor = NSUIColor.secondaryLabel.withAlphaComponent(0.2)
            BGChart.rightAxis.valueFormatter = ChartYMMOLValueFormatter()
            BGChart.rightAxis.granularityEnabled = true
            BGChart.rightAxis.granularity = 72
            let labelCount = Int(forcedMax / 72.0) + 1
            BGChart.rightAxis.forceLabelsEnabled = true
            BGChart.rightAxis.setLabelCount(labelCount, force: true)
        } else {
            BGChart.rightAxis.axisMaximum = Double(maxBG)
            BGChart.rightAxis.gridLineDashLengths = [2.0, 2.0]
            BGChart.rightAxis.drawGridLinesEnabled = false
            BGChart.rightAxis.gridColor = NSUIColor.secondaryLabel.withAlphaComponent(0.2)
            BGChart.rightAxis.valueFormatter = ChartYMMOLValueFormatter()
            BGChart.rightAxis.granularityEnabled = true
            BGChart.rightAxis.granularity = 50
        }
            
        BGChart.maxHighlightDistance = 15.0
        BGChart.legend.enabled = false
        BGChart.scaleYEnabled = false
        BGChart.drawGridBackgroundEnabled = true
        BGChart.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)
        BGChart.highlightValue(nil, callDelegate: false)
        BGChart.data = data
        BGChart.setExtraOffsets(left: 5, top: 10, right: 5, bottom: 10)


    }

    func updateRightAxis(forMax maxBG: Double) {
        if UserDefaultsRepository.units.value == "mmol/L" {
            // Force maximum to a multiple of 72 mg/dL.
            let forcedMax = ceil(maxBG / 72.0) * 72.0
            BGChart.rightAxis.axisMaximum = forcedMax
            BGChartFull.rightAxis.axisMaximum = forcedMax
            
            // Force tick marks every 72 mg/dL.
            let labelCount = Int(forcedMax / 72.0) + 1
            BGChart.rightAxis.forceLabelsEnabled = true
            BGChart.rightAxis.setLabelCount(labelCount, force: true)
            BGChart.rightAxis.granularityEnabled = true
            BGChart.rightAxis.granularity = 72
            
            BGChartFull.rightAxis.forceLabelsEnabled = true
            BGChartFull.rightAxis.setLabelCount(labelCount, force: true)
            BGChartFull.rightAxis.granularityEnabled = true
            BGChartFull.rightAxis.granularity = 72
        } else {
            // For mg/dL, use the dynamic max and a granularity of 50.
            BGChart.rightAxis.axisMaximum = maxBG
            BGChartFull.rightAxis.axisMaximum = maxBG
            
            BGChart.rightAxis.forceLabelsEnabled = false
            BGChart.rightAxis.granularityEnabled = true
            BGChart.rightAxis.granularity = 50
            
            BGChartFull.rightAxis.forceLabelsEnabled = false
            BGChartFull.rightAxis.granularityEnabled = true
            BGChartFull.rightAxis.granularity = 50
        }
    }


    
    func createVerticalLines() {
        BGChart.xAxis.removeAllLimitLines()
        BGChartFull.xAxis.removeAllLimitLines()
        createNowAndDIALines()
        createMidnightLines()
    }
    
    func createNowAndDIALines() {
        let ul = ChartLimitLine()
        ul.limit = Double(dateTimeUtils.getNowTimeIntervalUTC())
        ul.lineColor = NSUIColor.label
        ul.lineDashLengths = [CGFloat(4), CGFloat(2)]
        ul.lineWidth = 2
        BGChart.xAxis.addLimitLine(ul)
        
        // Small chart
        let sl = ChartLimitLine()
        sl.limit = Double(dateTimeUtils.getNowTimeIntervalUTC())
        sl.lineColor = NSUIColor.label
        sl.lineDashLengths = [CGFloat(2), CGFloat(2)]
        sl.lineWidth = 2
        BGChartFull.xAxis.addLimitLine(sl)
        
        if UserDefaultsRepository.show30MinLine.value {
            let ul2 = ChartLimitLine()
            ul2.limit = Double(dateTimeUtils.getNowTimeIntervalUTC().advanced(by: -30 * 60))
            ul2.lineColor = NSUIColor.systemBlue.withAlphaComponent(0.5)
            ul2.lineWidth = 1.5
            ul2.lineDashLengths = [1, 1]
            BGChart.xAxis.addLimitLine(ul2)
        }
        
        if UserDefaultsRepository.showDIALines.value {
            for i in 1..<7 {
                let ul = ChartLimitLine()
                ul.limit = Double(dateTimeUtils.getNowTimeIntervalUTC() - Double(i * 60 * 60))
                ul.lineColor = NSUIColor.systemGray.withAlphaComponent(0.5)
                let dash = 10.0 - Double(i)
                let space = 5.0 + Double(i)
                ul.lineDashLengths = [CGFloat(dash), CGFloat(space)]
                ul.lineWidth = 1
                BGChart.xAxis.addLimitLine(ul)
            }
        }
        
        // Daniel: Changed below show -90 min to instead show -24 h (to quickly campare now with yesterday same time)
        if UserDefaultsRepository.showMinus24hLine.value {
            // Large chart
            let ul3 = ChartLimitLine()
            ul3.limit = Double(dateTimeUtils.getNowTimeIntervalUTC().advanced(by: -1440 * 60))
            ul3.lineColor = NSUIColor.systemOrange.withAlphaComponent(0.8)
            ul3.lineDashLengths = [CGFloat(4), CGFloat(2)]
            ul3.lineWidth = 2
            BGChart.xAxis.addLimitLine(ul3)
            
            // Small chart
            let sl3 = ChartLimitLine()
            sl3.limit = Double(dateTimeUtils.getNowTimeIntervalUTC().advanced(by: -1440 * 60))
            sl3.lineColor = NSUIColor.systemOrange.withAlphaComponent(0.8)
            sl3.lineDashLengths = [CGFloat(2), CGFloat(2)]
            sl3.lineWidth = 2
            BGChartFull.xAxis.addLimitLine(sl3)
        }
    }
    
    func createMidnightLines() {
        // Draw a line at midnight: useful when showing multiple days of data
        if UserDefaultsRepository.showMidnightLines.value {
            var midnightTimeInterval = dateTimeUtils.getTimeIntervalMidnightToday()
            let graphHours = 24 * UserDefaultsRepository.downloadDays.value
            let graphStart = dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours)
            while midnightTimeInterval > graphStart {
                // Large chart
                let ul = ChartLimitLine()
                ul.limit = Double(midnightTimeInterval)
                ul.lineColor = NSUIColor.systemIndigo //.withAlphaComponent(0.7)
                ul.lineDashLengths = [CGFloat(4), CGFloat(2)]
                ul.lineWidth = 2
                BGChart.xAxis.addLimitLine(ul)

                // Small chart
                let sl = ChartLimitLine()
                sl.limit = Double(midnightTimeInterval)
                sl.lineColor = NSUIColor.systemIndigo //.withAlphaComponent(0.7)
                sl.lineDashLengths = [CGFloat(2), CGFloat(2)]
                sl.lineWidth = 2
                BGChartFull.xAxis.addLimitLine(sl)
                
                midnightTimeInterval = midnightTimeInterval.advanced(by: -24*60*60)
            }
        }
    }
    
    func updateBGGraphSettings() {
        let dataIndex = 0
        let dataIndexPrediction = 1
        let lineBG = BGChart.lineData!.dataSets[dataIndex] as! LineChartDataSet
        let linePrediction = BGChart.lineData!.dataSets[dataIndexPrediction] as! LineChartDataSet
        if UserDefaultsRepository.showLines.value {
            lineBG.lineWidth = 2
            linePrediction.lineWidth = 2
        } else {
            lineBG.lineWidth = 0
            linePrediction.lineWidth = 0
        }
        if UserDefaultsRepository.showDots.value {
            lineBG.drawCirclesEnabled = true
            linePrediction.drawCirclesEnabled = true
        } else {
            lineBG.drawCirclesEnabled = false
            linePrediction.drawCirclesEnabled = false
        }
        
        BGChart.rightAxis.axisMinimum = 0
        
        // Clear limit lines so they don't add multiples when changing the settings
        BGChart.rightAxis.removeAllLimitLines()
        
        //Add lower red line based on low alert value
        let ll = ChartLimitLine()
        ll.lineDashLengths = [1, 1]
        ll.lineWidth = 1.0
        ll.limit = Double(UserDefaultsRepository.lowLine.value)
        ll.lineColor = NSUIColor.systemRed.withAlphaComponent(0.7)
        BGChart.rightAxis.addLimitLine(ll)
        
        //Add upper purple line based on low alert value
        let ul = ChartLimitLine()
        ul.limit = Double(UserDefaultsRepository.highLine.value)
        ul.lineDashLengths = [1, 1]
        ul.lineWidth = 1.0
        if UserDefaultsRepository.colorBGText.value {
            ul.lineColor = NSUIColor.systemPurple.withAlphaComponent(0.7)
        } else {
            ul.lineColor = NSUIColor.systemYellow.withAlphaComponent(0.7)
        }
        BGChart.rightAxis.addLimitLine(ul)
        
        //Daniel: Add mid green line based on target value
        let tl = ChartLimitLine()
        tl.limit = Double(UserDefaultsRepository.targetLine.value)
        tl.lineColor = NSUIColor.systemGreen.withAlphaComponent(0.7)
        tl.lineDashLengths = [1, 1]
        tl.lineWidth = 1.0
        BGChart.rightAxis.addLimitLine(tl)
        
        // Re-create vertical markers in case their settings changed
        createVerticalLines()
    
        BGChart.data?.dataSets[dataIndex].notifyDataSetChanged()
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
        
    }
    
    func setBGColor(_ bgValue: Int) -> NSUIColor {

             // Auggie's dynamic color - Define the hue values for the key points
             let redHue: CGFloat = 0.0 / 360.0       // 0 degrees
             let greenHue: CGFloat = 120.0 / 360.0   // 120 degrees
             let purpleHue: CGFloat = 270.0 / 360.0  // 270 degrees

             // Define the bgLevel thresholds
             let minLevel = Int(UserDefaultsRepository.alertUrgentLowBG.value) // Use the urgent low BG alarm value for red text
             let targetLevel = Int(UserDefaultsRepository.targetLine.value) // Use the target BG for green text
             let maxLevel = Int(UserDefaultsRepository.alertUrgentHighBG.value) // Use the urgent high BG alarm value for purple text

             // Calculate the hue based on the bgLevel
             var hue: CGFloat
             if bgValue <= minLevel {
                 hue = redHue
             } else if bgValue >= maxLevel {
                 hue = purpleHue
             } else if bgValue <= targetLevel {
                 // Interpolate between red and green
                 let ratio = CGFloat(bgValue - minLevel) / CGFloat(targetLevel - minLevel)
                 hue = redHue + ratio * (greenHue - redHue)
             } else {
                 // Interpolate between green and purple
                 let ratio = CGFloat(bgValue - targetLevel) / CGFloat(maxLevel - targetLevel)
                 hue = greenHue + ratio * (purpleHue - greenHue)
             }

             // Return the color with full saturation and brightness
             let color = UIColor(hue: hue, saturation: 0.9, brightness: 0.9, alpha: 1.0)
             return color
         }
    
    // Daniel: Test even mmol yaxis tick marks
    func updateBGGraph() {
        let dataIndex = 0
        let entries = bgData
        guard !entries.isEmpty else {
            return
        }
        let mainChart = BGChart.lineData!.dataSets[dataIndex] as! LineChartDataSet
        let smallChart = BGChartFull.lineData!.dataSets[dataIndex] as! LineChartDataSet
        mainChart.removeAll(keepingCapacity: false)
        smallChart.removeAll(keepingCapacity: false)
        let maxBGOffset: Float = 36
        
        var colors = [NSUIColor]()
        topBG = UserDefaultsRepository.minBGScale.value
        for i in 0..<entries.count {
            if Float(entries[i].sgv) > topBG - maxBGOffset {
                topBG = Float(entries[i].sgv) + maxBGOffset
            }
            let value = ChartDataEntry(
                x: Double(entries[i].date),
                y: Double(entries[i].sgv),
                data: formatPillTextExtraLine(
                    line1: "Blodsocker",
                    line2: Localizer.toDisplayUnits(String(entries[i].sgv)) + (UserDefaultsRepository.units.value == "mmol/L" ? " mmol/L" : " mg/dL"),
                    time: entries[i].date
                )
            )
            mainChart.append(value)
            smallChart.append(value)
            
            // Set colors based on BG level.
            if UserDefaultsRepository.colorBGText.value {
                colors.append(setBGColor(entries[i].sgv))
            } else {
                if Double(entries[i].sgv) >= Double(UserDefaultsRepository.highLine.value) {
                    colors.append(NSUIColor.systemYellow)
                } else if Double(entries[i].sgv) <= Double(UserDefaultsRepository.lowLine.value) {
                    colors.append(NSUIColor.systemRed)
                } else {
                    colors.append(NSUIColor.systemGreen)
                }
            }
        }
        
        // Set Colors
        let lineBG = BGChart.lineData!.dataSets[dataIndex] as! LineChartDataSet
        let lineBGSmall = BGChartFull.lineData!.dataSets[dataIndex] as! LineChartDataSet
        lineBG.colors.removeAll()
        lineBG.circleColors.removeAll()
        lineBGSmall.colors.removeAll()
        lineBGSmall.circleColors.removeAll()
        for color in colors {
            mainChart.addColor(color)
            mainChart.circleColors.append(color)
            smallChart.addColor(color)
            smallChart.circleColors.append(color)
        }
        
        // Calculate dynamic maximum (in mg/dL) from your data.
        let maxValue = Double(calculateMaxBgGraphValue())
        // Update the right axis based on units.
        updateRightAxis(forMax: maxValue)
        
        BGChart.setVisibleXRangeMinimum(600)
        BGChart.data?.dataSets[dataIndex].notifyDataSetChanged()
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
        BGChartFull.data?.dataSets[dataIndex].notifyDataSetChanged()
        BGChartFull.data?.notifyDataChanged()
        BGChartFull.notifyDataSetChanged()
        
        // Refresh temp basal pulse dots
        updateTempBasalPulses()
        
        // (Additional code for zooming and auto-scrolling…)
        if firstGraphLoad {
            var scaleX = CGFloat(UserDefaultsRepository.chartScaleX.value)
            if scaleX > CGFloat(ScaleXMax) {
                scaleX = CGFloat(ScaleXMax)
                UserDefaultsRepository.chartScaleX.value = ScaleXMax
            }
            BGChart.zoom(scaleX: scaleX, scaleY: 1, x: 1, y: 1)
            firstGraphLoad = false
        }
        
        if autoScrollPauseUntil == nil || Date() > autoScrollPauseUntil! {
            BGChart.moveViewToAnimated(
                xValue: dateTimeUtils.getNowTimeIntervalUTC() - (BGChart.visibleXRange * 0.7),
                yValue: 0.0,
                axis: .right,
                duration: 1,
                easingOption: .easeInBack
            )
        }
    }
    
    // MARK: - Trio Decision Popup for BG Points

    /// Hämtar Trio-beslutsreason för en BG-timestamp och visar som alert.
    private func showTrioDecisionAlert(for timestamp: TimeInterval) {
        // `timestamp` kommer från entry.x och är sekunder sedan 1970 (TimeInterval)
        let bgDate = Date(timeIntervalSince1970: timestamp)
        // +180s-offset pga eftersläpning device status vs bg-värden
        let adjustedTimestamp = bgDate.addingTimeInterval(180)

        NightscoutUtils.fetchDeviceStatusReasonBeforeTimestamp(timestamp: adjustedTimestamp) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let reason):
                let formattedReason = self.formatGraphReason(reason)
                let alert = UIAlertController(
                    title: "Trio behandlingsbeslut",
                    message: formattedReason,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self.present(alert, animated: true, completion: nil)

            case .failure(let error):
                let alert = UIAlertController(
                    title: "Fel",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self.present(alert, animated: true, completion: nil)
            }
        }
    }

    /// Formatterar reason-strängen ungefär som i TreatmentsTableView.formatReason,
    /// men lokalt i Graphs för BG-popupen.
    private func formatGraphReason(_ reason: String) -> String {
        var formatted = reason

        // 1. Hantera AF och SMB Ratio innan övriga ersättningar.
        let patternAFSMB = "AF:\\s([0-9]\\.[0-9]{1,2})(?:,\\sSMB Ratio:\\s([0-9]\\.[0-9]{1,2}))?;"
        if let regexAFSMB = try? NSRegularExpression(pattern: patternAFSMB, options: []) {
            let range = NSRange(location: 0, length: formatted.utf16.count)
            let matches = regexAFSMB.matches(in: formatted, options: [], range: range)
            for match in matches.reversed() {
                let fullRange = match.range(at: 0)
                let afValue = (formatted as NSString).substring(with: match.range(at: 1))
                var replacement = "AF: \(afValue)\n"
                if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                    let smbValue = (formatted as NSString).substring(with: match.range(at: 2))
                    if !smbValue.isEmpty {
                        replacement += "• SMB Ratio: \(smbValue)\n"
                    }
                }
                replacement += "\n👉  OREF SLUTSATS:\n•"
                formatted = (formatted as NSString).replacingCharacters(in: fullRange, with: replacement)
            }
        }

        // 2. Byt alla kommatecken mot radbrytning + punktlista.
        formatted = formatted.replacingOccurrences(of: ",", with: "\n•")

        // 3. Mer specifika ersättningar.

        // Endast "BG: 5.5" som INTE har en bokstav direkt före "B"
        if let regexBG55 = try? NSRegularExpression(pattern: "(?<![A-Za-z])BG: 5\\.5", options: []) {
            let range = NSRange(location: 0, length: formatted.utf16.count)
            formatted = regexBG55.stringByReplacingMatches(
                in: formatted,
                options: [],
                range: range,
                withTemplate: "Glukos: 5.5 🦄"
            )
        }

        // Endast "BG:" som INTE har en bokstav direkt före "B"
        if let regexBG = try? NSRegularExpression(pattern: "(?<![A-Za-z])BG:", options: []) {
            let range = NSRange(location: 0, length: formatted.utf16.count)
            formatted = regexBG.stringByReplacingMatches(
                in: formatted,
                options: [],
                range: range,
                withTemplate: "Glukos:"
            )
        }
        formatted = formatted.replacingOccurrences(of: "SMB INAKTIVERADE!", with: "SMB Inaktiverade 🚫")
        formatted = formatted.replacingOccurrences(of: "Mikrobolus:", with: "🔹 Mikrobolus:")
        formatted = formatted.replacingOccurrences(of: ". ;", with: "\n• ")
        formatted = formatted.replacingOccurrences(of: "E. ", with: "E\n")
        formatted = formatted.replacingOccurrences(of: "U. ", with: "E\n")
        formatted = formatted.replacingOccurrences(of: "E/h. ", with: "E/h\n")
        formatted = formatted.replacingOccurrences(of: "temp.", with: "temp.\n")
        formatted = formatted.replacingOccurrences(of: ". ", with: "")
        formatted = formatted.replacingOccurrences(of: "; ", with: "\n• ")

        // 4. Ersätt "TDD: <number> U" med kompakt variant.
        if let regexTDD = try? NSRegularExpression(pattern: "TDD:\\s(\\d+(?:\\.\\d{1,2})?)\\sU", options: []) {
            let range = NSRange(location: 0, length: formatted.utf16.count)
            formatted = regexTDD.stringByReplacingMatches(
                in: formatted,
                options: [],
                range: range,
                withTemplate: "TDD: $1E"
            )
        }

        // 5. HTML-encodeade < och >.
        formatted = formatted.replacingOccurrences(of: "&lt;", with: "<")
        formatted = formatted.replacingOccurrences(of: "&gt;", with: ">")

        return formatted
    }

    // Daniel: Test even mmol yaxis tick marks
    func updatePredictionGraph(color: UIColor? = nil) {
        let dataIndex = 1
        let mainChart = BGChart.lineData!.dataSets[dataIndex] as! LineChartDataSet
        let smallChart = BGChartFull.lineData!.dataSets[dataIndex] as! LineChartDataSet
        mainChart.clear()
        smallChart.clear()
        
        var colors = [NSUIColor]()
        let maxBGOffset: Float = 18

        topPredictionBG = UserDefaultsRepository.minBGScale.value
        for i in 0..<predictionData.count {
            let predictionVal = Double(predictionData[i].sgv)
            if Float(predictionVal) > topPredictionBG - maxBGOffset {
                topPredictionBG = Float(predictionVal) + maxBGOffset
            }
            
            if i == 0 {
                if UserDefaultsRepository.showDots.value {
                    colors.append((color ?? NSUIColor.systemPurple).withAlphaComponent(0.0))
                } else {
                    colors.append((color ?? NSUIColor.systemPurple).withAlphaComponent(1.0))
                }
            } else if predictionVal > 400 {
                colors.append(color ?? NSUIColor.systemYellow)
            } else if predictionVal < 0 {
                colors.append(color ?? NSUIColor.systemRed)
            } else {
                colors.append(color ?? NSUIColor.systemPurple)
            }
            
            let value = ChartDataEntry(
                x: predictionData[i].date,
                y: predictionVal,
                data: formatPillTextExtraLine(
                    line1: "Prognos",
                    line2: Localizer.toDisplayUnits(String(predictionData[i].sgv)) + (UserDefaultsRepository.units.value == "mmol/L" ? " mmol/L" : " mg/dL"),
                    time: predictionData[i].date
                )
            )
            mainChart.addEntry(value)
            smallChart.addEntry(value)
        }
        
        smallChart.circleColors.removeAll()
        smallChart.colors.removeAll()
        mainChart.colors.removeAll()
        mainChart.circleColors.removeAll()
        for clr in colors {
            mainChart.addColor(clr)
            mainChart.circleColors.append(clr)
            smallChart.addColor(clr)
            smallChart.circleColors.append(clr)
        }
        
        // Calculate the current maximum (in mg/dL) from the data.
        let currentMaxBG = calculateMaxBgGraphValue()
        
        if UserDefaultsRepository.units.value == "mmol/L" {
            // Force maximum to a multiple of 90 mg/dL.
            let forcedMax = ceil(Double(currentMaxBG) / 72.0) * 72.0
            BGChart.rightAxis.axisMaximum = forcedMax
            BGChartFull.rightAxis.axisMaximum = forcedMax
            
            let labelCount = Int(forcedMax / 72.0) + 1
            BGChart.rightAxis.forceLabelsEnabled = true
            BGChart.rightAxis.setLabelCount(labelCount, force: true)
            BGChart.rightAxis.granularityEnabled = true
            BGChart.rightAxis.granularity = 72
            
            BGChartFull.rightAxis.forceLabelsEnabled = true
            BGChartFull.rightAxis.setLabelCount(labelCount, force: true)
            BGChartFull.rightAxis.granularityEnabled = true
            BGChartFull.rightAxis.granularity = 72
            
        } else {
            // For mg/dL mode, use the dynamic max and a granularity of 50.
            BGChart.rightAxis.axisMaximum = Double(currentMaxBG)
            BGChartFull.rightAxis.axisMaximum = Double(currentMaxBG)
            
            BGChart.rightAxis.forceLabelsEnabled = false
            BGChart.rightAxis.granularityEnabled = true
            BGChart.rightAxis.granularity = 50
            
            BGChartFull.rightAxis.forceLabelsEnabled = false
            BGChartFull.rightAxis.granularityEnabled = true
            BGChartFull.rightAxis.granularity = 50
        }
        
        // Notify the charts that the data has changed.
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
        BGChartFull.data?.notifyDataChanged()
        BGChartFull.notifyDataSetChanged()
    }
    
    func updateBasalGraph() {
        var dataIndex = 2
        BGChart.lineData?.dataSets[dataIndex].clear()
        BGChartFull.lineData?.dataSets[dataIndex].clear()
        var maxBasal = UserDefaultsRepository.minBasalScale.value
        var maxBasalSmall: Double = 0.0
        for i in 0..<basalData.count{
            let value = ChartDataEntry(x: Double(basalData[i].date), y: Double(basalData[i].basalRate), data: formatPillTextExtraLine(line1: "Basal", line2: String(basalData[i].basalRate) + " E/h", time: basalData[i].date))
            BGChart.data?.dataSets[dataIndex].addEntry(value)
            if UserDefaultsRepository.smallGraphTreatments.value {
                BGChartFull.data?.dataSets[dataIndex].addEntry(value)
            }
            if basalData[i].basalRate  > maxBasal {
                maxBasal = basalData[i].basalRate
            }
            if basalData[i].basalRate > maxBasalSmall {
                maxBasalSmall = basalData[i].basalRate
            }
        }
        
        BGChart.leftAxis.axisMaximum = maxBasal
        BGChartFull.leftAxis.axisMaximum = maxBasalSmall
        
        BGChart.data?.dataSets[dataIndex].notifyDataSetChanged()
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
        
        if UserDefaultsRepository.smallGraphTreatments.value {
            BGChartFull.data?.dataSets[dataIndex].notifyDataSetChanged()
            BGChartFull.data?.notifyDataChanged()
            BGChartFull.notifyDataSetChanged()
        }
    }
    
    func updateBasalScheduledGraph() {
        var dataIndex = 5
        BGChart.lineData?.dataSets[dataIndex].clear()
        BGChartFull.lineData?.dataSets[dataIndex].clear()
        for i in 0..<basalScheduleData.count{
            let value = ChartDataEntry(x: Double(basalScheduleData[i].date), y: Double(basalScheduleData[i].basalRate))
            BGChart.data?.dataSets[dataIndex].addEntry(value)
            if UserDefaultsRepository.smallGraphTreatments.value {
                BGChartFull.data?.dataSets[dataIndex].addEntry(value)
            }
        }
        
        BGChart.data?.dataSets[dataIndex].notifyDataSetChanged()
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
        if UserDefaultsRepository.smallGraphTreatments.value {
            BGChartFull.data?.dataSets[dataIndex].notifyDataSetChanged()
            BGChartFull.data?.notifyDataChanged()
            BGChartFull.notifyDataSetChanged()
        }
    }
    
    func updateBolusGraph() {
        var dataIndex = 3
        var yTop: Double = 370
        var yBottom: Double = 345
        var mainChart = BGChart.lineData!.dataSets[dataIndex] as! LineChartDataSet
        var smallChart = BGChartFull.lineData!.dataSets[dataIndex] as! LineChartDataSet
        mainChart.clear()
        smallChart.clear()
        
        var colors = [NSUIColor]()
        for i in 0..<bolusData.count{
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 2
            formatter.minimumIntegerDigits = 0
            
            // Check overlapping bolus to shift left if needed
            let bolusShift = findNextBolusTime(timeWithin: 240, needle: bolusData[i].date, haystack: bolusData, startingIndex: i)
            var dateTimeStamp = bolusData[i].date
            
            colors.append(NSUIColor.systemBlue.withAlphaComponent(1.0))
            
            if bolusShift {
                // Move it half the distance between BG readings
                dateTimeStamp = dateTimeStamp - 150
            }
            
            // skip if outside of visible area
            let graphHours = 24 * UserDefaultsRepository.downloadDays.value
            if dateTimeStamp < dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours) { continue }
  
            let dot = ChartDataEntry(x: Double(dateTimeStamp), y: Double(bolusData[i].sgv), data: formatPillTextExtraLine(line1: "Bolus", line2: (formatter.string(from: NSNumber(value: bolusData[i].value))?.replacingOccurrences(of: ",", with: "."))! + " E", time: dateTimeStamp))
            mainChart.addEntry(dot)
            if UserDefaultsRepository.smallGraphTreatments.value {
                smallChart.addEntry(dot)
            }
        }
        
        // Set Colors
        let lineBolus = BGChart.lineData!.dataSets[dataIndex] as! LineChartDataSet
        let lineBolusSmall = BGChartFull.lineData!.dataSets[dataIndex] as! LineChartDataSet
        lineBolus.colors.removeAll()
        lineBolus.circleColors.removeAll()
        lineBolusSmall.colors.removeAll()
        lineBolusSmall.circleColors.removeAll()
        
        if colors.count > 0 {
            for i in 0..<colors.count{
                mainChart.addColor(colors[i])
                mainChart.circleColors.append(colors[i])
                smallChart.addColor(colors[i])
                smallChart.circleColors.append(colors[i])
            }
        }
        
        BGChart.data?.dataSets[dataIndex].notifyDataSetChanged()
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
        if UserDefaultsRepository.smallGraphTreatments.value {
            BGChartFull.data?.dataSets[dataIndex].notifyDataSetChanged()
            BGChartFull.data?.notifyDataChanged()
            BGChartFull.notifyDataSetChanged()
        }
    }
    
    func updateSmbGraph() {
        var dataIndex = 16
        var yTop: Double = 370
        var yBottom: Double = 345
        var mainChart = BGChart.lineData!.dataSets[dataIndex] as! LineChartDataSet
        var smallChart = BGChartFull.lineData!.dataSets[dataIndex] as! LineChartDataSet
        mainChart.clear()
        smallChart.clear()
        let lightBlue = NSUIColor(red: 135/255, green: 206/255, blue: 235/255, alpha: 1.0) // Light Sky Blue
        
        var colors = [NSUIColor]()
        for i in 0..<smbData.count {
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 2
            formatter.minimumIntegerDigits = 0
            
            let bolusShift = findNextBolusTime(timeWithin: 240, needle: smbData[i].date, haystack: smbData, startingIndex: i)
            var dateTimeStamp = smbData[i].date
            
            let nowTime = dateTimeUtils.getNowTimeIntervalUTC()
            let diffTimeHours = (nowTime - dateTimeStamp) / 60 / 60
            if diffTimeHours <= 1 {
                colors.append(lightBlue.withAlphaComponent(1.0))
            } else if diffTimeHours > 6 {
                colors.append(lightBlue.withAlphaComponent(0.25))
            } else {
                let thisAlpha = 1.0 - (0.15 * diffTimeHours)
                colors.append(lightBlue.withAlphaComponent(CGFloat(thisAlpha)))
            }
            
            if bolusShift {
                dateTimeStamp = dateTimeStamp - 150
            }
            
            let graphHours = 24 * UserDefaultsRepository.downloadDays.value
            if dateTimeStamp < dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours) { continue }
            
            let dot = ChartDataEntry(x: Double(dateTimeStamp), y: Double(smbData[i].sgv), data: formatPillText(line1: "SMB\n" + (formatter.string(from: NSNumber(value: smbData[i].value))?.replacingOccurrences(of: ",", with: "."))! + " E", time: dateTimeStamp))
            mainChart.addEntry(dot)
            if UserDefaultsRepository.smallGraphTreatments.value {
                smallChart.addEntry(dot)
            }
        }
        
        BGChart.data?.dataSets[dataIndex].notifyDataSetChanged()
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
        if UserDefaultsRepository.smallGraphTreatments.value {
            BGChartFull.data?.dataSets[dataIndex].notifyDataSetChanged()
            BGChartFull.data?.notifyDataChanged()
            BGChartFull.notifyDataSetChanged()
        }
    }
    
    func updateCarbGraph() {
        var dataIndex = 4
        var mainChart = BGChart.lineData!.dataSets[dataIndex] as! LineChartDataSet
        var smallChart = BGChartFull.lineData!.dataSets[dataIndex] as! LineChartDataSet
        mainChart.clear()
        smallChart.clear()
        
        var colors = [NSUIColor]()
        for i in 0..<carbData.count{
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 2
            formatter.minimumIntegerDigits = 1

            
            let valueStringBase = formatter.string(from: NSNumber(value: carbData[i].value)) ?? "0"
            var valueString = valueStringBase

            let fatString = formatter.string(from: NSNumber(value: carbData[i].fat)) ?? ""
            let proteinString = formatter.string(from: NSNumber(value: carbData[i].protein)) ?? ""

            let rawFoodType = carbData[i].foodType ?? ""
            let foodType = rawFoodType
            let isDextro = rawFoodType.contains("🍬")

            if !rawFoodType.isEmpty {
                valueString += " " + rawFoodType
            }
            
            var hours = 3
            if carbData[i].absorptionTime > 0 && UserDefaultsRepository.showAbsorption.value {
                hours = carbData[i].absorptionTime / 60
                valueString += " " + String(hours) + "h"
            }
            
            // Check overlapping carbs to shift left if needed
            let carbShift = findNextCarbTime(timeWithin: 250, needle: carbData[i].date, haystack: carbData, startingIndex: i)
            var dateTimeStamp = carbData[i].date
            
            // Check condition: if foodType is empty we are most likely dealing with FPUs.
            // Dextro (🍬) markeras separat.
            if rawFoodType.isEmpty {
                colors.append(NSUIColor.systemBrown.withAlphaComponent(0.35))
            } else if isDextro {
                colors.append(NSUIColor.white)
            } else {
                colors.append(NSUIColor.systemOrange.withAlphaComponent(1.0))
            }
            
            // skip if outside of visible area
            let graphHours = 24 * UserDefaultsRepository.downloadDays.value
            if dateTimeStamp < dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours) { continue }
            
            if carbShift {
                dateTimeStamp = dateTimeStamp - 250
            }
            
            /*let dot = ChartDataEntry(x: Double(dateTimeStamp), y: Double(carbData[i].sgv), data: valueString)
            BGChart.data?.dataSets[dataIndex].addEntry(dot)*/
            
            let line2 = "Kolhydrater " + formatter.string(from: NSNumber(value: carbData[i].value))! + " g / Fett " + fatString + " g / Protein " + proteinString + " g"
            let line2FPU = "Kolhydratersekvivalenter " + formatter.string(from: NSNumber(value: carbData[i].value))! + " g"
            let dot = ChartDataEntry(x: Double(dateTimeStamp), y: Double(carbData[i].sgv), data: formatPillTextExtraLine(line1: (foodType.isEmpty ? "Fett/Protein" : "\(foodType)"), line2: (foodType.isEmpty ? line2FPU : line2), time: dateTimeStamp))
             BGChart.data?.dataSets[dataIndex].addEntry(dot)
            if UserDefaultsRepository.smallGraphTreatments.value {
                BGChartFull.data?.dataSets[dataIndex].addEntry(dot)
            }
            
            

        }
        
        // Set Colors
        let lineCarbs = BGChart.lineData!.dataSets[dataIndex] as! LineChartDataSet
        let lineCarbsSmall = BGChartFull.lineData!.dataSets[dataIndex] as! LineChartDataSet
        lineCarbs.colors.removeAll()
        lineCarbs.circleColors.removeAll()
        lineCarbsSmall.colors.removeAll()
        lineCarbsSmall.circleColors.removeAll()
        
        if colors.count > 0 {
            for i in 0..<colors.count{
                mainChart.addColor(colors[i])
                mainChart.circleColors.append(colors[i])
                smallChart.addColor(colors[i])
                smallChart.circleColors.append(colors[i])
            }
        }
        
        BGChart.data?.dataSets[dataIndex].notifyDataSetChanged()
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
        if UserDefaultsRepository.smallGraphTreatments.value {
            BGChartFull.data?.dataSets[dataIndex].notifyDataSetChanged()
            BGChartFull.data?.notifyDataChanged()
            BGChartFull.notifyDataSetChanged()
        }
    }
    
    func updateBGCheckGraph() {
        let dataIndex = 7

        BGChart.lineData?.dataSets[dataIndex].clear()
        BGChartFull.lineData?.dataSets[dataIndex].clear()

        // skip if outside of visible area
        let graphHours = 24 * UserDefaultsRepository.downloadDays.value
        let graphStart = dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours)

        for i in 0..<bgCheckData.count {
            if bgCheckData[i].date < graphStart { continue }

            // Din befintliga pill-text (behåll exakt samma)
            let pill = formatPillText(
                line1: "Fingerstick\n" + Localizer.toDisplayUnits(String(bgCheckData[i].sgv)) + " mmol/L",
                time: bgCheckData[i].date
            )

            // ✅ Huvudgrafen: 15-min “elongated dot”
            let start = Double(bgCheckData[i].date)
            let end = start + (15.0 * 60.0)

            let mainEntry = BGCheckLineChartDataEntry(
                xStart: start,
                xEnd: end,
                y: Double(bgCheckData[i].sgv),
                data: pill
            )
            BGChart.data?.dataSets[dataIndex].addEntry(mainEntry)

            // ✅ Small graph: lämna som dot (ChartDataEntry) för att slippa ändra den logiken
            if UserDefaultsRepository.smallGraphTreatments.value {
                let smallEntry = ChartDataEntry(
                    x: start,
                    y: Double(bgCheckData[i].sgv),
                    data: pill
                )
                BGChartFull.data?.dataSets[dataIndex].addEntry(smallEntry)
            }
        }

        // Notify
        BGChart.data?.dataSets[dataIndex].notifyDataSetChanged()
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()

        if UserDefaultsRepository.smallGraphTreatments.value {
            BGChartFull.data?.dataSets[dataIndex].notifyDataSetChanged()
            BGChartFull.data?.notifyDataChanged()
            BGChartFull.notifyDataSetChanged()
        }

        // Viktigt: säkerställ att vår custom renderer är inkopplad
        updateChartRenderers()
    }
    
    func updateSuspendGraph() {
        var dataIndex = 8
        BGChart.lineData?.dataSets[dataIndex].clear()
        BGChartFull.lineData?.dataSets[dataIndex].clear()
        let thisData = suspendGraphData
        for i in 0..<thisData.count{
            // skip if outside of visible area
            let graphHours = 24 * UserDefaultsRepository.downloadDays.value
            if thisData[i].date < dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours) { continue }
            
            let value = ChartDataEntry(x: Double(thisData[i].date), y: Double(thisData[i].sgv), data: formatPillText(line1: "Pausa pump", time: thisData[i].date))
            BGChart.data?.dataSets[dataIndex].addEntry(value)
            if UserDefaultsRepository.smallGraphTreatments.value {
                BGChartFull.data?.dataSets[dataIndex].addEntry(value)
            }
        }
        
        BGChart.data?.dataSets[dataIndex].notifyDataSetChanged()
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
        if UserDefaultsRepository.smallGraphTreatments.value {
            BGChartFull.data?.dataSets[dataIndex].notifyDataSetChanged()
            BGChartFull.data?.notifyDataChanged()
            BGChartFull.notifyDataSetChanged()
        }
    }
    
    func updateResumeGraph() {
        var dataIndex = 9
        BGChart.lineData?.dataSets[dataIndex].clear()
        BGChartFull.lineData?.dataSets[dataIndex].clear()
        let thisData = resumeGraphData
        for i in 0..<thisData.count{
            // skip if outside of visible area
            let graphHours = 24 * UserDefaultsRepository.downloadDays.value
            if thisData[i].date < dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours) { continue }
            
            let value = ChartDataEntry(x: Double(thisData[i].date), y: Double(thisData[i].sgv), data: formatPillText(line1: "Återuppta pump", time: thisData[i].date))
            BGChart.data?.dataSets[dataIndex].addEntry(value)
            if UserDefaultsRepository.smallGraphTreatments.value {
                BGChartFull.data?.dataSets[dataIndex].addEntry(value)
            }
        }
        
        BGChart.data?.dataSets[dataIndex].notifyDataSetChanged()
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
        if UserDefaultsRepository.smallGraphTreatments.value {
            BGChartFull.data?.dataSets[dataIndex].notifyDataSetChanged()
            BGChartFull.data?.notifyDataChanged()
            BGChartFull.notifyDataSetChanged()
        }
    }
    
    func updateTrainingGraph() {
        let dataIndex = 19//GraphDataIndex.training.rawValue

        guard let mainChart = BGChart.lineData?.dataSets[dataIndex] as? LineChartDataSet,
              let smallChart = BGChartFull.lineData?.dataSets[dataIndex] as? LineChartDataSet else {
            return
        }

        mainChart.clear()
        smallChart.clear()

        var dotEntries: [ChartDataEntry] = []
        var dotColors: [NSUIColor] = []

        for entry in trainingGraphData {
            let dotEntry = ChartDataEntry(
                x: Double(entry.date),
                y: Double(entry.sgv),
                data: formatPillTextExtraLine(
                    line1: "Träning",
                    line2: entry.note,
                    time: entry.date
                )
            )

            dotEntries.append(dotEntry)
            dotColors.append(.systemGreen.withAlphaComponent(0.65))
        }

        let sessionEntries = makeTrainingSessionEntries(from: trainingGraphData)

        // Lägg först in synliga dots
        for dotEntry in dotEntries {
            mainChart.addEntry(dotEntry)
            if UserDefaultsRepository.smallGraphTreatments.value {
                smallChart.addEntry(dotEntry)
            }
        }

        // Lägg sedan in osynliga session-entries som custom renderern använder
        for sessionEntry in sessionEntries {
            mainChart.addEntry(sessionEntry)
            if UserDefaultsRepository.smallGraphTreatments.value {
                smallChart.addEntry(sessionEntry)
            }
        }

        mainChart.colors.removeAll()
        mainChart.circleColors.removeAll()
        smallChart.colors.removeAll()
        smallChart.circleColors.removeAll()

        // Synliga dots
        for _ in dotEntries {
            let color = NSUIColor.systemGreen.withAlphaComponent(0.65)
            mainChart.addColor(color)
            mainChart.circleColors.append(color)
            smallChart.addColor(color)
            smallChart.circleColors.append(color)
        }

        // Osynliga linje-entries
        for _ in sessionEntries {
            mainChart.addColor(.clear)
            mainChart.circleColors.append(.clear)
            smallChart.addColor(.clear)
            smallChart.circleColors.append(.clear)
        }

        mainChart.notifyDataSetChanged()
        smallChart.notifyDataSetChanged()

        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()

        if UserDefaultsRepository.smallGraphTreatments.value {
            BGChartFull.data?.notifyDataChanged()
            BGChartFull.notifyDataSetChanged()
        }
    }
    
    func updateWarningGraph() {
        var dataIndex = 20
        BGChart.lineData?.dataSets[dataIndex].clear()
        BGChartFull.lineData?.dataSets[dataIndex].clear()
        let thisData = warningGraphData
        for i in 0..<thisData.count{
            
            // skip if outside of visible area
            let graphHours = 24 * UserDefaultsRepository.downloadDays.value
            if thisData[i].date < dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours) { continue }
            
            let value = ChartDataEntry(x: Double(thisData[i].date), y: Double(thisData[i].sgv), data: formatPillTextNotes(line1: thisData[i].note, time: thisData[i].date))
            BGChart.data?.dataSets[dataIndex].addEntry(value)
            if UserDefaultsRepository.smallGraphTreatments.value {
                BGChartFull.data?.dataSets[dataIndex].addEntry(value)
            }
        }
        
        BGChart.data?.dataSets[dataIndex].notifyDataSetChanged()
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
        if UserDefaultsRepository.smallGraphTreatments.value {
            BGChartFull.data?.dataSets[dataIndex].notifyDataSetChanged()
            BGChartFull.data?.notifyDataChanged()
            BGChartFull.notifyDataSetChanged()
        }
    }
    
    func updateSensorStart() {
        var dataIndex = 10
        BGChart.lineData?.dataSets[dataIndex].clear()
        BGChartFull.lineData?.dataSets[dataIndex].clear()
        let thisData = sensorStartGraphData
        
        for i in 0..<thisData.count {
            // Skip if outside of visible area
            let graphHours = 24 * UserDefaultsRepository.downloadDays.value
            if thisData[i].date < dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours) { continue }
            
            // Format line1: Always "Sensorbyte" followed by note if available
            let line1 = "Sensorbyte:" + (thisData[i].note?.isEmpty == false ? "\(thisData[i].note!)" : "")

            let value = ChartDataEntry(x: Double(thisData[i].date),
                                       y: Double(thisData[i].sgv),
                                       data: formatPillTextNotes(line1: line1, time: thisData[i].date))

            BGChart.data?.dataSets[dataIndex].addEntry(value)
            if UserDefaultsRepository.smallGraphTreatments.value {
                BGChartFull.data?.dataSets[dataIndex].addEntry(value)
            }
        }

        BGChart.data?.dataSets[dataIndex].notifyDataSetChanged()
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
        if UserDefaultsRepository.smallGraphTreatments.value {
            BGChartFull.data?.dataSets[dataIndex].notifyDataSetChanged()
            BGChartFull.data?.notifyDataChanged()
            BGChartFull.notifyDataSetChanged()
        }
    }
    
    func updatePumpChange() {
        var dataIndex = 18
        BGChart.lineData?.dataSets[dataIndex].clear()
        BGChartFull.lineData?.dataSets[dataIndex].clear()
        let thisData = pumpChangeGraphData
        for i in 0..<thisData.count{
            // skip if outside of visible area
            let graphHours = 24 * UserDefaultsRepository.downloadDays.value
            if thisData[i].date < dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours) { continue }
            
            let value = ChartDataEntry(x: Double(thisData[i].date), y: Double(thisData[i].sgv), data: formatPillText(line1: "Pumpbyte", time: thisData[i].date))
            BGChart.data?.dataSets[dataIndex].addEntry(value)
            if UserDefaultsRepository.smallGraphTreatments.value {
                BGChartFull.data?.dataSets[dataIndex].addEntry(value)
            }
        }
    }
    
    func updateNotes() {
        var dataIndex = 11
        BGChart.lineData?.dataSets[dataIndex].clear()
        BGChartFull.lineData?.dataSets[dataIndex].clear()
        let thisData = noteGraphData
        for i in 0..<thisData.count{
            
            // skip if outside of visible area
            let graphHours = 24 * UserDefaultsRepository.downloadDays.value
            if thisData[i].date < dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours) { continue }
            
            let value = ChartDataEntry(x: Double(thisData[i].date), y: Double(thisData[i].sgv), data: formatPillTextNotes(line1: thisData[i].note, time: thisData[i].date))
            BGChart.data?.dataSets[dataIndex].addEntry(value)
            if UserDefaultsRepository.smallGraphTreatments.value {
                BGChartFull.data?.dataSets[dataIndex].addEntry(value)
            }
        }
        
        BGChart.data?.dataSets[dataIndex].notifyDataSetChanged()
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
        if UserDefaultsRepository.smallGraphTreatments.value {
            BGChartFull.data?.dataSets[dataIndex].notifyDataSetChanged()
            BGChartFull.data?.notifyDataChanged()
            BGChartFull.notifyDataSetChanged()
        }
    }
 
    func createSmallBGGraph(){
        let entries = bgData
       var bgChartEntry = [ChartDataEntry]()
       var colors = [NSUIColor]()
        var maxBG: Float = UserDefaultsRepository.minBGScale.value
        
        let lineBG = LineChartDataSet(entries:bgChartEntry, label: "")
        
        lineBG.drawCirclesEnabled = false
        //line2.setDrawHighlightIndicators(false)
        lineBG.highlightEnabled = true
        lineBG.drawHorizontalHighlightIndicatorEnabled = false
        lineBG.drawVerticalHighlightIndicatorEnabled = false
        lineBG.highlightColor = NSUIColor.label
        lineBG.drawValuesEnabled = false
        lineBG.lineWidth = 1.5
        lineBG.axisDependency = YAxis.AxisDependency.right
        
        // Setup Prediction line details
        var predictionChartEntry = [ChartDataEntry]()
        let linePrediction = LineChartDataSet(entries:predictionChartEntry, label: "")
        linePrediction.drawCirclesEnabled = false
        //line2.setDrawHighlightIndicators(false)
        linePrediction.setColor(NSUIColor.systemPurple)
        linePrediction.highlightEnabled = false
        linePrediction.drawHorizontalHighlightIndicatorEnabled = false
        linePrediction.drawVerticalHighlightIndicatorEnabled = false
        linePrediction.highlightColor = NSUIColor.label
        linePrediction.drawValuesEnabled = false
        linePrediction.lineWidth = 1.5
        linePrediction.axisDependency = YAxis.AxisDependency.right
        
        // create Basal graph data
        var chartEntry = [ChartDataEntry]()
        var maxBasal = UserDefaultsRepository.minBasalScale.value
        let lineBasal = LineChartDataSet(entries:chartEntry, label: "")
        lineBasal.setDrawHighlightIndicators(false)
        lineBasal.setColor(NSUIColor.systemBlue, alpha: 0.4)
        lineBasal.lineWidth = 0
        lineBasal.drawFilledEnabled = true
        lineBasal.fillColor = NSUIColor.systemBlue
        lineBasal.fillAlpha = 0.4
        lineBasal.drawCirclesEnabled = false
        lineBasal.axisDependency = YAxis.AxisDependency.left
        lineBasal.highlightEnabled = false
        lineBasal.drawValuesEnabled = false
        lineBasal.fillFormatter = basalFillFormatter()
        
        // Boluses
        var chartEntryBolus = [ChartDataEntry]()
        let lineBolus = LineChartDataSet(entries:chartEntryBolus, label: "")
        lineBolus.circleRadius = 2
        lineBolus.circleColors = [NSUIColor.systemBlue.withAlphaComponent(0.75)]
        lineBolus.drawCircleHoleEnabled = false
        lineBolus.setDrawHighlightIndicators(false)
        lineBolus.setColor(NSUIColor.systemBlue, alpha: 1.0)
        lineBolus.lineWidth = 0
        lineBolus.axisDependency = YAxis.AxisDependency.right
        lineBolus.valueFormatter = ChartYDataValueFormatter()
        lineBolus.valueTextColor = NSUIColor.label
        lineBolus.fillColor = NSUIColor.systemBlue
        lineBolus.fillAlpha = 0.6
        lineBolus.drawCirclesEnabled = true
        lineBolus.drawFilledEnabled = false
        lineBolus.drawValuesEnabled = false
        lineBolus.highlightEnabled = false
        

        
        // Carbs
        var chartEntryCarbs = [ChartDataEntry]()
        let lineCarbs = LineChartDataSet(entries:chartEntryCarbs, label: "")
        lineCarbs.circleRadius = 2
        lineCarbs.circleColors = [NSUIColor.systemOrange.withAlphaComponent(0.75)]
        lineCarbs.drawCircleHoleEnabled = false
        lineCarbs.setDrawHighlightIndicators(false)
        lineCarbs.setColor(NSUIColor.systemBlue, alpha: 1.0)
        lineCarbs.lineWidth = 0
        lineCarbs.axisDependency = YAxis.AxisDependency.right
        lineCarbs.valueFormatter = ChartYDataValueFormatter()
        lineCarbs.valueTextColor = NSUIColor.label
        lineCarbs.fillColor = NSUIColor.systemOrange
        lineCarbs.fillAlpha = 0.6
        lineCarbs.drawCirclesEnabled = true
        lineCarbs.drawFilledEnabled = false
        lineCarbs.drawValuesEnabled = false
        lineCarbs.highlightEnabled = false
        
        
        
        // create Scheduled Basal graph data
        var chartBasalScheduledEntry = [ChartDataEntry]()
        let lineBasalScheduled = LineChartDataSet(entries:chartBasalScheduledEntry, label: "")
        lineBasalScheduled.setDrawHighlightIndicators(false)
        lineBasalScheduled.setColor(NSUIColor.systemBlue, alpha: 0.8)
        lineBasalScheduled.lineWidth = 0.5
        lineBasalScheduled.drawFilledEnabled = false
        lineBasalScheduled.drawCirclesEnabled = false
        lineBasalScheduled.axisDependency = YAxis.AxisDependency.left
        lineBasalScheduled.highlightEnabled = false
        lineBasalScheduled.drawValuesEnabled = false
        lineBasalScheduled.lineDashLengths = [2, 1]
        
        // create Override graph data
        var chartOverrideEntry = [ChartDataEntry]()
        let lineOverride = LineChartDataSet(entries:chartOverrideEntry, label: "")
        lineOverride.setDrawHighlightIndicators(false)
        lineOverride.lineWidth = 0
        lineOverride.drawFilledEnabled = true
        lineOverride.fillFormatter = OverrideFillFormatter()
        lineOverride.fillColor = NSUIColor.systemPurple.withAlphaComponent(0.7)
        lineOverride.fillAlpha = 0.6
        lineOverride.drawCirclesEnabled = false
        lineOverride.axisDependency = YAxis.AxisDependency.right
        lineOverride.highlightEnabled = false
        lineOverride.drawValuesEnabled = false
        
        // BG Check
        var chartEntryBGCheck = [ChartDataEntry]()
        let lineBGCheck = LineChartDataSet(entries:chartEntryBGCheck, label: "")
        lineBGCheck.circleRadius = 2
        lineBGCheck.circleColors = [NSUIColor.systemRed.withAlphaComponent(0.75)]
        lineBGCheck.drawCircleHoleEnabled = false
        lineBGCheck.setDrawHighlightIndicators(false)
        lineBGCheck.setColor(NSUIColor.systemRed, alpha: 1.0)
        lineBGCheck.drawCirclesEnabled = true
        lineBGCheck.lineWidth = 0
        lineBGCheck.highlightEnabled = false
        lineBGCheck.axisDependency = YAxis.AxisDependency.right
        lineBGCheck.valueFormatter = ChartYDataValueFormatter()
        lineBGCheck.drawValuesEnabled = false
        
        // Suspend Pump
        var chartEntrySuspend = [ChartDataEntry]()
        let lineSuspend = LineChartDataSet(entries:chartEntrySuspend, label: "")
        lineSuspend.circleRadius = 2
        lineSuspend.circleColors = [NSUIColor.systemTeal.withAlphaComponent(0.75)]
        lineSuspend.drawCircleHoleEnabled = false
        lineSuspend.setDrawHighlightIndicators(false)
        lineSuspend.setColor(NSUIColor.systemGray2, alpha: 1.0)
        lineSuspend.drawCirclesEnabled = true
        lineSuspend.lineWidth = 0
        lineSuspend.highlightEnabled = false
        lineSuspend.axisDependency = YAxis.AxisDependency.right
        lineSuspend.valueFormatter = ChartYDataValueFormatter()
        lineSuspend.drawValuesEnabled = false
        
        // Resume Pump
        var chartEntryResume = [ChartDataEntry]()
        let lineResume = LineChartDataSet(entries:chartEntryResume, label: "")
        lineResume.circleRadius = 2
        lineResume.circleColors = [NSUIColor.systemTeal.withAlphaComponent(0.75)]
        lineResume.drawCircleHoleEnabled = false
        lineResume.setDrawHighlightIndicators(false)
        lineResume.setColor(NSUIColor.systemGray4, alpha: 1.0)
        lineResume.drawCirclesEnabled = true
        lineResume.lineWidth = 0
        lineResume.highlightEnabled = false
        lineResume.axisDependency = YAxis.AxisDependency.right
        lineResume.valueFormatter = ChartYDataValueFormatter()
        lineResume.drawValuesEnabled = false
        
        // Training
        var chartEntryTraining = [ChartDataEntry]()
        let lineTraining = LineChartDataSet(entries:chartEntryTraining, label: "")
        lineTraining.circleRadius = 2
        lineTraining.circleColors = [NSUIColor.systemGreen.withAlphaComponent(0.65)]
        lineTraining.drawCircleHoleEnabled = false
        lineTraining.setDrawHighlightIndicators(false)
        lineTraining.setColor(NSUIColor.systemGreen, alpha: 1.0)
        lineTraining.drawCirclesEnabled = true
        lineTraining.lineWidth = 0
        lineTraining.highlightEnabled = false
        lineTraining.axisDependency = YAxis.AxisDependency.right
        lineTraining.valueFormatter = ChartYDataValueFormatter()
        lineTraining.drawValuesEnabled = false
        
        // Warning
        var chartEntryWarning = [ChartDataEntry]()
        let lineWarning = LineChartDataSet(entries:chartEntryWarning, label: "")
        lineWarning.circleRadius = 2
        lineWarning.circleColors = [NSUIColor.systemYellow.withAlphaComponent(0.65)]
        lineWarning.drawCircleHoleEnabled = false
        lineWarning.setDrawHighlightIndicators(false)
        lineWarning.setColor(NSUIColor.systemYellow, alpha: 1.0)
        lineWarning.drawCirclesEnabled = true
        lineWarning.lineWidth = 0
        lineWarning.highlightEnabled = false
        lineWarning.axisDependency = YAxis.AxisDependency.right
        lineWarning.valueFormatter = ChartYDataValueFormatter()
        lineWarning.drawValuesEnabled = false
        
        // Sensor Start
        var chartEntrySensor = [ChartDataEntry]()
        let lineSensor = LineChartDataSet(entries:chartEntrySensor, label: "")
        lineSensor.circleRadius = 2
        lineSensor.circleColors = [NSUIColor.systemTeal.withAlphaComponent(0.75)]
        lineSensor.drawCircleHoleEnabled = false
        lineSensor.setDrawHighlightIndicators(false)
        lineSensor.setColor(NSUIColor.systemGray3, alpha: 1.0)
        lineSensor.drawCirclesEnabled = true
        lineSensor.lineWidth = 0
        lineSensor.highlightEnabled = false
        lineSensor.axisDependency = YAxis.AxisDependency.right
        lineSensor.valueFormatter = ChartYDataValueFormatter()
        lineSensor.drawValuesEnabled = false
        
        // Pump Change
        var chartEntryPump = [ChartDataEntry]()
        let linePump = LineChartDataSet(entries:chartEntryPump, label: "")
        linePump.circleRadius = 2
        linePump.circleColors = [NSUIColor.systemTeal.withAlphaComponent(0.75)]
        linePump.drawCircleHoleEnabled = false
        linePump.setDrawHighlightIndicators(false)
        linePump.setColor(NSUIColor.systemGray3, alpha: 1.0)
        linePump.drawCirclesEnabled = true
        linePump.lineWidth = 0
        linePump.highlightEnabled = false
        linePump.axisDependency = YAxis.AxisDependency.right
        linePump.valueFormatter = ChartYDataValueFormatter()
        linePump.drawValuesEnabled = false
        
        // Notes
        var chartEntryNote = [ChartDataEntry]()
        let lineNote = LineChartDataSet(entries:chartEntryNote, label: "")
        lineNote.circleRadius = 2
        lineNote.circleColors = [NSUIColor.label.withAlphaComponent(0.3)]
        lineNote.drawCircleHoleEnabled = false
        lineNote.setDrawHighlightIndicators(false)
        lineNote.setColor(NSUIColor.systemGray3, alpha: 1.0)
        lineNote.drawCirclesEnabled = true
        lineNote.lineWidth = 0
        lineNote.highlightEnabled = false
        lineNote.axisDependency = YAxis.AxisDependency.right
        lineNote.valueFormatter = ChartYDataValueFormatter()
        lineNote.drawValuesEnabled = false

        // Setup COB Prediction line details
        var COBpredictionChartEntry = [ChartDataEntry]()
        let COBlinePrediction = LineChartDataSet(entries:COBpredictionChartEntry, label: "")
        COBlinePrediction.drawCirclesEnabled = false
        COBlinePrediction.setColor(NSUIColor.systemPurple)
        COBlinePrediction.highlightEnabled = false
        COBlinePrediction.drawHorizontalHighlightIndicatorEnabled = false
        COBlinePrediction.drawVerticalHighlightIndicatorEnabled = false
        COBlinePrediction.highlightColor = NSUIColor.label
        COBlinePrediction.drawValuesEnabled = false
        COBlinePrediction.lineWidth = 1.5
        COBlinePrediction.axisDependency = YAxis.AxisDependency.right

        // Setup IOB Prediction line details
        var IOBpredictionChartEntry = [ChartDataEntry]()
        let IOBlinePrediction = LineChartDataSet(entries:IOBpredictionChartEntry, label: "")
        IOBlinePrediction.drawCirclesEnabled = false
        IOBlinePrediction.setColor(NSUIColor.systemPurple)
        IOBlinePrediction.highlightEnabled = false
        IOBlinePrediction.drawHorizontalHighlightIndicatorEnabled = false
        IOBlinePrediction.drawVerticalHighlightIndicatorEnabled = false
        IOBlinePrediction.highlightColor = NSUIColor.label
        IOBlinePrediction.drawValuesEnabled = false
        IOBlinePrediction.lineWidth = 1.5
        IOBlinePrediction.axisDependency = YAxis.AxisDependency.right

        // Setup UAM Prediction line details
        var UAMpredictionChartEntry = [ChartDataEntry]()
        let UAMlinePrediction = LineChartDataSet(entries:UAMpredictionChartEntry, label: "")
        UAMlinePrediction.drawCirclesEnabled = false
        UAMlinePrediction.setColor(NSUIColor.systemPurple)
        UAMlinePrediction.highlightEnabled = false
        UAMlinePrediction.drawHorizontalHighlightIndicatorEnabled = false
        UAMlinePrediction.drawVerticalHighlightIndicatorEnabled = false
        UAMlinePrediction.highlightColor = NSUIColor.label
        UAMlinePrediction.drawValuesEnabled = false
        UAMlinePrediction.lineWidth = 1.5
        UAMlinePrediction.axisDependency = YAxis.AxisDependency.right

        // Setup ZT Prediction line details
        var ZTpredictionChartEntry = [ChartDataEntry]()
        let ZTlinePrediction = LineChartDataSet(entries:ZTpredictionChartEntry, label: "")
        ZTlinePrediction.drawCirclesEnabled = false
        ZTlinePrediction.setColor(NSUIColor.systemPurple)
        ZTlinePrediction.highlightEnabled = false
        ZTlinePrediction.drawHorizontalHighlightIndicatorEnabled = false
        ZTlinePrediction.drawVerticalHighlightIndicatorEnabled = false
        ZTlinePrediction.highlightColor = NSUIColor.label
        ZTlinePrediction.drawValuesEnabled = false
        ZTlinePrediction.lineWidth = 1.5
        ZTlinePrediction.axisDependency = YAxis.AxisDependency.right
        
        // SMB
        var chartEntrySmb = [ChartDataEntry]()
        let lineSmb = LineChartDataSet(entries:chartEntrySmb, label: "")
        lineSmb.circleRadius = 2
        lineSmb.circleColors = [NSUIColor.systemBlue.withAlphaComponent(0.75)]
        lineSmb.drawCircleHoleEnabled = false
        lineSmb.setDrawHighlightIndicators(false)
        lineSmb.setColor(NSUIColor.systemBlue, alpha: 1.0)
        lineSmb.lineWidth = 0
        lineSmb.axisDependency = YAxis.AxisDependency.right
        lineSmb.valueFormatter = ChartYDataValueFormatter()
        lineSmb.valueTextColor = NSUIColor.label
        lineSmb.fillColor = NSUIColor.systemBlue
        lineSmb.fillAlpha = 0.6
        lineSmb.drawCirclesEnabled = true
        lineSmb.drawFilledEnabled = false
        lineSmb.drawValuesEnabled = false
        lineSmb.highlightEnabled = false

        // Temp Target graph data
        let chartTempTargetEntry = [ChartDataEntry]()
        let lineTempTarget = LineChartDataSet(entries:chartTempTargetEntry, label: "")
        lineTempTarget.setDrawHighlightIndicators(false)
        lineTempTarget.lineWidth = 0
        lineTempTarget.drawFilledEnabled = false
        lineTempTarget.fillColor = NSUIColor.systemPurple
        lineTempTarget.fillAlpha = 0.6
        lineTempTarget.drawCirclesEnabled = false
        lineTempTarget.axisDependency = YAxis.AxisDependency.right
        lineTempTarget.highlightEnabled = false
        lineTempTarget.drawValuesEnabled = false

        // Setup the chart data of all lines
        let data = LineChartData()
        data.append(lineBG) // Dataset 0
        data.append(linePrediction) // Dataset 1
        data.append(lineBasal) // Dataset 2
        data.append(lineBolus) // Dataset 3
        data.append(lineCarbs) // Dataset 4
        data.append(lineBasalScheduled) // Dataset 5
        data.append(lineOverride) // Dataset 6
        data.append(lineBGCheck) // Dataset 7
        data.append(lineSuspend) // Dataset 8
        data.append(lineResume) // Dataset 9
        data.append(lineSensor) // Dataset 10
        data.append(lineNote) // Dataset 11
        data.append(ZTlinePrediction) // Dataset 12
        data.append(IOBlinePrediction) // Dataset 13
        data.append(COBlinePrediction) // Dataset 14
        data.append(UAMlinePrediction) // Dataset 15
        data.append(lineSmb) // Dataset 16
        data.append(lineTempTarget) // Dataset 17
        data.append(linePump) // Dataset 18
        data.append(lineTraining) // Dataset 19
        data.append(lineWarning) // Dataset 20

        BGChartFull.highlightPerDragEnabled = true
        BGChartFull.leftAxis.enabled = false
        BGChartFull.leftAxis.axisMaximum = maxBasal
        BGChartFull.leftAxis.axisMinimum = 0
        BGChartFull.leftAxis.axisLineColor = .clear
        
        BGChartFull.rightAxis.enabled = false
        BGChartFull.rightAxis.axisMinimum = 0.0
        BGChartFull.rightAxis.axisMaximum = Double(maxBG)
        BGChartFull.rightAxis.axisLineColor = .clear
                                               
        BGChartFull.xAxis.drawLabelsEnabled = false
        BGChartFull.xAxis.drawGridLinesEnabled = false
        BGChartFull.xAxis.drawAxisLineEnabled = false
        BGChartFull.legend.enabled = false
        BGChartFull.scaleYEnabled = false
        BGChartFull.scaleXEnabled = false
        BGChartFull.drawGridBackgroundEnabled = false
        BGChartFull.data = data
    }
    // Daniel: Test to make override attach to top regardless of mmol or mgdl
    func updateOverrideGraph() {
        let dataIndex = 6
        // Calculate dynamic maximum (in mg/dL) from your data.
        let dynamicMax = Double(calculateMaxBgGraphValue())
        
        // If using mmol/L, force the maximum to a multiple of 90 mg/dL.
        let chartMax: Double
        if UserDefaultsRepository.units.value == "mmol/L" {
            chartMax = ceil(dynamicMax / 72.0) * 72.0
        } else {
            chartMax = dynamicMax
        }
        
        // Use the chartMax as the top of the override rectangle.
        let yTop: Double = chartMax
        // Set yBottom to be 20 mg/dL (or adjust as needed) below the top.
        let yBottom: Double = chartMax - 25
        
        // Retrieve the override data chart datasets.
        let chart = BGChart.lineData!.dataSets[dataIndex] as! LineChartDataSet
        let smallChart = BGChartFull.lineData!.dataSets[dataIndex] as! LineChartDataSet
        chart.clear()
        smallChart.clear()
        
        let thisData = overrideGraphData
        for i in 0..<thisData.count {
            let thisItem = thisData[i]
            // Format a label for the override data entry.
            let labelText = formatPillTextExtraLine(
                line1: thisItem.notes ?? "--",
                line2: "Varaktighet: " + String(format:"%.0f", (thisItem.duration / 60)) + " min",
                time: thisItem.date
            )
            
            // Create entries for the override rectangle.
            // Pre-start: lower point at yBottom.
            let preStartDot = ChartDataEntry(x: Double(thisItem.date), y: yBottom, data: labelText)
            chart.addEntry(preStartDot)
            if UserDefaultsRepository.smallGraphTreatments.value {
                BGChartFull.data?.dataSets[dataIndex].addEntry(preStartDot)
            }
            
            // Start dot: at yTop.
            let startDot = ChartDataEntry(x: Double(thisItem.date + 1), y: yTop, data: labelText)
            chart.addEntry(startDot)
            if UserDefaultsRepository.smallGraphTreatments.value {
                BGChartFull.data?.dataSets[dataIndex].addEntry(startDot)
            }
            
            // End dot: at yTop.
            let endDot = ChartDataEntry(x: Double(thisItem.endDate - 2), y: yTop, data: labelText)
            chart.addEntry(endDot)
            if UserDefaultsRepository.smallGraphTreatments.value {
                BGChartFull.data?.dataSets[dataIndex].addEntry(endDot)
            }
            
            // Post end dot: lower point at yBottom.
            let postEndDot = ChartDataEntry(x: Double(thisItem.endDate - 1), y: yBottom, data: labelText)
            chart.addEntry(postEndDot)
            if UserDefaultsRepository.smallGraphTreatments.value {
                BGChartFull.data?.dataSets[dataIndex].addEntry(postEndDot)
            }
        }
        
        // Notify the charts that the override data has been updated.
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
        if UserDefaultsRepository.smallGraphTreatments.value {
            BGChartFull.data?.notifyDataChanged()
            BGChartFull.notifyDataSetChanged()
        }
    }

    func getChartDataSets(for index: GraphDataIndex) -> (chart: LineChartDataSet?, smallChart: LineChartDataSet?) {
        guard let chart = BGChart.lineData,
              index.rawValue < chart.dataSets.count,
              let smallChartData = BGChartFull.lineData,
              index.rawValue < smallChartData.dataSets.count else {
            //print("Warning: Invalid GraphDataIndex \(index.description) or lineData is nil.")
            return (nil, nil)
        }

        let chartDataSet = chart.dataSets[index.rawValue] as? LineChartDataSet
        let smallChartDataSet = smallChartData.dataSets[index.rawValue] as? LineChartDataSet

        return (chartDataSet, smallChartDataSet)
    }

    func addEntryToCharts(entry: ChartDataEntry, chart: LineChartDataSet, smallChart: LineChartDataSet?) {
        chart.addEntry(entry)
        if UserDefaultsRepository.smallGraphTreatments.value, let smallChart = smallChart {
            smallChart.addEntry(entry)
        }
    }

    func updateTempTargetGraph() {
        let dataIndex = GraphDataIndex.tempTarget.rawValue
        guard let chartData = BGChart.lineData,
              chartData.dataSets.count > dataIndex,
              let mainChartDataSet = chartData.dataSets[dataIndex] as? LineChartDataSet else {
            LogManager.shared.log(category: .general, message: "Error: Could not retrieve temp target datasets.", isDebug: true)

            return
        }

        mainChartDataSet.clear()

        var smallChartDataSet: LineChartDataSet?
        if UserDefaultsRepository.smallGraphTreatments.value,
           let smallChartData = BGChartFull.lineData,
           smallChartData.dataSets.count > dataIndex,
           let smallDataSet = smallChartData.dataSets[dataIndex] as? LineChartDataSet {
            smallChartDataSet = smallDataSet
            smallChartDataSet?.clear()
        }

        let thisData = tempTargetGraphData

        for tempTarget in thisData {
            let xStart = tempTarget.date
            let xEnd = tempTarget.endDate
            let yCenter = Double(tempTarget.correctionRange[0])
            let yTop = yCenter + 5.0
            let yBottom = yCenter - 5.0

            let entry = TempTargetChartDataEntry(
                xStart: xStart,
                xEnd: xEnd,
                yTop: yTop,
                yBottom: yBottom,
                data: nil
            )
            mainChartDataSet.addEntry(entry)

            if let smallDataSet = smallChartDataSet {
                smallDataSet.addEntry(entry)
            }
        }

        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()

        if let smallDataSet = smallChartDataSet {
            let tempTargetRendererSmall = TempTargetRenderer(
                dataProvider: BGChartFull,
                animator: BGChartFull.chartAnimator,
                viewPortHandler: BGChartFull.viewPortHandler,
                tempTargetDataSetIndex: dataIndex
            )
            BGChartFull.renderer = tempTargetRendererSmall

            BGChartFull.data?.notifyDataChanged()
            BGChartFull.notifyDataSetChanged()
        }
    }

    func wrapText(_ text: String, maxLineLength: Int) -> String {
        var lines: [String] = []
        var currentLine = ""

        let words = text.components(separatedBy: .whitespacesAndNewlines)
        for word in words {
            if word.count > maxLineLength {
                var wordToProcess = word
                while !wordToProcess.isEmpty {
                    let spaceCount = currentLine.isEmpty ? 0 : 1
                    let availableSpace = maxLineLength - (currentLine.count + spaceCount)

                    if availableSpace <= 0 {
                        if !currentLine.isEmpty {
                            lines.append(currentLine)
                            currentLine = ""
                        }
                        continue
                    }

                    let takeCount = min(wordToProcess.count, availableSpace)
                    if takeCount <= 0 {
                        if !currentLine.isEmpty {
                            lines.append(currentLine)
                            currentLine = ""
                        }
                        continue
                    }

                    let index = wordToProcess.index(wordToProcess.startIndex, offsetBy: takeCount)
                    let substring = wordToProcess[..<index]

                    if currentLine.isEmpty {
                        currentLine = String(substring)
                    } else {
                        currentLine += " " + substring
                    }

                    wordToProcess = String(wordToProcess[index...])

                    if currentLine.count >= maxLineLength {
                        lines.append(currentLine)
                        currentLine = ""
                    }
                }
            } else {
                let spaceNeeded = currentLine.isEmpty ? 0 : 1
                if currentLine.count + spaceNeeded + word.count > maxLineLength {
                    lines.append(currentLine)
                    currentLine = word
                } else {
                    if currentLine.isEmpty {
                        currentLine = word
                    } else {
                        currentLine += " " + word
                    }
                }
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines.joined(separator: "\r\n")
    }

        func formatPillText(line1: String, time: TimeInterval) -> String {
            let dateFormatter = DateFormatter()
            //let timezoneOffset = TimeZone.current.secondsFromGMT()
            //let epochTimezoneOffset = value + Double(timezoneOffset)
            if dateTimeUtils.is24Hour() {
                dateFormatter.setLocalizedDateFormatFromTemplate("HH:mm")
            } else {
                dateFormatter.setLocalizedDateFormatFromTemplate("hh:mm")
            }
            
            //let date = Date(timeIntervalSince1970: epochTimezoneOffset)
            let date = Date(timeIntervalSince1970: time)
            let formattedDate = dateFormatter.string(from: date)

            return line1 + "\r\n" + formattedDate
        }
        
        func formatPillTextNotes(line1: String, time: TimeInterval) -> String {
            let dateFormatter = DateFormatter()
            //let timezoneOffset = TimeZone.current.secondsFromGMT()
            //let epochTimezoneOffset = value + Double(timezoneOffset)
            if dateTimeUtils.is24Hour() {
                dateFormatter.setLocalizedDateFormatFromTemplate("HH:mm")
            } else {
                dateFormatter.setLocalizedDateFormatFromTemplate("hh:mm")
            }
            
            let wrappedLine1 = wrapText(line1, maxLineLength: 35)
            
            //let date = Date(timeIntervalSince1970: epochTimezoneOffset)
            let date = Date(timeIntervalSince1970: time)
            let formattedDate = dateFormatter.string(from: date)

            return wrappedLine1 + "\r\n" + formattedDate
        }
        
        func formatPillTextExtraLine(line1: String, line2: String, time: TimeInterval) -> String {
            let dateFormatter = DateFormatter()
            //let timezoneOffset = TimeZone.current.secondsFromGMT()
            //let epochTimezoneOffset = value + Double(timezoneOffset)
            if dateTimeUtils.is24Hour() {
                dateFormatter.setLocalizedDateFormatFromTemplate("HH:mm")
            } else {
                dateFormatter.setLocalizedDateFormatFromTemplate("hh:mm")
            }
            
            
            //let date = Date(timeIntervalSince1970: epochTimezoneOffset)
            let date = Date(timeIntervalSince1970: time)
            let formattedDate = dateFormatter.string(from: date)
            
            return line1 + "\r\n" + line2 + "\r\n" + formattedDate
        }
    
    // Daniel: Test even mmol yaxis tick marks
    func updatePredictionGraphGeneric(
        dataIndex: Int,
        predictionData: [ShareGlucoseData],
        chartLabel: String,
        color: UIColor
    ) {
        let mainChart = BGChart.lineData!.dataSets[dataIndex] as! LineChartDataSet
        let smallChart = BGChartFull.lineData!.dataSets[dataIndex] as! LineChartDataSet
        mainChart.clear()
        smallChart.clear()
        
        var colors = [NSUIColor]()
        let maxBGOffset: Float = 18
        
        for i in 0..<predictionData.count {
            let predictionVal = Double(predictionData[i].sgv)
            if Float(predictionVal) > topPredictionBG - maxBGOffset {
                topPredictionBG = Float(predictionVal) + maxBGOffset
            }
            
            if i == 0 {
                if UserDefaultsRepository.showDots.value {
                    colors.append(color.withAlphaComponent(0.0))
                } else {
                    colors.append(color.withAlphaComponent(1.0))
                }
            } else {
                colors.append(color)
            }
            
            let value = ChartDataEntry(
                x: predictionData[i].date,
                y: predictionVal,
                data: formatPillText(
                    line1: chartLabel,
                    time: predictionData[i].date
                    // Optionally add line2 if needed.
                )
            )
            mainChart.addEntry(value)
            smallChart.addEntry(value)
        }
        
        smallChart.circleColors.removeAll()
        smallChart.colors.removeAll()
        mainChart.colors.removeAll()
        mainChart.circleColors.removeAll()
        for clr in colors {
            mainChart.addColor(clr)
            mainChart.circleColors.append(clr)
            smallChart.addColor(clr)
            smallChart.circleColors.append(clr)
        }
        
        // Calculate the current maximum (in mg/dL) from the data.
        let currentMaxBG = calculateMaxBgGraphValue()
        
        if UserDefaultsRepository.units.value == "mmol/L" {
            let forcedMax = ceil(Double(currentMaxBG) / 72.0) * 72.0
            BGChart.rightAxis.axisMaximum = forcedMax
            BGChartFull.rightAxis.axisMaximum = forcedMax
            
            let labelCount = Int(forcedMax / 72.0) + 1
            BGChart.rightAxis.forceLabelsEnabled = true
            BGChart.rightAxis.setLabelCount(labelCount, force: true)
            BGChart.rightAxis.granularityEnabled = true
            BGChart.rightAxis.granularity = 72
            
            BGChartFull.rightAxis.forceLabelsEnabled = true
            BGChartFull.rightAxis.setLabelCount(labelCount, force: true)
            BGChartFull.rightAxis.granularityEnabled = true
            BGChartFull.rightAxis.granularity = 72
        } else {
            BGChart.rightAxis.axisMaximum = Double(currentMaxBG)
            BGChartFull.rightAxis.axisMaximum = Double(currentMaxBG)
            
            BGChart.rightAxis.forceLabelsEnabled = false
            BGChart.rightAxis.granularityEnabled = true
            BGChart.rightAxis.granularity = 50
            
            BGChartFull.rightAxis.forceLabelsEnabled = false
            BGChartFull.rightAxis.granularityEnabled = true
            BGChartFull.rightAxis.granularity = 50
        }
        
        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
        BGChartFull.data?.notifyDataChanged()
        BGChartFull.notifyDataSetChanged()
    }
    /// Simulates and plots 0.05 U temp basal pulses at the bottom of the chart
    func updateTempBasalPulses() {
        guard let data = BGChart.data else { return }
        // The last dataset in our chart is the pulse set
        let idx = data.dataSets.count - 1
        let pulseSet = data.dataSets[idx] as! LineChartDataSet
        pulseSet.clear()

        // Use actual basalData rates for pulse simulation
        let sortedBasals = basalData.sorted { $0.date < $1.date }
        for (i, entry) in sortedBasals.enumerated() {
            // Define segment start/end in chart X-axis domain
            let segmentStart = max(entry.date, BGChart.xAxis.axisMinimum)
            let segmentEnd: TimeInterval = {
                if i + 1 < sortedBasals.count {
                    return min(sortedBasals[i+1].date, BGChart.xAxis.axisMaximum)
                } else {
                    return BGChart.xAxis.axisMaximum
                }
            }()
            guard segmentStart < segmentEnd else { continue }
            let rate = entry.basalRate
            guard rate > 0 else { continue }

            let ratePerSec = rate / 3600.0
            var t = segmentStart
            // Simulate 0.05 U pulses without carry‑over
            while true {
                let dt = 0.05 / ratePerSec
                if t + dt > segmentEnd { break }
                t += dt
                // Plot at bottom (x is epoch seconds)
                pulseSet.addEntry(ChartDataEntry(x: t, y: 0))
            }
        }

        // Refresh chart display
        pulseSet.notifyDataSetChanged()
        data.notifyDataChanged()
        BGChart.notifyDataSetChanged()
    }
}
