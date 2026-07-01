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
    @Published var signalMarkers: [SignalMarker] = []
    @Published var position: PositionDirection = .none
    @Published var entryPrice: Double = 0
    @Published var pnl: Double = 0
    @Published var pnlPercent: Double = 0
    
    // 实时行情
    @Published var realTimeQuote: RealTimeQuote?
    @Published var isRealTimeConnected = false
    
    // 选中的指标
    @Published var showMA = false
    @Published var showEMA = false
    @Published var showMACD = false
    @Published var showRSI = false
    @Published var showKDJ = false
    @Published var showBOLL = false
    @Published var showVolume = true
    @Published var showSignals = true     // 是否显示信号标记
    @Published var showStopLoss = true    // 是否显示止损线
    
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
        // 订阅实时行情
        RealTimeService.shared.$quote
            .receive(on: DispatchQueue.main)
            .assign(to: &$realTimeQuote)
        
        RealTimeService.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRealTimeConnected)
        
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
                signalMarkers = SignalEngine.detectPerCandleSignals(klines)
                updatePosition()
            }
        } catch {
            errorMessage = error.localizedDescription
            // 降级到模拟数据
            klines = MockData.generateKlines(count: 200)
            if !klines.isEmpty {
                assessment = SignalEngine.evaluateSignals(klines: klines)
                signalMarkers = SignalEngine.detectPerCandleSignals(klines)
            }
        }
        
        // 启动实时行情
        RealTimeService.shared.startPolling(product: selectedProduct)
        
        isLoading = false
    }
    
    @MainActor
    func changeProduct(_ product: ProductType) {
        selectedProduct = product
        RealTimeService.shared.startPolling(product: product)
        Task { await refresh() }
    }
    
    @MainActor
    func changePeriod(_ period: KlinePeriod) {
        selectedPeriod = period
        Task { await refresh() }
    }
    
    deinit {
        RealTimeService.shared.stopPolling()
    }
    
    // MARK: - 持仓追踪
    private func updatePosition() {
        // 根据最后几个信号判断当前持仓方向
        let entries = signalMarkers.filter { $0.type.isEntry }.suffix(5)
        guard let last = entries.last else {
            position = .none
            return
        }
        
        if last.type == .longOpen {
            position = .long
            entryPrice = last.price
        } else if last.type == .shortOpen {
            position = .short
            entryPrice = last.price
        }
        
        // 检查有没有平仓信号覆盖
        let closes = signalMarkers.filter { !$0.type.isEntry }.suffix(2)
        if let lastClose = closes.last {
            if lastClose.candleIndex >= last.candleIndex {
                position = .none
                entryPrice = 0
            }
        }
        
        updatePnL()
    }
    
    private func updatePnL() {
        let currentPrice = realTimeQuote?.price ?? klines.last?.close ?? 0
        guard entryPrice > 0 else {
            pnl = 0
            pnlPercent = 0
            return
        }
        
        switch position {
        case .long:
            pnl = currentPrice - entryPrice
            pnlPercent = (pnl / entryPrice) * 100
        case .short:
            pnl = entryPrice - currentPrice
            pnlPercent = (pnl / entryPrice) * 100
        case .none:
            pnl = 0
            pnlPercent = 0
        }
    }
    
    // MARK: - 活跃信号（最近的未平仓信号）
    var activeSignals: [SignalMarker] {
        guard !signalMarkers.isEmpty else { return [] }
        let entries = signalMarkers.filter { $0.type.isEntry }
        let lastEntry = entries.last
        return entries.filter { $0.candleIndex >= (lastEntry?.candleIndex ?? 0) - 5 }
    }
    
    // MARK: - 止损线数据
    var stopLossLevels: [(price: Double, label: String, color: String)] {
        var levels: [(Double, String, String)] = []
        for signal in activeSignals {
            guard let sl = signal.stopLoss else { continue }
            if signal.type == .longOpen {
                levels.append((sl, "止损 \(String(format: "%.1f", sl))", "#EF4444"))
                if let st = signal.stopTarget {
                    levels.append((st, "止盈 \(String(format: "%.1f", st))", "#22C55E"))
                }
            } else if signal.type == .shortOpen {
                levels.append((sl, "止损 \(String(format: "%.1f", sl))", "#EF4444"))
                if let st = signal.stopTarget {
                    levels.append((st, "止盈 \(String(format: "%.1f", st))", "#22C55E"))
                }
            }
        }
        return levels
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
        realTimeQuote?.price ?? klines.last?.close ?? 0
    }
    
    var priceChange: Double {
        realTimeQuote?.change ?? (klines.count >= 2 ? klines.last!.close - klines.dropLast().last!.close : 0)
    }
    
    var priceChangePercent: Double {
        realTimeQuote?.changePercent ?? 0
    }
    
    var todayHigh: Double {
        realTimeQuote?.high ?? klines.last?.high ?? 0
    }
    
    var todayLow: Double {
        realTimeQuote?.low ?? klines.last?.low ?? 0
    }
}
