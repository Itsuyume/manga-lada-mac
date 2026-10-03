import Foundation

indirect enum ModelResponseSchema: Encodable, Sendable {
    case object(properties: [String: Self], required: [String])
    case array(items: Self, minimum: Int, maximum: Int)
    case string(choices: [String]?)
    case integer(minimum: Int, maximum: Int)
    case number(minimum: Double, maximum: Double)
    private enum Key: String, CodingKey { case type, properties, required, additionalProperties, items, minItems, maxItems, minimum, maximum; case choices = "enum" }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .object(let properties, let required):
            try container.encode("object", forKey: .type); try container.encode(properties, forKey: .properties)
            try container.encode(required, forKey: .required); try container.encode(false, forKey: .additionalProperties)
        case .array(let items, let minimum, let maximum):
            try container.encode("array", forKey: .type); try container.encode(items, forKey: .items)
            try container.encode(minimum, forKey: .minItems); try container.encode(maximum, forKey: .maxItems)
        case .string(let choices):
            try container.encode("string", forKey: .type); try container.encodeIfPresent(choices, forKey: .choices)
        case .integer(let minimum, let maximum):
            try container.encode("integer", forKey: .type); try container.encode(minimum, forKey: .minimum); try container.encode(maximum, forKey: .maximum)
        case .number(let minimum, let maximum):
            try container.encode("number", forKey: .type); try container.encode(minimum, forKey: .minimum); try container.encode(maximum, forKey: .maximum)
        }
    }
    static func page(count: Int) -> Self {
        let item = Self.object(properties: ["id": .integer(minimum: 0, maximum: max(0, count - 1)),
                                            "text": .string(choices: nil),
                                            "kind": .string(choices: ["dialogue", "caption", "soundEffect"])], required: ["id", "text", "kind"])
        return .object(properties: ["translations": .array(items: item, minimum: count, maximum: count)], required: ["translations"])
    }
    static let soundEffects: Self = .object(properties: ["regions": .array(items: .object(properties: [
        "text": .string(choices: nil), "x": .number(minimum: 0, maximum: 1000), "y": .number(minimum: 0, maximum: 1000),
        "width": .number(minimum: 1, maximum: 1000), "height": .number(minimum: 1, maximum: 1000)
    ], required: ["text", "x", "y", "width", "height"]), minimum: 0, maximum: 40)], required: ["regions"])
}
