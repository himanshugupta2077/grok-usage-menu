import AppKit

private let bundleID = "local.himanshu.GrokUsage"
private let refreshSkew: TimeInterval = 300
private let networkEvery: TimeInterval = 300

struct Session {
    var entryKey: String
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var issuer: String
    var clientID: String

    var isExpiring: Bool {
        guard let expiresAt else { return true }
        return expiresAt.timeIntervalSinceNow <= refreshSkew
    }
}

enum UsageError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

func authURL() -> URL {
    let home = ProcessInfo.processInfo.environment["GROK_HOME"]
    if let home, !home.isEmpty {
        return URL(fileURLWithPath: home).appendingPathComponent("auth.json")
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".grok/auth.json")
}

func parseDate(_ raw: String) -> Date? {
    let formatters: [ISO8601DateFormatter] = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [withFraction, plain]
    }()
    for formatter in formatters {
        if let date = formatter.date(from: raw) { return date }
    }
    guard let dot = raw.firstIndex(of: "."),
          let end = raw[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" })
    else { return nil }
    let fraction = raw[raw.index(after: dot)..<end]
    let trimmed = fraction.prefix(3)
    let collapsed = String(raw[..<dot]) + "." + trimmed + String(raw[end...])
    return formatters[0].date(from: collapsed) ?? formatters[1].date(from: String(raw[..<dot]) + String(raw[end...]))
}

func formatExpiry(_ date: Date) -> String {
    let seconds = date.timeIntervalSince1970
    let whole = floor(seconds)
    var micros = Int((seconds - whole) * 1_000_000)
    if micros >= 1_000_000 { micros = 999_999 }
    if micros < 0 { micros = 0 }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    let stamp = formatter.string(from: Date(timeIntervalSince1970: whole))
    return String(format: "%@.%06dZ", stamp, micros)
}

func loadSession() throws -> Session {
    let url = authURL()
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw UsageError.message("No Grok login. Run grok login.")
    }
    let data = try Data(contentsOf: url)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw UsageError.message("Could not read the Grok login.")
    }
    for (key, value) in root {
        guard let entry = value as? [String: Any],
              let token = entry["key"] as? String, !token.isEmpty else { continue }
        return Session(
            entryKey: key,
            accessToken: token,
            refreshToken: entry["refresh_token"] as? String,
            expiresAt: (entry["expires_at"] as? String).flatMap(parseDate),
            issuer: (entry["oidc_issuer"] as? String) ?? "https://auth.x.ai",
            clientID: (entry["oidc_client_id"] as? String) ?? ""
        )
    }
    throw UsageError.message("Grok login has no token. Run grok login.")
}

func http(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
    var outcome: Result<(Data, HTTPURLResponse), Error>!
    let wait = DispatchSemaphore(value: 0)
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        defer { wait.signal() }
        if let error {
            outcome = .failure(error)
            return
        }
        guard let data, let http = response as? HTTPURLResponse else {
            outcome = .failure(UsageError.message("No response from Grok."))
            return
        }
        outcome = .success((data, http))
    }
    task.resume()
    wait.wait()
    return try outcome.get()
}

func persist(_ session: Session) throws {
    let url = authURL()
    let data = try Data(contentsOf: url)
    guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          var entry = root[session.entryKey] as? [String: Any] else {
        throw UsageError.message("Could not update the Grok login.")
    }
    entry["key"] = session.accessToken
    if let refreshToken = session.refreshToken {
        entry["refresh_token"] = refreshToken
    }
    if let expiresAt = session.expiresAt {
        entry["expires_at"] = formatExpiry(expiresAt)
    }
    root[session.entryKey] = entry
    let encoded = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
    let temp = url.deletingLastPathComponent()
        .appendingPathComponent(".auth.json.\(UUID().uuidString).tmp")
    try encoded.write(to: temp)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
    _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

func refresh(_ session: Session) throws -> Session {
    guard let refreshToken = session.refreshToken, !refreshToken.isEmpty else {
        throw UsageError.message("Grok login expired. Run grok login.")
    }
    guard !session.clientID.isEmpty else {
        throw UsageError.message("Grok login is missing a client id. Run grok login.")
    }
    let issuer = session.issuer.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard let url = URL(string: issuer + "/oauth2/token") else {
        throw UsageError.message("Grok login issuer is invalid.")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 20
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    var items = URLComponents()
    items.queryItems = [
        URLQueryItem(name: "grant_type", value: "refresh_token"),
        URLQueryItem(name: "refresh_token", value: refreshToken),
        URLQueryItem(name: "client_id", value: session.clientID),
    ]
    request.httpBody = items.percentEncodedQuery?.data(using: .utf8)

    let (data, response) = try http(request)
    guard (200...299).contains(response.statusCode) else {
        throw UsageError.message("Grok login expired. Run grok login.")
    }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let access = json["access_token"] as? String, !access.isEmpty else {
        throw UsageError.message("Grok did not return a new login.")
    }
    var updated = session
    updated.accessToken = access
    if let rotated = json["refresh_token"] as? String, !rotated.isEmpty {
        updated.refreshToken = rotated
    }
    let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? 21_600
    updated.expiresAt = Date().addingTimeInterval(expiresIn)
    try persist(updated)
    return updated
}

func usableSession(forceRefresh: Bool = false) throws -> Session {
    var session = try loadSession()
    if forceRefresh || session.isExpiring {
        session = try refresh(session)
    }
    return session
}

func doubleValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber { return number.doubleValue }
    return nil
}

struct Reading {
    var percent: Int
    var end: Date
}

func fetchReading(token: String) throws -> Reading {
    guard let url = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits") else {
        throw UsageError.message("Bad billing URL.")
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
    let (data, response) = try http(request)
    if response.statusCode == 401 || response.statusCode == 403 {
        throw UsageError.message("unauthorized")
    }
    guard (200...299).contains(response.statusCode) else {
        throw UsageError.message("Usage request failed (\(response.statusCode)).")
    }
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw UsageError.message("Usage response was not JSON.")
    }
    let config = (root["config"] as? [String: Any]) ?? root
    let period = config["currentPeriod"] as? [String: Any]
    let endRaw = (period?["end"] as? String) ?? (config["billingPeriodEnd"] as? String)
    guard let endRaw, let end = parseDate(endRaw) else {
        throw UsageError.message("Usage response has no reset time.")
    }
    let percent: Int
    if let value = doubleValue(config["creditUsagePercent"]) {
        percent = Int(value.rounded())
    } else if period != nil {
        percent = 0
    } else {
        throw UsageError.message("Usage response has no percent.")
    }
    return Reading(percent: min(max(percent, 0), 999), end: end)
}

