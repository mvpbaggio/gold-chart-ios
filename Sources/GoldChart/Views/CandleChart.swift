import SwiftUI
import DGCharts

// MARK: - 信号徽章叠加层（口袋贵金属式：独立图层绘制，缩放/平移跟随重绘）
@available(iOS 14.0, *)
final class SignalBadgeOverlayView: UIView {
    private weak var chart: CandleStickChartView?
    var viewModel: ChartViewModel?
    var klines: [Kline] = []
    
    init(chart: CandleStickChartView) {
        self.chart = chart
        super.init(frame: chart.bounds)
        self.isUserInteractionEnabled = false   // 手势穿透给图表
        self.backgroundColor = .clear
        self.isOpaque = false
        self.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func draw(_ rect: CGRect) {
        guard let chart = chart, let vm = viewModel, !klines.isEmpty else { return }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        // 注：klines 已是 displayKlines（CNY已换算），锚点直接用，不再乘 factor（否则双乘）
        let transformer = chart.getTransformer(forAxis: .left)
        
        // 口袋式：可见区最高/最低价自动标注（价格标签 + 横虚线）
        drawExtremeLabels(ctx: ctx, chart: chart, transformer: transformer)
        
        // build78：当前持仓的止盈线（横虚线+价格标签，实时跟随；多单红/空单绿）
        drawTakeProfitLine(ctx: ctx, chart: chart, transformer: transformer)
        
        // 图表徽章：开仓最近5个 + 止盈最近2个（分开取——保证「盈」徽章不被连续开仓信号挤掉）
        let entrySignals = vm.signalMarkers.filter { $0.type.isEntry }.suffix(5)
        let tpSignals = vm.signalMarkers.filter { $0.type.isTakeProfit }.suffix(2)
        for sig in Array(entrySignals) + Array(tpSignals) {
            guard sig.candleIndex < klines.count else { continue }
            let idx = sig.candleIndex
            // 多→最低点下方；空→最高点上方（偏移用固定像素 24pt，避免金价高位时偏移不可见）
            let anchorValue: Double
            let color: UIColor
            if sig.type.isTakeProfit {
                // 止盈徽章：多单止盈红 / 空单止盈绿（超哥拍板 2026-08-10），锚点在触发K线收盘价
                anchorValue = klines[idx].close
                color = sig.type == .longTakeProfit ? UIColor(AppColors.red) : UIColor(AppColors.green)
            } else if sig.type == .longOpen {
                anchorValue = klines[idx].low
                color = UIColor(AppColors.red)
            } else {
                anchorValue = klines[idx].high
                color = UIColor(AppColors.green)
            }
            let anchor = transformer.pixelForValues(x: Double(idx), y: anchorValue)
            let badgeCenter = CGPoint(x: anchor.x, y: sig.type.isTakeProfit ? anchor.y - 24 : (sig.type == .longOpen ? anchor.y - 24 : anchor.y + 24))
            
            // 灰色垂直虚线：K线极值 → 徽章圆心
            ctx.saveGState()
            ctx.setStrokeColor(UIColor.gray.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [3, 3])
            ctx.move(to: anchor)
            ctx.addLine(to: badgeCenter)
            ctx.strokePath()
            ctx.restoreGState()
            
            drawBadge(ctx: ctx, center: badgeCenter, color: color, text: sig.type.marker)
        }
    }
    
    // MARK: - 口袋式可见区最高/最低标注
    /// 当前可见范围内自动找最高/最低价，画价格标签 + 横虚线（缩放/平移时由 chartScaled/chartTranslated 触发重绘）
    private func drawExtremeLabels(ctx: CGContext, chart: CandleStickChartView, transformer: Transformer) {
        guard !klines.isEmpty else { return }
        
        // 可见 x 范围（x 即 K线索引），clamp 到有效区间
        let startX = max(0, Int(chart.lowestVisibleX.rounded(.down)))
        let endX = min(klines.count - 1, Int(chart.highestVisibleX.rounded(.up)))
        guard startX <= endX else { return }
        
        var highIdx = startX, lowIdx = startX
        var highVal = klines[startX].high, lowVal = klines[startX].low
        if startX < endX {
            for i in (startX + 1)...endX {
                if klines[i].high > highVal { highVal = klines[i].high; highIdx = i }
                if klines[i].low < lowVal { lowVal = klines[i].low; lowIdx = i }
            }
        }
        
        // 高低点同一根K线时只画一次（防止重叠）
        if highIdx == lowIdx {
            drawExtremeBadge(ctx: ctx, transformer: transformer, idx: highIdx, value: highVal, isHigh: true)
            return
        }
        drawExtremeBadge(ctx: ctx, transformer: transformer, idx: highIdx, value: highVal, isHigh: true)
        drawExtremeBadge(ctx: ctx, transformer: transformer, idx: lowIdx, value: lowVal, isHigh: false)
    }
    
    /// 单个极值标签：白底圆角框 + 价格文字 + 横虚线指向K线极值点
    private func drawExtremeBadge(ctx: CGContext, transformer: Transformer, idx: Int, value: Double, isHigh: Bool) {
        let anchor = transformer.pixelForValues(x: Double(idx), y: value)
        let color: UIColor = isHigh ? UIColor(AppColors.red) : UIColor(AppColors.green)
        let text = String(format: "%.2f", value)
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: color
        ]
        let str = text as NSString
        let textSize = str.size(withAttributes: attrs)
        let padX: CGFloat = 6, padY: CGFloat = 3
        let boxW = textSize.width + padX * 2
        let boxH = textSize.height + padY * 2
        // 标签垂直位置：默认高点在极值上方、低点在极值下方；但极值贴近图表边界时翻转到内侧（否则超出 bounds 被裁剪看不见）
        let chartHeight = chart?.bounds.height ?? 400
        let aboveY = anchor.y - 26
        let belowY = anchor.y + 26
        let labelY: CGFloat
        if isHigh {
            // 高点：优先上方；上方空间不足（贴近图表顶部）则放下方
            labelY = (aboveY - boxH / 2) >= 0 ? aboveY : belowY
        } else {
            // 低点：优先下方；下方空间不足（贴近图表底部）则放上方 ← 修复最低价标签看不见
            labelY = (belowY + boxH / 2) <= chartHeight ? belowY : aboveY
        }
        
        // 标签默认在K线右侧；右侧超界则移到左侧
        let chartWidth = chart?.bounds.width ?? 400
        var boxX = anchor.x + 5
        if boxX + boxW + 5 > chartWidth {
            boxX = anchor.x - boxW - 5
        }
        let boxRect = CGRect(x: boxX, y: labelY - boxH / 2, width: boxW, height: boxH)
        
        // 横虚线：K线极值点 → 标签左/右边缘（水平方向）
        ctx.saveGState()
        ctx.setStrokeColor(color.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [3, 3])
        ctx.move(to: CGPoint(x: anchor.x, y: anchor.y))
        let lineEndX = boxX > anchor.x ? boxX : boxX + boxW
        ctx.addLine(to: CGPoint(x: lineEndX, y: anchor.y))
        ctx.strokePath()
        ctx.restoreGState()
        
        // 白底标签
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(boxRect)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(boxRect)
        // 价格文字居中
        str.draw(at: CGPoint(x: boxRect.midX - textSize.width / 2, y: boxRect.midY - textSize.height / 2),
                 withAttributes: attrs)
    }
    
