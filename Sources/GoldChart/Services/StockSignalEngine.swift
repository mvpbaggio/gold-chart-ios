import Foundation

// MARK: - A股信号引擎 v2（矩阵回测定稿 · 2026-08-09）
// 回测基准（474 只 × 严格7窗样本外 +397%、7窗全正；全样本 +587% 回撤-21%）：
//   信号：趋势组共振（M001趋势共振 + M002波段王 + M005智能均线 + M023多周期共振）
//         共振计数：|指标分|≥25 计 1 票，同向票数/4×100 → -100~+100
//   开仓：评分 ≥ +20 开多（只做多）
//   出场：吊灯 3×ATR 与 移动止盈 max(入场-3ATR, 持仓最高-2.5×ATR)（保本关 BE0）
//   成交：止损用最低价触线（matrix single_daily_rets l[i]<=stop 逻辑）
// 算法与 /tmp/bt/matrix_engine.py + matrix_mp.py 1:1 对齐
class StockSignalEngine {

    // MARK: - 配置（矩阵回测定稿参数）
    struct Config {
        var longThreshold: Int = 20        // 评分 ≥ 20 开多
        var chandelierATR: Double = 3.0    // 吊灯止损 ATR 倍数
        var trailATR: Double = 2.5         // 移动止盈 ATR 倍数
        var useBreakEven: Bool = false     // 保本开关（回测 BE0 → false）
        var minAbs: Double = 25.0          // 共振计数阈值（|指标分|≥25 算一票）

        static let `default` = Config()
    }

    static var config = Config.default

    // MARK: - 预计算（与 matrix_engine.compute_indicators 1:1）
    private struct Pre {
        let closes: [Double]
        let ma5: [Double]
        let ma10: [Double]
        let ma20: [Double]
        let ema20: [Double]
        let hh20: [Double]
        let ll20: [Double]
        let atr: [Double]        // nan 用均值填充后的 ATR14
        let vr: [Double]         // 20日量比
        let wk5: [Double]        // 周线近似 = sma(close,5)
        let ma5Slope: [Double]   // np.gradient(ma5)
        let ema20Slope: [Double] // np.gradient(ema20)
    }

    private static func sma(_ vals: [Double], _ p: Int) -> [Double] {
        let n = vals.count
        var out = [Double](repeating: 0, count: n)
        guard n >= p else { return out }
        var s = 0.0
        for i in 0..<n {
            s += vals[i]
            if i >= p { s -= vals[i - p] }
            if i >= p - 1 { out[i] = s / Double(p) }
        }
        return out
    }

    // EMA：种子 = 首根 close（回测 optimize.ema）
    private static func emaRec(_ vals: [Double], _ p: Int) -> [Double] {
        var out = [Double](repeating: 0, count: vals.count)
        guard !vals.isEmpty, p > 0 else { return out }
        let k = 2.0 / Double(p + 1)
        var e = vals[0]
        out[0] = e
        for i in 1..<vals.count {
            e = vals[i] * k + e * (1 - k)
            out[i] = e
        }
        return out
    }

    // numpy.gradient 等价：内部中心差分，端点单向差分
    private static func gradient(_ x: [Double]) -> [Double] {
        let n = x.count
        guard n > 1 else { return [Double](repeating: 0, count: n) }
        var g = [Double](repeating: 0, count: n)
        g[0] = x[1] - x[0]
        g[n - 1] = x[n - 1] - x[n - 2]
        for i in 1..<(n - 1) {
            g[i] = (x[i + 1] - x[i - 1]) / 2.0
        }
        return g
    }

