import AVFoundation
import AppKit
import Combine
import Foundation

/// Runs the service: plays cues, times the silence, and can start the Last Post by itself so that
/// it ends exactly at the target time (11:00 by default).
@MainActor
final class ServiceController: ObservableObject {
    let cues = Cue.service

    @Published var selected = 0
    @Published private(set) var playing: Int?          // index of the cue sounding / counting now
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var done: Set<String> = []
    @Published private(set) var now = Date()
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
    /// Start the Last Post automatically so that it ends at `targetTime`.
    @Published var armed = false
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

    var isBusy: Bool { playing != nil }

    /// Plays the selected cue. Does nothing while another cue is sounding, so a double press
    /// can never start something over the top.
    func go() {
        guard !isBusy, cues.indices.contains(selected) else { return }
        start(selected)
    }

    /// `offset` skips into the recording (used when the timed Last Post fires a little late,
    /// so it still ends on time).
    func start(_ index: Int, offset: TimeInterval = 0) {
        guard !isBusy else { return }
        let cue = cues[index]
        selected = index
        switch cue.kind {
        case .silence:
            silenceStart = Date()
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
        if cue.id == lastPost.id { armed = false }
    }

    /// Fades the current recording out over `seconds` (0 = cut), or ends the silence early.
    func stop(fade seconds: TimeInterval = 1.5) {
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
            // The Last Post's final note begins the silence.
            if cue.id == lastPost.id, cues[next].id == silenceCue.id {
                start(next)
            } else if cue.id == silenceCue.id, cues[next].id == "rouse", autoRouse {
                start(next)
            }
        } else if !advance {
            selected = min(index + 1, cues.count - 1)
        }
    }

    func reset() {
        if isBusy { stop(fade: 0) }
        done = []
        selected = 0
        armed = false
    }

    func select(_ delta: Int) {
        guard !isBusy else { return }
        selected = min(max(selected + delta, 0), cues.count - 1)
    }

    private func tick(_ date: Date) {
        now = date
        if let index = playing {
            if cues[index].isAudio, let p = currentPlayer {
                elapsed = p.currentTime
                let end = durations[cues[index].id] ?? p.duration
                if !fading, !p.isPlaying || p.currentTime >= end { finish(index, advance: true) }
            } else if let remaining = silenceRemaining {
                elapsed = silenceDuration - remaining
                if remaining <= 0 { finish(index, advance: true) }
            }
        } else if armed, let due = lastPostStart, date >= due {
            // Fire up to 10 s late, skipping in by the delay so the last note still lands on time;
            // any later and it waits for the operator.
            let late = date.timeIntervalSince(due)
            if late < 10, let i = cues.firstIndex(of: lastPost) {
                start(i, offset: late > 0.25 ? late : 0)
            } else {
                armed = false
            }
        }
    }

    func refreshOutput() { outputName = AudioOutput.defaultDeviceName() }
}
