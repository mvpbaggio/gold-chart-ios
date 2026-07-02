import Foundation

/// 黄金/白银K线数据服务
/// 数据源优先级：我们的代理服务器 → Yahoo Finance → Mock数据
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
    
    /// 获取K线数据（自动回退）
    func fetchKlines(product: ProductType, period: KlinePeriod, count: Int = 500) async throws -> [Kline] {
        // 1. 尝试代理服务器
        if let proxyResult = try? await fetchFromProxy(product: product, period: period, count: count) {
            return proxyResult
        }
        
        // 2. Yahoo直连（带重试和域轮换）
        if let yahooResult = try? await fetchFromYahoo(product: product, period: period) {
            return yahooResult
        }
        
        // 3. 模拟数据兜底
        let basePrice = product == .xau ? 4100.0 : 29.5
        return MockData.generateKlines(count: count, basePrice: basePrice)
    }
    
    // MARK: - 代理服务器
    
    private func fetchFromProxy(product: ProductType, period: KlinePeriod, count: Int) async throws -> [Kline] {
        let symbol = product == .xau ? "XAUUSD" : "XAGUSD"
        let interval = mapProxyInterval(period)
        
        let urlStr = "\(API.proxyBase)/gold/kline?symbol=\(symbol)&interval=\(interval)&limit=\(count)"
        guard let url = URL(string: urlStr) else { throw ProxyError.invalidURL }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("GoldChart-iOS/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw ProxyError.httpError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["code"] as? Int == 0,
              let items = json["data"] as? [[String: Any]] else {
            throw ProxyError.noData
        }
        
        let klines = items.compactMap { item -> Kline? in
            guard let ts = item["time"] as? TimeInterval,
                  let open = item["open"] as? Double, open > 0,
                  let high = item["high"] as? Double, high > 0,
                  let low = item["low"] as? Double, low > 0,
                  let close = item["close"] as? Double, close > 0 else { return nil }
            let volume = (item["volume"] as? Double) ?? 0
            return Kline(timestamp: ts * 1000, open: open, high: high, low: low, close: close, volume: volume)
        }
        
        if klines.isEmpty { throw ProxyError.noData }
        return klines
    }
    
    private func mapProxyInterval(_ period: KlinePeriod) -> String {
        switch period {
        case .m1:  return "1m"
        case .m5:  return "5m"
        case .m15: return "15m"
        case .m30: return "30m"
        case .h1:  return "1h"
        case .h4:  return "4h"
        case .d1:  return "1d"
        case .w1:  return "1w"
        }
    }
    
    // MARK: - Yahoo Finance（带域轮换和重试）
    
    private func fetchFromYahoo(product: ProductType, period: KlinePeriod) async throws -> [Kline] {
        let (range, interval) = mapPeriod(period)
        let symbol = product == .xau ? "GC=F" : "SI=F"
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        
        // Yahoo域列表（轮换避免限流）
        let yahooHosts = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
        let userAgents = [
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        ]
        
        var lastError: Error?
        
        // 最多重试3次
        for attempt in 0..<3 {
            let host = yahooHosts[attempt % yahooHosts.count]
            let ua = userAgents[attempt % userAgents.count]
            
            let urlStr = "https://\(host)/v8/finance/chart/\(encoded)?range=\(range)&interval=\(interval)"
            guard let url = URL(string: urlStr) else {
                lastError = APIError.invalidURL
                continue
            }
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue(ua, forHTTPHeaderField: "User-Agent")
            request.setValue("https://finance.yahoo.com", forHTTPHeaderField: "Referer")
            
            // 每次请求间隔，避免限流
            if attempt > 0 {
                try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
            }
            
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = APIError.httpError
                    continue
                }
                
                if httpResponse.statusCode == 429 {
                    // 限流，等更久再重试
                    lastError = APIError.rateLimited
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                    continue
                }
                
                guard httpResponse.statusCode == 200 else {
                    lastError = APIError.httpError
                    continue
                }
                
                let klines = try parseYahooResponse(data)
                if !klines.isEmpty {
                    return klines
                }
                lastError = APIError.noData
            } catch {
                lastError = error
                continue
            }
        }
        
        throw lastError ?? APIError.noData
    }
    
    private func parseYahooResponse(_ data: Data) throws -> [Kline] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = json["chart"] as? [String: Any] else {
            throw APIError.noData
        }
        
        if let error = chart["error"] as? [String: Any], !error.isEmpty {
            throw APIError.noData
        }
        
        guard let result = (chart["result"] as? [[String: Any]])?.first,
              let timestamps = result["timestamp"] as? [TimeInterval],
              let indicators = result["indicators"] as? [String: Any],
              let quote = (indicators["quote"] as? [[String: Any]])?.first else {
            throw APIError.noData
        }
        
        guard let opensArr = quote["open"] as? NSArray,
              let highsArr = quote["high"] as? NSArray,
              let lowsArr = quote["low"] as? NSArray,
              let closesArr = quote["close"] as? NSArray,
              let volsArr = quote["volume"] as? NSArray else {
            throw APIError.noData
        }
        
        let count = min(timestamps.count, opensArr.count, highsArr.count, lowsArr.count, closesArr.count, volsArr.count)
        var klines: [Kline] = []
        for i in 0..<count {
            guard let o = opensArr[i] as? NSNumber, o.doubleValue > 0,
                  let h = highsArr[i] as? NSNumber, h.doubleValue > 0,
                  let l = lowsArr[i] as? NSNumber, l.doubleValue > 0,
                  let c = closesArr[i] as? NSNumber, c.doubleValue > 0 else { continue }
            let v = (volsArr[i] as? NSNumber)?.doubleValue ?? 0
            klines.append(Kline(
                timestamp: timestamps[i] * 1000,
                open: o.doubleValue,
                high: h.doubleValue,
                low: l.doubleValue,
                close: c.doubleValue,
                volume: v
            ))
        }
        
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
        case .h4:  return ("6mo", "1d")
        case .d1:  return ("1y", "1d")
        case .w1:  return ("5y", "1wk")
        }
    }
    
    enum ProxyError: LocalizedError {
        case invalidURL
        case httpError
        case noData
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "无效的代理URL"
            case .httpError: return "代理服务器连接失败"
            case .noData: return "代理暂无数据"
            }
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
