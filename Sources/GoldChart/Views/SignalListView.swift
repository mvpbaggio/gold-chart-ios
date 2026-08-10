import SwiftUI

// MARK: - 信号分析页（接真实数据：综合评分 + 评分明细 + 多空信号列表）
@available(iOS 14.0, *)
struct SignalListView: View {
    @ObservedObject var viewModel: ChartViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // 综合评分卡
                if let cs = viewModel.compositeSignal {
                    scoreCard(cs)
                    
                    // 评分明细
                    breakdownCard(cs)
                } else {
                    emptyView(icon: "chart.bar.xaxis", title: "暂无评分", subtitle: "请先在行情页加载数据")
                        .frame(height: 200)
                }
                
                // 信号列表
                VStack(spacing: 8) {
                    Text("信号列表")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    
                    if viewModel.signalMarkers.isEmpty {
                        emptyView(icon: "bell.slash", title: "暂无信号", subtitle: "出现多空信号后会显示在这里")
                            .frame(height: 140)
                    } else {
                        ForEach(viewModel.signalMarkers.reversed().prefix(30)) { signal in
                            markerCard(signal)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .padding(12)
        }
    }
    
    // MARK: - 综合评分卡
    private func scoreCard(_ cs: CompositeSignal) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("综合多空评分")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                Text(cs.level.rawValue)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: cs.level.color))
            }
            
            // 进度条（-100~+100 → 0~100）
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // 背景渐变
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    AppColors.green,
                                    AppColors.textTertiary,
                                    AppColors.gold,
                                    AppColors.textTertiary,
                                    AppColors.red
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .opacity(0.5)
                        .frame(height: 12)
                    
                    // 指示器
                    Circle()
                        .fill(scoreColor(cs.score))
                        .frame(width: 18, height: 18)
                        .shadow(color: scoreColor(cs.score).opacity(0.5), radius: 4)
                        .offset(x: max(0, min(geo.size.width - 18, CGFloat(cs.score + 100) / 200.0 * geo.size.width - 9)))
                    
                    // 中间线（0 分位置）
                    RoundedRectangle(cornerRadius: 1)
                        .fill(AppColors.textPrimary)
                        .frame(width: 2, height: 18)
                        .offset(x: geo.size.width / 2 - 1)
                }
            }
            .frame(height: 18)
            
            HStack {
                Text("空头 📉")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
                Spacer()
                Text("\(cs.score)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(scoreColor(cs.score))
                Spacer()
                Text("多头 📈")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(14)
        .background(AppColors.cardBackground)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.cardBorder, lineWidth: 1))
    }
    
    // MARK: - 评分明细卡
    private func breakdownCard(_ cs: CompositeSignal) -> some View {
        VStack(spacing: 8) {
            Text("评分明细")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(cs.breakdown) { item in
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 90, alignment: .leading)
                    
                    // 强度条（-100~+100）
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppColors.cardBorder)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(item.score >= 0 ? AppColors.red : AppColors.green)
                                .frame(width: geo.size.width * CGFloat(abs(item.score)) / 100.0, height: 6)
                                .offset(x: item.score >= 0 ? geo.size.width / 2 : geo.size.width / 2 - geo.size.width * CGFloat(abs(item.score)) / 100.0)
                            // 中间线
                            RoundedRectangle(cornerRadius: 0.5)
                                .fill(AppColors.textTertiary)
                                .frame(width: 1, height: 8)
                                .offset(x: geo.size.width / 2 - 0.5)
                        }
                    }
                    .frame(height: 6)
                    
                    Text("\(item.score >= 0 ? "+" : "")\(item.score)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(item.score >= 0 ? AppColors.red : AppColors.green)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(AppColors.cardBackground)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.cardBorder, lineWidth: 1))
    }
    
    // MARK: - 信号卡片
    private func markerCard(_ signal: SignalMarker) -> some View {
        HStack(spacing: 10) {
            // 多/空徽章
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 34, height: 34)
                Circle()
                    .stroke(signal.type == .longOpen ? AppColors.red : (signal.type == .shortOpen ? AppColors.green : AppColors.gold), lineWidth: 2)
                    .frame(width: 34, height: 34)
                Text(signal.type.marker)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(signal.type == .longOpen ? AppColors.red : (signal.type == .shortOpen ? AppColors.green : AppColors.gold))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(signal.type.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    Text(timeString(signal.timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }
                
                HStack(spacing: 8) {
                    Text("价 \(String(format: "%.2f", signal.price))")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary)
                    if let sl = signal.stopLoss {
                        Text("止损 \(String(format: "%.2f", sl))")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.green)
                    }
                    if let st = signal.stopTarget {
                        Text("止盈 \(String(format: "%.2f", st))")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.red)
                    }
                }
            }
        }
        .padding(10)
        .background(AppColors.cardBackground)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.cardBorder, lineWidth: 1))
    }
    
    private func emptyView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(AppColors.textTertiary)
            Text(title)
                .foregroundColor(AppColors.textSecondary)
                .font(.system(size: 15))
            Text(subtitle)
                .foregroundColor(AppColors.textTertiary)
                .font(.system(size: 13))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private func scoreColor(_ score: Int) -> Color {
        if score >= 35 { return AppColors.red }
        if score >= 15 { return AppColors.gold }
        if score > -15 { return AppColors.textSecondary }
        if score > -35 { return AppColors.gold }
        return AppColors.green
    }
    
    private func timeString(_ ts: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.string(from: Date(timeIntervalSince1970: ts / 1000))
    }
}
