import SwiftUI
import DGCharts

// MARK: - K线图容器（UIKit桥接）
@available(iOS 14.0, *)
struct CandleChartContainer: UIViewRepresentable {
    let klines: [Kline]
    let viewModel: ChartViewModel
    
    func makeUIView(context: Context) -> CandleStickChartView {
        let chart = CandleStickChartView()
        configureChart(chart)
        chart.data = createChartData()
        return chart
    }
    
    func updateUIView(_ uiView: CandleStickChartView, context: Context) {
        uiView.data = createChartData()
        uiView.notifyDataSetChanged()
    }
    
    private func configureChart(_ chart: CandleStickChartView) {
        chart.backgroundColor = UIColor(AppColors.background)
        chart.gridBackgroundColor = UIColor(AppColors.cardBackground)
        
        // X轴
        let xAxis = chart.xAxis
        xAxis.labelPosition = .bottom
        xAxis.labelTextColor = UIColor(AppColors.textTertiary)
        xAxis.gridColor = UIColor(AppColors.cardBorder)
        xAxis.avoidFirstLastClippingEnabled = true
        xAxis.granularity = 1
        xAxis.setLabelCount(6, force: false)
        xAxis.valueFormatter = IndexAxisValueFormatter(
            values: klines.enumerated().map { (i, k) in
                if i % max(1, klines.count / 6) == 0 || i == klines.count - 1 {
                    return k.date.toKlineTimeString(period: viewModel.selectedPeriod)
                }
                return ""
            }
        )
        
        // 左Y轴
        let leftAxis = chart.leftAxis
        leftAxis.labelTextColor = UIColor(AppColors.textTertiary)
        leftAxis.gridColor = UIColor(AppColors.cardBorder)
        leftAxis.labelPosition = .outsideChart
        
        // 右Y轴
        let rightAxis = chart.rightAxis
        rightAxis.enabled = false
        
        chart.legend.enabled = false
        chart.doubleTapToZoomEnabled = false
        chart.pinchZoomEnabled = true
        chart.scaleXEnabled = true
        chart.scaleYEnabled = false
        chart.drawGridBackgroundEnabled = false
        chart.borderColor = UIColor(AppColors.cardBorder)
        chart.borderLineWidth = 0.5
        chart.drawBordersEnabled = true
    }
    
    private func createChartData() -> CandleChartData {
        var entries: [CandleChartDataEntry] = []
        
        for (i, kline) in klines.enumerated() {
            let entry = CandleChartDataEntry(
                x: Double(i),
                shadowH: kline.high,
                shadowL: kline.low,
                open: kline.open,
                close: kline.close
            )
            entries.append(entry)
        }
        
        let dataSet = CandleChartDataSet(entries: entries, label: "")
        dataSet.axisDependency = .left
        dataSet.shadowColorSameAsCandle = true
        dataSet.shadowWidth = 0.7
        dataSet.decreasingColor = UIColor(AppColors.green)
        dataSet.decreasingFilled = true
        dataSet.increasingColor = UIColor(AppColors.red)
        dataSet.increasingFilled = true
        dataSet.neutralColor = UIColor(AppColors.textSecondary)
        dataSet.valueTextColor = UIColor.clear
        dataSet.drawValuesEnabled = false
        
        // MA叠加
        if viewModel.showMA {
            addLineDataSet(to: dataSet, values: viewModel.computeMA(period: 5), color: AppColors.indicatorMA)
            addLineDataSet(to: dataSet, values: viewModel.computeMA(period: 10), color: AppColors.indicatorEMA)
            addLineDataSet(to: dataSet, values: viewModel.computeMA(period: 20), color: AppColors.textSecondary)
        }
        
        if viewModel.showEMA {
            addLineDataSet(to: dataSet, values: viewModel.computeEMA(period: 12), color: AppColors.indicatorEMA)
            addLineDataSet(to: dataSet, values: viewModel.computeEMA(period: 26), color: AppColors.indicatorRSI)
        }
        
        if viewModel.showBOLL {
            let boll = viewModel.computeBOLL()
            addLineDataSet(to: dataSet, values: boll.upper.map { $0 }, color: AppColors.textTertiary)
            addLineDataSet(to: dataSet, values: boll.middle.map { $0 }, color: AppColors.gold)
            addLineDataSet(to: dataSet, values: boll.lower.map { $0 }, color: AppColors.textTertiary)
        }
        
        return CandleChartData(dataSets: [dataSet] + extraDataSets)
    }
    
