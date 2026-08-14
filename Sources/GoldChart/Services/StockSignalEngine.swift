import Foundation

// MARK: - A股信号引擎 v3（gate_trmo 双确认 · 2026-08-14）
// 回测基准（474 只 × 严格7窗样本外 +456%、7窗全正；全样本 +612% 回撤-18%）
//   信号：趋势组共振（M001+M002+M005+M023）做主信号 ≥ +20
//         动量组共振（M010 MACD柱 + M011 RSI + M012 KDJ + M014 CCI）做确认闸门
//         gate_trmo_1：确认组净票合计≥1（趋势+动量双确认）才开仓
//   出场：吊灯 2×ATR 与 移动止盈 max(入场-2ATR, 持仓最高-3×ATR)（保本关 BE0，WF+466.7% 7窗全正）
//   成交：止损用最低价触线（matrix single_daily_rets l[i]<=stop 逻辑）
// 算法与 /tmp/bt/matrix_engine.py + matrix_mp.py 1:1 对齐
class StockSignalEngine {

    // MARK: - 配置（矩阵回测定稿参数）
    struct Config {
        var longThreshold: Int = 20        // 评分 ≥ 20 开多
        var chandelierATR: Double = 2.0    // 吊灯止损 ATR 倍数（WF最优 ch2.0）
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
        // 动量组所需（gate_trmo 双确认）
        let macdHist: [Double]   // MACD 柱 (DIF-DEA)
        let rsi: [Double]        // RSI(14)
        let k: [Double]          // KDJ K
        let d: [Double]          // KDJ D
        let cci: [Double]        // CCI(14)
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

        // ═══ 动量组字段（gate_trmo 双确认需要）═══
        // MACD(12,26,9)：与 optimize.macd 1:1（ema 种子=首根close）
        let ema12 = emaRec(closes, 12)
        let ema26 = emaRec(closes, 26)
        var dif = [Double](repeating: 0, count: n)
        for i in 0..<n { dif[i] = ema12[i] - ema26[i] }
        let dea = emaRec(dif, 9)
        var macdHist = [Double](repeating: 0, count: n)
        for i in 0..<n { macdHist[i] = dif[i] - dea[i] }

        // RSI(14)：与 optimize.rsi 1:1（SMA of gains/losses, 首 p 根 NaN→0）
        var rsi = [Double](repeating: 0, count: n)
        for i in 14..<n {
            var gsum = 0.0, lsum = 0.0
            for j in (i - 13)...i {
                let ch = closes[j] - closes[j - 1]
                if ch > 0 { gsum += ch } else { lsum += -ch }
            }
            let ag = gsum / 14.0, al = lsum / 14.0
            rsi[i] = al == 0 ? 100.0 : 100.0 - 100.0 / (1.0 + ag / al)
        }

        // KDJ(9)：与 optimize.kdj 1:1（k,d 种子 50，递归平滑）
        var kArr = [Double](repeating: 50.0, count: n)
        var dArr = [Double](repeating: 50.0, count: n)
        var prevK = 50.0, prevD = 50.0
        for i in 0..<n {
            let lo0 = max(0, i - 8)
            var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude
            for j in lo0...i {
                lo = min(lo, data[j].low)
                hi = max(hi, data[j].high)
            }
            let rsv = hi == lo ? 50.0 : (data[i].close - lo) / (hi - lo) * 100.0
            let k = prevK * 2.0 / 3.0 + rsv / 3.0
            let d = prevD * 2.0 / 3.0 + k / 3.0
            kArr[i] = k; dArr[i] = d
            prevK = k; prevD = d
        }

        // CCI(14)：与 compute_indicators 1:1（tp=(h+l+c)/3, md=平均绝对偏差）
        var cci = [Double](repeating: 0, count: n)
        for i in 13..<n {
            var tpSum = 0.0
            var tps = [Double](repeating: 0, count: 14)
            for j in 0..<14 {
                let idx = i - 13 + j
                tps[j] = (data[idx].high + data[idx].low + data[idx].close) / 3.0
                tpSum += tps[j]
            }
            let smaTp = tpSum / 14.0
            var md = 0.0
            for j in 0..<14 { md += abs(tps[j] - smaTp) }
            md /= 14.0
            let tp = (data[i].high + data[i].low + data[i].close) / 3.0
            cci[i] = md > 0 ? (tp - smaTp) / (0.015 * md) : 0
        }

        return Pre(closes: closes, ma5: ma5, ma10: ma10, ma20: ma20, ema20: ema20,
                   hh20: hh20, ll20: ll20, atr: atr, vr: vr, wk5: wk5,
                   ma5Slope: ma5Slope, ema20Slope: ema20Slope,
                   macdHist: macdHist, rsi: rsi, k: kArr, d: dArr, cci: cci)
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

    // MARK: - M010 MACD柱（sig_m010）
    private static func sigM010(_ pre: Pre, _ i: Int) -> Double {
        let h = pre.macdHist[i]
        let ph = i > 0 ? pre.macdHist[i - 1] : 0
        var s = 0.0
        let gc = h > 0 && ph <= 0
        let dc = h < 0 && ph >= 0
        if gc { s += 50 } else if dc { s -= 50 }
        if h > 0 { s += 20 } else if h < 0 { s -= 20 }
        return max(-100, min(100, s))
    }

