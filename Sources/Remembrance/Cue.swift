import Foundation

/// One step of the order of service the app drives: a recording, or the timed silence.
struct Cue: Identifiable, Equatable {
    enum Kind: Equatable {
        case audio(resource: String)
        case silence(seconds: TimeInterval)
    }

    let id: String
    let title: String
    let kind: Kind
    /// Where it falls in the ceremony, shown under the title.
    let note: String

    var isAudio: Bool { if case .audio = kind { return true } else { return false } }

    /// The order follows the Royal Canadian Legion's recommended order of service and
    /// the CAF / Veterans Affairs Canada guidance (see docs/ORDER-OF-SERVICE.md).
    static let service: [Cue] = [
        Cue(id: "o-canada", title: "O Canada", kind: .audio(resource: "o-canada.mp3"),
            note: "Near the start, around the opening remarks. Leave it finished by about 10:58."),
        Cue(id: "last-post", title: "The Last Post", kind: .audio(resource: "last-post.wav"),
            note: "Timed so its last note sounds at 11:00, which begins the silence."),
        Cue(id: "silence", title: "Two Minutes of Silence", kind: .silence(seconds: 120),
            note: "Starts by itself when the Last Post ends. No music at all, not even a lament."),
        Cue(id: "rouse", title: "The Rouse", kind: .audio(resource: "rouse.wav"),
            note: "Ends the silence (after the Lament, if a piper plays one). The Act of Remembrance follows."),
        Cue(id: "royal-anthem", title: "God Save the King", kind: .audio(resource: "royal-anthem.mp3"),
            note: "Closes the ceremony, after the wreaths and benediction."),
    ]
}
