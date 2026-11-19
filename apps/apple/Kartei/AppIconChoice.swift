// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The home-screen icon: Bergmönch "Mountain 1 · Range" in GEIST colours (default) or Gruvbox colours.
/// iOS uses alternate app icons (the system shows a short notice on change); macOS swaps the Dock icon while running.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case geist, gruvbox

    var id: String { rawValue }
    var title: String { self == .geist ? "GEIST" : "Gruvbox" }
    /// Alternate icon name in the asset catalog; nil is the primary icon.
    var iconName: String? { self == .geist ? nil : "AppIcon-Gruvbox" }
    /// Plain image of the same icon, for the macOS Dock and the picker preview.
    var previewImage: String { self == .geist ? "AppIconImage" : "AppIcon-GruvboxImage" }

    static let defaultsKey = "kartei.appIcon"

    static var saved: AppIconChoice {
        get { AppIconChoice(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .geist }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// Apply the choice. On iOS this changes the home-screen icon; on macOS the Dock icon until the app quits.
    @MainActor func apply() {
        AppIconChoice.saved = self
        #if os(iOS)
        guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != iconName else { return }
        UIApplication.shared.setAlternateIconName(iconName) { _ in }
        #else
        NSApplication.shared.applicationIconImage = self == .geist ? nil : NSImage(named: previewImage)
        #endif
    }
}

/// "App icon" row for the Appearance section.
struct AppIconPicker: View {
    @State private var choice = AppIconChoice.saved

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Caption("App icon").padding(.top, ChoiceLayout.sectionGap).padding(.bottom, ChoiceLayout.captionGap)
            ChoiceGrid(count: AppIconChoice.allCases.count) { i in
                let option = AppIconChoice.allCases[i]
                ChoiceTile(selected: choice == option, label: option.title, accessibility: "\(option.title) app icon") {
                    choice = option
                    option.apply()
                } swatch: {
                    // The icon on the page colour, the same height as the swatches above it.
                    Image(option.previewImage).resizable().scaledToFit()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Ink.surface)
                }
            }
        }
    }
}
