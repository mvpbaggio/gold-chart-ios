import Foundation

class SignalEngine {
    
    // MARK: - 综合信号评分
    static func evaluateSignals(klines: [Kline]) -> OverallAssessment {
        var signals: [TradeSignal] = []
        
        // 1. MACD背离
        signals.append(macdDivergence(klines))
        
        // 2. RSI超买超卖
        signals.append(rsiOversoldOverbought(klines))
        
        // 3. KDJ金叉死叉
        signals.append(kdjCross(klines))
        
        // 4. BOLL位置
        signals.append(bollingerPosition(klines))
        
        // 5. MA金叉死叉
        signals.append(maCross(klines))
        
        // 6. 多周期共振
        signals.append(multiPeriodResonance(klines))
        
        // 7. 成交量异常
        signals.append(volumeAnomaly(klines))
        
        // 8. 威廉指标
        signals.append(williamsSignal(klines))
        
        return OverallAssessment.evaluate(signals: signals)
    }
    
    // MARK: - MACD背离
    static func macdDivergence(_ data: [Kline]) -> TradeSignal {
        guard data.count >= 50 else {
            return TradeSignal(type: .neutral, strength: 50, description: "MACD", detail: "数据不足")
        }
        
        let macdResult = IndicatorEngine.macd(data)
        let histogram = macdResult.histogram.compactMap { $0 }
        guard histogram.count >= 10 else {
            return TradeSignal(type: .neutral, strength: 50, description: "MACD", detail: "等待更多数据")
        }
        
        // 底背离检测：价格新低但MACD没新低
        let recent8 = Array(histogram.suffix(8))
        let priceRecent8 = Array(data.suffix(8))
        
        var buySignal = false
        var sellSignal = false
        
        // 简化的背离检测
        if let histLow = recent8.min(),
           let priceLow = priceRecent8.min(by: { $0.low < $1.low }),
           histLow > -100 && priceLow.low == data.last?.low {
            // 价格新低但MACD柱没创新低 → 底背离
            let histIndex = histogram.suffix(15).firstIndex(of: histLow) ?? histogram.count - 1
            let lastHist = histogram.last ?? 0
            if lastHist > histLow && data.last?.close ?? 0 > (data[safe: histIndex]?.close ?? 0) {
                buySignal = true
            }
        }
        
        // 顶背离
        if let histHigh = recent8.max(),
           let priceHigh = priceRecent8.max(by: { $0.high < $1.high }),
           histHigh < 100 && priceHigh.high == data.last?.high {
            let histIndex = histogram.suffix(15).firstIndex(of: histHigh) ?? histogram.count - 1
            let lastHist = histogram.last ?? 0
            if lastHist < histHigh && data.last?.close ?? 0 < (data[safe: histIndex]?.close ?? 0) {
                sellSignal = true
            }
        }
        
        if buySignal {
            return TradeSignal(type: .buy, strength: 75, description: "MACD底背离", detail: "价格新低但MACD未创新低，反弹信号")
        }
        if sellSignal {
            return TradeSignal(type: .sell, strength: 75, description: "MACD顶背离", detail: "价格新高但MACD未创新高，回调信号")
        }
        
        return TradeSignal(type: .neutral, strength: 50, description: "MACD", detail: "无明显背离")
    }
    
    // MARK: - RSI超买超卖
    static func rsiOversoldOverbought(_ data: [Kline]) -> TradeSignal {
        guard data.count >= 20 else {
            return TradeSignal(type: .neutral, strength: 50, description: "RSI", detail: "数据不足")
        }
        
        let rsiValues = IndicatorEngine.rsi(data)
        guard let lastRSI = rsiValues.last ?? nil else {
            return TradeSignal(type: .neutral, strength: 50, description: "RSI", detail: "计算中")
        }
        
        if lastRSI >= 70 {
            let strength = min(Int((lastRSI - 70) * 3), 95)
            return TradeSignal(type: .sell, strength: strength, description: "RSI超买",
                              detail: String(format: "RSI(14)=%.1f ≥ 70", lastRSI))
        } else if lastRSI <= 30 {
            let strength = min(Int((30 - lastRSI) * 3), 95)
            return TradeSignal(type: .buy, strength: strength, description: "RSI超卖",
                              detail: String(format: "RSI(14)=%.1f ≤ 30", lastRSI))
        } else {
            return TradeSignal(type: .neutral, strength: 50, description: "RSI正常",
                              detail: String(format: "RSI(14)=%.1f", lastRSI))
        }
    }
    
