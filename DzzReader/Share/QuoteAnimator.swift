import AVFoundation
import Observation

/// Plays the quote card the way the lecture page did: characters appear one per tick to the sound
/// of a typewriter, then the source appears, then the marked phrases are underlined one character
/// per tick to the sound of a quill on paper.
@Observable @MainActor
final class QuoteAnimator {
    enum Phase: String { case idle, writing, underlining }

    private(set) var phase = Phase.idle
    /// Number of glyphs shown, from the start of the quote.
    private(set) var revealed = 0
    /// Highlighted glyphs before this index carry their underline.
    private(set) var underlineCursor = 0
    private(set) var sourceShown = false

    @ObservationIgnored let tick: Duration
    @ObservationIgnored private let sounds: QuoteSounds?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(tick: Duration = .milliseconds(200), sounds: QuoteSounds? = nil) {
        self.tick = tick
        self.sounds = sounds
    }

    /// Stops any playback and shows the finished card.
    func showFinished(_ script: QuoteScript) {
        cancel()
        revealed = script.glyphs.count
        underlineCursor = script.glyphs.count
        sourceShown = true
        phase = .idle
    }

    /// 开始: write the quote from an empty card, then underline.
    func start(_ script: QuoteScript) {
        cancel()
        revealed = 0
        underlineCursor = 0
        sourceShown = false
        phase = .writing
        task = Task { [weak self] in
            guard let self else { return }
            if !script.glyphs.isEmpty { sounds?.play(.typewriter) }
            for i in script.glyphs.indices {
                try? await Task.sleep(for: tick)
                if Task.isCancelled { return }
                revealed = i + 1
            }
            sounds?.stop(.typewriter, fade: true)
            sourceShown = true
            try? await Task.sleep(for: tick)
            if Task.isCancelled { return }
            await runUnderline(script)
        }
    }

    /// 标线: redraw just the underlines over the written card.
    func underline(_ script: QuoteScript) {
        cancel()
        revealed = script.glyphs.count
        sourceShown = true
        underlineCursor = 0
        phase = .underlining
        task = Task { [weak self] in await self?.runUnderline(script) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        sounds?.stop(.typewriter, fade: false)
        sounds?.stop(.quill, fade: false)
    }

    private func runUnderline(_ script: QuoteScript) async {
        phase = .underlining
        underlineCursor = 0
        if script.highlightCount > 0 { sounds?.play(.quill) }
        for (i, glyph) in script.glyphs.enumerated() {
            underlineCursor = i + 1
            guard glyph.highlighted else { continue }   // only underlined characters take a tick
            try? await Task.sleep(for: tick)
            if Task.isCancelled { return }
        }
        sounds?.stop(.quill, fade: true)   // lift the pen rather than cut the sound
        phase = .idle
    }
}

/// The two recordings, typewriter.caf and quill.caf: short clips kept as uncompressed PCM so
/// they loop without a gap. Each playback starts at a random point in the clip.
@MainActor
final class QuoteSounds {
    enum Effect: String, CaseIterable { case typewriter, quill }

    static let shared = QuoteSounds()

    private var players: [Effect: AVAudioPlayer] = [:]
    private var generations: [Effect: Int] = [:]

    init() {
        // Set the category before any player exists: prepareToPlay() under the default
        // .soloAmbient category activates a non-mixable session and stops the person's music.
        // .playback + .mixWithOthers plays over the person's music, and sounds even with the
        // silent switch on.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        for effect in Effect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "caf"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.numberOfLoops = -1
            player.prepareToPlay()
            players[effect] = player
        }
    }

    func play(_ effect: Effect) {
        guard let player = players[effect] else { return }
        generations[effect, default: 0] += 1
        player.volume = 1
        player.currentTime = Double.random(in: 0..<max(0.01, player.duration))
        player.play()
    }

    /// With `fade`, the sound dies away over a tenth of a second instead of cutting off.
    func stop(_ effect: Effect, fade: Bool) {
        guard let player = players[effect], player.isPlaying else { return }
        generations[effect, default: 0] += 1
        guard fade else { player.pause(); return }
        let generation = generations[effect]
        player.setVolume(0, fadeDuration: 0.12)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(130))
            guard let self, self.generations[effect] == generation else { return }   // restarted meanwhile
            player.pause()
        }
    }
}
