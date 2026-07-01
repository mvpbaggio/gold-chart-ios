import SwiftUI
import DGCharts

// MARK: - K线图容器（UIKit桥接）
@available(iOS 14.0, *)
struct CandleChartContainer: UIViewRepresentable {
    let klines: [Kline]
    let viewModel: ChartViewModel
    
    func makeUIView(context: Context) -> CandleStickChartView {
        let chart = CandleStickChartView()
        configureChart(chart, context: context)
        chart.data = createChartData()
        chart.marker = SignalMarkerView(viewModel: viewModel)
        return chart
    }
    
    func updateUIView(_ uiView: CandleStickChartView, context: Context) {
        uiView.data = createChartData()
        uiView.marker = SignalMarkerView(viewModel: viewModel)
        // 每帧刷新坐标轴（支持动态K线延伸）
        updateAxes(uiView)
        uiView.notifyDataSetChanged()
    }
    
    private func updateAxes(_ chart: CandleStickChartView) {
        let xAxis = chart.xAxis
        xAxis.valueFormatter = IndexAxisValueFormatter(
            values: klines.enumerated().map { (i, k) in
                if i % max(1, klines.count / 6) == 0 || i == klines.count - 1 {
                    return k.date.toKlineTimeString(period: viewModel.selectedPeriod)
                }
                return ""
            }
        )
        
        // 实时价格横线（所有LimitLine之前插入，注意removeAllLimitLines清除它，所以最后画）
        let leftAxis = chart.leftAxis
        leftAxis.removeAllLimitLines()
        
        let currentPrice = klines.last?.close ?? 0
        if currentPrice > 0 {
            let liveLl = ChartLimitLine(limit: currentPrice, label: "$\(String(format: "%.2f", currentPrice))")
            liveLl.labelPosition = .rightTop
            liveLl.lineWidth = 1.5
            liveLl.lineColor = UIColor.gray.withAlphaComponent(0.5)
            liveLl.valueTextColor = UIColor.gray.withAlphaComponent(0.7)
            liveLl.valueFont = UIFont.boldSystemFont(ofSize: 10)
            leftAxis.addLimitLine(liveLl)
        }
        
        // 止损线
        if viewModel.showStopLoss {
            for level in viewModel.stopLossLevels {
                let ll = ChartLimitLine(limit: level.price, label: level.label)
                ll.labelPosition = .rightTop
                ll.lineWidth = 1
                ll.lineDashLengths = [4, 4]
                ll.valueTextColor = UIColor(level.color == "#EF4444" ? AppColors.red : AppColors.green)
                leftAxis.addLimitLine(ll)
            }
        }
    }
    
    private func configureChart(_ chart: CandleStickChartView, context: Context) {
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
        
        let data = CandleChartData(dataSets: [dataSet] + extraDataSets + signalDataSets)
        return data
    }
    
    // MARK: - 信号标记数据集
    /// 当前显示币种的换算系数（CNY模式: 汇率/31.1035, USD模式: 1）
    private var displayFactor: Double {
        viewModel.useCNY ? viewModel.currentRate / ChartViewModel.gramPerOunce : 1.0
    }
    
