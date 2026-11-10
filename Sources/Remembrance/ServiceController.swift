import AVFoundation
import AppKit
import Combine
import Foundation

/// Runs the service: plays cues and times the silence. After O Canada the Last Post follows by
/// itself, at least `gap` seconds later and timed to end exactly at the target time (11:00).
@MainActor
final class ServiceController: ObservableObject {
    let cues = Cue.service
    /// Pause between O Canada ending and the Last Post starting.
    static let gap: TimeInterval = 5

    /// REMEMBRANCE_CLOCK=HH:MM:SS runs the app's clock as if it were that time today (for README
    /// screenshots and rehearsing the timing). Zero otherwise.
    static let clockOffset: TimeInterval = {
        guard let value = ProcessInfo.processInfo.environment["REMEMBRANCE_CLOCK"] else { return 0 }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2,
              let fake = Calendar.current.date(bySettingHour: parts[0], minute: parts[1],
                                               second: parts.count > 2 ? parts[2] : 0, of: Date())
        else { return 0 }
        return fake.timeIntervalSinceNow
    }()

    static func clock() -> Date { Date().addingTimeInterval(clockOffset) }

    /// A cue that will start by itself at `at` (the Last Post after O Canada).
    struct Pending: Equatable { let index: Int; let at: Date }

    @Published var selected = 0
    @Published private(set) var playing: Int?          // index of the cue sounding / counting now
    @Published private(set) var pending: Pending?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var done: Set<String> = []
    @Published private(set) var now = ServiceController.clock()
    @Published private(set) var loadErrors: [String: String] = [:]
    @Published private(set) var durations: [String: TimeInterval] = [:]
    @Published private(set) var outputName = AudioOutput.defaultDeviceName()

    /// Volume of the app's output, 0...1 (the Mac's own volume still applies on top).
    @Published var volume: Double = UserDefaults.standard.object(forKey: "volume") as? Double ?? 1 {
        didSet {
            UserDefaults.standard.set(volume, forKey: "volume")
            if let p = currentPlayer, !fading { p.volume = Float(volume) }
        }
    }
    /// Sound the Rouse as soon as the silence ends (off: the operator presses Play).
    @Published var autoRouse = UserDefaults.standard.bool(forKey: "autoRouse") {
        didSet { UserDefaults.standard.set(autoRouse, forKey: "autoRouse") }
    }
    /// Minutes after midnight when the silence begins.
    @Published var targetMinutes: Int = UserDefaults.standard.object(forKey: "targetMinutes") as? Int ?? 11 * 60 {
        didSet { UserDefaults.standard.set(targetMinutes, forKey: "targetMinutes") }
    }

    private var players: [String: AVAudioPlayer] = [:]
    private var currentPlayer: AVAudioPlayer?
    private var silenceStart: Date?
    private var fading = false
    private var ticker: AnyCancellable?
    private var activity: NSObjectProtocol?

