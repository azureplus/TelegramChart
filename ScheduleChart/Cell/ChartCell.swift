//
//  ChartCell.swift
//  ScheduleChart
//
//  Created by Alexander Graschenkov on 12/04/2019.
//  Copyright © 2019 Alex the Best. All rights reserved.
//

import UIKit


class ChartCell: UITableViewCell {

    @IBOutlet weak var chart: ChartCopmosedView!
    @IBOutlet weak var selectChart: SelectChartDisplayedView!
    var groupData: ChartGroupData?
    private static let chartHeight: CGFloat = 400
    
    
    
    static func getHeight(withData data: ChartGroupData, width: CGFloat) -> CGFloat {
        let selectHeight: CGFloat = SelectChartDisplayedView.getHeightAndLayout(groupData: data, fixedWidth: width)
        return ChartCell.chartHeight + selectHeight
    }
    
    func display(groupData: ChartGroupData) {
        self.groupData = groupData
        chart.data = groupData
        selectChart.display(groupData: groupData)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        chart.frame = CGRect(x: 0, y: 0, width: bounds.width, height: ChartCell.chartHeight)
        selectChart.frame = bounds.inset(by: UIEdgeInsets(top: ChartCell.chartHeight, left: 0, bottom: 0, right: 0))
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        selectChart.displayDelegate = self
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}

extension ChartCell: SelectChartDisplayedViewDelegate {
    func chartDataRequestDisplayChange(index: Int, display: Bool) -> Bool {
        guard let groupData = groupData else {
            return false
        }
        var displayCount = 0
        for (idx, d) in groupData.data.enumerated() {
            let isVisible = (idx == index) ? display : d.visible
            if isVisible {
                displayCount += 1
            }
        }
        if displayCount == 0 {
            return false
        }
        
        groupData.data[index].visible = display
        chart.setDisplayData(index: index, display: display, animated: true)
        return true
    }
    
    func displayOnly(index: Int) {
        guard let groupData = groupData else {
            return
        }
        for i in 0..<groupData.data.count {
            groupData.data[i].visible = (i == index)
        }
        chart.setDisplayDataOnly(index: index, animated: true)
    }
}
