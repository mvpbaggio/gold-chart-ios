import SwiftUI

@main
struct GoldChartApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)   // 锁定浅色模式：AppColors 配色是写死的浅色，深色模式下 List 黑底灰字看不清
        }
    }
}
