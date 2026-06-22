import SwiftUI

@available(iOS 14.0, *)
struct SettingsView: View {
    @State private var apiKey = UserDefaults.standard.string(forKey: "gold_api_key") ?? ""
    @State private var showSaveAlert = false
    @State private var alertMessage = ""
    
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
                
                // API设置
                settingsSection("数据源设置") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gold API Key（可选）")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.textSecondary)
                        
                        SecureField("输入API Key", text: $apiKey)
                            .foregroundColor(AppColors.textPrimary)
                            .accentColor(AppColors.gold)
                            .padding(10)
                            .background(AppColors.background)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.cardBorder, lineWidth: 1))
                        
                        Text("留空时使用模拟数据。可从 gold-api.com 免费获取。")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                        
                        Button(action: saveAPIKey) {
                            Text("保存")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppColors.background)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                                .background(AppColors.gold)
                                .cornerRadius(6)
                        }
                    }
                }
                
                // 关于
                settingsSection("关于") {
                    VStack(spacing: 6) {
                        settingRow("数据来源", value: "Gold-API / 新浪财经")
                        settingRow("图表引擎", value: "DGCharts")
                        settingRow("适配系统", value: "iOS 14.0+")
                        settingRow("安装方式", value: "TrollStore")
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .alert(isPresented: $showSaveAlert) {
            Alert(title: Text("提示"), message: Text(alertMessage), dismissButton: .default(Text("好")))
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
    
    private func saveAPIKey() {
        UserDefaults.standard.set(apiKey, forKey: "gold_api_key")
        alertMessage = "API Key 已保存"
        showSaveAlert = true
        
        // 实际调用时更新API配置
        // 注：这里需要修改Constants，后续版本可优化
    }
}
