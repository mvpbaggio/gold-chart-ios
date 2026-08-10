import Foundation

/// 黄金/白银K线数据服务
/// 数据源优先级：东方财富现货(122.XAU/122.XAG，全周期) → 代理服务器(可选) → 新浪现货(日K/1分钟K，全周期聚合) → Mock数据
class GoldApiService {
    static let shared = GoldApiService()
    private let session: URLSession
    private let decoder = JSONDecoder()
    
    /// 东财K线主机（限流自动切换）
    private let emKlineHosts = [
        "push2his.eastmoney.com",
        "92.push2his.eastmoney.com",
        "1.push2his.eastmoney.com",
    ]
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }
    
    /// 获取K线数据（自动回退）
    /// 优先级（build77 超哥拍板）：
    ///   分钟K(m1..h4)：Yahoo 期货优先（深度 1d-6mo，碾压东财现货分钟K 132根）→ 东财现货 → 代理 → 新浪1分聚合 → Mock
    ///   日K/周K：东财现货（5000根深）→ 代理 → 新浪日K/周K → Mock
    func fetchKlines(product: ProductType, period: KlinePeriod, count: Int = 500) async throws -> [Kline] {
        // 分钟K：Yahoo 期货主源（基差校准到现货价；H4由60m聚合）
        if period != .d1, period != .w1 {
            if let yahooResult = try? await fetchFromYahoo(product: product, period: period) {
                let calibrated = (try? await calibrateToSpot(yahooResult, product: product)) ?? yahooResult
                if period == .h4 {
                    return aggregateToH4(calibrated)
                }
                return calibrated
            }
        }

        // 0. 东方财富现货（日K/周K 主源；分钟K 兜底）
        if let emResult = try? await fetchFromEastMoney(product: product, period: period, count: count) {
            return emResult
        }
        
        // 1. 尝试代理服务器（只有配置了URL才走）
        if !API.proxyBase.isEmpty, let proxyResult = try? await fetchFromProxy(product: product, period: period, count: count) {
            return proxyResult
        }
        
        // 2. 新浪财经现货：日K/周K（深度 5185 根，价格准确）
        if period == .d1 || period == .w1 {
            if let sinaResult = try? await fetchFromSina(product: product, period: period, count: count) {
                return sinaResult
            }
        } else {
            // 3. 新浪现货1分钟聚合（浅约1天，价格准确，Yahoo/东财不通时兜底）
            if let sinaResult = try? await fetchFromSina(product: product, period: period, count: count) {
                return sinaResult
            }
        }
        
        // 4. 模拟数据兜底（所有真实源失败时，保底显示）
        let basePrice = product == .xau ? 4100.0 : 29.5
        return MockData.generateKlines(count: count, basePrice: basePrice)
    }
    
    // MARK: - 东方财富现货K线（主源）
    
    private func fetchFromEastMoney(product: ProductType, period: KlinePeriod, count: Int) async throws -> [Kline] {
        if period == .h4 {
            // 东财无4小时K：取60分钟K后按时间窗口聚合
            let hourly = try await fetchFromEastMoneyRaw(product: product, klt: "60", count: count * 4)
            return aggregateToH4(hourly)
        }
        return try await fetchFromEastMoneyRaw(product: product, klt: mapEastMoneyPeriod(period), count: count)
    }
    
    private func fetchFromEastMoneyRaw(product: ProductType, klt: String, count: Int) async throws -> [Kline] {
        let secid = product == .xau ? "122.XAU" : "122.XAG"
        var lastError: Error?
        
        for host in emKlineHosts {
            let urlStr = "https://\(host)/api/qt/stock/kline/get?secid=\(secid)"
                + "&fields1=f1,f2,f3&fields2=f51,f52,f53,f54,f55,f56"
                + "&klt=\(klt)&fqt=1&end=20500101&lmt=\(count)"
            guard let url = URL(string: urlStr) else {
                lastError = APIError.invalidURL
                continue
            }
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                            forHTTPHeaderField: "User-Agent")
            request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")
            
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                    lastError = APIError.httpError
                    continue
                }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let d = json["data"] as? [String: Any],
                      let klinesRaw = d["klines"] as? [String] else {
                    lastError = APIError.noData
                    continue
                }
                let klines = klinesRaw.compactMap { Self.parseEastMoneyKline($0) }
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
    
    /// 东财K线行格式: "日期[,时间],开,收,高,低,量[,额]"
    private static func parseEastMoneyKline(_ line: String) -> Kline? {
        let parts = line.components(separatedBy: ",")
        guard parts.count >= 6,
              let open = Double(parts[1]), open > 0,
              let close = Double(parts[2]), close > 0,
              let high = Double(parts[3]), high > 0,
              let low = Double(parts[4]), low > 0 else { return nil }
        let volume = Double(parts[5]) ?? 0
        guard let ts = Self.eastMoneyTimeToMillis(parts[0]) else { return nil }
        return Kline(timestamp: ts, open: open, high: high, low: low, close: close, volume: volume)
    }
    
    /// 东财时间字符串（北京时间）→ 毫秒时间戳；日K"2026-08-07"，分钟K"2026-08-07 14:30"
    private static func eastMoneyTimeToMillis(_ timeStr: String) -> TimeInterval? {
        let formatter = eastMoneyFormatter(timeStr.contains(":"))
        guard let date = formatter.date(from: timeStr) else { return nil }
        return date.timeIntervalSince1970 * 1000
    }
    
    private static var dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    private static var minuteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
    
    private static func eastMoneyFormatter(_ hasTime: Bool) -> DateFormatter {
        hasTime ? minuteFormatter : dayFormatter
    }
    
    /// 东财周期代码: 1/5/15/30/60分钟, 101日K, 102周K
    private func mapEastMoneyPeriod(_ period: KlinePeriod) -> String {
        switch period {
        case .m1:  return "1"
        case .m5:  return "5"
        case .m15: return "15"
        case .m30: return "30"
        case .h1:  return "60"
        case .h4:  return "60"   // 由fetchFromEastMoney聚合，不会走到这
        case .d1:  return "101"
        case .w1:  return "102"
        }
    }
    
    // MARK: - 新浪财经（日K/周K）
    
    private func fetchFromSina(product: ProductType, period: KlinePeriod, count: Int) async throws -> [Kline] {
        switch period {
        case .d1:
            let klines = try await fetchSinaDaily(product: product)
            return Array(klines.suffix(count))
        case .w1:
            // 周K = 日K按自然周聚合（新浪周K接口已失效）
            let daily = try await fetchSinaDaily(product: product)
            return Array(aggregateWeekly(daily).suffix(count))
        case .m1, .m5, .m15, .m30, .h1, .h4:
            // 分钟K = 新浪1分钟现货K聚合（接口返回近1个交易日约1374根）
            let minute = try await fetchSinaMinute(product: product)
            switch period {
            case .m1:   return Array(minute.suffix(count))
            case .m5:   return Array(aggregateKlines(minute, minutes: 5).suffix(count))
            case .m15:  return Array(aggregateKlines(minute, minutes: 15).suffix(count))
            case .m30:  return Array(aggregateKlines(minute, minutes: 30).suffix(count))
            case .h1:   return Array(aggregateKlines(minute, minutes: 60).suffix(count))
            case .h4:   return Array(aggregateKlines(minute, minutes: 240).suffix(count))
            default:    throw APIError.noData
            }
        }
    }
    
    /// 新浪现货日K（全量返回，实测 5185 根覆盖 2006 至今）
    private func fetchSinaDaily(product: ProductType) async throws -> [Kline] {
        let symbol = product.sinaSymbols[0]
        let urlStr = "https://stock.finance.sina.com.cn/futures/api/openapi.php/GlobalFuturesService.getGlobalFuturesDailyKLine?symbol=\(symbol)&datalen=500"
        guard let url = URL(string: urlStr) else { throw APIError.noData }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                        forHTTPHeaderField: "User-Agent")
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw APIError.noData
        }
        let klines = try parseSinaGlobalKline(data)
        return klines
    }
    
    /// 新浪现货1分钟K（JSONP 格式，近1个交易日约1374根）
    private func fetchSinaMinute(product: ProductType) async throws -> [Kline] {
        let symbol = product.sinaSymbols[0]
        let urlStr = "https://stock.finance.sina.com.cn/futures/api/jsonp.php/var%20_=/GlobalFuturesService.getGlobalFuturesMinLine?symbol=\(symbol)&type=1"
        guard let url = URL(string: urlStr) else { throw APIError.noData }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                        forHTTPHeaderField: "User-Agent")
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
              let body = String(data: data, encoding: .utf8) else {
            throw APIError.noData
        }
        // 剥 JSONP 壳：var _=({...});
        guard let openParen = body.range(of: "("),
              let closeParen = body.range(of: ")", options: .backwards),
              openParen.upperBound < closeParen.lowerBound else {
            throw APIError.noData
        }
        let jsonStr = String(body[openParen.upperBound..<closeParen.lowerBound])
        guard let json = try JSONSerialization.jsonObject(with: Data(jsonStr.utf8)) as? [String: Any],
              let rows = json["minLine_1d"] as? [[Any]] else {
            throw APIError.noData
        }
        
        // 行格式: ["2026-08-07","4240.550","LIFFE","","06:00","4240.120","0","0","4239.520","2026-08-07 06:00:00"]
        // 后续行: ["06:01","4240.180","0","0","4239.753","2026-08-07 06:01:00"]
        // [1]=当前价(用做close)，[0]或[4]=时间，最后元素=完整时间戳
        var klines: [Kline] = []
        var lastClose: Double?
        for row in rows {
            guard row.count >= 6,
                  let close = Double(row[1] as? String ?? ""), close > 0 else { continue }
            var ts: TimeInterval = 0
            if let fullTime = row.last as? String, fullTime.contains("-") {
                ts = Self.sinaMinuteFormatter.date(from: fullTime)?.timeIntervalSince1970 ?? 0
            }
            guard ts > 0 else { continue }
            let open = lastClose ?? close
            let high = max(open, close)
            let low = min(open, close)
            klines.append(Kline(timestamp: ts * 1000, open: open, high: high, low: low, close: close, volume: 0))
            lastClose = close
        }
        if klines.isEmpty { throw APIError.noData }
        return klines
    }
    
    private static let sinaMinuteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
    
    /// 分钟K聚合：1分钟 → N分钟（滚动时间窗口）
    private func aggregateKlines(_ klines: [Kline], minutes: Int) -> [Kline] {
        guard minutes > 1, klines.count > 1 else { return klines }
        let windowMs = Double(minutes) * 60 * 1000
        var result: [Kline] = []
        var current: (open: Double, high: Double, low: Double, close: Double, volume: Double, ts: TimeInterval)?
        for k in klines {
            if var cur = current {
                if k.timestamp - cur.ts < windowMs {
                    cur.high = max(cur.high, k.high)
                    cur.low = min(cur.low, k.low)
                    cur.close = k.close
                    cur.volume = cur.volume + k.volume
                    current = cur
                } else {
                    result.append(Kline(timestamp: cur.ts, open: cur.open, high: cur.high, low: cur.low, close: cur.close, volume: cur.volume))
                    current = (k.open, k.high, k.low, k.close, k.volume, k.timestamp)
                }
            } else {
                current = (k.open, k.high, k.low, k.close, k.volume, k.timestamp)
            }
        }
        if let cur = current {
            result.append(Kline(timestamp: cur.ts, open: cur.open, high: cur.high, low: cur.low, close: cur.close, volume: cur.volume))
        }
        return result
    }
    
    /// 日K聚合周K（按自然周，ISO 周号分组）
    private func aggregateWeekly(_ daily: [Kline]) -> [Kline] {
        guard daily.count > 1 else { return daily }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        var result: [Kline] = []
        var current: (open: Double, high: Double, low: Double, close: Double, volume: Double, ts: TimeInterval, weekKey: Int)?
        for k in daily {
            let date = Date(timeIntervalSince1970: k.timestamp / 1000)
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            let weekKey = (comps.yearForWeekOfYear ?? 0) * 100 + (comps.weekOfYear ?? 0)
            if var cur = current {
                if weekKey == cur.weekKey {
                    cur.high = max(cur.high, k.high)
                    cur.low = min(cur.low, k.low)
                    cur.close = k.close
                    cur.volume = cur.volume + k.volume
                    current = cur
                } else {
                    result.append(Kline(timestamp: cur.ts, open: cur.open, high: cur.high, low: cur.low, close: cur.close, volume: cur.volume))
                    current = (k.open, k.high, k.low, k.close, k.volume, k.timestamp, weekKey)
                }
            } else {
                current = (k.open, k.high, k.low, k.close, k.volume, k.timestamp, weekKey)
            }
        }
        if let cur = current {
            result.append(Kline(timestamp: cur.ts, open: cur.open, high: cur.high, low: cur.low, close: cur.close, volume: cur.volume))
        }
        return result
    }
    
    private func fetchDailyWeeklyFromSina(product: ProductType, period: KlinePeriod) async throws -> [Kline] {
        let symbols = product.sinaSymbols
        var lastError: Error?
        
        for (_, symbol) in symbols.enumerated() {
            do {
                // 外盘 COMEX：GlobalFuturesService（日K/周K）
                let service = period == .w1
                    ? "GlobalFuturesService.getGlobalFuturesWeeklyKLine"
                    : "GlobalFuturesService.getGlobalFuturesDailyKLine"
                let urlStr = "https://stock.finance.sina.com.cn/futures/api/openapi.php/\(service)?symbol=\(symbol)&datalen=500"
                
                guard let url = URL(string: urlStr) else { continue }
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                                forHTTPHeaderField: "User-Agent")
                request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
                
                let (data, response) = try await session.data(for: request)
                guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                    lastError = APIError.httpError
                    continue
                }
                
                if let klines = try? parseSinaGlobalKline(data), !klines.isEmpty {
                    return klines
                }
                lastError = APIError.noData
            } catch {
                lastError = error
            }
        }
        
        throw lastError ?? APIError.noData
    }
    
    private func parseSinaGlobalKline(_ data: Data) throws -> [Kline] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let status = result["status"] as? [String: Any],
              (status["code"] as? Int) == 0,
              let items = result["data"] as? [[String: Any]] else {
            throw APIError.noData
        }
        
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        
        var klines: [Kline] = []
        for item in items {
            guard let dateStr = item["date"] as? String,
                  let open = Double(item["open"] as? String ?? ""), open > 0,
                  let high = Double(item["high"] as? String ?? ""), high > 0,
                  let low = Double(item["low"] as? String ?? ""), low > 0,
                  let close = Double(item["close"] as? String ?? ""), close > 0 else { continue }
            let volume = Double(item["volume"] as? String ?? "") ?? 0
            let ts = fmt.date(from: dateStr)?.timeIntervalSince1970 ?? 0
            klines.append(Kline(
                timestamp: ts * 1000,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume
            ))
        }
        
        if klines.isEmpty { throw APIError.noData }
        return klines
    }
    
    // MARK: - Yahoo Finance（期货分钟K：带域轮换、重试、随机延迟 + 基差校准）
    
    private func fetchFromYahoo(product: ProductType, period: KlinePeriod) async throws -> [Kline] {
        // 随机延迟 0.5-2秒，分散请求避免限流
        let jitter = Double.random(in: 0.5...2.0)
        try await Task.sleep(nanoseconds: UInt64(jitter * 1_000_000_000))
        let (range, interval) = mapPeriod(period)
        // ⚠️ 期货代码（GC=F 深度够；价格与现货差~60美元，由 calibrateToSpot 校准到现货价）
        let symbol = product == .xau ? "GC=F" : "SI=F"
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        
        let yahooHosts = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
        let userAgents = [
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        ]
        
        var lastError: Error?
        
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
    
    /// 周期映射（分钟K走Yahoo期货；日K/周K走新浪现货）
    private func mapPeriod(_ period: KlinePeriod) -> (range: String, interval: String) {
        switch period {
        case .m1:  return ("1d", "1m")
        case .m5:  return ("5d", "5m")
        case .m15: return ("1mo", "15m")
        case .m30: return ("1mo", "30m")
        case .h1:  return ("3mo", "60m")
        case .h4:  return ("6mo", "60m")   // Yahoo 无原生4h，取60m后每4根聚合成4h
        case .d1:  return ("1y", "1d")
        case .w1:  return ("5y", "1wk")
        }
    }
    
    /// 基差校准：Yahoo期货价 → 现货价（delta = 新浪现货最新收盘 - 期货最新收盘）
    /// 失败时原样返回（至少形状/深度可用）
    private func calibrateToSpot(_ futures: [Kline], product: ProductType) async throws -> [Kline] {
        guard let lastFutures = futures.last, lastFutures.close > 0 else { return futures }
        let daily = try await fetchSinaDaily(product: product)
        guard let spot = daily.last, spot.close > 0 else { return futures }
        let delta = spot.close - lastFutures.close
        guard abs(delta) > 0.01 else { return futures }
        return futures.map { k in
            Kline(timestamp: k.timestamp,
                  open: k.open + delta,
                  high: k.high + delta,
                  low: k.low + delta,
                  close: k.close + delta,
                  volume: k.volume)
        }
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
    
    /// 将60分钟K线聚合成4小时K线
    private func aggregateToH4(_ klines: [Kline]) -> [Kline] {
        guard klines.count > 1 else { return klines }
        var result: [Kline] = []
        var current: (open: Double, high: Double, low: Double, close: Double, volume: Double, ts: TimeInterval)? = nil
        
        for k in klines {
            if var cur = current {
                if k.timestamp - cur.ts < 4 * 3600 * 1000 {
                    // 同一4h段内：合并
                    cur.high = max(cur.high, k.high)
                    cur.low = min(cur.low, k.low)
                    cur.close = k.close
                    cur.volume = cur.volume + k.volume
                    current = cur
                } else {
                    result.append(Kline(timestamp: cur.ts, open: cur.open, high: cur.high, low: cur.low, close: cur.close, volume: cur.volume))
                    current = (k.open, k.high, k.low, k.close, k.volume, k.timestamp)
                }
            } else {
                current = (k.open, k.high, k.low, k.close, k.volume, k.timestamp)
            }
        }
        if let cur = current {
            result.append(Kline(timestamp: cur.ts, open: cur.open, high: cur.high, low: cur.low, close: cur.close, volume: cur.volume))
        }
        return result
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
