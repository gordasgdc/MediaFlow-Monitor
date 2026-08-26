import Foundation
import IOKit
import CryptoKit

/// Port byte-for-byte din DataMover/mac-native (`MachineID.swift`) — aceeași
/// proprietate IOKit, același SHA-512-prefix-6-bytes, același Base32, ca
/// orice cod generat de `sell.py --machine-id` pentru ecosistemul GDC să
/// funcționeze neschimbat și aici.
enum MachineID {
    private static func rawPlatformUUID() -> String {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        guard entry != 0 else { return "mac-machine-id-unavailable" }
        defer { IOObjectRelease(entry) }

        guard let cfValue = IORegistryEntryCreateCFProperty(entry, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0) else {
            return "mac-machine-id-unavailable"
        }
        let uuidRef = cfValue.takeRetainedValue()
        return (uuidRef as? String) ?? "mac-machine-id-unavailable"
    }

    static var hashBytes: [UInt8] {
        Array(SHA512.hash(data: Data(rawPlatformUUID().utf8)).prefix(6))
    }

    static var display: String {
        LicenseCore.base32Encode(Data(hashBytes))
    }
}