    private static func precompute(_ data: [Kline]) -> Pre {
        let closes = data.map { $0.close }
        let n = closes.count
        let ma5 = sma(closes, 5)
        let ma10 = sma(closes, 10)
        let ma20 = sma(closes, 20)
        let ema20 = emaRec(closes, 20)

        // ATR14（matrix_engine 用 O.atr，SMA of TR，含首日 H-L）
        var trs = [Double](repeating: 0, count: n)
        for i in 0..<n {
            if i == 0 {
                trs[i] = data[i].high - data[i].low
            } else {
                trs[i] = max(data[i].high - data[i].low,
                             abs(data[i].high - data[i-1].close),
                             abs(data[i].low - data[i-1].close))
            }
        }
        var atr14 = [Double](repeating: 0, count: n)
        for i in 14..<n {
            var s = 0.0
            for j in (i - 13)...i { s += trs[j] }
            atr14[i] = s / 14.0
        }
        // nan → 均值填充（matrix_engine: np.nanmean(atr)）
        var validSum = 0.0, validCount = 0
        for i in 14..<n where atr14[i] > 0 { validSum += atr14[i]; validCount += 1 }
        let fill = validCount > 0 ? validSum / Double(validCount) : 1.0
        var atr = atr14
        for i in 0..<n where atr[i] <= 0 { atr[i] = fill }

        // 20日高低点
        var hh20 = [Double](repeating: 0, count: n)
        var ll20 = [Double](repeating: 0, count: n)
        for i in 19..<n {
            var hh = -Double.greatestFiniteMagnitude, ll = Double.greatestFiniteMagnitude
            for j in (i - 19)...i {
                hh = max(hh, data[j].high)
                ll = min(ll, data[j].low)
            }
            hh20[i] = hh; ll20[i] = ll
        }

        // 量比 vr = vol / ma20(vol)（matrix: convolve same，前19根 nan→1.0）
        var vma = [Double](repeating: 0, count: n)
        var vsum = 0.0
        for i in 0..<n {
            vsum += data[i].volume
            if i >= 20 { vsum -= data[i - 20].volume }
            if i >= 19 { vma[i] = vsum / 20.0 }
        }
        var vr = [Double](repeating: 1.0, count: n)
        for i in 19..<n where vma[i] > 0 { vr[i] = data[i].volume / vma[i] }

        let wk5 = sma(closes, 5)
        let ma5Slope = gradient(ma5)
        let ema20Slope = gradient(ema20)

        return Pre(closes: closes, ma5: ma5, ma10: ma10, ma20: ma20, ema20: ema20,
                   hh20: hh20, ll20: ll20, atr: atr, vr: vr, wk5: wk5,
                   ma5Slope: ma5Slope, ema20Slope: ema20Slope)
    }

    // MARK: - M001 趋势共振（sig_m001）
    private static func sigM001(_ pre: Pre, _ i: Int) -> Double {
        let c = pre.closes[i], m5 = pre.ma5[i], m10 = pre.ma10[i], m20 = pre.ma20[i]
        var s = 0.0
        let bull = c > m5 && m5 > m10 && m10 > m20
        let bear = c < m5 && m5 < m10 && m10 < m20
        let midb = m5 > m10 && m10 > m20
        let midbe = m5 < m10 && m10 < m20
        if bull { s += 60 } else if bear { s -= 60 }
        if midb { s += 30 } else if midbe { s -= 30 }
        if pre.ma5Slope[i] > 0 { s += 20 } else if pre.ma5Slope[i] < 0 { s -= 20 }
        return max(-100, min(100, s))
    }

    // MARK: - M002 波段王（sig_m002）
    private static func sigM002(_ pre: Pre, _ i: Int) -> Double {
        let c = pre.closes[i]
        let hh = pre.hh20[i], ll = pre.ll20[i]
        let atr = pre.atr[i]
        let vr = pre.vr[i]
        var s = 0.0
        if c > hh - 0.5 * atr {
            s += 50
            if vr > 1.5 { s += 30 }
        } else if c < ll + 0.5 * atr {
            s -= 50
            if vr > 1.5 { s -= 30 }
        }
        return max(-100, min(100, s))
    }

    // MARK: - M005 智能均线（sig_m005）
    private static func sigM005(_ pre: Pre, _ i: Int) -> Double {
        let c = pre.closes[i], e = pre.ema20[i]
        var s = 0.0
        if c > e { s += 40 } else { s -= 40 }
        if i >= 1 {
            let pc = pre.closes[i - 1], pe = pre.ema20[i - 1]
            if c > e && pc <= pe { s += 30 }
            if c < e && pc >= pe { s -= 30 }
        }
        if pre.ema20Slope[i] > 0 { s += 20 } else if pre.ema20Slope[i] < 0 { s -= 20 }
        return max(-100, min(100, s))
    }

    // MARK: - M023 多周期共振（sig_m023）
    private static func sigM023(_ pre: Pre, _ i: Int) -> Double {
        let c = pre.closes[i], m5 = pre.ma5[i], wk5 = pre.wk5[i]
        var s = 0.0
        let b1 = c > m5 && m5 > wk5
        let b2 = c < m5 && m5 < wk5
        if b1 { s += 60 } else if b2 { s -= 60 }
        if c > m5 && !b1 { s += 25 } else if c < m5 && !b2 { s -= 25 }
        return max(-100, min(100, s))
    }