    init() {
        reloadAll()
        ticker = Timer.publish(every: 0.05, tolerance: 0.01, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.tick(date) }
        // Keep the Mac (and its display) awake for the whole service.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleDisplaySleepDisabled, .idleSystemSleepDisabled],
            reason: "Remembrance Day service audio")
    }

    // MARK: Files

    /// A replacement recording the user picked for a cue, if any.
    func customURL(for cue: Cue) -> URL? {
        UserDefaults.standard.string(forKey: "file.\(cue.id)").map { URL(fileURLWithPath: $0) }
    }

    func url(for cue: Cue) -> URL? {
        if let custom = customURL(for: cue) { return custom }
        guard case .audio(let resource) = cue.kind else { return nil }
        let name = (resource as NSString).deletingPathExtension, ext = (resource as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext)
    }

    func setCustomFile(_ url: URL?, for cue: Cue) {
        UserDefaults.standard.set(url?.path, forKey: "file.\(cue.id)")
        load(cue)
    }

    func reloadAll() {
        for cue in cues where cue.isAudio { load(cue) }
        outputName = AudioOutput.defaultDeviceName()
    }

    private func load(_ cue: Cue) {
        players[cue.id] = nil
        durations[cue.id] = nil
        loadErrors[cue.id] = nil
        guard let url = url(for: cue) else {
            loadErrors[cue.id] = "Recording missing from the app"
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()          // decode ahead so Play starts instantly
            players[cue.id] = p
            // Time cues by where the sound dies away, not the file's silent tail.
            durations[cue.id] = min(p.duration, AudioAnalysis.audibleEnd(of: url) ?? p.duration)
        } catch {
            loadErrors[cue.id] = "Can't play \(url.lastPathComponent)"
        }
    }

    // MARK: Timing

    var lastPost: Cue { cues.first { $0.id == "last-post" }! }
    var silenceCue: Cue { cues.first { $0.id == "silence" }! }

    /// Today's (or the next) moment the silence begins.
    var targetDate: Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: targetMinutes / 60, minute: targetMinutes % 60, second: 0, of: now) ?? now
    }

    /// When the Last Post must start to end at the target time.
    var lastPostStart: Date? {
        durations[lastPost.id].map { targetDate.addingTimeInterval(-$0) }
    }

    var oCanada: Cue { cues.first { $0.id == "o-canada" }! }

    /// The latest O Canada can start for the Last Post to follow after the gap and end on time.
    var oCanadaStart: Date? {
        guard let lp = lastPostStart, let d = durations[oCanada.id] else { return nil }
        return lp.addingTimeInterval(-Self.gap - d)
    }

    var silenceDuration: TimeInterval {
        if case .silence(let s) = silenceCue.kind { return s }
        return 120
    }

    var silenceRemaining: TimeInterval? {
        guard let start = silenceStart else { return nil }
        return max(0, silenceDuration - now.timeIntervalSince(start))
    }

    func duration(of cue: Cue) -> TimeInterval? {
        if case .silence(let s) = cue.kind { return s }
        return durations[cue.id]
    }

    // MARK: Transport

    /// Something is sounding, counting, or about to start by itself.
    var isBusy: Bool { playing != nil || pending != nil }

    /// Plays the selected cue, or starts a waiting cue now. Does nothing while a cue is sounding,
    /// so a double press can never start something over the top.
    func go() {
        if let p = pending { start(p.index); return }
        guard !isBusy, cues.indices.contains(selected) else { return }
        start(selected)
    }

    /// `offset` skips into the recording (used when the timer fires a little late, so the
    /// Last Post still ends on time).
    func start(_ index: Int, offset: TimeInterval = 0) {
        guard playing == nil else { return }
        pending = nil
        let cue = cues[index]
        selected = index
        switch cue.kind {
        case .silence:
            silenceStart = Self.clock()
            playing = index
        case .audio:
            guard let p = players[cue.id] else { NSSound.beep(); return }
            p.currentTime = max(0, offset)
            p.volume = Float(volume)
            fading = false
            currentPlayer = p
            playing = index
            elapsed = p.currentTime
            p.play()
        }
    }

    /// Fades the current recording out over `seconds` (0 = cut), or ends the silence early.
    /// Also cancels a cue waiting to start by itself.
    func stop(fade seconds: TimeInterval = 1.5) {
        if pending != nil, playing == nil { pending = nil; return }
        guard let index = playing else { return }
        if cues[index].isAudio, let p = currentPlayer {
            if seconds > 0, p.isPlaying, !fading {
                fading = true
                p.setVolume(0, fadeDuration: seconds)
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                    guard let self, self.currentPlayer === p, self.fading else { return }
                    self.finish(index, advance: false)
                }
            } else {
                finish(index, advance: false)
            }
        } else {
            finish(index, advance: false)
        }
    }

    private func finish(_ index: Int, advance: Bool) {
        if advance, let p = currentPlayer, p.isPlaying {
            // Reached the audible end: let the faint room tail fade rather than cut it.
            p.setVolume(0, fadeDuration: 0.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                if self?.currentPlayer !== p { p.stop() }
            }
        } else {
            currentPlayer?.stop()
        }
        currentPlayer = nil
        fading = false
        silenceStart = nil
        playing = nil
        elapsed = 0
        let cue = cues[index]
        done.insert(cue.id)
        let next = index + 1
        if advance, cues.indices.contains(next) {
            selected = next
            // The Last Post follows O Canada after the gap, or at its scheduled time if that's
            // later, so its last note still sounds at the target time.
            if cue.id == oCanada.id, cues[next].id == lastPost.id {
                let soonest = Self.clock().addingTimeInterval(Self.gap)
                pending = Pending(index: next, at: max(soonest, lastPostStart ?? soonest))
            } else if cue.id == lastPost.id, cues[next].id == silenceCue.id {
                start(next)
            } else if cue.id == silenceCue.id, cues[next].id == "rouse", autoRouse {
                start(next)
            }
        } else if !advance {
            selected = min(index + 1, cues.count - 1)
        }
    }

    func reset() {
        pending = nil
        if isBusy { stop(fade: 0) }
        done = []
        selected = 0
    }

    func select(_ delta: Int) {
        guard !isBusy else { return }
        selected = min(max(selected + delta, 0), cues.count - 1)
    }

    private func tick(_ date: Date) {
        now = date.addingTimeInterval(Self.clockOffset)
        if let index = playing {
            if cues[index].isAudio, let p = currentPlayer {
                elapsed = p.currentTime
                let end = durations[cues[index].id] ?? p.duration
                if !fading, !p.isPlaying || p.currentTime >= end { finish(index, advance: true) }
            } else if let remaining = silenceRemaining {
                elapsed = silenceDuration - remaining
                if remaining <= 0 { finish(index, advance: true) }
            }
        } else if let p = pending, date >= p.at {
            // If the timer fires late (it shouldn't), skip in by the delay to keep the end on time.
            let late = date.timeIntervalSince(p.at)
            start(p.index, offset: late > 0.25 && late < 10 ? late : 0)
        }
    }

    func refreshOutput() { outputName = AudioOutput.defaultDeviceName() }
}
