import AppKit
import XCTest
@testable import Octava

/// Pegar carátula: se usa un portapapeles propio de la prueba (no se toca el del usuario).
final class ArtworkImportTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("octava-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
    }

    private func image(size: Int = 64) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        image.unlockFocus()
        return image
    }

    private func png() -> Data {
        let rep = NSBitmapImageRep(data: image().tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testPastedPNGIsUsedAsIs() throws {
        pasteboard.setData(png(), forType: .png)
        let data = try XCTUnwrap(ArtworkImport.imageData(from: pasteboard))
        let artwork = try XCTUnwrap(ArtworkImport.prepare(data))
        XCTAssertEqual(artwork.mimeType, "image/png")
    }

    func testPastedTIFFBecomesJPEG() throws {
        // Safari y Vista Previa copian TIFF.
        pasteboard.setData(image().tiffRepresentation!, forType: .tiff)
        let data = try XCTUnwrap(ArtworkImport.imageData(from: pasteboard))
        let artwork = try XCTUnwrap(ArtworkImport.prepare(data))
        XCTAssertEqual(artwork.mimeType, "image/jpeg")
    }

    func testCopiedImageAddressIsDetected() {
        pasteboard.setString("https://example.com/cover.jpg", forType: .string)
        XCTAssertNil(ArtworkImport.imageData(from: pasteboard))
        XCTAssertEqual(ArtworkImport.webImageURL(from: pasteboard)?.absoluteString, "https://example.com/cover.jpg")
    }

    func testTextIsNotAnImage() {
        pasteboard.setString("Walls Of Jericho", forType: .string)
        XCTAssertNil(ArtworkImport.imageData(from: pasteboard))
        XCTAssertNil(ArtworkImport.webImageURL(from: pasteboard))
    }
}
