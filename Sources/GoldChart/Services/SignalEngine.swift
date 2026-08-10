import Foundation

// MARK: - 金银信号引擎 v4（回测定稿 · 2026-08-09）
// 回测基准（金银 2590 根 × 严格7窗样本外 +149% 回撤-26%，80组邻域78组正收益）：
//   因子：动量(s_biga_gold) 1 : EMA排列(s_ema_align) 1 : 波动状态(atr_state) 2 : RSI动量(rsi_momentum) 2
//   开仓：评分 ≥ +18 做多 / ≤ -18 做空；ADX(14) ≥ 20 过滤（仅开仓时）
//   出场：吊灯 3×ATR + 移动止盈 2×ATR（trail），保本关（BE=false）
//   反手：评分反向过阈值 → 先平仓再开反向仓
// 算法与 /tmp/bt/engine_v4.py + gold_grid.py 1:1 对齐
class SignalEngine {

    // MARK: - 配置（回测定稿参数）
    struct Config {
        var longThreshold: Int = 18        // 评分 ≥ 18 做多
        var shortThreshold: Int = -18      // 评分 ≤ -18 做空
        var chandelierATR: Double = 3.0    // 吊灯止损 ATR 倍数
        var trailATR: Double = 2.0         // 移动止盈 ATR 倍数
        var adxMin: Double = 20.0          // ADX 过滤（开仓）
        var useBreakEven: Bool = false     // 保本开关（回测 BE0 → false）

        static let `default` = Config()
    }

    static var config = Config.default

    // MARK: - 预计算（与回测 precompute 1:1）
    private struct Pre {
        let opens: [Double]
        let highs: [Double]
        let lows: [Double]
        let closes: [Double]
        let ema9: [Double]
        let ema21: [Double]
        let ema50: [Double]
        let ema200: [Double]
        let rsi: [Double]       // SMA 型 RSI（回测 optimize.rsi）
        let atr: [Double]       // SMA 型 ATR（含当天 TR，回测 optimize.atr）
        let adx: [Double]       // Wilder ADX（回测 final6.adx）
        let chg5: [Double]      // 5日涨跌幅 %
        let chg: [Double]       // 单日涨跌幅 %
        let amp: [Double]       // 振幅 = (H-L)/O*100
    }

