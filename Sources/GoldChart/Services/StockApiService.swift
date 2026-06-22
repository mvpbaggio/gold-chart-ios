import Foundation

class StockApiService {
    static let shared = StockApiService()
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
    }
    
    /// 搜索A股
    func searchStocks(keyword: String) async throws -> [StockItem] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        guard let url = URL(string: "\(API.sinaSearch)\(encoded)") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                        forHTTPHeaderField: "User-Agent")
        request.setValue("www.baidu.com", forHTTPHeaderField: "Referer")
        
        let (data, _) = try await session.data(for: request)
        
        // 新浪返回GBK编码，尝试UTF-8后回退GB18030
        let text: String
        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
            text = utf8
        } else {
            let cfEnc = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
            text = NSString(data: data, encoding: nsEnc) as String? ?? ""
        }
        
        return parseSinaSuggest(text)
    }
    
    /// 获取个股日K线（最近90天）
    func fetchStockKlines(code: String) async throws -> [Kline] {
        let market = getMarket(code)
        let fullCode = "\(market)\(code)"
        let urlStr = "\(API.sinaHistory)_symbol=\(fullCode)"
        
        guard let url = URL(string: urlStr) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                        forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return MockData.generateKlines(count: 90)
        }
        
        return parseSinaHistory(json, code: fullCode)
    }
    
    // MARK: - Private
    
    private func getMarket(_ code: String) -> String {
        if code.hasPrefix("6") || code.hasPrefix("9") {
            return "sh"
        }
        return "sz"
    }
    
    private func parseSinaSuggest(_ text: String) -> [StockItem] {
        guard let dataStart = text.firstIndex(of: "\""),
              let dataEnd = text.lastIndex(of: "\""),
              dataStart < dataEnd else { return [] }
        
        let content = text[text.index(after: dataStart)..<dataEnd]
        let items = content.components(separatedBy: ";")
        
        return items.compactMap { item in
            let parts = item.components(separatedBy: ",")
            guard parts.count >= 3 else { return nil }
            return StockItem(
                code: parts[2],
                name: parts[0],
                market: parts[1],
                pinyin: parts.count > 3 ? parts[3] : ""
            )
        }
    }
    
    private func parseSinaHistory(_ json: [String: Any], code: String) -> [Kline] {
        guard let data = json[code] as? [String: Any],
              let day = data["day"] as? [[Any]] ?? data["data"] as? [[Any]] else {
            return MockData.generateKlines(count: 90)
        }
        
        return day.compactMap { item in
            guard item.count >= 6,
                  let dateStr = item[0] as? String,
                  let open = Double("\(item[1])"),
                  let high = Double("\(item[2])"),
                  let low = Double("\(item[3])"),
                  let close = Double("\(item[4])"),
                  let volume = Double("\(item[5])") else { return nil }
            
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            let ts = fmt.date(from: dateStr)?.timeIntervalSince1970 ?? 0
            
            return Kline(
                timestamp: ts * 1000,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume
            )
        }.reversed()
    }
    
    struct StockItem: Identifiable {
        let id = UUID()
        let code: String
        let name: String
        let market: String
        let pinyin: String
        
        var displayName: String {
            "\(name) (\(code))"
        }
        
        var marketDisplay: String {
            market == "sh" ? "沪" : "深"
        }
    }
    
    enum APIError: LocalizedError {
        case invalidURL
        case noData
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "无效的查询"
            case .noData: return "暂无数据"
            }
        }
    }
}
