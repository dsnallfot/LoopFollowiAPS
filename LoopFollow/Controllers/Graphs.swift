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
        }
    }
}

class CompositeRenderer: LineChartRenderer {
    let tempTargetRenderer: TempTargetRenderer
    let triangleRenderer: TriangleRenderer

    init(dataProvider: LineChartDataProvider?, animator: Animator?, viewPortHandler: ViewPortHandler?, tempTargetDataSetIndex: Int, smbDataSetIndex: Int) {
        self.tempTargetRenderer = TempTargetRenderer(
            dataProvider: dataProvider,
            animator: animator,
            viewPortHandler: viewPortHandler,
            tempTargetDataSetIndex: tempTargetDataSetIndex
        )
        self.triangleRenderer = TriangleRenderer(
            dataProvider: dataProvider,
            animator: animator,
            viewPortHandler: viewPortHandler,
            smbDataSetIndex: smbDataSetIndex
        )
        super.init(dataProvider: dataProvider!, animator: animator!, viewPortHandler: viewPortHandler!)
    }

    override func drawExtras(context: CGContext) {
        super.drawExtras(context: context)
        tempTargetRenderer.drawExtras(context: context)
        // Daniel: Do not draw those triangles for smbs // triangleRenderer.drawExtras(context: context)
    }
}

class TriangleRenderer: LineChartRenderer {
    let smbDataSetIndex: Int
    
    init(dataProvider: LineChartDataProvider?, animator: Animator?, viewPortHandler: ViewPortHandler?, smbDataSetIndex: Int) {
        self.smbDataSetIndex = smbDataSetIndex
        super.init(dataProvider: dataProvider!, animator: animator!, viewPortHandler: viewPortHandler!)
    }
    
