import Foundation
import Combine

/// 新浪实时行情服务（每秒轮询）
class RealTimeService: ObservableObject {
    static let shared = RealTimeService()
    
    @Published var quote: RealTimeQuote?
    @Published var isConnected = false
    @Published var exchangeRate: Double = 7.25   // USDCNY，默认7.25
    
    private var timer: Timer?
    private var fxTimer: Timer?
    private let sinaCodes: [ProductType: String] = [
        .xau: "hf_XAU",     // 伦敦金（现货，与口袋贵金属一致）
        .xag: "hf_XAG",     // 伦敦银（现货）
    ]
    
    private init() {}
    
    func startPolling(product: ProductType) {
        stopPolling()
        isConnected = false
        
        // 立即获取一次行情
        fetchQuote(product: product)
        // 立即获取一次汇率
        fetchExchangeRate()
        
        // 每秒轮询行情
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.fetchQuote(product: product)
        }
        
        // 每30秒刷新汇率
        fxTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.fetchExchangeRate()
        }
    }
    
    func stopPolling() {
        timer?.invalidate()
        timer = nil
        fxTimer?.invalidate()
        fxTimer = nil
        isConnected = false
    }
    
    /// 获取USDCNY汇率
    func fetchExchangeRate() {
        // 方式1：新浪财经 fx_susdcny
        if let url = URL(string: "http://hq.sinajs.cn/list=fx_susdcny") {
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                        forHTTPHeaderField: "User-Agent")
            req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
            req.timeoutInterval = 5
            
            URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
                guard let data = data, error == nil,
                      let text = String(data: data, encoding: .utf8) else {
                    // 方式2：备用 exchangerate API
                    self?.fetchExchangeRateFallback()
                    return
                }
                self?.parseExchangeRate(text)
            }.resume()
        }
    }
    
    private func fetchExchangeRateFallback() {
        guard let url = URL(string: "https://api.exchangerate-api.com/v4/latest/USD") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rates = json["rates"] as? [String: Double],
                  let cny = rates["CNY"] else { return }
            DispatchQueue.main.async {
                self?.exchangeRate = cny
            }
        }.resume()
    }
    
    private func parseExchangeRate(_ text: String) {
        // 格式: var hq_str_fx_susdcny="6.8773,6.8773,6.8810,6.8760,6.8760,6.8810,2024/01/15,10:30:00,..."
        guard let start = text.firstIndex(of: "\""),
              let end = text.lastIndex(of: "\""),
              start < end else { return }
        let content = String(text[text.index(after: start)..<end])
        let parts = content.components(separatedBy: ",")
        guard parts.count >= 2, let rate = Double(parts[1]) else { return }
        DispatchQueue.main.async {
            self.exchangeRate = rate
        }
    }
    
    private func fetchQuote(product: ProductType) {
        guard let code = sinaCodes[product] else { return }
        
        let urlStr = "http://hq.sinajs.cn/list=\(code)"
        guard let url = URL(string: urlStr) else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                        forHTTPHeaderField: "User-Agent")
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 3
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data = data, error == nil else { return }
            
            // Sina 中文字段(最后)是 GBK 编码，用 .utf8 会返回 nil
            // String(decoding:as:) 不抛异常，非法字节用 � 替换
            // 反正报价字段0~12全是ASCII，中文字段不用，完全不受影响
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                self?.parseResponse(text, product: product)
            }
        }.resume()
    }
    
    private func parseResponse(_ text: String, product: ProductType) {
        // 格式: var hq_str_hf_GC="price,,open,?,high,low,time,bid,ask,..."
        guard let dataStart = text.firstIndex(of: "\""),
              let dataEnd = text.lastIndex(of: "\""),
              dataStart < dataEnd else { return }
        
        let content = String(text[text.index(after: dataStart)..<dataEnd])
        let parts = content.components(separatedBy: ",")
        
        guard parts.count >= 9,
              let price = Double(parts[0]),
              let open = Double(parts[2]),
              let high = Double(parts[4]),
              let low = Double(parts[5]) else { return }
        
        let time = parts[6]
        let date = parts.count > 12 ? parts[12] : ""
        let bid = Double(parts[7])
        let ask = Double(parts[8])
        let change = price - open
        let changePercent = open > 0 ? (change / open) * 100 : 0
        
        let quote = RealTimeQuote(
            price: price,
            open: open,
            high: high,
            low: low,
            bid: bid,
            ask: ask,
            change: change,
            changePercent: changePercent,
            time: time,
            date: date
        )
        
        self.quote = quote
        self.isConnected = true
    }
}
