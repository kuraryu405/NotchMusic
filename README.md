
# NotchMusic

MacBookのノッチをDynamic Island風の音楽プレーヤーに変えるmacOSアプリ。

![macOS](https://img.shields.io/badge/macOS-14.0+-black) ![Swift](https://img.shields.io/badge/Swift-6.2-orange) ![License](https://img.shields.io/badge/license-MIT-blue)

## 概要

Apple Musicで再生中の曲をノッチエリアに表示します。ホバーするとアルバムアートや再生コントロールが展開されます。

## 機能

- ノッチ左側にアルバムアート、右側に音楽バーを表示
- ホバーで展開 → アルバムアート・曲名・アーティスト・シークバー・コントロール
- 曲が変わると3秒間自動展開
- ログイン時自動起動対応（LaunchAgent）
- ノッチサイズを動的に検出 → MacBook Pro / Air M2/M3 すべて対応

## CPU使用率

常駐アプリとして軽量動作を重視して設計しています。

| 状態 | CPU使用率 |
|---|---|
| 再生中（非ホバー） | ~5% |
| 再生中（カード展開中） | ~8% |
| 一時停止中 | ~0% |

### 他アプリとの比較

| アプリ | CPU使用率（目安） |
|---|---|
| **NotchMusic** | **~5%** |
| PopClip などの常駐アプリ | 5〜15% |
| Notchmeister | 10〜20% |
| Navi (歌詞表示) | 10〜20% |

低CPU使用率を実現するための工夫：
- 音楽バーアニメーションに `TimelineView + Canvas` を採用（SwiftUI `repeatForever` を廃止）
- 非ホバー時は5fps、ホバー時のみ20fpsに切り替え
- ポーリング間隔5秒 + 一時停止中はタイマー停止（通知ベースに切り替え）
- 2ウィンドウ構成（ピルウィンドウ固定 + カードウィンドウのみアニメーション）

## 動作環境

- macOS 14 Sonoma 以降（macOS 26 Beta 動作確認済み）
- ノッチ付き MacBook（Pro 14/16", Air 13"/15" M2/M3 以降）
- Apple Music

## インストール

```bash
git clone [https://github.com/kuraryu405/NotchMusic.git](https://github.com/kuraryu405/NotchMusic.git)
cd NotchMusic
swift build -c release
cp -r .build/release/NotchMusic /Applications/NotchMusic.app/Contents/MacOS/NotchMusic
open /Applications/NotchMusic.app
