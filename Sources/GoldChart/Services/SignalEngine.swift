import Foundation

// MARK: - 11指标综合评分引擎
class SignalEngine {
    
    /// 11个指标加权合成评分
    static func composite(_ data: [Kline]) -> CompositeSignal {
        guard data.count >= 60 else {
            return CompositeSignal(score: 0, breakdown: [
                SignalBreakdown(name: "数据不足", score: 0, weight: 1.0)
            ])
        }
        
        var breakdowns: [SignalBreakdown] = []
        
        // 1. MACD金叉死叉 (12%)
        breakdowns.append(scoreMacdCross(data, weight: 0.12))
        
        // 2. MACD背离 (10%)
        breakdowns.append(scoreMacdDivergence(data, weight: 0.10))
        
        // 3. RSI超买超卖 (10%)
        breakdowns.append(scoreRSI(data, weight: 0.10))
        
        // 4. KDJ金叉死叉 (8%)
        breakdowns.append(scoreKDJ(data, weight: 0.08))
        
        // 5. 布林带位置 (10%)
        breakdowns.append(scoreBollinger(data, weight: 0.10))
        
        // 6. 均线排列 (10%)
        breakdowns.append(scoreMA(data, weight: 0.10))
        
        // 7. CCI (10%)
        breakdowns.append(scoreCCI(data, weight: 0.10))
        
        // 8. MFI资金流向 (8%)
        breakdowns.append(scoreMFI(data, weight: 0.08))
        
        // 9. ADX趋势强度 (7%)
        breakdowns.append(scoreADX(data, weight: 0.07))
        
        // 10. 威廉%R (7%)
        breakdowns.append(scoreWilliams(data, weight: 0.07))
        
        // 11. K线形态 (8%)
        breakdowns.append(scoreCandlestick(data, weight: 0.08))
        
        // 计算加权总分
        var totalScore: Double = 0
        for b in breakdowns {
            totalScore += Double(b.score) * b.weight
        }
        
        return CompositeSignal(score: Int(totalScore.rounded()), breakdown: breakdowns)
    }
    
    // MARK: - 1. MACD金叉死叉
    private static func scoreMacdCross(_ data: [Kline], weight: Double) -> SignalBreakdown {
        let macd = IndicatorEngine.macd(data)
        let dif = macd.dif.compactMap { $0 }
        let dea = macd.dea.compactMap { $0 }
        let hist = macd.histogram.compactMap { $0 }
        
        guard dif.count >= 3, dea.count >= 3, hist.count >= 3,
              let lastDIF = dif.last, let lastDEA = dea.last,
              let prevDIF = dif[safe: dif.count - 2],
              let prevDEA = dea[safe: dea.count - 2] else {
            return SignalBreakdown(name: "MACD", score: 0, weight: weight)
        }
        
        // 金叉
        if prevDIF <= prevDEA && lastDIF > lastDEA {
            return SignalBreakdown(name: "MACD金叉", score: 60, weight: weight)
        }
        // 死叉
        if prevDIF >= prevDEA && lastDIF < lastDEA {
            return SignalBreakdown(name: "MACD死叉", score: -60, weight: weight)
        }
        
        // 无交叉：看柱体趋势
        let histTrend = hist.suffix(5)
        let up = histTrend.filter { $0 > 0 }.count
        let dn = histTrend.filter { $0 < 0 }.count
        
        if lastDIF > lastDEA {
            let score = min(up * 12, 40)
            return SignalBreakdown(name: "MACD", score: score, weight: weight)
        }
        let score = min(dn * 12, 40)
        return SignalBreakdown(name: "MACD", score: -score, weight: weight)
    }
    
