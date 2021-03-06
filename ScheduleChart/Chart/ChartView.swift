//
//  ChartView.swift
//  ScheduleChart
//
//  Created by Alexander Graschenkov on 10/03/2019.
//  Copyright © 2019 Alex the Best. All rights reserved.
//

import UIKit
import MetalKit

struct Color {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
    var a: CGFloat
    
    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
    
    init(w: CGFloat, a: CGFloat) {
        self.r = w
        self.g = w
        self.b = w
        self.a = a
    }
    
    init(color: UIColor) {
        r = 0; g = 0; b = 0; a = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
    }
    
    var uiColor: UIColor {
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
    
    var metalClear: MTLClearColor {
        return MTLClearColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }
    
    var vector: vector_float4 {
        return vector_float4(Float(r), Float(g), Float(b), Float(a))
    }
}

extension UIColor {
    var myColor: Color {
        return Color(color: self)
    }
}

class ChartView: UIView {
    struct RangeI {
        var from: Int64
        var to: Int64
    }
    
    var drawGrid: Bool = true
    var gridColor: Color = Color(w: 0.45, a: 0.2)
    var drawOutsideChart: Bool = true
    var selectedDate: Int64? {
        didSet {
            if selectedDate == oldValue { return }
            metal.display.setSelectionDate(date: selectedDate)
        }
    }
    var isSelectionView: Bool = false {
        didSet {
            metal?.isSelectionChart = isSelectionView
        }
    }
    lazy var verticalAxe: VerticalAxe = VerticalAxe(view: self)
    lazy var horisontalAxe: HorisontalAxe = HorisontalAxe(view: self)
    let labelsPool: LabelsPool = LabelsPool()
    var metal: MetalChartView!
    
    var data: ChartGroupData? {
        didSet {
            guard let groupData = data else {
                cleanUp()
                return
            }
            
            setupMetal()
            dataMinTime = groupData.getMinTime()
            dataMaxTime = groupData.getMaxTime()
            displayRange = RangeI(from: dataMinTime, to: dataMaxTime)
            dataAlpha = groupData.data.map({$0.visible ? CGFloat(1.0) : CGFloat(0.0)})
            horisontalAxe.setRange(minTime: displayRange.from, maxTime: displayRange.to)
            
            metal.setupWithData(data: groupData)
            metal.isHidden = false
            metalUpdateDisplay()
        }
    }
    var shapeLayers: [CAShapeLayer] = []
    var dataAlpha: [CGFloat] = [] {
        didSet {
            metal?.display?.dataAlpha = dataAlpha
        }
    }
    private(set) var dataMinTime: Int64 = -1
    private(set) var dataMaxTime: Int64 = -1
    var displayRange: RangeI = RangeI(from: 0, to: 0)
    var maxValue: Float = 200
    var minValue: Float = 0
    var minMaxValueAnimation: (Float, Float)? = nil
    var onDrawDebug: (()->())?
    var maxValAnimatorCancel: Cancelable?
    var rangeAnimatorCancel: Cancelable?
    var chartInset = UIEdgeInsets(top: 0, left: 40, bottom: 30, right: 30)
    var onMinMaxValueAnimChange: (()->())?
    
    var isMaxValAnimating: Bool {
        return minMaxValueAnimation != nil
    }
    
    private func setupMetal() {
        if metal != nil { return }
        metal = MetalChartView(frame: bounds)
        metal.isSelectionChart = isSelectionView
        metal.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        metal.setupBuffers(maxChartDataCount: 8, maxChartItemsCount: 400)
        insertSubview(metal, at: 0)
//        metalUpdateDisplay()
    }
    
    private func cleanUp() {
        metal?.isHidden = true
    }
    
    override var frame: CGRect {
        didSet {
            if oldValue.size == frame.size { return }
            metalUpdateDisplay()
        }
    }
    
    func setMaxVal(val: Float, minVal: Float = 0, animationDuration: Double) {
        if let (minValAnim, maxValueAnim) = minMaxValueAnimation {
            if animationDuration > 0 && maxValueAnim == val && minValAnim == minVal { return }
        } else if maxValue == val, minValue == minVal, minMaxValueAnimation == nil {
            return
        }
        
        maxValAnimatorCancel?()
        if animationDuration > 0 {
            minMaxValueAnimation = (val, minVal)
            let fromMaxVal = maxValue
            let fromMinVal = minValue
            maxValAnimatorCancel = DisplayLinkAnimator.animate(duration: animationDuration) { (percent) in
                let percent = -percent * (percent - 2) // ease out
                self.maxValue = (val - fromMaxVal) * Float(percent) + fromMaxVal
                self.minValue = (minVal - fromMinVal) * Float(percent) + fromMinVal
                self.onMinMaxValueAnimChange?()
                
                if self.drawGrid {
                    self.verticalAxe.updateLabelsPos(inset: self.chartInset)
                    self.updateLevels()
                }
                
                self.metalUpdateDisplay()
                if percent == 1 {
                    self.minMaxValueAnimation = nil
                }
            }
        } else {
            maxValue = val
            minValue = minVal
            minMaxValueAnimation = nil
            metalUpdateDisplay()
        }
        
        if drawGrid {
            verticalAxe.setMaxVal(val, minVal: minVal, animationDuration: animationDuration)
            
            if animationDuration == 0 {
                verticalAxe.updateLabelsPos(inset: chartInset)
                updateLevels()
            }
        }
    }
    
