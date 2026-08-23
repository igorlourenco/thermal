// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TempSensors",
    platforms: [
        .macOS(.v13)
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
        // CLI executable: `swift run tempsensors`
        .executableTarget(
            name: "tempsensors",
            dependencies: ["CPrivateHID"]
        )
    ]
)