    // MARK: - 趋势组共振评分（group_score：趋势组 4 指标，min_abs=25）
    static func makeScores(_ data: [Kline]) -> [Double] {
        guard data.count >= 60 else { return [] }
        let pre = precompute(data)
        let n = data.count
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var pos = 0.0, neg = 0.0
            let scores: [Double] = [sigM001(pre, i), sigM002(pre, i), sigM005(pre, i), sigM023(pre, i)]
            for v in scores {
                if v >= config.minAbs { pos += 1 }
                else if v <= -config.minAbs { neg += 1 }
            }
            out[i] = (pos - neg) / 4.0 * 100.0
        }
        return out
    }

    // MARK: - A股融合评分（UI 展示）
    static func composite(_ data: [Kline]) -> CompositeSignal {
        guard data.count >= 60 else {
            return CompositeSignal(score: 0, breakdown: [
                SignalBreakdown(name: "数据不足", score: 0, weight: 1.0)
            ])
        }
        let pre = precompute(data)
        let i = data.count - 1
        let m1 = sigM001(pre, i), m2 = sigM002(pre, i), m5 = sigM005(pre, i), m23 = sigM023(pre, i)
        var pos = 0.0, neg = 0.0
        for v in [m1, m2, m5, m23] {
            if v >= config.minAbs { pos += 1 }
            else if v <= -config.minAbs { neg += 1 }
        }
        let total = (pos - neg) / 4.0 * 100.0
        let score = Int(max(-100, min(100, total.rounded())))
        return CompositeSignal(score: score, breakdown: [
            SignalBreakdown(name: "M001趋势共振", score: Int(m1.rounded()), weight: 1.0),
            SignalBreakdown(name: "M002波段王", score: Int(m2.rounded()), weight: 1.0),
            SignalBreakdown(name: "M005智能均线", score: Int(m5.rounded()), weight: 1.0),
            SignalBreakdown(name: "M023多周期", score: Int(m23.rounded()), weight: 1.0)
        ])
    }

    // MARK: - 逐根K线历史信号（matrix single_daily_rets 逻辑 · 只做多）
    /// 开仓：评分 ≥ +20；止损线 = max(入场-3ATR, 持仓最高-2.5×ATR)（BE0 不启用保本）
    /// 出场：最低价 ≤ 止损线（触线成交，与回测 l[i]<=stop 一致）
    static func perCandleSignals(_ data: [Kline]) -> [SignalMarker] {
        guard data.count >= 60 else { return [] }
        let pre = precompute(data)
        let scores = makeScores(data)
        guard scores.count == data.count else { return [] }

        var signals: [SignalMarker] = []
        var inPosition = false
        var entry: Double = 0
        var highest: Double = 0

        for i in 1..<data.count {
            let candle = data[i]
            let a = pre.atr[i] > 0 ? pre.atr[i] : 1e-9
            let sc = scores[i]

            if inPosition {
                highest = max(highest, candle.high)
                var stop = entry - config.chandelierATR * a
                if config.useBreakEven && (highest - entry) > 1.0 * a {
                    stop = max(stop, entry)
                }
                if config.trailATR > 0 {
                    stop = max(stop, highest - config.trailATR * a)
                }
                if candle.low <= stop {
                    signals.append(SignalMarker(
                        candleIndex: i, type: .longClose, price: stop,
                        stopLoss: stop, stopTarget: stop,
                        strength: 100, source: "止盈止损", timestamp: candle.timestamp
                    ))
                    inPosition = false
                }
            } else {
                if sc >= Double(config.longThreshold) {
                    signals.append(SignalMarker(
                        candleIndex: i, type: .longOpen, price: candle.close,
                        stopLoss: candle.low - config.chandelierATR * a, stopTarget: nil,
                        strength: min(Int(sc.rounded()), 100),
                        source: "趋势共振", timestamp: candle.timestamp
                    ))
                    inPosition = true; entry = candle.close; highest = candle.high
                }
            }
        }

        return signals
    }

    // MARK: - 实时信号（最后一根K线）
    /// 评分 ≥ +20 返回做多信号，否则 nil
    static func realtimeSignal(_ data: [Kline], livePrice: Double? = nil) -> (marker: SignalMarker?, score: Int) {
        guard data.count >= 60, let last = data.last else { return (nil, 0) }
        let pre = precompute(data)
        let i = data.count - 1
        let m1 = sigM001(pre, i), m2 = sigM002(pre, i), m5 = sigM005(pre, i), m23 = sigM023(pre, i)
        var pos = 0.0, neg = 0.0
        for v in [m1, m2, m5, m23] {
            if v >= config.minAbs { pos += 1 }
            else if v <= -config.minAbs { neg += 1 }
        }
        let total = (pos - neg) / 4.0 * 100.0
        let score = Int(max(-100, min(100, total.rounded())))
        let close = livePrice ?? last.close

        guard total >= Double(config.longThreshold) else { return (nil, score) }

        let a = pre.atr[i] > 0 ? pre.atr[i] : 0
        let sl = last.low - config.chandelierATR * a
        return (SignalMarker(
            candleIndex: i, type: .longOpen, price: close,
            stopLoss: sl, stopTarget: nil,
            strength: min(score, 100), source: "实时信号", timestamp: last.timestamp
        ), score)
    }
}