import SwiftUI

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
        chart.doubleTapToZoomEnabled = false
        chart.pinchZoomEnabled = true
        chart.drawGridBackgroundEnabled = false
        chart.borderColor = UIColor(AppColors.cardBorder)
        chart.borderLineWidth = 0.5
        chart.drawBordersEnabled = true
        
        let xAxis = chart.xAxis
        xAxis.labelPosition = .bottom
        xAxis.labelTextColor = UIColor(AppColors.textTertiary)
        xAxis.gridColor = UIColor(AppColors.cardBorder)
        xAxis.setLabelCount(4, force: false)
        
        let leftAxis = chart.leftAxis
        leftAxis.labelTextColor = UIColor(AppColors.textTertiary)
        leftAxis.gridColor = UIColor(AppColors.cardBorder)
        
        let rightAxis = chart.rightAxis
        rightAxis.enabled = false
        
        chart.data = createData()
        return chart
    }
    
    func updateUIView(_ uiView: CandleStickChartView, context: Context) {
        uiView.data = createData()
        uiView.notifyDataSetChanged()
    }
    
    private func createData() -> CandleChartData {
        let entries: [CandleChartDataEntry] = klines.enumerated().map { (i, k) in
            CandleChartDataEntry(x: Double(i), shadowH: k.high, shadowL: k.low, open: k.open, close: k.close)
        }
        let set = CandleChartDataSet(entries: entries, label: "")
        set.shadowColorSameAsCandle = true
        set.decreasingColor = UIColor(AppColors.green)
        set.decreasingFilled = true
        set.increasingColor = UIColor(AppColors.red)
        set.increasingFilled = true
        set.neutralColor = UIColor(AppColors.textSecondary)
        set.drawValuesEnabled = false
        
        return CandleChartData(dataSets: [set])
    }
}
