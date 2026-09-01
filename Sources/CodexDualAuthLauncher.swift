import AppKit
import SwiftUI

@MainActor
final class LauncherModel: ObservableObject {
    struct ConnectorAccount: Equatable {
        let email: String?
        let planType: String?

        var displayName: String {
            guard let email, !email.isEmpty else { return "ChatGPT account" }
            return email
        }

        var planDisplayName: String? {
            guard let planType, !planType.isEmpty else { return nil }
            let knownNames = [
                "free": "Free",
                "plus": "Plus",
                "pro": "Pro",
                "prolite": "Pro Lite",
                "team": "Team",
                "business": "Business",
                "enterprise": "Enterprise",
                "edu": "Education",
            ]
            return "\(knownNames[planType.lowercased()] ?? planType.capitalized) plan"
        }
    }

    enum LoginState {
        case checking
        case signedOut
        case signedIn(ConnectorAccount)
        case working
        case error(String)
    }

    @Published var loginState: LoginState = .checking
    @Published var launchMessage = ""

    private let fileManager = FileManager.default

    var connectorHome: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Codex Dual Auth", isDirectory: true)
            .appendingPathComponent("connector-account", isDirectory: true)
    }

    private var bundledCodex: URL? {
        Bundle.main.url(forResource: "codex-dual-auth", withExtension: nil)
    }

    var statusText: String {
        switch loginState {
        case .checking: return "Checking connector account…"
        case .signedOut: return "Connector account is not signed in"
        case .signedIn: return "Connector account connected"
        case .working: return "Waiting for browser sign-in…"
        case .error(let message): return message
        }
    }

    var isBusy: Bool {
        switch loginState {
        case .checking, .working: return true
        default: return false
        }
    }

    var connectedAccount: ConnectorAccount? {
        guard case .signedIn(let account) = loginState else { return nil }
        return account
    }

    func refreshStatus() async {
        loginState = .checking
        do {
            try prepareConnectorHome()
            if let account = try await readConnectorAccount() {
                loginState = .signedIn(account)
            } else {
                loginState = .signedOut
            }
        } catch {
            loginState = .error(error.localizedDescription)
        }
    }

    func signIn() async {
        await authenticate(clearExistingAccount: false)
    }

    func changeAccount() async {
        await authenticate(clearExistingAccount: true)
    }

    private func authenticate(clearExistingAccount: Bool) async {
        loginState = .working
        launchMessage = clearExistingAccount
            ? "Signing out the current connector profile, then opening ChatGPT sign-in…"
            : "Your browser will open. Sign in with the ChatGPT account that owns identity 2's Apps."
        do {
            try prepareConnectorHome()
            if clearExistingAccount {
                let logoutResult = try await runConnectorCodex(arguments: ["logout"])
                guard logoutResult.exitCode == 0 else {
                    loginState = .error("Could not sign out the current connector account.")
                    launchMessage = logoutResult.summary
                    return
                }
            }
            let result = try await runConnectorCodex(arguments: ["login"])
            if result.exitCode == 0 {
                if let account = try await readConnectorAccount() {
                    loginState = .signedIn(account)
                    launchMessage = "Connected as \(account.displayName)."
                } else {
                    loginState = .error("Sign-in finished, but no ChatGPT account was returned.")
                    launchMessage = "Try Change Account and complete the browser sign-in again."
                }
            } else {
                loginState = .error("Connector sign-in did not finish.")
                launchMessage = result.summary
            }
        } catch {
            loginState = .error(error.localizedDescription)
        }
    }

    func launchCodex() async {
        launchMessage = ""
        await refreshStatus()
        guard connectedAccount != nil else {
            launchMessage = "Sign in to the connector account first."
            return
        }

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
        guard running.isEmpty else {
            launchMessage = "Codex is already running. Quit it normally, then press Launch Codex again so the dual-auth environment is applied at startup."
            return
        }
        guard let codexURL = bundledCodex else {
            launchMessage = "The packaged dual-auth Codex binary is missing."
            return
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex"),
              let appExecutable = Bundle(url: appURL)?.executableURL,
              fileManager.isExecutableFile(atPath: appExecutable.path) else {
            launchMessage = "Install the official Codex desktop app first."
            return
        }

        do {
            let process = Process()
            process.executableURL = appExecutable
            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_CLI_PATH"] = codexURL.path
            environment["CODEX_CONNECTORS_HOME"] = connectorHome.path
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            launchMessage = "Codex launched. Threads and model usage remain on account A; built-in Apps use the connector account."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                NSApp.terminate(nil)
            }
        } catch {
            launchMessage = "Could not launch Codex: \(error.localizedDescription)"
        }
    }

    func revealConnectorProfile() {
        try? prepareConnectorHome()
        NSWorkspace.shared.activateFileViewerSelecting([connectorHome])
    }

    private func prepareConnectorHome() throws {
        try fileManager.createDirectory(
            at: connectorHome,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: connectorHome.path)
    }

    private struct CommandResult: Sendable {
        let exitCode: Int32
        let summary: String
    }

    private struct AccountReadResult: Decodable {
        struct Account: Decodable {
            let email: String?
            let planType: String?
            let type: String
        }

        let account: Account?
    }

    private struct AccountReadEnvelope: Decodable {
        let id: String?
        let result: AccountReadResult?
    }

    private func readConnectorAccount() async throws -> ConnectorAccount? {
        guard let codexURL = bundledCodex else {
            throw NSError(
                domain: "CodexDualAuthLauncher",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The packaged dual-auth Codex binary is missing."]
            )
        }
        let home = connectorHome
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = codexURL
            process.arguments = ["app-server", "--listen", "stdio://"]
            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_HOME"] = home.path
            environment.removeValue(forKey: "CODEX_CONNECTORS_HOME")
            environment.removeValue(forKey: "CODEX_CONNECTORS_TOKEN")
            process.environment = environment

            let input = Pipe()
            let output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()

            let requests: [[String: Any]] = [
                [
                    "id": "initialize",
                    "method": "initialize",
                    "params": [
                        "clientInfo": [
                            "name": "codex_dual_auth_launcher",
                            "title": "Codex Dual Auth Launcher",
                            "version": "0.1.4",
                        ],
                        "capabilities": ["experimentalApi": true],
                    ],
                ],
                ["method": "initialized"],
                [
                    "id": "account",
                    "method": "account/read",
                    "params": ["refreshToken": false],
                ],
            ]
            let requestData = try requests.reduce(into: Data()) { data, request in
                data.append(try JSONSerialization.data(withJSONObject: request))
                data.append(0x0A)
            }
            try input.fileHandleForWriting.write(contentsOf: requestData)

            let decoder = JSONDecoder()
            var responseBuffer = Data()
            var receivedAccountResponse = false
            var connectorAccount: ConnectorAccount?
            readLoop: while process.isRunning {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                responseBuffer.append(chunk)
                while let newlineIndex = responseBuffer.firstIndex(of: 0x0A) {
                    let line = responseBuffer[..<newlineIndex]
                    responseBuffer.removeSubrange(...newlineIndex)
                    guard let envelope = try? decoder.decode(
                        AccountReadEnvelope.self,
                        from: Data(line)
                    ), envelope.id == "account" else { continue }
                    receivedAccountResponse = true
                    if let account = envelope.result?.account, account.type == "chatgpt" {
                        connectorAccount = ConnectorAccount(
                            email: account.email,
                            planType: account.planType
                        )
                    }
                    break readLoop
                }
            }
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            if receivedAccountResponse { return connectorAccount }
            throw NSError(
                domain: "CodexDualAuthLauncher",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The connector account status response was incomplete."]
            )
        }.value
    }

    private func runConnectorCodex(arguments: [String]) async throws -> CommandResult {
        guard let codexURL = bundledCodex else {
            throw NSError(
                domain: "CodexDualAuthLauncher",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The packaged dual-auth Codex binary is missing."]
            )
        }
        let home = connectorHome
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = codexURL
            process.arguments = [
                "-c", "cli_auth_credentials_store=\"file\"",
            ] + arguments
            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_HOME"] = home.path
            environment.removeValue(forKey: "CODEX_CONNECTORS_HOME")
            environment.removeValue(forKey: "CODEX_CONNECTORS_TOKEN")
            process.environment = environment

            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let text = String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .suffix(4)
                .joined(separator: "\n")
            return CommandResult(exitCode: process.terminationStatus, summary: text)
        }.value
    }
}

