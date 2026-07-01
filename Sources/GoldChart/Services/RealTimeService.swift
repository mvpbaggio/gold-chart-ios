import Foundation
import Combine

/// 新浪实时行情服务（每秒轮询）
class RealTimeService: ObservableObject {
    static let shared = RealTimeService()
    
    @Published var quote: RealTimeQuote?
    @Published var isConnected = false
    
    private var timer: Timer?
    private let sinaCodes: [ProductType: String] = [
        .xau: "hf_GC",      // 纽约金
        .xag: "hf_SI",       // 纽约银
    ]
    
    private init() {}
    
    func startPolling(product: ProductType) {
        stopPolling()
        isConnected = false
        
        // 立即获取一次
        fetchQuote(product: product)
        
        // 每秒轮询
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.fetchQuote(product: product)
        }
    }
    
    func stopPolling() {
        timer?.invalidate()
        timer = nil
        isConnected = false
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
            guard let data = data, error == nil,
                  let text = String(data: data, encoding: .utf8) else { return }
            
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
