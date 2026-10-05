import Foundation

public struct OllamaSoundEffectDetector: Sendable {
    private let client: OllamaChatClient
    public init(configuration: OllamaConfiguration = OllamaConfiguration(model: OllamaConfiguration.visionModel), session: URLSession = .shared) {
        client = OllamaChatClient(configuration: configuration, session: session)
    }
    public func recognize(imageData: Data) async throws -> [TextBlock] {
        return try await client.validated(system: "You detect printed Japanese sound effects in manga. Return only the requested JSON object.",
            user: """
            Read Japanese SOUND EFFECTS on the page, including effects in colored decorative enclosures as well as outside balloons. Do not include spoken exclamations, ordinary dialogue, faces or objects. A frame or colored background alone does not make an effect dialogue.
            Return {"regions":[{"text":"Japanese original","x":0,"y":0,"width":0,"height":0}]}.
            Coordinates are 0 to 1000 relative to the full image, origin top left. Give tight rectangles around the characters, not entire panels.
            If no sound effect return {"regions":[]}.
            Each region must be a complete object with all five fields. Do not include angles or separate metadata objects.
            """, schema: .soundEffects, images: [imageData], outputTokens: 2048, decode: Self.decode)
    }
    public static func decode(_ data: Data) throws -> [TextBlock] {
        let regions: [Region]
        do {
            // Locally observed Qwen replies use both the schema envelope and a bare region array.
            // Normalize that boundary shape only; every item still requires valid text and geometry.
            let isArray = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")
            regions = isArray ? try JSONDecoder().decode([Region].self, from: data)
                              : try JSONDecoder().decode(Response.self, from: data).regions
        }
        catch { throw TranslationError.invalidPageResponse("효과음 좌표 응답을 읽지 못했습니다: \(String(decoding: data.prefix(1000), as: UTF8.self))") }
        guard regions.count <= 40 else { throw TranslationError.invalidPageResponse("효과음 영역이 지나치게 많습니다.") }
        return try regions.map { region in
            let text = region.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 150, region.x.isFinite, region.y.isFinite,
                  region.width.isFinite, region.height.isFinite, (region.angle ?? 0).isFinite,
                  region.x >= 0, region.y >= 0, region.width > 0, region.height > 0,
                  region.x + region.width <= 1000, region.y + region.height <= 1000, abs(region.angle ?? 0) <= 90 else {
                throw TranslationError.invalidPageResponse("효과음 좌표 또는 원문이 올바르지 않습니다.")
            }
            return TextBlock(box: TextBox(x: region.x / 1000, y: region.y / 1000,
                                          width: region.width / 1000, height: region.height / 1000),
                             originalText: text, confidence: 0.6, sourceIsVertical: region.height > region.width * 2,
                             textKind: .soundEffect, rotationDegrees: region.angle)
        }
    }
    private struct Response: Decodable { let regions: [Region] }
    /// Qwen vision replies observed in the local runtime use either x/y or x_min/y_min.
    /// Normalize that external contract here; the rest of the app only uses TextBox.
    private struct Region: Decodable {
        let text: String; let x: Double; let y: Double; let width: Double; let height: Double; let angle: Double?
        private enum Key: String, CodingKey { case text, x, y, width, height, angle; case xMin = "x_min"; case yMin = "y_min" }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            text = try container.decode(String.self, forKey: .text)
            x = try Self.coordinate(.x, alias: .xMin, in: container)
            y = try Self.coordinate(.y, alias: .yMin, in: container)
            width = try container.decode(Double.self, forKey: .width); height = try container.decode(Double.self, forKey: .height)
            angle = try container.decodeIfPresent(Double.self, forKey: .angle)
        }
        private static func coordinate(_ key: Key, alias: Key, in container: KeyedDecodingContainer<Key>) throws -> Double {
            let primary = try container.decodeIfPresent(Double.self, forKey: key)
            let alternate = try container.decodeIfPresent(Double.self, forKey: alias)
            if let primary, let alternate, primary != alternate { throw TranslationError.invalidPageResponse("효과음 좌표가 서로 모순됩니다.") }
            if let value = primary ?? alternate { return value }
            throw TranslationError.invalidPageResponse("효과음 좌표가 없습니다.")
        }
    }
}
