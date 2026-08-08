# 金银Chart - iOS

现货黄金/白银 K线分析工具 + A股查询，原生 iOS 应用，支持 TrollStore 免签名安装。
由 GitHub Actions 自动构建 IPA（XcodeGen 工程）。

## 功能

- 🟡 **现货黄金 (XAU/USD)** 和 **白银 (XAG/USD)** K线
- 📊 多周期：1分/5分/15分/30分/1时/4时/日线/周线
- 📈 **技术指标**：MA、EMA、MACD、RSI、KDJ、布林带、W%R、ATR、OBV、一目均衡表
- 🔔 **综合信号系统**：MACD背离、RSI超买超卖、KDJ金叉死叉、均线系统、多周期共振、成交量异常等
- 🎯 **多空综合评分**：0~100
- 🔍 **A股个股搜索、自选、K线 + 信号评分**
- 🌙 **浅色主题**，金色点缀（build60 起锁定浅色，修复深色模式下 A股搜索黑底灰字）

## 数据源架构（当前，勿被 git log 早期 commit 误导）

> **核心原则：全部现货标的，不跳变。** 实时/日K/周K 走现货，分钟K 深度优先、价格用基差校准回现货。

| 数据 | 主源 | 备用 | 兜底 |
|------|------|------|------|
| 实时价 | 东方财富 push2 `122.XAU`/`122.XAG`（现货） | 新浪 `hf_XAU`/`hf_XAG`（伦敦金/银现货） | Mock |
| 日K/周K | 东方财富 push2his `122.XAU`/`122.XAG`（klt 101/102；周K 用日K聚合） | 新浪 `XAU`/`XAG`（5186根） | Mock |
| 分钟K 1/5/15/30/60/4h | 东方财富 push2his（有历史深度） | 新浪 1分钟线（仅当天，type参数是摆设） | Yahoo 期货 `GC=F`/`SI=F` 深度分钟K + **基差校准** |

- **基差校准**：`delta = 现货最新收盘 − 期货最新收盘`，对所有期货K线 OHLC 整体平移 +delta，使显示价格≈现货（现价约 4340 美元/盎司），形状与深度保留
- **h4 K线** = 60m K线每4根聚合
- **代理服务器**：若配置了代理（`KlineData.swift`），优先走代理抓东财
- 所有数据源失败依次降级（东财 → 新浪 → Yahoo 期货 → Mock），**永不返回假数据当真的用**（build67 教训：Yahoo 现货 `XAUUSD=X` 不存在导致非日线全变假数据的坑已修）

**已知限制**：新浪分钟K只有当天；Yahoo 现货不存在；东财本机数据中心 IP 偶发限流（不影响 App 家庭宽带）；本仓库 CI 环境无法直接测东财（限流），靠 App 真机验证。

## 安装（TrollStore）

### 方法一：下载 GitHub Actions 构建的 IPA

1. Fork 此仓库（或直接用本仓库 Actions）
2. 前往 Actions → Build IPA → Run workflow
3. 等待构建完成，下载 `GoldChart-IPA` artifact（文件名为 `GoldChart-v1.0-buildNN.ipa`）
4. 分享 IPA 到 TrollStore 安装

### 方法二：本地 Xcode 构建

```bash
git clone https://github.com/mvpbaggio/gold-chart-ios.git
cd gold-chart-ios
open Package.swift   # Xcode 自动解析依赖
# 或 xcodebuild -scheme GoldChart -destination 'platform=iOS,name=Any iPhone' build
```

> 构建依赖 GitHub Actions workflow（`.github/workflows/build.yml`），内含 XcodeGen + xcodebuild + 签名（TrollStore 免签名）。

## 已知状态（2026-08-08 build73）

- ✅ 已验证：A股搜索、自选列表即时显示（LazyVStack→VStack 全量渲染 + `.id()` 重建根治）、日线/周线现货价格正确
- ⏳ 待验证：分钟K深度（需手机端）、价格≈4340（手机端）、自选左滑删除（ScrollView 下需手动补手势）
- 🐛 已知遗留：东财分钟K手机端待复测（根治路径）；`emQuoteHosts` 未统一 push2delay

## 技术栈

- SwiftUI + UIKit 桥接（DGCharts 渲染K线）
- 纯原生，无第三方付费依赖，无 API Key 需求

## 目录速览

```
Sources/GoldChart/
├── Services/
│   ├── GoldApiService.swift      # 金银K线：东财→新浪→Yahoo期货+基差→Mock
│   ├── RealTimeService.swift     # 金银/汇率实时：东财→新浪
│   ├── StockApiService.swift     # A股搜索/K线（新浪/东财）
│   ├── IndicatorEngine.swift     # 指标计算（MA/EMA/MACD/RSI/KDJ/BOLL/OBV...）
│   ├── SignalEngine.swift        # 金银综合信号系统
│   └── StockSignalEngine.swift   # A股信号引擎（23指标×3权重 + 吊灯止损，只做多）
├── ViewModels/                   # ChartViewModel / SearchViewModel（自选持久化）
└── Views/                        # ChartView（K线主图+成交量）/ StockSearchView / SignalListView
```

## 许可

MIT（fork 后可自由改）