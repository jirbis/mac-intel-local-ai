// Mac Intel Local AI: menu bar app that picks how a local LLM server runs on
// an Intel Mac with an AMD Radeon GPU (Ollama with Vulkan, Ollama from
// Homebrew, llama.cpp with Vulkan or on the CPU, or any custom command) and
// edits each one's launch parameters.
//
// One LaunchAgent runs whichever backend is selected, so only one server and
// one model sit in memory. Per-backend parameters are kept in
// ~/Library/Application Support/Mac Intel Local AI/settings.json; the plist is
// generated from the selected one and lists the others in an XML comment.
// With autostart on the plist lives in ~/Library/LaunchAgents (loaded at
// login); with autostart off it lives in Application Support.
//
// The running server is described in active.json next to settings.json so
// other tools can find it (see examples/active_server.py).
//
// Build: ./build.sh install

import AppKit
import IOKit
import SwiftUI

// MARK: - Paths

let appName = "Mac Intel Local AI"
let agentLabel = "com.github.jirbis.mac-intel-local-ai.server"
let hexEnvLabel = "com.github.jirbis.mac-intel-local-ai.hex-env"
let home = FileManager.default.homeDirectoryForCurrentUser.path
let loginPlist = home + "/Library/LaunchAgents/\(agentLabel).plist"
let hexEnvPlist = home + "/Library/LaunchAgents/\(hexEnvLabel).plist"
let supportDir = home + "/Library/Application Support/\(appName)"
let sessionPlist = supportDir + "/\(agentLabel).plist"
let settingsPath = supportDir + "/settings.json"
let activePath = supportDir + "/active.json"
let logDir = home + "/Library/Logs/\(appName)"
let logPath = logDir + "/server.log"
let domain = "gui/\(getuid())"
let defaultModels = home + "/.ollama/models"
let moltenICD = "/usr/local/etc/vulkan/icd.d/MoltenVK_icd.json"

let shortActivePath = activePath.replacingOccurrences(of: home, with: "~")

// MARK: - Interface language

/// English by default; Russian on request. Stored in the app's defaults.
enum UILanguage: String, CaseIterable, Identifiable {
    case en, ru
    var id: String { rawValue }
    var name: String { self == .en ? "English" : "Русский" }
}

let languageKey = "language"
var uiLanguage = UILanguage(rawValue: UserDefaults.standard.string(forKey: languageKey) ?? "") ?? .en

/// The interface string in the selected language.
func tr(_ en: String, _ ru: String) -> String { uiLanguage == .ru ? ru : en }

// MARK: - Backends

enum Backend: String, CaseIterable, Codable, Identifiable {
    case ollamaGPU, momin010, ollamaBrew, llamaVulkan, llamaCPU, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ollamaGPU: return "OllamaGPU"
        case .momin010: return "Ollama Vulkan (Momin010)"
        case .ollamaBrew: return "Ollama (brew)"
        case .llamaVulkan: return "llama.cpp Vulkan"
        case .llamaCPU: return "llama.cpp CPU"
        case .custom: return tr("Custom command", "Своя команда")
        }
    }

    var summary: String {
        switch self {
        case .ollamaGPU: return tr("Ollama with Vulkan (baksogen/ollama_GPU) in /Applications/Ollama.app · GPU", "Ollama с Vulkan (baksogen/ollama_GPU) в /Applications/Ollama.app · GPU")
        case .momin010: return tr("Ollama with Vulkan (Momin010/ollama-vulkan-macos), standalone folder · GPU", "Ollama с Vulkan (Momin010/ollama-vulkan-macos), отдельная папка · GPU")
        case .ollamaBrew: return tr("Ollama from Homebrew · CPU only", "Ollama из Homebrew · только CPU")
        case .llamaVulkan: return tr("llama-server built with GGML_VULKAN · GPU", "llama-server, собранный с GGML_VULKAN · GPU")
        case .llamaCPU: return tr("llama-server without GPU (-dev none -ngl 0) · CPU", "llama-server без GPU (-dev none -ngl 0) · CPU")
        case .custom: return tr("Any server with the Ollama or OpenAI API", "Любой сервер с API Ollama или OpenAI")
        }
    }

    var isOllama: Bool { [.ollamaGPU, .momin010, .ollamaBrew].contains(self) }
    var isLlama: Bool { [.llamaVulkan, .llamaCPU].contains(self) }
}

enum APIStyle: String, Codable, CaseIterable, Identifiable {
    case ollama, openai
    var id: String { rawValue }
}

// MARK: - Per-backend parameters

struct OllamaSettings: Codable, Equatable {
    var binary: String
    var port = 11434
    var modelsDir = defaultModels
    var keepAlive = "-1"
    var maxLoaded = 1
    var context = 0          // 0 = the model's default
    var flashAttention = false
    var numParallel = 1
    var model = "qwen2.5:3b" // what Hex and the benchmark ask for
    var extraEnv = ""        // "KEY=VALUE KEY2=VALUE2"

    var arguments: [String] { [binary, "serve"] }

    var environment: [String: String] {
        var env = [
            "OLLAMA_HOST": "127.0.0.1:\(port)",
            "OLLAMA_MODELS": modelsDir,
            "OLLAMA_KEEP_ALIVE": keepAlive,
            "OLLAMA_MAX_LOADED_MODELS": "\(maxLoaded)",
            "OLLAMA_NUM_PARALLEL": "\(numParallel)",
        ]
        if context > 0 { env["OLLAMA_CONTEXT_LENGTH"] = "\(context)" }
        if flashAttention { env["OLLAMA_FLASH_ATTENTION"] = "1" }
        return env.merging(parseEnv(extraEnv)) { _, new in new }
    }
}

struct LlamaSettings: Codable, Equatable {
    var binary: String
    var model = ""
    var device = "Vulkan0"
    var allLayersOnGPU = true
    var context = 4096
    var port = 8080
    var alias = "qwen2.5-3b"
    var flashAttention = "off"
    var icd = moltenICD
    var extraArgs = ""

    var arguments: [String] {
        [binary, "-m", model, "-dev", device, "-ngl", allLayersOnGPU ? "99" : "0",
         "-fa", flashAttention, "-c", "\(context)",
         "--host", "127.0.0.1", "--port", "\(port)", "-a", alias]
            + extraArgs.split(separator: " ").map(String.init)
    }

    var environment: [String: String] { icd.isEmpty ? [:] : ["VK_ICD_FILENAMES": icd] }

    mutating func parse(arguments a: [String], environment: [String: String]) {
        if let first = a.first { binary = first }
        var extra: [String] = []
        var i = 1
        while i < a.count {
            let key = a[i]
            let value = i + 1 < a.count ? a[i + 1] : ""
            switch key {
            case "-m": model = value
            case "-dev": device = value
            case "-ngl": allLayersOnGPU = (Int(value) ?? 99) > 0
            case "-fa": flashAttention = value
            case "-c": context = Int(value) ?? 4096
            case "--host": break
            case "--port": port = Int(value) ?? 8080
            case "-a": alias = value
            default:
                extra.append(key)
                i += 1
                continue
            }
            i += 2
        }
        extraArgs = extra.joined(separator: " ")
        icd = environment["VK_ICD_FILENAMES"] ?? ""
    }
}

