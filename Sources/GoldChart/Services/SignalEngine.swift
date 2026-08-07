import Foundation

// MARK: - 信号引擎（技能版评分 + 追风揽月信号/止损/止盈）
// 评分公式（aistockresearcher 技术评分 + KDJ 补充）：
//   均线 ±40 + RSI ±15 + MACD ±20 + 布林 ±10 + KDJ ±10 → -100~+100
//   >20 多 / <−20 空 / 中间观望
// 追风揽月规则：
//   信号 → K线图上标「多」/「空」圆点；反向信号 → 平仓并开反向仓
//   止损逻辑1：多头=信号K线最低点，空头=信号K线最高点
//   止损逻辑2：多头=最低价−1%，空头=最高价+1%
//   止盈逻辑1：多头累计+5%，空头累计−5%
//   止盈逻辑2：出现反向信号即止盈
class SignalEngine {
    
    // MARK: - 配置
    struct Config {
        var longThreshold: Int = 25        // 评分 > 25 做多
        var shortThreshold: Int = -25      // 评分 < -25 做空
        var takeProfitPercent: Double = 5.0 // 止盈：累计涨跌幅 5%
        var stopLossMode: Int = 2          // 1=信号K线极值，2=极值±1%
        var stopLossBuffer: Double = 0.01  // 缓冲 1%
        
        static let `default` = Config()
    }
    
    static var config = Config.default
    
    // MARK: - 技能版综合评分
    static func composite(_ data: [Kline]) -> CompositeSignal {
        guard data.count >= 60 else {
            return CompositeSignal(score: 0, breakdown: [
                SignalBreakdown(name: "数据不足", score: 0, weight: 1.0)
            ])
        }
        
        var breakdowns: [SignalBreakdown] = []
        
        // 1. 均线状态 (±40)
        breakdowns.append(scoreMA(data))
        
        // 2. RSI (±15)
        breakdowns.append(scoreRSI(data))
        
        // 3. MACD (±20)
        breakdowns.append(scoreMACD(data))
        
        // 4. 布林带位置 (±10)
        breakdowns.append(scoreBollinger(data))
        
        // 5. KDJ 金叉死叉 (±10)
        breakdowns.append(scoreKDJ(data))
        
        // 累加总分 -100~+100
        var totalScore: Double = 0
        for b in breakdowns {
            totalScore += Double(b.score)
        }
        totalScore = max(-100, min(100, totalScore))
        
        return CompositeSignal(score: Int(totalScore.rounded()), breakdown: breakdowns)
    }
    
    // MARK: - 1. 均线状态 (±40)
    // 多头排列 +40 / 空头排列 −40 / MA5>MA20 +20 / 否则 −20
    private static func scoreMA(_ data: [Kline]) -> SignalBreakdown {
        guard data.count >= 60 else {
            return SignalBreakdown(name: "均线", score: 0, weight: 1.0)
        }
        
        let arrangement = IndicatorEngine.maArrangement(data)
        
        if arrangement == "多头排列" {
            return SignalBreakdown(name: "均线多头", score: 40, weight: 1.0)
        }
        if arrangement == "空头排列" {
            return SignalBreakdown(name: "均线空头", score: -40, weight: 1.0)
        }
        
        // 混乱：看 MA5 vs MA20
        let ma5 = IndicatorEngine.ma(data, period: 5).compactMap { $0 }.last ?? 0
        let ma20 = IndicatorEngine.ma(data, period: 20).compactMap { $0 }.last ?? 0
        if ma5 > ma20 {
            return SignalBreakdown(name: "均线偏多", score: 20, weight: 1.0)
        }
        return SignalBreakdown(name: "均线偏空", score: -20, weight: 1.0)
    }
    
    // MARK: - 2. RSI (±15)
    // <30 超卖 +15 / >70 超买 −15 / 中性 >50 +5 / <50 −5
    private static func scoreRSI(_ data: [Kline]) -> SignalBreakdown {
        guard data.count >= 20 else {
            return SignalBreakdown(name: "RSI", score: 0, weight: 1.0)
        }
        
        let rsiValues = IndicatorEngine.rsi(data)
        guard let lastRSI = rsiValues.compactMap({ $0 }).last else {
            return SignalBreakdown(name: "RSI", score: 0, weight: 1.0)
        }
        
        if lastRSI < 30 {
            return SignalBreakdown(name: "RSI超卖", score: 15, weight: 1.0)
        }
        if lastRSI > 70 {
            return SignalBreakdown(name: "RSI超买", score: -15, weight: 1.0)
        }
        if lastRSI > 50 {
            return SignalBreakdown(name: "RSI偏强", score: 5, weight: 1.0)
        }
        return SignalBreakdown(name: "RSI偏弱", score: -5, weight: 1.0)
    }
    
