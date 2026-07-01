import SwiftUI

@available(iOS 14.0, *)
struct ContentView: View {
    @StateObject private var chartVM = ChartViewModel()
    @StateObject private var searchVM = SearchViewModel()
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶部栏
                headerBar
                
                // Tab内容
                TabView(selection: $selectedTab) {
                    chartTab
                        .tag(0)
                    
                    signalTab
                        .tag(1)
                    
                    stockSearchTab
                        .tag(2)
                    
                    settingsTab
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // 底部导航
                bottomNav
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - 顶部栏
    private var headerBar: some View {
        HStack {
            if selectedTab == 0 {
                // 品种切换
                HStack(spacing: 0) {
                    ForEach(ProductType.allCases, id: \.self) { product in
                        Button(action: { chartVM.changeProduct(product) }) {
                            Text(product.displayName)
                                .font(.system(size: 14, weight: chartVM.selectedProduct == product ? .bold : .regular))
                                .foregroundColor(chartVM.selectedProduct == product ? AppColors.gold : AppColors.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    chartVM.selectedProduct == product
                                        ? AppColors.gold.opacity(0.15)
                                        : Color.clear
                                )
                                .cornerRadius(6)
                        }
                    }
                }
            } else {
                Text(selectedTab == 1 ? "信号分析" : selectedTab == 2 ? "A股搜索" : "设置")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
            }
            
            Spacer()
            
            if selectedTab == 0 {
                // 刷新按钮
                Button(action: { Task { await chartVM.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(AppColors.gold)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - 图表Tab
    private var chartTab: some View {
        ChartView(viewModel: chartVM)
            .background(AppColors.background)
    }
    
    // MARK: - 信号Tab
    private var signalTab: some View {
        // 旧版信号已被11指标综合评分替代
        VStack {
            Text("多指标综合评分")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
            Spacer()
        }
        .background(AppColors.background)
    }
    
    // MARK: - A股搜索Tab
    private var stockSearchTab: some View {
        StockSearchView(viewModel: searchVM)
            .background(AppColors.background)
    }
    
    // MARK: - 设置Tab
    private var settingsTab: some View {
        SettingsView()
            .background(AppColors.background)
    }
    
    // MARK: - 底部导航
    private var bottomNav: some View {
        HStack(spacing: 0) {
            navItem(index: 0, icon: "chart.bar.fill", label: "行情")
            navItem(index: 1, icon: "bell.badge.fill", label: "信号")
            navItem(index: 2, icon: "magnifyingglass", label: "A股")
            navItem(index: 3, icon: "gearshape.fill", label: "设置")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppColors.cardBackground)
        .overlay(Divider().background(AppColors.cardBorder), alignment: .top)
    }
    
    private func navItem(index: Int, icon: String, label: String) -> some View {
        Button(action: { selectedTab = index }) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(selectedTab == index ? AppColors.tabActive : AppColors.tabInactive)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(selectedTab == index ? AppColors.tabActive : AppColors.tabInactive)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 预览
@available(iOS 14.0, *)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
