// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FluxStudio",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FluxStudio", targets: ["FluxStudio"]),
    ],
    targets: [
        // Lógica pura: cliente de la API, modelos, reglas. Testeable sin interfaz.
        .target(name: "FluxCore", path: "Sources/FluxCore"),
        // La app SwiftUI.
        .executableTarget(name: "FluxStudio", dependencies: ["FluxCore"], path: "Sources/FluxStudio"),
        .testTarget(name: "FluxCoreTests", dependencies: ["FluxCore"], path: "Tests/FluxCoreTests"),
    ]
)
