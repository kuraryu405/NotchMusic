# NotchMusic 開発引き継ぎ

## アプリ概要

macOS のノッチ領域に動的に音楽情報を表示する常駐アプリ。
iPhoneのDynamic Islandにインスパイアされたデザイン。

- ビルド: `swift build -c release`
- デプロイ: `cp .build/release/NotchMusic NotchMusic.app/Contents/MacOS/NotchMusic && codesign --force --deep --sign - --identifier "dev.notchmusic.app" NotchMusic.app`
- 起動: `open NotchMusic.app`
- ログ: `/tmp/notchmusic.log`

## 現在の構成

```
Sources/NotchMusic/
  main.swift               — エントリポイント + debugLog()
  App/AppDelegate.swift    — NSApp設定、ステータスバーメニュー
  Window/
    NotchGeometry.swift    — ノッチ座標検出（auxiliaryTopLeftArea/TopRightArea）
    NotchWindowManager.swift — 2ウィンドウ管理（pillWindow + cardWindow）
  Views/
    NotchRootView.swift    — PillView（ピル）+ CardView（カード）
    CompactView.swift      — DualPillView + MusicBarsView
    ExpandedView.swift     — 展開カード（アート・曲情報・シークバー・ボタン）
  ViewModels/
    MusicPlayerViewModel.swift — @Published状態、ホバー制御
  Services/
    AppleMusicService.swift    — Apple Music連携（通知＋AppleScript）
    MusicServiceProtocol.swift — サービスプロトコル
  Models/
    Track.swift            — 曲情報モデル（artwork: NSImage?含む）
```

## 2ウィンドウアーキテクチャ（重要）

```
pillWindow  → 常時表示、絶対に動かない。ノッチ幅(360pt)×ノッチ高さ(43pt)
cardWindow  → 展開時のみ表示。ノッチ下端から下方向にアニメーション展開
              collapsed: y=notchMinY-1, height=1, alpha=0
              expanded:  y=notchMinY-120, height=120, alpha=1
```

ホバー制御は `MusicPlayerViewModel.onHoverEntered()` / `onHoverLeft()` で一元管理。
両ウィンドウからこれを呼ぶことで、ウィンドウ間の隙間を通過しても0.5sディレイで閉じない。

## 音楽検出

- **主経路**: `com.apple.Music.playerInfo` 分散通知 → 曲変更を即時検出
- **ポーリング**: NSAppleScript 2秒毎（進捗更新目的）→ TCC権限が必要
- **アートワーク**: iTunes Search API (`itunes.apple.com/search`) → 100x100 → 600x600に差し替え

TCC権限（AppleEvents for Music.app）がないとポーリングが空を返す。
`tccutil reset AppleEvents dev.notchmusic.app` でリセット後、再起動すると権限ダイアログが出る。

## 主要な寸法（NotchGeometry）

| 定数 | 値 | 説明 |
|------|-----|------|
| expandedWidth | 360pt | ウィンドウ常時幅 |
| expandedHeight | 120pt | カード高さ |
| notchFrame | (899, 1287, 250, 43) | 検出されたノッチ座標（変わる場合あり） |
| sideW | (360-250)/2 = 55pt | ノッチ両端のピル幅 |

## デザインの現状

### 完成済み
- [x] ノッチ両端デュアルピル（左:アート、右:バー）
- [x] ピル形状: 上端フラット（画面上端と密着）、下端外角のみ丸み
- [x] 展開時に下角を0にアニメーション（カードと継ぎ目なし）
- [x] 純黒背景（Color.black）でノッチと色一致
- [x] カードボーダー (white 0.15, 0.5pt)
- [x] シークバー 2px、ホバー時4px+サム表示
- [x] 時間表示 (0:45 / 3:20)
- [x] ボタンホバーエフェクト（scale 1.15 + 円形背景）
- [x] アートワーク: iTunes Search API経由で取得
- [x] アートワーク消滅バグ修正（Track.== に artwork===比較追加）
- [x] ホバー0.5sディレイ（隙間通過でも閉じない）
- [x] アニメーション: spring(response:0.4, dampingFraction:0.7)
- [x] コンテンツはカード展開と同時に表示（ディレイなし）
- [x] カードのshadow削除（角丸外に黒滲み出るバグ対処）

### 残課題 / 改善案
- [ ] ノッチ形状の再現精度：ノッチ底辺の凸カーブにカードを密着させる（現状は直角フラット接続）
- [ ] AppleScript TCC権限の案内UI（権限なしでもポーリングが静かに失敗する）
- [ ] Spotifyサポート（MusicServiceProtocol実装済み、SpotifyService未実装）
- [ ] カラーテーマ：アルバムアートから抽出したアクセントカラーをUIに反映
- [ ] シークバーをインタラクティブに（クリックでシーク）
- [ ] LaunchAgent対応（ログイン時自動起動）
- [ ] GitHub Actions CI（macos-14ランナー、.github/workflows/ci.ymlあり）

## Track.== の注意点

```swift
static func == (lhs: Track, rhs: Track) -> Bool {
    lhs.title  == rhs.title  &&
    lhs.artist == rhs.artist &&
    lhs.album  == rhs.album  &&
    lhs.artwork === rhs.artwork   // NSImage参照比較 — これがないとSwiftUIが再描画しない
}
```

artwork の比較は `===`（参照等値）必須。`==` にすると NSImage は Equatable 未準拠でエラー。
かつアート付きトラックへの更新時に SwiftUI が「変化なし」と判断して再描画をスキップする。

## よくあるトラブル

| 症状 | 原因 | 対処 |
|------|------|------|
| ピルが表示されない | 曲が停止中 | Apple Musicで再生開始 |
| アートワークが出ない | iTunes API の遅延 or 曲名不一致 | 数秒待つ、または別曲で確認 |
| 座標が大幅にズレる | 外部モニターをメインにしている | Built-in Display をメインに |
| ポーリングが空 | TCC未許可 | `tccutil reset AppleEvents dev.notchmusic.app` → 再起動 |