    private var extraDataSets: [ChartDataSetProtocol] {
        var sets: [ChartDataSetProtocol] = []
        
        if viewModel.showMA {
            sets.append(createLineDataSet(values: viewModel.computeMA(period: 5), color: AppColors.indicatorMA, label: "MA5"))
            sets.append(createLineDataSet(values: viewModel.computeMA(period: 10), color: AppColors.indicatorEMA, label: "MA10"))
            sets.append(createLineDataSet(values: viewModel.computeMA(period: 20), color: AppColors.textSecondary, label: "MA20"))
        }
        
        if viewModel.showEMA {
            sets.append(createLineDataSet(values: viewModel.computeEMA(period: 12), color: AppColors.indicatorEMA, label: "EMA12"))
            sets.append(createLineDataSet(values: viewModel.computeEMA(period: 26), color: AppColors.indicatorRSI, label: "EMA26"))
        }
        
        if viewModel.showBOLL {
            let boll = viewModel.computeBOLL()
            sets.append(createLineDataSet(values: boll.upper.map { $0 }, color: AppColors.textTertiary, label: "UP"))
            sets.append(createLineDataSet(values: boll.middle.map { $0 }, color: AppColors.gold, label: "MID"))
            sets.append(createLineDataSet(values: boll.lower.map { $0 }, color: AppColors.textTertiary, label: "LOW"))
        }
        
        return sets
    }
    
    private func createLineDataSet(values: [Double?], color: Color, label: String) -> LineChartDataSet {
        let entries: [ChartDataEntry] = values.enumerated().compactMap { (i, v) in
            guard let v = v else { return nil }
            return ChartDataEntry(x: Double(i), y: v)
        }
        let dataSet = LineChartDataSet(entries: entries, label: label)
        dataSet.color = UIColor(color)
        dataSet.lineWidth = 0.8
        dataSet.drawCirclesEnabled = false
        dataSet.drawValuesEnabled = false
        dataSet.axisDependency = .left
        return dataSet
    }
    
    private func addLineDataSet(to set: CandleChartDataSet, values: [Double?], color: Color) {
        // 这里简化处理，实际MA线通过extraDataSets添加
    }
}

// MARK: - MACD副图
@available(iOS 14.0, *)
struct MACDChartView: UIViewRepresentable {
    let macd: MACDResult
    let klineCount: Int
    
    func makeUIView(context: Context) -> BarLineChartViewBase {
        let chart = CombinedChartView()
        chart.backgroundColor = UIColor(AppColors.background)
        
        let xAxis = chart.xAxis
        xAxis.labelPosition = .bottom
        xAxis.labelTextColor = UIColor(AppColors.textTertiary)
        xAxis.gridColor = UIColor(AppColors.cardBorder)
        xAxis.setLabelCount(4, force: false)
        xAxis.drawLabelsEnabled = false
        
        let leftAxis = chart.leftAxis
        leftAxis.labelTextColor = UIColor(AppColors.textTertiary)
        leftAxis.gridColor = UIColor(AppColors.cardBorder)
        leftAxis.labelPosition = .outsideChart
        
        let rightAxis = chart.rightAxis
        rightAxis.enabled = false
        
        chart.legend.enabled = false
        chart.doubleTapToZoomEnabled = false
        chart.pinchZoomEnabled = false
        chart.drawGridBackgroundEnabled = false
        
        chart.data = createCombinedData()
        return chart
    }
    
    func updateUIView(_ uiView: BarLineChartViewBase, context: Context) {
        if let combined = uiView as? CombinedChartView {
            combined.data = createCombinedData()
            combined.notifyDataSetChanged()
        }
    }
    
    private func createCombinedData() -> CombinedChartData {
        let data = CombinedChartData()
        
        // DIF线
        let difEntries: [ChartDataEntry] = macd.dif.enumerated().compactMap { (i, v) in
            guard let v = v else { return nil }
            return ChartDataEntry(x: Double(i), y: v)
        }
        let difSet = LineChartDataSet(entries: difEntries, label: "DIF")
        difSet.color = UIColor(AppColors.gold)
        difSet.lineWidth = 1
        difSet.drawCirclesEnabled = false
        difSet.drawValuesEnabled = false
        
        // DEA线
        let deaEntries: [ChartDataEntry] = macd.dea.enumerated().compactMap { (i, v) in
            guard let v = v else { return nil }
            return ChartDataEntry(x: Double(i), y: v)
        }
        let deaSet = LineChartDataSet(entries: deaEntries, label: "DEA")
        deaSet.color = UIColor(AppColors.indicatorRSI)
        deaSet.lineWidth = 0.8
        deaSet.drawCirclesEnabled = false
        deaSet.drawValuesEnabled = false
        
        // 柱状图
        let barEntries: [BarChartDataEntry] = macd.histogram.enumerated().compactMap { (i, v) in
            guard let v = v else { return nil }
            return BarChartDataEntry(x: Double(i), y: v)
        }
        let barSet = BarChartDataSet(entries: barEntries, label: "MACD")
        barSet.drawValuesEnabled = false
        barSet.colors = barEntries.map { entry in
            UIColor(entry.y >= 0 ? AppColors.red : AppColors.green)
        }
        
        let lineData = LineChartData(dataSets: [difSet, deaSet])
        let barData = BarChartData(dataSets: [barSet])
        barData.barWidth = 0.5
        
        data.lineData = lineData
        data.barData = barData
        
        return data
    }
}