    // MARK: - build78：当前持仓止盈线（横虚线 + 价格标签）
    /// 多单红虚线（持仓最高−2ATR）/ 空单绿虚线（持仓最低+2ATR），横跨可见区，右侧标签显示价格
    /// 注意：overlay 的 klines 已是 CNY 换算，止盈线美元价需乘同一 factor 再投影
    private func drawTakeProfitLine(ctx: CGContext, chart: CandleStickChartView, transformer: Transformer) {
        guard let vm = viewModel, let tpUSD = vm.takeProfitLine else { return }
        let factor = vm.useCNY ? vm.currentRate / ChartViewModel.gramPerOunce : 1.0
        let tp = tpUSD * factor
        let color: UIColor = vm.position == .long ? UIColor(AppColors.red) : UIColor(AppColors.green)
        
        let left = transformer.pixelForValues(x: Double(chart.lowestVisibleX), y: tp)
        let right = transformer.pixelForValues(x: Double(chart.highestVisibleX), y: tp)
        
        // 横虚线（全宽）
        ctx.saveGState()
        ctx.setStrokeColor(color.withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(1.2)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.move(to: CGPoint(x: left.x, y: left.y))
        ctx.addLine(to: CGPoint(x: right.x, y: right.y))
        ctx.strokePath()
        ctx.restoreGState()
        
        // 右侧价格标签（「盈线」位置）
        let text = String(format: "%.2f", tpUSD)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: color
        ]
        let str = text as NSString
        let textSize = str.size(withAttributes: attrs)
        let padX: CGFloat = 6, padY: CGFloat = 2
        let boxW = textSize.width + padX * 2
        let boxH = textSize.height + padY * 2
        let chartWidth = chart.bounds.width
        let chartHeight = chart.bounds.height
        var boxX = chartWidth - boxW - 6
        var labelY = left.y - boxH / 2
        if labelY < 2 { labelY = 2 }
        if labelY + boxH > chartHeight - 2 { labelY = chartHeight - boxH - 2 }
        let boxRect = CGRect(x: boxX, y: labelY, width: boxW, height: boxH)
        
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.92).cgColor)
        ctx.fill(boxRect)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(boxRect)
        str.draw(at: CGPoint(x: boxRect.midX - textSize.width / 2, y: boxRect.midY - textSize.height / 2),
                 withAttributes: attrs)
    }
    
    private func drawBadge(ctx: CGContext, center: CGPoint, color: UIColor, text: String) {
        let radius: CGFloat = 13
        // 白底
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2))
        // 描边
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                     width: radius * 2, height: radius * 2))
        // 居中文字
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 13),
            .foregroundColor: color
        ]
        let str = text as NSString
        let size = str.size(withAttributes: attrs)
        str.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
                 withAttributes: attrs)
    }
}

