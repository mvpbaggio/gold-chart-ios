import Foundation

// MARK: - A股信号引擎（timing + 23指标，1:3 权重，只做多）
// 评分公式（A股回测定稿 B 方案，超哥确认）：
//   timing = 择时引擎（MA5/10/20 排列 + MA20斜率 + MACD柱 + 顶底背离）
//   23指标 = stock-analysis-23 提炼四维（趋势共振 + MACD增强 + RSI/KDJ共振 + 布林带）
//   融合 = (timing×1 + 23指标×3) / 4 → -100~+100，阈值 ±30
// 追风揽月规则（A股散户不能做空 → 只做多）：
//   评分 ≥ +30 → 开多；吊灯止损：持仓最高价 − 3×ATR(14)；无固定止盈
//   评分 ≤ −30 → 平多（离场观望），不开空
class StockSignalEngine {

    // MARK: - 配置
    struct Config {
        var longThreshold: Int = 30      // 评分 ≥ 30 做多
        var exitThreshold: Int = -30     // 评分 ≤ -30 平多离场
        var chandelierATR: Double = 3.0  // 吊灯止损 ATR 倍数

        static let `default` = Config()
    }

    static var config = Config.default

    // MARK: - 融合评分 (timing×1 + 23指标×3) / 4
    static func composite(_ data: [Kline]) -> CompositeSignal {
        guard data.count >= 60 else {
            return CompositeSignal(score: 0, breakdown: [
                SignalBreakdown(name: "数据不足", score: 0, weight: 1.0)
            ])
        }

        let timingScore = scoreTiming(data)
        let s23Score = scoreS23(data)

        let breakdowns = [
            SignalBreakdown(name: "择时timing", score: timingScore, weight: 1.0),
            SignalBreakdown(name: "23指标", score: s23Score, weight: 3.0)
        ]

        var totalScore: Double = 0
        for b in breakdowns {
            totalScore += Double(b.score) * b.weight
        }
        totalScore = max(-100, min(100, totalScore / 4.0))

        return CompositeSignal(score: Int(totalScore.rounded()), breakdown: breakdowns)
    }

    // MARK: - 引擎 1：择时 timing（s_timing 照抄）
    // ① MA5/10/20 排列 + MA20 斜率（5日）：多头排列+60/+30，空头排列-60/-30，否则 ±20
    // ② MACD 柱：>0 且升 +24 / >0 降 +8 / <0 升 -8 / <0 降 -24
    // ③ 顶底背离（30日窗口）：底背离 +16 / 顶背离 -16
    private static func scoreTiming(_ data: [Kline]) -> Int {
        guard data.count >= 60 else { return 0 }
        let n = data.count
        let i = n - 1

        var s = 0.0

        // ① 均线排列（数组保留 nil 占位，与回测下标对齐）
        let m5 = IndicatorEngine.ma(data, period: 5)
        let m10 = IndicatorEngine.ma(data, period: 10)
        let m20 = IndicatorEngine.ma(data, period: 20)
        guard let v5 = val(m5, i), let v10 = val(m10, i), let v20 = val(m20, i) else { return 0 }
        // MA20 斜率 = ma20[i] - ma20[i-5]
        let slope20 = (i >= 5) ? ((val(m20, i) ?? 0) - (val(m20, i - 5) ?? 0)) : 0
        let bull = v5 > v10 && v10 > v20
        let bear = v5 < v10 && v10 < v20
        if bull {
            s += slope20 > 0 ? 60 : 30
        } else if bear {
            s += slope20 < 0 ? -60 : -30
        } else if v5 > v20 {
            s += 20
        } else if v5 < v20 {
            s -= 20
        }

        // ② MACD 柱
        let hist = IndicatorEngine.macd(data).histogram
        if let h = val(hist, i) {
            let ph = (i >= 1) ? (val(hist, i - 1) ?? h) : h
            if h > 0 {
                s += h > ph ? 24 : 8
            } else {
                s += h > ph ? -8 : -24
            }
        }

        // ③ 顶底背离（30日窗口，照抄回测 divergence）
        let closes = data.map { $0.close }
        let lookback = 30
        if i >= lookback {
            let seg = Array(closes[(i - lookback)...i])
            let cur = closes[i]
            // 底背离
            if let segMin = seg.min(), cur <= segMin * 1.001 {
                for j in max(5, i - lookback)..<(i - 3) {
                    if let hj = val(hist, j), hj < 0, let hi = val(hist, i), hi > hj {
                        if closes[i] < closes[j] {
                            s += 16
                            break
                        }
                    }
                }
            }
            // 顶背离
            if let segMax = seg.max(), cur >= segMax * 0.999 {
                for j in max(5, i - lookback)..<(i - 3) {
                    if let hj = val(hist, j), hj > 0, let hi = val(hist, i), hi < hj {
                        if closes[i] > closes[j] {
                            s -= 16
                            break
                        }
                    }
                }
            }
        }

        return max(-100, min(100, Int(s.rounded())))
    }

