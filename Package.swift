// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarrKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17),
    ],
    products: [
        // Foundation only — deliberately no SwiftUI, no UIKit, no AppKit, so it
        // compiles for iOS, Mac Catalyst and native macOS from one source.
        .library(name: "CalendarrCore", targets: ["CalendarrCore"]),
    ],
    targets: [
        .target(
            name: "CalendarrCore",
            // Matches the apps, which build in Swift 5 language mode. Note that
            // this package deliberately does NOT set defaultIsolation(MainActor),
            // even though the Calendarr iOS app target does: the widget extension
            // and the read-only consumer app have no MainActor default, and making
            // the package MainActor-by-default would force `await` at every
            // SnapshotStore.read() call site.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CalendarrCoreTests",
            dependencies: ["CalendarrCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
