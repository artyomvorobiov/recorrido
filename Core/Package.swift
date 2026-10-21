// swift-tools-version: 5.9
// The platform-independent heart of Recorrido: models, route planning,
// share links and the Wikipedia client. The iOS app and the widget compile
// these same sources directly; this package exists so the logic can be
// unit-tested with `swift test`.
import PackageDescription

let package = Package(
    name: "RecorridoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RecorridoCore", targets: ["RecorridoCore"]),
    ],
    targets: [
        .target(name: "RecorridoCore", path: "Sources/RecorridoCore"),
        .testTarget(name: "RecorridoCoreTests", dependencies: ["RecorridoCore"], path: "Tests/RecorridoCoreTests"),
    ]
)
