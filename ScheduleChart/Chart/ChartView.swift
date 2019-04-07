//
//  ChartView.swift
//  ScheduleChart
//
//  Created by Alexander Graschenkov on 10/03/2019.
//  Copyright © 2019 Alex the Best. All rights reserved.
//

import UIKit

class ChartView: UIView {
    struct Range {
        var from: Float
        var to: Float
    }
    
    struct RangeI {
        var from: Int64
        var to: Int64
    }
    
    var drawGrid: Bool = true
    var gridColor: UIColor = UIColor(white: 0.9, alpha: 1.0) {
        didSet { verticalAxe.gridColor = gridColor }
    }
    var showZeroYValue: Bool = true
    var drawOutsideChart: Bool = false
    var lineWidth: CGFloat = 2.0
    var selectedDate: Int64? {
        didSet {
            if selectedDate == oldValue { return }
            setNeedsDisplay()
        }
    }
    lazy var verticalAxe: VerticalAxe = VerticalAxe(view: self)
    lazy var horisontalAxe: HorisontalAxe = HorisontalAxe(view: self)
    let labelsPool: LabelsPool = LabelsPool()
    
    var data: [ChartData] = [] {
        didSet {
            if display == nil {
                display = LinesDisplayBehavior(view: self)
            }
            dataMinTime = -1
            dataMaxTime = -1
            for d in data {
                if dataMinTime < 0 {
                    dataMinTime = d.items.first!.time
                    dataMaxTime = d.items.last!.time
                    continue
                }
                dataMinTime = min(dataMinTime, d.items.first!.time)
                dataMaxTime = max(dataMaxTime, d.items.last!.time)
            }
            displayRange = RangeI(from: dataMinTime, to: dataMaxTime)
            dataAlpha = Array(repeating: 1.0, count: data.count)
            display.data = data
            setNeedsDisplay()
        }
    }
    var shapeLayers: [CAShapeLayer] = []
    var dataAlpha: [CGFloat] {
        get { return display.dataAlpha }
        set { display.dataAlpha = newValue }
    }
    var display: BaseDisplayBehavior!
    private(set) var dataMinTime: Int64 = -1
    private(set) var dataMaxTime: Int64 = -1
    var displayRange: RangeI = RangeI(from: 0, to: 0)
//    var displayVerticalRange: Range = Range(from: 0, to: 200)
    var maxValue: Float = 200
    var maxValueAnimation: Float? = nil
    var onDrawDebug: (()->())?
    var maxValAnimatorCancel: Cancelable?
    var rangeAnimatorCancel: Cancelable?
    var chartInset = UIEdgeInsets(top: 0, left: 40, bottom: 30, right: 30)
    var endAnimationFlag = false
    
    var isMaxValAnimating: Bool {
        return maxValueAnimation != nil
    }
    
    override var frame: CGRect {
        didSet {
            if oldValue.size == frame.size { return }
            setNeedsDisplay()
        }
    }
    
    func setMaxVal(val: Float, animationDuration: Double) {
        if let maxValueAnimation = maxValueAnimation {
            if animationDuration > 0 && maxValueAnimation == val { return }
        } else if maxValue == val, maxValueAnimation == nil {
            return
        }
        
        maxValAnimatorCancel?()
        if animationDuration > 0 {
            maxValueAnimation = val
            let fromMaxVal = maxValue
            maxValAnimatorCancel = DisplayLinkAnimator.animate(duration: animationDuration) { (percent) in
                self.maxValue = (val - fromMaxVal) * Float(percent) + fromMaxVal
                self.setNeedsDisplay()
                if percent == 1 {
                    self.maxValueAnimation = nil
                    self.endAnimationFlag = true
                }
            }
        } else {
            maxValue = val
            maxValueAnimation = nil
            self.setNeedsDisplay()
        }
        
        if drawGrid {
            verticalAxe.setMaxVal(val, animationDuration: animationDuration)
        }
    }
    
    func setRange(minTime: Int64, maxTime: Int64, animated: Bool) {
        rangeAnimatorCancel?()
        if !animated {
            displayRange.from = minTime
            displayRange.to = maxTime
            if maxValueAnimation == nil {
                // little hack: if we ave animation with redraws, do not need to call redraw here
                setNeedsDisplay()
            }
            horisontalAxe.setRange(minTime: displayRange.from, maxTime: displayRange.to, animationDuration: 0.2)
            // TODO
            return
        }
        
        let fromRange = displayRange
        rangeAnimatorCancel = DisplayLinkAnimator.animate(duration: 0.5, closure: { (percent) in
            self.displayRange.from = Int64(CGFloat(minTime - fromRange.from) * percent) + fromRange.from
            self.displayRange.to = Int64(CGFloat(maxTime - fromRange.to) * percent) + fromRange.to
            self.setNeedsDisplay()
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
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
       
        guard let ctx = UIGraphicsGetCurrentContext() else {
            return
        }
        
        onDrawDebug?()
        if drawGrid {
            if verticalAxe.maxVal == nil {
                verticalAxe.setMaxVal(maxValue)
            }
            verticalAxe.drawGrid(ctx: ctx, inset: chartInset)
            if horisontalAxe.maxTime == 0 && data.count > 0 {
                horisontalAxe.setRange(minTime: displayRange.from, maxTime: displayRange.to)
            }
            if rangeAnimatorCancel != nil {
                horisontalAxe.layoutLabels()
            }
        }
        
        var chartRect = bounds.inset(by: chartInset)
        
        var fromTime = displayRange.from
        var toTime = displayRange.to
        if drawOutsideChart {
            (chartRect, fromTime, toTime) = expandDrawRange(rect: chartRect,
                                                            inset: chartInset,
                                                            from: fromTime,
                                                            to: toTime)
        } else {
            ctx.clip(to: chartRect)
        }
        if let selected = selectedDate {
            ctx.setStrokeColor(gridColor.cgColor)
            let x = convertPos(time: selected, val: 0, inRect: chartRect, fromTime: fromTime, toTime: toTime).x
            ctx.move(to: CGPoint(x: x, y: chartRect.minY))
            ctx.addLine(to: CGPoint(x: x, y: chartRect.maxY))
            ctx.strokePath()
        }
        let force = endAnimationFlag
        endAnimationFlag = false
        display.update(maxValue: maxValue, displayRange: RangeI(from: fromTime, to: toTime), rect: chartRect, force: force)
    }
    
    
    private func drawSelection(_ data: ChartData, selectedDate: Int64, alpha: CGFloat, ctx: CGContext, from: Int64, to: Int64, inRect rect: CGRect) {
        guard let val = data.items.first(where: {$0.time == selectedDate})?.value else {
            return
        }
        let pos = convertPos(time: selectedDate, val: val, inRect: rect, fromTime: from, toTime: to)
        let or = lineWidth*2
        ctx.setFillColor(data.color.cgColor)
        let outCircle = CGRect(x: pos.x - or, y: pos.y - or, width: 2*or, height: 2*or)
        ctx.fillEllipse(in: outCircle)
        
        let bgColor = backgroundColor ?? UIColor.white
        ctx.setFillColor(bgColor.cgColor)
        let ir = or - lineWidth
        let innerCircle = CGRect(x: pos.x - ir, y: pos.y - ir, width: 2*ir, height: 2*ir)
        ctx.fillEllipse(in: innerCircle)
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