    // MARK: - 2. MACD背离
    private static func scoreMacdDivergence(_ data: [Kline], weight: Double) -> SignalBreakdown {
        guard data.count >= 50 else {
            return SignalBreakdown(name: "MACD背离", score: 0, weight: weight)
        }
        
        let macd = IndicatorEngine.macd(data)
        let hist = macd.histogram.compactMap { $0 }
        guard hist.count >= 10 else {
            return SignalBreakdown(name: "MACD背离", score: 0, weight: weight)
        }
        
        let recentHist = Array(hist.suffix(10))
        let recentPrices = Array(data.suffix(10))
        guard let close = data.last?.close else {
            return SignalBreakdown(name: "MACD背离", score: 0, weight: weight)
        }
        
        // 底背离：价格更低但MACD柱更高
        let priceLow = recentPrices.min(by: { $0.low < $1.low })?.low ?? close
        let histNow = recentHist.last ?? 0
        let histLow = recentHist.min() ?? 0
        
        if close <= priceLow * 1.001 && histNow > histLow + 5 {
            return SignalBreakdown(name: "MACD底背离", score: 70, weight: weight)
        }
        
        // 顶背离：价格更高但MACD柱更低
        let priceHigh = recentPrices.max(by: { $0.high < $1.high })?.high ?? close
        let histHigh = recentHist.max() ?? 0
        
        if close >= priceHigh * 0.999 && histNow < histHigh - 5 {
            return SignalBreakdown(name: "MACD顶背离", score: -70, weight: weight)
        }
        
        return SignalBreakdown(name: "MACD背离", score: 0, weight: weight)
    }
    
    // MARK: - 3. RSI
    private static func scoreRSI(_ data: [Kline], weight: Double) -> SignalBreakdown {
        guard data.count >= 20 else {
            return SignalBreakdown(name: "RSI", score: 0, weight: weight)
        }
        
        let rsiValues = IndicatorEngine.rsi(data)
        guard let lastRSI = rsiValues.compactMap({ $0 }).last else {
            return SignalBreakdown(name: "RSI", score: 0, weight: weight)
        }
        
        // RSI < 30 = 超卖 → 偏多
        if lastRSI <= 30 {
            let score = min(Int((30 - lastRSI) * 3), 80)
            return SignalBreakdown(name: "RSI超卖", score: score, weight: weight)
        }
        // RSI > 70 = 超买 → 偏空
        if lastRSI >= 70 {
            let score = min(Int((lastRSI - 70) * 3), 80)
            return SignalBreakdown(name: "RSI超买", score: -score, weight: weight)
        }
        // 正常范围：线性映射
        let score = Int((lastRSI - 50) * 1.5)
        return SignalBreakdown(name: "RSI", score: score, weight: weight)
    }
    
    // MARK: - 4. KDJ
    private static func scoreKDJ(_ data: [Kline], weight: Double) -> SignalBreakdown {
        guard data.count >= 20 else {
            return SignalBreakdown(name: "KDJ", score: 0, weight: weight)
        }
        
        let kdj = IndicatorEngine.kdj(data)
        guard let k = kdj.k.compactMap({ $0 }).last,
              let d = kdj.d.compactMap({ $0 }).last,
              let prevK = kdj.k.compactMap({ $0 })[safe: max(kdj.k.compactMap({ $0 }).count - 2, 0)],
              let prevD = kdj.d.compactMap({ $0 })[safe: max(kdj.d.compactMap({ $0 }).count - 2, 0)] else {
            return SignalBreakdown(name: "KDJ", score: 0, weight: weight)
        }
        
        // 金叉（K上穿D + 低位）
        if prevK <= prevD && k > d && k < 40 {
            let strength = min(Int((40 - k) * 2), 60)
            return SignalBreakdown(name: "KDJ金叉", score: strength, weight: weight)
        }
        // 死叉（K下穿D + 高位）
        if prevK >= prevD && k < d && k > 60 {
            let strength = min(Int((k - 60) * 2), 60)
            return SignalBreakdown(name: "KDJ死叉", score: -strength, weight: weight)
        }
        
        // 无交叉：看K值位置
        let score = Int((k - 50) * 1.2)
        return SignalBreakdown(name: "KDJ", score: score, weight: weight)
    }
    
