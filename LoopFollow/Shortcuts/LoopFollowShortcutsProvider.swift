//
//  LoopFollowShortcutsProvider.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-11-23.
//

import AppIntents

@available(iOS 16.0, *)
struct LoopFollowShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: EnableSnoozeAllIntent(),
                phrases: [
                    "Snooza alla larm i \(.applicationName)",
                    "Snooza alla larm med \(.applicationName)"
                ],
                shortTitle: "Snooza alla",
                systemImageName: "clock.badge"
            ),

            AppShortcut(
                intent: DisableSnoozeAllIntent(),
                phrases: [
                    "Avsnooza alla larm i \(.applicationName)",
                    "Ta bort snooze för alla larm i \(.applicationName)"
                ],
                shortTitle: "Avsnooza alla",
                systemImageName: "clock"
            ),

            AppShortcut(
                intent: EnableMuteAllIntent(),
                phrases: [
                    "Tysta alla larm i \(.applicationName)",
                    "Tysta alla larm med \(.applicationName)"
                ],
                shortTitle: "Tysta alla",
                systemImageName: "speaker.slash"
            ),

            AppShortcut(
                intent: DisableMuteAllIntent(),
                phrases: [
                    "Avtysta alla larm i \(.applicationName)",
                    "Ta bort tyst läge för alla larm i \(.applicationName)"
                ],
                shortTitle: "Avtysta alla",
                systemImageName: "speaker"
            )
        ]
    }
}
