import Foundation

// MARK: - 品种类型
enum ProductType: String, CaseIterable {
    case xau = "XAU/USD"    // 现货黄金
    case xag = "XAG/USD"    // 现货白银
    
    var symbol: String {
        switch self {
        case .xau: return "XAU"
        case .xag: return "XAG"
        }
    }
    
    var apiSymbol: String {
        switch self {
        case .xau: return "XAU"
        case .xag: return "XAG"
        }
    }
    
    var displayName: String {
        switch self {
        case .xau: return "现货黄金"
        case .xag: return "现货白银"
        }
    }
}

// MARK: - 周期
enum KlinePeriod: String, CaseIterable {
    case m1 = "1m"
    case m5 = "5m"
    case m15 = "15m"
    case m30 = "30m"
    case h1 = "1h"
    case h4 = "4h"
    case d1 = "1d"
    case w1 = "1w"
    
    var displayName: String {
        switch self {
        case .m1: return "1分"
        case .m5: return "5分"
        case .m15: return "15分"
        case .m30: return "30分"
        case .h1: return "1时"
        case .h4: return "4时"
        case .d1: return "日线"
        case .w1: return "周线"
        }
    }
    
    var apiParameter: String {
        return self.rawValue
    }
}

// MARK: - K线数据
struct Kline: Codable, Identifiable, Equatable {
    let id = UUID()
    let timestamp: TimeInterval
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    
    var date: Date {
        Date(timeIntervalSince1970: timestamp / 1000)
    }
    
    var isGreen: Bool {
        close >= open
    }
    
    var isRed: Bool {
        close < open
    }
    
    enum CodingKeys: String, CodingKey {
        case timestamp = "t"
        case open = "o"
        case high = "h"
        case low = "l"
        case close = "c"
        case volume = "v"
    }
    
    static func == (lhs: Kline, rhs: Kline) -> Bool {
        lhs.timestamp == rhs.timestamp
    }
}

// MARK: - API 响应
struct GoldApiResponse: Codable {
    let status: String
    let data: [String: [KlineData]]?
    
    struct KlineData: Codable {
        let time: String
        let open: String
        let high: String
        let low: String
        let close: String
        let volume: String?
        let turnover: String?
        
        var toKline: Kline? {
            guard let ts = parseTimestamp(time),
                  let o = Double(open),
                  let h = Double(high),
                  let l = Double(low),
                  let c = Double(close) else { return nil }
            let v = volume.flatMap(Double.init) ?? 0
            return Kline(timestamp: ts, open: o, high: h, low: l, close: c, volume: v)
        }
        
        private func parseTimestamp(_ timeStr: String) -> TimeInterval? {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            formatter.timeZone = TimeZone(identifier: "UTC")
            if let date = formatter.date(from: timeStr) {
                return date.timeIntervalSince1970 * 1000
            }
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: timeStr) {
                return date.timeIntervalSince1970 * 1000
            }
            return nil
        }
    }
}

// MARK: - 新浪A股响应
struct SinaStockResponse: Codable {
    let result: SinaResult?
    
    struct SinaResult: Codable {
        let data: [SinaStockItem]?
    }
    
    struct SinaStockItem: Codable {
        let symbol: String
        let name: String
        let chName: String?
        let code: String?
        let pinyin: String?
        
        var displayCode: String {
            code ?? symbol
        }
        
        var displayName: String {
            chName ?? name
        }
    }
}

// MARK: - 新浪K线响应
struct SinaKlineResponse {
    let klines: [Kline]
    
    init?(rawString: String) {
        // 格式: var hq_str_sh600519="名称,open,close,high,low,volume,amount,..."
        guard let dataStart = rawString.firstIndex(of: "\""),
              let dataEnd = rawString.lastIndex(of: "\""),
              dataStart < dataEnd else { return nil }
        
        let content = rawString[rawString.index(after: dataStart)..<dataEnd]
        let parts = content.components(separatedBy: ",")
        
        // 日K线从第40位开始是日K数据
        // 实际日K线数据在 parts[1...6] 是今天数据
        // 历史日K线需要调另一个接口
        guard parts.count >= 7,
              let open = Double(parts[1]),
              let close = Double(parts[2]),
              let high = Double(parts[3]),
              let low = Double(parts[4]) else { return nil }
        
        let volume = Double(parts[5]) ?? 0
        let now = Date().timeIntervalSince1970 * 1000
        
        self.klines = [Kline(timestamp: now, open: open, high: high, low: low, close: close, volume: volume)]
    }
}

// MARK: - 技术指标
struct IndicatorResult {
    let name: String
    let values: [Double]
    let colors: [String]?
}

struct MACDResult {
    let dif: [Double?]
    let dea: [Double?]
    let histogram: [Double?]
}

struct KDJResult {
    let k: [Double?]
    let d: [Double?]
    let j: [Double?]
}

struct BollingerResult {
    let upper: [Double?]
    let middle: [Double?]
    let lower: [Double?]
}

struct IchimokuResult {
    let tenkan: [Double?]
    let kijun: [Double?]
    let senkouA: [Double?]
    let senkouB: [Double?]
    let chikou: [Double?]
}

// MARK: - 信号
struct TradeSignal: Identifiable {
    let id = UUID()
    let type: SignalType
    let strength: Int       // 0-100
    let description: String
    let detail: String?
    
    enum SignalType: String {
        case buy = "买入"
        case sell = "卖出"
        case neutral = "中性"
        case warning = "警告"
        
        var color: String {
            switch self {
            case .buy: return "#EF4444"     // 中国红=涨
            case .sell: return "#22C55E"    // 绿=跌
            case .neutral: return "#9CA3AF"
            case .warning: return "#F59E0B"
            }
        }
    }
}

struct OverallAssessment {
    let score: Int          // 0-100, >60偏多, <40偏空
    let signals: [TradeSignal]
    let level: String       // 严重超卖 ~ 严重超买
    
    static func evaluate(signals: [TradeSignal]) -> OverallAssessment {
        var buyScore = 0
        var totalWeight = 0
        for signal in signals {
            let weight = abs(signal.strength - 50)
            totalWeight += weight
            if signal.type == .buy {
                buyScore += signal.strength * weight
            } else if signal.type == .sell {
                buyScore += (100 - signal.strength) * weight
            } else if signal.strength > 50 {
                buyScore += signal.strength * weight / 2
            }
        }
        let score = totalWeight > 0 ? buyScore / totalWeight : 50
        
        let level: String
        if score >= 80 { level = "严重超买 🚨" }
        else if score >= 65 { level = "偏多 📈" }
        else if score >= 55 { level = "微偏多 ↗️" }
        else if score >= 45 { level = "中性 ⚖️" }
        else if score >= 35 { level = "微偏空 ↘️" }
        else if score >= 20 { level = "偏空 📉" }
        else { level = "严重超卖 🚨" }
        
        return OverallAssessment(score: score, signals: signals, level: level)
    }
}