    private var signalDataSets: [ChartDataSetProtocol] {
        guard viewModel.showSignals else { return [] }
        guard !klines.isEmpty else { return [] }
        
        let factor = displayFactor
        var sets: [ChartDataSetProtocol] = []
        
        // 多头开仓标记（绿色三角向上）
        let longEntries: [ChartDataEntry] = viewModel.signalMarkers
            .filter { $0.type == .longOpen }
            .map { ChartDataEntry(x: Double($0.candleIndex), y: $0.price * factor) }
        
        if !longEntries.isEmpty {
            let longSet = ScatterChartDataSet(entries: longEntries, label: "多")
            longSet.setScatterShape(.triangle)
            longSet.setColor(UIColor(AppColors.red))
            longSet.scatterShapeSize = 12
            longSet.drawValuesEnabled = true
            longSet.valueFont = UIFont.boldSystemFont(ofSize: 8)
            longSet.valueTextColor = UIColor(AppColors.red)
            longSet.valueFormatter = SignalValueFormatter(marker: "多")
            longSet.axisDependency = .left
            sets.append(longSet)
        }
        
        // 空头开仓标记（绿色三角向下）
        let shortEntries: [ChartDataEntry] = viewModel.signalMarkers
            .filter { $0.type == .shortOpen }
            .map { ChartDataEntry(x: Double($0.candleIndex), y: $0.price * factor) }
        
        if !shortEntries.isEmpty {
            let shortSet = ScatterChartDataSet(entries: shortEntries, label: "空")
            shortSet.setScatterShape(.chevronDown)
            shortSet.setColor(UIColor(AppColors.green))
            shortSet.scatterShapeSize = 12
            shortSet.drawValuesEnabled = true
            shortSet.valueFont = UIFont.boldSystemFont(ofSize: 8)
            shortSet.valueTextColor = UIColor(AppColors.green)
            shortSet.valueFormatter = SignalValueFormatter(marker: "空")
            shortSet.axisDependency = .left
            sets.append(shortSet)
        }
        
        // 平仓标记（圆点）
        let closeEntries: [ChartDataEntry] = viewModel.signalMarkers
            .filter { !$0.type.isEntry }
            .map { ChartDataEntry(x: Double($0.candleIndex), y: $0.price * factor) }
        
        if !closeEntries.isEmpty {
            let closeSet = ScatterChartDataSet(entries: closeEntries, label: "平")
            closeSet.setScatterShape(.circle)
            closeSet.setColor(UIColor(AppColors.gold))
            closeSet.scatterShapeSize = 8
            closeSet.drawValuesEnabled = true
            closeSet.valueFont = UIFont.systemFont(ofSize: 8)
            closeSet.valueTextColor = UIColor(AppColors.gold)
            closeSet.valueFormatter = SignalValueFormatter(marker: "平")
            closeSet.axisDependency = .left
            sets.append(closeSet)
        }
        
        return sets
    }
    
    private var extraDataSets: [ChartDataSetProtocol] {
        let factor = displayFactor
        var sets: [ChartDataSetProtocol] = []
        
        if viewModel.showMA {
            sets.append(createLineDataSet(values: viewModel.computeMA(period: 5).map { $0.map { $0 * factor } }, clr: AppColors.indicatorMA, label: "MA5"))
            sets.append(createLineDataSet(values: viewModel.computeMA(period: 10).map { $0.map { $0 * factor } }, clr: AppColors.indicatorEMA, label: "MA10"))
            sets.append(createLineDataSet(values: viewModel.computeMA(period: 20).map { $0.map { $0 * factor } }, clr: AppColors.textSecondary, label: "MA20"))
        }
        
        if viewModel.showEMA {
            sets.append(createLineDataSet(values: viewModel.computeEMA(period: 12).map { $0.map { $0 * factor } }, clr: AppColors.indicatorEMA, label: "EMA12"))
            sets.append(createLineDataSet(values: viewModel.computeEMA(period: 26).map { $0.map { $0 * factor } }, clr: AppColors.indicatorRSI, label: "EMA26"))
        }
        
        if viewModel.showBOLL {
            let boll = viewModel.computeBOLL()
            let mapOpt: ([Double?]) -> [Double?] = { arr in arr.map { $0.map { v in v * factor } } }
            sets.append(createLineDataSet(values: mapOpt(boll.upper), clr: AppColors.textTertiary, label: "UP"))
            sets.append(createLineDataSet(values: mapOpt(boll.middle), clr: AppColors.gold, label: "MID"))
            sets.append(createLineDataSet(values: mapOpt(boll.lower), clr: AppColors.textTertiary, label: "LOW"))
        }
        
        return sets
    }
    
