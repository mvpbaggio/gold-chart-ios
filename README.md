# 金银Chart - iOS

现货黄金/白银 K线分析工具 + A股查询，原生 iOS 应用，支持 TrollStore 安装。

## 功能

- 🟡 **现货黄金 (XAU/USD)** 和 **白银 (XAG/USD)** K线
- 📊 多周期：1分/5分/15分/30分/1时/4时/日线/周线
- 📈 **技术指标**：MA、EMA、MACD、RSI、KDJ、布林带、W%R、ATR、OBV、一目均衡表
- 🔔 **综合信号系统**：MACD背离、RSI超买超卖、KDJ金叉死叉、均线系统、多周期共振、成交量异常等
- 🎯 **多空综合评分**：0~100，一目了然
- 🔍 **A股个股搜索与查看**
- 🌙 **深色主题**，金色点缀

## 安装（TrollStore）

### 方法一：下载 GitHub Actions 构建的 IPA

1. Fork 此仓库
2. 前往 Actions → Build IPA → Run workflow
3. 等待构建完成，下载 `GoldChart-IPA` artifact
4. 分享 IPA 到 TrollStore 安装

### 方法二：本地 Xcode 构建

```bash
# 克隆项目
git clone <your-repo>
cd gold-ios

# 打开 Package.swift，Xcode 会自动解析依赖
open Package.swift
# 或者用 xcodebuild 构建
xcodebuild -scheme GoldChart -destination 'platform=iOS,name=Any iPhone' build
```

## 数据源

- **黄金/白银**：[Gold-API](https://www.gold-api.com)（免费注册获取 API Key）
- **A股**：新浪财经 API
- 无 API Key 时自动使用模拟数据

在 App 设置页面输入你的 Gold-API Key 即可启用真实数据。

## 技术栈

- SwiftUI + UIKit 桥接
- DGCharts（K线渲染）
- 纯原生，无第三方依赖（除图表库）

## 许可

MIT
