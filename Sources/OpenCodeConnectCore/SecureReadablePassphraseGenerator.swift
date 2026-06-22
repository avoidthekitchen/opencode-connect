import Foundation

/// Produces six pronounceable words with 72 bits of entropy using the system CSPRNG.
public struct SecureReadablePassphraseGenerator: PassphraseGenerating {
    public init() {}

    public func generate() throws -> String {
        var random = SystemRandomNumberGenerator()
        return (0..<6).map { _ in
            Self.prefixes.randomElement(using: &random)! + Self.suffixes.randomElement(using: &random)!
        }.joined(separator: " ")
    }

    private static let prefixes = [
        "amber", "apple", "arrow", "atlas", "baker", "beacon", "birch", "bison",
        "brisk", "brook", "cedar", "charm", "cider", "cloud", "coral", "crane",
        "daisy", "delta", "ember", "falcon", "fable", "field", "flint", "forest",
        "frost", "garden", "globe", "grape", "harbor", "hazel", "heron", "honey",
        "indigo", "island", "jade", "juniper", "koala", "lagoon", "lemon", "lilac",
        "lotus", "maple", "meadow", "melon", "misty", "north", "ocean", "olive",
        "orbit", "otter", "peach", "pearl", "piano", "plum", "quartz", "raven",
        "river", "robin", "solar", "spruce", "stone", "tiger", "ultra", "willow",
    ]

    private static let suffixes = [
        "able", "acorn", "berry", "bloom", "branch", "breeze", "bridge", "cabin",
        "candle", "castle", "circle", "comet", "copper", "crystal", "dancer", "dawn",
        "dream", "drift", "feather", "fern", "finch", "flame", "flower", "glade",
        "grove", "haven", "hill", "kite", "lake", "lantern", "leaf", "light",
        "lunar", "marble", "moon", "moss", "nest", "nova", "orchid", "path",
        "pine", "pond", "rain", "ridge", "rose", "sail", "shore", "sky",
        "spark", "spring", "star", "stream", "sun", "thistle", "trail", "vale",
        "wave", "whisper", "wind", "wing", "wood", "world", "wren", "zephyr",
    ]
}
