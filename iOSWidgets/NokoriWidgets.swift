import AppIntents
import SwiftUI
import UsageCore
import WidgetKit

@main struct NokoriWidgets: WidgetBundle {
    var body: some Widget {
        UsageWidget()
        RingWidget()
    }
}

/// Home screen small and medium, and the lock screen rectangle: the services the Mac shows, or one chosen service.
/// One service per widget lets StandBy put Claude on one side and Codex on the other.
struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "dev.int314.nokori.usage", intent: SelectServicesIntent.self, provider: UsageProvider()) { entry in
            UsageEntryView(entry: entry)
        }.configurationDisplayName("Usage").description("Claude Code and Codex usage, fetched by your Mac.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular]).contentMarginsDisabled()
    }
}

/// Lock screen circle: one ring per widget, so place two to watch both.
struct RingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "dev.int314.nokori.ring", intent: SelectServiceIntent.self, provider: RingProvider()) { entry in
            UsageEntryView(entry: entry)
        }.configurationDisplayName("Usage ring").description("One service's 5-hour and weekly usage as rings.")
            .supportedFamilies([.accessoryCircular])
    }
}

enum ServiceOption: String, AppEnum {
    case claude, codex
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Service"
    static let caseDisplayRepresentations: [ServiceOption: DisplayRepresentation] = [.claude: "Claude Code", .codex: "Codex"]
    var provider: Provider { self == .claude ? .claude : .codex }
}

struct SelectServiceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Service"
    @Parameter(title: "Service", default: .claude) var service: ServiceOption
}

enum ServicesOption: String, AppEnum {
    case mac, claude, codex
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Services"
    static let caseDisplayRepresentations: [ServicesOption: DisplayRepresentation] = [.mac: "Same as Mac", .claude: "Claude Code", .codex: "Codex"]
    var provider: Provider? { switch self { case .mac: nil; case .claude: .claude; case .codex: .codex } }
}

enum StyleOption: String, AppEnum {
    case rings, bars
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static let caseDisplayRepresentations: [StyleOption: DisplayRepresentation] = [.rings: "Rings", .bars: "Bars"]
}

struct SelectServicesIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Services"
    @Parameter(title: "Services", default: .mac) var services: ServicesOption
    @Parameter(title: "Style", default: .rings) var style: StyleOption
    /// Only the small widget has rings to swap; the medium one and the lock screen are bars already.
    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .systemSmall) {
            Summary { \.$services; \.$style }
        } otherwise: {
            Summary { \.$services }
        }
    }
}