struct CustomSettings: Codable, Equatable {
    var command = ""
    var env = ""
    var port = 8080
    var api = APIStyle.openai
    var model = ""

    var arguments: [String] { command.split(separator: " ").map(String.init) }
    var environment: [String: String] { parseEnv(env) }
}

func parseEnv(_ text: String) -> [String: String] {
    var env: [String: String] = [:]
    for pair in text.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
        let parts = pair.split(separator: "=", maxSplits: 1)
        if parts.count == 2 { env[String(parts[0])] = String(parts[1]) }
    }
    return env
}

struct Settings: Codable, Equatable {
    var backend = Backend.ollamaGPU
    var ollamaGPU = OllamaSettings(binary: "/Applications/Ollama.app/Contents/Resources/ollama")
    var momin010 = OllamaSettings(binary: supportDir + "/backends/ollama-vulkan-macos/ollama",
                                  extraEnv: "OLLAMA_VULKAN=1")
    var ollamaBrew = OllamaSettings(binary: "/usr/local/opt/ollama/bin/ollama")
    var llamaVulkan = LlamaSettings(binary: home + "/llama.cpp/build-vulkan/bin/llama-server")
    var llamaCPU = LlamaSettings(binary: home + "/llama.cpp/build/bin/llama-server",
                                 device: "none", allLayersOnGPU: false, icd: "")
    var custom = CustomSettings()

    init() {}

    /// Missing keys (settings written by an older version) keep their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        backend = try c.decodeIfPresent(Backend.self, forKey: .backend) ?? d.backend
        ollamaGPU = try c.decodeIfPresent(OllamaSettings.self, forKey: .ollamaGPU) ?? d.ollamaGPU
        momin010 = try c.decodeIfPresent(OllamaSettings.self, forKey: .momin010) ?? d.momin010
        ollamaBrew = try c.decodeIfPresent(OllamaSettings.self, forKey: .ollamaBrew) ?? d.ollamaBrew
        llamaVulkan = try c.decodeIfPresent(LlamaSettings.self, forKey: .llamaVulkan) ?? d.llamaVulkan
        llamaCPU = try c.decodeIfPresent(LlamaSettings.self, forKey: .llamaCPU) ?? d.llamaCPU
        custom = try c.decodeIfPresent(CustomSettings.self, forKey: .custom) ?? d.custom
    }

    func ollama(_ b: Backend) -> OllamaSettings {
        switch b {
        case .momin010: return momin010
        case .ollamaBrew: return ollamaBrew
        default: return ollamaGPU
        }
    }

    func llama(_ b: Backend) -> LlamaSettings { b == .llamaCPU ? llamaCPU : llamaVulkan }

    func arguments(_ b: Backend) -> [String] {
        if b.isOllama { return ollama(b).arguments }
        if b.isLlama { return llama(b).arguments }
        return custom.arguments
    }

    func environment(_ b: Backend) -> [String: String] {
        if b.isOllama { return ollama(b).environment }
        if b.isLlama { return llama(b).environment }
        return custom.environment
    }

    func port(_ b: Backend) -> Int {
        if b.isOllama { return ollama(b).port }
        if b.isLlama { return llama(b).port }
        return custom.port
    }

    func api(_ b: Backend) -> APIStyle {
        if b.isOllama { return .ollama }
        if b.isLlama { return .openai }
        return custom.api
    }

    /// The model name a client sends: Ollama tag or llama-server alias.
    func model(_ b: Backend) -> String {
        if b.isOllama { return ollama(b).model }
        if b.isLlama { return llama(b).alias }
        return custom.model
    }

    func binary(_ b: Backend) -> String { arguments(b).first ?? "" }

    /// The OpenAI-compatible base every backend answers under.
    func openAIBase(_ b: Backend) -> String { "http://127.0.0.1:\(port(b))/v1" }

    func endpoint(_ b: Backend) -> String {
        let base = "http://127.0.0.1:\(port(b))"
        return api(b) == .ollama ? base + "/api/chat" : base + "/v1/chat/completions"
    }

    func healthURL(_ b: Backend) -> String {
        let base = "http://127.0.0.1:\(port(b))"
        if api(b) == .ollama { return base + "/api/version" }
        return b.isLlama ? base + "/health" : base + "/v1/models"
    }

    /// Shell-style preview of how launchd starts it.
    func commandLine(_ b: Backend) -> String {
        let env = environment(b).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        return (env + [arguments(b).map(quote).joined(separator: " ")]).joined(separator: " \\\n  ")
    }
}

func quote(_ s: String) -> String {
    s.contains(" ") ? "'\(s)'" : s
}

// MARK: - Plist

func xmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

/// XML comments may not contain "--".
func commentSafe(_ s: String) -> String {
    var t = s
    while t.contains("--") { t = t.replacingOccurrences(of: "--", with: "- -") }
    return t
}

