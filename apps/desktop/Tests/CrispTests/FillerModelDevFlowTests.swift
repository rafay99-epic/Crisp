import XCTest
import CrispCore
@testable import Crisp

/// The ML dev-flow seams: channel-derived model manifests, the HF URL helpers the
/// version picker + updater build, and the dev sideload resolution.
final class FillerModelDevFlowTests: XCTestCase {
    private let pinned = URL(string:
        "https://huggingface.co/rafay99-epic/crisp-models/resolve/v0.0.8/Wren.mlmodel")!

    // MARK: Channel → model branch

    func testModelChannelRefMirrorsReleaseChannels() {
        // Stable rides the promoted `main`; Nightly + Dev ride the `nightly` staging
        // manifest, so they test a model before it's promoted to Stable.
        XCTAssertEqual(Channel.stable.modelChannelRef, "main")
        XCTAssertEqual(Channel.nightly.modelChannelRef, "nightly")
        XCTAssertEqual(Channel.dev.modelChannelRef, "nightly")
    }

    func testOnlyDevShowsModelDevTools() {
        XCTAssertTrue(Channel.dev.showsModelDevTools)
        XCTAssertFalse(Channel.stable.showsModelDevTools)
        XCTAssertFalse(Channel.nightly.showsModelDevTools)
    }

    // MARK: HF resolve-URL helpers

    func testManifestURLUsesCurrentChannelRef() {
        // In the test bundle Channel.current defaults to .stable → the `main` manifest.
        let url = FillerModelUpdater.manifestURL(from: pinned)
        XCTAssertEqual(url?.absoluteString,
            "https://huggingface.co/rafay99-epic/crisp-models/resolve/main/Wren.config.json")
    }

    func testVersionedURLPinsToTag() {
        let url = FillerModelUpdater.versionedURL(from: pinned, version: "0.0.6", file: "Wren.mlmodel")
        XCTAssertEqual(url?.absoluteString,
            "https://huggingface.co/rafay99-epic/crisp-models/resolve/v0.0.6/Wren.mlmodel")
    }

    func testRefsURLForVersionHistory() {
        let url = FillerModelVersions.refsURL(from: pinned)
        XCTAssertEqual(url?.absoluteString,
            "https://huggingface.co/api/models/rafay99-epic/crisp-models/refs")
    }

    func testVersionOrderingIsNewestFirst() {
        XCTAssertTrue(FillerModelUpdater.isNewer("0.0.10", than: "0.0.9"))
        XCTAssertFalse(FillerModelUpdater.isNewer("0.0.7", than: "0.0.8"))
        XCTAssertFalse(FillerModelUpdater.isNewer("0.0.8", than: "0.0.8"))
    }

    // MARK: Dev sideload resolution

    func testDevSideloadIsInertOffDevBuild() {
        // Tests run as the stable-default bundle, so no override is ever resolved even
        // if a path was picked — the sideload is strictly a dev-build affordance.
        let key = "devLocalFillerModelPath"
        let saved = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        DevFillerModel.pickedPath = "/tmp/whatever/Wren.mlmodel"
        XCTAssertEqual(DevFillerModel.pickedPath, "/tmp/whatever/Wren.mlmodel")
        XCTAssertFalse(DevFillerModel.isAvailable)
        XCTAssertNil(DevFillerModel.overridePath)
        DevFillerModel.pickedPath = nil
    }
}
