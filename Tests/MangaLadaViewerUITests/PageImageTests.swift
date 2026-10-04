import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
private final class PageImageTests {
    func testReleasePreservesGeometryAndReloadsOriginalPixels() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try Data(contentsOf: fixture.portrait)
        let state = PageImageState()
        await state.load(fixture.portrait, maximumPixels: 100)
        try check(state.sourceSize == CGSize(width: 60, height: 100))
        try check(state.image != nil)
        let size = state.sourceSize
        let initialPixels = try require(state.image?.tiffRepresentation)
        weak var retainedImage = state.image
        state.release()
        state.release()
        try check(state.image == nil)
        try check(retainedImage == nil)
        try check(state.sourceSize == size)
        try check(state.failure == nil)
        await state.load(fixture.portrait, maximumPixels: 100)
        try check(state.sourceSize == size)
        let image = try require(state.image)
        try check(image.tiffRepresentation == initialPixels)
        try check(try Data(contentsOf: fixture.portrait) == original)
    }

    func testNewURLReplacesImageAndAspectRatio() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let state = PageImageState()
        await state.load(fixture.portrait, maximumPixels: 100)
        await state.load(fixture.landscape, maximumPixels: 100)
        try check(state.sourceSize == CGSize(width: 100, height: 50))
        try check(state.image?.size == CGSize(width: 100, height: 50))
        try check(state.failure == nil)
    }

    func testCorruptAndMissingFilesNeverKeepPreviousImage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let state = PageImageState()
        await state.load(fixture.portrait, maximumPixels: 100)
        let corrupt = fixture.folder.appendingPathComponent("corrupt.png")
        try Data([0, 1, 2]).write(to: corrupt)
        for url in [corrupt, fixture.folder.appendingPathComponent("missing.png")] {
            await state.load(url, maximumPixels: 100)
            try check(state.image == nil)
            try check(state.sourceSize == nil)
            try check(state.failure != nil)
        }
        await state.load(fixture.portrait, maximumPixels: 100)
        try check(state.image != nil)
        try check(state.failure == nil)
    }

    func testCancelledLoadDoesNotPublishImageOrFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let state = PageImageState()
        let task = Task { await state.load(fixture.portrait, maximumPixels: 100) }
        task.cancel()
        await task.value
        try check(state.image == nil)
        try check(state.failure == nil)
    }

    func testDecoderBoundsPixelsAndSupportsOnePixelImage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let landscape = try await PageImageLoader.load(fixture.landscape, maximumPixels: 30)
        try check(landscape.width == 30 && landscape.height == 15)
        let single = fixture.folder.appendingPathComponent("single.png")
        try fixture.write(single, width: 1, height: 1)
        let pixel = try await PageImageLoader.load(single, maximumPixels: 240)
        try check(pixel.width == 1 && pixel.height == 1)
    }

    private struct Fixture {
        let folder: URL
        var portrait: URL { folder.appendingPathComponent("portrait.png") }
        var landscape: URL { folder.appendingPathComponent("landscape.png") }
        init() throws {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("page-image-tests-\(UUID())")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try write(portrait, width: 120, height: 200)
            try write(landscape, width: 600, height: 300)
        }
        func write(_ url: URL, width: Int, height: Int) throws {
            let context = try require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let destination = try require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, try require(context.makeImage()), nil)
            try check(CGImageDestinationFinalize(destination))
        }
        func remove() {
            do { try FileManager.default.removeItem(at: folder) }
            catch { fatalError("Fixture cleanup failed: \(error)") }
        }
    }
}

@main
struct PageImageChecks {
    @MainActor static func main() async throws {
        let tests = PageImageTests()
        try await tests.testReleasePreservesGeometryAndReloadsOriginalPixels()
        try await tests.testNewURLReplacesImageAndAspectRatio()
        try await tests.testCorruptAndMissingFilesNeverKeepPreviousImage()
        try await tests.testCancelledLoadDoesNotPublishImageOrFailure()
        try await tests.testDecoderBoundsPixelsAndSupportsOnePixelImage()
        print("Page image checks passed: release/reload, geometry, source preservation, URL changes, corrupt/missing input, cancellation, pixel bounds")
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func check(_ condition: @autoclosure () throws -> Bool, line: UInt = #line) throws {
    guard try condition() else { throw CheckFailure(description: "Page image check failed at line \(line)") }
}

private func require<Value>(_ value: Value?, line: UInt = #line) throws -> Value {
    guard let value else { throw CheckFailure(description: "Missing expected value at line \(line)") }
    return value
}