    // MARK: - 5. 布林带
    private static func scoreBollinger(_ data: [Kline], weight: Double) -> SignalBreakdown {
        guard data.count >= 26 else {
            return SignalBreakdown(name: "布林带", score: 0, weight: weight)
        }
        
        let boll = IndicatorEngine.bollinger(data)
        guard let close = data.last?.close,
              let upper = boll.upper.compactMap({ $0 }).last,
              let lower = boll.lower.compactMap({ $0 }).last,
              let middle = boll.middle.compactMap({ $0 }).last,
              upper > lower else {
            return SignalBreakdown(name: "布林带", score: 0, weight: weight)
        }
        
        // 价格在通道中的位置，-100~+100
        let range = upper - lower
        let pos = range == 0 ? 0 : ((close - middle) / (range / 2)) * 100
        
        if close <= lower {
            return SignalBreakdown(name: "布林触下轨", score: 60, weight: weight)
        }
        if close >= upper {
            return SignalBreakdown(name: "布林触上轨", score: -60, weight: weight)
        }
        
        return SignalBreakdown(name: "布林", score: Int(pos.rounded()), weight: weight)
    }
    
    // MARK: - 6. 均线排列
    private static func scoreMA(_ data: [Kline], weight: Double) -> SignalBreakdown {
        guard data.count >= 30 else {
            return SignalBreakdown(name: "均线", score: 0, weight: weight)
        }
        
        let ma5 = IndicatorEngine.ma(data, period: 5).compactMap { $0 }
        let ma10 = IndicatorEngine.ma(data, period: 10).compactMap { $0 }
        let ma20 = IndicatorEngine.ma(data, period: 20).compactMap { $0 }
        let ma60 = IndicatorEngine.ma(data, period: 60).compactMap { $0 }
        
        guard let m5 = ma5.last, let m10 = ma10.last,
              let m20 = ma20.last, let m60 = ma60.last else {
            return SignalBreakdown(name: "均线", score: 0, weight: weight)
        }
        
        // 多头排列：MA5 > MA10 > MA20 > MA60
        if m5 > m10 && m10 > m20 && m20 > m60 {
            let spread = ((m5 - m60) / m60 * 100)
            let score = min(Int(spread * 3), 70)
            return SignalBreakdown(name: "多头排列", score: score, weight: weight)
        }
        // 空头排列：MA5 < MA10 < MA20 < MA60
        if m5 < m10 && m10 < m20 && m20 < m60 {
            let spread = ((m60 - m5) / m60 * 100)
            let score = min(Int(spread * 3), 70)
            return SignalBreakdown(name: "空头排列", score: -score, weight: weight)
        }
        
        // 局部排列：看价格相对MA20位置
        guard let close = data.last?.close else {
            return SignalBreakdown(name: "均线", score: 0, weight: weight)
        }
        let score = Int((close - m20) / m20 * 200)
        return SignalBreakdown(name: "均线", score: max(-40, min(40, score)), weight: weight)
    }
    
    // MARK: - 7. CCI
    private static func scoreCCI(_ data: [Kline], weight: Double) -> SignalBreakdown {
        guard data.count >= 20 else {
            return SignalBreakdown(name: "CCI", score: 0, weight: weight)
        }
        
        let cciValues = IndicatorEngine.cci(data)
        guard let lastCCI = cciValues.compactMap({ $0 }).last else {
            return SignalBreakdown(name: "CCI", score: 0, weight: weight)
        }
        
        // CCI > +100 = 超买 → 偏空；CCI < -100 = 超卖 → 偏多
        if lastCCI > 100 {
            let score = min(Int((lastCCI - 100) * 0.5), 60)
            return SignalBreakdown(name: "CCI超买", score: -score, weight: weight)
        }
        if lastCCI < -100 {
            let score = min(Int((-100 - lastCCI) * 0.5), 60)
            return SignalBreakdown(name: "CCI超卖", score: score, weight: weight)
        }
        
        // 线性映射 -100~+100 → -40~+40
        let score = Int((lastCCI / 100) * 40)
        return SignalBreakdown(name: "CCI", score: max(-40, min(40, score)), weight: weight)
    }
    