    // EMA：种子 = 首根 close（回测 ema_arr / optimize.ema，非 SMA 种子）
    private static func emaArr(_ vals: [Double], _ p: Int) -> [Double] {
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

    // ATR：SMA of TR；TR[0]=H-L；out[i] = mean(TR[i-13...i])（回测 optimize.atr）
    private static func atrPy(_ kl: [Kline], _ p: Int = 14) -> [Double] {
        let n = kl.count
        var trs = [Double](repeating: 0, count: n)
        for i in 0..<n {
            if i == 0 {
                trs[i] = kl[i].high - kl[i].low
            } else {
                trs[i] = max(kl[i].high - kl[i].low,
                             abs(kl[i].high - kl[i-1].close),
                             abs(kl[i].low - kl[i-1].close))
            }
        }
        var out = [Double](repeating: 0, count: n)
        for i in p..<n {
            var s = 0.0
            for j in (i - p + 1)...i { s += trs[j] }
            out[i] = s / Double(p)
        }
        return out
    }

    // RSI：SMA 型（回测 optimize.rsi：每个 i 重算窗口均值）
    private static func rsiSMA(_ closes: [Double], _ p: Int = 14) -> [Double] {
        let n = closes.count
        var out = [Double](repeating: 0, count: n)
        guard n > p else { return out }
        for i in p..<n {
            var g = 0.0, l = 0.0
            for j in (i - p + 1)...i {
                let ch = closes[j] - closes[j-1]
                if ch > 0 { g += ch } else { l += -ch }
            }
            out[i] = l == 0 ? 100 : 100 - 100 / (1 + g / l)
        }
        return out
    }

    // ADX：Wilder 平滑（回测 final6.adx）
    private static func adx(_ kl: [Kline], _ p: Int = 14) -> [Double] {
        let n = kl.count
        var tr = [Double](repeating: 0, count: n)
        var pdm = [Double](repeating: 0, count: n)
        var mdm = [Double](repeating: 0, count: n)
        for i in 1..<n {
            let h = kl[i].high, l = kl[i].low, pc = kl[i-1].close
            tr[i] = max(h - l, abs(h - pc), abs(l - pc))
            let up = h - kl[i-1].high
            let dn = kl[i-1].low - l
            pdm[i] = (up > dn && up > 0) ? up : 0
            mdm[i] = (dn > up && dn > 0) ? dn : 0
        }
        func wilder(_ arr: [Double]) -> [Double] {
            var out = [Double](repeating: 0, count: n)
            if n <= p { return out }
            var s = 0.0
            for j in 1...p { s += arr[j] }
            out[p] = s
            for i in (p + 1)..<n {
                s = (s - s / Double(p)) + arr[i]
                out[i] = s
            }
            return out
        }
        let atrW = wilder(tr), pdmW = wilder(pdm), mdmW = wilder(mdm)
        var dx = [Double](repeating: 0, count: n)
        for i in p..<n {
            if atrW[i] == 0 { continue }
            let pdi = pdmW[i] / atrW[i] * 100
            let mdi = mdmW[i] / atrW[i] * 100
            let s = pdi + mdi
            dx[i] = s == 0 ? 0 : abs(pdi - mdi) / s * 100
        }
        var adxV = [Double](repeating: 0, count: n)
        if n > p + p {
            var s = 0.0
            for j in p..<(p + p) { s += dx[j] }
            adxV[p + p - 1] = s / Double(p)
            for i in (p + p)..<n {
                s = (s - s / Double(p)) + dx[i]
                adxV[i] = s / Double(p)
            }
        }
        return adxV
    }

    private static func precompute(_ data: [Kline]) -> Pre {
        let opens = data.map { $0.open }
        let highs = data.map { $0.high }
        let lows = data.map { $0.low }
        let closes = data.map { $0.close }
        let n = closes.count
        var chg = [Double](repeating: 0, count: n)
        for i in 1..<n { chg[i] = (closes[i] - closes[i-1]) / closes[i-1] * 100 }
        var chg5 = [Double](repeating: 0, count: n)
        for i in 5..<n { chg5[i] = (closes[i] - closes[i-5]) / closes[i-5] * 100 }
        var amp = [Double](repeating: 0, count: n)
        for i in 0..<n { amp[i] = opens[i] > 0 ? (highs[i] - lows[i]) / opens[i] * 100 : 0 }
        return Pre(opens: opens, highs: highs, lows: lows, closes: closes,
                   ema9: emaArr(closes, 9), ema21: emaArr(closes, 21),
                   ema50: emaArr(closes, 50), ema200: emaArr(closes, 200),
                   rsi: rsiSMA(closes), atr: atrPy(data), adx: adx(data),
                   chg5: chg5, chg: chg, amp: amp)
    }

    // MARK: - 因子 1：动量（回测 s_biga_gold）
    private static func scoreMomentum(_ pre: Pre, _ i: Int) -> Double {
        var s = 0.0
        let c5 = pre.chg5[i]
        if c5 < -15 { s += 40 }
        else if c5 < -8 { s += 27 }
        else if c5 <= 5 { s += 0 }
        else if c5 <= 15 { s -= 13 }
        else if c5 <= 25 { s -= 27 }
        else { s -= 40 }
        let o = pre.opens[i], c = pre.closes[i]
        let amp = pre.amp[i]
        let chg = pre.chg[i]
        if chg > 0 && c > o && amp > 2.5 { s += 30 }
        else if chg < 0 && c < o && amp > 2.5 { s -= 30 }
        else if -3 < chg && chg < 0 { s += 10 }
        return max(-100, min(100, s))
    }

    // MARK: - 因子 2：EMA排列（回测 s_ema_align）
    private static func scoreEMA(_ pre: Pre, _ i: Int) -> Double {
        if i < 50 { return 0 }
        let e9 = pre.ema9[i], e21 = pre.ema21[i], e50 = pre.ema50[i]
        var s = 0.0
        if e9 > e21 && e21 > e50 { s += 30 }
        if i >= 200 && e50 > pre.ema200[i] { s += 10 }
        else if e9 < e21 && e21 < e50 { s -= 30 }
        else { s += e9 > e21 ? 8 : -8 }
        return s
    }

    // MARK: - 因子 3：波动状态（回测 atr_state）
    private static func scoreVolState(_ pre: Pre, _ i: Int) -> Double {
        if i < 21 { return 0 }
        let a = pre.atr[i]
        if a <= 0 { return 0 }
        var sum = 0.0
        for j in (i - 20)..<i { sum += pre.atr[j] }
        let avg = sum / 20.0
        if a > avg * 1.3 { return 30 }
        if a < avg * 0.7 { return -15 }
        return 0
    }

    // MARK: - 因子 4：RSI动量（回测 rsi_momentum）
    private static func scoreRSIMom(_ pre: Pre, _ i: Int) -> Double {
        if i < 2 { return 0 }
        let d = pre.rsi[i] - pre.rsi[i-1]
        if d > 5 { return 40 }
        if d > 2 { return 20 }
        if d < -5 { return -40 }
        if d < -2 { return -20 }
        return 0
    }

    // MARK: - 全序列评分 [Double]（回测 make_scores）
    static func makeScores(_ data: [Kline]) -> [Double] {
        guard data.count >= 60 else { return [] }
        let pre = precompute(data)
        let n = data.count
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let m = scoreMomentum(pre, i)
            let e = scoreEMA(pre, i)
            let v = scoreVolState(pre, i)
            let r = scoreRSIMom(pre, i)
            let total = (m * 1 + e * 1 + v * 2 + r * 2) / 6.0
            out[i] = max(-100, min(100, total))
        }
        return out
    }

