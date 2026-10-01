// Film Grain -- the window.
//
// Derived from the ComfyUI "FilmGrain" node (GPL-3.0), see GrainEngine.swift.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - App

@main
struct FilmGrainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = GrainModel.shared

    var body: some Scene {
        Window("\(AppInfo.name) \(AppInfo.version)", id: "main") {
            ContentView().environmentObject(model)
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Pictures…") { model.chooseFiles() }.keyboardShortcut("o")
            }
            // The keyboard shortcuts of the picture list live here, in the menu, and nowhere else in the window.
            CommandMenu("Pictures") {
                // The comma key: a picture picked at random, to spot-check a big batch "here and there".
                Button("Random Picture") { model.showRandomPicture() }
                    .keyboardShortcut(",", modifiers: [])
                    .disabled(model.urls.count < 2)
                Divider()
                // The arrow keys are handled by the app itself (a menu shortcut would steal them from
                // text fields), so these two items only list them.
                Button("Previous Picture   ←") { model.step(-1) }.disabled(model.urls.count < 2)
                Button("Next Picture   →") { model.step(1) }.disabled(model.urls.count < 2)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Pictures dropped on the Dock icon, or opened with "Open With".
    func application(_ application: NSApplication, open urls: [URL]) { GrainModel.shared.load(urls) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// If the window loses the focus while the compare button is held, never stay stuck on the original.
    func applicationDidResignActive(_ notification: Notification) { GrainModel.shared.holdOriginal = false }

    /// Left / right arrow = previous / next picture, looping. The arrows are left alone while
    /// a text field is being edited (they move the cursor), on a focused slider, and in
    /// the Open dialog.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isArrow = event.keyCode == 123 || event.keyCode == 124      // left, right
            let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            let responder = NSApp.keyWindow?.firstResponder
            guard isArrow, plain, !(event.window is NSPanel),
                  !(responder is NSTextView), !(responder is NSSlider),
                  GrainModel.shared.urls.count > 1
            else { return event }
            GrainModel.shared.step(event.keyCode == 124 ? 1 : -1)
            return nil
        }
    }
}

// MARK: - Model

private struct NoiseKey: Equatable { let width: Int, height: Int, scale: Double, seed: Int }

final class GrainModel: ObservableObject {
    static let shared = GrainModel()

    @Published var urls: [URL] = []
    @Published var index = 0
    @Published private(set) var current: SourceImage?
    @Published var showOriginal = false          // the Result / Original switch above the picture
    @Published var holdOriginal = false          // true only while the compare button is held down
    @Published var dropTargeted = false

    // These three are remembered between launches (see remember()).
    @Published var settings = GrainSettings() { didSet { remember() } }
    @Published var format: OutputFormat = .png { didSet { remember() } }
    @Published var actualSize = false { didSet { remember() } }       // "Fit" until chosen otherwise
    @Published var writeSettingsFile = false { didSet { remember() } } // the .txt is optional, off by default

    @Published private(set) var originalImage: CGImage?
    @Published private(set) var resultImage: CGImage?
    @Published private(set) var isRendering = false

    @Published var message = ""
    @Published var savedURLs: [URL] = []
    @Published var progress: Double?

    private let renderQueue = DispatchQueue(label: "filmgrain.render", qos: .userInitiated)
    private let lock = NSLock()
    private var renderToken = 0
    private var loadToken = 0
    private var stopSaving = false
    private var cachedNoise: (key: NoiseKey, values: [Float])?   // only touched on renderQueue

    // MARK: Remembering the last settings

    private enum Key {
        static let settings = "settings", format = "format", actualSize = "actualSize", settingsFile = "writeSettingsFile"
    }

    /// While the saved values are being put back, remember() must stay silent: setting one
    /// property would otherwise write the others' *default* values over the saved ones
    /// before they have been read.
    private var isRestoring = false