    // MARK: - 8. MFI
    private static func scoreMFI(_ data: [Kline], weight: Double) -> SignalBreakdown {
        guard data.count >= 20 else {
            return SignalBreakdown(name: "MFI", score: 0, weight: weight)
        }
        
        let mfiValues = IndicatorEngine.mfi(data)
        guard let lastMFI = mfiValues.compactMap({ $0 }).last else {
            return SignalBreakdown(name: "MFI", score: 0, weight: weight)
        }
        
        // MFI < 20 = 超卖；MFI > 80 = 超买
        if lastMFI <= 20 {
            let score = min(Int((20 - lastMFI) * 3), 60)
            return SignalBreakdown(name: "MFI超卖", score: score, weight: weight)
        }
        if lastMFI >= 80 {
            let score = min(Int((lastMFI - 80) * 3), 60)
            return SignalBreakdown(name: "MFI超买", score: -score, weight: weight)
        }
        
        let score = Int((lastMFI - 50) * 1.5)
        return SignalBreakdown(name: "MFI", score: max(-40, min(40, score)), weight: weight)
    }
    
    // MARK: - 9. ADX
    private static func scoreADX(_ data: [Kline], weight: Double) -> SignalBreakdown {
        guard data.count >= 30 else {
            return SignalBreakdown(name: "ADX", score: 0, weight: weight)
        }
        
        let (pdi, mdi, adxValues) = IndicatorEngine.directionalIndicators(data)
        guard let adx = adxValues.compactMap({ $0 }).last,
              let plusDI = pdi.compactMap({ $0 }).last,
              let minusDI = mdi.compactMap({ $0 }).last else {
            return SignalBreakdown(name: "ADX", score: 0, weight: weight)
        }
        
        // ADX < 20 = 震荡无趋势
        if adx < 20 {
            return SignalBreakdown(name: "ADX震荡", score: 0, weight: weight)
        }
        
        // ADX >= 20 = 趋势行情，方向由+DI和-DI决定
        let diff = plusDI - minusDI
        let strength = min(Int(abs(diff) * 1.5), 60)
        
        if diff > 0 {
            return SignalBreakdown(name: "ADX多头", score: strength, weight: weight)
        }
        return SignalBreakdown(name: "ADX空头", score: -strength, weight: weight)
    }
    
    // MARK: - 10. 威廉%R
    private static func scoreWilliams(_ data: [Kline], weight: Double) -> SignalBreakdown {
        guard data.count >= 20 else {
            return SignalBreakdown(name: "威廉%R", score: 0, weight: weight)
        }
        
        let wrValues = IndicatorEngine.williamsR(data)
        guard let lastWR = wrValues.compactMap({ $0 }).last else {
            return SignalBreakdown(name: "威廉%R", score: 0, weight: weight)
        }
        
        // WR 范围 -100~0, < -80 = 超卖(偏多), > -20 = 超买(偏空)
        if lastWR <= -80 {
            let score = min(Int((-80 - lastWR) * 2), 60)
            return SignalBreakdown(name: "威廉超卖", score: score, weight: weight)
        }
        if lastWR >= -20 {
            let score = min(Int((lastWR + 20) * 2), 60)
            return SignalBreakdown(name: "威廉超买", score: -score, weight: weight)
        }
        
        let score = Int((lastWR + 50) * 1.5)
        return SignalBreakdown(name: "威廉%R", score: max(-40, min(40, score)), weight: weight)
    }
    
