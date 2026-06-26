import AppIntents
import CrispCore
import Foundation

/// Cutting strength as a Shortcuts-pickable enum (the in-app `.custom` strength is
/// intentionally omitted — automations pick a named preset).
enum CleanStrengthChoice: String, AppEnum {
    case gentle, balanced, aggressive, veryAggressive

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Cleaning Strength")
    static var caseDisplayRepresentations: [CleanStrengthChoice: DisplayRepresentation] = [
        .gentle: "Gentle",
        .balanced: "Balanced",
        .aggressive: "Aggressive",
        .veryAggressive: "Very aggressive"
    ]

    var strength: Strength {
        switch self {
        case .gentle:         return .gentle
        case .balanced:       return .balanced
        case .aggressive:     return .aggressive
        case .veryAggressive: return .veryAggressive
        }
    }
}

/// The "Clean with Crisp" Shortcuts action: remove long pauses + filler words from
/// the given video(s), writing a tight `<name>_cleaned.<ext>` beside each original.
/// Runs headlessly through the shared `QuickClean` path (same engine + settings as
/// the app), auto-downloading the speech model the first time fillers are needed.
struct CleanWithCrispIntent: AppIntent {
    static var title: LocalizedStringResource = "Clean with Crisp"
    static var description = IntentDescription(
        "Remove long pauses and filler words from a recording, producing a tight cut beside the original.")

    @Parameter(title: "Videos", description: "The recordings to clean.",
               supportedContentTypes: [.movie, .audiovisualContent])
    var files: [IntentFile]

    @Parameter(title: "Strength", default: .aggressive)
    var strength: CleanStrengthChoice

    @Parameter(title: "Remove filler words", default: true)
    var removeFillers: Bool

    @Parameter(title: "Remove repeated takes",
               description: "Remove a phrase you flubbed and immediately said again, keeping the corrected take.",
               default: true)
    var removeRetakes: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Clean \(\.$files) at \(\.$strength) strength") {
            \.$removeFillers
            \.$removeRetakes
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let inputs: [URL] = files.compactMap(\.fileURL)
        guard !inputs.isEmpty else {
            throw $files.needsValueError("Choose one or more video files to clean.")
        }
        let quick = QuickClean()
        // One provisioner for the whole batch so the model is verified once, not
        // re-hashed per file (Swift default args would re-create it each call).
        let provisioner = ModelProvisioner.forSelectedModel()
        var outputs: [IntentFile] = []
        for url in inputs {
            let result = try await quick.clean(url, strength: strength.strength,
                                               removeFillers: removeFillers,
                                               removeRetakes: removeRetakes,
                                               provisioner: provisioner)
            let outURL = URL(fileURLWithPath: result.output)
            outputs.append(IntentFile(fileURL: outURL))
        }
        return .result(value: outputs)
    }
}

/// Exposes the action (and a couple of spoken phrases) to Shortcuts + Spotlight.
struct CrispShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CleanWithCrispIntent(),
            phrases: [
                "Clean with \(.applicationName)",
                "Clean a video with \(.applicationName)"
            ],
            shortTitle: "Clean with Crisp",
            systemImageName: "scissors")
    }
}
