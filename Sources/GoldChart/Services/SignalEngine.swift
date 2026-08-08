import Foundation

// MARK: - 信号引擎（金银专用引擎 + 追风揽月信号/止损）
// 评分公式（超哥给的金银专用技能提炼）：
//   cta  = china-technical-analysis 期货官方综合评分（MACD30%+RSI20%+MA25%+布林10%+KDJ15%）
//   gold = aistockresearcher GoldAnalyzer 趋势分（MA5/20/60 排列 + RSI 调节）
//   融合 = (cta×1 + gold×3) / 4 → -100~+100
//   >20 多 / <−20 空 / 中间观望
// 追风揽月规则：
//   信号 → K线图上标「多」/「空」圆点；反向信号 → 平仓并开反向仓
//   止损：吊灯止损（Chandelier Exit，回测验证正期望）
//     多头 = 持仓最高价 − 3×ATR(14)，空头 = 持仓最低价 + 3×ATR(14)
//   止盈：无固定止盈，让利润奔跑；反向信号即平仓
class SignalEngine {
    
    // MARK: - 配置
    struct Config {
        var longThreshold: Int = 20        // 评分 > 20 做多
        var shortThreshold: Int = -20      // 评分 < -20 做空
        var chandelierATR: Double = 3.0    // 吊灯止损 ATR 倍数
        
        static let `default` = Config()
    }
    
    static var config = Config.default
    
    // MARK: - 金银融合评分 (cta×1 + gold×3) / 4
    static func composite(_ data: [Kline]) -> CompositeSignal {
        guard data.count >= 60 else {
            return CompositeSignal(score: 0, breakdown: [
                SignalBreakdown(name: "数据不足", score: 0, weight: 1.0)
            ])
        }
        
        let ctaScore = scoreCTA(data)
        let goldScore = scoreGold(data)
        
        let breakdowns = [
            SignalBreakdown(name: "CTA期货评分", score: ctaScore, weight: 1.0),
            SignalBreakdown(name: "黄金趋势分", score: goldScore, weight: 3.0)
        ]
        
        var totalScore: Double = 0
        for b in breakdowns {
            totalScore += Double(b.score) * b.weight
        }
        totalScore = max(-100, min(100, totalScore / 4.0))
        
        return CompositeSignal(score: Int(totalScore.rounded()), breakdown: breakdowns)
    }
    
    // MARK: - 引擎 1：CTA 期货官方综合评分（china-technical-analysis）
    // MACD 30% + RSI 20% + MA 25% + 布林 10% + KDJ 15% → -100~+100
    private static func scoreCTA(_ data: [Kline]) -> Int {
        guard data.count >= 30 else { return 0 }
        var s = 0.0
        let close = data[data.count - 1].close
        
        // MACD 30%：DIF>DEA 且 DIF>0 +30 / DIF<DEA 且 DIF<0 -30
        let macd = IndicatorEngine.macd(data)
        if let dif = macd.dif.compactMap({ $0 }).last,
           let dea = macd.dea.compactMap({ $0 }).last {
            if dif > dea && dif > 0 { s += 30 }
            else if dif < dea && dif < 0 { s -= 30 }
        }
        
        // RSI 20%：<30 +20（超卖买）/ >70 -20（超买卖）
        if let r = IndicatorEngine.rsi(data).compactMap({ $0 }).last {
            if r < 30 { s += 20 }
            else if r > 70 { s -= 20 }
        }
        
        // MA 25%：价>MA5>MA10>MA20 +25 / 反向 -25
        let ma5 = IndicatorEngine.ma(data, period: 5).compactMap { $0 }.last
        let ma10 = IndicatorEngine.ma(data, period: 10).compactMap { $0 }.last
        let ma20 = IndicatorEngine.ma(data, period: 20).compactMap { $0 }.last
        if let m5 = ma5, let m10 = ma10, let m20 = ma20 {
            if close > m5 && m5 > m10 && m10 > m20 { s += 25 }
            else if close < m5 && m5 < m10 && m10 < m20 { s -= 25 }
        }
        
        // 布林 10%：价≤下轨 +10 / 价≥上轨 -10
        let boll = IndicatorEngine.bollinger(data)
        if let up = boll.upper.compactMap({ $0 }).last,
           let lo = boll.lower.compactMap({ $0 }).last {
            if close <= lo { s += 10 }
            else if close >= up { s -= 10 }
        }
        
        // KDJ 15%：低位金叉(K上穿D且D<20) +15 / 高位死叉(K下穿D且D>80) -15
        let kdj = IndicatorEngine.kdj(data)
        let kArr = kdj.k.compactMap { $0 }
        let dArr = kdj.d.compactMap { $0 }
        if kArr.count >= 2, dArr.count >= 2 {
            let k = kArr[kArr.count - 1], d = dArr[dArr.count - 1]
            let pk = kArr[kArr.count - 2], pd = dArr[dArr.count - 2]
            if pk <= pd && k > d && d < 20 { s += 15 }
            else if pk >= pd && k < d && d > 80 { s -= 15 }
        }
        
        return max(-100, min(100, Int(s.rounded())))
    }
    
