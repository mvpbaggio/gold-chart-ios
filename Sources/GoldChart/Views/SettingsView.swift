import SwiftUI

@available(iOS 14.0, *)
struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 应用信息
                VStack(spacing: 0) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.gold)
                        .padding(.bottom, 8)
                    
                    Text(Constants.appName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                    
                    Text("v\(Constants.version)")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.top, 2)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .background(AppColors.cardBackground)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.cardBorder, lineWidth: 1))
                .padding(.horizontal, 12)
                
                // 数据源信息
                settingsSection("数据源") {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.green)
                                .font(.system(size: 14))
                            Text("黄金/白银")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.textSecondary)
                            Spacer()
                            Text("aurumrates.com")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.textPrimary)
                        }
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.green)
                                .font(.system(size: 14))
                            Text("A股行情")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.textSecondary)
                            Spacer()
                            Text("新浪财经")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.textPrimary)
                        }
                        
                        Text("所有数据源均为免费开放接口，无需配置")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                            .padding(.top, 4)
                    }
                }
                
                // 关于
                settingsSection("关于") {
                    VStack(spacing: 6) {
                        settingRow("版本", value: Constants.version)
                        settingRow("图表引擎", value: "DGCharts")
                        settingRow("适配系统", value: "iOS 14.0+")
                        settingRow("安装方式", value: "TrollStore")
                    }
                }
                
                // 说明
                settingsSection("使用说明") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• 底部切换 行情/信号/A股/设置")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textSecondary)
                        Text("• 顶部切换 黄金/白银")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textSecondary)
                        Text("• 横向滚动选择周期和指标")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textSecondary)
                        Text("• aurumrates.com 限制100次/小时")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }
    
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal, 4)
            
            content()
        }
        .padding(12)
        .background(AppColors.cardBackground)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.cardBorder, lineWidth: 1))
        .padding(.horizontal, 12)
    }
    
    private func settingRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(AppColors.textPrimary)
        }
    }
}
