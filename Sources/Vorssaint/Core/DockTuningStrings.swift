// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import Foundation

/// Words for the Dock tuning card: the Dock's own settings, the hidden ones
/// included, and custom icons for the apps pinned to it.
struct DockTuningStrings {
    let title: String
    let hubDescription: String
    let loading: String
    let sizeSection: String
    let iconSize: String
    let magnification: String
    let magnifiedSize: String
    let position: String
    let positionLeft: String
    let positionBottom: String
    let positionRight: String
    let hidingSection: String
    let autohide: String
    let autohideCaption: String
    let delay: String
    let delayCaption: String
    let duration: String
    let durationCaption: String
    let instant: String
    let behaviorSection: String
    let minimizeEffect: String
    let effectGenie: String
    let effectScale: String
    let effectSuck: String
    let minimizeIntoApp: String
    let minimizeIntoAppCaption: String
    let showRecents: String
    let runningOnly: String
    let runningOnlyCaption: String
    let dimHidden: String
    let dimHiddenCaption: String
    let launchAnimation: String
    let scrollToOpen: String
    let scrollToOpenCaption: String
    let processIndicators: String
    let singleApp: String
    let singleAppCaption: String
    let stackHighlight: String
    let spacersSection: String
    let addSpacer: String
    let addSmallSpacer: String
    let spacersCaption: String
    let resetSection: String
    let reset: String
    let resetCaption: String
    let restartDock: String
    let iconsTitle: String
    let iconsCaption: String
    let noPinnedApps: String
    let changeIcon: String
    let resetIcon: String
    let customBadge: String
    let iconNotWritableFormat: String
    let iconFailedFormat: String
    let iconUnreadable: String
    let keywords: String

    func iconNotWritable(_ app: String) -> String { String(format: iconNotWritableFormat, app) }
    func iconFailed(_ app: String) -> String { String(format: iconFailedFormat, app) }

    var searchKeywords: [String] { [hubDescription, iconSize, magnification, autohide, minimizeEffect, iconsTitle, keywords] }

    static var current: DockTuningStrings { FeatureStrings.dockTuning(L10n.shared.language) }
}

