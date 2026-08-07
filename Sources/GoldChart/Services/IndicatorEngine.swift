import Foundation

// MARK: - 技术指标引擎（全部按技能标准算法：china-technical-analysis + aistockresearcher）
// 指标集：MA(5/10/20/60/120/250) / EMA(12/26) / MACD(12,26,9) / RSI(14) / KDJ(9,3,3)
//        / BOLL(20,2) / ADX / OBV / Hurst指数
// 已删除 App 独有指标：W%R / ATR / CCI / MFI / SuperTrend / Ichimoku
class IndicatorEngine {
    
    // MARK: - 移动平均线 (MA / SMA)
    static func ma(_ data: [Kline], period: Int) -> [Double?] {
        guard data.count >= period else {
            return Array(repeating: nil as Double?, count: data.count)
        }
        var result: [Double?] = Array(repeating: nil, count: data.count)
        var sum: Double = 0
        for i in 0..<data.count {
            sum += data[i].close
            if i >= period - 1 {
                if i >= period {
                    sum -= data[i - period].close
                }
                result[i] = sum / Double(period)
            }
        }
        return result
    }
    
    // MARK: - 指数移动平均线 (EMA)
    // 标准算法：种子 = 前 period 根收盘价的 SMA（技能同款）
    static func ema(_ data: [Kline], period: Int) -> [Double?] {
        guard data.count >= period, period > 0 else {
            return Array(repeating: nil as Double?, count: data.count)
        }
        var result: [Double?] = Array(repeating: nil, count: data.count)
        let multiplier = 2.0 / Double(period + 1)
        
        var sum: Double = 0
        for i in 0..<period {
            sum += data[i].close
        }
        var emaValue: Double = sum / Double(period)
        result[period - 1] = emaValue
        
        for i in period..<data.count {
            emaValue = (data[i].close - emaValue) * multiplier + emaValue
            result[i] = emaValue
        }
        return result
    }
    
    // MARK: - MACD (12,26,9)
    // DIF = EMA12 - EMA26；DEA = EMA(DIF,9)；柱 = 2×(DIF-DEA)
    static func macd(_ data: [Kline], fast: Int = 12, slow: Int = 26, signal: Int = 9) -> MACDResult {
        let fastEMA = ema(data, period: fast)
        let slowEMA = ema(data, period: slow)
        
        var dif: [Double?] = Array(repeating: nil, count: data.count)
        for i in 0..<data.count {
            if let f = fastEMA[i], let s = slowEMA[i] {
                dif[i] = f - s
            }
        }
        
        // DEA = EMA of DIF（种子 = 前 signal 根 DIF 的 SMA）
        var dea: [Double?] = Array(repeating: nil, count: data.count)
        if data.count >= signal {
            var difSum: Double = 0
            var difCount = 0
            for i in 0..<data.count {
                guard let d = dif[i] else { continue }
                difSum += d
                difCount += 1
                if difCount == signal {
                    var deaValue = difSum / Double(signal)
                    dea[i] = deaValue
                    for j in (i + 1)..<data.count {
                        guard let dj = dif[j] else { continue }
                        deaValue = (dj - deaValue) * (2.0 / Double(signal + 1)) + deaValue
                        dea[j] = deaValue
                    }
                    break
                }
            }
        }
        
        // Histogram = 2 * (DIF - DEA)
        var histogram: [Double?] = Array(repeating: nil, count: data.count)
        for i in 0..<data.count {
            if let d = dif[i], let e = dea[i] {
                histogram[i] = 2 * (d - e)
            }
        }
        
        return MACDResult(dif: dif, dea: dea, histogram: histogram)
    }
    
    // MARK: - RSI (14)
    static func rsi(_ data: [Kline], period: Int = 14) -> [Double?] {
        guard data.count > period else {
            return Array(repeating: nil, count: data.count)
        }
        var result: [Double?] = Array(repeating: nil, count: data.count)
        var gains: [Double] = []
        var losses: [Double] = []
        
        for i in 1..<data.count {
            let change = data[i].close - data[i-1].close
            gains.append(max(change, 0))
            losses.append(max(-change, 0))
        }
        
        var avgGain = gains[0..<period].reduce(0, +) / Double(period)
        var avgLoss = losses[0..<period].reduce(0, +) / Double(period)
        
        result[period] = avgLoss == 0 ? 100 : 100 - (100 / (1 + avgGain / avgLoss))
        
        for i in (period + 1)..<data.count {
            let idx = i - 1
            avgGain = (avgGain * Double(period - 1) + gains[idx]) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + losses[idx]) / Double(period)
            result[i] = avgLoss == 0 ? 100 : 100 - (100 / (1 + avgGain / avgLoss))
        }
        
