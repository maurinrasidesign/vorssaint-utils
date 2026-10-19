// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import Combine
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The picture the companion wears in its `image` style: one file the person
/// chose, kept as a PNG in Application Support and decoded once. Views that
/// draw the companion observe `version` so a new picture shows at once.
final class NotchMascotImageStore: ObservableObject {
    static let shared = NotchMascotImageStore()

    @Published private(set) var version = 0

    private var cached: CGImage?
    private var loaded = false

    private init() {}

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Juno Island", isDirectory: true)
    }

    static var url: URL { folder.appendingPathComponent("companion.png") }

    var hasImage: Bool { image != nil }

    /// The decoded picture, or nil without one.
    var image: CGImage? {
        if !loaded {
            loaded = true
            cached = Self.decode(Self.url)
        }
        return cached
    }

    /// Copies `source` in as the companion's picture, re-encoded as PNG so
    /// any format ImageIO reads works, then tells the island.
    func store(from source: URL) throws {
        guard let image = Self.decode(source) else {
            throw NSError(domain: "JunoCompanionImage", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The file is not an image ImageIO can read."])
        }
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let destination = Self.url
        guard let sink = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "JunoCompanionImage", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The picture could not be saved."])
        }
        CGImageDestinationAddImage(sink, image, nil)
        guard CGImageDestinationFinalize(sink) else {
            throw NSError(domain: "JunoCompanionImage", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "The picture could not be saved."])
        }
        cached = image
        loaded = true
        version += 1
    }

    func remove() {
        try? FileManager.default.removeItem(at: Self.url)
        cached = nil
        loaded = true
        version += 1
    }

    private static func decode(_ url: URL) -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
    }
}
