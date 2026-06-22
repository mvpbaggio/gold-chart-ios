import Foundation

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
        isFetchingStock = false
    }
}