    init() {
        isRestoring = true
        defer { isRestoring = false }
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Key.settings),
           let saved = try? JSONDecoder().decode(GrainSettings.self, from: data) { settings = saved }
        if let raw = defaults.string(forKey: Key.format), let saved = OutputFormat(rawValue: raw) { format = saved }
        actualSize = defaults.object(forKey: Key.actualSize) as? Bool ?? false
        writeSettingsFile = defaults.object(forKey: Key.settingsFile) as? Bool ?? false
    }

    private func remember() {
        if isRestoring { return }
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Key.settings) }
        defaults.set(format.rawValue, forKey: Key.format)
        defaults.set(actualSize, forKey: Key.actualSize)
        defaults.set(writeSettingsFile, forKey: Key.settingsFile)
    }

    // MARK: Opening

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose the pictures to add grain to"
        if panel.runModal() == .OK { load(panel.urls) }
    }

    /// Opens pictures (a folder gives the pictures inside it). Replaces what was open.
    func load(_ dropped: [URL]) {
        DispatchQueue.global(qos: .userInitiated).async {
            var files: [URL] = []
            for url in dropped {
                var isFolder: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
                if isFolder.boolValue {
                    let inside = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                    // results of an earlier run (name_grain.png) are skipped, so a folder can be dropped again safely
                    files += inside.filter { ImageFiles.isImage($0) && !$0.deletingPathExtension().lastPathComponent.contains("_grain") }
                } else if ImageFiles.isImage(url) {
                    files.append(url)
                }
            }
            files.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            DispatchQueue.main.async {
                guard !files.isEmpty else {
                    self.message = "Nothing to open: drop picture files (PNG, JPEG, TIFF, HEIC, WebP…)."
                    return
                }
                self.urls = files
                self.randomBag = []
                self.index = 0
                self.savedURLs = []
                self.message = ""
                self.loadCurrent()
            }
        }
    }

    /// Pictures not yet shown by "Random Picture" in the current round.
    private var randomBag: [Int] = []

    /// A random picture of the list. Each one is shown once before any comes back, so that
    /// pressing the key twenty times on 200 pictures looks at twenty different ones.
    func showRandomPicture() {
        guard urls.count > 1 else { return }
        while true {
            // A new round starts with every picture but the one on screen, which counts as seen.
            if randomBag.isEmpty { randomBag = urls.indices.filter { $0 != index }.shuffled() }
            let pick = randomBag.removeLast()
            if pick != index { select(pick); return }     // never "jump" to the picture already on screen
        }
    }

    /// Previous (-1) or next (+1) picture. It loops: after the last one comes the first.
    func step(_ delta: Int) {
        guard urls.count > 1 else { return }
        select((index + delta + urls.count) % urls.count)
    }

    func select(_ newIndex: Int) {
        guard urls.indices.contains(newIndex) else { return }
        index = newIndex
        loadCurrent()
    }

    /// Loads the picture AND draws its grain before showing anything, so that browsing
    /// never flashes the clean original for a moment.
    private func loadCurrent() {
        let url = urls[index]
        let snapshot = settings
        lock.lock(); loadToken += 1; let mine = loadToken; lock.unlock()
        isRendering = true
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); let latest = self.loadToken; self.lock.unlock()
            if mine != latest { return }          // arrows pressed again meanwhile: skip this one

            let loaded = Result { try ImageFiles.load(url) }
            var original: CGImage?
            var result: CGImage?
            if case .success(let image) = loaded {
                original = ImageFiles.makeCGImage(image.pixels, colorSpace: image.colorSpace)
                result = self.drawResult(of: image, with: snapshot)
            }
            DispatchQueue.main.async {
                guard self.urls.indices.contains(self.index), self.urls[self.index] == url else { return }   // user moved on
                self.isRendering = false
                switch loaded {
                case .success(let image):
                    self.current = image
                    self.originalImage = original
                    self.resultImage = result
                    if self.settings != snapshot { self.scheduleRender() }   // a slider moved while loading
                case .failure(let error):
                    self.current = nil
                    self.originalImage = nil
                    self.resultImage = nil
                    self.message = error.localizedDescription
                }
            }
        }
    }

    // MARK: Live preview

    /// The grain pattern, then the effects, for one picture. Only call it on renderQueue
    /// (it uses the cached pattern).
    private func drawResult(of image: SourceImage, with s: GrainSettings) -> CGImage? {
        let key = NoiseKey(width: image.pixels.width, height: image.pixels.height, scale: s.scale, seed: s.seed)
        let noise: [Float]
        if let cached = cachedNoise, cached.key == key {
            noise = cached.values
        } else {
            noise = GrainEngine.noise(width: key.width, height: key.height, scale: key.scale, seed: key.seed)
            cachedNoise = (key, noise)
        }
        let output = GrainEngine.render(image.pixels, noise: noise, settings: s)
        return ImageFiles.makeCGImage(output, colorSpace: image.colorSpace)
    }

    /// Re-renders the preview. If several requests pile up (a slider being dragged),
    /// only the latest one is drawn.
    func scheduleRender() {
        guard let image = current else { return }
        let s = settings
        lock.lock(); renderToken += 1; let mine = renderToken; lock.unlock()
        isRendering = true
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); let latest = self.renderToken; self.lock.unlock()
            if mine != latest { return }

            let picture = self.drawResult(of: image, with: s)
            DispatchQueue.main.async {
                self.lock.lock(); let isLatest = (mine == self.renderToken); self.lock.unlock()
                if isLatest { self.resultImage = picture; self.isRendering = false }
            }
        }
    }

    // MARK: Saving

    func save(all: Bool) {
        guard !urls.isEmpty else { return }
        let targets = all ? urls : [urls[index]]
        let s = settings, fmt = format, withSettingsFile = writeSettingsFile
        lock.lock(); stopSaving = false; lock.unlock()
        progress = 0
        savedURLs = []
        message = ""
        DispatchQueue.global(qos: .userInitiated).async {
            var saved: [URL] = []
            var problems: [String] = []
            for (n, url) in targets.enumerated() {
                self.lock.lock(); let stop = self.stopSaving; self.lock.unlock()
                if stop { break }
                do {
                    let image = try ImageFiles.load(url)
                    let noise = GrainEngine.noise(width: image.pixels.width, height: image.pixels.height, scale: s.scale, seed: s.seed)
                    let output = GrainEngine.render(image.pixels, noise: noise, settings: s)
                    let destination = ImageFiles.freeURL(beside: url, format: fmt)
                    try ImageFiles.save(output, from: image, format: fmt, to: destination)
                    if withSettingsFile {
                        ImageFiles.writeSettingsFile(for: destination, source: image, settings: s, format: fmt)
                    }
                    saved.append(destination)
                } catch {
                    problems.append(error.localizedDescription)
                }
                DispatchQueue.main.async { self.progress = Double(n + 1) / Double(targets.count) }
            }
            DispatchQueue.main.async {
                self.progress = nil
                self.savedURLs = saved
                var text = saved.isEmpty ? "Nothing saved." : (saved.count == 1
                    ? "Saved \(saved[0].lastPathComponent), next to the original."
                    : "Saved \(saved.count) pictures, each next to its original.")
                if !problems.isEmpty { text += " Problem: " + problems.joined(separator: " ") }
                self.message = text
            }
        }
    }

    func cancelSaving() {
        lock.lock(); stopSaving = true; lock.unlock()
    }

    func revealSaved() {
        NSWorkspace.shared.activateFileViewerSelecting(savedURLs)
    }
}