func agentPlistXML(_ s: Settings) -> String {
    let b = s.backend
    var x = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <!--
      Local LLM server, written by Mac Intel Local AI
      (https://github.com/jirbis/mac-intel-local-ai). Change it in the app: it rewrites this file.
      Active: \(commentSafe(b.title))

      Other launch options, inactive (in XML comments "- -" stands for two hyphens):

    """
    for other in Backend.allCases where other != b && !s.arguments(other).isEmpty {
        x += "  \(commentSafe(other.title)):\n    "
        x += commentSafe(s.commandLine(other)).replacingOccurrences(of: "\n", with: "\n  ") + "\n\n"
    }
    x += """
    -->
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>\(agentLabel)</string>
        <key>ProgramArguments</key>
        <array>

    """
    for a in s.arguments(b) { x += "        <string>\(xmlEscape(a))</string>\n" }
    x += "    </array>\n    <key>EnvironmentVariables</key>\n    <dict>\n"
    for (k, v) in s.environment(b).sorted(by: { $0.key < $1.key }) {
        x += "        <key>\(xmlEscape(k))</key>\n        <string>\(xmlEscape(v))</string>\n"
    }
    x += """
        </dict>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <dict>
            <key>SuccessfulExit</key>
            <false/>
        </dict>
        <key>ThrottleInterval</key>
        <integer>30</integer>
        <key>ProcessType</key>
        <string>Interactive</string>
        <key>StandardOutPath</key>
        <string>\(xmlEscape(logPath))</string>
        <key>StandardErrorPath</key>
        <string>\(xmlEscape(logPath))</string>
    </dict>
    </plist>

    """
    return x
}

func writeFile(_ text: String, to path: String) throws {
    try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                            withIntermediateDirectories: true)
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

func writeAgentPlist(_ s: Settings, to path: String) throws {
    try FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    let xml = agentPlistXML(s)
    guard (try? PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil)) != nil else {
        throw NSError(domain: "MacIntelLocalAI", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: tr("the generated plist doesn't parse", "сгенерированный plist не читается")])
    }
    try writeFile(xml, to: path)
}

/// Settings for a first run: take the backend and its values from the plist
/// that's installed now, everything else from defaults.
func importFromPlist() -> Settings {
    var s = Settings()
    guard let data = FileManager.default.contents(atPath: loginPlist) ?? FileManager.default.contents(atPath: sessionPlist),
          let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let args = dict["ProgramArguments"] as? [String], let binary = args.first
    else { return s }
    let env = dict["EnvironmentVariables"] as? [String: String] ?? [:]
    if binary.hasSuffix("llama-server") {
        let cpu = binary.contains("/build/bin/")
        var l = cpu ? s.llamaCPU : s.llamaVulkan
        l.parse(arguments: args, environment: env)
        if cpu { s.llamaCPU = l; s.backend = .llamaCPU } else { s.llamaVulkan = l; s.backend = .llamaVulkan }
    } else if binary.hasSuffix("/ollama") {
        let b: Backend = binary.contains("Ollama.app") ? .ollamaGPU
            : binary.contains("ollama-vulkan-macos") ? .momin010 : .ollamaBrew
        var o = s.ollama(b)
        o.binary = binary
        if let h = env["OLLAMA_HOST"], let p = h.split(separator: ":").last.flatMap({ Int($0) }) { o.port = p }
        if let v = env["OLLAMA_MODELS"] { o.modelsDir = v }
        if let v = env["OLLAMA_KEEP_ALIVE"] { o.keepAlive = v }
        if let v = env["OLLAMA_MAX_LOADED_MODELS"].flatMap({ Int($0) }) { o.maxLoaded = v }
        if let v = env["OLLAMA_CONTEXT_LENGTH"].flatMap({ Int($0) }) { o.context = v }
        if let v = env["OLLAMA_NUM_PARALLEL"].flatMap({ Int($0) }) { o.numParallel = v }
        o.flashAttention = env["OLLAMA_FLASH_ATTENTION"] == "1"
        switch b {
        case .momin010: s.momin010 = o
        case .ollamaBrew: s.ollamaBrew = o
        default: s.ollamaGPU = o
        }
        s.backend = b
    } else {
        s.custom.command = args.joined(separator: " ")
        s.custom.env = env.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        s.backend = .custom
    }
    return s
}

/// Describe the selected server for other tools (examples/active_server.py).
func writeActive(_ s: Settings) {
    let b = s.backend
    let openai = s.openAIBase(b)
    let info: [String: Any] = [
        "backend": b.rawValue,
        "title": b.title,
        "api": s.api(b).rawValue,
        "base_url": "http://127.0.0.1:\(s.port(b))",
        "openai_base_url": openai,
        "chat_endpoint": s.endpoint(b),
        "model": s.model(b),
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    else { return }
    try? FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
    try? data.write(to: URL(fileURLWithPath: activePath), options: .atomic)
}

func loadSettings() -> Settings {
    if let data = FileManager.default.contents(atPath: settingsPath),
       let s = try? JSONDecoder().decode(Settings.self, from: data) {
        return withDefaultModels(s)
    }
    return withDefaultModels(importFromPlist())
}

/// llama.cpp backends with no model yet get qwen2.5:3b from the Ollama store.
func withDefaultModels(_ settings: Settings) -> Settings {
    var s = settings
    let models = ollamaModels()
    guard let m = models.first(where: { $0.name == "qwen2.5:3b" }) ?? models.first else { return s }
    if s.llamaVulkan.model.isEmpty { s.llamaVulkan.model = m.path; s.llamaVulkan.alias = aliasFor(m.name) }
    if s.llamaCPU.model.isEmpty { s.llamaCPU.model = m.path; s.llamaCPU.alias = aliasFor(m.name) }
    return s
}

func saveSettings(_ s: Settings) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
    try encoder.encode(s).write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
}

// MARK: - Video memory

struct VRAMInfo: Equatable {
    var name = ""
    var total: Double = 0      // bytes
    var free: Double = 0
}

/// The discrete GPU's video memory from the IORegistry (the accelerator with the
/// most VRAM): total from its PCI device, free from its PerformanceStatistics.
func vramInfo() -> VRAMInfo? {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(iterator) }
    var best: VRAMInfo?
    let up = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
    while case let service = IOIteratorNext(iterator), service != 0 {
        defer { IOObjectRelease(service) }
        guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
              let free = (stats["vramFreeBytes"] as? NSNumber)?.doubleValue,
              let totalMB = (IORegistryEntrySearchCFProperty(service, kIOServicePlane, "VRAM,totalMB" as CFString,
                                                             kCFAllocatorDefault, up) as? NSNumber)?.doubleValue
        else { continue }
        var name = ""
        if let data = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "model" as CFString, kCFAllocatorDefault, up) as? Data {
            name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        }
        let info = VRAMInfo(name: name, total: totalMB * 1_048_576, free: free)
        if info.total > (best?.total ?? 0) { best = info }
    }
    return best
}

// MARK: - Shell helpers

@discardableResult
func shell(_ path: String, _ args: [String], env: [String: String] = [:]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    if !env.isEmpty {
        process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
    }
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return (-1, "\(error.localizedDescription)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

struct AgentState: Equatable {
    var loaded = false
    var pid: Int?
}

func agentState() -> AgentState {
    let r = shell("/bin/launchctl", ["print", "\(domain)/\(agentLabel)"])
    guard r.status == 0 else { return AgentState() }
    var state = AgentState(loaded: true)
    for line in r.output.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("pid = "), let pid = Int(t.dropFirst(6)) { state.pid = pid }
    }
    return state
}

/// Ollama.app's own GUI starts a second server on :11434.
func ollamaAppRunning() -> Bool {
    shell("/usr/bin/pgrep", ["-f", "Ollama.app/Contents/MacOS/Ollama"]).status == 0
}

func httpJSON(_ url: String, body: [String: Any]? = nil, timeout: TimeInterval) async -> [String: Any]? {
    guard let u = URL(string: url) else { return nil }
    var request = URLRequest(url: u)
    request.timeoutInterval = timeout
    if let body {
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }
    guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return json }
    return String(decoding: data, as: UTF8.self).contains("ok") ? ["status": "ok"] : nil
}

// MARK: - Models and devices

struct LocalModel: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let bytes: Int64
}

func ollamaModels(_ base: String = defaultModels) -> [LocalModel] {
    let fm = FileManager.default
    let library = base + "/manifests/registry.ollama.ai"
    var models: [LocalModel] = []
    for namespace in (try? fm.contentsOfDirectory(atPath: library)) ?? [] {
        for name in (try? fm.contentsOfDirectory(atPath: "\(library)/\(namespace)")) ?? [] {
            for tag in (try? fm.contentsOfDirectory(atPath: "\(library)/\(namespace)/\(name)")) ?? [] {
                guard let data = fm.contents(atPath: "\(library)/\(namespace)/\(name)/\(tag)"),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let layers = json["layers"] as? [[String: Any]],
                      let layer = layers.first(where: { ($0["mediaType"] as? String)?.hasSuffix(".image.model") == true }),
                      let digest = layer["digest"] as? String
                else { continue }
                let path = base + "/blobs/" + digest.replacingOccurrences(of: ":", with: "-")
                guard fm.fileExists(atPath: path) else { continue }
                let size = (layer["size"] as? NSNumber)?.int64Value ?? 0
                let short = namespace == "library" ? name : "\(namespace)/\(name)"
                models.append(LocalModel(name: tag == "latest" ? short : "\(short):\(tag)", path: path, bytes: size))
            }
        }
    }
    return models.sorted { $0.name < $1.name }
}

/// "qwen2.5:3b" -> "qwen2.5-3b"; the name clients send to llama-server.
func aliasFor(_ modelName: String) -> String {
    modelName.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
}

struct GPUDevice: Identifiable, Hashable {
    var id: String
    var description: String
}

func listDevices(binary: String, icd: String) -> [GPUDevice] {
    let r = shell(binary, ["--list-devices"], env: icd.isEmpty ? [:] : ["VK_ICD_FILENAMES": icd])
    var found = r.output.split(separator: "\n").compactMap { line -> GPUDevice? in
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let colon = t.firstIndex(of: ":"), !t.hasPrefix("Available") else { return nil }
        return GPUDevice(id: String(t[..<colon]), description: String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
    }
    found.append(GPUDevice(id: "none", description: tr("no GPU, CPU only", "без GPU, только CPU")))
    return found
}

// MARK: - App state

@MainActor
final class Controller: ObservableObject {
    @Published var settings = Settings()
    @Published var saved = Settings()
    @Published var autostart = false
    @Published var agent = AgentState()
    @Published var healthy = false
    @Published var models: [LocalModel] = []
    /// Ollama models that only make embeddings (bge, nomic-embed…): no chat, no generate.
    @Published var embeddingOnly: Set<String> = []
    private var probedModels: Set<String> = []
    @Published var devices: [String: [GPUDevice]] = [:]
    @Published var loaded = ""          // Ollama /api/ps summary
    @Published var vram: VRAMInfo?
    @Published var modelVRAM: Double = 0 // bytes the loaded Ollama models hold in VRAM
    @Published var appConflict = false
    @Published var message = ""
    @Published var busy = false
    @Published var benchmark = ""
    @Published var hexEndpoint = ""
    @Published var hexModel = ""
    @Published var language = uiLanguage {
        didSet {
            uiLanguage = language
            UserDefaults.standard.set(language.rawValue, forKey: languageKey)
        }
    }

    private var timer: Timer?

    var dirty: Bool { settings != saved }
    var running: Backend { saved.backend }
    var hexUsesThis: Bool { hexEndpoint == saved.endpoint(running) && hexModel == saved.model(running) }

    var statusText: String {
        if !agent.loaded { return tr("Stopped", "Остановлен") }
        if agent.pid == nil { return tr("Restarting…", "Перезапускается…") }
        return healthy ? tr("Running on :\(saved.port(running))", "Работает на :\(saved.port(running))") : tr("Starting…", "Запускается…")
    }

    init() {
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func load() {
        autostart = FileManager.default.fileExists(atPath: loginPlist)
        settings = loadSettings()
        models = ollamaModels()
        saved = settings
        writeActive(saved)
        for b in [Backend.llamaVulkan, .llamaCPU] { loadDevices(b) }
        refresh()
    }

    func loadDevices(_ b: Backend) {
        let l = settings.llama(b)
        let binary = l.binary
        let icd = l.icd
        Task.detached {
            let found = FileManager.default.isExecutableFile(atPath: binary) ? listDevices(binary: binary, icd: icd) : []
            await MainActor.run { self.devices[b.rawValue] = found }
        }
    }

    func available(_ b: Backend) -> Bool {
        return b == .custom ? !settings.custom.command.isEmpty
            : FileManager.default.isExecutableFile(atPath: settings.binary(b))
    }

    func refresh() {
        let s = saved
        let b = s.backend
        Task.detached {
            let state = agentState()
            var ok = false
            var loaded = ""
            var modelVRAM: Double = 0
            if state.pid != nil {
                ok = await httpJSON(s.healthURL(b), timeout: 1.5) != nil
                if ok, s.api(b) == .ollama,
                   let ps = await httpJSON("http://127.0.0.1:\(s.port(b))/api/ps", timeout: 1.5),
                   let list = ps["models"] as? [[String: Any]] {
                    loaded = list.isEmpty ? tr("no models in memory", "в памяти нет моделей") : list.map { m in
                        let name = m["name"] as? String ?? "?"
                        let size = (m["size"] as? NSNumber)?.doubleValue ?? 0
                        let vram = (m["size_vram"] as? NSNumber)?.doubleValue ?? 0
                        modelVRAM += vram
                        let where_ = vram >= size && size > 0 ? "GPU" : vram > 0 ? "GPU+CPU" : "CPU"
                        return String(format: tr("%@ · %.1f GB · %@", "%@ · %.1f ГБ · %@"), name, size / 1e9, where_)
                    }.joined(separator: ", ")
                }
            }
            let endpoint = shell("/bin/launchctl", ["getenv", "HEX_LOCAL_AI_ENDPOINT"]).output
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let model = shell("/bin/launchctl", ["getenv", "HEX_LOCAL_AI_MODEL"]).output
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let conflict = ollamaAppRunning()
            let healthy = ok
            let summary = loaded
            let inModels = modelVRAM
            let gpu = vramInfo()
            await MainActor.run {
                self.agent = state
                self.healthy = healthy
                self.loaded = summary
                if healthy, s.api(b) == .ollama { self.probeCapabilities(port: s.port(b)) }
                self.modelVRAM = inModels
                self.vram = gpu
                self.appConflict = conflict
                self.hexEndpoint = endpoint
                self.hexModel = model
            }
        }
    }

    private func perform(_ title: String, _ work: @escaping @Sendable () -> String?) {
        busy = true
        message = title
        Task.detached {
            let error = work()
            await MainActor.run {
                self.busy = false
                self.message = error ?? ""
                self.refresh()
            }
        }
    }

    private var activePlist: String { autostart ? loginPlist : sessionPlist }

    /// Write the plist for the current autostart choice and remove the other copy.
    private func persist(_ s: Settings) throws {
        try saveSettings(s)
        writeActive(s)
        try writeAgentPlist(s, to: activePlist)
        try? FileManager.default.removeItem(atPath: autostart ? sessionPlist : loginPlist)
    }

    func start() {
        let path = activePlist
        let s = saved
        perform(tr("Starting…", "Запуск…")) {
            if !FileManager.default.fileExists(atPath: path) {
                do { try writeAgentPlist(s, to: path) } catch { return tr("Couldn't write the plist: \(error.localizedDescription)", "Не удалось записать plist: \(error.localizedDescription)") }
            }
            if agentState().loaded {
                let r = shell("/bin/launchctl", ["kickstart", "\(domain)/\(agentLabel)"])
                return r.status == 0 ? nil : r.output
            }
            let r = shell("/bin/launchctl", ["bootstrap", domain, path])
            return r.status == 0 ? nil : "launchctl bootstrap: \(r.output)"
        }
    }

    func stop() {
        perform(tr("Stopping…", "Остановка…")) {
            let r = shell("/bin/launchctl", ["bootout", "\(domain)/\(agentLabel)"])
            return r.status == 0 || !agentState().loaded ? nil : r.output
        }
    }

    func restart() {
        guard agent.loaded else { return start() }
        perform(tr("Restarting…", "Перезапуск…")) {
            let r = shell("/bin/launchctl", ["kickstart", "-k", "\(domain)/\(agentLabel)"])
            return r.status == 0 ? nil : r.output
        }
    }

    /// Save settings; a running server is replaced by the selected one.
    func apply() {
        let s = settings
        let wasLoaded = agent.loaded
        do { try persist(s) } catch {
            message = tr("Couldn't save: \(error.localizedDescription)", "Не удалось сохранить: \(error.localizedDescription)")
            return
        }
        saved = s
        benchmark = ""
        let path = activePlist
        perform(wasLoaded ? tr("Applying and restarting…", "Применяю и перезапускаю…") : tr("Saved", "Сохранено")) {
            guard wasLoaded else { return nil }
            shell("/bin/launchctl", ["bootout", "\(domain)/\(agentLabel)"])
            for _ in 0..<40 where agentState().loaded { usleep(250_000) }
            let r = shell("/bin/launchctl", ["bootstrap", domain, path])
            return r.status == 0 ? nil : "launchctl bootstrap: \(r.output)"
        }
    }

    func setAutostart(_ on: Bool) {
        autostart = on
        do { try persist(saved) } catch { message = tr("Autostart: \(error.localizedDescription)", "Автозапуск: \(error.localizedDescription)") }
    }

    /// Point Hex at the running server now and at every login.
    func useInHex() {
        let endpoint = saved.endpoint(running)
        let model = saved.model(running)
        perform(tr("Connecting Hex…", "Подключаю Hex…")) {
            shell("/bin/launchctl", ["setenv", "HEX_LOCAL_AI_ENDPOINT", endpoint])
            shell("/bin/launchctl", ["setenv", "HEX_LOCAL_AI_MODEL", model])
            let script = "launchctl setenv HEX_LOCAL_AI_ENDPOINT \(endpoint); launchctl setenv HEX_LOCAL_AI_MODEL \(model)"
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <!-- At login: point Hex's local AI at the Mac Intel Local AI server (written by the app). -->
            <plist version="1.0">
            <dict>
              <key>Label</key><string>\(hexEnvLabel)</string>
              <key>ProgramArguments</key>
              <array>
                <string>/bin/sh</string><string>-c</string>
                <string>\(xmlEscape(script))</string>
              </array>
              <key>RunAtLoad</key><true/>
            </dict>
            </plist>

            """
            try? writeFile(xml, to: hexEnvPlist)
            // Hex reads the variables only at launch: restart it if it runs.
            guard let app = ["Hex Test", "Hex"].first(where: {
                shell("/usr/bin/pgrep", ["-f", "\($0).app/Contents/MacOS/"]).status == 0
            }) else { return tr("Hex is set up. It picks up the settings the next time it starts.", "Hex настроен. Он подхватит настройки при следующем запуске.") }
            shell("/usr/bin/osascript", ["-e", "quit app \"\(app)\""])
            for _ in 0..<20 where shell("/usr/bin/pgrep", ["-f", "\(app).app/Contents/MacOS/"]).status == 0 {
                usleep(250_000)
            }
            shell("/usr/bin/open", ["-a", app])
            return tr("Hex restarted with this server.", "Hex перезапущен с этим сервером.")
        }
    }

    /// Ask Ollama once per model what it can do (/api/show "capabilities").
    func probeCapabilities(port: Int) {
        let names = models.map(\.name).filter { !probedModels.contains($0) }
        guard !names.isEmpty else { return }
        probedModels.formUnion(names)
        Task.detached {
            var embeddings: [String] = []
            for name in names {
                guard let d = await httpJSON("http://127.0.0.1:\(port)/api/show", body: ["model": name], timeout: 5),
                      let caps = d["capabilities"] as? [String] else { continue }
                if caps.contains("embedding") && !caps.contains("completion") { embeddings.append(name) }
            }
            let found = embeddings
            await MainActor.run { self.embeddingOnly.formUnion(found) }
        }
    }

    func isEmbedding(_ name: String) -> Bool {
        embeddingOnly.contains(name) || embeddingOnly.contains(name + ":latest")
    }

    func runBenchmark() {
        guard healthy else { benchmark = tr("Server isn't ready", "Сервер не готов"); return }
        benchmark = tr("Measuring… (the first request loads the model)", "Замер… (первый запрос загружает модель)")
        let s = saved
        let b = running
        // Ollama loads any model on request, so test the one picked in the window
        // even before it is applied; llama.cpp can only answer with the model it started with.
        let model = b.isOllama ? settings.ollama(b).model : s.model(b)
        let base = "http://127.0.0.1:\(s.port(b))"
        benchmark = tr("Measuring \(model)… (the first request loads the model)", "Замер \(model)… (первый запрос загружает модель)")
        let embedding = b.isOllama && isEmbedding(model)
        Task.detached {
            var result = tr("Request failed", "Ошибка запроса")
            if embedding {
                // An embedding model can't generate: measure how fast it reads text instead.
                let texts = (1...32).map { "Document \($0): a lighthouse keeper writes a long letter about storms, ships and the sea." }
                _ = await httpJSON(base + "/api/embed", body: ["model": model, "input": ["warm up"]], timeout: 180)
                if let d = await httpJSON(base + "/api/embed", body: ["model": model, "input": texts], timeout: 180),
                   let n = (d["prompt_eval_count"] as? NSNumber)?.doubleValue,
                   let ns = (d["total_duration"] as? NSNumber)?.doubleValue, ns > 0 {
                    result = String(format: tr("embedding model: %.0f tok/s (%d texts, %.0f tokens in %.2f s)",
                                               "модель эмбеддингов: %.0f ток/с (%d текстов, %.0f токенов за %.2f с)"),
                                    n / ns * 1e9, texts.count, n, ns / 1e9)
                } else {
                    result = tr("Embedding request failed", "Ошибка запроса эмбеддингов")
                }
            } else if s.api(b) == .ollama {
                _ = await httpJSON(base + "/api/generate", body: ["model": model, "prompt": "Hi", "stream": false,
                                                                  "options": ["num_predict": 1]], timeout: 180)
                if let d = await httpJSON(base + "/api/generate", body: [
                    "model": model, "prompt": "Write 200 words about a lighthouse.", "stream": false,
                    "options": ["num_predict": 200, "temperature": 0]], timeout: 180),
                   let n = (d["eval_count"] as? NSNumber)?.doubleValue,
                   let ns = (d["eval_duration"] as? NSNumber)?.doubleValue, ns > 0 {
                    let tps = n / ns * 1e9
                    let pn = (d["prompt_eval_count"] as? NSNumber)?.doubleValue ?? 0
                    let pns = (d["prompt_eval_duration"] as? NSNumber)?.doubleValue ?? 0
                    let pp = pns > 0 ? pn / pns * 1e9 : 0
                    result = String(format: tr("%.1f tok/s (%.0f tokens), prompt %.0f tok/s — %@", "%.1f ток/с (%.0f токенов), промпт %.0f ток/с — %@"),
                                    tps, n, pp, tps > 25 ? "GPU" : tr("looks like CPU", "похоже на CPU"))
                } else if let d = await httpJSON(base + "/api/generate", body: ["model": model, "prompt": "Hi",
                                                                               "stream": false], timeout: 30),
                          let error = d["error"] as? String {
                    result = tr("Error: \(error)", "Ошибка: \(error)")
                }
            } else if let d = await httpJSON(base + "/v1/chat/completions", body: [
                "model": model, "max_tokens": 200, "stream": false, "temperature": 0,
                "messages": [["role": "user", "content": "Write 200 words about a lighthouse."]]], timeout: 180) {
                if let t = d["timings"] as? [String: Any], let tps = t["predicted_per_second"] as? Double {
                    let n = t["predicted_n"] as? Int ?? 0
                    let pp = t["prompt_per_second"] as? Double ?? 0
                    result = String(format: tr("%.1f tok/s (%d tokens), prompt %.0f tok/s — %@", "%.1f ток/с (%d токенов), промпт %.0f ток/с — %@"),
                                    tps, n, pp, tps > 25 ? "GPU" : tr("looks like CPU", "похоже на CPU"))
                } else if d["choices"] != nil {
                    result = tr("Got a reply; the server doesn't report speed", "Ответ получен, сервер не сообщает скорость")
                }
            }
            let text = result
            await MainActor.run { self.benchmark = text }
        }
    }

    /// Ollama: drop every loaded model from memory (keep_alive 0).
    func unloadModels() {
        let base = "http://127.0.0.1:\(saved.port(running))"
        Task.detached {
            if let ps = await httpJSON(base + "/api/ps", timeout: 2), let list = ps["models"] as? [[String: Any]] {
                for m in list {
                    if let name = m["name"] as? String {
                        _ = await httpJSON(base + "/api/generate", body: ["model": name, "keep_alive": 0], timeout: 10)
                    }
                }
            }
            await MainActor.run { self.refresh() }
        }
    }

    func quitOllamaApp() {
        perform(tr("Quitting Ollama.app…", "Закрываю Ollama.app…")) {
            shell("/usr/bin/pkill", ["-TERM", "-f", "Ollama.app/Contents/MacOS/Ollama"])
            for _ in 0..<20 where ollamaAppRunning() { usleep(250_000) }
            return ollamaAppRunning() ? tr("Ollama.app didn't quit", "Ollama.app не закрылась") : nil
        }
    }

    func chooseGGUF(_ b: Backend) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = tr("Choose a GGUF model file", "Выберите файл модели GGUF")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            update(llama: b) {
                $0.model = url.path
                $0.alias = url.deletingPathExtension().lastPathComponent.lowercased()
            }
        }
    }

    func update(llama b: Backend, _ change: (inout LlamaSettings) -> Void) {
        if b == .llamaCPU { change(&settings.llamaCPU) } else { change(&settings.llamaVulkan) }
    }

    func update(ollama b: Backend, _ change: (inout OllamaSettings) -> Void) {
        switch b {
        case .momin010: change(&settings.momin010)
        case .ollamaBrew: change(&settings.ollamaBrew)
        default: change(&settings.ollamaGPU)
        }
    }

    func ollamaBinding<T>(_ b: Backend, _ key: WritableKeyPath<OllamaSettings, T>) -> Binding<T> {
        Binding(get: { self.settings.ollama(b)[keyPath: key] },
                set: { v in self.update(ollama: b) { $0[keyPath: key] = v } })
    }

    func llamaBinding<T>(_ b: Backend, _ key: WritableKeyPath<LlamaSettings, T>) -> Binding<T> {
        Binding(get: { self.settings.llama(b)[keyPath: key] },
                set: { v in self.update(llama: b) { $0[keyPath: key] = v } })
    }

    func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }
}

