// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Thermal",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // Updates (installer.md §4). Binary xcframework; bundle.sh embeds it
        // into Thermal.app/Contents/Frameworks.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        // C shim exposing the private IOHIDEventSystemClient API.
        // These functions live in IOKit but have no public headers.
        .target(
            name: "CPrivateHID",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        // CLI executable: `swift run thermal`
        .executableTarget(
            name: "thermal",
            dependencies: [
                "CPrivateHID",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                // So the bundled app finds Sparkle.framework next to the
                // binary; `swift run` finds it via SwiftPM's artifact rpath.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