    // MARK: - M011 RSI（sig_m011）
    private static func sigM011(_ pre: Pre, _ i: Int) -> Double {
        let r = pre.rsi[i]
        var s = 0.0
        if r < 30 { s += 50 } else if r < 45 { s += 20 }
        if r > 70 { s -= 50 } else if r > 55 { s -= 20 }
        if i >= 1 {
            let pr = pre.rsi[i - 1]
            if r > pr && r < 40 { s += 30 }
            if r < pr && r > 60 { s -= 30 }
        }
        return max(-100, min(100, s))
    }

    // MARK: - M012 KDJ（sig_m012）
    private static func sigM012(_ pre: Pre, _ i: Int) -> Double {
        let k = pre.k[i], d = pre.d[i]
        let k1 = i > 0 ? pre.k[i - 1] : 0
        let d1 = i > 0 ? pre.d[i - 1] : 0
        var s = 0.0
        let gcLo = (k > d) && (k1 <= d1) && (k < 30)
        let dcHi = (k < d) && (k1 >= d1) && (k > 70)
        if gcLo { s += 70 } else if (k > d) && !gcLo { s += 30 }
        if dcHi { s -= 70 } else if (k < d) && !dcHi { s -= 30 }
        return max(-100, min(100, s))
    }

    // MARK: - M014 CCI（sig_m014）
    private static func sigM014(_ pre: Pre, _ i: Int) -> Double {
        let c = pre.cci[i]
        var s = 0.0
        if c < -100 { s += 50 } else if c < -50 { s += 20 }
        if c > 100 { s -= 50 } else if c > 50 { s -= 20 }
        if i >= 1 {
            let pc = pre.cci[i - 1]
            if c > pc && c < -80 { s += 30 }
            if c < pc && c > 80 { s -= 30 }
        }
        return max(-100, min(100, s))
    }

    // MARK: - 动量组共振分（M010+M011+M012+M014，min_abs=25）
    static func momentumScores(_ data: [Kline]) -> [Double] {
        guard data.count >= 60 else { return [] }
        let pre = precompute(data)
        let n = data.count
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var pos = 0.0, neg = 0.0
            let scores: [Double] = [sigM010(pre, i), sigM011(pre, i), sigM012(pre, i), sigM014(pre, i)]
            for v in scores {
                if v >= config.minAbs { pos += 1 }
                else if v <= -config.minAbs { neg += 1 }
            }
            out[i] = (pos - neg) / 4.0 * 100.0
        }
        return out
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
    // MARK: - gate_trmo_1 双确认闸门（与回测 sig_gate 1:1）
    /// 趋势组评分≥20（主信号，隐含趋势组净票≥1）且 确认组净票合计≥1
    /// 确认组 = 趋势组+动量组：各组成员 |指标分|≥minAbs 计 1 票，净票 = 多票-空票
    /// 因 group_score 输出恒为 25 的倍数 → 净票 = Int(评分/25)
    private static func gateTrmoPass(trendScore: Double, momentumScore: Double) -> Bool {
        let trNet = Int(trendScore / config.minAbs)      // 趋势组净票（≥20 时 ≥1）
        let moNet = Int(momentumScore / config.minAbs)   // 动量组净票
        return trendScore >= Double(config.longThreshold) && (trNet + moNet) >= 1
    }

    static func perCandleSignals(_ data: [Kline]) -> [SignalMarker] {
        guard data.count >= 60 else { return [] }
        let pre = precompute(data)
        let scores = makeScores(data)
        let mScores = momentumScores(data)
        guard scores.count == data.count, mScores.count == data.count else { return [] }

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
                // gate_trmo_1：趋势+动量双确认（净票合计≥1）
                if gateTrmoPass(trendScore: sc, momentumScore: mScores[i]) {
                    signals.append(SignalMarker(
                        candleIndex: i, type: .longOpen, price: candle.close,
                        stopLoss: candle.low - config.chandelierATR * a, stopTarget: nil,
                        strength: min(Int(sc.rounded()), 100),
                        source: "趋势+动量共振", timestamp: candle.timestamp
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

        // gate_trmo_1：趋势+动量双确认（净票合计≥1）
        let m10 = sigM010(pre, i), m11 = sigM011(pre, i), m12 = sigM012(pre, i), m14 = sigM014(pre, i)
        var mpos = 0.0, mneg = 0.0
        for v in [m10, m11, m12, m14] {
            if v >= config.minAbs { mpos += 1 }
            else if v <= -config.minAbs { mneg += 1 }
        }
        let mTotal = (mpos - mneg) / 4.0 * 100.0

        guard gateTrmoPass(trendScore: total, momentumScore: mTotal) else { return (nil, score) }

        let a = pre.atr[i] > 0 ? pre.atr[i] : 0
        let sl = last.low - config.chandelierATR * a
        return (SignalMarker(
            candleIndex: i, type: .longOpen, price: close,
            stopLoss: sl, stopTarget: nil,
            strength: min(score, 100), source: "实时信号", timestamp: last.timestamp
        ), score)
    }
}