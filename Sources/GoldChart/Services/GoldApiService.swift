import Foundation

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
    
    /// 获取黄金或白银K线数据
    func fetchKlines(product: ProductType, period: KlinePeriod, count: Int = 500) async throws -> [Kline] {
        // 如果有API Key则用真实数据
        if !API.goldApiKey.isEmpty {
            return try await fetchFromGoldApi(product: product, period: period, count: count)
        }
        
        // 模拟数据降级
        return MockData.generateKlines(count: count)
    }
    
    private func fetchFromGoldApi(product: ProductType, period: KlinePeriod, count: Int) async throws -> [Kline] {
        var components = URLComponents(string: "\(API.goldBase)/api/data/\(product.apiSymbol)/\(period.apiParameter)")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: API.goldApiKey),
            URLQueryItem(name: "limit", value: "\(count)")
        ]
        
        guard let url = components.url else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError
        }
        
        let apiResponse = try decoder.decode(GoldApiResponse.self, from: data)
        
        guard apiResponse.status == "ok",
              let dataDict = apiResponse.data,
              let klineData = dataDict[product.apiSymbol] else {
            throw APIError.noData
        }
        
        return klineData.compactMap { $0.toKline }
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
            case .rateLimited: return "请求过于频繁"
            }
        }
    }
}
