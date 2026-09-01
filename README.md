# Codex Dual Auth Launcher

Use account A for Codex threads, model usage, history, and subscription billing while the built-in Codex Apps use the connections attached to account B.

This is an experimental, unofficial macOS launcher. It patches the open-source Codex app-server and starts the unmodified official Codex desktop app with the patched binary. You do not need to ask Codex to use a custom MCP tool: GitHub, Jira, Slack, Vercel, and other built-in Apps keep their normal names and behavior.

## Install on the second Mac

Prerequisites: Apple-silicon Mac running macOS 14 or later, with the official Codex desktop app already installed and signed in to account A.

```sh
/bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/Rana-Faraz/codex-dual-auth-launcher/main/install.sh)"
```

The installer downloads the pinned `v0.1.0` release, checks its SHA-256 digest and code signature, installs it to `~/Applications/Codex Dual Auth.app`, and opens it. It does not modify the official Codex app.

Then:

1. Quit Codex normally if it is running.
2. Open **Codex Dual Auth** and click **Sign In Connector Account**.
3. In the browser, sign in to ChatGPT account B—the account whose GitHub, Jira, Slack, Vercel, or other Apps are connected.
4. Return to the launcher and click **Launch Codex**.

Use **Codex Dual Auth** whenever starting this isolated Apps profile. Starting Codex normally continues to use account A for both the model and Apps.

## What is isolated

| Concern | Identity/storage used |
| --- | --- |
| Threads, history, model requests, usage | Account A and the normal Codex home |
| Built-in `codex_apps` discovery and tool calls | Account B |
| Account B login and connector cache | `~/Library/Application Support/Codex Dual Auth/connector-account` |

The app-server creates a second refresh-capable authentication manager and passes it only to the reserved `codex_apps` server. The normal model, thread, and usage paths retain account A. It fails closed when the connector profile is missing or is not a ChatGPT login.

OpenAI documents the underlying [Codex app-server protocol](https://developers.openai.com/codex/app-server/) and [Codex authentication storage](https://developers.openai.com/codex/auth/). The dual-auth behavior itself is an experiment, not an officially supported OpenAI feature.

## Security and limitations

- No credentials or tokens are included in this repository or release. Account B's login stays in the isolated local profile.
- Data returned by account B's Apps becomes part of the Codex conversation processed under account A. Use accounts and workspaces whose data-sharing rules permit that.
- The release is ad-hoc signed and is not Apple-notarized. Its installer verifies the pinned SHA-256 digest and the bundle signature but does not remove macOS quarantine attributes or weaken Gatekeeper.
- The launcher currently targets Apple-silicon macOS 14+.
- Codex Desktop's internal app-server integration can change. This release is pinned to upstream Codex commit [`8209978`](https://github.com/openai/codex/commit/82099786163f3c05facf09078136679e18b64279).
- Quit Codex before launching. The helper deliberately refuses to terminate an existing session, so it cannot discard active work.

## Build from source

Install Rust and Xcode Command Line Tools, then run:

```sh
git clone https://github.com/Rana-Faraz/codex-dual-auth-launcher.git
cd codex-dual-auth-launcher
./build-helper.sh
```

The script fetches the pinned upstream Codex revision, applies [`patches/codex-dual-auth.patch`](patches/codex-dual-auth.patch), builds the Rust CLI and SwiftUI launcher, strips symbols, ad-hoc signs the app, and writes the result to `dist/`.

## Validation performed for v0.1.0

- `cargo check -p codex-mcp -p codex-core -p codex-app-server`
- All 215 `codex-mcp` tests through the repository's `just test`/Nextest harness
- Swift type-check and property-list validation
- Deep strict signature verification on the packaged app
- A live JSON-RPC `initialize` smoke test with independent account A and account B profiles; the app-server remained healthy and selected the isolated Apps identity

The complete upstream Codex test suite was not run. The focused checks above cover the modified build boundary and connector routing, but this remains experimental software.

## License

Apache-2.0. The patch is based on [OpenAI Codex](https://github.com/openai/codex), also licensed under Apache-2.0.
