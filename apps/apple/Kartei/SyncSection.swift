// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// Settings → Sync: log in to a self-hosted Anki sync server, sync now, one-way sync, log out.
struct SyncSection: View {
    let store: DeckStore
    @State private var sync = SyncController.shared
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var problem: String?
    @State private var confirmLogout = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sync").font(Type.display(22, heavy: true)).foregroundStyle(Ink.text)
            if let account = sync.account { loggedIn(account) } else { loginForm }
            Text("Bergmönch syncs only with a sync server you run yourself, such as the one built into Anki or anki-sync-server. AnkiWeb is not offered: its terms only allow Anki's own apps.")
                .font(Type.body(12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.control).frame(height: 1) }
        .syncChoiceDialog(sync)
        .onAppear { Reach.storeDidUpdate(store) }
    }

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Server address", text: $server, prompt: "http://192.168.1.20:8080")
                .textContentType(.URL)
            #if os(iOS)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            #endif
            field("Username", text: $username, prompt: "")
                .textContentType(.username)
            #if os(iOS)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            #endif
            VStack(alignment: .leading, spacing: 2) {
                Text("Password").font(Type.body(12, 500)).foregroundStyle(Ink.muted)
                SecureField("", text: $password).textContentType(.password).onSubmit(logIn)
                    .textFieldStyle(.plain).font(Type.body(16)).foregroundStyle(Ink.text).frame(minHeight: 36)
                Rectangle().fill(Ink.control).frame(height: 1)
            }
            Text("Only a login key is kept, in the Keychain; your password is not stored.")
                .font(Type.body(12)).foregroundStyle(Ink.muted)
            if let problem { Text(problem).font(Type.body(13)).foregroundStyle(Ink.forgot).fixedSize(horizontal: false, vertical: true) }
            Button(action: logIn) {
                Text(sync.isBusy ? "Logging in…" : "Log in and sync").font(Type.display(18, heavy: true)).foregroundStyle(Ink.onAccent)
                    .padding(.horizontal, 24).frame(minHeight: 48).primarySurface()
            }
            .buttonStyle(.plain).disabled(sync.isBusy || store.backend == nil)
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Type.body(12, 500)).foregroundStyle(Ink.muted)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(Ink.muted))
                .textFieldStyle(.plain).font(Type.body(16)).foregroundStyle(Ink.text).frame(minHeight: 36)
            Rectangle().fill(Ink.control).frame(height: 1)
        }
    }

    private func logIn() {
        problem = nil
        Task {
            if let p = await sync.login(server: server, username: username, password: password) { problem = p.text } else { password = "" }
        }
    }

    private func loggedIn(_ account: SyncAccount) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(account.username) on \(account.host)").font(Type.body(15, 500)).foregroundStyle(Ink.text)
                Spacer()
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(statusText(now: context.date)).font(Type.body(13)).foregroundStyle(statusIsError ? Ink.forgot : Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let msg = sync.serverMessage { Text("Server: \(msg)").font(Type.body(13)).foregroundStyle(Ink.text) }
            HStack(spacing: 20) {
                Button { sync.sync() } label: {
                    Text("Sync now").font(Type.display(18, heavy: true)).foregroundStyle(Ink.onAccent)
                        .padding(.horizontal, 24).frame(minHeight: 48).primarySurface()
                }
                .buttonStyle(.plain).disabled(sync.isBusy)
                Button("One-way sync…") { sync.requestFullSync() }
                    .buttonStyle(.plain).font(Type.body(15, 500)).foregroundStyle(Ink.text).underline().frame(minHeight: 44).disabled(sync.isBusy)
                Spacer()
                Button("Log out") { confirmLogout = true }
                    .buttonStyle(.plain).font(Type.body(15, 500)).foregroundStyle(Ink.text).underline().frame(minHeight: 44).disabled(sync.isBusy)
            }
        }
        .confirmationDialog("Log out of \(account.host)?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { sync.logout() }
        } message: {
            Text("Your cards stay on this device. Log in again to resume syncing.")
        }
    }

    private var statusIsError: Bool { if case .failed = sync.status { return true }; return false }

    private func statusText(now: Date) -> String {
        switch sync.status {
        case .working(let what): return what + "…"
        case .failed(let why): return why
        case .needsChoice: return "Waiting for your choice: upload or download."
        case .idle: return SyncText.syncedAgo(sync.lastSync, now: now) + "."
        }
    }
}

/// Home topline: "↻ Synced 2 min ago"; tap to sync. Hidden until logged in.
struct SyncStatusLine: View {
    let store: DeckStore
    @State private var sync = SyncController.shared
    @State private var showError = false

    var body: some View {
        Group {
            if sync.account != nil {
                Button(action: tap) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        ViewThatFits(in: .horizontal) {
                            label(long: true, now: context.date)
                            label(long: false, now: context.date)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityHint(failed == nil ? "Syncs now" : "Shows what went wrong")
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
        // The collection opens after the view appears; connect sync, the widget and reminders as soon as it does.
        .onChange(of: store.backend != nil, initial: true) { _, ready in if ready { Reach.storeDidUpdate(store) } }
        .syncChoiceDialog(sync)
        .alert("Sync did not finish", isPresented: $showError) {
            Button("Try again") { sync.sync() }
            Button("OK", role: .cancel) {}
        } message: { Text(failed ?? "") }
    }

    private var failed: String? { if case .failed(let why) = sync.status { return why }; return nil }

    private func tap() { if failed != nil { showError = true } else { sync.sync() } }

    private func label(long: Bool, now: Date) -> some View {
        HStack(spacing: 4) {
            Image(systemName: failed != nil ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath")
                .font(Type.symbol(11, .semibold))
                .symbolEffect(.pulse, isActive: sync.isBusy)
            Text(text(long: long, now: now)).lineLimit(1)
        }
        .font(Type.body(13, 500))
        .foregroundStyle(failed != nil ? Ink.forgot : Ink.muted)
        .fixedSize()
    }

    private func text(long: Bool, now: Date) -> String {
        switch sync.status {
        case .working: return "Syncing…"
        case .failed: return "Sync failed"
        case .needsChoice: return "Choose sync"
        case .idle:
            let s = SyncText.syncedAgo(sync.lastSync, now: now)
            return long ? s : s.replacingOccurrences(of: "Synced ", with: "")
        }
    }
}

private struct SyncChoiceDialog: ViewModifier {
    let sync: SyncController

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Keep which copy?",
            isPresented: Binding(get: { sync.status == .needsChoice }, set: { if !$0 { sync.cancelFullSync() } }),
            titleVisibility: .visible
        ) {
            Button("Upload this device", role: .destructive) { sync.resolveFullSync(upload: true) }
            Button("Download from server", role: .destructive) { sync.resolveFullSync(upload: false) }
            Button("Not now", role: .cancel) { sync.cancelFullSync() }
        } message: {
            Text("This device and the server have changes that cannot be merged. Upload replaces the server's cards with this device's; download replaces this device's cards with the server's. Reviews only on the replaced side are lost.")
        }
    }
}

extension View {
    func syncChoiceDialog(_ sync: SyncController) -> some View { modifier(SyncChoiceDialog(sync: sync)) }
}
