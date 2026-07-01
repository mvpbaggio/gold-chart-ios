import Foundation

// MARK: - 技术指标引擎
class IndicatorEngine {
    
    // MARK: - 移动平均线 (MA)
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
    static func ema(_ data: [Kline], period: Int) -> [Double?] {
        guard data.count >= 1 else { return [] }
        var result: [Double?] = Array(repeating: nil, count: data.count)
        let multiplier = 2.0 / Double(period + 1)
        
        // 第一个EMA用SMA
        var emaValue: Double = data[0].close
        result[0] = emaValue
        
        for i in 1..<data.count {
            emaValue = (data[i].close - emaValue) * multiplier + emaValue
            result[i] = emaValue
        }
        return result
    }
    
    // MARK: - MACD
    static func macd(_ data: [Kline], fast: Int = 12, slow: Int = 26, signal: Int = 9) -> MACDResult {
        let fastEMA = ema(data, period: fast)
        let slowEMA = ema(data, period: slow)
        
        var dif: [Double?] = Array(repeating: nil, count: data.count)
        for i in 0..<data.count {
            if let f = fastEMA[i], let s = slowEMA[i] {
                dif[i] = f - s
            }
        }
        
        // DEA = EMA of DIF
        var dea: [Double?] = Array(repeating: nil, count: data.count)
        var deaValue: Double?
        for i in 0..<data.count {
            guard let d = dif[i] else { continue }
            if deaValue == nil {
                deaValue = d
            } else {
                deaValue = (d - deaValue!) * (2.0 / Double(signal + 1)) + deaValue!
            }
            dea[i] = deaValue
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
    
    // MARK: - RSI
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
    
    // MARK: - KDJ
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
    
    // MARK: - BOLL
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
    
    // MARK: - W%R (威廉指标)
    static func williamsR(_ data: [Kline], period: Int = 14) -> [Double?] {
        guard data.count >= period else { return Array(repeating: nil, count: data.count) }
        var result: [Double?] = Array(repeating: nil, count: data.count)
        
        for i in (period - 1)..<data.count {
            let start = i - period + 1
            let highest = data[start...i].max(by: { $0.high < $1.high })?.high ?? data[i].high
            let lowest = data[start...i].min(by: { $0.low < $1.low })?.low ?? data[i].low
            result[i] = (highest - lowest) == 0 ? -50 : (highest - data[i].close) / (highest - lowest) * -100
        }
        return result
    }
    
    // MARK: - ATR (平均真实波幅)
    static func atr(_ data: [Kline], period: Int = 14) -> [Double?] {
        guard data.count > 1 else { return Array(repeating: nil, count: data.count) }
        var result: [Double?] = Array(repeating: nil, count: data.count)
        
        var trValues: [Double] = []
        for i in 1..<data.count {
            let highLow = data[i].high - data[i].low
            let highClose = abs(data[i].high - data[i-1].close)
            let lowClose = abs(data[i].low - data[i-1].close)
            trValues.append(max(highLow, highClose, lowClose))
        }
        
        guard trValues.count >= period else { return result }
        
        var atrValue = trValues[0..<period].reduce(0, +) / Double(period)
        result[period] = atrValue
        
        for i in (period + 1)..<data.count {
            atrValue = (atrValue * Double(period - 1) + trValues[i-1]) / Double(period)
            result[i] = atrValue
        }
        
        return result
    }
    
    // MARK: - CCI (商品通道指数)
    static func cci(_ data: [Kline], period: Int = 20) -> [Double?] {
        guard data.count >= period else { return Array(repeating: nil, count: data.count) }
        var result: [Double?] = Array(repeating: nil, count: data.count)
        
        for i in (period - 1)..<data.count {
            let start = i - period + 1
            let typicalPrices = data[start...i].map { ($0.high + $0.low + $0.close) / 3.0 }
            let meanTP = typicalPrices.reduce(0, +) / Double(period)
            let meanDev = typicalPrices.reduce(0) { $0 + abs($1 - meanTP) } / Double(period)
            let tp = (data[i].high + data[i].low + data[i].close) / 3.0
            result[i] = meanDev == 0 ? 0 : (tp - meanTP) / (0.015 * meanDev)
        }
        return result
    }
    
    // MARK: - MFI (资金流向指数)
    static func mfi(_ data: [Kline], period: Int = 14) -> [Double?] {
        guard data.count > period else { return Array(repeating: nil, count: data.count) }
        var result: [Double?] = Array(repeating: nil, count: data.count)
        var rawFlows: [Double] = []
        var positiveFlowFlag: [Bool] = []
        
        for i in 0..<data.count {
            let tp = (data[i].high + data[i].low + data[i].close) / 3.0
            let rawFlow = tp * data[i].volume
            rawFlows.append(rawFlow)
            
            if i > 0 {
                let prevTP = (data[i-1].high + data[i-1].low + data[i-1].close) / 3.0
                positiveFlowFlag.append(tp >= prevTP)
            }
        }
        
        guard rawFlows.count > period, positiveFlowFlag.count >= period else { return result }
        
        for i in period..<data.count {
            var posFlow: Double = 0
            var negFlow: Double = 0
            for j in (i - period)..<i {
                if positiveFlowFlag[j] {
                    posFlow += rawFlows[j]
                } else {
                    negFlow += rawFlows[j]
                }
            }
            let mfr = negFlow == 0 ? 100 : posFlow / negFlow
            result[i] = 100 - (100 / (1 + mfr))
        }
        return result
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
    
    // MARK: - 一目均衡表 (云图)
    static func ichimoku(_ data: [Kline]) -> IchimokuResult {
        let n = data.count
        
        var tenkan: [Double?] = Array(repeating: nil, count: n)
        var kijun: [Double?] = Array(repeating: nil, count: n)
        var senkouA: [Double?] = Array(repeating: nil, count: n)
        var senkouB: [Double?] = Array(repeating: nil, count: n)
        var chikou: [Double?] = Array(repeating: nil, count: n)
        
        for i in 8..<n {
            let h1 = data[i-8...i].max(by: { $0.high < $1.high })?.high ?? data[i].high
            let l1 = data[i-8...i].min(by: { $0.low < $1.low })?.low ?? data[i].low
            tenkan[i] = (h1 + l1) / 2
        }
        
        for i in 25..<n {
            let h2 = data[i-25...i].max(by: { $0.high < $1.high })?.high ?? data[i].high
            let l2 = data[i-25...i].min(by: { $0.low < $1.low })?.low ?? data[i].low
            kijun[i] = (h2 + l2) / 2
        }
        
        for i in 25..<n {
            if let t = tenkan[i], let k = kijun[i] {
                senkouA[i] = (t + k) / 2
            }
        }
        
        for i in 51..<n {
            let h3 = data[i-51...i].max(by: { $0.high < $1.high })?.high ?? data[i].high
            let l3 = data[i-51...i].min(by: { $0.low < $1.low })?.low ?? data[i].low
            senkouB[i] = (h3 + l3) / 2
        }
        
        for i in 0..<(n - 25) {
            chikou[i + 25] = data[i].close
        }
        
        return IchimokuResult(tenkan: tenkan, kijun: kijun, senkouA: senkouA, senkouB: senkouB, chikou: chikou)
    }
}