    private func createLineDataSet(values: [Double?], clr: Color, label: String) -> LineChartDataSet {
        let entries: [ChartDataEntry] = values.enumerated().compactMap { (i, v) in
            guard let v = v else { return nil }
            return ChartDataEntry(x: Double(i), y: v)
        }
        let dataSet = LineChartDataSet(entries: entries, label: label)
        dataSet.colors = [UIColor(clr)]
        dataSet.lineWidth = 0.8
        dataSet.drawCirclesEnabled = false
        dataSet.drawValuesEnabled = false
        dataSet.axisDependency = .left
        return dataSet
    }
}

// MARK: - 信号ValueFormatter（在标记点显示文字）
class SignalValueFormatter: ValueFormatter {
    private let marker: String
    
    init(marker: String) {
        self.marker = marker
    }
    
    func stringForValue(_ value: Double, entry: ChartDataEntry, dataSetIndex: Int, viewPortHandler: ViewPortHandler?) -> String {
        marker
    }
}

// MARK: - 信号弹出View（点击标记时显示详情）
@available(iOS 14.0, *)
class SignalMarkerView: MarkerView {
    private let viewModel: ChartViewModel
    
    init(viewModel: ChartViewModel) {
        self.viewModel = viewModel
        super.init(frame: CGRect(x: 0, y: 0, width: 160, height: 60))
        self.backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func refreshContent(entry: ChartDataEntry, highlight: Highlight) {
        let idx = Int(entry.x)
        _ = viewModel.signalMarkers.filter { $0.candleIndex == idx }
        // 由SwiftUI overlay处理显示
        super.refreshContent(entry: entry, highlight: highlight)
    }
}

// MARK: - 副图视图不变...
// (保持原有的MACDChartView, KDJChartView, LineIndicatorChartView不变)

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
        
        let difEntries: [ChartDataEntry] = macd.dif.enumerated().compactMap { (i, v) in
            guard let v = v else { return nil }
            return ChartDataEntry(x: Double(i), y: v)
        }
        let difSet = LineChartDataSet(entries: difEntries, label: "DIF")
        difSet.colors = [UIColor(AppColors.gold)]
        difSet.lineWidth = 1
        difSet.drawCirclesEnabled = false
        difSet.drawValuesEnabled = false
        
        let deaEntries: [ChartDataEntry] = macd.dea.enumerated().compactMap { (i, v) in
            guard let v = v else { return nil }
            return ChartDataEntry(x: Double(i), y: v)
        }
        let deaSet = LineChartDataSet(entries: deaEntries, label: "DEA")
        deaSet.colors = [UIColor(AppColors.indicatorRSI)]
        deaSet.lineWidth = 0.8
        deaSet.drawCirclesEnabled = false
        deaSet.drawValuesEnabled = false
        
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
        
        let dataSets: [LineChartDataSet] = colors.map { (name, vals, clr) in
            let entries: [ChartDataEntry] = vals.enumerated().compactMap { (i, v) in
                guard let v = v else { return nil }
                return ChartDataEntry(x: Double(i), y: v)
            }
            let set = LineChartDataSet(entries: entries, label: name)
            set.colors = [clr]
            set.lineWidth = 0.8
            set.drawCirclesEnabled = false
            set.drawValuesEnabled = false
            return set
        }
        
        return LineChartData(dataSets: dataSets)
    }
    
    private var kj: [Double?] {
        zip(kdj.k, kdj.d).map { (k, d) -> Double? in
            guard let k = k, let d = d else { return nil }
            return 3 * k - 2 * d
        }
    }
}

// MARK: - 单线指标副图
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
        dataSet.colors = [UIColor(color)]
        dataSet.lineWidth = 1
        dataSet.drawCirclesEnabled = false
        dataSet.drawValuesEnabled = false
        
        return LineChartData(dataSets: [dataSet])
    }
}