func loadReading() throws -> Reading {
    let session = try usableSession()
    do {
        return try fetchReading(token: session.accessToken)
    } catch UsageError.message(let text) where text == "unauthorized" {
        let renewed = try refresh(session)
        return try fetchReading(token: renewed.accessToken)
    }
}

func compactLabel(percent: Int, end: Date, now: Date = Date()) -> String {
    let seconds = end.timeIntervalSince(now)
    if seconds < 24 * 3600 {
        let hours = Int(seconds / 3600)
        if hours >= 1 { return "\(percent)% [\(hours)H]" }
        let minutes = max(0, Int(seconds / 60))
        return "\(percent)% [\(minutes)M]"
    }
    let days = Int((seconds / 86_400).rounded())
    return "\(percent)% [\(max(days, 1))D]"
}

func detailLabel(end: Date, now: Date = Date()) -> String {
    let seconds = max(0, Int(end.timeIntervalSince(now)))
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3600
    let minutes = (seconds % 3600) / 60
    if days > 0 { return "\(days)d \(hours)h left" }
    if hours > 0 { return "\(hours)h \(minutes)m left" }
    return "\(minutes)m left"
}

func grokIcon() -> NSImage {
    let size = NSSize(width: 16, height: 16)
    if let url = Bundle.main.url(forResource: "grok", withExtension: "png"),
       let image = NSImage(contentsOf: url) {
        image.size = size
        image.isTemplate = true
        return image
    }
    let image = NSImage(size: size, flipped: false) { rect in
        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 1.6
        NSColor.black.setStroke()
        path.stroke()
        return true
    }
    image.isTemplate = true
    return image
}

final class MenuApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var status: NSStatusItem!
    let usageItem = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
    let timeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var reading: Reading?
    var lastError: String?
    var lastNetwork = Date.distantPast
    var busy = false
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: "NSStatusItem Visible GrokUsage")
        UserDefaults.standard.set(1100.0, forKey: "NSStatusItem Preferred Position GrokUsage")
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.autosaveName = "GrokUsage"
        status.isVisible = true

        usageItem.isEnabled = false
        timeItem.isEnabled = false

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(usageItem)
        menu.addItem(timeItem)
        menu.addItem(.separator())
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        if let button = status.button {
            button.image = grokIcon()
            button.imagePosition = .imageLeft
            button.title = " …"
        }
        status.menu = menu

        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if Date().timeIntervalSince(lastNetwork) > 60 {
            fetch()
        }
    }

    func tick() {
        paint()
        if Date().timeIntervalSince(lastNetwork) >= networkEvery {
            fetch()
        }
    }

    func paint() {
        if let reading {
            status.button?.title = " " + compactLabel(percent: reading.percent, end: reading.end)
            usageItem.title = "\(reading.percent)% used"
            timeItem.title = detailLabel(end: reading.end)
            timeItem.isHidden = false
        } else if let lastError {
            status.button?.title = " —"
            usageItem.title = lastError
            timeItem.isHidden = true
        }
    }

    func fetch() {
        if busy { return }
        busy = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try loadReading() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.lastNetwork = Date()
                switch result {
                case .success(let reading):
                    self.reading = reading
                    self.lastError = nil
                case .failure(let error):
                    if self.reading == nil {
                        self.lastError = error.localizedDescription
                    }
                }
                self.paint()
            }
        }
    }

    @objc func refreshNow() {
        lastNetwork = .distantPast
        fetch()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

if CommandLine.arguments.contains("--dump") {
    do {
        let reading = try loadReading()
        print(compactLabel(percent: reading.percent, end: reading.end))
        print(detailLabel(end: reading.end))
        exit(0)
    } catch {
        fputs(error.localizedDescription + "\n", stderr)
        exit(1)
    }
}

let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
let me = ProcessInfo.processInfo.processIdentifier
if running.contains(where: { $0.processIdentifier != me }) {
    exit(0)
}

let app = NSApplication.shared
let delegate = MenuApp()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
