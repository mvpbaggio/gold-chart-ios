import Foundation

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
