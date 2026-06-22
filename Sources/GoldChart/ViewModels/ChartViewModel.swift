import Foundation
import Combine

@available(iOS 14.0, *)
class ChartViewModel: ObservableObject {
    @Published var klines: [Kline] = []
    @Published var selectedProduct: ProductType = .xau
    @Published var selectedPeriod: KlinePeriod = .h1
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var assessment: OverallAssessment?
    
    // 选中的指标
    @Published var showMA = false
    @Published var showEMA = false
    @Published var showMACD = false
    @Published var showRSI = false
    @Published var showKDJ = false
    @Published var showBOLL = false
    @Published var showVolume = true
    
    @Published var selectedIndicator: IndicatorType? = nil
    
    enum IndicatorType: String, CaseIterable {
        case ma = "MA"
        case ema = "EMA"
        case macd = "MACD"
        case rsi = "RSI"
        case kdj = "KDJ"
        case boll = "BOLL"
        case wr = "W%R"
        case atr = "ATR"
        case obv = "OBV"
        case ichimoku = "云图"
        
        var displayName: String { self.rawValue }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        Task { await refresh() }
    }
    
    @MainActor
    func refresh() async {
        isLoading = true
        errorMessage = nil
        
        do {
            klines = try await GoldApiService.shared.fetchKlines(
                product: selectedProduct,
                period: selectedPeriod
            )
            // 评估信号
            if !klines.isEmpty {
                assessment = SignalEngine.evaluateSignals(klines: klines)
            }
        } catch {
            errorMessage = error.localizedDescription
            // 降级到模拟数据
            klines = MockData.generateKlines(count: 200)
            assessment = SignalEngine.evaluateSignals(klines: klines)
        }
        
        isLoading = false
    }
    
    @MainActor
    func changeProduct(_ product: ProductType) {
        selectedProduct = product
        Task { await refresh() }
    }
    
    @MainActor
    func changePeriod(_ period: KlinePeriod) {
        selectedPeriod = period
        Task { await refresh() }
    }
    
    // MARK: - 指标计算
    func computeMA(period: Int = 5) -> [Double?] {
        IndicatorEngine.ma(klines, period: period)
    }
    
    func computeEMA(period: Int = 12) -> [Double?] {
        IndicatorEngine.ema(klines, period: period)
    }
    
    func computeMACD() -> MACDResult {
        IndicatorEngine.macd(klines)
    }
    
    func computeRSI(period: Int = 14) -> [Double?] {
        IndicatorEngine.rsi(klines, period: period)
    }
    
    func computeKDJ() -> KDJResult {
        IndicatorEngine.kdj(klines)
    }
    
    func computeBOLL() -> BollingerResult {
        IndicatorEngine.bollinger(klines)
    }
    
    func computeWR() -> [Double?] {
        IndicatorEngine.williamsR(klines)
    }
    
    func computeOBV() -> [Double?] {
        IndicatorEngine.obv(klines)
    }
    
    func computeATR() -> [Double?] {
        IndicatorEngine.atr(klines)
    }
    
    func computeIchimoku() -> IchimokuResult {
        IndicatorEngine.ichimoku(klines)
    }
    
    // MARK: - 当前价格信息
    var currentPrice: Double {
        klines.last?.close ?? 0
    }
    
    var priceChange: Double {
        guard klines.count >= 2 else { return 0 }
        return klines.last!.close - klines.dropLast().last!.close
    }
    
    var priceChangePercent: Double {
        guard klines.count >= 2 else { return 0 }
        let prev = klines.dropLast().last!.close
        return prev > 0 ? (priceChange / prev) * 100 : 0
    }
    
    var todayHigh: Double {
        klines.last?.high ?? 0
    }
    
    var todayLow: Double {
        klines.last?.low ?? 0
    }
}
