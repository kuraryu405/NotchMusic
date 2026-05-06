import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var playerViewModel: MusicPlayerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                generalSection
                permissionsSection
                supportSection
            }
            .padding(20)
        }
        .frame(width: 500, height: 540)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { settingsViewModel.refreshPermissionStatus() }
        .alert(
            "NotchMusic Settings",
            isPresented: Binding(
                get: { settingsViewModel.alertMessage != nil },
                set: { if !$0 { settingsViewModel.alertMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    settingsViewModel.alertMessage = nil
                }
            },
            message: {
                Text(settingsViewModel.alertMessage ?? "")
            }
        )
        .sheet(isPresented: $settingsViewModel.isShowingPermissionHelp) {
            PermissionHelpView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NotchMusic Settings")
                .font(.system(size: 20, weight: .semibold))
            Text("初回セットアップと、動かないときの復帰をここから行えます。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var generalSection: some View {
        SettingsSection(title: "General", description: "毎回触りそうな設定です。") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { settingsViewModel.launchAtLoginEnabled },
                    set: { settingsViewModel.setLaunchAtLoginEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch At Login")
                        Text(settingsViewModel.launchAtLoginHint)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(!settingsViewModel.canConfigureLaunchAtLogin)

                Divider()

                LabeledContent("Playback") {
                    StatusBadge(
                        title: playbackTitle,
                        color: playbackColor
                    )
                }
            }
        }
    }

    private var permissionsSection: some View {
        SettingsSection(title: "Permissions", description: "音楽アプリとの連携状態を確認できます。") {
            VStack(alignment: .leading, spacing: 14) {
                permissionRow(
                    app: .appleMusic,
                    status: settingsViewModel.appleMusicPermissionStatus,
                    checkAction: settingsViewModel.requestAppleMusicAccess,
                    openAction: settingsViewModel.openAppleMusic
                )

                Divider()

                permissionRow(
                    app: .spotify,
                    status: settingsViewModel.spotifyPermissionStatus,
                    checkAction: settingsViewModel.requestSpotifyAccess,
                    openAction: settingsViewModel.openSpotify
                )

                Divider()

                HStack(spacing: 10) {
                    Button("再接続") {
                        playerViewModel.restartObserving()
                        settingsViewModel.refreshPermissionStatus()
                    }
                    Button("設定手順") {
                        settingsViewModel.isShowingPermissionHelp = true
                    }
                }
            }
        }
    }

    private func permissionRow(
        app: ScriptableMusicApp,
        status: MusicAppPermissionStatus,
        checkAction: @escaping () -> Void,
        openAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(app.displayName) Automation")
                        .font(.system(size: 13, weight: .medium))
                    Text(status.detail(for: app))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                StatusBadge(
                    title: status.title(for: app),
                    color: Color(status.tint)
                )
            }

            HStack(spacing: 10) {
                Button("アクセス確認", action: checkAction)
                Button("\(app.displayName) を開く", action: openAction)
            }
        }
    }

    private var supportSection: some View {
        SettingsSection(title: "Support", description: "うまく動かないときのショートカットです。") {
            HStack(spacing: 10) {
                Button("System Settings を開く") {
                    settingsViewModel.openSystemSettings()
                }
                Button("ログを開く") {
                    settingsViewModel.openLogFile()
                }
                Button("状態を更新") {
                    settingsViewModel.refreshState()
                    settingsViewModel.refreshPermissionStatus()
                }
            }
        }
    }

    private var playbackTitle: String {
        if playerViewModel.isPlaying {
            return "再生中"
        }
        if playerViewModel.currentTrack != nil {
            return "一時停止中"
        }
        return "待機中"
    }

    private var playbackColor: Color {
        if playerViewModel.isPlaying {
            return .green
        }
        if playerViewModel.currentTrack != nil {
            return .orange
        }
        return .secondary
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let description: String
    private let content: Content

    init(title: String, description: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
    }
}

private struct PermissionHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("音楽アプリ権限の通し方")
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text("1. 使う音楽アプリを開いて前面に出します。")
                Text("2. `アクセス確認` を押すと、必要に応じて macOS の確認ダイアログが表示されます。")
                Text("3. 拒否済みだった場合は `System Settings` を開き、`Privacy & Security > Automation` で NotchMusic から Music または Spotify を許可します。")
                Text("4. 設定後に `再接続` を押すと再取得しやすくなります。")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("閉じる") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
