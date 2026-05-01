// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShortcutHUD",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ShortcutHUD",
            path: "Sources",
            linkerSettings: [
                .unsafeFlags(["-framework", "AppKit"]),
                .unsafeFlags(["-framework", "ApplicationServices"]),
                .unsafeFlags(["-framework", "Carbon"]),
                .unsafeFlags(["-framework", "IOKit"]),
                .unsafeFlags(["-framework", "ServiceManagement"]),
            ]
        )
    ]
)