    // MARK: - H动态空头阈值（超哥拍板 2026-08-10）
    /// EMA50 下降趋势（当前 < 20根前）→ 空头阈值放宽到 -12，否则维持 -18
    /// 回测 gold_dynamic_th.py：H 动态-12 空头 75 笔 -29.0% 合计 +219.2%（超哥选定）
    private static func effectiveShortThreshold(_ pre: Pre, _ i: Int) -> Double {
        if i >= 20 && pre.ema50[i] < pre.ema50[i - 20] {
            return -12
        }
        return Double(config.shortThreshold)
    }

    // MARK: - 金银融合评分（UI 展示）
    static func composite(_ data: [Kline]) -> CompositeSignal {
        guard data.count >= 60 else {
            return CompositeSignal(score: 0, breakdown: [
                SignalBreakdown(name: "数据不足", score: 0, weight: 1.0)
            ])
        }
        let pre = precompute(data)
        let i = data.count - 1
        let m = scoreMomentum(pre, i)
        let e = scoreEMA(pre, i)
        let v = scoreVolState(pre, i)
        let r = scoreRSIMom(pre, i)
        let total = (m * 1 + e * 1 + v * 2 + r * 2) / 6.0
        let score = Int(max(-100, min(100, total.rounded())))
        return CompositeSignal(score: score, breakdown: [
            SignalBreakdown(name: "动量", score: Int(m.rounded()), weight: 1.0),
            SignalBreakdown(name: "EMA排列", score: Int(e.rounded()), weight: 1.0),
            SignalBreakdown(name: "波动状态", score: Int(v.rounded()), weight: 2.0),
            SignalBreakdown(name: "RSI动量", score: Int(r.rounded()), weight: 2.0)
        ])
    }

