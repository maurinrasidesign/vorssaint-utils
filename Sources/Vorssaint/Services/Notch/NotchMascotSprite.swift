// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import CoreGraphics
import Foundation

/// Juno, the island's own companion: a small owl on a 16-by-16 grid, drawn
/// in the companion's palette. Its eyes are the island's own and blink, look
/// about and pull faces as in every style; the body comes in a few poses,
/// played in turn to type while Claude works, to doze and to wait for an
/// answer. Original artwork of this fork.
enum NotchMascotSprite {
    static let grid = 16

    /// One pose: 16 rows of 16 cells, each an ink or `.` for nothing.
    struct Frame: Equatable {
        let rows: [String]
    }

    /// One step of a pose sequence: the pose and how long it holds.
    struct Step {
        let frame: Frame
        let hold: TimeInterval
    }

    /// The inks a cell can take, each a colour from the companion's palette.
    enum Ink: Character, CaseIterable {
        case outline = "o"
        case body = "b"
        case wing = "d"
        case cream = "c"
        case beak = "y"
        case highlight = "h"
        case spark = "s"
        case doze = "z"

        func color(in palette: NotchMascotPalette) -> NotchMascotColor {
            let light = palette.light, shade = palette.shade
            func toward(_ base: NotchMascotColor, _ target: (CGFloat, CGFloat, CGFloat), _ amount: CGFloat) -> NotchMascotColor {
                NotchMascotColor(red: base.red + (target.0 - base.red) * amount,
                                 green: base.green + (target.1 - base.green) * amount,
                                 blue: base.blue + (target.2 - base.blue) * amount)
            }
            switch self {
            case .outline: return NotchMascotColor(red: shade.red * 0.36, green: shade.green * 0.34, blue: shade.blue * 0.36)
            case .body: return light
            case .wing: return NotchMascotColor(red: shade.red * 0.88, green: shade.green * 0.86, blue: shade.blue * 0.88)
            case .cream: return toward(light, (1.0, 0.95, 0.86), 0.78)
            case .beak: return NotchMascotColor(red: 0.99, green: 0.74, blue: 0.25)
            case .highlight: return toward(light, (1, 1, 1), 0.4)
            case .spark: return NotchMascotColor(red: 0.75, green: 0.95, blue: 1.0)
            case .doze: return NotchMascotColor(red: 0.85, green: 0.90, blue: 1.0)
            }
        }
    }

    // MARK: Poses

    /// Wings folded: how it stands most of the time.
    static let rest = Frame(rows: [
        ".o............o.",
        ".obo........obo.",
        ".obboooooooobbo.",
        "obhhbbbbbbbbbbbo",
        "ohbbbbbbbbbbbbbo",
        "obbccccbbccccbbo",
        "obccccccccccccbo",
        "obccccccccccccbo",
        "obcccccyycccccbo",
        "odbccccyyccccbdo",
        "oddbbbccccccbddo",
        "odddbbccccccdddo",
        "odddbbbccccbdddo",
        ".oddbbbbbbbbddo.",
        "..oooooooooooo..",
        "....yy....yy....",
    ])

    /// Both wings raised: wide awake, waiting on an answer.
    static let up = Frame(rows: [
        ".o............o.",
        ".obo........obo.",
        ".obboooooooobbo.",
        "obhhbbbbbbbbbbbo",
        "ohbbbbbbbbbbbbbo",
        "obbccccbbccccbbo",
        "obccccccccccccbo",
        "odccccccccccccdo",
        "oddccccyyccccddo",
        "odddcccyycccdddo",
        "odddbbccccccdddo",
        "obddbbccccccddbo",
        "obbbbbbccccbbbbo",
        ".obbbbbbbbbbbbo.",
        "..oooooooooooo..",
        "....yy....yy....",
    ])

    /// Typing: the left wing up, the right one on the keys, which spark.
    static let typeLeft = Frame(rows: [
        ".o............o.",
        ".obo........obo.",
        ".obboooooooobbo.",
        "obhhbbbbbbbbbbbo",
        "ohbbbbbbbbbbbbbo",
        "obbccccbbccccbbo",
        "obccccccccccccbo",
        "odccccccccccccbo",
        "oddccccyycccccbo",
        "odddcccyyccccbdo",
        "odddbbccccccbddo",
        "obddbbccccccdddo",
        "obbbbbbccccbdddo",
        ".obbbbbbbbbbddos",
        "..oooooooooooo.s",
        "....yy....yy....",
    ])

    /// Typing: the right wing up, the left one on the keys.
    static let typeRight = Frame(rows: [
        ".o............o.",
        ".obo........obo.",
        ".obboooooooobbo.",
        "obhhbbbbbbbbbbbo",
        "ohbbbbbbbbbbbbbo",
        "obbccccbbccccbbo",
        "obccccccccccccbo",
        "obccccccccccccdo",
        "obcccccyyccccddo",
        "odbccccyycccdddo",
        "oddbbbccccccdddo",
        "odddbbccccccddbo",
        "odddbbbccccbbbbo",
        "soddbbbbbbbbbbo.",
        "s.oooooooooooo..",
        "....yy....yy....",
    ])

    /// The left wing up without a spark: a beat between bursts of typing.
    static let liftLeft = Frame(rows: [
        ".o............o.",
        ".obo........obo.",
        ".obboooooooobbo.",
        "obhhbbbbbbbbbbbo",
        "ohbbbbbbbbbbbbbo",
        "obbccccbbccccbbo",
        "obccccccccccccbo",
        "odccccccccccccbo",
        "oddccccyycccccbo",
        "odddcccyyccccbdo",
        "odddbbccccccbddo",
        "obddbbccccccdddo",
        "obbbbbbccccbdddo",
        ".obbbbbbbbbbddo.",
        "..oooooooooooo..",
        "....yy....yy....",
    ])

