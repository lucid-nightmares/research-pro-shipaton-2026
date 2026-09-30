import CryptoKit
import Foundation
import Security

enum BridgeScope: String, Codable, CaseIterable, Sendable {
    case researchRead = "research:read"
    case researchPropose = "research:propose"
    case artifactsRead = "artifacts:read"
    case syncPropose = "sync:propose"
    case modelPropose = "model:propose"
}

enum BridgeOperation: String, Codable, Sendable {
    case projectSnapshot = "project.snapshot"
    case eventProposal = "event.proposal"
    case conflictPreview = "sync.conflict-preview"
    case artifactManifest = "artifact.manifest"
    case modelProposal = "model.proposal"

    var requiredScope: BridgeScope {
        switch self {
        case .projectSnapshot: .researchRead
        case .eventProposal: .researchPropose
        case .conflictPreview: .syncPropose
        case .artifactManifest: .artifactsRead
        case .modelProposal: .modelPropose
        }
    }
}

struct BridgePairingOffer: Codable, Equatable, Sendable {
    let schemaVersion: String
    let pairingID: String
    let desktopName: String
    let desktopPublicKey: Data
    let projects: [String]
    let scopes: [BridgeScope]
    let expiresAt: Date

    init(
        pairingID: String,
        desktopName: String,
        desktopPublicKey: Data,
        projects: [String],
        scopes: [BridgeScope],
        expiresAt: Date
    ) {
        self.schemaVersion = "research-os.mobile.bridge-pairing-offer.v1"
        self.pairingID = pairingID
        self.desktopName = desktopName
        self.desktopPublicKey = desktopPublicKey
        self.projects = projects.sorted()
        self.scopes = scopes.sorted { $0.rawValue < $1.rawValue }
        self.expiresAt = expiresAt
    }
}

struct BridgePairingResponse: Codable, Equatable, Sendable {
    let schemaVersion: String
    let pairingID: String
    let deviceID: String
    let deviceName: String
    let devicePublicKey: Data
    let offerDigest: String
    let proof: String

    init(
        pairingID: String,
        deviceID: String,
        deviceName: String,
        devicePublicKey: Data,
        offerDigest: String,
        proof: String
    ) {
        self.schemaVersion = "research-os.mobile.bridge-pairing-response.v1"
        self.pairingID = pairingID
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.devicePublicKey = devicePublicKey
        self.offerDigest = offerDigest
        self.proof = proof
    }
}

struct BridgeCredential: Codable, Equatable, Sendable {
    let schemaVersion: String
    let pairingID: String
    let desktopName: String
    let projects: [String]
    let scopes: [BridgeScope]
    let expiresAt: Date
    let keyMaterial: Data
    let usedNonces: [String: Date]
    let revoked: Bool

    init(
        pairingID: String,
        desktopName: String,
        projects: [String],
        scopes: [BridgeScope],
        expiresAt: Date,
        keyMaterial: Data,
        usedNonces: [String: Date] = [:],
        revoked: Bool = false
    ) {
        self.schemaVersion = "research-os.mobile.bridge-credential.v1"
        self.pairingID = pairingID
        self.desktopName = desktopName
        self.projects = projects.sorted()
        self.scopes = scopes.sorted { $0.rawValue < $1.rawValue }
        self.expiresAt = expiresAt
        self.keyMaterial = keyMaterial
        self.usedNonces = usedNonces
        self.revoked = revoked
    }
}