    // MARK: - 逐根K线历史信号（回测 run_v4：吊灯+移动止盈+反手）
    /// 开仓：评分≥+18（ADX≥20）做多 / ≤-18 做空；持仓中评分反向过阈值 → 反手
    /// 止损：多头 = max(入场-3ATR, 持仓最高-2×ATR)；空头 = min(入场+3ATR, 持仓最低+2×ATR)
    /// 判定用收盘价（与回测 run_v4 一致）
    static func perCandleSignals(_ data: [Kline]) -> [SignalMarker] {
        guard data.count >= 60 else { return [] }
        let pre = precompute(data)
        let scores = makeScores(data)
        guard scores.count == data.count else { return [] }

        var signals: [SignalMarker] = []
        var position: PositionDirection = .none
        var entry: Double = 0
        var highest: Double = 0
        var lowest: Double = 0

        for i in 60..<data.count {
            let candle = data[i]
            let px = candle.close
            let a = pre.atr[i] > 0 ? pre.atr[i] : 1.0
            let sc = scores[i]

            if position != .none {
                // 反手：反向信号过阈值 → 平仓并开反向仓
                if position == .long && sc <= effectiveShortThreshold(pre, i) {
                    signals.append(SignalMarker(
                        candleIndex: i, type: .longClose, price: px,
                        stopLoss: entry, stopTarget: px,
                        strength: min(abs(Int(sc.rounded())), 100),
                        source: "反向信号", timestamp: candle.timestamp
                    ))
                    signals.append(SignalMarker(
                        candleIndex: i, type: .shortOpen, price: px,
                        stopLoss: candle.high + config.chandelierATR * a, stopTarget: nil,
                        strength: min(abs(Int(sc.rounded())), 100),
                        source: "追风揽月", timestamp: candle.timestamp
                    ))
                    position = .short; entry = px; lowest = candle.low
                    continue
                }
                if position == .short && sc >= Double(config.longThreshold) {
                    signals.append(SignalMarker(
                        candleIndex: i, type: .shortClose, price: px,
                        stopLoss: entry, stopTarget: px,
                        strength: min(abs(Int(sc.rounded())), 100),
                        source: "反向信号", timestamp: candle.timestamp
                    ))
                    signals.append(SignalMarker(
                        candleIndex: i, type: .longOpen, price: px,
                        stopLoss: candle.low - config.chandelierATR * a, stopTarget: nil,
                        strength: min(abs(Int(sc.rounded())), 100),
                        source: "追风揽月", timestamp: candle.timestamp
                    ))
                    position = .long; entry = px; highest = candle.high
                    continue
                }

                if position == .long {
                    highest = max(highest, candle.high)
                    var stop = entry - config.chandelierATR * a
                    if config.useBreakEven && (highest - entry) > 1.0 * a {
                        stop = max(stop, entry)
                    }
                    let line = max(stop, highest - config.trailATR * a)
                    if px <= line {
                        // 有利离场（浮盈回撤触发移动止盈）→ 额外标“盈”
                        if px > entry {
                            signals.append(SignalMarker(
                                candleIndex: i, type: .longTakeProfit, price: line,
                                stopLoss: entry, stopTarget: px,
                                strength: 90, source: "移动止盈", timestamp: candle.timestamp
                            ))
                        }
                        signals.append(SignalMarker(
                            candleIndex: i, type: .longClose, price: px,
                            stopLoss: line, stopTarget: px,
                            strength: 100, source: "止盈止损", timestamp: candle.timestamp
                        ))
                        position = .none
                    }
                } else {
                    lowest = min(lowest, candle.low)
                    var stop = entry + config.chandelierATR * a
                    if config.useBreakEven && (entry - lowest) >= 1.0 * a {
                        stop = min(stop, entry)
                    }
                    let line = min(stop, lowest + config.trailATR * a)
                    if px >= line {
                        // 有利离场（浮盈反弹触发移动止盈）→ 额外标“盈”
                        if px < entry {
                            signals.append(SignalMarker(
                                candleIndex: i, type: .shortTakeProfit, price: line,
                                stopLoss: entry, stopTarget: px,
                                strength: 90, source: "移动止盈", timestamp: candle.timestamp
                            ))
                        }
                        signals.append(SignalMarker(
                            candleIndex: i, type: .shortClose, price: px,
                            stopLoss: line, stopTarget: px,
                            strength: 100, source: "止盈止损", timestamp: candle.timestamp
                        ))
                        position = .none
                    }
                }
            } else {
                // ADX 过滤（仅开仓；回测 run_v4 同款）
                if pre.adx[i] < config.adxMin { continue }
                if sc >= Double(config.longThreshold) {
                    let sl = candle.low - config.chandelierATR * a
                    signals.append(SignalMarker(
                        candleIndex: i, type: .longOpen, price: px,
                        stopLoss: sl, stopTarget: nil,
                        strength: min(Int(sc.rounded()), 100),
                        source: "追风揽月", timestamp: candle.timestamp
                    ))
                    position = .long; entry = px; highest = candle.high
                } else if sc <= effectiveShortThreshold(pre, i) {
                    let sl = candle.high + config.chandelierATR * a
                    signals.append(SignalMarker(
                        candleIndex: i, type: .shortOpen, price: px,
                        stopLoss: sl, stopTarget: nil,
                        strength: min(abs(Int(sc.rounded())), 100),
                        source: "追风揽月", timestamp: candle.timestamp
                    ))
                    position = .short; entry = px; lowest = candle.low
                }
            }
        }

        return signals
    }