    /// The right wing up without a spark.
    static let liftRight = Frame(rows: [
        ".o............o.",
        ".obo........obo.",
        ".obboooooooobbo.",
        "obhhbbbbbbbbbbbo",
        "ohbbbbbbbbbbbbbo",
        "obbccccbbccccbbo",
        "obccccccccccccbo",
        "obccccccccccccdo",
        "obcccccyyccccddo",
        "odbccccyycccdddo",
        "oddbbbccccccdddo",
        "odddbbccccccddbo",
        "odddbbbccccbbbbo",
        ".oddbbbbbbbbbbo.",
        "..oooooooooooo..",
        "....yy....yy....",
    ])

    /// Dozing, a bubble rising past a tuft.
    static let dozeA = Frame(rows: [
        ".o.........z..o.",
        ".obo......z.obo.",
        ".obboooooooobbo.",
        "obhhbbbbbbbbbbbo",
        "ohbbbbbbbbbbbbbo",
        "obbccccbbccccbbo",
        "obccccccccccccbo",
        "obccccccccccccbo",
        "obcccccyycccccbo",
        "odbccccyyccccbdo",
        "oddbbbccccccbddo",
        "odddbbccccccdddo",
        "odddbbbccccbdddo",
        ".oddbbbbbbbbddo.",
        "..oooooooooooo..",
        "....yy....yy....",
    ])

    /// Dozing, the bubble a little further on.
    static let dozeB = Frame(rows: [
        ".o.......z....o.",
        ".obo.......zobo.",
        ".obboooooooobbo.",
        "obhhbbbbbbbbbbbo",
        "ohbbbbbbbbbbbbbo",
        "obbccccbbccccbbo",
        "obccccccccccccbo",
        "obccccccccccccbo",
        "obcccccyycccccbo",
        "odbccccyyccccbdo",
        "oddbbbccccccbddo",
        "odddbbccccccdddo",
        "odddbbbccccbdddo",
        ".oddbbbbbbbbddo.",
        "..oooooooooooo..",
        "....yy....yy....",
    ])

    /// The poses it plays with `mood`, over and over. One step holds still.
    static func program(for mood: NotchMascotMood) -> [Step] {
        switch mood {
        case .thinking:
            // Bursts of typing, a pause to read, and a stretch now and then.
            return [
                Step(frame: typeLeft, hold: 0.13), Step(frame: typeRight, hold: 0.13),
                Step(frame: typeLeft, hold: 0.13), Step(frame: typeRight, hold: 0.13),
                Step(frame: liftLeft, hold: 0.13), Step(frame: liftRight, hold: 0.13),
                Step(frame: rest, hold: 0.35),
                Step(frame: typeRight, hold: 0.13), Step(frame: typeLeft, hold: 0.13),
                Step(frame: typeRight, hold: 0.13), Step(frame: typeLeft, hold: 0.13),
                Step(frame: rest, hold: 0.6),
                Step(frame: up, hold: 0.3), Step(frame: rest, hold: 0.5),
            ]
        case .searching:
            // Looking about, a wing up on the side it looks to.
            return [
                Step(frame: liftLeft, hold: 0.6), Step(frame: rest, hold: 0.3),
                Step(frame: liftRight, hold: 0.6), Step(frame: rest, hold: 0.3),
            ]
        case .alert, .surprised:
            return [Step(frame: up, hold: 1)]
        case .sleepy:
            return [Step(frame: dozeA, hold: 0.9), Step(frame: dozeB, hold: 0.9)]
        case .love, .happy:
            return [Step(frame: rest, hold: 1.1), Step(frame: up, hold: 0.35)]
        case .idle, .wink, .determined, .confused:
            return [Step(frame: rest, hold: 1)]
        }
    }

    // MARK: Drawing

    /// The cells of each ink in `frame`, as one path per ink over a square of
    /// `size` points. Cell edges snap to the device pixel grid at `scale`, so
    /// neighbouring inks meet without a seam.
    static func paths(_ frame: Frame, size: CGFloat, scale: CGFloat) -> [Ink: CGPath] {
        let scale = max(1, scale)
        func edge(_ index: Int) -> CGFloat {
            (CGFloat(index) * size / CGFloat(grid) * scale).rounded() / scale
        }
        var paths: [Ink: CGMutablePath] = [:]
        for (y, row) in frame.rows.prefix(grid).enumerated() {
            for (x, cell) in row.prefix(grid).enumerated() {
                guard let ink = Ink(rawValue: cell) else { continue }
                let rect = CGRect(x: edge(x), y: edge(y), width: edge(x + 1) - edge(x), height: edge(y + 1) - edge(y))
                let path = paths[ink] ?? CGMutablePath()
                path.addRect(rect)
                paths[ink] = path
            }
        }
        return paths
    }

    /// Every pose is a full 16-by-16 grid of known inks.
    static var framesAreWellFormed: Bool {
        let frames = [rest, up, typeLeft, typeRight, liftLeft, liftRight, dozeA, dozeB]
        return frames.allSatisfy { frame in
            frame.rows.count == grid && frame.rows.allSatisfy { row in
                row.count == grid && row.allSatisfy { $0 == "." || Ink(rawValue: $0) != nil }
            }
        }
    }
}