    func setRange(minTime: Int64, maxTime: Int64, animated: Bool) {
        rangeAnimatorCancel?()
        if !animated {
            displayRange.from = minTime
            displayRange.to = maxTime
            if minMaxValueAnimation == nil {
                // little hack: if we ave animation with redraws, do not need to call redraw here
                metalUpdateDisplay()
            }
            horisontalAxe.setRange(minTime: displayRange.from, maxTime: displayRange.to, animationDuration: 0.2)
            // TODO
            return
        }
        
        let fromRange = displayRange
        rangeAnimatorCancel = DisplayLinkAnimator.animate(duration: 0.5, closure: { (percent) in
            self.displayRange.from = Int64(CGFloat(minTime - fromRange.from) * percent) + fromRange.from
            self.displayRange.to = Int64(CGFloat(maxTime - fromRange.to) * percent) + fromRange.to
            self.metalUpdateDisplay()
            if percent == 1 {
                self.rangeAnimatorCancel = nil
            }
        })
        
        horisontalAxe.setRange(minTime: minTime, maxTime: maxTime, animationDuration: 0.5)
    }
    
    func getDate(forPos pos: CGPoint) -> Int64? {
        if displayRange.from == 0 && displayRange.to == 0 {
            return nil
        }
        
        let from = displayRange.from
        let to = displayRange.to
        let rect = bounds.inset(by: chartInset)
        let percent = (pos.x - rect.minX) / rect.width
        let time = Int64(CGFloat(to - from) * percent) + from
        return time
    }
    
    func getXPos(date: Int64) -> CGFloat {
        let chartRect = bounds.inset(by: chartInset)
        let x = convertPos(time: date,
                           val: 0,
                           inRect: chartRect,
                           fromTime: displayRange.from,
                           toTime: displayRange.to).x
        return x
    }
    
    func updateLevels() {
        metal.updateLevels(levels: self.getLevels())
    }
    
    func getLevels() -> [LineAlpha] {
        return subviews.compactMap({ lab->LineAlpha? in
            guard let lab = lab as? AttachedLabel, let val = lab.attachedValue, lab.alpha > 0 else {
                return nil
            }
            
            let vec = vector_float4(Float(gridColor.r),
                                    Float(gridColor.g),
                                    Float(gridColor.b),
                                    Float(gridColor.a*lab.alpha))
            return LineAlpha(y: val, color: vec)
        })
    }
    
    func metalUpdateDisplay() {
        var chartRect = bounds.inset(by: chartInset)
        if displayRange.to - displayRange.from == 0 {
            return
        }
        
        var fromTime = displayRange.from
        var toTime = displayRange.to
        if drawOutsideChart {
            (chartRect, fromTime, toTime) = expandDrawRange(rect: chartRect,
                                                            inset: chartInset,
                                                            from: fromTime,
                                                            to: toTime)
        }
        
        metal?.display.update(minValue: minValue, maxValue: maxValue, displayRange: RangeI(from: fromTime, to: toTime), rect: chartRect)
        metal?.setNeedsDisplay()
    }
    
    
    func calculateTransform() -> CGAffineTransform {
        let fromTime = CGFloat(displayRange.from)
        let toTime = CGFloat(displayRange.to)
        let maxVal = CGFloat(maxValue)
        let minVal = CGFloat(minValue)
        let rect = bounds.inset(by: chartInset)
        
        var t: CGAffineTransform = .identity
        let scaleX = rect.width / (toTime - fromTime)
        t = t.translatedBy(x: rect.minX, y: rect.maxY)
        t = t.scaledBy(x: scaleX, y: -rect.height / (maxVal - minVal))
        t = t.translatedBy(x: -fromTime, y: -minVal)
        return t
    }
    
    private func convertPos(time: Int64, val: Float, inRect rect: CGRect, fromTime: Int64, toTime: Int64) -> CGPoint {
        let xPercent = Float(time - fromTime) / Float(toTime - fromTime)
        let x = rect.origin.x + rect.width * CGFloat(xPercent)
        let yPercent = val / maxValue
        let y = rect.maxY - rect.height * CGFloat(yPercent)
        return CGPoint(x: x, y: y)
    }
}

private extension ChartView { // Data draw helpers
    func expandDrawRange(rect: CGRect, inset: UIEdgeInsets, from: Int64, to: Int64) -> (CGRect, Int64, Int64) {
        let leftRectPercent = inset.left / rect.width
        let leftTimePercent = CGFloat(dataMinTime - from) / CGFloat(from - to)
        let leftPercent = min(leftRectPercent, leftTimePercent)
        
        let rightRectPercent = inset.right / rect.width
        let rightTimePercent = CGFloat(dataMaxTime - to) / CGFloat(to - from)
        let rightPercent = min(rightRectPercent, rightTimePercent)
        
        let drawRect = rect.inset(by: UIEdgeInsets(top: 0,
                                                   left: -leftPercent * rect.width,
                                                   bottom: 0,
                                                   right: -rightPercent * rect.width))
        let drawFrom = from + Int64(CGFloat(from - to) * leftPercent)
        let drawTo = to + Int64(CGFloat(to - from) * rightPercent)
        
        return (drawRect, drawFrom, drawTo)
    }
}