extension FeatureStrings {
    static func dockTuning(_ language: AppLanguage) -> DockTuningStrings {
        switch language {
        case .de: return DockTuningStrings(
            title: "Dock anpassen",
            hubDescription: "Grösse, Position, Ein-/Ausblenden, versteckte Dock-Optionen, Abstandshalter und eigene App-Icons. Änderungen werden sofort auf das Dock angewendet.",
            loading: "Dock wird gelesen…",
            sizeSection: "Grösse und Position",
            iconSize: "Icon-Grösse",
            magnification: "Vergrösserung",
            magnifiedSize: "Vergrösserte Grösse",
            position: "Position",
            positionLeft: "Links",
            positionBottom: "Unten",
            positionRight: "Rechts",
            hidingSection: "Ein- und Ausblenden",
            autohide: "Dock automatisch ausblenden",
            autohideCaption: "Das Dock erscheint, wenn der Zeiger den Bildschirmrand berührt.",
            delay: "Verzögerung",
            delayCaption: "Wie lange der Zeiger am Rand warten muss, bis das Dock erscheint. 0 = sofort.",
            duration: "Animationsdauer",
            durationCaption: "Wie schnell das Dock ein- und ausfährt. 0 = ohne Animation.",
            instant: "Sofort",
            behaviorSection: "Verhalten",
            minimizeEffect: "Effekt beim Minimieren",
            effectGenie: "Genie",
            effectScale: "Skalieren",
            effectSuck: "Einsaugen (versteckt)",
            minimizeIntoApp: "Fenster in das App-Icon minimieren",
            minimizeIntoAppCaption: "Minimierte Fenster landen beim App-Icon statt rechts im Dock.",
            showRecents: "Zuletzt benutzte Apps anzeigen",
            runningOnly: "Nur laufende Apps anzeigen",
            runningOnlyCaption: "Blendet alle angehefteten Apps aus. Das Dock zeigt nur, was gerade läuft.",
            dimHidden: "Ausgeblendete Apps transparent zeigen",
            dimHiddenCaption: "Apps, die mit ⌘H ausgeblendet sind, erscheinen halb durchsichtig.",
            launchAnimation: "Hüpfen beim Starten",
            scrollToOpen: "Scrollen öffnet die Fenster einer App",
            scrollToOpenCaption: "Nach oben scrollen über einem Icon zeigt dessen Fenster (Exposé).",
            processIndicators: "Punkte unter laufenden Apps",
            singleApp: "Einzel-App-Modus",
            singleAppCaption: "Ein Klick auf eine App blendet alle anderen aus. Gut zum Fokussieren.",
            stackHighlight: "Stapel beim Überfahren hervorheben",
            spacersSection: "Abstandshalter",
            addSpacer: "Abstand hinzufügen",
            addSmallSpacer: "Halben Abstand hinzufügen",
            spacersCaption: "Ein leerer Platz rechts bei den Apps. Verschiebe ihn im Dock, oder zieh ihn heraus zum Löschen.",
            resetSection: "Zurücksetzen",
            reset: "Auf macOS-Standard zurücksetzen",
            resetCaption: "Entfernt alle hier gesetzten Werte. Das Dock startet neu.",
            restartDock: "Dock neu starten",
            iconsTitle: "App-Icons",
            iconsCaption: "Gib einer angehefteten App ein eigenes Icon (PNG, ICNS, JPEG). Funktioniert nur bei Apps, in die du schreiben darfst. Apps aus /System gehen nicht; bei Apps, die ein Installer als Admin abgelegt hat, hilft eine Kopie in ~/Programme.",
            noPinnedApps: "Keine angehefteten Apps gefunden.",
            changeIcon: "Icon wählen…",
            resetIcon: "Original",
            customBadge: "Eigenes",
            iconNotWritableFormat: "Keine Schreibrechte für „%@“. Kopiere die App nach ~/Programme und hefte die Kopie ans Dock.",
            iconFailedFormat: "Das Icon für „%@“ konnte nicht gesetzt werden.",
            iconUnreadable: "Die Datei ist kein lesbares Bild.",
            keywords: "Dock, Icons, Vergrösserung, Ausblenden, Abstandshalter, DockFix, Farbe, Position"
        )
        default: return DockTuningStrings(
            title: "Dock Tuning",
            hubDescription: "Size, position, hiding, the Dock's hidden options, spacers and custom app icons. Changes apply to the Dock at once.",
            loading: "Reading the Dock…",
            sizeSection: "Size and Position",
            iconSize: "Icon size",
            magnification: "Magnification",
            magnifiedSize: "Magnified size",
            position: "Position",
            positionLeft: "Left",
            positionBottom: "Bottom",
            positionRight: "Right",
            hidingSection: "Hiding",
            autohide: "Automatically hide the Dock",
            autohideCaption: "The Dock comes out when the pointer touches the edge of the screen.",
            delay: "Delay",
            delayCaption: "How long the pointer waits at the edge before the Dock comes out. 0 = at once.",
            duration: "Animation",
            durationCaption: "How fast the Dock slides in and out. 0 = no animation.",
            instant: "Instant",
            behaviorSection: "Behavior",
            minimizeEffect: "Minimize effect",
            effectGenie: "Genie",
            effectScale: "Scale",
            effectSuck: "Suck (hidden)",
            minimizeIntoApp: "Minimize windows into the app icon",
            minimizeIntoAppCaption: "Minimized windows go to their app's icon instead of the right side of the Dock.",
            showRecents: "Show recent apps",
            runningOnly: "Show running apps only",
            runningOnlyCaption: "Hides every pinned app. The Dock shows only what is running.",
            dimHidden: "Dim hidden apps",
            dimHiddenCaption: "Apps hidden with ⌘H appear translucent.",
            launchAnimation: "Bounce when opening",
            scrollToOpen: "Scroll to show an app's windows",
            scrollToOpenCaption: "Scrolling up over an icon shows its windows (Exposé).",
            processIndicators: "Dots under running apps",
            singleApp: "Single app mode",
            singleAppCaption: "Clicking an app hides every other one. Good for focus.",
            stackHighlight: "Highlight stack items on hover",
            spacersSection: "Spacers",
            addSpacer: "Add Spacer",
            addSmallSpacer: "Add Half Spacer",
            spacersCaption: "An empty slot at the right of the apps. Move it in the Dock, or drag it out to remove it.",
            resetSection: "Reset",
            reset: "Reset to macOS defaults",
            resetCaption: "Removes every value set here. The Dock restarts.",
            restartDock: "Restart Dock",
            iconsTitle: "App icons",
            iconsCaption: "Give a pinned app an icon of your own (PNG, ICNS, JPEG). Works for apps you may write to. Apps in /System cannot change; for apps an installer placed as an administrator, a copy in ~/Applications works.",
            noPinnedApps: "No pinned apps found.",
            changeIcon: "Choose Icon…",
            resetIcon: "Original",
            customBadge: "Custom",
            iconNotWritableFormat: "No write access to “%@”. Copy the app to ~/Applications and pin the copy to the Dock.",
            iconFailedFormat: "The icon for “%@” could not be set.",
            iconUnreadable: "The file is not a readable image.",
            keywords: "Dock, icons, magnification, hiding, spacers, DockFix, color, position"
        )
        }
    }
}
