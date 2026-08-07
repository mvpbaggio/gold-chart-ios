import SwiftUI

// MARK: - 颜色主题
struct AppColors {
    // 追风揽月浅色风格：柔和浅蓝背景 + 白色卡片
    static let background = Color(hex: "E8F1F9")
    static let cardBackground = Color(hex: "FFFFFF")
    static let cardBorder = Color(hex: "D0DCE8")
    static let gold = Color(hex: "E6A23C")
    static let red = Color(hex: "EF4444")       // 涨（中国红）
    static let green = Color(hex: "22C55E")     // 跌
    static let textPrimary = Color(hex: "1A2530")
    static let textSecondary = Color(hex: "5A6B7C")
    static let textTertiary = Color(hex: "9AA8B8")
    static let accent = Color(hex: "E6A23C")
    static let tabBarBackground = Color(hex: "B1D7FE")
    static let tabActive = Color(hex: "2563EB")
    static let tabInactive = Color(hex: "9AA8B8")
    static let indicatorMA = Color(hex: "E6A23C")
    static let indicatorEMA = Color(hex: "8B5CF6")
    static let indicatorMACD = Color(hex: "3B82F6")
    static let indicatorRSI = Color(hex: "EC4899")
    static let indicatorVolume = Color(hex: "60A5FA")
    static let indicatorSuperTrend = Color(hex: "00E5FF")  // 青色
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
    // 黄金/白银数据代理（可选，默认不走）
    // 在家里WiFi下可设置：http://192.168.0.114:28789/api
    // 在外面或设置空字符串 = 直接走 Yahoo + 模拟兜底
    static var proxyBase: String {
        UserDefaults.standard.string(forKey: "proxy_url") ?? ""
    }
    static func setProxyURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: "proxy_url")
    }
    
    // A股搜索：新浪财经
    static let sinaSearch = "https://suggest3.sinajs.cn/suggest/type=11,12,13,14,15&key="

    // 实时行情：腾讯财经（金银 + 内盘）
    static let tencentQuote = "https://qt.gtimg.cn/q="
    // A股日K：腾讯财经
    static let tencentKline = "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param="

    // 实时行情备用：新浪财经（内盘期货 nf_AU0/nf_AG0）
    static let sinaQuote = "https://hq.sinajs.cn/list="
    // 外盘日K（COMEX金银）：新浪全球期货
    static let sinaGlobalKline = "https://stock.finance.sina.com.cn/futures/api/openapi.php/GlobalFuturesService.getGlobalFuturesDailyKLine?symbol="
}

// MARK: - 其他常量
struct Constants {
    static let appName = "金银Chart"
    static let version = "1.0.0"
    static let appGroup = "com.goldchart.app"
}

// MARK: - 模拟数据
struct MockData {
    static func generateKlines(count: Int = 200, basePrice: Double = 2330.0) -> [Kline] {
        var klines: [Kline] = []
        var price: Double = basePrice
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
