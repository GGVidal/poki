import XCTest
@testable import Poki

/// The account page's Text Chat row. Switching a model on for an account that the chat does not use
/// read "Off", so owners thought the switch had failed and picked the model from Poki's menu instead.
@MainActor
final class ModelAccountRowTests: XCTestCase {
    private var hostLocalization: HostLocalizationSnapshot!
    private var storage: IsolatedTestStorage!

    override func setUp() async throws {
        hostLocalization = HostLocalizationSnapshot.capture()
        storage = try IsolatedTestStorage(prefix: "poki-model-row")
        AppLocalization.shared.preference = "en"
    }

    override func tearDown() async throws {
        hostLocalization.restore()
        hostLocalization.assertUnchanged()
        if let storage {
            self.storage = nil
            try storage.tearDown()
        }
    }

    func testSwitchedOnModelOfAnotherAccountIsNotShownAsOff() throws {
        let storage = storage.storage
        ModelKeys.setSelectedProvider(.anthropic, in: storage)
        for model in ModelCatalog.all(.openai, storage: storage) {
            ModelCatalog.set(model.id, on: false, for: .openai, notify: false, storage: storage)
        }
        XCTAssertEqual(ModelAccounts.textChatValue(.openai, storage: storage), "Off")

        let first = try XCTUnwrap(ModelCatalog.all(.openai, storage: storage).first)
        ModelCatalog.set(first.id, on: true, for: .openai, notify: false, storage: storage)

        XCTAssertEqual(ModelAccounts.textChatValue(.openai, storage: storage), "1 Model")
        XCTAssertEqual(ModelKeys.selectedProvider(in: storage), .anthropic, "Switching a model on does not move the chat")
    }

    func testAccountTheChatUsesShowsItsModel() {
        let storage = storage.storage
        ModelKeys.setSelectedProvider(.openai, in: storage)
        XCTAssertEqual(ModelAccounts.textChatValue(.openai, storage: storage), ModelKeys.selectedModelName(in: storage))
    }
}
