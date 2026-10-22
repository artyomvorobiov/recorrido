import XCTest
@testable import RecorridoCore
#if canImport(MachO)
import MachO
#endif

final class CodeSignatureTests: XCTestCase {
    /// A SuperBlob like the one codesign writes: a code directory and an
    /// XML entitlements blob, everything big-endian.
    private func superBlob(entitlements: [String: Any]) throws -> Data {
        let plist = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
        var data = Data()
        func append(_ value: UInt32) {
            withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
        }
        let indexSize = 12 + 2 * 8
        let directoryOffset = indexSize
        let entitlementsOffset = directoryOffset + 8
        append(CodeSignature.superBlobMagic)
        append(UInt32(entitlementsOffset + 8 + plist.count))
        append(2)
        append(0)  // code directory slot
        append(UInt32(directoryOffset))
        append(CodeSignature.entitlementsSlot)
        append(UInt32(entitlementsOffset))
        append(0xfade0c02)  // a stub code directory
        append(8)
        append(CodeSignature.entitlementsMagic)
        append(UInt32(8 + plist.count))
        data.append(plist)
        return data
    }

    func testReadsCloudKitContainersFromTheSignature() throws {
        let blob = try superBlob(entitlements: [
            "com.apple.developer.icloud-services": ["CloudKit"],
            "com.apple.developer.icloud-container-identifiers": ["iCloud.app.recorrido"],
            "com.apple.security.application-groups": ["group.app.recorrido"],
        ])
        let entitlements = try XCTUnwrap(blob.withUnsafeBytes { CodeSignature.entitlements(superBlob: $0) })
        XCTAssertEqual(CodeSignature.cloudKitContainers(in: entitlements), ["iCloud.app.recorrido"])
    }

    func testNoICloudMeansNoContainers() throws {
        let blob = try superBlob(entitlements: ["com.apple.security.application-groups": ["group.app.recorrido"]])
        let entitlements = try XCTUnwrap(blob.withUnsafeBytes { CodeSignature.entitlements(superBlob: $0) })
        XCTAssertEqual(CodeSignature.cloudKitContainers(in: entitlements), [])
        XCTAssertEqual(CodeSignature.cloudKitContainers(in: [:]), [])
    }

    func testRejectsDamagedSignatures() throws {
        var blob = try superBlob(entitlements: ["a": "b"])
        XCTAssertNil(Data([1, 2, 3]).withUnsafeBytes { CodeSignature.entitlements(superBlob: $0) })
        blob.removeLast(40)  // the entitlements blob now runs past the end
        XCTAssertNil(blob.withUnsafeBytes { CodeSignature.entitlements(superBlob: $0) })
    }

    #if canImport(MachO)
    /// SwiftPM signs test bundles ad hoc, so this bundle has a real signature to find.
    func testFindsTheSignatureOfALoadedImage() throws {
        var checked = false
        for index in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(index).map({ String(cString: $0) }),
                  name.contains("RecorridoCorePackageTests"),
                  let header = _dyld_get_image_header(index) else { continue }
            let blob = try XCTUnwrap(CodeSignature.superBlob(image: UnsafeRawPointer(header),
                                                             slide: _dyld_get_image_vmaddr_slide(index)))
            XCTAssertEqual(UInt32(bigEndian: blob.loadUnaligned(as: UInt32.self)), CodeSignature.superBlobMagic)
            checked = true
        }
        try XCTSkipUnless(checked, "the test bundle image was not found")
        _ = CodeSignature.current()  // must not crash on a real process
    }
    #endif
}
