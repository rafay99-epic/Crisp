import XCTest
import CrispCore

final class ModelCatalogTests: XCTestCase {
    func testCatalogHasDistinctIdsAndFiles() {
        let ids = ModelCatalog.all.map(\.id)
        let files = ModelCatalog.all.map(\.fileName)
        XCTAssertEqual(Set(ids).count, ids.count, "model ids must be unique")
        XCTAssertEqual(Set(files).count, files.count, "model file names must be unique")
        XCTAssertFalse(ModelCatalog.all.isEmpty)
    }

    func testExactlyOneRecommendedAndItIsTheDefault() {
        let recommended = ModelCatalog.all.filter(\.recommended)
        XCTAssertEqual(recommended.count, 1)
        XCTAssertEqual(recommended.first?.id, ModelCatalog.defaultID)
    }

    func testSpecLookup() {
        XCTAssertEqual(ModelCatalog.spec(id: "large-v3-turbo").id, "large-v3-turbo")
        XCTAssertEqual(ModelCatalog.spec(id: ModelCatalog.defaultID).id, ModelCatalog.defaultID)
    }

    func testUnknownOrNilFallsBackToDefault() {
        // A settings file naming a model we no longer ship must still resolve.
        XCTAssertEqual(ModelCatalog.spec(id: nil).id, ModelCatalog.defaultID)
        XCTAssertEqual(ModelCatalog.spec(id: "ggml-does-not-exist").id, ModelCatalog.defaultID)
    }

    func testFilenamesAreWhisperGGMLAndDeriveDTWAlias() {
        // The engine infers the DTW preset from the file stem; these must match
        // whisper.cpp naming so that inference works.
        XCTAssertEqual(ModelCatalog.base.fileName, "ggml-base.en.bin")
        XCTAssertTrue(ModelCatalog.turbo.fileName.hasPrefix("ggml-large-v3-turbo"))
    }
}

final class EngineConfigModelFieldTests: XCTestCase {
    func testDefaultSelectedModelIsCatalogDefault() {
        XCTAssertEqual(EngineConfig.defaults.selectedModelID, ModelCatalog.defaultID)
    }

    func testRoundTripsSelectedModel() throws {
        var cfg = EngineConfig.defaults
        cfg.selectedModelID = "large-v3-turbo"
        let data = try JSONEncoder().encode(cfg)
        let back = try JSONDecoder().decode(EngineConfig.self, from: data)
        XCTAssertEqual(back.selectedModelID, "large-v3-turbo")
    }

    func testOldConfigWithoutModelKeyDecodesToDefault() throws {
        // Forward-compatible decode: a settings.json written before this field
        // existed must load with the default model, not fail.
        let json = Data(#"{"version":3,"pauseThreshold":0.35}"#.utf8)
        let cfg = try JSONDecoder().decode(EngineConfig.self, from: json)
        XCTAssertEqual(cfg.selectedModelID, ModelCatalog.defaultID)
    }
}