struct ContentView: View {
    @StateObject private var model = LauncherModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "person.2.badge.gearshape")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Codex Dual Auth")
                        .font(.title2.weight(.semibold))
                    Text("One Codex account, a separate Apps identity")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Label(model.statusText, systemImage: statusIcon)
                .foregroundStyle(statusColor)

            if let account = model.connectedAccount {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName)
                            .font(.headline)
                            .textSelection(.enabled)
                        if let plan = account.planDisplayName {
                            Text(plan)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Connected")
                }
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }

            Text("Account A stays signed in through the official Codex app. This helper stores account B in a separate folder and routes only built-in Apps such as GitHub, Jira, Slack, and Vercel through it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if model.connectedAccount == nil {
                    Button("Sign In Connector Account") {
                        Task { await model.signIn() }
                    }
                    .disabled(model.isBusy)
                } else {
                    Button("Change Account…") {
                        Task { await model.changeAccount() }
                    }
                    .disabled(model.isBusy)
                }

                Button("Launch Codex") {
                    Task { await model.launchCodex() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || model.connectedAccount == nil)
            }

            if !model.launchMessage.isEmpty {
                Text(model.launchMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Show isolated connector profile") {
                model.revealConnectorProfile()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(24)
        .frame(width: 520, height: 500)
        .task { await model.refreshStatus() }
    }

    private var statusIcon: String {
        switch model.loginState {
        case .signedIn: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .checking, .working: return "clock.fill"
        case .signedOut: return "person.crop.circle.badge.questionmark"
        }
    }

    private var statusColor: Color {
        switch model.loginState {
        case .signedIn: return .green
        case .error: return .orange
        default: return .primary
        }
    }
}

@main
struct CodexDualAuthLauncherApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
