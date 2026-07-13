import SwiftUI
import RelicCore

@main
struct NightreignRelicCheckerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("夜幕验物") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1040, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("遗物") {
                Button("检查合法性") { model.checkSelection() }
                    .keyboardShortcut(.return, modifiers: [.command])
                Button("随机获取") { model.randomize() }
                    .keyboardShortcut("r", modifiers: [.command])
                Divider()
                Button("清空选择") { model.clearSelection() }
                    .keyboardShortcut(.delete, modifiers: [.command])
            }
        }
    }
}
