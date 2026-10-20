// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Lense", platforms: [.macOS(.v14)], products: [.executable(name: "Lense", targets: ["Lense"])], targets: [.executableTarget(name: "Lense")])
