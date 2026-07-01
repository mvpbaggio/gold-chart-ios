import Foundation

/// Yahoo Finance API 获取黄金/白银K线（免费，无需Key）
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
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        
        let urlStr = "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=\(range)&interval=\(interval)"
        guard let url = URL(string: urlStr) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("https://finance.yahoo.com", forHTTPHeaderField: "Referer")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.httpError
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 429 {
                throw APIError.rateLimited
            }
            throw APIError.httpError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = json["chart"] as? [String: Any] else {
            throw APIError.noData
        }
        
        // 检查API错误
        if let error = chart["error"] as? [String: Any], !error.isEmpty {
            throw APIError.noData
        }
        
        guard let result = (chart["result"] as? [[String: Any]])?.first,
              let timestamps = result["timestamp"] as? [TimeInterval],
              let indicators = result["indicators"] as? [String: Any],
              let quote = (indicators["quote"] as? [[String: Any]])?.first else {
            throw APIError.noData
        }
        
        // Yahoo在某些时段返回null，Swift的as? [Double]会整个失败
        // 改用NSArray逐元素同步提取 + timestamp对齐
        func buildKlines(ts: [TimeInterval], open: Any?, high: Any?, low: Any?, close: Any?, volume: Any?) -> [Kline] {
            guard let opensArr = open as? NSArray,
                  let highsArr = high as? NSArray,
                  let lowsArr = low as? NSArray,
                  let closesArr = close as? NSArray,
                  let volsArr = volume as? NSArray else { return [] }
            let count = min(ts.count, opensArr.count, highsArr.count, lowsArr.count, closesArr.count, volsArr.count)
            var klines: [Kline] = []
            for i in 0..<count {
                guard let o = opensArr[i] as? NSNumber, o.doubleValue > 0,
                      let h = highsArr[i] as? NSNumber, h.doubleValue > 0,
                      let l = lowsArr[i] as? NSNumber, l.doubleValue > 0,
                      let c = closesArr[i] as? NSNumber, c.doubleValue > 0 else { continue }
                let v = (volsArr[i] as? NSNumber)?.doubleValue ?? 0
                klines.append(Kline(
                    timestamp: ts[i] * 1000,
                    open: o.doubleValue,
                    high: h.doubleValue,
                    low: l.doubleValue,
                    close: c.doubleValue,
                    volume: v
                ))
            }
            return klines
        }
        
        let klines = buildKlines(ts: timestamps, open: quote["open"], high: quote["high"], low: quote["low"], close: quote["close"], volume: quote["volume"])
        if klines.isEmpty { throw APIError.noData }
        
        return klines
    }
    
    /// 周期映射
    private func mapPeriod(_ period: KlinePeriod) -> (range: String, interval: String) {
        switch period {
        case .m1:  return ("1d", "1m")
        case .m5:  return ("5d", "5m")
        case .m15: return ("1mo", "15m")
        case .m30: return ("1mo", "30m")
        case .h1:  return ("3mo", "60m")
        case .h4:  return ("6mo", "1d")   // Yahoo没有4h，用日线替代
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
            case .rateLimited: return "请求过于频繁，稍后再试"
            }
        }
    }
}
