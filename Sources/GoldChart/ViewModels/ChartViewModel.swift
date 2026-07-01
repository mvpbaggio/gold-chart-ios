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
    
    // 人民币计价
    @Published var useCNY = false
    
    // 实时K线（最后一根K线随实时行情延伸）
    @Published var realtimeKlines: [Kline] = []
    
    // 选中的指标
    @Published var showMA = false
    @Published var showEMA = false
    @Published var showMACD = false
    @Published var showRSI = false
    @Published var showKDJ = false
    @Published var showBOLL = false
    @Published var showVolume = true
    @Published var showSignals = true
    @Published var showStopLoss = true
    
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
            .sink { [weak self] quote in
                guard let self = self, let quote = quote else { return }
                self.realTimeQuote = quote
                self.updateRealtimeCandle(quote: quote)
            }
            .store(in: &cancellables)
        
        RealTimeService.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRealTimeConnected)
        
        Task { await refresh() }
    }
    
    // MARK: - 人民币计价（元/克）
    /// 1金衡盎司 = 31.1034768克
    static let gramPerOunce: Double = 31.1034768
    
    /// 当前汇率
    var currentRate: Double {
        RealTimeService.shared.exchangeRate
    }
    
    /// 盎司→克换算系数
    var ounceToGram: Double {
        Self.gramPerOunce
    }
    
    /// 人民币价格（元/克）
    var cnyPrice: Double {
        currentPrice * currentRate / ounceToGram
    }
    
    /// 人民币涨跌额（元/克）
    var cnyChange: Double {
        priceChange * currentRate / ounceToGram
    }
    
    /// 人民币涨跌幅（沿用百分比不变）
    var cnyChangePercent: Double {
        changePercent
    }
    
    /// 人民币最高（元/克）
    var cnyHigh: Double {
        todayHigh * currentRate / ounceToGram
    }
    
    /// 人民币最低（元/克）
    var cnyLow: Double {
        todayLow * currentRate / ounceToGram
    }
    
    /// 获取实时价格（按币种）
    var displayPrice: Double {
        useCNY ? cnyPrice : currentPrice
    }
    
    var displayChange: Double {
        useCNY ? cnyChange : priceChange
    }
    
    var displayChangePercent: Double {
        useCNY ? cnyChangePercent : changePercent
    }
    
    var displayHigh: Double {
        useCNY ? cnyHigh : todayHigh
    }
    
    var displayLow: Double {
        useCNY ? cnyLow : todayLow
    }
    
    var displayLabel: String {
        useCNY ? "\(selectedProduct.displayName)" : selectedProduct.displayName
    }
    
    /// 获取换算后的K线数据供图表使用
    var displayKlines: [Kline] {
        if useCNY {
            let rate = currentRate / ounceToGram
            return realtimeKlines.map { kline in
                Kline(
                    timestamp: kline.timestamp,
                    open: kline.open * rate,
                    high: kline.high * rate,
                    low: kline.low * rate,
                    close: kline.close * rate,
                    volume: kline.volume
                )
            }
        }
        return realtimeKlines
    }
    
    // MARK: - 实时K线延伸
    
    private func updateRealtimeCandle(quote: RealTimeQuote) {
        guard !realtimeKlines.isEmpty else { return }
        var updated = realtimeKlines
        var last = updated.removeLast()
        
        // 如果实时行情时间超过K线周期，则新建一根（正常情况）
        // 否则更新最后一根的最高/最低/收盘
        let lastKlineTime = last.timestamp
        let timePerCandle = periodInSeconds
        let now = Date().timeIntervalSince1970 * 1000
        
        if now - lastKlineTime >= timePerCandle {
            // 新K线：使用当前实时数据
            let newCandle = Kline(
                timestamp: lastKlineTime + timePerCandle,
                open: quote.price,
                high: quote.price,
                low: quote.price,
                close: quote.price,
                volume: 0
            )
            updated.append(last)
            updated.append(newCandle)
        } else {
            // 更新最后一根
            let newHigh = max(last.open, last.close, quote.price, last.high)
            let newLow = min(last.open, last.close, quote.price, last.low)
            let newClose = quote.price
            let updatedLast = Kline(
                timestamp: last.timestamp,
                open: last.open,
                high: newHigh,
                low: newLow,
                close: newClose,
                volume: last.volume
            )
            updated.append(updatedLast)
        }
        
        realtimeKlines = updated
    }
    
    private var periodInSeconds: Double {
        switch selectedPeriod {
        case .m1: return 60_000
        case .m5: return 300_000
        case .m15: return 900_000
        case .m30: return 1_800_000
        case .h1: return 3_600_000
        case .h4: return 14_400_000
        case .d1: return 86_400_000
        case .w1: return 604_800_000
        }
    }
    
    // MARK: - 刷新
    
    @MainActor
    func refresh() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let fetched = try await GoldApiService.shared.fetchKlines(
                product: selectedProduct,
                period: selectedPeriod
            )
            klines = fetched
            realtimeKlines = fetched
            if !fetched.isEmpty {
                assessment = SignalEngine.evaluateSignals(klines: fetched)
                signalMarkers = SignalEngine.detectPerCandleSignals(fetched)
                updatePosition()
            }
        } catch {
            errorMessage = error.localizedDescription
            let mock = MockData.generateKlines(count: 200)
            klines = mock
            realtimeKlines = mock
            if !mock.isEmpty {
                assessment = SignalEngine.evaluateSignals(klines: mock)
                signalMarkers = SignalEngine.detectPerCandleSignals(mock)
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
    
    func toggleCNY() {
        useCNY.toggle()
    }
    
    deinit {
        RealTimeService.shared.stopPolling()
    }
    
    // MARK: - 持仓追踪
    private func updatePosition() {
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
        let currentPrice = realTimeQuote?.price ?? realtimeKlines.last?.close ?? 0
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
    
    var activeSignals: [SignalMarker] {
        guard !signalMarkers.isEmpty else { return [] }
        let entries = signalMarkers.filter { $0.type.isEntry }
        let lastEntry = entries.last
        return entries.filter { $0.candleIndex >= (lastEntry?.candleIndex ?? 0) - 5 }
    }
    
    var stopLossLevels: [(price: Double, label: String, color: String)] {
        var levels: [(Double, String, String)] = []
        let rate = useCNY ? (currentRate / ounceToGram) : 1
        for signal in activeSignals {
            guard let sl = signal.stopLoss else { continue }
            let slPrice = sl * rate
            if signal.type == .longOpen {
                levels.append((slPrice, "止损 \(String(format: "%.1f", slPrice))", "#EF4444"))
                if let st = signal.stopTarget {
                    let stPrice = st * rate
                    levels.append((stPrice, "止盈 \(String(format: "%.1f", stPrice))", "#22C55E"))
                }
            } else if signal.type == .shortOpen {
                levels.append((slPrice, "止损 \(String(format: "%.1f", slPrice))", "#EF4444"))
                if let st = signal.stopTarget {
                    let stPrice = st * rate
                    levels.append((stPrice, "止盈 \(String(format: "%.1f", stPrice))", "#22C55E"))
                }
            }
        }
        return levels
    }
    
    // MARK: - 指标计算（使用原始K线数据）
    func computeMA(period: Int = 5) -> [Double?] {
        IndicatorEngine.ma(realtimeKlines, period: period)
    }
    
    func computeEMA(period: Int = 12) -> [Double?] {
        IndicatorEngine.ema(realtimeKlines, period: period)
    }
    
    func computeMACD() -> MACDResult {
        IndicatorEngine.macd(realtimeKlines)
    }
    
    func computeRSI(period: Int = 14) -> [Double?] {
        IndicatorEngine.rsi(realtimeKlines, period: period)
    }
    
    func computeKDJ() -> KDJResult {
        IndicatorEngine.kdj(realtimeKlines)
    }
    
    func computeBOLL() -> BollingerResult {
        IndicatorEngine.bollinger(realtimeKlines)
    }
    
    func computeWR() -> [Double?] {
        IndicatorEngine.williamsR(realtimeKlines)
    }
    
    func computeOBV() -> [Double?] {
        IndicatorEngine.obv(realtimeKlines)
    }
    
    func computeATR() -> [Double?] {
        IndicatorEngine.atr(realtimeKlines)
    }
    
    func computeIchimoku() -> IchimokuResult {
        IndicatorEngine.ichimoku(realtimeKlines)
    }
    
    // MARK: - 当前价格信息（原始USD价）
    var currentPrice: Double {
        realTimeQuote?.price ?? realtimeKlines.last?.close ?? 0
    }
    
    var priceChange: Double {
        realTimeQuote?.change ?? 0
    }
    
    var changePercent: Double {
        realTimeQuote?.changePercent ?? 0
    }
    
    var todayHigh: Double {
        realTimeQuote?.high ?? realtimeKlines.last?.high ?? 0
    }
    
    var todayLow: Double {
        realTimeQuote?.low ?? realtimeKlines.last?.low ?? 0
    }
}
