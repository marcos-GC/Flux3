import XCTest
@testable import FluxCore

final class PreciseEditTests: XCTestCase {
    func testBBoxIsYFirstAndNormalized() {
        // Imagen 2000×1000; caja x=500…1500, y=100…600.
        let r = PixelRect(x: 500, y: 100, width: 1000, height: 500)
        XCTAssertEqual(PreciseEdit.bbox(r, imageWidth: 2000, imageHeight: 1000), [100, 250, 600, 750])
    }

    func testBBoxRoundsAndClamps() {
        let r = PixelRect(x: -10, y: 33.4, width: 1200, height: 100.2)
        XCTAssertEqual(PreciseEdit.bbox(r, imageWidth: 1000, imageHeight: 1000), [33, 0, 134, 1000])
    }

    func testGridPositions() {
        func pos(_ cx: Double, _ cy: Double) -> String {
            PreciseEdit.position(of: PixelRect(x: cx - 5, y: cy - 5, width: 10, height: 10), imageWidth: 900, imageHeight: 900)
        }
        XCTAssertEqual(pos(100, 100), "upper left")
        XCTAssertEqual(pos(450, 100), "upper middle")
        XCTAssertEqual(pos(800, 100), "upper right")
        XCTAssertEqual(pos(100, 450), "middle left")
        XCTAssertEqual(pos(450, 450), PreciseEdit.centerWord)
        XCTAssertEqual(pos(800, 450), "middle right")
        XCTAssertEqual(pos(100, 800), "lower left")
        XCTAssertEqual(pos(450, 800), "lower middle")
        XCTAssertEqual(pos(800, 800), "lower right")
    }

    /// Ejemplo copiado de la herramienta oficial ("View prompt → Model prompt").
    func testMatchesOfficialExample() {
        let region = EditRegionSpec(
            number: 1, kind: .edit,
            source: PixelRect(x: 241, y: 34, width: 583, height: 219),
            instruction: "make the hat bright red"
        )
        let prompt = PreciseEdit.buildPrompt(
            globalInstruction: "make it black and white film photo",
            regions: [region], imageWidth: 1000, imageHeight: 1000
        )
        let expected = #"Edit the first reference image. make it black and white film photo. Apply this edit to the marked area <region_1> in the upper middle: "make the hat bright red". Keep everything else — composition, lighting, other subjects, and style — exactly as in the reference image. [{"id":"region_1","from":"ref_image_0","src_bbox":[34,241,253,824]}]"#
        XCTAssertEqual(prompt, expected)
    }

    func testWithoutGlobalInstructionAndEmptyRegionsAreSkipped() {
        let empty = EditRegionSpec(number: 1, source: PixelRect(x: 0, y: 0, width: 100, height: 100), instruction: "  ")
        let real = EditRegionSpec(number: 2, source: PixelRect(x: 0, y: 900, width: 100, height: 100), instruction: "add a rug")
        let prompt = PreciseEdit.buildPrompt(globalInstruction: "", regions: [empty, real], imageWidth: 1000, imageHeight: 1000)
        XCTAssertTrue(prompt.hasPrefix("Edit the first reference image. Apply this edit to the marked area <region_2> in the lower left"))
        XCTAssertFalse(prompt.contains("region_1"))
    }

    func testAdvancedKinds() {
        let w = 1000.0, h = 1000.0
        let regions = [
            EditRegionSpec(number: 1, kind: .new, target: PixelRect(x: 700, y: 700, width: 200, height: 200),
                           instruction: "a \"green\" armchair", referenceImageIndex: 1),
            EditRegionSpec(number: 2, kind: .move, source: PixelRect(x: 0, y: 0, width: 100, height: 100),
                           target: PixelRect(x: 800, y: 0, width: 100, height: 100), instruction: ""),
            EditRegionSpec(number: 3, kind: .anchor, source: PixelRect(x: 400, y: 400, width: 200, height: 200), instruction: ""),
        ]
        let prompt = PreciseEdit.buildPrompt(globalInstruction: "", regions: regions, imageWidth: w, imageHeight: h)
        XCTAssertTrue(prompt.contains(#"Add a new element in the marked area <region_1> in the lower right, using <ref_image_1> as the reference: "a 'green' armchair"."#))
        XCTAssertTrue(prompt.contains(#"{"id":"region_1","from":"ref_image_1","src_bbox":null,"tgt_bbox":[700,700,900,900],"desc":"a \"green\" armchair","kind":"new"}"#))
        XCTAssertTrue(prompt.contains("Move the element in the marked area <region_2> from the upper left to the upper right."))
        XCTAssertTrue(prompt.contains(#"{"id":"region_2","from":"ref_image_0","src_bbox":[0,0,100,100],"tgt_bbox":[0,800,100,900],"kind":"move"}"#))
        XCTAssertTrue(prompt.contains("Keep the marked area <region_3> in the centre of the frame unchanged."))
        XCTAssertTrue(prompt.contains(#"{"id":"region_3","from":"ref_image_0","src_bbox":[400,400,600,600],"kind":"anchor"}"#))
    }

    func testEditWithReferenceAndExtraReferences() {
        let r = EditRegionSpec(number: 1, source: PixelRect(x: 0, y: 0, width: 500, height: 500),
                               instruction: "replace the lamp", referenceImageIndex: 1)
        let prompt = PreciseEdit.buildPrompt(globalInstruction: "warmer light!", regions: [r],
                                             imageWidth: 1000, imageHeight: 1000, extraReferenceIndices: [2, 3])
        XCTAssertTrue(prompt.contains("Edit the first reference image. warmer light! Apply this edit"))
        XCTAssertTrue(prompt.contains("in the upper left, using <ref_image_1> as the reference: \"replace the lamp\"."))
        XCTAssertTrue(prompt.contains("Use <ref_image_2>, <ref_image_3> as additional reference. Keep everything else"))
    }

    /// Segundo ejemplo copiado de la herramienta oficial (región en el centro y otra arriba a la derecha).
    func testMatchesOfficialCentreExample() {
        let regions = [
            EditRegionSpec(number: 1, source: PixelRect(x: 300, y: 300, width: 400, height: 400), instruction: "change"),
            EditRegionSpec(number: 2, source: PixelRect(x: 712, y: 35, width: 229, height: 193), instruction: "corlour change"),
        ]
        let prompt = PreciseEdit.buildPrompt(globalInstruction: "", regions: regions, imageWidth: 1000, imageHeight: 1000)
        let expected = #"Edit the first reference image. Apply this edit to the marked area <region_1> in the centre of the frame: "change". Apply this edit to the marked area <region_2> in the upper right: "corlour change". Keep everything else — composition, lighting, other subjects, and style — exactly as in the reference image. [{"id":"region_1","from":"ref_image_0","src_bbox":[300,300,700,700]},{"id":"region_2","from":"ref_image_0","src_bbox":[35,712,228,941]}]"#
        XCTAssertEqual(prompt, expected)
    }

    func testSmallBoxWarning() {
        XCTAssertTrue(PreciseEdit.isTooSmall(PixelRect(x: 0, y: 0, width: 39, height: 30)))
        XCTAssertTrue(PreciseEdit.isTooSmall(PixelRect(x: 0, y: 0, width: 100, height: 20)))
        XCTAssertFalse(PreciseEdit.isTooSmall(PixelRect(x: 0, y: 0, width: 40, height: 25)))
        XCTAssertFalse(PreciseEdit.isTooSmall(PixelRect(x: 0, y: 0, width: 25, height: 40)))
    }
}
