import Foundation
import Combine

/// 腾讯财经实时行情服务（每5秒轮询）
/// 数据源：腾讯财经 qt.gtimg.cn（hf_GC 纽约金 / hf_SI 纽约银）
class RealTimeService: ObservableObject {
    static let shared = RealTimeService()
    
    @Published var quote: RealTimeQuote?
    @Published var isConnected = false
    @Published var exchangeRate: Double = 7.25   // USDCNY，初始默认值，启动后自动刷新为实时汇率
    
    private var timer: Timer?
    private var fxTimer: Timer?
    private let tencentCodes: [ProductType: String] = [
        .xau: "hf_GC",     // 纽约黄金（COMEX，与日K数据源 GC 一致）
        .xag: "hf_SI",     // 纽约白银（COMEX，与日K数据源 SI 一致）
    ]
    
    private init() {}
    
    func startPolling(product: ProductType) {
        stopPolling()
        isConnected = false
        
        // 立即获取一次行情
        fetchQuote(product: product)
        // 立即获取一次汇率
        fetchExchangeRate()
        
        // 每5秒轮询行情（原1秒，改为5秒省流量防限流）
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
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
        if let url = URL(string: "https://hq.sinajs.cn/list=fx_susdcny") {
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
        // 格式: var hq_str_fx_susdcny="时间,买价,卖价,昨收,..."
        // 实测: "11:27:18,6.7471000000,6.7489000000,..." → parts[1] = 买价 6.7471
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
        guard let code = tencentCodes[product] else { return }
        
        let urlStr = "https://qt.gtimg.cn/q=\(code)"
        guard let url = URL(string: urlStr) else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                        forHTTPHeaderField: "User-Agent")
        request.setValue("https://gu.qq.com", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 3
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data = data, error == nil else { return }
            
            // 腾讯返回 GBK 编码；报价字段全是 ASCII，中文字段（名称）用 UTF-8 替换字符即可
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                self?.parseResponse(text, product: product)
            }
        }.resume()
    }
    
    private func parseResponse(_ text: String, product: ProductType) {
        // 腾讯格式: v_hf_GC="4315.89,0.38,4315.20,4315.50,4320.80,4288.00,11:29:03,4299.60,4298.30,0,1,1,2026-08-07,纽约黄金"
        // [0]现价 [1]涨跌额 [2]今开 [3]昨收 [4]最高 [5]最低 [6]时间 [7]买一 [8]卖一 [12]日期 [13]名称
        guard let dataStart = text.firstIndex(of: "\""),
              let dataEnd = text.lastIndex(of: "\""),
              dataStart < dataEnd else { return }
        
        let content = String(text[text.index(after: dataStart)..<dataEnd])
        let parts = content.components(separatedBy: ",")
        
        guard parts.count >= 13,
              let price = Double(parts[0]),
              let change = Double(parts[1]),
              let open = Double(parts[2]),
              let high = Double(parts[4]),
              let low = Double(parts[5]) else { return }
        
        let time = parts[6]
        let date = parts[12]
        let bid = Double(parts[7])
        let ask = Double(parts[8])
        // 昨收 = 现价 - 涨跌额；涨跌幅按昨收计算
        let prevClose = price - change
        let changePercent = prevClose > 0 ? (change / prevClose) * 100 : 0
        
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