    // MARK: - 3. MACD (±20)
    // 柱 > 0 +20 / < 0 −20
    private static func scoreMACD(_ data: [Kline]) -> SignalBreakdown {
        guard data.count >= 30 else {
            return SignalBreakdown(name: "MACD", score: 0, weight: 1.0)
        }
        
        let macd = IndicatorEngine.macd(data)
        guard let hist = macd.histogram.compactMap({ $0 }).last else {
            return SignalBreakdown(name: "MACD", score: 0, weight: 1.0)
        }
        
        if hist > 0 {
            return SignalBreakdown(name: "MACD多头", score: 20, weight: 1.0)
        }
        return SignalBreakdown(name: "MACD空头", score: -20, weight: 1.0)
    }
    
    // MARK: - 4. 布林带位置 (±10)
    // bb_position > 80 接近上轨 −10 / < 20 接近下轨 +10
    private static func scoreBollinger(_ data: [Kline]) -> SignalBreakdown {
        guard data.count >= 26 else {
            return SignalBreakdown(name: "布林", score: 0, weight: 1.0)
        }
        
        guard let pos = IndicatorEngine.bollingerPosition(data) else {
            return SignalBreakdown(name: "布林", score: 0, weight: 1.0)
        }
        
        if pos > 80 {
            return SignalBreakdown(name: "布林上轨", score: -10, weight: 1.0)
        }
        if pos < 20 {
            return SignalBreakdown(name: "布林下轨", score: 10, weight: 1.0)
        }
        return SignalBreakdown(name: "布林中轨", score: 0, weight: 1.0)
    }
    
    // MARK: - 5. KDJ 金叉死叉 (±10)
    // 低位金叉 +10 / 高位死叉 −10
    private static func scoreKDJ(_ data: [Kline]) -> SignalBreakdown {
        guard data.count >= 20 else {
            return SignalBreakdown(name: "KDJ", score: 0, weight: 1.0)
        }
        
        let kdj = IndicatorEngine.kdj(data)
        let kArr = kdj.k.compactMap { $0 }
        let dArr = kdj.d.compactMap { $0 }
        guard let k = kArr.last, let d = dArr.last,
              kArr.count >= 2, dArr.count >= 2 else {
            return SignalBreakdown(name: "KDJ", score: 0, weight: 1.0)
        }
        
        let prevK = kArr[kArr.count - 2]
        let prevD = dArr[dArr.count - 2]
        
        // 金叉（K上穿D + 低位）
        if prevK <= prevD && k > d && k < 40 {
            return SignalBreakdown(name: "KDJ金叉", score: 10, weight: 1.0)
        }
        // 死叉（K下穿D + 高位）
        if prevK >= prevD && k < d && k > 60 {
            return SignalBreakdown(name: "KDJ死叉", score: -10, weight: 1.0)
        }
        
        // 无交叉：K值位置
        let score = Int((k - 50) / 5)
        return SignalBreakdown(name: "KDJ", score: max(-10, min(10, score)), weight: 1.0)
    }
    
