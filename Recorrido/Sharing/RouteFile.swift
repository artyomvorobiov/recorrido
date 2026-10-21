import CoreImage.CIFilterBuiltins
import CoreTransferable
import UIKit
import UniformTypeIdentifiers

extension UTType {
    /// A route file (`.recorrido`), declared in Info.plist.
    static let recorridoRoute = UTType(exportedAs: "app.recorrido.route", conformingTo: .json)
}

/// A route as a file to send with AirDrop, Messages, Telegram…
struct RouteFile: Transferable {
    var route: Route

    private struct Envelope: Codable {
        var recorrido: Int
        var route: Route
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .recorridoRoute) { file in
            SentTransferredFile(try file.writeTemporaryFile())
        }
    }

    func writeTemporaryFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Shared routes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = route.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let url = folder.appendingPathComponent(name.isEmpty ? "Route" : name).appendingPathExtension("recorrido")
        var shared = route
        shared.source = .imported
        try JSONCoders.encoder.encode(Envelope(recorrido: 1, route: shared)).write(to: url, options: .atomic)
        return url
    }

    /// Reads a received file. The route gets a new identity.
    static func read(from url: URL) throws -> Route {
        let data = try Data(contentsOf: url)
        let decoder = JSONCoders.decoder
        var route: Route
        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            route = envelope.route
        } else {
            route = try decoder.decode(Route.self, from: data)
        }
        let original = route.originID ?? route.id
        route = route.userCopy()
        route.source = .imported
        route.originID = original
        return route
    }
}

enum QRCode {
    /// A crisp QR code, or `nil` when the text is too long to fit.
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let image = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}