// MARK: - K线图容器（UIKit桥接）
@available(iOS 14.0, *)
struct CandleChartContainer: UIViewRepresentable {
    let klines: [Kline]
    let viewModel: ChartViewModel
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> CandleStickChartView {
        let chart = CandleStickChartView()
        configureChart(chart, context: context)
        chart.data = createChartData()
        chart.marker = SignalMarkerView(viewModel: viewModel)
        chart.delegate = context.coordinator
        
        // 信号徽章叠加层（口袋式独立图层）
        let overlay = SignalBadgeOverlayView(chart: chart)
        overlay.viewModel = viewModel
        overlay.klines = klines
        chart.addSubview(overlay)
        context.coordinator.overlay = overlay
        overlay.frame = chart.bounds
        
        return chart
    }
    
    func updateUIView(_ uiView: CandleStickChartView, context: Context) {
        // 保存缩放矩阵 → 重建数据 → 恢复缩放（避免 setData 的 fitScreen 重置用户缩放）
        let savedMatrix = uiView.viewPortHandler.touchMatrix
        uiView.data = createChartData()
        uiView.viewPortHandler.refresh(newMatrix: savedMatrix, chart: uiView, invalidate: false)
        uiView.marker = SignalMarkerView(viewModel: viewModel)
        // 更新徽章层数据并重绘
        context.coordinator.overlay?.viewModel = viewModel
        context.coordinator.overlay?.klines = klines
        context.coordinator.overlay?.frame = uiView.bounds
        context.coordinator.overlay?.setNeedsDisplay()
        // 每帧刷新坐标轴（支持动态K线延伸）
        updateAxes(uiView)
        uiView.notifyDataSetChanged()
    }
    
    // MARK: - Coordinator（监听缩放/平移，重绘徽章层）
    final class Coordinator: NSObject, ChartViewDelegate {
        weak var overlay: SignalBadgeOverlayView?
        
        func chartScaled(_ chartView: ChartViewBase, scaleX: CGFloat, scaleY: CGFloat) {
            overlay?.setNeedsDisplay()
        }
        