    // MARK: - 逐根K线历史信号（追风揽月风格）
    /// 遍历每根K线，评分>20标「多」、<-20标「空」；反向信号触发平仓并开反向仓；
    /// 止盈：持仓累计涨跌幅达 5% 平仓；止损：触发信号K线极值（±1% 缓冲可选）
    static func perCandleSignals(_ data: [Kline]) -> [SignalMarker] {
        guard data.count >= 60 else { return [] }
        var signals: [SignalMarker] = []
        
        var position: PositionDirection = .none   // 当前持仓
        var entryPrice: Double = 0                 // 开仓价
        var entryStopLoss: Double = 0              // 止损价
        var entryIndex: Int = 0                    // 开仓K线索引
        
        for i in 59..<data.count {
            let prefix = Array(data[0...i])
            let cs = composite(prefix)
            let candle = data[i]
            let score = cs.score
            let close = candle.close
            
            // 计算止损价（追风揽月：信号K线极值 ±1% 缓冲）
            func stopLossFor(type: SignalMarker.SignalType) -> Double {
                if type == .longOpen {
                    let base = candle.low
                    return config.stopLossMode == 2 ? base * (1 - config.stopLossBuffer) : base
                } else {
                    let base = candle.high
                    return config.stopLossMode == 2 ? base * (1 + config.stopLossBuffer) : base
                }
            }
            
            // 止盈检查（持仓累计涨跌幅 ≥5%）
            if position != .none {
                let pnlPct = position == .long
                    ? (close - entryPrice) / entryPrice * 100
                    : (entryPrice - close) / entryPrice * 100
                
                if pnlPct >= config.takeProfitPercent {
                    signals.append(SignalMarker(
                        candleIndex: i,
                        type: position == .long ? .longClose : .shortClose,
                        price: close,
                        stopLoss: entryStopLoss,
                        stopTarget: close,
                        strength: min(Int(pnlPct * 10), 100),
                        source: "止盈\(Int(config.takeProfitPercent))%",
                        timestamp: candle.timestamp
                    ))
                    position = .none
                }
            }
            
            // 止损检查
            if position == .long && close <= entryStopLoss {
                signals.append(SignalMarker(
                    candleIndex: i,
                    type: .longClose,
                    price: close,
                    stopLoss: entryStopLoss,
                    stopTarget: close,
                    strength: 100,
                    source: "止损",
                    timestamp: candle.timestamp
                ))
                position = .none
            } else if position == .short && close >= entryStopLoss {
                signals.append(SignalMarker(
                    candleIndex: i,
                    type: .shortClose,
                    price: close,
                    stopLoss: entryStopLoss,
                    stopTarget: close,
                    strength: 100,
                    source: "止损",
                    timestamp: candle.timestamp
                ))
                position = .none
            }
            
            // 开仓信号：只在状态转换时开仓（避免同一持仓周期内重复发信号 → 徽章爆炸）
            if position != .long && score >= config.longThreshold {
                // 反向持仓 → 先平仓（止盈逻辑2：出现反向信号即平仓）
                if position == .short {
                    signals.append(SignalMarker(
                        candleIndex: i,
                        type: .shortClose,
                        price: close,
                        stopLoss: entryStopLoss,
                        stopTarget: close,
                        strength: min(abs(score), 100),
                        source: "反向信号",
                        timestamp: candle.timestamp
                    ))
                }
                let sl = stopLossFor(type: .longOpen)
                signals.append(SignalMarker(
                    candleIndex: i,
                    type: .longOpen,
                    price: close,
                    stopLoss: sl,
                    stopTarget: close * (1 + config.takeProfitPercent / 100),
                    strength: min(score, 100),
                    source: "追风揽月",
                    timestamp: candle.timestamp
                ))
                position = .long
                entryPrice = close
                entryStopLoss = sl
                entryIndex = i
                
            } else if position != .short && score <= config.shortThreshold {
                // 反向持仓 → 先平仓
                if position == .long {
                    signals.append(SignalMarker(
                        candleIndex: i,
                        type: .longClose,
                        price: close,
                        stopLoss: entryStopLoss,
                        stopTarget: close,
                        strength: min(abs(score), 100),
                        source: "反向信号",
                        timestamp: candle.timestamp
                    ))
                }
                let sl = stopLossFor(type: .shortOpen)
                signals.append(SignalMarker(
                    candleIndex: i,
                    type: .shortOpen,
                    price: close,
                    stopLoss: sl,
                    stopTarget: close * (1 - config.takeProfitPercent / 100),
                    strength: min(abs(score), 100),
                    source: "追风揽月",
                    timestamp: candle.timestamp
                ))
                position = .short
                entryPrice = close
                entryStopLoss = sl
                entryIndex = i
            }
        }
        
        return signals
    }
    
    // MARK: - 实时信号（最后一根K线）
    /// 实时评分达到阈值时返回信号，否则 nil。价格用实时价（K线未走完时 close 滞后，图标会画偏）
    static func realtimeSignal(_ data: [Kline], livePrice: Double? = nil) -> (marker: SignalMarker?, score: Int) {
        guard data.count >= 60, let last = data.last else {
            return (nil, 0)
        }
        
        let cs = composite(data)
        let score = cs.score
        let candle = last
        // 实时价优先，无则回退K线close
        let close = livePrice ?? candle.close
        
        guard score >= config.longThreshold || score <= config.shortThreshold else {
            return (nil, score)
        }
        
        if score >= config.longThreshold {
            let sl = config.stopLossMode == 2 ? candle.low * (1 - config.stopLossBuffer) : candle.low
            return (SignalMarker(
                candleIndex: data.count - 1,
                type: .longOpen,
                price: close,
                stopLoss: sl,
                stopTarget: close * (1 + config.takeProfitPercent / 100),
                strength: min(score, 100),
                source: "实时信号",
                timestamp: candle.timestamp
            ), score)
        }
        
        let sl = config.stopLossMode == 2 ? candle.high * (1 + config.stopLossBuffer) : candle.high
        return (SignalMarker(
            candleIndex: data.count - 1,
            type: .shortOpen,
            price: close,
            stopLoss: sl,
            stopTarget: close * (1 - config.takeProfitPercent / 100),
            strength: min(abs(score), 100),
            source: "实时信号",
            timestamp: candle.timestamp
        ), score)
    }
}