    // MARK: - 实时信号（最后一根K线）
    /// 评分 ≥ +18（ADX≥20）→ 做多；≤ -18 → 做空；否则 nil
    static func realtimeSignal(_ data: [Kline], livePrice: Double? = nil) -> (marker: SignalMarker?, score: Int) {
        guard data.count >= 60, let last = data.last else { return (nil, 0) }
        let pre = precompute(data)
        let scores = makeScores(data)
        guard scores.count == data.count else { return (nil, 0) }
        let sc = scores[data.count - 1]
        let scoreInt = Int(max(-100, min(100, sc.rounded())))
        let close = livePrice ?? last.close
        let a = pre.atr[data.count - 1] > 0 ? pre.atr[data.count - 1] : 0
        let i = data.count - 1

        let effShort = effectiveShortThreshold(pre, i)
        let thL = Double(config.longThreshold)
        guard sc >= thL || sc <= effShort else { return (nil, scoreInt) }
        guard pre.adx[i] >= config.adxMin else { return (nil, scoreInt) }

        if sc >= thL {
            let sl = last.low - config.chandelierATR * a
            return (SignalMarker(
                candleIndex: data.count - 1, type: .longOpen, price: close,
                stopLoss: sl, stopTarget: nil,
                strength: min(scoreInt, 100), source: "实时信号", timestamp: last.timestamp
            ), scoreInt)
        }
        let sl = last.high + config.chandelierATR * a
        return (SignalMarker(
            candleIndex: data.count - 1, type: .shortOpen, price: close,
            stopLoss: sl, stopTarget: nil,
            strength: min(abs(scoreInt), 100), source: "实时信号", timestamp: last.timestamp
        ), scoreInt)
    }

    // MARK: - 当前持仓止盈线（build78：让止盈线看得见）
    /// 返回当前持仓的移动止盈线价格（不触发也能拿到，供 UI 展示）：
    ///   多单：持仓以来最高价 − trail×ATR；空单：持仓以来最低价 + trail×ATR
    /// 与 realtimeTakeProfit 同一套逻辑，只计算不判断触发。无持仓/数据不足返回 nil
    static func currentTakeProfitLine(
        _ data: [Kline],
        position: PositionDirection,
        entryPrice: Double,
        entryIndex: Int? = nil,
        livePrice: Double? = nil
    ) -> Double? {
        guard position != .none, entryPrice > 0 else { return nil }
        guard data.count >= 60, data.count > (entryIndex ?? 60) else { return nil }
        let pre = precompute(data)
        let a = pre.atr[data.count - 1]
        guard a > 0 else { return nil }
        let startIdx = max(60, entryIndex ?? 60)
        let lp = livePrice ?? data[data.count - 1].close
        switch position {
        case .long:
            var highest = entryPrice
            for i in startIdx..<data.count { highest = max(highest, data[i].high) }
            highest = max(highest, lp)
            let line = highest - config.trailATR * a
            return line < highest ? line : nil
        case .short:
            var lowest = entryPrice
            for i in startIdx..<data.count { lowest = min(lowest, data[i].low) }
            lowest = min(lowest, lp)
            let line = lowest + config.trailATR * a
            return line > lowest ? line : nil
        case .none:
            return nil
        }
    }