struct BridgeEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: String
    let requestID: String
    let pairingID: String
    let projectID: String
    let operation: BridgeOperation
    let issuedAt: Date
    let expiresAt: Date
    let nonce: String
    let payload: Data
    let payloadDigest: String
    let signature: String

    init(
        requestID: String,
        pairingID: String,
        projectID: String,
        operation: BridgeOperation,
        issuedAt: Date,
        expiresAt: Date,
        nonce: String,
        payload: Data,
        payloadDigest: String,
        signature: String
    ) {
        self.schemaVersion = "research-os.mobile.bridge-envelope.v1"
        self.requestID = requestID
        self.pairingID = pairingID
        self.projectID = projectID
        self.operation = operation
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.nonce = nonce
        self.payload = payload
        self.payloadDigest = payloadDigest
        self.signature = signature
    }

    var signingDocument: BridgeSigningDocument {
        BridgeSigningDocument(
            schemaVersion: schemaVersion,
            requestID: requestID,
            pairingID: pairingID,
            projectID: projectID,
            operation: operation,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            nonce: nonce,
            payloadDigest: payloadDigest
        )
    }
}

struct BridgeSigningDocument: Codable, Sendable {
    let schemaVersion: String
    let requestID: String
    let pairingID: String
    let projectID: String
    let operation: BridgeOperation
    let issuedAt: Date
    let expiresAt: Date
    let nonce: String
    let payloadDigest: String
}

