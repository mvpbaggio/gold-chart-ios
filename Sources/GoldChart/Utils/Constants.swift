import SwiftUI

// MARK: - 颜色主题
struct AppColors {
    static let background = Color(hex: "0D1117")
    static let cardBackground = Color(hex: "161B22")
    static let cardBorder = Color(hex: "30363D")
    static let gold = Color(hex: "F0B90B")
    static let red = Color(hex: "EF4444")       // 涨（中国红）
    static let green = Color(hex: "22C55E")     // 跌
    static let textPrimary = Color(hex: "E6EDF3")
    static let textSecondary = Color(hex: "8B949E")
    static let textTertiary = Color(hex: "484F58")
    static let accent = Color(hex: "F0B90B")
    static let tabActive = Color(hex: "F0B90B")
    static let tabInactive = Color(hex: "8B949E")
    static let indicatorMA = Color(hex: "F0B90B")
    static let indicatorEMA = Color(hex: "FF7B72")
    static let indicatorMACD = Color(hex: "79C0FF")
    static let indicatorRSI = Color(hex: "D2A8FF")
    static let indicatorVolume = Color(hex: "58A6FF")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - API 配置
struct API {
    // 黄金/白银数据：aurumrates.com（免费，无需Key）
    static let goldBase = "https://aurumrates.com/api/chart"
    
    // A股：新浪财经
    static let sinaSearch = "https://suggest3.sinajs.cn/suggest/type=11,12,13,14,15&key="
    static let sinaQuote = "https://hq.sinajs.cn/list="
    static let sinaHistory = "https://web.ifzq.gtimg.cn/appstock/app/day/query?"
}

// MARK: - 其他常量
struct Constants {
    static let appName = "金银Chart"
    static let version = "1.0.0"
    static let appGroup = "com.goldchart.app"
}

// MARK: - 模拟数据
struct MockData {
    static func generateKlines(count: Int = 200) -> [Kline] {
        var klines: [Kline] = []
        var price: Double = 2330.0
        let now = Date().timeIntervalSince1970 * 1000
        
        for i in 0..<count {
            let change = Double.random(in: -12...12)
            let open = price
            let close = price + change
            let high = max(open, close) + Double.random(in: 0...5)
            let low = min(open, close) - Double.random(in: 0...5)
            let volume = Double.random(in: 1000...50000)
            
            klines.append(Kline(
                timestamp: now - Double(count - i) * 3600000,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume
            ))
            
            price = close
        }
        
        return klines
    }
}