    override func drawExtras(context: CGContext) {
        super.drawExtras(context: context)
        
        guard let dataProvider = dataProvider else { return }
        
        if dataProvider.lineData?.dataSets.count ?? 0 > smbDataSetIndex, let lineDataSet = dataProvider.lineData?.dataSets[smbDataSetIndex] as? LineChartDataSet {
            let trans = dataProvider.getTransformer(forAxis: lineDataSet.axisDependency)
            let phaseY = animator.phaseY
            
            for j in 0 ..< lineDataSet.entryCount {
                guard let e = lineDataSet.entryForIndex(j) else { continue }
                
                let pt = trans.pixelForValues(x: e.x, y: e.y * phaseY)
                
                context.saveGState()
                context.beginPath()
                context.move(to: CGPoint(x: pt.x, y: pt.y + 9))
                context.addLine(to: CGPoint(x: pt.x - 5, y: pt.y - 1))
                context.addLine(to: CGPoint(x: pt.x + 5, y: pt.y - 1))
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

let ScaleXMax:Float = 150.0
extension MainViewController {
    func updateChartRenderers() {
        let tempTargetDataIndex = GraphDataIndex.tempTarget.rawValue
        let smbDataIndex = GraphDataIndex.smb.rawValue

        let compositeRenderer = CompositeRenderer(
            dataProvider: BGChart,
            animator: BGChart.chartAnimator,
            viewPortHandler: BGChart.viewPortHandler,
            tempTargetDataSetIndex: tempTargetDataIndex,
            smbDataSetIndex: smbDataIndex
        )
        BGChart.renderer = compositeRenderer

        BGChart.data?.notifyDataChanged()
        BGChart.notifyDataSetChanged()
    }
    
    func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
        if chartView == BGChartFull {
            BGChart.moveViewToX(entry.x)
        }
        if entry.data as? String == "hide"{
            BGChart.highlightValue(nil, callDelegate: false)
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
            lineBG.lineWidth = 2
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
            linePrediction.lineWidth = 2
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
        lineBGCheck.drawCirclesEnabled = true
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
        
        // Sensor Start
        let chartEntrySensor = [ChartDataEntry]()
        let lineSensor = LineChartDataSet(entries:chartEntrySensor, label: "")
        lineSensor.circleRadius = CGFloat(globalVariables.dotOther)
        lineSensor.circleColors = [NSUIColor.label.withAlphaComponent(0.5)]
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
        linePump.circleColors = [NSUIColor.label.withAlphaComponent(0.5)]
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
        lineNote.circleColors = [NSUIColor.label.withAlphaComponent(0.5)]
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
        COBlinePrediction.highlightEnabled = true
        COBlinePrediction.drawValuesEnabled = false
        
        if UserDefaultsRepository.showLines.value {
            COBlinePrediction.lineWidth = 2
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
        IOBlinePrediction.highlightEnabled = true
        IOBlinePrediction.drawValuesEnabled = false
        
        if UserDefaultsRepository.showLines.value {
            IOBlinePrediction.lineWidth = 2
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
        UAMlinePrediction.highlightEnabled = true
        UAMlinePrediction.drawValuesEnabled = false
        
        if UserDefaultsRepository.showLines.value {
            UAMlinePrediction.lineWidth = 2
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
        ZTlinePrediction.highlightEnabled = true
        ZTlinePrediction.drawValuesEnabled = false
        
        if UserDefaultsRepository.showLines.value {
            ZTlinePrediction.lineWidth = 2
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
        data.append(lineTempTarget)
        data.append(linePump)
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
        ll.lineColor = NSUIColor.systemRed.withAlphaComponent(0.5)
        BGChart.rightAxis.addLimitLine(ll)
        
        //Add upper yellow line based on high alert value
        let ul = ChartLimitLine()
        ul.limit = Double(UserDefaultsRepository.highLine.value)
        if UserDefaultsRepository.colorBGText.value {
            ul.lineColor = NSUIColor.systemPurple.withAlphaComponent(0.5)
        } else {
            ul.lineColor = NSUIColor.systemYellow.withAlphaComponent(0.5)
        }
        BGChart.rightAxis.addLimitLine(ul)
        
        //Daniel: Add mid green line based on target value
        let tl = ChartLimitLine()
        tl.limit = Double(UserDefaultsRepository.targetLine.value)
        tl.lineColor = NSUIColor.systemGreen.withAlphaComponent(0.2)
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

        BGChart.leftAxis.enabled = true
        BGChart.leftAxis.labelPosition = YAxis.LabelPosition.insideChart
        BGChart.leftAxis.axisMaximum = maxBasal
        BGChart.leftAxis.axisMinimum = 0
        BGChart.leftAxis.drawGridLinesEnabled = false
        BGChart.leftAxis.granularityEnabled = true
        BGChart.leftAxis.granularity = 0.5

        BGChart.rightAxis.labelTextColor = NSUIColor.label
        BGChart.rightAxis.labelPosition = YAxis.LabelPosition.insideChart
        BGChart.rightAxis.axisMinimum = 0.0

        if UserDefaultsRepository.units.value == "mmol/L" {
            let forcedMax = ceil(Double(maxBG) / 72.0) * 72.0
            BGChart.rightAxis.axisMaximum = forcedMax
            BGChart.rightAxis.gridLineDashLengths = [5.0, 5.0]
            BGChart.rightAxis.drawGridLinesEnabled = false
            BGChart.rightAxis.valueFormatter = ChartYMMOLValueFormatter()
            BGChart.rightAxis.granularityEnabled = true
            BGChart.rightAxis.granularity = 72
            let labelCount = Int(forcedMax / 72.0) + 1
            BGChart.rightAxis.forceLabelsEnabled = true
            BGChart.rightAxis.setLabelCount(labelCount, force: true)
        } else {
            BGChart.rightAxis.axisMaximum = Double(maxBG)
            BGChart.rightAxis.gridLineDashLengths = [5.0, 5.0]
            BGChart.rightAxis.drawGridLinesEnabled = false
            BGChart.rightAxis.valueFormatter = ChartYMMOLValueFormatter()
            BGChart.rightAxis.granularityEnabled = true
            BGChart.rightAxis.granularity = 50
        }
            
        BGChart.maxHighlightDistance = 15.0
        BGChart.legend.enabled = false
        BGChart.scaleYEnabled = false
        BGChart.drawGridBackgroundEnabled = true
        BGChart.gridBackgroundColor = NSUIColor.secondarySystemBackground
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
        ul.lineWidth = 1
        BGChart.xAxis.addLimitLine(ul)
        
        // Small chart
        let sl = ChartLimitLine()
        sl.limit = Double(dateTimeUtils.getNowTimeIntervalUTC())
        sl.lineColor = NSUIColor.label
        sl.lineDashLengths = [CGFloat(2), CGFloat(2)]
        sl.lineWidth = 1
        BGChartFull.xAxis.addLimitLine(sl)
        
        if UserDefaultsRepository.show30MinLine.value {
            let ul2 = ChartLimitLine()
            ul2.limit = Double(dateTimeUtils.getNowTimeIntervalUTC().advanced(by: -30 * 60))
            ul2.lineColor = NSUIColor.systemBlue.withAlphaComponent(0.5)
            ul2.lineWidth = 1
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
        if UserDefaultsRepository.show90MinLine.value {
            // Large chart
            let ul3 = ChartLimitLine()
            ul3.limit = Double(dateTimeUtils.getNowTimeIntervalUTC().advanced(by: -1440 * 60))
            ul3.lineColor = NSUIColor.systemOrange.withAlphaComponent(0.8)
            ul3.lineDashLengths = [CGFloat(4), CGFloat(2)]
            ul3.lineWidth = 1
            BGChart.xAxis.addLimitLine(ul3)
            
            // Small chart
            let sl3 = ChartLimitLine()
            sl3.limit = Double(dateTimeUtils.getNowTimeIntervalUTC().advanced(by: -1440 * 60))
            sl3.lineColor = NSUIColor.systemOrange.withAlphaComponent(0.8)
            sl3.lineDashLengths = [CGFloat(2), CGFloat(2)]
            sl3.lineWidth = 1
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
                ul.lineWidth = 1
                BGChart.xAxis.addLimitLine(ul)

                // Small chart
                let sl = ChartLimitLine()
                sl.limit = Double(midnightTimeInterval)
                sl.lineColor = NSUIColor.systemIndigo //.withAlphaComponent(0.7)
                sl.lineDashLengths = [CGFloat(2), CGFloat(2)]
                sl.lineWidth = 1
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
        ll.limit = Double(UserDefaultsRepository.lowLine.value)
        ll.lineColor = NSUIColor.systemRed.withAlphaComponent(0.5)
        BGChart.rightAxis.addLimitLine(ll)
        
        //Add upper purple line based on low alert value
        let ul = ChartLimitLine()
        ul.limit = Double(UserDefaultsRepository.highLine.value)
        if UserDefaultsRepository.colorBGText.value {
            ul.lineColor = NSUIColor.systemPurple.withAlphaComponent(0.5)
        } else {
            ul.lineColor = NSUIColor.systemYellow.withAlphaComponent(0.5)
        }
        BGChart.rightAxis.addLimitLine(ul)
        
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
  
            let dot = ChartDataEntry(x: Double(dateTimeStamp), y: Double(bolusData[i].sgv), data: formatPillTextExtraLine(line1: "Bolus", line2: formatter.string(from: NSNumber(value: bolusData[i].value))! + " E", time: dateTimeStamp))
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
            
            let dot = ChartDataEntry(x: Double(dateTimeStamp), y: Double(smbData[i].sgv), data: formatPillText(line1: "SMB\n" + formatter.string(from: NSNumber(value: smbData[i].value))! + " E", time: dateTimeStamp))
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

            
            var valueString: String = formatter.string(from: NSNumber(value: carbData[i].value))!
            
            var fatString: String = formatter.string(from: NSNumber(value: carbData[i].fat)) ?? ""
            
            var proteinString: String = formatter.string(from: NSNumber(value: carbData[i].protein)) ?? ""
            
            guard var foodType = String?(carbData[i].foodType ?? "") else { return }
            if (carbData[i].foodType != nil) {
                valueString += " " + foodType
            }
            
            var hours = 3
            if carbData[i].absorptionTime > 0 && UserDefaultsRepository.showAbsorption.value {
                hours = carbData[i].absorptionTime / 60
                valueString += " " + String(hours) + "h"
            }
            
            // Check overlapping carbs to shift left if needed
            let carbShift = findNextCarbTime(timeWithin: 250, needle: carbData[i].date, haystack: carbData, startingIndex: i)
            var dateTimeStamp = carbData[i].date
            
            // Check condition: if foodType is empty we are most likely dealing with FPUs
            if (carbData[i].foodType ?? "").isEmpty {
                colors.append(NSUIColor.systemBrown.withAlphaComponent(0.35))
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
        var dataIndex = 7
        BGChart.lineData?.dataSets[dataIndex].clear()
        BGChartFull.lineData?.dataSets[dataIndex].clear()
        
        for i in 0..<bgCheckData.count{
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 2
            formatter.minimumIntegerDigits = 1
            
            // skip if outside of visible area
            let graphHours = 24 * UserDefaultsRepository.downloadDays.value
            if bgCheckData[i].date < dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours) { continue }
            
            let value = ChartDataEntry(x: Double(bgCheckData[i].date), y: Double(bgCheckData[i].sgv), data: formatPillText(line1: "Fingerstick\n" + Localizer.toDisplayUnits(String(bgCheckData[i].sgv)) + " mmol/L", time: bgCheckData[i].date))
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
        linePrediction.highlightEnabled = true
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
        lineOverride.highlightEnabled = true
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
        
        // Sensor Start
        var chartEntrySensor = [ChartDataEntry]()
        let lineSensor = LineChartDataSet(entries:chartEntrySensor, label: "")
        lineSensor.circleRadius = 2
        lineSensor.circleColors = [NSUIColor.label.withAlphaComponent(0.5)]
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
        linePump.circleColors = [NSUIColor.label.withAlphaComponent(0.5)]
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
        lineNote.circleColors = [NSUIColor.label.withAlphaComponent(0.5)]
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
        COBlinePrediction.highlightEnabled = true
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
        IOBlinePrediction.highlightEnabled = true
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
        UAMlinePrediction.highlightEnabled = true
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
        ZTlinePrediction.highlightEnabled = true
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
        data.append(lineTempTarget)
        data.append(linePump)

        BGChartFull.highlightPerDragEnabled = true
        BGChartFull.leftAxis.enabled = false
        BGChartFull.leftAxis.axisMaximum = maxBasal
        BGChartFull.leftAxis.axisMinimum = 0
        
        BGChartFull.rightAxis.enabled = false
        BGChartFull.rightAxis.axisMinimum = 0.0
        BGChartFull.rightAxis.axisMaximum = Double(maxBG)
                                               
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
                line1: thisItem.notes ?? "N/A",
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