    // MARK: - 实时止盈提醒（移动止盈线触发，多空双向）
    /// 基于最近持仓以来的最高/最低价 + 2×ATR 移动止盈线：
    ///   多单：现价从持仓最高点回撤 ≥ trail×ATR → 止盈提醒
    ///   空单：现价从持仓最低点反弹 ≥ trail×ATR → 止盈提醒
    /// 返回 nil 表示未触发（或数据不足/无持仓）
    static func realtimeTakeProfit(
        _ data: [Kline],
        position: PositionDirection,
        entryPrice: Double,
        livePrice: Double,
        entryIndex: Int? = nil
    ) -> SignalMarker? {
        guard position != .none, entryPrice > 0 else { return nil }
        guard data.count >= 60, let last = data.last else { return nil }
        let pre = precompute(data)
        let a = pre.atr[data.count - 1]
        guard a > 0 else { return nil }

        let startIdx = max(60, entryIndex ?? 60)
        guard startIdx < data.count else { return nil }

        switch position {
        case .long:
            // 持仓以来最高价（含实时价）
            var highest = entryPrice
            for i in startIdx..<data.count { highest = max(highest, data[i].high) }
            highest = max(highest, livePrice)
            let trailLine = highest - config.trailATR * a
            if livePrice <= trailLine, trailLine < highest {
                return SignalMarker(
                    candleIndex: data.count - 1, type: .longTakeProfit, price: livePrice,
                    stopLoss: entryPrice, stopTarget: trailLine,
                    strength: 90, source: "实时止盈", timestamp: last.timestamp
                )
            }
        case .short:
            var lowest = entryPrice
            for i in startIdx..<data.count { lowest = min(lowest, data[i].low) }
            lowest = min(lowest, livePrice)
            let trailLine = lowest + config.trailATR * a
            if livePrice >= trailLine, trailLine > lowest {
                return SignalMarker(
                    candleIndex: data.count - 1, type: .shortTakeProfit, price: livePrice,
                    stopLoss: entryPrice, stopTarget: trailLine,
                    strength: 90, source: "实时止盈", timestamp: last.timestamp
                )
            }
        case .none:
            break
        }
        return nil
    }

    // MARK: - 当前持仓状态（引擎模拟到最后一根K线）
    /// 与 perCandleSignals 同一套开仓/平仓/反手规则，只回传最后一根K线时的持仓状态
    /// （供实时止盈提醒使用：多单回撤 2ATR / 空单反弹 2ATR → 弹“盈”）
    struct PositionState {
        let position: PositionDirection
        let entryPrice: Double
        let entryIndex: Int
        let highest: Double
        let lowest: Double
    }

    static func currentPositionState(_ data: [Kline]) -> PositionState {
        guard data.count >= 60 else {
            return PositionState(position: .none, entryPrice: 0, entryIndex: 0, highest: 0, lowest: 0)
        }
        let pre = precompute(data)
        let scores = makeScores(data)
        var position: PositionDirection = .none
        var entry: Double = 0
        var entryIndex = 0
        var highest: Double = 0
        var lowest: Double = 0

        for i in 60..<data.count {
            let candle = data[i]
            let px = candle.close
            let a = pre.atr[i] > 0 ? pre.atr[i] : 1.0
            let sc = scores[i]

            if position != .none {
                // 反手
                if position == .long && sc <= effectiveShortThreshold(pre, i) {
                    position = .short; entry = px; entryIndex = i; lowest = candle.low
                    continue
                }
                if position == .short && sc >= Double(config.longThreshold) {
                    position = .long; entry = px; entryIndex = i; highest = candle.high
                    continue
                }
                if position == .long {
                    highest = max(highest, candle.high)
                    var stop = entry - config.chandelierATR * a
                    if config.useBreakEven && (highest - entry) > 1.0 * a { stop = max(stop, entry) }
                    let line = max(stop, highest - config.trailATR * a)
                    if px <= line { position = .none }
                } else {
                    lowest = min(lowest, candle.low)
                    var stop = entry + config.chandelierATR * a
                    if config.useBreakEven && (entry - lowest) >= 1.0 * a { stop = min(stop, entry) }
                    let line = min(stop, lowest + config.trailATR * a)
                    if px >= line { position = .none }
                }
            } else {
                // ADX 过滤（仅开仓）
                if pre.adx[i] < config.adxMin { continue }
                if sc >= Double(config.longThreshold) {
                    position = .long; entry = px; entryIndex = i; highest = candle.high
                } else if sc <= effectiveShortThreshold(pre, i) {
                    position = .short; entry = px; entryIndex = i; lowest = candle.low
                }
            }
        }
        return PositionState(position: position, entryPrice: entry, entryIndex: entryIndex, highest: highest, lowest: lowest)
    }
}