import Foundation
import CryptoKit

/// Port byte-for-byte din DataMover/mac-native (`LicenseCore.swift`) —
/// ACEEAȘI cheie publică Ed25519 hardcodată în tot ecosistemul GDC, ca un
/// cod generat din `GenerateSerialView.swift` (Furnizor) pentru
/// `media-flow-monitor` să fie verificat identic aici. Doar cheia PUBLICĂ —
/// cheia privată de semnare rămâne exclusiv pe mașina lui Cristi.
enum LicenseCore {
    struct Payload {
        let expiresAt: Int64 // unix seconds, 0 = never expires
        let machineLocked: Bool
    }

    enum ValidationError: Error {
        case malformedCode
        case badSignature
        case wrongProduct
        case wrongMachine
        case expired(Int64)
    }

    private static let publicKeyBase64 = "I1h23MNMRbOhc0ObKJrfa3oFHKA9w+SzbNrroAIy8hs="
    private static let payloadSize = 22

    static func validate(serial: String, expectedProductID: String) -> Result<Payload, ValidationError> {
        guard let packed = base32Decode(serial), packed.count == payloadSize + 64 else {
            return .failure(.malformedCode)
        }
        let payloadBytes = packed.prefix(payloadSize)
        let signature = packed.suffix(64)

        guard let publicKeyData = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            return .failure(.malformedCode)
        }
        guard publicKey.isValidSignature(signature, for: payloadBytes) else {
            return .failure(.badSignature)
        }

        let bytes = Array(payloadBytes)
        let storedProductHash = bytes[0..<4]
        let expectedProductHash = productHash(for: expectedProductID)
        guard Array(storedProductHash) == expectedProductHash else {
            return .failure(.wrongProduct)
        }

        var expiresAt: Int64 = 0
        for i in 4..<12 { expiresAt = (expiresAt << 8) | Int64(bytes[i]) }

        let storedMachineHash = Array(bytes[16..<22])
        let isMachineLocked = storedMachineHash.contains { $0 != 0 }
        if isMachineLocked {
            guard storedMachineHash == MachineID.hashBytes else {
                return .failure(.wrongMachine)
            }
        }

        if expiresAt != 0 && expiresAt < Int64(Date().timeIntervalSince1970) {
            return .failure(.expired(expiresAt))
        }
        return .success(Payload(expiresAt: expiresAt, machineLocked: isMachineLocked))
    }

    private static func productHash(for productID: String) -> [UInt8] {
        Array(SHA512.hash(data: Data(productID.utf8)).prefix(4))
    }

    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func base32Encode(_ data: Data) -> String {
        var bits = 0, value = 0
        var output = ""
        for byte in data {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                output.append(base32Alphabet[(value >> (bits - 5)) & 0x1F])
                bits -= 5
            }
        }
        if bits > 0 {
            output.append(base32Alphabet[(value << (5 - bits)) & 0x1F])
        }
        return output
    }

    private static func base32Decode(_ string: String) -> Data? {
        let cleaned = string.uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "=", with: "")
        var bits = 0, value = 0
        var output = [UInt8]()
        for char in cleaned {
            guard let index = base32Alphabet.firstIndex(of: char) else { return nil }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                output.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return Data(output)
    }
}
