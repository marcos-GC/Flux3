import XCTest
@testable import FluxCore

final class PromptRecipeTests: XCTestCase {
    func testDefaultTitle() {
        XCTAssertEqual(PromptRecipe.defaultTitle(for: "Salón luminoso con sofá de bouclé y luz de tarde"),
                       "Salón luminoso con sofá de bouclé…")
        XCTAssertEqual(PromptRecipe.defaultTitle(for: "Cocina blanca."), "Cocina blanca")
        XCTAssertEqual(PromptRecipe.defaultTitle(for: "   "), "Prompt sin título")
    }

    func testParametersAndSummary() {
        let recipe = PromptRecipe(
            title: "x", prompt: "p", tool: "Generar", endpoint: "/v1/flux-3-image",
            parameters: .object(["resolution": .string("2k"), "aspect_ratio": .string("3:2"), "safety_tolerance": .number(2)])
        )
        XCTAssertEqual(recipe.imageSettings?.resolution, "2k")
        XCTAssertEqual(recipe.imageSettings?.aspectRatio, "3:2")
        XCTAssertTrue(recipe.parameterSummary.contains("3:2"))
        XCTAssertTrue(recipe.parameterSummary.contains("tolerancia 2"))
        XCTAssertNil(PromptRecipe(title: "x", prompt: "p", tool: "Vídeo").imageSettings)
    }

    func testLibraryRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent(PromptLibraryFile.fileName)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let recipes = [
            PromptRecipe(title: "Librería", notes: "Para renders de salón", prompt: "Architectural interior…", tool: "Generar",
                         parameters: .object(["resolution": .string("2k")]),
                         created: Date(timeIntervalSince1970: 1_790_000_000), updated: Date(timeIntervalSince1970: 1_790_000_100)),
        ]
        try PromptLibraryFile.save(recipes, to: url)
        XCTAssertEqual(PromptLibraryFile.load(from: url), recipes)
        XCTAssertEqual(PromptLibraryFile.load(from: url.appendingPathExtension("nada")), [])
    }
}