    // MARK: - 引擎 2：23指标四维（s_23 照抄，等权平均）
    // M001 趋势共振：MA5>10>20>60 +100 / 反向 -100 / MA5>10>20 +60 / 反向 -60
    // M010 MACD增强：背离 ±50 + 金叉死叉 ±50 + 柱 ±20
    // M011/12 RSI+KDJ共振：RSI≤30且K≤20 +100 / RSI≥70且K≥80 -100 / 单边 ±50 / KDJ上行 ±30
    // M013 布林带：价≤下轨且RSI<40 +100 / 价≤下轨×1.01 +60 / 价≥上轨且RSI>60 -100 / 价≥上轨×0.99 -60
    private static func scoreS23(_ data: [Kline]) -> Int {
        guard data.count >= 60 else { return 0 }
        let n = data.count
        let i = n - 1
        let close = data[i].close

        var scores: [Double] = []

        // M001 趋势共振
        let m5 = IndicatorEngine.ma(data, period: 5)
        let m10 = IndicatorEngine.ma(data, period: 10)
        let m20 = IndicatorEngine.ma(data, period: 20)
        let m60 = IndicatorEngine.ma(data, period: 60)
        if let a = val(m5, i), let b = val(m10, i), let c = val(m20, i), let d = val(m60, i) {
            if a > b && b > c && c > d {
                scores.append(100)
            } else if a < b && b < c && c < d {
                scores.append(-100)
            } else if a > b && b > c {
                scores.append(60)
            } else if a < b && b < c {
                scores.append(-60)
            } else {
                scores.append(0)
            }
        }

        // M010 MACD（含背离）
        let hist = IndicatorEngine.macd(data).histogram
        if let h = val(hist, i) {
            let ph = (i >= 1) ? (val(hist, i - 1) ?? h) : h
            var sc = 0.0
            // 背离（与 timing 同一逻辑）
            let closes = data.map { $0.close }
            let lookback = 30
            if i >= lookback {
                let seg = Array(closes[(i - lookback)...i])
                let cur = closes[i]
                if let segMin = seg.min(), cur <= segMin * 1.001 {
                    for j in max(5, i - lookback)..<(i - 3) {
                        if let hj = val(hist, j), hj < 0, let hi = val(hist, i), hi > hj, closes[i] < closes[j] {
                            sc += 50
                            break
                        }
                    }
                }
                if let segMax = seg.max(), cur >= segMax * 0.999 {
                    for j in max(5, i - lookback)..<(i - 3) {
                        if let hj = val(hist, j), hj > 0, let hi = val(hist, i), hi < hj, closes[i] > closes[j] {
                            sc -= 50
                            break
                        }
                    }
                }
            }
            // 金叉死叉 + 柱
            if h > 0 && ph <= 0 {
                sc += 50
            } else if h < 0 && ph >= 0 {
                sc -= 50
            } else if h > 0 {
                sc += 20
            } else if h < 0 {
                sc -= 20
            }
            scores.append(max(-100, min(100, sc)))
        }

        // M011/12 RSI + KDJ 共振
        let rsi = IndicatorEngine.rsi(data)
        let kdj = IndicatorEngine.kdj(data)
        if let r = val(rsi, i), let kk = val(kdj.k, i), let dd = val(kdj.d, i) {
            var sc = 0.0
            if r <= 30 && kk <= 20 {
                sc += 100
            } else if r >= 70 && kk >= 80 {
                sc -= 100
            } else if r <= 30 || kk <= 20 {
                sc += 50
            } else if r >= 70 || kk >= 80 {
                sc -= 50
            } else if i >= 1, let pk = val(kdj.k, i - 1), let pd = val(kdj.d, i - 1), kk > pk, dd > pd {
                sc += 30
            } else if i >= 1, let pk = val(kdj.k, i - 1), let pd = val(kdj.d, i - 1), kk < pk, dd < pd {
                sc -= 30
            }
            scores.append(max(-100, min(100, sc)))
        }

        // M013 布林带
        let boll = IndicatorEngine.bollinger(data)
        if let up = val(boll.upper, i), let lo = val(boll.lower, i), let r = val(rsi, i) {
            if close <= lo && r < 40 {
                scores.append(100)
            } else if close <= lo * 1.01 {
                scores.append(60)
            } else if close >= up && r > 60 {
                scores.append(-100)
            } else if close >= up * 0.99 {
                scores.append(-60)
            } else {
                scores.append(0)
            }
        }

        guard !scores.isEmpty else { return 0 }
        return max(-100, min(100, Int((scores.reduce(0, +) / Double(scores.count)).rounded())))
    }