    // MARK: - KDJ金叉死叉
    static func kdjCross(_ data: [Kline]) -> TradeSignal {
        guard data.count >= 20 else {
            return TradeSignal(type: .neutral, strength: 50, description: "KDJ", detail: "数据不足")
        }
        
        let kdjResult = IndicatorEngine.kdj(data)
        let kValues = kdjResult.k.compactMap { $0 }
        let dValues = kdjResult.d.compactMap { $0 }
        
        guard kValues.count >= 3, dValues.count >= 3 else {
            return TradeSignal(type: .neutral, strength: 50, description: "KDJ", detail: "计算中")
        }
        
        let prevK = kValues[safe: kValues.count - 2] ?? 50
        let prevD = dValues[safe: dValues.count - 2] ?? 50
        let currK = kValues.last ?? 50
        let currD = dValues.last ?? 50
        
        // 金叉：K上穿D
        if prevK <= prevD && currK > currD && currK < 40 {
            return TradeSignal(type: .buy, strength: 70, description: "KDJ金叉",
                              detail: String(format: "K=%.1f 上穿 D=%.1f", currK, currD))
        }
        // 死叉：K下穿D
        if prevK >= prevD && currK < currD && currK > 60 {
            return TradeSignal(type: .sell, strength: 70, description: "KDJ死叉",
                              detail: String(format: "K=%.1f 下穿 D=%.1f", currK, currD))
        }
        
        return TradeSignal(type: .neutral, strength: 50, description: "KDJ", detail: "无明显信号")
    }
    
    // MARK: - BOLL位置
    static func bollingerPosition(_ data: [Kline]) -> TradeSignal {
        guard data.count >= 26 else {
            return TradeSignal(type: .neutral, strength: 50, description: "布林带", detail: "数据不足")
        }
        
        let boll = IndicatorEngine.bollinger(data)
        guard let close = data.last?.close,
              let lower = boll.lower.last ?? nil,
              let upper = boll.upper.last ?? nil,
              let middle = boll.middle.last ?? nil else {
            return TradeSignal(type: .neutral, strength: 50, description: "布林带", detail: "计算中")
        }
        
        if close <= lower {
            return TradeSignal(type: .buy, strength: 80, description: "触及下轨",
                              detail: "价格触及布林下轨，超卖反弹")
        } else if close >= upper {
            return TradeSignal(type: .sell, strength: 80, description: "触及上轨",
                              detail: "价格触及布林上轨，超买回调")
        } else if close < middle {
            let pct = (middle - close) / (middle - lower)
            if pct > 0.7 {
                return TradeSignal(type: .buy, strength: 60, description: "偏向下轨",
                                  detail: "价格偏向下轨，偏多")
            }
        } else if close > middle {
            let pct = (close - middle) / (upper - middle)
            if pct > 0.7 {
                return TradeSignal(type: .sell, strength: 60, description: "偏向上轨",
                                  detail: "价格偏向上轨，偏空")
            }
        }
        
        return TradeSignal(type: .neutral, strength: 50, description: "布林带中轨附近", detail: nil)
    }
    
    // MARK: - MA金叉死叉
    static func maCross(_ data: [Kline]) -> TradeSignal {
        guard data.count >= 30 else {
            return TradeSignal(type: .neutral, strength: 50, description: "均线系统", detail: "数据不足")
        }
        
        let ma5 = IndicatorEngine.ma(data, period: 5).compactMap { $0 }
        let ma10 = IndicatorEngine.ma(data, period: 10).compactMap { $0 }
        let ma20 = IndicatorEngine.ma(data, period: 20).compactMap { $0 }
        
        guard ma5.count >= 3, ma10.count >= 3 else {
            return TradeSignal(type: .neutral, strength: 50, description: "均线系统", detail: "计算中")
        }
        
        let cm5 = ma5.last ?? 0
        let pm5 = ma5[safe: ma5.count - 2] ?? 0
        let cm10 = ma10.last ?? 0
        let pm10 = ma10[safe: ma10.count - 2] ?? 0
        let cm20 = ma20.last ?? 0
        
        // MA5上穿MA10
        if pm5 <= pm10 && cm5 > cm10 {
            var strength = 65
            if cm5 > cm20 { strength += 10 } // 同时在MA20之上
            return TradeSignal(type: .buy, strength: strength, description: "MA5金叉MA10", detail: nil)
        }
        // MA5下穿MA10
        if pm5 >= pm10 && cm5 < cm10 {
            var strength = 65
            if cm5 < cm20 { strength += 10 } // 同时在MA20之下
            return TradeSignal(type: .sell, strength: strength, description: "MA5死叉MA10", detail: nil)
        }
        
        // 多头排列 MA5 > MA10 > MA20
        if cm5 > cm10 && cm10 > cm20 {
            return TradeSignal(type: .buy, strength: 55, description: "多头排列", detail: "MA5>MA10>MA20")
        }
        // 空头排列
        if cm5 < cm10 && cm10 < cm20 {
            return TradeSignal(type: .sell, strength: 55, description: "空头排列", detail: "MA5<MA10<MA20")
        }
        
        return TradeSignal(type: .neutral, strength: 50, description: "均线", detail: "无明显信号")
    }
    
