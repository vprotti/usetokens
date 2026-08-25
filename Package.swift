// swift-tools-version:5.9
import PackageDescription

// NOTE: keep this package free of `resources:` declarations. The .app bundle is
// assembled by hand in scripts/build.sh, so Bundle.module lookups would crash at
// launch — all strings live in code (L10n.swift) and every icon is drawn at
// runtime. The only bundled resource, UseTokens.icns, is referenced by
// Info.plist alone.
let package = Package(
    name: "UseTokens",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "UseTokens"),
        .executableTarget(name: "assetgen"),
    ]
)
