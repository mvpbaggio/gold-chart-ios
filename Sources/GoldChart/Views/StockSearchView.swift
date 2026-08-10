import SwiftUI
import DGCharts

@available(iOS 14.0, *)
struct StockSearchView: View {
    @ObservedObject var viewModel: SearchViewModel
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.textTertiary)
                TextField("输入股票代码或名称", text: $searchText, onEditingChanged: { _ in })
                    .foregroundColor(AppColors.textPrimary)
                    .accentColor(AppColors.gold)
                    .onChange(of: searchText) { newValue in
                        viewModel.query = newValue
                    }
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        viewModel.query = ""
                        viewModel.results = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }
            .padding(10)
            .background(AppColors.cardBackground)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.cardBorder, lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            if viewModel.isFetchingStock || viewModel.selectedStock != nil {
                // 个股详情
                stockDetailView
            } else {
                // 搜索结果
                searchResultsView
            }
        }
    }
    
    // MARK: - 搜索结果
    private var searchResultsView: some View {
        Group {
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if viewModel.results.isEmpty {
                if searchText.isEmpty {
                    // 自选列表
                    favoritesView
                } else {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "building.columns")
                            .font(.system(size: 40))
                            .foregroundColor(AppColors.textTertiary)
                        Text("未找到匹配")
                            .foregroundColor(AppColors.textSecondary)
                    }
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.results) { stock in
                            HStack {
                                Button(action: { viewModel.selectStock(stock) }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(stock.name)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(AppColors.textPrimary)
                                            Text(stock.code)
                                                .font(.system(size: 12))
                                                .foregroundColor(AppColors.textTertiary)
                                        }
                                        Spacer()
                                        Text(stock.marketDisplay)
                                            .font(.system(size: 11))
                                            .foregroundColor(AppColors.gold)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(AppColors.gold.opacity(0.15))
                                            .cornerRadius(4)
                                    }
                                    .padding(.vertical, 4)
                                }
                                Button(action: { viewModel.toggleFavorite(stock) }) {
                                    Image(systemName: viewModel.isFavorite(code: stock.code) ? "star.fill" : "star")
                                        .foregroundColor(viewModel.isFavorite(code: stock.code) ? AppColors.gold : AppColors.textTertiary)
                                        .font(.system(size: 16))
                                        .padding(.trailing, 8)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            .padding(.horizontal, 16)
                            Divider().background(AppColors.cardBorder)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(AppColors.background)
                .id(viewModel.results)   // 结果变化→整棵重建，避开懒加载增量渲染 bug
            }
        }
    }
    
    // MARK: - 自选列表
    private var favoritesView: some View {
        Group {
            if viewModel.favorites.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "star")
                        .font(.system(size: 40))
                        .foregroundColor(AppColors.textTertiary)
                    Text("暂无自选，搜索个股后点 ☆ 添加")
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.favorites) { fav in
                            HStack {
                                Button(action: { viewModel.selectFavorite(fav) }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(fav.name)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(AppColors.textPrimary)
                                            Text(fav.code)
                                                .font(.system(size: 12))
                                                .foregroundColor(AppColors.textTertiary)
                                        }
                                        Spacer()
                                        Text(fav.marketDisplay)
                                            .font(.system(size: 11))
                                            .foregroundColor(AppColors.gold)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(AppColors.gold.opacity(0.15))
                                            .cornerRadius(4)
                                    }
                                    .padding(.vertical, 4)
                                }
                                Button(action: { viewModel.removeFavorite(fav) }) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(AppColors.gold)
                                        .font(.system(size: 16))
                                        .padding(.trailing, 8)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            .padding(.horizontal, 16)
                            Divider().background(AppColors.cardBorder)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(AppColors.background)
                .id("\(viewModel.favorites.count)-\(viewModel.resetToken)")   // 集合变化/切回tab → 整棵重建，避开懒加载增量渲染 bug
            }
        }
    }
    
    // MARK: - 个股详情
    private var stockDetailView: some View {
        VStack(spacing: 8) {
            // 股票信息头
            if let stock = viewModel.selectedStock {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stock.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppColors.textPrimary)
                        Text("\(stock.code) · \(stock.marketDisplay)")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.textSecondary)
                    }
                    Spacer()
                    Button(action: {
                        viewModel.selectedStock = nil
                        viewModel.stockKlines = []
                        searchText = ""
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(AppColors.textSecondary)
                            .padding(8)
                            .background(AppColors.cardBackground)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            
            if viewModel.isFetchingStock {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.gold))
                Spacer()
            } else if !viewModel.stockKlines.isEmpty {
                // 简易K线图
                StockMiniChart(klines: viewModel.stockKlines, signals: viewModel.stockSignals)
                    .frame(height: 240)
                    .padding(.horizontal, 4)
                
                // 基本信息
                let klines = viewModel.stockKlines
                if let last = klines.last, let prev = klines.dropLast().last {
                    let change = last.close - prev.close
                    let pct = prev.close > 0 ? (change / prev.close) * 100 : 0
                    
                    HStack(spacing: 20) {
                        infoItem("最新价", value: String(format: "%.2f", last.close), color: change >= 0 ? AppColors.red : AppColors.green)
                        infoItem("涨幅", value: String(format: "%.2f%%", pct), color: change >= 0 ? AppColors.red : AppColors.green)
                        infoItem("最高", value: String(format: "%.2f", last.high), color: AppColors.textPrimary)
                        infoItem("最低", value: String(format: "%.2f", last.low), color: AppColors.textPrimary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
                
                // A股引擎评分卡
                stockScoreCard
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                
                Spacer()
            }
        }
    }
    
    // MARK: - A股引擎评分卡
    private var stockScoreCard: some View {
        VStack(spacing: 6) {
            if let cs = viewModel.stockComposite {
                HStack(spacing: 16) {
                    Label(cs.level.rawValue, systemImage: levelIcon(cs.level))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: cs.level.color))
                    Text("\(cs.score)")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundColor(Color(hex: cs.level.color))
                    Spacer()
                    Text("A股引擎")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.horizontal, 12)
                
                // 评分进度条
                scoreBar(value: Double(cs.score))
                    .padding(.horizontal, 12)
                
                // 明细（timing / 23指标）
                VStack(spacing: 0) {
                    ForEach(cs.breakdown) { item in
                        HStack(spacing: 8) {
                            Text(item.name)
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textSecondary)
                                .frame(width: 70, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(AppColors.cardBorder)
                                        .frame(height: 6)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(item.score >= 0 ? AppColors.red : AppColors.green)
                                        .frame(width: max(2, min(geo.size.width, geo.size.width * CGFloat(abs(item.score)) / 200)),
                                               height: 6)
                                }
                            }
                            .frame(height: 6)
                            Text("\(item.score)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(item.score >= 0 ? AppColors.red : AppColors.green)
                                .frame(width: 28, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    }
                }
            } else {
                Text("正在计算评分...")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
                    .padding()
            }
        }
        .padding(.vertical, 8)
        .background(AppColors.cardBackground.opacity(0.5))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.cardBorder, lineWidth: 1))
    }
    
    private func levelIcon(_ level: CompositeSignal.SignalLevel) -> String {
        switch level {
        case .fierceLong: return "arrow.up.circle.fill"
        case .long: return "arrow.up"
        case .neutral: return "equal"
        case .short: return "arrow.down"
        case .fierceShort: return "arrow.down.circle.fill"
        }
    }
    
    private func scoreBar(value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                LinearGradient(gradient: Gradient(colors: [
                    Color.green.opacity(0.3),
                    Color.gray.opacity(0.15),
                    Color.red.opacity(0.3)
                ]), startPoint: .leading, endPoint: .trailing)
                .frame(height: 12)
                .cornerRadius(6)
                
                Circle()
                    .fill(AppColors.textTertiary)
                    .frame(width: 4, height: 4)
                    .offset(x: geo.size.width / 2, y: 0)
                
                let pct = (value + 100) / 200
                Circle()
                    .fill(value >= 0 ? AppColors.red : AppColors.green)
                    .frame(width: 10, height: 10)
                    .offset(x: max(5, min(geo.size.width - 5, geo.size.width * CGFloat(pct))), y: 0)
            }
        }
        .frame(height: 12)
    }
    
    private func infoItem(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AppColors.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - A股简易K线
@available(iOS 14.0, *)
struct StockMiniChart: UIViewRepresentable {
    let klines: [Kline]
    var signals: [SignalMarker] = []
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> CandleStickChartView {
        let chart = CandleStickChartView()
        chart.backgroundColor = UIColor(AppColors.background)
        chart.legend.enabled = false
        chart.doubleTapToZoomEnabled = true
        chart.pinchZoomEnabled = true
        chart.scaleXEnabled = true
        chart.scaleYEnabled = true
        chart.drawGridBackgroundEnabled = false
        chart.borderColor = UIColor(AppColors.cardBorder)
        chart.borderLineWidth = 0.5
        chart.drawBordersEnabled = true
        chart.delegate = context.coordinator
        
        let xAxis = chart.xAxis
        xAxis.labelPosition = .bottom
        xAxis.labelTextColor = UIColor(AppColors.textTertiary)
        xAxis.gridColor = UIColor(hex: "F2F2F7")   // 同花顺浅灰网格
        xAxis.setLabelCount(4, force: false)
        xAxis.avoidFirstLastClippingEnabled = true
        xAxis.granularity = 1
        xAxis.spaceMin = 1   // 左侧留1根K线空间
        xAxis.spaceMax = 30  // 右侧留30根K线空间（最新K线远离右缘）
        
        let leftAxis = chart.leftAxis
        leftAxis.labelTextColor = UIColor(AppColors.textTertiary)
        leftAxis.gridColor = UIColor(hex: "F2F2F7")
        leftAxis.labelPosition = .outsideChart
        
        let rightAxis = chart.rightAxis
        rightAxis.enabled = false
        
        chart.data = createData()
        updateLimitLines(chart)
        
        // A股信号徽章叠加层（精简版，直接传 signals/klines）
        let overlay = StockSignalOverlayView(chart: chart, signals: signals, klines: klines)
        chart.addSubview(overlay)
        context.coordinator.overlay = overlay
        overlay.frame = chart.bounds
        
        return chart
    }
    
    func updateUIView(_ uiView: CandleStickChartView, context: Context) {
        // 保存缩放矩阵 → 重建数据 → 恢复缩放（避免 setData 重置用户缩放）
        let savedMatrix = uiView.viewPortHandler.touchMatrix
        uiView.data = createData()
        uiView.viewPortHandler.refresh(newMatrix: savedMatrix, chart: uiView, invalidate: false)
        updateLimitLines(uiView)
        // 更新徽章层并重绘
        context.coordinator.overlay?.signals = signals
        context.coordinator.overlay?.klines = klines
        context.coordinator.overlay?.frame = uiView.bounds
        context.coordinator.overlay?.setNeedsDisplay()
        uiView.notifyDataSetChanged()
    }
    
    // MARK: - Coordinator（缩放/平移重绘徽章层）
    final class Coordinator: NSObject, ChartViewDelegate {
        weak var overlay: StockSignalOverlayView?
        
        func chartScaled(_ chartView: ChartViewBase, scaleX: CGFloat, scaleY: CGFloat) {
            overlay?.setNeedsDisplay()
        }
        
        func chartTranslated(_ chartView: ChartViewBase, dX: CGFloat, dY: CGFloat) {
            overlay?.setNeedsDisplay()
        }
    }
    
    private func updateLimitLines(_ chart: CandleStickChartView) {
        let leftAxis = chart.leftAxis
        leftAxis.removeAllLimitLines()
        if let last = klines.last {
            let ll = ChartLimitLine(limit: last.close, label: String(format: "%.2f", last.close))
            ll.labelPosition = .rightTop
            ll.lineWidth = 1
            ll.lineDashLengths = [4, 3]   // 红虚线现价线（同花顺）
            ll.lineColor = UIColor(AppColors.red)
            ll.valueTextColor = UIColor(AppColors.red)
            ll.valueFont = UIFont.boldSystemFont(ofSize: 10)
            leftAxis.addLimitLine(ll)
        }
    }
    
    private func createData() -> CandleChartData {
        let entries: [CandleChartDataEntry] = klines.enumerated().map { (i, k) in
            CandleChartDataEntry(x: Double(i), shadowH: k.high, shadowL: k.low, open: k.open, close: k.close)
        }
        let set = CandleChartDataSet(entries: entries, label: "")
        set.axisDependency = .left
        set.shadowColorSameAsCandle = true
        set.shadowWidth = 1.0
        set.decreasingColor = UIColor(AppColors.green)
        set.decreasingFilled = true        // 阴线（跌）绿实心（同花顺）
        set.increasingColor = UIColor(AppColors.red)
        set.increasingFilled = false       // 阳线（涨）红空心（同花顺）
        set.neutralColor = UIColor(AppColors.textSecondary)
        set.drawValuesEnabled = false
        
        // 3均线：MA5灰 / MA10橙黄 / MA20淡紫
        var sets: [ChartDataSetProtocol] = [set]
        let maConfigs: [(Int, Color)] = [(5, AppColors.indicatorMA), (10, AppColors.indicatorEMA), (20, AppColors.indicatorMA20)]
        for (period, clr) in maConfigs {
            let ma = IndicatorEngine.ma(klines, period: period)
            let maEntries: [ChartDataEntry] = ma.enumerated().compactMap { (i, v) in
                guard let v = v else { return nil }
                return ChartDataEntry(x: Double(i), y: v)
            }
            let maSet = LineChartDataSet(entries: maEntries, label: "MA\(period)")
            maSet.colors = [UIColor(clr)]
            maSet.lineWidth = 0.8
            maSet.drawCirclesEnabled = false
            maSet.drawValuesEnabled = false
            maSet.axisDependency = .left
            sets.append(maSet)
        }
        
        return CandleChartData(dataSets: sets)
    }
}

// MARK: - A股信号徽章叠加层（精简版，照抄 SignalBadgeOverlayView 核心逻辑）
@available(iOS 14.0, *)
final class StockSignalOverlayView: UIView {
    private weak var chart: CandleStickChartView?
    var signals: [SignalMarker] = []
    var klines: [Kline] = []
    
    init(chart: CandleStickChartView, signals: [SignalMarker], klines: [Kline]) {
        self.chart = chart
        self.signals = signals
        self.klines = klines
        super.init(frame: chart.bounds)
        self.isUserInteractionEnabled = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func draw(_ rect: CGRect) {
        guard let chart = chart, !klines.isEmpty else { return }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        let transformer = chart.getTransformer(forAxis: .left)
        
        // 只画开仓信号（多/空），最近 5 个
        for sig in signals.filter({ $0.type.isEntry }).suffix(5) {
            guard sig.candleIndex < klines.count else { continue }
            let idx = sig.candleIndex
            let anchorValue: Double
            let color: UIColor
            if sig.type == .longOpen {
                anchorValue = klines[idx].low
                color = UIColor(AppColors.red)
            } else {
                anchorValue = klines[idx].high
                color = UIColor(AppColors.green)
            }
            let anchor = transformer.pixelForValues(x: Double(idx), y: anchorValue)
            let badgeCenter = CGPoint(x: anchor.x, y: sig.type == .longOpen ? anchor.y - 24 : anchor.y + 24)
            
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
    
    private func drawBadge(ctx: CGContext, center: CGPoint, color: UIColor, text: String) {
        let radius: CGFloat = 13
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2))
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                     width: radius * 2, height: radius * 2))
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
