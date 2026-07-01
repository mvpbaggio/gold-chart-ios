import SwiftUI

@available(iOS 14.0, *)
struct ChartView: View {
    @ObservedObject var viewModel: ChartViewModel
    
    @State private var showSignalDetail = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 实时行情栏 + 币种切换
            realTimeBar
            
            // 价格信息栏
            priceInfoBar
            
            // 持仓状态
            positionBar
            
            ScrollView {
                VStack(spacing: 8) {
                    // 周期选择
                    periodSelector
                    
                    // K线图
                    if viewModel.isLoading {
                        loadingView
                    } else {
                        ZStack(alignment: .topTrailing) {
                            CandleChartContainer(
                                klines: viewModel.displayKlines,
                                viewModel: viewModel
                            )
                            .frame(height: 320)
                            .padding(.horizontal, 4)
                            .onTapGesture {
                                showSignalDetail = true
                            }
                            
                            // 一个亿抄底见顶信号浮标
                            if let assessment = viewModel.assessment {
                                BillionSignalBadge(score: assessment.score, level: assessment.level)
                                    .padding(.trailing, 12)
                                    .padding(.top, 8)
                            }
                        }
                        
                        // 副图指标
                        if let indicator = viewModel.selectedIndicator {
                            indicatorSubChart(indicator)
                                .frame(height: 120)
                                .padding(.horizontal, 4)
                        }
                    }
                    
                    // 信号标记列表
                    if viewModel.showSignals && !viewModel.signalMarkers.isEmpty {
                        signalList
                    }
                    
                    // 指标选择
                    indicatorSelector
                    
                    // 当前价格详细信息
                    if !viewModel.klines.isEmpty {
                        priceDetailCard
                    }
                    
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showSignalDetail) {
            SignalDetailSheet(viewModel: viewModel)
        }
    }
    
