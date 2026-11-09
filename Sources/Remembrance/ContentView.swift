import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var service: ServiceController

    var body: some View {
        VStack(spacing: 0) {
            Header()
                .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(service.cues.enumerated()), id: \.element.id) { index, cue in
                        CueRow(index: index, cue: cue)
                        if cue.id == "rouse" { SpokenSection() }
                    }
                }
                .padding(16)
            }
            Divider()
            Transport()
                .padding(.horizontal, 20).padding(.vertical, 14)
                .background(.bar)
        }
        .frame(minWidth: 720, minHeight: 640)
    }
}

// MARK: - Header: clock, the 11:00 countdown, Last Post timing and output device

private struct Header: View {
    @EnvironmentObject var service: ServiceController

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(service.now, format: .dateTime.hour().minute().second())
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                HStack(spacing: 6) {
                    Image(systemName: "hifispeaker")
                    Text(service.outputName).lineLimit(1)
                    Button { service.refreshOutput() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Check the sound output again")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 4) {
                    Text("Silence at")
                    TargetTimePicker()
                }
                .font(.headline)
                Text(countdown)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let start = service.lastPostStart {
                    HStack(spacing: 8) {
                        Text("Last Post starts \(start.formatted(.dateTime.hour().minute().second()))")
                            .monospacedDigit()
                        Toggle("Start it automatically", isOn: $service.armed)
                            .toggleStyle(.checkbox)
                            .disabled(start < service.now || service.isBusy)
                            .help("Plays the Last Post at exactly this time so its last note sounds at the silence.")
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var countdown: String {
        let diff = service.targetDate.timeIntervalSince(service.now)
        if diff > 0 { return "in \(clock(diff))" }
        if diff > -service.silenceDuration { return "now" }
        return "passed"
    }
}

private struct TargetTimePicker: View {
    @EnvironmentObject var service: ServiceController

    var body: some View {
        Menu(String(format: "%d:%02d", service.targetMinutes / 60, service.targetMinutes % 60)) {
            ForEach(Array(stride(from: 8 * 60, through: 16 * 60, by: 15)), id: \.self) { m in
                Button(String(format: "%d:%02d", m / 60, m % 60)) { service.targetMinutes = m }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(service.isBusy)
    }
}

// MARK: - Cue rows

private struct CueRow: View {
    @EnvironmentObject var service: ServiceController
    let index: Int
    let cue: Cue

    var isSelected: Bool { service.selected == index }
    var isActive: Bool { service.playing == index }
    var isDone: Bool { service.done.contains(cue.id) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("\(index + 1)")
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(cue.title).font(.title3.weight(.semibold))
                    if service.customURL(for: cue) != nil {
                        Text("Own recording").font(.caption).padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                if let error = service.loadErrors[cue.id] {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.red)
                } else {
                    Text(cue.note).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(alignment: .leading) { progressFill }
        .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(isDone && !isSelected && !isActive ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if !service.isBusy { service.start(index) } }
        .onTapGesture { if !service.isBusy { service.selected = index } }
        .contextMenu { if cue.isAudio { fileMenu } }
    }

    @ViewBuilder private var trailing: some View {
        if isActive, case .silence = cue.kind, let remaining = service.silenceRemaining {
            Text(clock(remaining))
                .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
        } else if isActive, let total = service.duration(of: cue) {
            Text("−" + clock(max(0, total - service.elapsed)))
                .font(.title2.monospacedDigit().weight(.semibold))
        } else {
            HStack(spacing: 10) {
                if let d = service.duration(of: cue) {
                    Text(clock(d)).font(.body.monospacedDigit()).foregroundStyle(.secondary)
                }
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? Color.green : Color.secondary.opacity(0.4))
                    .font(.title3)
            }
        }
    }

    @ViewBuilder private var progressFill: some View {
        if isActive, let total = service.duration(of: cue), total > 0 {
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.accentColor.opacity(0.22))
                    .frame(width: geo.size.width * min(1, service.elapsed / total))
            }
        }
    }

    @ViewBuilder private var fileMenu: some View {
        Button("Use a Different Recording…") { chooseFile() }
        if service.customURL(for: cue) != nil {
            Button("Use the Built-in Recording") { service.setCustomFile(nil, for: cue) }
        }
        if let url = service.url(for: cue) {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose a recording to play for \(cue.title)"
        if panel.runModal() == .OK, let url = panel.url { service.setCustomFile(url, for: cue) }
    }
}

// MARK: - Spoken part of the service (not a cue: shown for orientation, never selected)

private struct SpokenSection: View {
    static let items = [
        "Act of Remembrance / Commitment to Remember",
        "Prayers",
        "Placing of wreaths (In Flanders Fields is often read)",
        "Benediction / guest speakers",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Self.items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "text.bubble").font(.callout).foregroundStyle(.tertiary)
                    Text(item).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 52).padding(.trailing, 14).padding(.vertical, 10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Transport

private struct Transport: View {
    @EnvironmentObject var service: ServiceController

    var body: some View {
        HStack(spacing: 14) {
            Button(action: service.go) {
                Label(playTitle, systemImage: service.isBusy ? "waveform" : "play.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .frame(minWidth: 220, maxWidth: 320, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(service.isBusy)

            Button { service.stop() } label: {
                Label(stopTitle, systemImage: "stop.fill")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .frame(minHeight: 34)
            }
            .fixedSize()
            .controlSize(.large)
            .disabled(!service.isBusy)
            .help("Fades out over 1.5 seconds (Esc). Shift-Esc stops at once.")

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $service.volume, in: 0...1).frame(width: 130)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                Toggle("Play the Rouse when the silence ends", isOn: $service.autoRouse)
                    .toggleStyle(.checkbox)
                    .lineLimit(1)
                    .fixedSize()
                    .font(.callout)
                    .help("Off: press Play when the parade commander is ready (e.g. after a Lament).")
            }
        }
    }

    private var playTitle: String {
        if let i = service.playing { return service.cues[i].title }
        return "Play \(service.cues[service.selected].title)"
    }

    private var stopTitle: String {
        if let i = service.playing, !service.cues[i].isAudio { return "End Silence" }
        return "Stop"
    }
}

func clock(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded(.up))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                     : String(format: "%d:%02d", s / 60, s % 60)
}
