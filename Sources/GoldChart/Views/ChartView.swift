import SwiftUI

@available(iOS 14.0, *)
struct ChartView: View {
    @ObservedObject var viewModel: ChartViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // 价格信息栏
            priceInfoBar
            
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
                                klines: viewModel.klines,
                                viewModel: viewModel
                            )
                            .frame(height: 320)
                            .padding(.horizontal, 4)
                            
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
    }
    
    // MARK: - 价格信息栏
    private var priceInfoBar: some View {
        HStack {
            Text(viewModel.selectedProduct.displayName)
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)
            
            Text(viewModel.currentPrice.formattedPrice(viewModel.selectedProduct))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(viewModel.priceChange >= 0 ? AppColors.red : AppColors.green)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.priceChange.formattedPrice(viewModel.selectedProduct))
                    .font(.system(size: 13))
                    .foregroundColor(viewModel.priceChange >= 0 ? AppColors.red : AppColors.green)
                Text(viewModel.priceChangePercent.percentString())
                    .font(.system(size: 12))
                    .foregroundColor(viewModel.priceChangePercent >= 0 ? AppColors.red : AppColors.green)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                HStack {
                    Text("高")
                        .foregroundColor(AppColors.textTertiary)
                    Text(viewModel.todayHigh.formattedPrice(viewModel.selectedProduct))
                        .foregroundColor(AppColors.textPrimary)
                }
                HStack {
                    Text("低")
                        .foregroundColor(AppColors.textTertiary)
                    Text(viewModel.todayLow.formattedPrice(viewModel.selectedProduct))
                        .foregroundColor(AppColors.textPrimary)
                }
            }
            .font(.system(size: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
    
    // MARK: - 指标选择
    private var indicatorSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button(action: {
                    viewModel.selectedIndicator = viewModel.selectedIndicator == nil ? nil : nil
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
            MACDChartView(macd: viewModel.computeMACD(), klineCount: viewModel.klines.count)
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
            // MA 信息
            let ma5 = viewModel.computeMA(period: 5)
            let ma10 = viewModel.computeMA(period: 10)
            let ma20 = viewModel.computeMA(period: 20)
            
            HStack(spacing: 20) {
                indicatorLabel("MA5", value: (ma5.last ?? nil).map { String(format: "%.2f", $0) } ?? "--", color: AppColors.indicatorMA)
                indicatorLabel("MA10", value: (ma10.last ?? nil).map { String(format: "%.2f", $0) } ?? "--", color: AppColors.indicatorEMA)
                indicatorLabel("MA20", value: (ma20.last ?? nil).map { String(format: "%.2f", $0) } ?? "--", color: AppColors.textSecondary)
            }
            
            // MACD 信息
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
            
            // RSI 信息
            let rsi = viewModel.computeRSI()
            if let rsiVal = rsi.last ?? nil {
                HStack(spacing: 20) {
                    indicatorLabel("RSI(14)", value: String(format: "%.1f", rsiVal), color: rsiVal >= 70 ? AppColors.red : rsiVal <= 30 ? AppColors.green : AppColors.indicatorRSI)
                }
            }
        }
        .padding(12)
        .background(AppColors.cardBackground)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.cardBorder, lineWidth: 1))
        .padding(.horizontal, 12)
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