// MARK: - Views

struct MenuContent: View {
    @ObservedObject var controller: Controller
    var showSettings: () -> Void

    var body: some View {
        Text("\(controller.running.title) · \(controller.statusText)")
        Text(tr("Model: \(controller.saved.model(controller.running))", "Модель: \(controller.saved.model(controller.running))"))
        Divider()
        if controller.agent.loaded {
            Button(tr("Restart", "Перезапустить")) { controller.restart() }
            Button(tr("Stop", "Остановить")) { controller.stop() }
        } else {
            Button(tr("Start", "Запустить")) { controller.start() }
        }
        Divider()
        Button(tr("Settings…", "Настройки…")) { showSettings() }
        Button(tr("Open Log", "Открыть лог")) { controller.openLog() }
        Divider()
        Button(tr("Quit \(appName)", "Выйти из \(appName)")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct SettingsView: View {
    @ObservedObject var controller: Controller

    private var selected: Backend { controller.settings.backend }

    private var statusColor: Color {
        if controller.healthy { return .green }
        return controller.agent.loaded ? .orange : .secondary
    }

    var body: some View {
        Form {
            serverSection
            backendSection
            if selected.isOllama { ollamaSection(selected) }
            if selected.isLlama { llamaSection(selected) }
            if selected == .custom { customSection }
            Section(tr("Launch command (\(selected.title))", "Команда запуска (\(selected.title))")) {
                Text(controller.settings.commandLine(selected))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            appsSection
            hexSection
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(controller.message).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button(tr("Revert", "Отменить")) { controller.settings = controller.saved }
                    .disabled(!controller.dirty)
                Button(controller.agent.loaded ? tr("Apply and Restart", "Применить и перезапустить") : tr("Save", "Сохранить")) { controller.apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!controller.dirty || controller.busy || !controller.available(selected))
            }
            .padding(12)
            .background(.bar)
        }
        .frame(minWidth: 620, minHeight: 640)
    }

    private func vramRow(_ v: VRAMInfo) -> some View {
        let gb = { (x: Double) in String(format: "%.1f", max(0, x) / 1_073_741_824) }
        let model = controller.modelVRAM
        let system = v.total - v.free - model
        // What a model could use: free now plus what the loaded model would give back.
        let forModels = v.free + model
        let color: Color = forModels < 3 * 1_073_741_824 ? .red : forModels < 5 * 1_073_741_824 ? .orange : .secondary
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(tr("Video memory", "Видеопамять") + (v.name.isEmpty ? "" : " (\(v.name))") + ":")
                Text(tr("\(gb(v.free)) GB free of \(gb(v.total)) GB", "свободно \(gb(v.free)) ГБ из \(gb(v.total)) ГБ"))
                    .monospacedDigit()
            }
            ProgressView(value: min(v.total, max(0, v.total - v.free)), total: v.total)
            Text(tr("""
                For models: \(gb(forModels)) GB · loaded model \(gb(model)) GB · macOS and displays \(gb(system)) GB. \
                A model runs fully on the GPU only if its size in memory (weights plus context) fits; \
                every external display takes video memory.
                """, """
                Для моделей: \(gb(forModels)) ГБ · загруженная модель \(gb(model)) ГБ · macOS и экраны \(gb(system)) ГБ. \
                Модель работает целиком на GPU, только если её размер в памяти (веса плюс контекст) помещается; \
                каждый внешний монитор занимает видеопамять.
                """)).font(.caption).foregroundStyle(color)
        }
    }

    private var serverSection: some View {
        Section(tr("Server", "Сервер")) {
            Picker("Language / Язык", selection: $controller.language) {
                ForEach(UILanguage.allCases) { Text($0.name).tag($0) }
            }
            HStack {
                Circle().fill(statusColor).frame(width: 10, height: 10)
                Text("\(controller.running.title) · \(controller.statusText)")
                if let pid = controller.agent.pid {
                    Text("pid \(pid)").foregroundStyle(.secondary)
                }
                Spacer()
                if controller.agent.loaded {
                    Button(tr("Restart", "Перезапустить")) { controller.restart() }
                    Button(tr("Stop", "Остановить")) { controller.stop() }
                } else {
                    Button(tr("Start", "Запустить")) { controller.start() }
                }
            }
            .disabled(controller.busy)
            if !controller.loaded.isEmpty {
                HStack {
                    Text(tr("In memory: \(controller.loaded)", "В памяти: \(controller.loaded)")).foregroundStyle(.secondary)
                    Spacer()
                    Button(tr("Unload Models", "Выгрузить модели")) { controller.unloadModels() }
                }
            }
            if let v = controller.vram {
                vramRow(v)
            }
            HStack {
                Button(tr("Measure Speed", "Замерить скорость")) { controller.runBenchmark() }
                    .disabled(!controller.healthy)
                Text(controller.benchmark).foregroundStyle(.secondary)
                Spacer()
                Button(tr("Log", "Лог")) { controller.openLog() }
            }
            Toggle(tr("Start at login", "Запускать при входе в систему"), isOn: Binding(
                get: { controller.autostart },
                set: { controller.setAutostart($0) }
            ))
            if controller.appConflict {
                HStack {
                    Label(tr("Ollama.app is open: it runs a second server on :11434", "Открыто приложение Ollama.app: оно запускает второй сервер на :11434"),
                          systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Spacer()
                    Button(tr("Quit It", "Закрыть его")) { controller.quitOllamaApp() }
                }
            }
        }
    }

    private var backendSection: some View {
        Section(tr("Backend", "Способ запуска")) {
            Picker("", selection: $controller.settings.backend) {
                ForEach(Backend.allCases) { b in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(b.title)
                            if b == controller.running && controller.agent.loaded {
                                Text(tr("running now", "сейчас запущен")).font(.caption).foregroundStyle(.green)
                            }
                            if !controller.available(b) {
                                Text(b == .custom ? tr("not set", "не задана") : tr("not installed", "не установлен")).font(.caption).foregroundStyle(.red)
                            }
                        }
                        Text(b.summary).font(.caption).foregroundStyle(.secondary)
                        Text("\(controller.settings.endpoint(b)) · \(controller.settings.model(b))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .tag(b)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if controller.settings.backend != controller.saved.backend {
                Text(tr("Switching stops \(controller.saved.backend.title) and starts \(selected.title): only one model stays in memory.", "Переключение остановит \(controller.saved.backend.title) и запустит \(selected.title): в памяти остаётся одна модель."))
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func ollamaSection(_ b: Backend) -> some View {
        Section(tr("Parameters: \(b.title)", "Параметры: \(b.title)")) {
            Picker(tr("Model (for Hex and the speed test)", "Модель (для Hex и замера)"), selection: controller.ollamaBinding(b, \.model)) {
                if !controller.models.contains(where: { $0.name == controller.settings.ollama(b).model }) {
                    Text(controller.settings.ollama(b).model).tag(controller.settings.ollama(b).model)
                }
                ForEach(controller.models) { m in
                    Text("\(m.name)  ·  \(ByteCountFormatter.string(fromByteCount: m.bytes, countStyle: .file))"
                         + (controller.isEmbedding(m.name) ? tr("  ·  embeddings only", "  ·  только эмбеддинги") : "")).tag(m.name)
                }
            }
            if controller.isEmbedding(controller.settings.ollama(b).model) {
                Text(tr("This is an embedding model (vectors for search), not a chat model: it can't answer. Hex, renaming scans and chat apps need a chat model such as qwen2.5:3b. The speed test measures how fast it reads text.",
                        "Это модель эмбеддингов (векторы для поиска), а не чат-модель: отвечать она не умеет. Hex, переименованию сканов и чат-программам нужна чат-модель, например qwen2.5:3b. Замер покажет, как быстро она читает текст."))
                    .font(.caption).foregroundStyle(.orange)
            }
            Picker(tr("Keep the model loaded (OLLAMA_KEEP_ALIVE)", "Держать модель в памяти (OLLAMA_KEEP_ALIVE)"), selection: controller.ollamaBinding(b, \.keepAlive)) {
                Text(tr("always", "всегда")).tag("-1")
                Text(tr("5 minutes", "5 минут")).tag("5m")
                Text(tr("30 minutes", "30 минут")).tag("30m")
                Text(tr("1 hour", "1 час")).tag("1h")
                Text(tr("unload right away", "выгружать сразу")).tag("0")
                if !["-1", "5m", "30m", "1h", "0"].contains(controller.settings.ollama(b).keepAlive) {
                    Text(controller.settings.ollama(b).keepAlive).tag(controller.settings.ollama(b).keepAlive)
                }
            }
            Stepper(tr("Models in memory at once: \(controller.settings.ollama(b).maxLoaded)", "Моделей в памяти одновременно: \(controller.settings.ollama(b).maxLoaded)"),
                    value: controller.ollamaBinding(b, \.maxLoaded), in: 1...4)
            Picker(tr("Context (OLLAMA_CONTEXT_LENGTH)", "Контекст (OLLAMA_CONTEXT_LENGTH)"), selection: controller.ollamaBinding(b, \.context)) {
                Text(tr("model default", "по умолчанию")).tag(0)
                ForEach([2048, 4096, 8192, 16384, 32768], id: \.self) { Text("\($0)").tag($0) }
            }
            Stepper(tr("Parallel requests: \(controller.settings.ollama(b).numParallel)", "Параллельных запросов: \(controller.settings.ollama(b).numParallel)"),
                    value: controller.ollamaBinding(b, \.numParallel), in: 1...4)
            Toggle(tr("Flash attention (usually unsupported by Vulkan through MoltenVK)", "Flash attention (Vulkan через MoltenVK обычно не поддерживает)"), isOn: controller.ollamaBinding(b, \.flashAttention))
            TextField(tr("Port", "Порт"), value: controller.ollamaBinding(b, \.port), format: .number.grouping(.never))
            TextField(tr("Binary", "Программа"), text: controller.ollamaBinding(b, \.binary))
            TextField(tr("Models folder (OLLAMA_MODELS)", "Папка моделей (OLLAMA_MODELS)"), text: controller.ollamaBinding(b, \.modelsDir))
            TextField(tr("Extra variables (KEY=VALUE, space-separated)", "Доп. переменные (KEY=VALUE через пробел)"), text: controller.ollamaBinding(b, \.extraEnv))
            if b == .ollamaBrew {
                Text(tr("This build runs on the CPU only, about 3x slower than the GPU.", "Эта версия считает только на CPU, примерно в 3 раза медленнее GPU."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func llamaSection(_ b: Backend) -> some View {
        let l = controller.settings.llama(b)
        Section(tr("Parameters: \(b.title)", "Параметры: \(b.title)")) {
            Picker(tr("Model", "Модель"), selection: Binding(
                get: { l.model },
                set: { path in
                    controller.update(llama: b) { s in
                        s.model = path
                        if let m = controller.models.first(where: { $0.path == path }) { s.alias = aliasFor(m.name) }
                    }
                }
            )) {
                if !controller.models.contains(where: { $0.path == l.model }) {
                    Text((l.model as NSString).lastPathComponent).tag(l.model)
                }
                ForEach(controller.models) { m in
                    Text("\(m.name)  ·  \(ByteCountFormatter.string(fromByteCount: m.bytes, countStyle: .file))").tag(m.path)
                }
            }
            HStack {
                Text(l.model).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(tr("Other GGUF…", "Другой GGUF…")) { controller.chooseGGUF(b) }
            }
            TextField(tr("Model name in the API (-a)", "Имя модели в API (-a)"), text: controller.llamaBinding(b, \.alias))
            Picker(tr("Device (-dev)", "Устройство (-dev)"), selection: controller.llamaBinding(b, \.device)) {
                let list = controller.devices[b.rawValue] ?? []
                if !list.contains(where: { $0.id == l.device }) { Text(l.device).tag(l.device) }
                ForEach(list) { d in Text("\(d.id): \(d.description)").tag(d.id) }
            }
            Toggle(tr("All layers on the GPU (-ngl 99)", "Все слои на GPU (-ngl 99)"), isOn: controller.llamaBinding(b, \.allLayersOnGPU))
            if b == .llamaCPU && l.allLayersOnGPU {
                Text(tr("With a Metal build, full offload through Metal usually crashes on Intel Macs with Radeon GPUs.", "Если сборка с Metal: на Intel-Маках с Radeon полная выгрузка через Metal обычно падает."))
                    .font(.caption).foregroundStyle(.orange)
            }
            Picker(tr("Context (-c)", "Контекст (-c)"), selection: controller.llamaBinding(b, \.context)) {
                ForEach([2048, 4096, 8192, 16384, 32768], id: \.self) { Text("\($0)").tag($0) }
            }
            Picker("Flash attention (-fa)", selection: controller.llamaBinding(b, \.flashAttention)) {
                Text("off").tag("off")
                Text("on").tag("on")
                Text("auto").tag("auto")
            }
            TextField(tr("Port", "Порт"), value: controller.llamaBinding(b, \.port), format: .number.grouping(.never))
            TextField("llama-server", text: controller.llamaBinding(b, \.binary))
            TextField("VK_ICD_FILENAMES", text: controller.llamaBinding(b, \.icd))
            TextField(tr("Extra arguments", "Доп. аргументы"), text: controller.llamaBinding(b, \.extraArgs))
        }
    }

    private var customSection: some View {
        Section(tr("Parameters: custom command", "Параметры: своя команда")) {
            TextField(tr("Command (space-separated)", "Команда (через пробел)"), text: $controller.settings.custom.command)
            TextField(tr("Variables (KEY=VALUE, space-separated)", "Переменные (KEY=VALUE через пробел)"), text: $controller.settings.custom.env)
            TextField(tr("Port", "Порт"), value: $controller.settings.custom.port, format: .number.grouping(.never))
            Picker("API", selection: $controller.settings.custom.api) {
                Text("Ollama (/api/chat)").tag(APIStyle.ollama)
                Text("OpenAI (/v1/chat/completions)").tag(APIStyle.openai)
            }
            TextField(tr("Model name", "Имя модели"), text: $controller.settings.custom.model)
        }
    }

    private func copyRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            HStack {
                Text(value).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help(tr("Copy", "Скопировать"))
            }
        }
    }

    /// Chat apps (Jan, Open WebUI, Msty, …) and scripts: the OpenAI-compatible
    /// API every backend serves under /v1.
    private var appsSection: some View {
        let b = controller.running
        let base = "http://127.0.0.1:\(controller.saved.port(b))"
        return Section(tr("Chat apps and other programs", "Чат-программы и другие программы")) {
            copyRow("Base URL (OpenAI)", controller.saved.openAIBase(b))
            copyRow(tr("Model", "Модель"), controller.saved.model(b))
            copyRow("API key", "local")
            Text(tr("""
                Any app that lets you add an OpenAI-compatible provider can use this server: \
                Jan (Settings → Model Providers → add a provider with this Base URL and any API key), \
                Open WebUI, Msty, Raycast and similar. The API key isn't checked.
                """, """
                Этот сервер может использовать любая программа, где можно добавить провайдера с OpenAI API: \
                Jan (Settings → Model Providers → новый провайдер с этим Base URL и любым API key), \
                Open WebUI, Msty, Raycast и похожие. API key не проверяется.
                """))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if b.isLlama {
                    Button(tr("Open Chat in Browser", "Открыть чат в браузере")) {
                        NSWorkspace.shared.open(URL(string: base + "/")!)
                    }
                    .disabled(!controller.healthy)
                    .help(tr("llama-server's built-in chat page", "Встроенная страница чата llama-server"))
                }
                if let jan = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "jan.ai.app") {
                    Button(tr("Open Jan", "Открыть Jan")) { NSWorkspace.shared.open(jan) }
                }
                Spacer()
            }
            if b.isOllama {
                Text(tr("Ollama has no chat page of its own; switch to llama.cpp Vulkan for one, or use a chat app.",
                        "У Ollama нет своей страницы чата: она есть у llama.cpp Vulkan, или используйте чат-программу."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(tr("Programs can also read \(shortActivePath) to find the running server.",
                    "Программы также могут найти запущенный сервер по файлу \(shortActivePath)."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var hexSection: some View {
        Section("Hex") {
            LabeledContent("HEX_LOCAL_AI_ENDPOINT", value: controller.hexEndpoint.isEmpty ? "—" : controller.hexEndpoint)
            LabeledContent("HEX_LOCAL_AI_MODEL", value: controller.hexModel.isEmpty ? "—" : controller.hexModel)
            HStack {
                if controller.hexUsesThis {
                    Label(tr("Hex uses the running server", "Hex использует запущенный сервер"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(tr("Hex is set to another server or model", "Hex настроен на другой сервер или модель"), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button(tr("Connect Hex", "Подключить Hex")) { controller.useInHex() }
                    .disabled(controller.busy || controller.hexUsesThis || controller.dirty)
            }

        }
    }
}

/// The settings window is a plain AppKit window: SwiftUI's Window scene does
/// not open reliably from a menu-bar-only (LSUIElement) app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let controller = Controller()
    private var window: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Check without touching anything: print the plist the current settings produce.
        if CommandLine.arguments.contains("--print-plist") {
            print(agentPlistXML(loadSettings()), terminator: "")
            exit(0)
        }
        if CommandLine.arguments.contains("--vram") {
            if let v = vramInfo() {
                print(String(format: "%@: %.2f GB free of %.2f GB", v.name, v.free / 1_073_741_824, v.total / 1_073_741_824))
            } else {
                print("no GPU video memory statistics")
            }
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started at login with --background: stay in the menu bar only.
        if !CommandLine.arguments.contains("--background") { showSettings() }
    }

    /// Opening the app again from Finder or Spotlight shows the window: the
    /// menu bar icon can be hidden by the notch or a menu bar manager.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return true
    }

    func showSettings() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 820),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = appName
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(controller: Self.controller))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@main
struct MacIntelLocalAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var controller = AppDelegate.controller

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller) { delegate.showSettings() }
        } label: {
            Image(systemName: controller.healthy ? "cpu.fill" : "cpu")
        }
    }
}