// MARK: - KDJ副图
@available(iOS 14.0, *)
struct KDJChartView: UIViewRepresentable {
    let kdj: KDJResult
    
    func makeUIView(context: Context) -> LineChartView {
        let chart = LineChartView()
        chart.backgroundColor = UIColor(AppColors.background)
        
        let xAxis = chart.xAxis
        xAxis.labelPosition = .bottom
        xAxis.labelTextColor = UIColor(AppColors.textTertiary)
        xAxis.gridColor = UIColor(AppColors.cardBorder)
        xAxis.setLabelCount(4, force: false)
        xAxis.drawLabelsEnabled = false
        
        let leftAxis = chart.leftAxis
        leftAxis.labelTextColor = UIColor(AppColors.textTertiary)
        leftAxis.gridColor = UIColor(AppColors.cardBorder)
        leftAxis.axisMinimum = 0
        leftAxis.axisMaximum = 100
        
        let rightAxis = chart.rightAxis
        rightAxis.enabled = false
        
        chart.legend.enabled = false
        chart.doubleTapToZoomEnabled = false
        chart.pinchZoomEnabled = false
        chart.drawGridBackgroundEnabled = false
        
        chart.data = createLineData()
        return chart
    }
    
    func updateUIView(_ uiView: LineChartView, context: Context) {
        uiView.data = createLineData()
        uiView.notifyDataSetChanged()
    }
    
    private func createLineData() -> LineChartData {
        let colors: [(String, [Double?], UIColor)] = [
            ("K", kdj.k, UIColor(AppColors.gold)),
            ("D", kdj.d, UIColor(AppColors.indicatorRSI)),
            ("J", kj, UIColor(AppColors.green))
        ]
        
        let dataSets: [LineChartDataSet] = colors.map { (name, values, color) in
            let entries: [ChartDataEntry] = values.enumerated().compactMap { (i, v) in
                guard let v = v else { return nil }
                return ChartDataEntry(x: Double(i), y: v)
            }
            let set = LineChartDataSet(entries: entries, label: name)
            set.color = color
            set.lineWidth = 0.8
            set.drawCirclesEnabled = false
            set.drawValuesEnabled = false
            return set
        }
        
        return LineChartData(dataSets: dataSets)
    }
    
    // J值 = 3K - 2D
    private var kj: [Double?] {
        zip(kdj.k, kdj.d).map { (k, d) -> Double? in
            guard let k = k, let d = d else { return nil }
            return 3 * k - 2 * d
        }
    }
}

// MARK: - 单线指标副图（RSI, W%R, OBV, ATR）
@available(iOS 14.0, *)
struct LineIndicatorChartView: UIViewRepresentable {
    let values: [Double?]
    let name: String
    let overbought: Double?
    let oversold: Double?
    let color: Color
    
    func makeUIView(context: Context) -> LineChartView {
        let chart = LineChartView()
        chart.backgroundColor = UIColor(AppColors.background)
        
        let xAxis = chart.xAxis
        xAxis.labelPosition = .bottom
        xAxis.labelTextColor = UIColor(AppColors.textTertiary)
        xAxis.gridColor = UIColor(AppColors.cardBorder)
        xAxis.setLabelCount(4, force: false)
        xAxis.drawLabelsEnabled = false
        
        let leftAxis = chart.leftAxis
        leftAxis.labelTextColor = UIColor(AppColors.textTertiary)
        leftAxis.gridColor = UIColor(AppColors.cardBorder)
        if let ob = overbought, let os = oversold {
            leftAxis.axisMinimum = os - 10
            leftAxis.axisMaximum = ob + 10
        }
        
        let rightAxis = chart.rightAxis
        rightAxis.enabled = false
        
        chart.legend.enabled = false
        chart.doubleTapToZoomEnabled = false
        chart.pinchZoomEnabled = false
        chart.drawGridBackgroundEnabled = false
        
        chart.data = createLineData()
        return chart
    }
    
    func updateUIView(_ uiView: LineChartView, context: Context) {
        uiView.data = createLineData()
        uiView.notifyDataSetChanged()
    }
    
    private func createLineData() -> LineChartData {
        let entries: [ChartDataEntry] = values.enumerated().compactMap { (i, v) in
            guard let v = v else { return nil }
            return ChartDataEntry(x: Double(i), y: v)
        }
        
        let dataSet = LineChartDataSet(entries: entries, label: name)
        dataSet.color = UIColor(color)
        dataSet.lineWidth = 1
        dataSet.drawCirclesEnabled = false
        dataSet.drawValuesEnabled = false
        
        return LineChartData(dataSets: [dataSet])
    }
}