struct QuarantinedModelProposal: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let projectID: String
    let targetObjectID: String
    let promptDigest: String
    let content: String
    let contentDigest: String
    let modelReceiptDigest: String
    let receivedAt: Date

    var classification: String { "PROPOSAL_ONLY" }

    init(
        id: String,
        projectID: String,
        targetObjectID: String,
        promptDigest: String,
        content: String,
        contentDigest: String,
        modelReceiptDigest: String,
        receivedAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.targetObjectID = targetObjectID
        self.promptDigest = promptDigest
        self.content = content
        self.contentDigest = contentDigest
        self.modelReceiptDigest = modelReceiptDigest
        self.receivedAt = receivedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, projectID, targetObjectID, promptDigest, content
        case contentDigest, modelReceiptDigest, classification, receivedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let encodedClassification = try values.decode(String.self, forKey: .classification)
        guard encodedClassification == "PROPOSAL_ONLY" else {
            throw DecodingError.dataCorruptedError(
                forKey: .classification,
                in: values,
                debugDescription: "A model result must remain proposal-only."
            )
        }
        self.init(
            id: try values.decode(String.self, forKey: .id),
            projectID: try values.decode(String.self, forKey: .projectID),
            targetObjectID: try values.decode(String.self, forKey: .targetObjectID),
            promptDigest: try values.decode(String.self, forKey: .promptDigest),
            content: try values.decode(String.self, forKey: .content),
            contentDigest: try values.decode(String.self, forKey: .contentDigest),
            modelReceiptDigest: try values.decode(String.self, forKey: .modelReceiptDigest),
            receivedAt: try values.decode(Date.self, forKey: .receivedAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(projectID, forKey: .projectID)
        try values.encode(targetObjectID, forKey: .targetObjectID)
        try values.encode(promptDigest, forKey: .promptDigest)
        try values.encode(content, forKey: .content)
        try values.encode(contentDigest, forKey: .contentDigest)
        try values.encode(modelReceiptDigest, forKey: .modelReceiptDigest)
        try values.encode(classification, forKey: .classification)
        try values.encode(receivedAt, forKey: .receivedAt)
    }
}

protocol BridgeCredentialStoring: Sendable {
    func load() throws -> BridgeCredential?
    func save(_ credential: BridgeCredential) throws
    func delete() throws
}

struct KeychainBridgeCredentialStore: BridgeCredentialStoring {
    private let service: String
    private let account: String

    init(
        service: String = "org.researchos.flight-recorder.bridge",
        account: String = "paired-desktop"
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> BridgeCredential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw BridgeError.keychain(status)
        }
        return try BridgeCodec.decoder.decode(BridgeCredential.self, from: data)
    }

    func save(_ credential: BridgeCredential) throws {
        let data = try BridgeCodec.encoder.encode(credential)
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var insert = baseQuery
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else { throw BridgeError.keychain(added) }
        } else if status != errSecSuccess {
            throw BridgeError.keychain(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BridgeError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

actor ResearchOSBridge {
    private let store: any BridgeCredentialStoring
    private let now: @Sendable () -> Date
    private let targetBelongsToProject: @Sendable (String, String) -> Bool
    private var credential: BridgeCredential?
    private var revoked = false

    init(
        store: any BridgeCredentialStoring = KeychainBridgeCredentialStore(),
        now: @escaping @Sendable () -> Date = { Date() },
        targetBelongsToProject: @escaping @Sendable (String, String) -> Bool = { _, _ in false }
    ) {
        self.store = store
        self.now = now
        self.targetBelongsToProject = targetBelongsToProject
    }

    func restore() throws -> BridgeCredential? {
        credential = nil
        revoked = true
        let loaded = try store.load()
        if let loaded, loaded.revoked {
            credential = nil
            revoked = true
            return nil
        }
        if let loaded, Self.validCredential(loaded, at: now()) {
            let pruned = loaded.usedNonces.filter { $0.value > now() }
            let restored = BridgeCredential(
                pairingID: loaded.pairingID,
                desktopName: loaded.desktopName,
                projects: loaded.projects,
                scopes: loaded.scopes,
                expiresAt: loaded.expiresAt,
                keyMaterial: loaded.keyMaterial,
                usedNonces: pruned,
                revoked: false
            )
            if pruned != loaded.usedNonces { try store.save(restored) }
            credential = restored
            revoked = false
            return restored
        }
        if loaded != nil { try store.delete() }
        revoked = false
        return nil
    }

    func acceptPairing(
        offer: BridgePairingOffer,
        code: String,
        deviceID: String,
        deviceName: String
    ) throws -> BridgePairingResponse {
        let current = now()
        let uniqueProjects = Set(offer.projects)
        let uniqueScopes = Set(offer.scopes)
        guard offer.schemaVersion == "research-os.mobile.bridge-pairing-offer.v1",
              offer.expiresAt > current,
              offer.expiresAt.timeIntervalSince(current) <= 600,
              (1...32).contains(offer.projects.count),
              uniqueProjects.count == offer.projects.count,
              offer.projects.allSatisfy({ Self.validID($0) }),
              (1...BridgeScope.allCases.count).contains(offer.scopes.count),
              uniqueScopes.count == offer.scopes.count,
              (16...256).contains(code.utf8.count),
              Self.validID(offer.pairingID),
              Self.validID(deviceID),
              (1...120).contains(deviceName.trimmingCharacters(in: .whitespacesAndNewlines).count),
              (1...120).contains(offer.desktopName.trimmingCharacters(in: .whitespacesAndNewlines).count) else {
            throw BridgeError.invalidPairingOffer
        }
        let desktopKey: P256.KeyAgreement.PublicKey
        do {
            desktopKey = try P256.KeyAgreement.PublicKey(rawRepresentation: offer.desktopPublicKey)
        } catch {
            throw BridgeError.invalidDesktopKey
        }
        let deviceKey = P256.KeyAgreement.PrivateKey()
        let secret = try deviceKey.sharedSecretFromKeyAgreement(with: desktopKey)
        let key = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(code.utf8),
            sharedInfo: Data("research-os-mobile-pairing-v1".utf8),
            outputByteCount: 32
        )
        let keyData = key.withUnsafeBytes { Data($0) }
        let offerData = try BridgeCodec.encoder.encode(offer)
        let offerDigest = BridgeCodec.sha256(offerData)
        let proof = BridgeCodec.hmac(
            key: key,
            data: Data("pairing-response-v1\0\(offerDigest)\0\(deviceID)".utf8)
        )
        let created = BridgeCredential(
            pairingID: offer.pairingID,
            desktopName: offer.desktopName,
            projects: offer.projects,
            scopes: offer.scopes,
            expiresAt: offer.expiresAt,
            keyMaterial: keyData
        )
        try store.save(created)
        credential = created
        revoked = false
        return BridgePairingResponse(
            pairingID: offer.pairingID,
            deviceID: deviceID,
            deviceName: deviceName,
            devicePublicKey: deviceKey.publicKey.rawRepresentation,
            offerDigest: offerDigest,
            proof: proof
        )
    }

    func authorizeData(_ envelope: BridgeEnvelope) throws -> Data {
        guard envelope.operation != .modelProposal else { throw BridgeError.invalidModelProposal }
        return try authorizePayload(envelope)
    }

    private func authorizePayload(_ envelope: BridgeEnvelope) throws -> Data {
        let current = now()
        guard !revoked, let credential else { throw BridgeError.notPaired }
        guard envelope.schemaVersion == "research-os.mobile.bridge-envelope.v1",
              Self.validID(envelope.requestID),
              Self.validID(envelope.pairingID),
              Self.validID(envelope.projectID),
              Self.validID(envelope.nonce),
              envelope.payload.count <= 1_048_576 else {
            throw BridgeError.invalidEnvelope
        }
        guard BridgeCodec.sha256(envelope.payload) == envelope.payloadDigest else {
            throw BridgeError.payloadDigestMismatch
        }
        let document = try BridgeCodec.encoder.encode(envelope.signingDocument)
        let key = SymmetricKey(data: credential.keyMaterial)
        guard BridgeCodec.verifyHMAC(key: key, data: document, hexadecimalCode: envelope.signature) else {
            throw BridgeError.invalidSignature
        }
        guard envelope.pairingID == credential.pairingID else { throw BridgeError.invalidEnvelope }
        guard credential.expiresAt > current,
              envelope.issuedAt <= current.addingTimeInterval(300),
              envelope.expiresAt > current,
              envelope.expiresAt.timeIntervalSince(envelope.issuedAt) <= 300 else {
            throw BridgeError.expired
        }
        guard credential.projects.contains(envelope.projectID) else { throw BridgeError.crossProject }
        guard credential.scopes.contains(envelope.operation.requiredScope) else { throw BridgeError.missingScope }
        guard credential.usedNonces[envelope.nonce] == nil else { throw BridgeError.replay }
        var nonces = credential.usedNonces.filter { $0.value > current }
        guard nonces.count < 2_048 else { throw BridgeError.replayLedgerFull }
        nonces[envelope.nonce] = envelope.expiresAt
        let updated = BridgeCredential(
            pairingID: credential.pairingID,
            desktopName: credential.desktopName,
            projects: credential.projects,
            scopes: credential.scopes,
            expiresAt: credential.expiresAt,
            keyMaterial: credential.keyMaterial,
            usedNonces: nonces,
            revoked: false
        )
        try store.save(updated)
        self.credential = updated
        return envelope.payload
    }

    func authorizeModelProposal(_ envelope: BridgeEnvelope) throws -> QuarantinedModelProposal {
        guard envelope.operation == .modelProposal else { throw BridgeError.invalidEnvelope }
        let payload = try authorizePayload(envelope)
        let proposal = try BridgeCodec.decoder.decode(QuarantinedModelProposal.self, from: payload)
        guard proposal.projectID == envelope.projectID,
              Self.validID(proposal.id),
              Self.validID(proposal.targetObjectID),
              targetBelongsToProject(envelope.projectID, proposal.targetObjectID),
              proposal.content.utf8.count <= 262_144,
              Self.validDigest(proposal.promptDigest),
              Self.validDigest(proposal.contentDigest),
              Self.validDigest(proposal.modelReceiptDigest),
              BridgeCodec.sha256(Data(proposal.content.utf8)) == proposal.contentDigest else {
            throw BridgeError.invalidModelProposal
        }
        return proposal
    }

    func revoke() throws {
        revoked = true
        let existing: BridgeCredential?
        do {
            if let credential {
                existing = credential
            } else {
                existing = try store.load()
            }
        } catch {
            credential = nil
            throw error
        }
        credential = nil
        if let existing {
            let tombstone = BridgeCredential(
                pairingID: existing.pairingID,
                desktopName: existing.desktopName,
                projects: existing.projects,
                scopes: existing.scopes,
                expiresAt: Date(timeIntervalSince1970: 0),
                keyMaterial: Data(repeating: 0, count: 32),
                usedNonces: [:],
                revoked: true
            )
            do {
                // Keep the tombstone durable. A later explicit pairing may
                // replace it, but ordinary restore can never revive this key.
                try store.save(tombstone)
            } catch {
                // If secure overwrite is unavailable, removal is the only
                // safe fallback. Failure of both operations is surfaced while
                // this actor remains revoked in memory.
                do { try store.delete() }
                catch { throw error }
            }
        }
    }

    private static func validID(_ value: String) -> Bool {
        (1...200).contains(value.utf8.count) &&
        value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:")).contains($0)
        }
    }

    private static func validDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private static func validCredential(_ value: BridgeCredential, at current: Date) -> Bool {
        value.schemaVersion == "research-os.mobile.bridge-credential.v1" &&
        !value.revoked &&
        value.keyMaterial.count == 32 &&
        value.expiresAt > current &&
        validID(value.pairingID) &&
        (1...120).contains(value.desktopName.trimmingCharacters(in: .whitespacesAndNewlines).count) &&
        (1...32).contains(value.projects.count) &&
        Set(value.projects).count == value.projects.count &&
        value.projects.allSatisfy(validID) &&
        (1...BridgeScope.allCases.count).contains(value.scopes.count) &&
        Set(value.scopes).count == value.scopes.count &&
        value.usedNonces.count <= 2_048 &&
        value.usedNonces.allSatisfy { validID($0.key) && $0.value <= value.expiresAt }
    }
}

enum BridgeError: LocalizedError, Equatable {
    case invalidPairingOffer
    case invalidDesktopKey
    case notPaired
    case expired
    case crossProject
    case missingScope
    case replay
    case replayLedgerFull
    case payloadDigestMismatch
    case invalidSignature
    case invalidEnvelope
    case invalidModelProposal
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidPairingOffer: "The pairing offer is malformed, expired, or too broad."
        case .invalidDesktopKey: "The desktop pairing key is invalid."
        case .notPaired: "This device is not paired with a Research OS desktop."
        case .expired: "The pairing credential or request has expired."
        case .crossProject: "The desktop request is outside the paired project scope."
        case .missingScope: "The desktop request needs a scope that was not granted."
        case .replay: "This desktop request was already used."
        case .replayLedgerFull: "The one-use request ledger is full; pair again before accepting another request."
        case .payloadDigestMismatch: "The desktop payload changed after it was signed."
        case .invalidSignature: "The desktop request signature is invalid."
        case .invalidEnvelope: "The desktop request envelope is invalid."
        case .invalidModelProposal: "The model proposal is malformed or not bound to this project."
        case .keychain(let status): "The paired credential could not be stored securely (\(status))."
        }
    }
}

enum BridgeCodec {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hmac(key: SymmetricKey, data: Data) -> String {
        HMAC<SHA256>.authenticationCode(for: data, using: key)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func verifyHMAC(key: SymmetricKey, data: Data, hexadecimalCode: String) -> Bool {
        guard hexadecimalCode.count == 64 else { return false }
        var bytes = [UInt8]()
        bytes.reserveCapacity(32)
        var index = hexadecimalCode.startIndex
        for _ in 0..<32 {
            let next = hexadecimalCode.index(index, offsetBy: 2)
            guard let byte = UInt8(hexadecimalCode[index..<next], radix: 16) else { return false }
            bytes.append(byte)
            index = next
        }
        return HMAC<SHA256>.isValidAuthenticationCode(bytes, authenticating: data, using: key)
    }
}
