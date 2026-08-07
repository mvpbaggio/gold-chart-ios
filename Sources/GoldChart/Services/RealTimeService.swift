import Foundation
import Combine

/// 实时行情服务（每5秒轮询）
/// 数据源：东方财富现货 122.XAU/122.XAG（主）→ 新浪现货 hf_XAU/hf_XAG（备，同标的，避免期货/现货跳变）
class RealTimeService: ObservableObject {
    static let shared = RealTimeService()
    
    @Published var quote: RealTimeQuote?
    @Published var isConnected = false
    @Published var exchangeRate: Double = 7.25   // USDCNY，初始默认值，启动后自动刷新为实时汇率
    
    private var timer: Timer?
    private var fxTimer: Timer?
    /// 东财现货 secid（市场122=FORPM，现货伦敦金/银）
    private let emSecids: [ProductType: String] = [
        .xau: "122.XAU",
        .xag: "122.XAG",
    ]
    /// 东财行情主机（轮换，限流自动切换）
    private let emQuoteHosts = ["push2.eastmoney.com", "push2delay.eastmoney.com"]
    private var hostIdx = 0
    /// 东财f59缩放因子缓存（每品种不同，默认100）
    private var scaleCache: [ProductType: Double] = [:]
    /// 新浪现货代码（伦敦金/银，与东财同标的——备用源必须同标的，否则价格跳变）
    private let sinaCodes: [ProductType: String] = [
        .xau: "hf_XAU",     // 伦敦金（现货黄金）
        .xag: "hf_XAG",     // 伦敦银（现货白银）
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
        fetchFromEastMoney(product: product)
    }
    
    // MARK: - 东方财富实时（主源）
    
    private func fetchFromEastMoney(product: ProductType) {
        guard let secid = emSecids[product] else { return }
        
        let host = emQuoteHosts[hostIdx % emQuoteHosts.count]
        hostIdx += 1
        let fields = "f43,f44,f45,f46,f57,f58,f59,f60,f170"
        let urlStr = "https://\(host)/api/qt/stock/get?secid=\(secid)&fields=\(fields)"
        guard let url = URL(string: urlStr) else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                        forHTTPHeaderField: "User-Agent")
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 3
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil,
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                // 东财失败 → 新浪现货备用（同标的，防跳变）
                self?.fetchFromSina(product: product)
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let d = json["data"] as? [String: Any],
                  let priceRaw = d["f43"] as? NSNumber else {
                self.fetchFromSina(product: product)
                return
            }
            
            // f59=小数位数，缩放因子=10^f59（现货通常2位小数）
            let scale: Double
            if let cached = self.scaleCache[product] {
                scale = cached
            } else if let f59 = d["f59"] as? NSNumber {
                scale = pow(10, f59.doubleValue)
                self.scaleCache[product] = scale
            } else {
                scale = 100
            }
            
            let price = priceRaw.doubleValue / scale
            let open = (d["f46"] as? NSNumber)?.doubleValue ?? 0
            let high = (d["f44"] as? NSNumber)?.doubleValue ?? 0
            let low = (d["f45"] as? NSNumber)?.doubleValue ?? 0
            let prevClose = (d["f60"] as? NSNumber)?.doubleValue ?? 0
            let change = price - prevClose
            let changePercent = prevClose > 0 ? (change / prevClose) * 100 : 0
            
            let quote = RealTimeQuote(
                price: price,
                open: open / scale,
                high: high / scale,
                low: low / scale,
                bid: nil,
                ask: nil,
                change: change,
                changePercent: changePercent,
                time: "",
                date: ""
            )
            
            DispatchQueue.main.async {
                self.quote = quote
                self.isConnected = true
            }
        }.resume()
    }
    
    // MARK: - 新浪现货实时（备用，同标的防跳变）
    
    private func fetchFromSina(product: ProductType) {
        guard let code = sinaCodes[product] else { return }
        
        let urlStr = "https://hq.sinajs.cn/list=\(code)"
        guard let url = URL(string: urlStr) else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                        forHTTPHeaderField: "User-Agent")
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 3
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data = data, error == nil else { return }
            
            // 新浪中文字段（名称）是 GBK 编码，用 UTF-8 替换即可；报价字段0~12全是 ASCII 不受影响
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                self?.parseSinaResponse(text, product: product)
            }
        }.resume()
    }
    
    private func parseSinaResponse(_ text: String, product: ProductType) {
        // 新浪现货格式: var hq_str_hf_XAU="现价,?,开盘,?,最高,最低,时间,买价,卖价,...,日期,名称"
        // [0]现价 [2]今开 [4]最高 [5]最低 [6]时间 [7]买一 [8]卖一 [12]日期 [13]名称
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
        // 新浪无昨收字段：用今开作基准算涨跌
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
