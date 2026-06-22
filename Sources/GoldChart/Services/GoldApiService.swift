import Foundation

/// aurumrates.com 免费黄金/白银API（无需Key，100次/小时）
/// 文档: https://aurumrates.com/gold-price-api
class GoldApiService {
    static let shared = GoldApiService()
    private let session: URLSession
    private let decoder = JSONDecoder()
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }
    
    /// 获取K线数据
    func fetchKlines(product: ProductType, period: KlinePeriod, count: Int = 500) async throws -> [Kline] {
        let (range, interval) = mapPeriod(period)
        let symbol = product == .xau ? "GC=F" : "SI=F"
        
        let urlStr = "https://aurumrates.com/api/chart?symbol=\(symbol)&range=\(range)&interval=\(interval)"
        guard let url = URL(string: urlStr) else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = json["chart"] as? [String: Any],
              let result = (chart["result"] as? [[String: Any]])?.first,
              let timestamps = result["timestamp"] as? [TimeInterval],
              let indicators = result["indicators"] as? [String: Any],
              let quote = (indicators["quote"] as? [[String: Any]])?.first,
              let opens = quote["open"] as? [Double],
              let highs = quote["high"] as? [Double],
              let lows = quote["low"] as? [Double],
              let closes = quote["close"] as? [Double] else {
            throw APIError.noData
        }
        
        let volumes = quote["volume"] as? [Double] ?? Array(repeating: 0, count: opens.count)
        
        let count = min(timestamps.count, opens.count, highs.count, lows.count, closes.count, volumes.count)
        
        var klines: [Kline] = []
        for i in 0..<count {
            let ts = timestamps[i] * 1000  // 秒→毫秒
            klines.append(Kline(
                timestamp: ts,
                open: opens[i],
                high: highs[i],
                low: lows[i],
                close: closes[i],
                volume: volumes[i]
            ))
        }
        
        // 按时间正序排列
        klines.sort { $0.timestamp < $1.timestamp }
        
        if klines.isEmpty {
            throw APIError.noData
        }
        
        // 如果数据不够count，用最后的数据填充
        if klines.count < count {
            return klines
        }
        
        // 只返回需要的数量
        return klines.suffix(count).map { $0 }
    }
    
    /// 周期映射
    private func mapPeriod(_ period: KlinePeriod) -> (range: String, interval: String) {
        switch period {
        case .m1:  return ("1d", "1m")
        case .m5:  return ("5d", "5m")
        case .m15: return ("1mo", "15m")
        case .m30: return ("1mo", "1h")   // 无30m档，用1h近似
        case .h1:  return ("3mo", "1h")
        case .h4:  return ("6mo", "1d")   // 无4h档，用日线近似
        case .d1:  return ("1y", "1d")
        case .w1:  return ("5y", "1wk")
        }
    }
    
    enum APIError: LocalizedError {
        case invalidURL
        case httpError
        case noData
        case rateLimited
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "无效的URL"
            case .httpError: return "网络请求失败"
            case .noData: return "暂无数据"
            case .rateLimited: return "请求过于频繁（100次/小时限制）"
            }
        }
    }
}
