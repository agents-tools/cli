// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "cli",
  platforms: [.macOS(.v15)],
  products: [.executable(name: "agents", targets: ["CLI"])],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    .package(
      url: "https://github.com/agents-tools/core.git",
      revision: "aca8f9fbebf8db010705f480445cda315de3e979"),
  ],
  targets: [
    .executableTarget(
      name: "CLI",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "AgentsCore", package: "core"),
        .product(name: "AgentsSkills", package: "core"),
        .product(name: "AgentsInstructions", package: "core"),
        .product(name: "AgentsUpdates", package: "core"),
      ]),
    .testTarget(name: "CLITests", dependencies: ["CLI"]),
  ],
  swiftLanguageModes: [.v6]
)
