import Foundation

// MARK: - 信号标记（每条K线位置）
struct SignalMarker: Identifiable {
    let id = UUID()
    let candleIndex: Int        // 第几根K线
    let type: SignalType
    let price: Double           // 信号价格
    let stopLoss: Double?       // 止损价格
    let stopTarget: Double?     // 止盈目标（止损反向等距）
    let strength: Int           // 强度 0-100
    let source: String          // 来源指标
    let timestamp: TimeInterval // 信号时间戳
    
    enum SignalType: String, Codable {
        case longOpen = "多头开仓"
        case shortOpen = "空头开仓"
        case longClose = "多头平仓"
        case shortClose = "空头平仓"
        
        var isEntry: Bool {
            self == .longOpen || self == .shortOpen
        }
        
        var isLong: Bool {
            self == .longOpen || self == .shortClose
        }
        
        var marker: String {
            switch self {
            case .longOpen: return "多"
            case .shortOpen: return "空"
            case .longClose: return "平多"
            case .shortClose: return "平空"
            }
        }
    }
}

// MARK: - 实时行情（新浪推送）
struct RealTimeQuote {
    let price: Double           // 当前价
    let open: Double            // 今开
    let high: Double            // 今日最高
    let low: Double             // 今日最低
    let bid: Double?            // 买一价
    let ask: Double?            // 卖一价
    let change: Double          // 涨跌额
    let changePercent: Double   // 涨跌幅 %
    let time: String            // 更新时间
    let date: String            // 日期
    
    var formattedPrice: String {
        String(format: "%.2f", price)
    }
    
    var formattedChange: String {
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", change))"
    }
    
    var formattedPercent: String {
        let sign = changePercent >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", changePercent))%"
    }
}

// MARK: - 信号状态（当前持仓方向）
enum PositionDirection: String {
    case none = "空仓"
    case long = "多头持仓"
    case short = "空头持仓"
}