    // MARK: - 安全取值（保留 nil 占位的数组，与回测下标对齐）
    private static func val(_ arr: [Double?], _ idx: Int) -> Double? {
        guard idx >= 0, idx < arr.count else { return nil }
        return arr[idx]
    }

    // MARK: - 逐根K线历史信号（只做多 · 吊灯止损）
    /// 评分 ≥ +30 开多；评分 ≤ -30 平多离场（不开空）；吊灯止损 = 持仓最高价 − 3×ATR(14)
    static func perCandleSignals(_ data: [Kline]) -> [SignalMarker] {
        guard data.count >= 60 else { return [] }
        var signals: [SignalMarker] = []

        var position: PositionDirection = .none
        var entryStopLoss: Double = 0
        var highestPrice: Double = 0

        // 预计算 ATR
        let atrValues = IndicatorEngine.atr(data, period: 14)

        for i in 59..<data.count {
            let prefix = Array(data[0...i])
            let cs = composite(prefix)
            let candle = data[i]
            let score = cs.score
            let close = candle.close
            let atr = atrValues[i] ?? 0

            // 吊灯止损更新 + 止损检查（持仓中）
            if position == .long, atr > 0 {
                highestPrice = max(highestPrice, candle.high)
                entryStopLoss = highestPrice - config.chandelierATR * atr
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
            }

            // 平多离场：评分 ≤ -30（无持仓时不开空）
            if position == .long && score <= config.exitThreshold {
                signals.append(SignalMarker(
                    candleIndex: i,
                    type: .longClose,
                    price: close,
                    stopLoss: entryStopLoss,
                    stopTarget: close,
                    strength: min(abs(score), 100),
                    source: "离场信号",
                    timestamp: candle.timestamp
                ))
                position = .none
            }

            // 开多：评分 ≥ +30，空仓时开仓（避免持仓期内重复信号）
            if position == .none && score >= config.longThreshold {
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
                highestPrice = candle.high
            }
        }

        return signals
    }

    // MARK: - 实时信号（最后一根K线）
    /// 实时评分 ≥ +30 返回做多信号，否则 nil。价格用实时价优先。
    static func realtimeSignal(_ data: [Kline], livePrice: Double? = nil) -> (marker: SignalMarker?, score: Int) {
        guard data.count >= 60, let last = data.last else {
            return (nil, 0)
        }

        let cs = composite(data)
        let score = cs.score
        let candle = last
        let close = livePrice ?? candle.close

        guard score >= config.longThreshold else {
            return (nil, score)
        }

        let atr = IndicatorEngine.atr(data, period: 14).compactMap { $0 }.last ?? 0
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
}
