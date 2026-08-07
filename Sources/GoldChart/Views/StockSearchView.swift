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
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "building.columns")
                        .font(.system(size: 40))
                        .foregroundColor(AppColors.textTertiary)
                    Text(searchText.isEmpty ? "搜索A股个股" : "未找到匹配")
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(viewModel.results) { stock in
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
                    }
                }
                .listStyle(PlainListStyle())
                .background(AppColors.background)
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
                StockMiniChart(klines: viewModel.stockKlines)
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
                
                Spacer()
            }
        }
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
        
        let xAxis = chart.xAxis
        xAxis.labelPosition = .bottom
        xAxis.labelTextColor = UIColor(AppColors.textTertiary)
        xAxis.gridColor = UIColor(hex: "F2F2F7")   // 同花顺浅灰网格
        xAxis.setLabelCount(4, force: false)
        xAxis.avoidFirstLastClippingEnabled = true
        xAxis.granularity = 1
        xAxis.spaceMin = 1   // 左侧留1根K线空间
        xAxis.spaceMax = 3   // 右侧留3根K线空间（最新K线不贴边）
        
        let leftAxis = chart.leftAxis
        leftAxis.labelTextColor = UIColor(AppColors.textTertiary)
        leftAxis.gridColor = UIColor(hex: "F2F2F7")
        leftAxis.labelPosition = .outsideChart
        
        let rightAxis = chart.rightAxis
        rightAxis.enabled = false
        
        chart.data = createData()
        updateLimitLines(chart)
        return chart
    }
    
    func updateUIView(_ uiView: CandleStickChartView, context: Context) {
        // 保存缩放矩阵 → 重建数据 → 恢复缩放（避免 setData 重置用户缩放）
        let savedMatrix = uiView.viewPortHandler.touchMatrix
        uiView.data = createData()
        uiView.viewPortHandler.refresh(newMatrix: savedMatrix, chart: uiView, invalidate: false)
        updateLimitLines(uiView)
        uiView.notifyDataSetChanged()
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