    // MARK: - 实时行情栏 + 币种切换
    private var realTimeBar: some View {
        HStack(spacing: 8) {
            // 连接状态指示
            Circle()
                .fill(viewModel.isRealTimeConnected ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
            
            Text(viewModel.isRealTimeConnected ? "实时" : "延迟")
                .font(.system(size: 10))
                .foregroundColor(AppColors.textTertiary)
            
            if let quote = viewModel.realTimeQuote {
                Text(quote.time)
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
            }
            
            // 实时价格（USD）
            HStack(spacing: 2) {
                Text("$")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
                Text(String(format: "%.2f", viewModel.currentPrice))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(viewModel.priceChange >= 0 ? AppColors.red : AppColors.green)
            }
            
            // 实时价格（CNY）
            HStack(spacing: 2) {
                Text("¥")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
                Text(String(format: "%.2f", viewModel.cnyPrice))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(viewModel.priceChange >= 0 ? AppColors.red : AppColors.green)
            }
            
            Spacer()
            
            // 币种切换
            HStack(spacing: 2) {
                Button(action: { if viewModel.useCNY { viewModel.toggleCNY() } }) {
                    Text("$")
                        .font(.system(size: 11, weight: viewModel.useCNY ? .regular : .bold))
                        .foregroundColor(viewModel.useCNY ? AppColors.textTertiary : AppColors.gold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                }
                Button(action: { if !viewModel.useCNY { viewModel.toggleCNY() } }) {
                    Text("¥")
                        .font(.system(size: 11, weight: viewModel.useCNY ? .bold : .regular))
                        .foregroundColor(viewModel.useCNY ? AppColors.gold : AppColors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                }
            }
            .background(AppColors.cardBackground)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(AppColors.cardBorder, lineWidth: 1)
            )
            
            // 信号开关
            Button(action: { viewModel.showSignals.toggle() }) {
                Text("信号")
                    .font(.system(size: 11))
                    .foregroundColor(viewModel.showSignals ? AppColors.gold : AppColors.textTertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(viewModel.showSignals ? AppColors.gold.opacity(0.15) : Color.clear)
            .cornerRadius(4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(AppColors.cardBackground)
    }
    
    // MARK: - 价格信息栏
    private var priceInfoBar: some View {
        HStack {
            Text(viewModel.displayLabel)
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)
            
            Text(priceFormatted(viewModel.displayPrice))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(viewModel.displayChange >= 0 ? AppColors.red : AppColors.green)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(priceFormatted(viewModel.displayChange))
                    .font(.system(size: 13))
                    .foregroundColor(viewModel.displayChange >= 0 ? AppColors.red : AppColors.green)
                Text("(\(viewModel.displayChangePercent.percentString()))")
                    .font(.system(size: 12))
                    .foregroundColor(viewModel.displayChangePercent >= 0 ? AppColors.red : AppColors.green)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                HStack {
                    Text("高")
                        .foregroundColor(AppColors.textTertiary)
                    Text(priceFormatted(viewModel.displayHigh))
                        .foregroundColor(AppColors.textPrimary)
                }
                HStack {
                    Text("低")
                        .foregroundColor(AppColors.textTertiary)
                    Text(priceFormatted(viewModel.displayLow))
                        .foregroundColor(AppColors.textPrimary)
                }
            }
            .font(.system(size: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private func priceFormatted(_ value: Double) -> String {
        if viewModel.useCNY {
            return String(format: "%.2f", value)
        }
        return value.formattedPrice(viewModel.selectedProduct)
    }
    
    // MARK: - 持仓状态栏
    private var positionBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle()
                    .fill(positionColor)
                    .frame(width: 8, height: 8)
                Text(viewModel.position.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(positionColor)
            }
            
            if viewModel.entryPrice > 0 {
                Text("开 \(viewModel.entryPrice.formattedPrice(viewModel.selectedProduct))")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textSecondary)
                
                Text(viewModel.pnl.formattedPrice(viewModel.selectedProduct))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(viewModel.pnl >= 0 ? AppColors.red : AppColors.green)
                
                Text("(\(viewModel.pnlPercent.percentString()))")
                    .font(.system(size: 11))
                    .foregroundColor(viewModel.pnlPercent >= 0 ? AppColors.red : AppColors.green)
            }
            
            Spacer()
            
            if let assessment = viewModel.assessment {
                Text("信号: \(assessment.score)")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
            }
            
            // 汇率显示
            Text("USD/CNY \(String(format: "%.4f", viewModel.currentRate))")
                .font(.system(size: 10))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(AppColors.cardBackground.opacity(0.5))
    }
    
    private var positionColor: Color {
        switch viewModel.position {
        case .long: return AppColors.red
        case .short: return AppColors.green
        case .none: return AppColors.textTertiary
        }
    }
    
    // MARK: - 加载中
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppColors.gold))
                .scaleEffect(1.5)
            Text("加载中...")
                .foregroundColor(AppColors.textSecondary)
                .font(.system(size: 13))
                .padding(.top, 8)
            Spacer()
        }
        .frame(height: 320)
    }
    
    // MARK: - 周期选择
    private var periodSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(KlinePeriod.allCases, id: \.self) { period in
                    Button(action: { viewModel.changePeriod(period) }) {
                        Text(period.displayName)
                            .font(.system(size: 12, weight: viewModel.selectedPeriod == period ? .bold : .regular))
                            .foregroundColor(viewModel.selectedPeriod == period ? AppColors.gold : AppColors.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                viewModel.selectedPeriod == period
                                    ? AppColors.gold.opacity(0.15)
                                    : AppColors.cardBackground
                            )
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(viewModel.selectedPeriod == period ? AppColors.gold.opacity(0.3) : AppColors.cardBorder, lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
    
    // MARK: - 信号列表
    private var signalList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.signalMarkers.suffix(10)) { signal in
                    HStack(spacing: 2) {
                        Text(signal.type.marker)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(signalColor(signal.type))
                        Text(priceFormatted(signal.price))
                            .font(.system(size: 9))
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(AppColors.cardBackground)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(signalColor(signal.type).opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
    
    private func signalColor(_ type: SignalMarker.SignalType) -> Color {
        switch type {
        case .longOpen: return AppColors.red
        case .shortOpen: return AppColors.green
        case .longClose: return AppColors.gold
        case .shortClose: return AppColors.gold
        }
    }
    
    // MARK: - 指标选择
    private var indicatorSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button(action: {
                    viewModel.selectedIndicator = nil
                    viewModel.showVolume.toggle()
                }) {
                    Text("成交量")
                        .font(.system(size: 11))
                        .foregroundColor(viewModel.showVolume ? AppColors.gold : AppColors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(viewModel.showVolume ? AppColors.gold.opacity(0.12) : AppColors.cardBackground)
                        .cornerRadius(4)
                }
                
                ForEach(ChartViewModel.IndicatorType.allCases, id: \.rawValue) { indicator in
                    Button(action: {
                        viewModel.selectedIndicator = viewModel.selectedIndicator == indicator ? nil : indicator
                    }) {
                        Text(indicator.rawValue)
                            .font(.system(size: 11))
                            .foregroundColor(viewModel.selectedIndicator == indicator ? AppColors.gold : AppColors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(viewModel.selectedIndicator == indicator ? AppColors.gold.opacity(0.12) : AppColors.cardBackground)
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - 副图指标
    @ViewBuilder
    private func indicatorSubChart(_ indicator: ChartViewModel.IndicatorType) -> some View {
        switch indicator {
        case .macd:
            MACDChartView(macd: viewModel.computeMACD(), klineCount: viewModel.displayKlines.count)
        case .rsi:
            LineIndicatorChartView(values: viewModel.computeRSI(), name: "RSI", overbought: 70, oversold: 30, color: AppColors.indicatorRSI)
        case .kdj:
            KDJChartView(kdj: viewModel.computeKDJ())
        case .wr:
            LineIndicatorChartView(values: viewModel.computeWR(), name: "W%R", overbought: -20, oversold: -80, color: AppColors.indicatorMACD)
        case .obv:
            LineIndicatorChartView(values: viewModel.computeOBV(), name: "OBV", overbought: nil, oversold: nil, color: AppColors.indicatorVolume)
        case .atr:
            LineIndicatorChartView(values: viewModel.computeATR(), name: "ATR", overbought: nil, oversold: nil, color: AppColors.green)
        default:
            EmptyView()
        }
    }
    
    // MARK: - 价格详情卡片
    private var priceDetailCard: some View {
        VStack(spacing: 6) {
            let ma5 = viewModel.computeMA(period: 5)
            let ma10 = viewModel.computeMA(period: 10)
            let ma20 = viewModel.computeMA(period: 20)
            
            HStack(spacing: 20) {
                indicatorLabel("MA5", value: formatIndicatorValue(ma5.last ?? nil), color: AppColors.indicatorMA)
                indicatorLabel("MA10", value: formatIndicatorValue(ma10.last ?? nil), color: AppColors.indicatorEMA)
                indicatorLabel("MA20", value: formatIndicatorValue(ma20.last ?? nil), color: AppColors.textSecondary)
            }
            
            let macd = viewModel.computeMACD()
            if let dif = macd.dif.last ?? nil,
               let dea = macd.dea.last ?? nil,
               let hist = macd.histogram.last ?? nil {
                HStack(spacing: 20) {
                    indicatorLabel("DIF", value: String(format: "%.2f", dif), color: AppColors.gold)
                    indicatorLabel("DEA", value: String(format: "%.2f", dea), color: AppColors.indicatorRSI)
                    indicatorLabel("MACD", value: String(format: "%.2f", hist), color: hist >= 0 ? AppColors.red : AppColors.green)
                }
            }
            
            let rsi = viewModel.computeRSI()
            if let rsiVal = rsi.last ?? nil {
                HStack(spacing: 20) {
                    indicatorLabel("RSI(14)", value: String(format: "%.1f", rsiVal),
                                  color: rsiVal >= 70 ? AppColors.red : rsiVal <= 30 ? AppColors.green : AppColors.indicatorRSI)
                }
            }
        }
        .padding(12)
        .background(AppColors.cardBackground)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.cardBorder, lineWidth: 1))
        .padding(.horizontal, 12)
    }
    
    private func formatIndicatorValue(_ value: Double?) -> String {
        guard let v = value else { return "--" }
        if viewModel.useCNY {
            return String(format: "%.2f", v * viewModel.currentRate)
        }
        return String(format: "%.2f", v)
    }
    
    private func indicatorLabel(_ name: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(name)
                .font(.system(size: 11))
                .foregroundColor(AppColors.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
        }
    }
}

// MARK: - 信号详情页
@available(iOS 14.0, *)
struct SignalDetailSheet: View {
    @ObservedObject var viewModel: ChartViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.signalMarkers.reversed()) { signal in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(signal.type.rawValue)
                                .font(.headline)
                                .foregroundColor(signalColor(signal.type))
                            Spacer()
                            Text(signal.source)
                                .font(.caption)
                                .foregroundColor(AppColors.textTertiary)
                        }
                        HStack {
                            Text("价格: \(signal.price.formattedPrice(viewModel.selectedProduct))")
                            if let sl = signal.stopLoss {
                                Text("止损: \(sl.formattedPrice(viewModel.selectedProduct))")
                            }
                            if let st = signal.stopTarget {
                                Text("止盈: \(st.formattedPrice(viewModel.selectedProduct))")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("信号明细")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
    
    private func signalColor(_ type: SignalMarker.SignalType) -> Color {
        switch type {
        case .longOpen: return AppColors.red
        case .shortOpen: return AppColors.green
        case .longClose, .shortClose: return AppColors.gold
        }
    }
}

// MARK: - 一个亿抄底见顶信号浮标
@available(iOS 14.0, *)
struct BillionSignalBadge: View {
    let score: Int
    let level: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text("💰 一个亿")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(signalColor)
            
            Text("\(score)")
                .font(.system(size: 20, weight: .heavy))
                .foregroundColor(signalColor)
            
            Text(level.prefix(4))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(signalColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.75))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(signalColor.opacity(0.5), lineWidth: 1)
        )
    }
    
    private var signalColor: Color {
        if score >= 75 { return AppColors.red }
        if score >= 60 { return Color.orange }
        if score >= 45 { return AppColors.textSecondary }
        if score >= 30 { return Color.orange }
        return AppColors.green
    }
}