        func chartTranslated(_ chartView: ChartViewBase, dX: CGFloat, dY: CGFloat) {
            overlay?.setNeedsDisplay()
        }
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
        
        // 现价取实时行情（每5秒刷新），无实时价时回退最后一根K线收盘
        let livePrice = (viewModel.realTimeQuote?.price ?? (klines.last?.close ?? 0)) * displayFactor
        if livePrice > 0 {
            let liveLl = ChartLimitLine(limit: livePrice, label: "\(String(format: "%.2f", livePrice))")
            liveLl.labelPosition = .rightTop
            liveLl.lineWidth = 1
            liveLl.lineDashLengths = [4, 3]   // 红虚线现价线（同花顺）
            liveLl.lineColor = UIColor(AppColors.red)
            liveLl.valueTextColor = UIColor(AppColors.red)
            liveLl.valueFont = UIFont.boldSystemFont(ofSize: 11)
            leftAxis.addLimitLine(liveLl)
        }
        // 止盈/止损虚线：超哥要求去掉（2026-08-07）
    }
    
    private func configureChart(_ chart: CandleStickChartView, context: Context) {
        chart.backgroundColor = UIColor(AppColors.background)
        chart.gridBackgroundColor = UIColor(AppColors.cardBackground)
        
        // X轴
        let xAxis = chart.xAxis
        xAxis.labelPosition = .bottom
        xAxis.labelTextColor = UIColor(AppColors.textTertiary)
        xAxis.gridColor = UIColor(hex: "F2F2F7")   // 同花顺浅灰网格
        xAxis.avoidFirstLastClippingEnabled = true
        xAxis.granularity = 1
        xAxis.setLabelCount(6, force: false)
        xAxis.spaceMin = 1   // 左侧留1根K线空间
        xAxis.spaceMax = 30  // 右侧留30根K线空间（最新K线远离右边，同花顺风格）
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
        leftAxis.gridColor = UIColor(hex: "F2F2F7")   // 同花顺浅灰网格
        leftAxis.labelPosition = .outsideChart
        
        // 右Y轴
        let rightAxis = chart.rightAxis
        rightAxis.enabled = false
        
        chart.legend.enabled = false
        chart.doubleTapToZoomEnabled = true   // 双击恢复
        chart.pinchZoomEnabled = true
        chart.scaleXEnabled = true
        chart.scaleYEnabled = true   // 放开Y轴缩放，双指捏合按比例缩放
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
        dataSet.shadowWidth = 1.0
        dataSet.decreasingColor = UIColor(AppColors.green)
        dataSet.decreasingFilled = true       // 阴线（跌）绿实心
        dataSet.increasingColor = UIColor(AppColors.red)
        dataSet.increasingFilled = false      // 阳线（涨）红空心（同花顺）
        dataSet.neutralColor = UIColor(AppColors.textSecondary)
        dataSet.valueTextColor = UIColor.clear
        dataSet.drawValuesEnabled = false
        
        let data = CandleChartData(dataSets: [dataSet] + extraDataSets)
        return data
    }
    
    // MARK: - 信号连接线（虚线+徽章全部由 SignalBadgeOverlayView 像素层绘制，此处不再生成数据集）
    /// 当前显示币种的换算系数（CNY模式: 汇率/31.1035, USD模式: 1）
    private var displayFactor: Double {
        viewModel.useCNY ? viewModel.currentRate / ChartViewModel.gramPerOunce : 1.0
    }
    
    private var extraDataSets: [ChartDataSetProtocol] {
        let factor = displayFactor
        var sets: [ChartDataSetProtocol] = []
        
        if viewModel.showMA {
            sets.append(createLineDataSet(values: viewModel.computeMA(period: 5).map { $0.map { $0 * factor } }, clr: AppColors.indicatorMA, label: "MA5"))
            sets.append(createLineDataSet(values: viewModel.computeMA(period: 10).map { $0.map { $0 * factor } }, clr: AppColors.indicatorEMA, label: "MA10"))
            sets.append(createLineDataSet(values: viewModel.computeMA(period: 20).map { $0.map { $0 * factor } }, clr: AppColors.indicatorMA20, label: "MA20"))
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
