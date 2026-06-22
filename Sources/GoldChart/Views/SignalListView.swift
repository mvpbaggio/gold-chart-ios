import SwiftUI

@available(iOS 14.0, *)
struct SignalListView: View {
    let assessment: OverallAssessment?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let assessment = assessment {
                    // 综合评分卡片
                    scoreCard(assessment)
                    
                    // 信号列表
                    VStack(spacing: 8) {
                        Text("信号详情")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        
                        ForEach(assessment.signals) { signal in
                            signalCard(signal)
                        }
                    }
                    .padding(.top, 8)
                } else {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 48))
                            .foregroundColor(AppColors.textTertiary)
                        Text("暂无数据")
                            .foregroundColor(AppColors.textSecondary)
                            .font(.system(size: 15))
                        Text("请先在行情页加载数据")
                            .foregroundColor(AppColors.textTertiary)
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .frame(height: 400)
                }
            }
            .padding(12)
        }
    }
    
    private func scoreCard(_ assessment: OverallAssessment) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("综合多空评分")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                Text(assessment.level)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(scoreColor(assessment.score))
            }
            
            // 进度条
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
                        .fill(scoreColor(assessment.score))
                        .frame(width: 18, height: 18)
                        .shadow(color: scoreColor(assessment.score).opacity(0.5), radius: 4)
                        .offset(x: max(0, min(geo.size.width - 18, CGFloat(assessment.score) / 100.0 * geo.size.width - 9)))
                    
                    // 中间线
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
                Text("\(assessment.score)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(scoreColor(assessment.score))
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
    
    private func signalCard(_ signal: TradeSignal) -> some View {
        HStack(spacing: 10) {
            // 信号类型指示
            RoundedRectangle(cornerRadius: 4)
                .fill(signalTypeColor(signal.type))
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(signal.description)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    Text("\(signal.strength)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(signalTypeColor(signal.type))
                }
                
                if let detail = signal.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textSecondary)
                }
                
                // 强度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.cardBorder)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(signalTypeColor(signal.type))
                            .frame(width: geo.size.width * CGFloat(signal.strength) / 100.0, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(12)
        .background(AppColors.cardBackground)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.cardBorder, lineWidth: 1))
    }
    
    private func scoreColor(_ score: Int) -> Color {
        if score >= 70 { return AppColors.red }
        if score >= 55 { return AppColors.gold }
        if score >= 45 { return AppColors.textSecondary }
        if score >= 30 { return AppColors.gold }
        return AppColors.green
    }
    
    private func signalTypeColor(_ type: TradeSignal.SignalType) -> Color {
        switch type {
        case .buy: return AppColors.red
        case .sell: return AppColors.green
        case .neutral: return AppColors.textTertiary
        case .warning: return .orange
        }
    }
}
