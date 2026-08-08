import SwiftUI

@available(iOS 14.0, *)
struct ChartView: View {
    @ObservedObject var viewModel: ChartViewModel
    @ObservedObject private var realTimeService = RealTimeService.shared
    
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
                            .frame(height: 480)
                            .padding(.horizontal, 4)
                        }
                        
                    }
                    
                    // 调试状态栏（K线实时更新诊断用）
                    debugBar
                    
                    // 综合评分
                    compositeScoreCard
                    
                    // 历史信号列表（综合评分 ±75 以上）
                    if !viewModel.signalMarkers.isEmpty {
                        signalListView
                    }
                    
                    // 指标选择
                    indicatorSelector
                    
                }
            }
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
            
            // 市场开闭市状态（口袋贵金属式：开市 / 休市 HH:mm:ss）
            Text(realTimeService.marketStatus.displayText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(realTimeService.marketStatus.isOpen ? AppColors.red : AppColors.textSecondary)
            
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
            
            // 汇率显示
            Text("\(String(format: "%.4f", viewModel.currentRate))  ¥\(String(format: "%.2f", viewModel.currentPrice * viewModel.currentRate / ChartViewModel.gramPerOunce))/g")
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
    
    // MARK: - 调试状态栏
    private var debugBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isRealTimeConnected ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            
            Text(viewModel.debugText)
                .font(.system(size: 8))
                .foregroundColor(AppColors.textTertiary)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(AppColors.cardBackground.opacity(0.3))
    }
    
    // MARK: - 历史信号列表
    private var signalListView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.signalMarkers.suffix(5)) { signal in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 2) {
                            Image(systemName: signal.type == .longOpen ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.system(size: 10))
                                .foregroundColor(signal.type == .longOpen ? AppColors.red : AppColors.green)
                            Text(priceFormatted(signal.price))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(AppColors.textPrimary)
                        }
                        HStack(spacing: 4) {
                            Text("止\(signal.type == .longOpen ? "损" : "损")")
                                .foregroundColor(AppColors.green)
                            + Text(String(format: "%.1f", signal.stopLoss ?? 0))
                                .foregroundColor(AppColors.green)
                            Text("|")
                                .foregroundColor(AppColors.textTertiary)
                            Text("盈")
                                .foregroundColor(AppColors.red)
                            + Text(String(format: "%.1f", signal.stopTarget ?? 0))
                                .foregroundColor(AppColors.red)
                        }
                        .font(.system(size: 8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.cardBackground)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(signal.type == .longOpen ? AppColors.red.opacity(0.3) : AppColors.green.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - 综合评分卡
    private var compositeScoreCard: some View {
        VStack(spacing: 6) {
            if let cs = viewModel.compositeSignal {
                HStack(spacing: 16) {
                    // 评级标签
                    Label(cs.level.rawValue, systemImage: levelIcon(cs.level))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: cs.level.color))
                    
                    // 评分数字
                    Text("\(cs.score)")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(Color(hex: cs.level.color))
                    
                    Spacer()
                    
                    // 指标个数
                    Text("\(cs.breakdown.count)项")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.horizontal, 12)
                
                // 评分进度条
                scoreBar(value: Double(cs.score))
                    .padding(.horizontal, 12)
                
                // 11项明细
                VStack(spacing: 0) {
                    ForEach(cs.breakdown) { item in
                        HStack(spacing: 8) {
                            Text(item.name)
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textSecondary)
                                .frame(width: 80, alignment: .leading)
                            
                            // 单项进度条
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
                Text("正在计算综合评分...")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
                    .padding()
            }
        }
        .padding(.vertical, 8)
        .background(AppColors.cardBackground.opacity(0.5))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.cardBorder, lineWidth: 1))
        .padding(.horizontal, 12)
    }
    
    private func scoreBar(value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // 背景（左绿右红渐变色）
                LinearGradient(gradient: Gradient(colors: [
                    Color.green.opacity(0.3),
                    Color.gray.opacity(0.15),
                    Color.red.opacity(0.3)
                ]), startPoint: .leading, endPoint: .trailing)
                .frame(height: 12)
                .cornerRadius(6)
                
                // 中间0点
                Circle()
                    .fill(AppColors.textTertiary)
                    .frame(width: 4, height: 4)
                    .offset(x: geo.size.width / 2, y: 0)
                
                // 评分指针
                let pct = (value + 100) / 200
                Circle()
                    .fill(value >= 0 ? AppColors.red : AppColors.green)
                    .frame(width: 10, height: 10)
                    .offset(x: max(5, min(geo.size.width - 5, geo.size.width * CGFloat(pct))), y: 0)
            }
        }
        .frame(height: 12)
    }
    
    private func levelIcon(_ level: CompositeSignal.SignalLevel) -> String {
        switch level {
        case .fierceLong: return "arrow.up.circle.fill"
        case .long: return "arrow.up"
        case .neutral: return "circle"
        case .short: return "arrow.down"
        case .fierceShort: return "arrow.down.circle.fill"
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
                

            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
    
}




