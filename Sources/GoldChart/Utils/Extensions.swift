import Foundation
import UIKit

// MARK: - UIColor Hex
 extension UIColor {
    convenience init(hex: String) {
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
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

// MARK: - Double 格式化
extension Double {
    func formattedPrice(_ product: ProductType) -> String {
        let decimals: Int
        switch product {
        case .xau: decimals = 2   // 黄金精确到0.01
        case .xag: decimals = 3   // 白银精确到0.001
        }
        return String(format: "%.\(decimals)f", self)
    }
    
    func formattedVolume() -> String {
        if self >= 10000 {
            return String(format: "%.1fK", self / 1000)
        }
        return String(format: "%.0f", self)
    }
    
    func percentString() -> String {
        let prefix = self >= 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.2f", self))%"
    }
}

// MARK: - Date 格式化
extension Date {
    func toKlineTimeString(period: KlinePeriod) -> String {
        let fmt = DateFormatter()
        switch period {
        case .m1, .m5, .m15, .m30, .h1, .h4:
            fmt.dateFormat = "MM/dd HH:mm"
        case .d1:
            fmt.dateFormat = "MM/dd"
        case .w1:
            fmt.dateFormat = "yyyy/MM/dd"
        }
        fmt.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return fmt.string(from: self)
    }
}

// MARK: - Array 安全性
extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

// MARK: - UserDefaults 缓存
extension UserDefaults {
    func cacheKlines(_ klines: [Kline], forKey key: String) {
        if let data = try? JSONEncoder().encode(klines) {
            set(data, forKey: key)
        }
    }
    
    func cachedKlines(forKey key: String) -> [Kline]? {
        guard let data = object(forKey: key) as? Data,
              let klines = try? JSONDecoder().decode([Kline].self, from: data) else {
            return nil
        }
        return klines
    }
}
