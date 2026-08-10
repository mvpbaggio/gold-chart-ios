import Foundation

/// A股自选股（可持久化到 UserDefaults）
struct FavoriteStock: Codable, Identifiable, Equatable, Hashable {
    let code: String
    let name: String
    let market: String
    
    var id: String { code }
    
    var marketDisplay: String {
        market == "sh" ? "沪" : "深"
    }
}

@available(iOS 14.0, *)
class SearchViewModel: ObservableObject {
    @Published var query = "" {
        didSet {
            if query.count >= 1 {
                Task { await doSearch() }
            }
        }
    }
    @Published var results: [StockApiService.StockItem] = []
    @Published var isLoading = false
    @Published var selectedStock: StockApiService.StockItem?
    @Published var stockKlines: [Kline] = []
    @Published var isFetchingStock = false
    @Published var stockSignals: [SignalMarker] = []
    @Published var stockScore: Int = 0
    @Published var stockComposite: CompositeSignal?
    @Published var favorites: [FavoriteStock] = []
    /// 重置令牌：自选列表重建用（切回 A股 tab 时强制重建整棵树，避开详情页残留/搜索框残留）
    @Published var resetToken = 0
    
    private static let favoritesKey = "stock_favorites"
    
    init() {
        loadFavorites()
    }
    
    // MARK: - 自选股
    
    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: Self.favoritesKey),
              let list = try? JSONDecoder().decode([FavoriteStock].self, from: data) else {
            favorites = []
            return
        }
        favorites = list
    }
    
    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: Self.favoritesKey)
        }
    }
    
    func isFavorite(code: String) -> Bool {
        favorites.contains { $0.code == code }
    }
    
    func toggleFavorite(_ stock: StockApiService.StockItem) {
        if let idx = favorites.firstIndex(where: { $0.code == stock.code }) {
            var newList = favorites
            newList.remove(at: idx)
            favorites = newList
        } else {
            var newList = favorites
            newList.append(FavoriteStock(code: stock.code, name: stock.name, market: stock.market))
            favorites = newList
        }
        saveFavorites()
    }
    
    func removeFavorite(_ stock: FavoriteStock) {
        var newList = favorites
        newList.removeAll { $0.code == stock.code }
        favorites = newList
        saveFavorites()
    }
    
    @MainActor
    func selectFavorite(_ stock: FavoriteStock) {
        let item = StockApiService.StockItem(code: stock.code, name: stock.name, market: stock.market, pinyin: "")
        selectStock(item)
    }
    
    @MainActor
    func resetToFavorites() {
        // 切回 A股 tab 且不在搜索中：复位详情页 + 搜索框，保证自选列表可见
        selectedStock = nil
        stockKlines = []
        isFetchingStock = false
        query = ""
        results = []
        resetToken += 1
    }

    // MARK: - 搜索与详情
    
    @MainActor
    func doSearch() async {
        guard query.count >= 1 else {
            results = []
            return
        }
        
        isLoading = true
        do {
            results = try await StockApiService.shared.searchStocks(keyword: query)
        } catch {
            results = []
        }
        isLoading = false
    }
    
    @MainActor
    func selectStock(_ stock: StockApiService.StockItem) {
        selectedStock = stock
        query = stock.displayName
        results = []
        Task { await fetchStockData() }
    }
    
    @MainActor
    func fetchStockData() async {
        guard let stock = selectedStock else { return }
        isFetchingStock = true
        do {
            stockKlines = try await StockApiService.shared.fetchStockKlines(code: stock.code)
        } catch {
            stockKlines = MockData.generateKlines(count: 90)
        }
        // A股信号引擎（timing×1 + 23指标×3，只做多，吊灯止损）
        stockSignals = StockSignalEngine.perCandleSignals(stockKlines)
        let cs = StockSignalEngine.composite(stockKlines)
        stockComposite = cs
        stockScore = cs.score
        isFetchingStock = false
    }
}