    // MARK: - 11. K线形态
    private static func scoreCandlestick(_ data: [Kline], weight: Double) -> SignalBreakdown {
        guard data.count >= 10 else {
            return SignalBreakdown(name: "K线形态", score: 0, weight: weight)
        }
        
        guard let last = data.last, let prev = data[safe: data.count - 2],
              let prev2 = data[safe: data.count - 3] else {
            return SignalBreakdown(name: "K线形态", score: 0, weight: weight)
        }
        
        let body = abs(last.close - last.open)
        let upperShadow = last.high - max(last.open, last.close)
        let lowerShadow = min(last.open, last.close) - last.low
        let totalRange = last.high - last.low
        
        guard totalRange > 0 else {
            return SignalBreakdown(name: "K线形态", score: 0, weight: weight)
        }
        
        let bodyRatio = body / totalRange
        let upperRatio = upperShadow / totalRange
        let lowerRatio = lowerShadow / totalRange
        
        // 锤子线（低位反转 → 多头）
        // 下影线>2倍实体, 上影线很短
        if lowerRatio > 0.6 && upperRatio < 0.1 && bodyRatio < 0.3 {
            // 确认出现在下降趋势中
            let trend = prev.close < prev2.close
            if trend {
                return SignalBreakdown(name: "锤子线", score: 50, weight: weight)
            }
        }
        
        // 射击之星（高位反转 → 空头）
        // 上影线>2倍实体, 下影线很短
        if upperRatio > 0.6 && lowerRatio < 0.1 && bodyRatio < 0.3 {
            let trend = prev.close > prev2.close
            if trend {
                return SignalBreakdown(name: "射击之星", score: -50, weight: weight)
            }
        }
        
        // 看涨吞没
        if last.close > last.open && prev.close < prev.open &&
           last.close > prev.open && last.open < prev.close {
            return SignalBreakdown(name: "看涨吞没", score: 55, weight: weight)
        }
        
        // 看跌吞没
        if last.close < last.open && prev.close > prev.open &&
           last.close < prev.open && last.open > prev.close {
            return SignalBreakdown(name: "看跌吞没", score: -55, weight: weight)
        }
        
        // 连续走势判断：看最后3根K线的实体方向
        let lastBody = last.close - last.open
        let prevBody = prev.close - prev.open
        if lastBody > 0 && prevBody > 0 {
            let avg = (lastBody + prevBody) / 2
            let closePrice = last.close
            let strength = min(Int(avg / closePrice * 200), 30)
            return SignalBreakdown(name: "K线上涨", score: strength, weight: weight)
        }
        if lastBody < 0 && prevBody < 0 {
            let avg = (abs(lastBody) + abs(prevBody)) / 2
            let closePrice = last.close
            let strength = min(Int(avg / closePrice * 200), 30)
            return SignalBreakdown(name: "K线下跌", score: -strength, weight: weight)
        }
        
        return SignalBreakdown(name: "K线形态", score: 0, weight: weight)
    }
    
    // MARK: - 逐根K线历史评分信号
    /// 逐根K线计算综合评分，>=+75产生做多信号，<=-75产生做空信号
    static func perCandleSignals(_ data: [Kline]) -> [SignalMarker] {
        guard data.count >= 60 else { return [] }
        var signals: [SignalMarker] = []
        
        for i in 59..<data.count {
            let prefix = Array(data[0...i])
            let cs = composite(prefix)
            let candle = data[i]
            
            if cs.score >= 40 {
                let stopLoss = candle.low
                let range = candle.close - stopLoss
                let stopTarget = candle.close + range
                signals.append(SignalMarker(
                    candleIndex: i,
                    type: .longOpen,
                    price: candle.close,
                    stopLoss: stopLoss,
                    stopTarget: stopTarget,
                    strength: min(cs.score, 100),
                    source: "综合评分",
                    timestamp: candle.timestamp
                ))
            } else if cs.score <= -40 {
                let stopLoss = candle.high
                let range = stopLoss - candle.close
                let stopTarget = candle.close - range
                signals.append(SignalMarker(
                    candleIndex: i,
                    type: .shortOpen,
                    price: candle.close,
                    stopLoss: stopLoss,
                    stopTarget: stopTarget,
                    strength: min(abs(cs.score), 100),
                    source: "综合评分",
                    timestamp: candle.timestamp
                ))
            }
        }
        return signals
    }
}