    // MARK: - 引擎 2：GoldAnalyzer 趋势分（aistockresearcher）
    // 价>MA5>MA20 +0.4（反向-0.4）；MA20>MA60 +0.3（反向-0.3）；RSI(14) 40-60 +0.1 / >70 -0.2 / <30 +0.2 → ×100
    private static func scoreGold(_ data: [Kline]) -> Int {
        guard data.count >= 60 else { return 0 }
        var s = 0.0
        let close = data[data.count - 1].close
        
        let ma5 = IndicatorEngine.ma(data, period: 5).compactMap { $0 }.last
        let ma20 = IndicatorEngine.ma(data, period: 20).compactMap { $0 }.last
        let ma60 = IndicatorEngine.ma(data, period: 60).compactMap { $0 }.last
        if let m5 = ma5, let m20 = ma20 {
            if close > m5 && m5 > m20 { s += 0.4 }
            else if close < m5 && m5 < m20 { s -= 0.4 }
        }
        if let m20 = ma20, let m60 = ma60 {
            if m20 > m60 { s += 0.3 }
            else { s -= 0.3 }
        }
        if let r = IndicatorEngine.rsi(data).compactMap({ $0 }).last {
            if r >= 40 && r <= 60 { s += 0.1 }
            else if r > 70 { s -= 0.2 }
            else if r < 30 { s += 0.2 }
        }
        
        return max(-100, min(100, Int((s * 100).rounded())))
    }
    
    // MARK: - 逐根K线历史信号（追风揽月风格 · 吊灯双向止损）
    /// 遍历每根K线，评分>20标「多」、<-20标「空」；反向信号触发平仓并开反向仓；
    /// 止损：吊灯止损（Chandelier Exit）多头=持仓最高价−3×ATR(14)，空头=持仓最低价+3×ATR(14)；无固定止盈
    static func perCandleSignals(_ data: [Kline]) -> [SignalMarker] {
        guard data.count >= 60 else { return [] }
        var signals: [SignalMarker] = []
        
        var position: PositionDirection = .none   // 当前持仓
        var entryStopLoss: Double = 0              // 当前吊灯止损价
        var extremePrice: Double = 0               // 持仓期最高价（多头）/ 最低价（空头）
        
        // 预计算 ATR（吊灯止损用）
        let atrValues = IndicatorEngine.atr(data, period: 14)
        
        for i in 59..<data.count {
            let prefix = Array(data[0...i])
            let cs = composite(prefix)
            let candle = data[i]
            let score = cs.score
            let close = candle.close
            let atr = atrValues[i] ?? 0
            
            // 吊灯止损更新 + 止损检查
            if position != .none, atr > 0 {
                if position == .long {
                    extremePrice = max(extremePrice, candle.high)
                    entryStopLoss = extremePrice - config.chandelierATR * atr
                    if close <= entryStopLoss {
                        signals.append(SignalMarker(
                            candleIndex: i,
                            type: .longClose,
                            price: close,
                            stopLoss: entryStopLoss,
                            stopTarget: close,
                            strength: 100,
                            source: "吊灯止损",
                            timestamp: candle.timestamp
                        ))
                        position = .none
                    }
                } else {
                    extremePrice = min(extremePrice, candle.low)
                    entryStopLoss = extremePrice + config.chandelierATR * atr
                    if close >= entryStopLoss {
                        signals.append(SignalMarker(
                            candleIndex: i,
                            type: .shortClose,
                            price: close,
                            stopLoss: entryStopLoss,
                            stopTarget: close,
                            strength: 100,
                            source: "吊灯止损",
                            timestamp: candle.timestamp
                        ))
                        position = .none
                    }
                }
            }
            
            // 开仓信号：只在状态转换时开仓（避免同一持仓周期内重复发信号 → 徽章爆炸）
            if position != .long && score >= config.longThreshold {
                // 反向持仓 → 先平仓（出现反向信号即平仓）
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
                let sl = candle.low - config.chandelierATR * (atr > 0 ? atr : 0)
                signals.append(SignalMarker(
                    candleIndex: i,
                    type: .longOpen,
                    price: close,
                    stopLoss: sl,
                    stopTarget: nil,
                    strength: min(score, 100),
                    source: "追风揽月",
                    timestamp: candle.timestamp
                ))
                position = .long
                entryStopLoss = sl
                extremePrice = candle.high
                
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
                let sl = candle.high + config.chandelierATR * (atr > 0 ? atr : 0)
                signals.append(SignalMarker(
                    candleIndex: i,
                    type: .shortOpen,
                    price: close,
                    stopLoss: sl,
                    stopTarget: nil,
                    strength: min(abs(score), 100),
                    source: "追风揽月",
                    timestamp: candle.timestamp
                ))
                position = .short
                entryStopLoss = sl
                extremePrice = candle.low
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
        let atr = IndicatorEngine.atr(data, period: 14).compactMap { $0 }.last ?? 0
        
        guard score >= config.longThreshold || score <= config.shortThreshold else {
            return (nil, score)
        }
        
        if score >= config.longThreshold {
            let sl = candle.low - config.chandelierATR * atr
            return (SignalMarker(
                candleIndex: data.count - 1,
                type: .longOpen,
                price: close,
                stopLoss: sl,
                stopTarget: nil,
                strength: min(score, 100),
                source: "实时信号",
                timestamp: candle.timestamp
            ), score)
        }
        
        let sl = candle.high + config.chandelierATR * atr
        return (SignalMarker(
            candleIndex: data.count - 1,
            type: .shortOpen,
            price: close,
            stopLoss: sl,
            stopTarget: nil,
            strength: min(abs(score), 100),
            source: "实时信号",
            timestamp: candle.timestamp
        ), score)
    }
}
