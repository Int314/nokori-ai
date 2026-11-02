import SwiftUI
import UsageCore

public struct Theme {
    public let dark: Bool
    public init(_ scheme: ColorScheme) { dark = scheme == .dark }
    private func color(_ light: UInt32, _ dark: UInt32) -> Color {
        let hex = self.dark ? dark : light
        return Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
    public var page: Color { color(0xF4F5F7, 0x121418) }
    public var caption: Color { color(0x55595F, 0xA3A9B5) }
    public var macWall: Color { color(0xD9DFE7, 0x2A2F3A) }
    public var itemBackground: Color { color(0xD5D8DE, 0x3A3F4A) }
    public var phoneWall: Color { color(0xC7D0DC, 0x3B4250) }
    public var phoneLabel: Color { color(0x2E3440, 0xE3E6EB) }
    public var lock: Color { color(0x3C4656, 0x232833) }
    public var settingsMenubar: Color { color(0xE4E7EC, 0x2A2E36) }
    public var settingsDivider: Color { color(0xDFE1E6, 0x3A3F4A) }
    public var text: Color { color(0x1C1D21, 0xF2F3F5) }
    public var sub: Color { color(0x6B7079, 0xA3A9B5) }
    public var pop: Color { color(0xFFFFFF, 0x1E2128) }
    public var chip: Color { color(0xF0F1F4, 0x2C3039) }
    public var track: Color { color(0xE6E8EC, 0x353A44) }
    public var divider: Color { color(0xECEDF0, 0x2C3039) }
    public var marker: Color { text }
    public var card: Color { widget }
    public var ringTrack: Color { color(0xB4B9C2, 0x4A505C) }
    public var menubar: Color { color(0xF6F7F9, 0x1A1D23) }
    public var screen: Color { color(0xF2F2F7, 0x000000) }
    public var widget: Color { color(0xFFFFFF, 0x1C1F25) }
    public func provider(_ provider: Provider) -> Color { provider == .claude ? color(0xC8603C, 0xE8825F) : color(0x2563C9, 0x8EC5FF) }
}
