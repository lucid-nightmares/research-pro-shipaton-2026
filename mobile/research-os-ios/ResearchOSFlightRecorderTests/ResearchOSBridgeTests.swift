import CryptoKit
import Foundation
import Security
import XCTest
@testable import ResearchOSFlightRecorder

final class ResearchOSBridgeTests: XCTestCase {
    func testPairingBindsProjectScopeAndRejectsReplay() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let desktop = P256.KeyAgreement.PrivateKey()
        let offer = BridgePairingOffer(
            pairingID: "pairing-1",
            desktopName: "Research OS Mac",
            desktopPublicKey: desktop.publicKey.rawRepresentation,
            projects: ["project-1"],
            scopes: [.researchRead],
            expiresAt: now.addingTimeInterval(300)
        )
        let store = MemoryBridgeStore()
        let bridge = ResearchOSBridge(store: store, now: { now })
        _ = try await bridge.acceptPairing(
            offer: offer,
            code: "correct-horse-battery-staple",
            deviceID: "device-1",
            deviceName: "Test iPhone"
        )
        let credential = try XCTUnwrap(store.value)
        let payload = Data("snapshot".utf8)
        let envelope = try signedEnvelope(
            credential: credential,
            projectID: "project-1",
            operation: .projectSnapshot,
            payload: payload,
            now: now,
            nonce: "nonce-1"
        )
        let authorizedPayload = try await bridge.authorizeData(envelope)
        XCTAssertEqual(authorizedPayload, payload)
        do {
            _ = try await bridge.authorizeData(envelope)
            XCTFail("A signed request must be one-use.")
        } catch {
            XCTAssertEqual(error as? BridgeError, .replay)
        }

