// swift-tools-version:6.1
import PackageDescription

// Vendored build tools. This isolated package exists solely so the project
// generator (XcodeGen) is pinned and reproducible on a clean checkout with
// nothing but the Xcode toolchain installed — no Homebrew, no Mint.
//
// Usage (wrapped by the Makefile):
//   swift run --package-path Tools xcodegen generate --spec project.yml
let package = Package(
    name: "Tools",
    dependencies: [
        .package(url: "https://github.com/yonaskolb/XcodeGen.git", exact: "2.46.0")
    ],
    targets: []
)
