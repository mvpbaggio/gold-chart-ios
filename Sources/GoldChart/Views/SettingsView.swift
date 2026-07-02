import SwiftUI

@available(iOS 14.0, *)
struct SettingsView: View {
    @State private var proxyURL: String = API.proxyBase
    @State private var showSaved = false
    
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
                
                // 代理服务器配置
                settingsSection("代理服务器") {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "server.rack")
                                .foregroundColor(AppColors.gold)
                                .font(.system(size: 14))
                            Text("K线数据代理")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.textSecondary)
                            Spacer()
                            Text("优先使用")
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.green)
                        }
                        
                        TextField("代理URL", text: $proxyURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.system(size: 13))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: proxyURL) { newValue in
                                API.setProxyURL(newValue)
                            }
                        
                        HStack {
                            Text("默认: http://192.168.0.114:28789/api")
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textTertiary)
                            Spacer()
                            if showSaved {
                                Text("✓ 已保存")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppColors.green)
                            }
                        }
                        
                        Text("如果代理不可用，自动回退到 Yahoo Finance 直连 + 模拟数据")
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
