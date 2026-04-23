import SwiftUI
import AppKit
import CoreText

@main
struct KinApp: App {
    @State private var store = AgentStore()
    @AppStorage("kinTheme") private var kinTheme = "dark"

    init() {
        registerInterFont()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .preferredColorScheme(kinTheme == "light" ? .light : .dark)
                .onAppear { applyAppearance(kinTheme) }
                .onChange(of: kinTheme) { _, newTheme in applyAppearance(newTheme) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1060, height: 680)
        .commands {
            CommandGroup(replacing: .appSettings) {}
        }
    }

    private func applyAppearance(_ theme: String) {
        NSApp.appearance = NSAppearance(named: theme == "light" ? .aqua : .darkAqua)
    }

    private func registerInterFont() {
        guard let url = Bundle.main.url(forResource: "InterVariable", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
