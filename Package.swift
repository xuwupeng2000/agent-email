// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "AgentEmail", platforms: [.macOS(.v14)], products: [.executable(name: "AgentEmail", targets: ["AgentEmail"])], targets: [.executableTarget(name: "AgentEmail")])
