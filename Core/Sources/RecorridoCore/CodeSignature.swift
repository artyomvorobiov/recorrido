import Foundation
#if canImport(MachO)
import MachO
#endif

/// Reads entitlements from the app's own code signature.
///
/// CloudKit crashes the app when the iCloud entitlement is missing, and a
/// free Apple ID cannot sign with it. Checking the signature first lets the
/// community feed switch itself on only where it can work.
enum CodeSignature {
    /// Entitlements in a code signature SuperBlob (big-endian, as stored).
    static func entitlements(superBlob blob: UnsafeRawBufferPointer) -> [String: Any]? {
        func word(_ offset: Int) -> UInt32? {
            guard offset >= 0, offset + 4 <= blob.count else { return nil }
            return UInt32(bigEndian: blob.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
        guard word(0) == superBlobMagic, let count = word(8) else { return nil }
        for index in 0..<Int(min(count, 64)) {
            guard let type = word(12 + index * 8), let offset = word(16 + index * 8) else { return nil }
            guard type == entitlementsSlot else { continue }
            let start = Int(offset)
            guard word(start) == entitlementsMagic, let length = word(start + 4).map({ Int($0) }),
                  length > 8, start + length <= blob.count else { return nil }
            let data = Data(blob[(start + 8)..<(start + length)])
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        }
        return nil
    }

    /// iCloud containers the app may use with CloudKit, or none.
    static func cloudKitContainers(in entitlements: [String: Any]) -> [String] {
        guard let services = entitlements["com.apple.developer.icloud-services"] as? [String],
              services.contains(where: { $0.hasPrefix("CloudKit") }) else { return [] }
        return entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] ?? []
    }

    static let superBlobMagic: UInt32 = 0xfade0cc0
    static let entitlementsMagic: UInt32 = 0xfade7171
    static let entitlementsSlot: UInt32 = 5

    #if canImport(MachO)
    /// The entitlements of the running app (the main executable).
    static func current() -> [String: Any] {
        guard let header = _dyld_get_image_header(0) else { return [:] }
        let image = UnsafeRawPointer(header)
        #if targetEnvironment(simulator)
        // The simulator does not sign with entitlements; Xcode puts them in a section instead.
        if let simulated = sectionEntitlements(image: image) { return simulated }
        #endif
        guard let blob = superBlob(image: image, slide: _dyld_get_image_vmaddr_slide(0)) else { return [:] }
        return entitlements(superBlob: blob) ?? [:]
    }

    /// The code signature of a loaded 64-bit Mach-O image, found through its
    /// LC_CODE_SIGNATURE command inside the mapped __LINKEDIT segment.
    static func superBlob(image: UnsafeRawPointer, slide: Int) -> UnsafeRawBufferPointer? {
        let header = image.loadUnaligned(as: mach_header_64.self)
        guard header.magic == 0xfeedfacf else { return nil }
        var command = image + MemoryLayout<mach_header_64>.size
        var linkedit: segment_command_64?
        var signature: linkedit_data_command?
        for _ in 0..<min(header.ncmds, 512) {
            let load = command.loadUnaligned(as: load_command.self)
            if load.cmd == 0x19 /* LC_SEGMENT_64 */ {
                let segment = command.loadUnaligned(as: segment_command_64.self)
                if name(of: segment) == "__LINKEDIT" { linkedit = segment }
            } else if load.cmd == 0x1d /* LC_CODE_SIGNATURE */ {
                signature = command.loadUnaligned(as: linkedit_data_command.self)
            }
            guard load.cmdsize >= 8 else { return nil }
            command += Int(load.cmdsize)
        }
        guard let linkedit, let signature, signature.datasize > 12 else { return nil }
        let start = UInt64(signature.dataoff)
        let end = start + UInt64(signature.datasize)
        guard start >= linkedit.fileoff, end <= linkedit.fileoff + linkedit.filesize,
              end - linkedit.fileoff <= linkedit.vmsize else { return nil }
        let address = UInt64(bitPattern: Int64(slide)) &+ linkedit.vmaddr &+ (start - linkedit.fileoff)
        guard let pointer = UnsafeRawPointer(bitPattern: UInt(address)) else { return nil }
        return UnsafeRawBufferPointer(start: pointer, count: Int(signature.datasize))
    }

    private static func name(of segment: segment_command_64) -> String {
        withUnsafeBytes(of: segment.segname) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    #if targetEnvironment(simulator)
    private static func sectionEntitlements(image: UnsafeRawPointer) -> [String: Any]? {
        var size: UInt = 0
        let header = image.assumingMemoryBound(to: mach_header_64.self)
        guard let bytes = getsectiondata(header, "__TEXT", "__entitlements", &size), size > 0 else { return nil }
        let data = Data(bytes: bytes, count: Int(size))
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
    #endif
    #endif
}