        return result
    }
    
    // MARK: - KDJ (9,3,3)
    static func kdj(_ data: [Kline], period: Int = 9) -> KDJResult {
        guard data.count >= period else {
            return KDJResult(k: [], d: [], j: [])
        }
        
        var kValues: [Double?] = Array(repeating: nil, count: data.count)
        var dValues: [Double?] = Array(repeating: nil, count: data.count)
        var jValues: [Double?] = Array(repeating: nil, count: data.count)
        
        var k: Double = 50
        var d: Double = 50
        
        for i in 0..<data.count {
            guard i >= period - 1 else { continue }
            
            let start = i - period + 1
            let highest = data[start...i].max(by: { $0.high < $1.high })?.high ?? data[i].high
            let lowest = data[start...i].min(by: { $0.low < $1.low })?.low ?? data[i].low
            
            let rsv = (highest - lowest) == 0 ? 50 : (data[i].close - lowest) / (highest - lowest) * 100
            
            k = 2.0 / 3.0 * k + 1.0 / 3.0 * rsv
            d = 2.0 / 3.0 * d + 1.0 / 3.0 * k
            let j = 3 * k - 2 * d
            
            kValues[i] = k
            dValues[i] = d
            jValues[i] = j
        }
        
        return KDJResult(k: kValues, d: dValues, j: jValues)
    }
    
    // MARK: - BOLL (20,2)
    static func bollinger(_ data: [Kline], period: Int = 20, multiplier: Double = 2.0) -> BollingerResult {
        let middle = ma(data, period: period)
        
        var upper: [Double?] = Array(repeating: nil, count: data.count)
        var lower: [Double?] = Array(repeating: nil, count: data.count)
        
        for i in 0..<data.count {
            guard let m = middle[i] else { continue }
            
            let start = max(0, i - period + 1)
            let count = i - start + 1
            let mean = m
            
            let variance = data[start...i].reduce(0) { $0 + ($1.close - mean) * ($1.close - mean) } / Double(count)
            let stdDev = sqrt(variance)
            
            upper[i] = m + multiplier * stdDev
            lower[i] = m - multiplier * stdDev
        }
        
        return BollingerResult(upper: upper, middle: middle, lower: lower)
    }
    
    // MARK: - 布林带位置 (bb_position 0-100)
    // 当前价在布林带中的位置：0=下轨，100=上轨
    static func bollingerPosition(_ data: [Kline], period: Int = 20) -> Double? {
        guard data.count >= period else { return nil }
        let boll = bollinger(data, period: period)
        guard let close = data.last?.close,
              let upper = boll.upper.compactMap({ $0 }).last,
              let lower = boll.lower.compactMap({ $0 }).last,
              upper > lower else { return nil }
        return (close - lower) / (upper - lower) * 100
    }
    
    // MARK: - 均线状态（多头排列/空头排列/混乱）
    // 多头排列: MA5 > MA10 > MA20 > MA60；空头排列: MA5 < MA10 < MA20 < MA60
    static func maArrangement(_ data: [Kline]) -> String {
        guard data.count >= 60 else { return "混乱" }
        let ma5 = ma(data, period: 5).compactMap { $0 }.last
        let ma10 = ma(data, period: 10).compactMap { $0 }.last
        let ma20 = ma(data, period: 20).compactMap { $0 }.last
        let ma60 = ma(data, period: 60).compactMap { $0 }.last
        
        guard let m5 = ma5, let m10 = ma10, let m20 = ma20, let m60 = ma60 else {
            return "混乱"
        }
        
        if m5 > m10 && m10 > m20 && m20 > m60 {
            return "多头排列"
        }
        if m5 < m10 && m10 < m20 && m20 < m60 {
            return "空头排列"
        }
        return "混乱"
    }
    
    // MARK: - DI (方向指标) — 供ADX使用
    static func directionalIndicators(_ data: [Kline], period: Int = 14) -> (plusDI: [Double?], minusDI: [Double?], adx: [Double?]) {
        guard data.count > period + 1 else {
            return (Array(repeating: nil, count: data.count), Array(repeating: nil, count: data.count), Array(repeating: nil, count: data.count))
        }
        
        var plusDM: [Double] = []
        var minusDM: [Double] = []
        var tr: [Double] = []
        
        for i in 1..<data.count {
            let upMove = data[i].high - data[i-1].high
            let downMove = data[i-1].low - data[i].low
            
            let pDM = upMove > downMove && upMove > 0 ? upMove : 0
            let mDM = downMove > upMove && downMove > 0 ? downMove : 0
            plusDM.append(pDM)
            minusDM.append(mDM)
            
            let hl = data[i].high - data[i].low
            let hc = abs(data[i].high - data[i-1].close)
            let lc = abs(data[i].low - data[i-1].close)
            tr.append(max(hl, hc, lc))
        }
        
        guard tr.count >= period else {
            return (Array(repeating: nil, count: data.count), Array(repeating: nil, count: data.count), Array(repeating: nil, count: data.count))
        }
        
        var resultPDI: [Double?] = Array(repeating: nil, count: data.count)
        var resultMDI: [Double?] = Array(repeating: nil, count: data.count)
        var resultADX: [Double?] = Array(repeating: nil, count: data.count)
        
        var sumPDM = plusDM[0..<period].reduce(0, +)
        var sumMDM = minusDM[0..<period].reduce(0, +)
        var sumTR = tr[0..<period].reduce(0, +)
        
        for i in (period)..<tr.count {
            let idx = i + 1
            sumPDM = sumPDM - sumPDM / Double(period) + plusDM[i]
            sumMDM = sumMDM - sumMDM / Double(period) + minusDM[i]
            sumTR = sumTR - sumTR / Double(period) + tr[i]
            
            if sumTR == 0 { continue }
            let pdi = sumPDM / sumTR * 100
            let mdi = sumMDM / sumTR * 100
            resultPDI[idx] = pdi
            resultMDI[idx] = mdi
        }
        
        // ADX
        var dxSum: Double = 0
        var dxCount = 0
        for i in 0..<resultPDI.count {
            guard let pdi = resultPDI[i], let mdi = resultMDI[i] else { continue }
            let diff = abs(pdi - mdi)
            let sum = pdi + mdi
            if sum == 0 { continue }
            let dx = diff / sum * 100
            
            if dxCount < period {
                dxSum += dx
                dxCount += 1
                if dxCount == period {
                    resultADX[i] = dxSum / Double(period)
                }
            } else {
                let prevADX = resultADX[i-1] ?? dx
                resultADX[i] = (prevADX * Double(period - 1) + dx) / Double(period)
            }
        }
        
        return (resultPDI, resultMDI, resultADX)
    }
    
    // MARK: - OBV (能量潮)
    static func obv(_ data: [Kline]) -> [Double?] {
        guard data.count >= 1 else { return [] }
        var result: [Double?] = Array(repeating: nil, count: data.count)
        result[0] = data[0].volume
        
        for i in 1..<data.count {
            if data[i].close > data[i-1].close {
                result[i] = (result[i-1] ?? 0) + data[i].volume
            } else if data[i].close < data[i-1].close {
                result[i] = (result[i-1] ?? 0) - data[i].volume
            } else {
                result[i] = result[i-1]
            }
        }
        return result
    }
    
    // MARK: - Hurst 指数（R/S 分析，技能 aistockresearcher 同款）
    // H < 0.5: 均值回归；H ≈ 0.5: 随机游走；H > 0.5: 趋势延续
    static func hurst(_ data: [Kline], lookback: Int = 100) -> Double {
        guard data.count >= 2 else { return 0.5 }
        
        var returns: [Double] = []
        for i in 1..<data.count {
            let prev = data[i-1].close
            guard prev != 0 else { continue }
            returns.append((data[i].close - prev) / prev)
        }
        
        if returns.count < lookback {
            // 直接用 min 限制窗口
        }
        let n = min(lookback, returns.count)
        guard n >= 10 else { return 0.5 }
        
        let dataArr = Array(returns.suffix(n))
        
        func rangeOverStd(_ window: Int) -> Double {
            guard window <= dataArr.count, window >= 2 else { return 1 }
            var ranges: [Double] = []
            var i = 0
            while i < dataArr.count {
                let end = min(i + window, dataArr.count)
                let sub = Array(dataArr[i..<end])
                i = end
                if sub.count < 2 { continue }
                let mean = sub.reduce(0, +) / Double(sub.count)
                var cumsum: [Double] = [0]
                for v in sub {
                    cumsum.append(cumsum[cumsum.count - 1] + v - mean)
                }
                let r = (cumsum.max() ?? 0) - (cumsum.min() ?? 0)
                let variance = sub.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(sub.count)
                let s = sqrt(variance)
                ranges.append(s > 0 ? r / s : 1)
            }
            return ranges.isEmpty ? 1 : ranges.reduce(0, +) / Double(ranges.count)
        }
        
        var logN: [Double] = []
        var logRS: [Double] = []
        
        for size in [5, 10, 20, 50] where size <= dataArr.count {
            let rs = rangeOverStd(size)
            if rs > 0 {
                logN.append(log(Double(size)))
                logRS.append(log(rs))
            }
        }
        
        guard logN.count >= 2 else { return 0.5 }
        
        let nMean = logN.reduce(0, +) / Double(logN.count)
        let rsMean = logRS.reduce(0, +) / Double(logRS.count)
        
        var numerator = 0.0
        var denominator = 0.0
        for i in 0..<logN.count {
            numerator += (logN[i] - nMean) * (logRS[i] - rsMean)
            denominator += (logN[i] - nMean) * (logN[i] - nMean)
        }
        
        guard denominator > 0 else { return 0.5 }
        let h = numerator / denominator
        return max(0, min(1, h))
    }
}