    // MARK: - 多周期共振（简化版）
    static func multiPeriodResonance(_ data: [Kline]) -> TradeSignal {
        // 同一数据上模拟多周期：用不同EMA对比
        guard data.count >= 30 else {
            return TradeSignal(type: .neutral, strength: 50, description: "多周期共振", detail: "数据不足")
        }
        
        // 短期、中期、长期EMA方向
        let ema5 = IndicatorEngine.ema(data, period: 5).compactMap { $0 }
        let ema20 = IndicatorEngine.ema(data, period: 20).compactMap { $0 }
        let ema60 = IndicatorEngine.ema(data, period: 60).compactMap { $0 }
        
        guard ema5.count >= 3, ema20.count >= 3 else {
            return TradeSignal(type: .neutral, strength: 50, description: "多周期共振", detail: "计算中")
        }
        
        let e5 = (ema5.last ?? 0) - (ema5[safe: ema5.count - 2] ?? 0)
        let e20 = (ema20.last ?? 0) - (ema20[safe: ema20.count - 2] ?? 0)
        let e60 = ema60.count >= 3 ? (ema60.last ?? 0) - (ema60[safe: ema60.count - 2] ?? 0) : 0
        
        let upCount = [e5, e20, e60].filter { $0 > 0 }.count
        let downCount = [e5, e20, e60].filter { $0 < 0 }.count
        
        if upCount >= 2 {
            return TradeSignal(type: .buy, strength: min(50 + upCount * 12, 85), description: "多周期看涨共振",
                              detail: "\(upCount)/3周期向上")
        }
        if downCount >= 2 {
            return TradeSignal(type: .sell, strength: min(50 + downCount * 12, 85), description: "多周期看跌共振",
                              detail: "\(downCount)/3周期向下")
        }
        
        return TradeSignal(type: .neutral, strength: 50, description: "多周期", detail: "方向不一致")
    }
    
    // MARK: - 成交量异常
    static func volumeAnomaly(_ data: [Kline]) -> TradeSignal {
        guard data.count >= 21 else {
            return TradeSignal(type: .neutral, strength: 50, description: "成交量", detail: "数据不足")
        }
        
        let volumes = data.map { $0.volume }
        let recent = volumes.suffix(20)
        let avgVolume = recent.dropLast().reduce(0, +) / Double(recent.count - 1)
        let lastVolume = volumes.last ?? 0
        
        guard avgVolume > 0 else {
            return TradeSignal(type: .neutral, strength: 50, description: "成交量", detail: "数据异常")
        }
        
        let ratio = lastVolume / avgVolume
        
        if ratio >= 2.0, let lastClose = data.last?.close, let prevClose = data.dropLast().last?.close {
            if lastClose >= prevClose {
                return TradeSignal(type: .buy, strength: 70, description: "放量上涨",
                                  detail: String(format: "量比%.1f倍", ratio))
            } else {
                return TradeSignal(type: .sell, strength: 70, description: "放量下跌",
                                  detail: String(format: "量比%.1f倍", ratio))
            }
        }
        
        if ratio <= 0.5 {
            return TradeSignal(type: .neutral, strength: 40, description: "缩量", detail: String(format: "量比%.1f倍", ratio))
        }
        
        return TradeSignal(type: .neutral, strength: 50, description: "成交量正常", detail: nil)
    }
    
    // MARK: - 威廉指标
    static func williamsSignal(_ data: [Kline]) -> TradeSignal {
        guard data.count >= 20 else {
            return TradeSignal(type: .neutral, strength: 50, description: "威廉指标", detail: "数据不足")
        }
        
        let wr = IndicatorEngine.williamsR(data)
        guard let lastWR = wr.last ?? nil else {
            return TradeSignal(type: .neutral, strength: 50, description: "威廉指标", detail: "计算中")
        }
        
        if lastWR <= -80 {
            return TradeSignal(type: .buy, strength: 75, description: "威廉超卖",
                              detail: String(format: "W%%R=%.1f ≤ -80", lastWR))
        } else if lastWR >= -20 {
            return TradeSignal(type: .sell, strength: 75, description: "威廉超买",
                              detail: String(format: "W%%R=%.1f ≥ -20", lastWR))
        }
        
        return TradeSignal(type: .neutral, strength: 50, description: "威廉正常", detail: nil)
    }
}
