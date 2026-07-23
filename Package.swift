// swift-tools-version:6.1
import PackageDescription

// Ergo — a Mac-first, agent-native Kubernetes client.
//
// This package holds the platform-agnostic domain layers. The macOS app
// target lives in the XcodeGen-generated `Ergo.xcodeproj` and depends on
// these libraries. Keeping the logic here (not in the app target) is what
// lets a future iOS/iPadOS companion reuse it unchanged.
//
// Dependency graph (acyclic, one direction only):
//   KubeUI  ──▶  KubeClient  ──▶  KubeCore
//
// Three product pillars live as module seams, not features:
//   1. relationships & time  → KubeCore (OwnerReference, EventRecord)
//   2. schema & AI           → KubeCore (CRDSummary) + KubeClient (SchemaProviding)
//   3. auth & agents         → KubeClient (ClusterCredential, MCPExposing)
let package = Package(
    name: "Ergo",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "KubeCore", targets: ["KubeCore"]),
        .library(name: "KubeClient", targets: ["KubeClient"]),
        .library(name: "KubeUI", targets: ["KubeUI"]),
    ],
    targets: [
        // Pillar seams 1 & 2: pure value types, no I/O, no platform deps.
        .target(
            name: "KubeCore",
            swiftSettings: .strict
        ),
        // The API boundary + a fixture-backed fake. Ships fixtures as a
        // resource so both tests and SwiftUI previews stay hermetic.
        .target(
            name: "KubeClient",
            dependencies: ["KubeCore"],
            resources: [.process("Fixtures")],
            swiftSettings: .strict
        ),
        // Shared SwiftUI surface. macOS-only APIs stay behind availability.
        .target(
            name: "KubeUI",
            dependencies: ["KubeClient", "KubeCore"],
            swiftSettings: .strict
        ),
        .testTarget(
            name: "KubeCoreTests",
            dependencies: ["KubeCore"],
            swiftSettings: .strict
        ),
        .testTarget(
            name: "KubeClientTests",
            dependencies: ["KubeClient", "KubeCore"],
            swiftSettings: .strict
        ),
    ]
)

extension [SwiftSetting] {
    /// Swift 6 language mode with complete strict concurrency, applied
    /// uniformly to every target so the graph is enforced end to end.
    static var strict: [SwiftSetting] {
        [
            .swiftLanguageMode(.v6),
            .enableUpcomingFeature("ExistentialAny"),
        ]
    }
}