// MARK: - Main view

struct ContentView: View {
    @EnvironmentObject var model: GrainModel

    var body: some View {
        HStack(spacing: 0) {
            ControlsPanel().frame(width: 310)
            Divider()
            PreviewPane()
        }
        .frame(minWidth: 960, minHeight: 620)
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted, perform: handleDrop)
        .overlay {
            if model.dropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor, lineWidth: 4)
                    .background(Color.accentColor.opacity(0.08))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: model.settings) { _, _ in model.scheduleRender() }
        // Without this the Seed field grabs the keyboard at launch and shows up highlighted.
        .onAppear { DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) } }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var dropped: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                if let url { lock.lock(); dropped.append(url); lock.unlock() }
            }
        }
        group.notify(queue: .main) { model.load(dropped) }
        return true
    }
}

// MARK: - Left panel: the controls

struct ControlsPanel: View {
    @EnvironmentObject var model: GrainModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(AppInfo.name).font(.title2.bold())
                    Text("v\(AppInfo.version)").font(.callout).foregroundStyle(.secondary)
                }
                Text("Drop pictures on the window to give them film grain, a colour cast or a vignette.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()

                CompareButton()

                ParamRow(title: "Strength", value: $model.settings.intensity, range: 0...1, step: 0.01,
                         defaultValue: 0.2, format: "%.2f",
                         help: "How visible the grain is. 0 = none, 1 = extreme.")
                ParamRow(title: "Scale", value: $model.settings.scale, range: 1...100, step: 1,
                         defaultValue: 10, format: "%.0f",
                         help: "How even the grain is across the picture. Low: patches where it is stronger or weaker. High: the same everywhere. The grain itself always stays one pixel fine.")
                ParamRow(title: "Warmth", value: $model.settings.temperature, range: -100...100, step: 1,
                         defaultValue: 0, format: "%+.0f",
                         help: "Colour cast. Negative = cooler and bluer, positive = warmer and more orange.")
                ParamRow(title: "Vignette", value: $model.settings.vignette, range: 0...1, step: 0.01,
                         defaultValue: 0, format: "%.2f",
                         help: "Darkens the corners. 0 = off, 1 = the corners go black.")

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Seed").font(.headline)
                        Spacer()
                        TextField("", value: $model.settings.seed, format: .number.grouping(.never))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                            .textFieldStyle(.roundedBorder)
                            // Return gives the keyboard back, so the arrow keys browse pictures again.
                            .onSubmit { NSApp.keyWindow?.makeFirstResponder(nil) }
                        Button { model.settings.seed = Int.random(in: 0...2_147_483_647) } label: {
                            Image(systemName: "dice")
                        }
                        .help("Pick another random seed")
                    }
                    Text("Same seed + same settings = exactly the same grain, every time.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Divider()
                SaveSection()
            }
            .padding(16)
        }
    }
}