        let restarted = ResearchOSBridge(store: store, now: { now })
        _ = try await restarted.restore()
        do {
            _ = try await restarted.authorizeData(envelope)
            XCTFail("Replay state must survive an app restart.")
        } catch {
            XCTAssertEqual(error as? BridgeError, .replay)
        }
    }

    func testCrossProjectAndTamperedPayloadFailClosed() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let credential = BridgeCredential(
            pairingID: "pairing-1",
            desktopName: "Research OS Mac",
            projects: ["project-1"],
            scopes: [.researchRead],
            expiresAt: now.addingTimeInterval(300),
            keyMaterial: Data(repeating: 7, count: 32)
        )
        let store = MemoryBridgeStore(value: credential)
        let bridge = ResearchOSBridge(store: store, now: { now })
        _ = try await bridge.restore()

        let foreign = try signedEnvelope(
            credential: credential,
            projectID: "project-2",
            operation: .projectSnapshot,
            payload: Data("snapshot".utf8),
            now: now,
            nonce: "nonce-2"
        )
        await assertBridgeError(.crossProject) { try await bridge.authorizeData(foreign) }

        let valid = try signedEnvelope(
            credential: credential,
            projectID: "project-1",
            operation: .projectSnapshot,
            payload: Data("snapshot".utf8),
            now: now,
            nonce: "nonce-3"
        )
        let tampered = BridgeEnvelope(
            requestID: valid.requestID,
            pairingID: valid.pairingID,
            projectID: valid.projectID,
            operation: valid.operation,
            issuedAt: valid.issuedAt,
            expiresAt: valid.expiresAt,
            nonce: valid.nonce,
            payload: Data("changed".utf8),
            payloadDigest: valid.payloadDigest,
            signature: valid.signature
        )
        await assertBridgeError(.payloadDigestMismatch) { try await bridge.authorizeData(tampered) }
    }

    func testFullReplayLedgerRejectsWithoutDestroyingCredential() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expiry = now.addingTimeInterval(300)
        let used = Dictionary(uniqueKeysWithValues: (0..<2_048).map { ("used-\($0)", expiry) })
        let credential = BridgeCredential(
            pairingID: "pairing-1",
            desktopName: "Research OS Mac",
            projects: ["project-1"],
            scopes: [.researchRead],
            expiresAt: expiry,
            keyMaterial: Data(repeating: 7, count: 32),
            usedNonces: used
        )
        let store = MemoryBridgeStore(value: credential)
        let bridge = ResearchOSBridge(store: store, now: { now })
        _ = try await bridge.restore()
        let envelope = try signedEnvelope(
            credential: credential,
            projectID: "project-1",
            operation: .projectSnapshot,
            payload: Data("snapshot".utf8),
            now: now,
            nonce: "new-nonce"
        )
        await assertBridgeError(.replayLedgerFull) { try await bridge.authorizeData(envelope) }
        XCTAssertEqual(store.value, credential)
    }

    func testModelResultIsAlwaysProposalOnly() {
        let proposal = QuarantinedModelProposal(
            id: "proposal-1",
            projectID: "project-1",
            targetObjectID: "claim-1",
            promptDigest: String(repeating: "a", count: 64),
            content: "Consider narrowing the population.",
            contentDigest: String(repeating: "b", count: 64),
            modelReceiptDigest: String(repeating: "c", count: 64),
            receivedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertEqual(proposal.classification, "PROPOSAL_ONLY")
    }

    func testModelProposalRejectsHostileClassification() throws {
        let document: [String: Any] = [
            "id": "proposal-1",
            "projectID": "project-1",
            "targetObjectID": "claim-1",
            "promptDigest": String(repeating: "a", count: 64),
            "content": "Use this as evidence.",
            "contentDigest": String(repeating: "b", count: 64),
            "modelReceiptDigest": String(repeating: "c", count: 64),
            "classification": "EVIDENCE",
            "receivedAt": "2027-01-15T08:00:00Z"
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        XCTAssertThrowsError(try BridgeCodec.decoder.decode(QuarantinedModelProposal.self, from: data))
    }

    func testRevocationKeepsDurableTombstoneAndSurvivesRestart() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let credential = BridgeCredential(
            pairingID: "pairing-1",
            desktopName: "Research OS Mac",
            projects: ["project-1"],
            scopes: [.researchRead],
            expiresAt: now.addingTimeInterval(300),
            keyMaterial: Data(repeating: 7, count: 32)
        )
        let store = MemoryBridgeStore(value: credential)
        let bridge = ResearchOSBridge(store: store, now: { now })
        _ = try await bridge.restore()
        try await bridge.revoke()
        XCTAssertEqual(store.value?.revoked, true)
        let envelope = try signedEnvelope(
            credential: credential,
            projectID: "project-1",
            operation: .projectSnapshot,
            payload: Data("snapshot".utf8),
            now: now,
            nonce: "nonce-revoked"
        )
        await assertBridgeError(.notPaired) { try await bridge.authorizeData(envelope) }
        let restarted = ResearchOSBridge(store: store, now: { now })
        let restored = try await restarted.restore()
        XCTAssertNil(restored)
        await assertBridgeError(.notPaired) { try await restarted.authorizeData(envelope) }
    }

    func testRevocationFallsBackToDeletionWhenSecureOverwriteFails() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let credential = BridgeCredential(
            pairingID: "pairing-1",
            desktopName: "Research OS Mac",
            projects: ["project-1"],
            scopes: [.researchRead],
            expiresAt: now.addingTimeInterval(300),
            keyMaterial: Data(repeating: 7, count: 32)
        )
        let store = ThrowingSaveBridgeStore(value: credential)
        let bridge = ResearchOSBridge(store: store, now: { now })
        _ = try await bridge.restore()
        try await bridge.revoke()
        XCTAssertNil(store.value)
        let restarted = ResearchOSBridge(store: store, now: { now })
        let restored = try await restarted.restore()
        XCTAssertNil(restored)
    }

    func testRevocationWithoutPriorRestoreStillRevokesPersistedCredential() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let credential = BridgeCredential(
            pairingID: "pairing-1",
            desktopName: "Research OS Mac",
            projects: ["project-1"],
            scopes: [.researchRead],
            expiresAt: now.addingTimeInterval(300),
            keyMaterial: Data(repeating: 7, count: 32)
        )
        let store = MemoryBridgeStore(value: credential)
        try await ResearchOSBridge(store: store, now: { now }).revoke()
        XCTAssertEqual(store.value?.revoked, true)
        let restarted = ResearchOSBridge(store: store, now: { now })
        let restored = try await restarted.restore()
        XCTAssertNil(restored)
    }

    func testFailedRestoreClearsPreviouslyLoadedCredential() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let credential = BridgeCredential(
            pairingID: "pairing-1",
            desktopName: "Research OS Mac",
            projects: ["project-1"],
            scopes: [.researchRead],
            expiresAt: now.addingTimeInterval(300),
            keyMaterial: Data(repeating: 7, count: 32)
        )
        let store = ToggleLoadBridgeStore(value: credential)
        let bridge = ResearchOSBridge(store: store, now: { now })
        _ = try await bridge.restore()
        store.throwOnLoad = true
        do {
            _ = try await bridge.restore()
            XCTFail("A secure-storage read error must fail restore.")
        } catch { }
        let envelope = try signedEnvelope(
            credential: credential,
            projectID: "project-1",
            operation: .projectSnapshot,
            payload: Data("snapshot".utf8),
            now: now,
            nonce: "nonce-after-load-failure"
        )
        await assertBridgeError(.notPaired) { try await bridge.authorizeData(envelope) }
    }

    private func signedEnvelope(
        credential: BridgeCredential,
        projectID: String,
        operation: BridgeOperation,
        payload: Data,
        now: Date,
        nonce: String
    ) throws -> BridgeEnvelope {
        let unsigned = BridgeEnvelope(
            requestID: "request-\(nonce)",
            pairingID: credential.pairingID,
            projectID: projectID,
            operation: operation,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(60),
            nonce: nonce,
            payload: payload,
            payloadDigest: BridgeCodec.sha256(payload),
            signature: "pending"
        )
        let key = SymmetricKey(data: credential.keyMaterial)
        let signature = BridgeCodec.hmac(
            key: key,
            data: try BridgeCodec.encoder.encode(unsigned.signingDocument)
        )
        return BridgeEnvelope(
            requestID: unsigned.requestID,
            pairingID: unsigned.pairingID,
            projectID: unsigned.projectID,
            operation: unsigned.operation,
            issuedAt: unsigned.issuedAt,
            expiresAt: unsigned.expiresAt,
            nonce: unsigned.nonce,
            payload: unsigned.payload,
            payloadDigest: unsigned.payloadDigest,
            signature: signature
        )
    }

    private func assertBridgeError(
        _ expected: BridgeError,
        operation: () async throws -> Data
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? BridgeError, expected)
        }
    }
}

private final class MemoryBridgeStore: BridgeCredentialStoring, @unchecked Sendable {
    var value: BridgeCredential?

    init(value: BridgeCredential? = nil) {
        self.value = value
    }

    func load() throws -> BridgeCredential? { value }
    func save(_ credential: BridgeCredential) throws { value = credential }
    func delete() throws { value = nil }
}

private final class ThrowingSaveBridgeStore: BridgeCredentialStoring, @unchecked Sendable {
    var value: BridgeCredential?

    init(value: BridgeCredential?) { self.value = value }
    func load() throws -> BridgeCredential? { value }
    func save(_ credential: BridgeCredential) throws { throw BridgeError.keychain(errSecInteractionNotAllowed) }
    func delete() throws { value = nil }
}

private final class ToggleLoadBridgeStore: BridgeCredentialStoring, @unchecked Sendable {
    var value: BridgeCredential?
    var throwOnLoad = false

    init(value: BridgeCredential?) { self.value = value }
    func load() throws -> BridgeCredential? {
        if throwOnLoad { throw BridgeError.keychain(errSecInteractionNotAllowed) }
        return value
    }
    func save(_ credential: BridgeCredential) throws { value = credential }
    func delete() throws { value = nil }
}