/// Press and hold: the picture without any effect. Let go: the effects are back.
/// Meant for the eyes to compare with and without, without touching a slider.
struct CompareButton: View {
    @EnvironmentObject var model: GrainModel

    var body: some View {
        Button { } label: {
            Label("Hold to see the original", systemImage: "eye").frame(maxWidth: .infinity)
        }
        .buttonStyle(HoldStyle { model.holdOriginal = $0 })
        .disabled(model.current == nil)
        .help("Press and hold: the picture without any effect. Let go: the effects come back.")
    }
}

/// A button whose pressed state is reported while it lasts (a normal button only reports the click).
struct HoldStyle: ButtonStyle {
    let onChange: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(configuration.isPressed ? Color.accentColor : Color.secondary.opacity(0.22)))
            .foregroundStyle(configuration.isPressed ? Color.white : Color.primary)
            .onChange(of: configuration.isPressed) { _, pressed in onChange(pressed) }
    }
}

struct ParamRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double
    let format: String
    let help: String

    private var isDefault: Bool { abs(value - defaultValue) < step / 2 }

    var body: some View {
        // No `step:` on the Slider itself: it would draw a row of tick marks under it.
        // The value is snapped to the step here instead.
        let snapped = Binding<Double>(get: { value }, set: { value = ($0 / step).rounded() * step })
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(String(format: format, value)).monospacedDigit().foregroundStyle(.secondary)
                Button { value = defaultValue } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.borderless)
                    .help("Back to \(String(format: format, defaultValue))")
                    .opacity(isDefault ? 0.25 : 1)
                    .disabled(isDefault)
            }
            Slider(value: snapped, in: range)
            Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SaveSection: View {
    @EnvironmentObject var model: GrainModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Save as", selection: $model.format) {
                ForEach(OutputFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Toggle("Also write a .txt with all the settings (seed included)", isOn: $model.writeSettingsFile)
                .toggleStyle(.checkbox)
                .font(.callout)

            if let progress = model.progress {
                ProgressView(value: progress)
                Button("Stop") { model.cancelSaving() }
            } else {
                Button { model.save(all: false) } label: {
                    Text("Save this picture").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.current == nil)

                if model.urls.count > 1 {
                    Button { model.save(all: true) } label: {
                        Text("Save all \(model.urls.count) pictures").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
                Text("The result goes next to the original, as name_grain. The original is never touched.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if !model.message.isEmpty {
                Text(model.message).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            if !model.savedURLs.isEmpty {
                Button("Show in Finder") { model.revealSaved() }
            }
        }
    }
}

// MARK: - Right side: the picture

struct PreviewPane: View {
    @EnvironmentObject var model: GrainModel
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 0) {
            if model.current == nil && model.originalImage == nil {
                EmptyState()
            } else {
                toolbar
                Divider()
                picture
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            if model.urls.count > 1 {
                Button { model.step(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous picture (left arrow key). After the first comes the last.")
                Text("\(model.index + 1) of \(model.urls.count)").monospacedDigit()
                Button { model.step(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next picture (right arrow key). After the last comes the first.")
            }
            if let image = model.current {
                Text(image.name).lineLimit(1).truncationMode(.middle).fontWeight(.medium)
                Text("\(image.pixels.width) × \(image.pixels.height) px").foregroundStyle(.secondary)
            }
            if model.isRendering { ProgressView().controlSize(.small) }
            Spacer()
            Picker("", selection: $model.showOriginal) {
                Text("Result").tag(false)
                Text("Original").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 170)
            Picker("", selection: $model.actualSize) {
                Text("Actual size").tag(true)
                Text("Fit").tag(false)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 170)
            .help("Grain is only truthful at actual size: a reduced picture averages it away")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    @ViewBuilder private var picture: some View {
        let showingOriginal = model.showOriginal || model.holdOriginal
        let shown = showingOriginal ? model.originalImage : (model.resultImage ?? model.originalImage)
        GeometryReader { area in
            if let shown {
                if model.actualSize {
                    ScrollView([.horizontal, .vertical]) {
                        Image(decorative: shown, scale: displayScale)
                            .interpolation(.none)
                            .frame(minWidth: area.size.width, minHeight: area.size.height)
                    }
                    .defaultScrollAnchor(.center)
                } else {
                    Image(decorative: shown, scale: 1)
                        .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: area.size.width, height: area.size.height)
                }
            }
        }
        // A label, so that an original on screen is never taken for the result.
        .overlay(alignment: .topLeading) {
            if showingOriginal {
                Text("ORIGINAL")
                    .font(.caption.bold())
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct EmptyState: View {
    @EnvironmentObject var model: GrainModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("Drop pictures here").font(.title2)
            Text("one picture, several, or a whole folder").foregroundStyle(.secondary)
            Button("Choose Pictures…") { model.chooseFiles() }.controlSize(.large)
            if !model.message.isEmpty { Text(model.message).foregroundStyle(.orange).padding(.top, 6) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                .foregroundStyle(.tertiary)
                .padding(28)
                .allowsHitTesting(false)
        }
    }
}
