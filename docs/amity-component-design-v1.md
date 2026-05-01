# Amity-QSO コンポーネント設計書 v1.0

> **文書管理**
> | 項目 | 内容 |
> |---|---|
> | 文書バージョン | 1.0 |
> | ステータス | 確定 |
> | 上位文書 | PRD v2.1, 基本設計書 v1.1 |
> | 関連文書 | クラス設計書 v2.1（各コンポーネントの Pascal 宣言を収録） |
> | 対象読者 | 実装担当エンジニア・アーキテクト・将来のライブラリ利用者 |

---

## 改訂履歴

| バージョン | 日付 | 変更概要 |
|---|---|---|
| 1.0 | 初版 | 全コンポーネントカタログ・依存グラフ・ロードマップを策定 |

---

## 用語定義

| 用語 | 定義 |
|---|---|
| コンポーネント | 独立してビルド・テスト・再利用できる機能単位。他モジュールとはインターフェース型のみで接続する。 |
| ライブラリ化候補 | Amity-QSO 外からも参照可能な独立ライブラリとして抽出する予定のコンポーネント（M・H カテゴリ）。`lib/` 下に配置する。 |
| アダプター | `lib/` コンポーネントと `src/` のアプリ固有型（TQSOData 等）の間の変換クラス。`src/` 側に配置し、`lib/` 側の純粋性を維持する。 |
| 独立ビルド | そのコンポーネントのみを `lazbuild` でコンパイルし、単体テストを実行できる状態。 |

---

## 1. コンポーネント化の目的と設計原則

### 1.1 目的

本プロジェクトのコンポーネント化は以下の3目的を持つ。PRD v2.1 の F-REUSE-01〜08 がこれらの要件を規定している。

**目的1 — 保守性の向上**
変更頻度の高い領域（デジタルモード追加・リグプロトコル追加）を独立コンポーネントにすることで、変更の影響範囲を構造的に限定する。新モード追加が SeqCtrl・UI・DBWorker に波及しない設計を OCP により保証する。

**目的2 — テスト容易性の向上**
各コンポーネントをハードウェア（リグ・音声デバイス・DSP プロセス）なしで単体テストできる設計とする。`TSimulatorProtocol`・`TNullCodec`・`TMemoryCtyProvider` 等のテストダブルを各コンポーネントに付属させる。

**目的3 — 再利用性の確保**
ADIF I/O・コールサインリゾルバ・LWW 同期エンジン等をアマチュア無線ドメインの共有ライブラリとして抽出し、Amity-QSO 以外のツール（コンテストロガー・クラスタービューア・ログ変換ツール等）の開発基盤とする。

### 1.2 SOLID 原則との対応

| 原則 | コンポーネント設計への適用 |
|---|---|
| SRP | 各コンポーネントは単一の変更理由のみを持つ。`TRigController` はプロトコル変更に依存しない。 |
| OCP | `IDecodeEngine`・`IRigProtocol` 等の抽象により、新実装の追加が既存コードの変更を不要にする。 |
| LSP | テストダブル（`TNullCodec`・`TSimulatorProtocol` 等）は本番実装と完全に置換可能な事前・事後条件を持つ。 |
| ISP | `IRigVFOControl`・`IRigPTTControl`・`IRigModeControl` 等、利用者が必要なメソッドのみを持つインターフェースに分割する。 |
| DIP | `lib/` コンポーネントは抽象インターフェースのみに依存し、具体クラスを参照しない。 |

### 1.3 コンポーネント境界の強制ルール

以下のルールは基本設計書 v1.1 第15章と同等の強制力を持ち、全プルリクエストでコードレビューの確認対象とする。

| ルール | 内容 | 検出方法 |
|---|---|---|
| 一方向依存 | `lib/` 内のコードは `src/` を `uses` しない | CI で `grep` による静的チェック |
| インターフェース接続 | コンポーネント間は宣言インターフェース型のみで接続する | コードレビュー |
| アダプター配置 | `lib/` ↔ `src/` 型変換は `src/` 側アダプタークラスが担う | コードレビュー |
| 独立ビルド | M・H カテゴリは単独の `.lpi` ファイルを持ち、単体ビルドが CI で確認される | CI パイプライン |

---

## 2. コンポーネントカタログ

### 2.1 カテゴリ概要

```
┌────────────────────────────────────────────────────────────────┐
│  再利用範囲: 広（他アプリ転用可）  ←────────→  狭（Amity固有）│
│                                                                  │
│  高  M: 汎用ミドルウェア            H: 無線ドメインライブラリ   │
│  ↑   (LWW同期, Lua, DB移行等)        (ADIF, Callsign, Band等)   │
│  │                                                              │
│  保  T: 技術インフラ部品             A: アプリ固有コンポーネント │
│  守  (SPSC Buffer, CodeSign等)       (CTIアフィニティ, 外部連携) │
│  価                                                              │
│  値  D: 信号処理                     R: リグ制御               │
│  低  (Codec, Pipeline, SeqRules)     (Protocol, 機能IF等)       │
└────────────────────────────────────────────────────────────────┘
```

### 2.2 全コンポーネント一覧

| ID | 名称 | カテゴリ | 配置先 | フェーズ | 独立ビルド |
|---|---|---|---|---|---|
| M-01 | LWW ジャーナル同期エンジン | 汎用 | `lib/middleware/LWWSync/` | v1.0 | ✅ 必須 |
| M-02 | SQLite マイグレーション | 汎用 | `lib/middleware/SQLiteMigrate/` | α | ✅ 必須 |
| M-03 | Lua サンドボックスランタイム | 汎用 | `lib/middleware/LuaSandbox/` | v1.0 | ✅ 必須 |
| M-04 | 非同期コールバックキュー | 汎用 | `lib/middleware/AsyncDispatch/` | α | ✅ 必須 |
| M-05 | FTS5 全文検索ラッパー | 汎用 | `lib/middleware/FTS5Search/` | α | ✅ 必須 |
| H-01 | ADIF I/O ライブラリ | 無線 | `lib/hamlib/ADIFLib/` | α | ✅ 必須 |
| H-02 | コールサイン・DXCC リゾルバ | 無線 | `lib/hamlib/DXCCResolver/` | α | ✅ 必須 |
| H-03 | バンドプランエンジン | 無線 | `lib/hamlib/BandPlanEngine/` | β | ✅ 必須 |
| H-04 | Cabrillo I/O ライブラリ | 無線 | `lib/hamlib/CabrilloLib/` | v1.0 | ✅ 必須 |
| H-05 | グリッドスクエアライブラリ | 無線 | `lib/hamlib/GridSquareLib/` | α | ✅ 必須 |
| H-06 | QSL 状態機械 | 無線 | `lib/hamlib/QSLStateMachine/` | v1.0 | ✅ 必須 |
| H-07 | コンテストルールインタープリター | 無線 | `lib/hamlib/ContestRules/` | v1.0 | ✅ 必須 |
| H-08 | 周波数フォーマッター | 無線 | `lib/hamlib/FreqFormatter/` | α | ✅ 必須 |
| T-01 | SPSC オーディオリングバッファ | インフラ | `lib/infra/SPSCBuffer/` | β | ⚪ 推奨 |
| T-02 | ED25519 署名検証器 | インフラ | `lib/infra/CodeSigning/` | v1.0 | ⚪ 推奨 |
| T-03 | 子プロセス監視状態機械 | インフラ | `lib/infra/ProcessGuard/` | β | ⚪ 推奨 |
| T-04 | 設定スキーマ DSL | インフラ | `lib/infra/ConfigDSL/` | v1.0 | ⚪ 推奨 |
| D-01 | デジタルモードコーデック | 信号処理 | `dsp/` + `src/app/` | α/β | ⚪ 推奨 |
| D-02 | モード別シーケンス規則 | 信号処理 | `src/app/SeqRules/` | α | ⚪ 推奨 |
| D-03 | 音声信号処理パイプライン | 信号処理 | `dsp/` | β | ⚪ 推奨 |
| R-01 | リグプロトコル | リグ制御 | `src/infra/RigProtocol/` | α | ⚪ 推奨 |
| R-02 | リグ機能インターフェース | リグ制御 | `shared/AmityInterfaces.pas` | α | — |
| R-03 | 接続状態機械 | リグ制御 | `src/infra/RigConnectionSM/` | β | ⚪ 推奨 |
| R-04 | リグ×バンドプラン連携 | リグ制御 | `src/app/RigBandCoordinator/` | v1.0 | — |
| A-01 | CTI アフィニティエンジン | アプリ固有 | `src/app/` | v1.0 | — |
| A-02 | アワード進捗計算エンジン | アプリ固有 | `src/app/` | v1.0 | — |
| A-03 | PSKReporter 連携 | アプリ固有 | `src/app/` | v1.0 | — |
| A-04 | DX クラスター連携 | アプリ固有 | `src/app/` | v2.0 | — |

---

## 3. 各コンポーネント詳細仕様

### M-01: LWW ジャーナル同期エンジン

**目的**: `field_journal` の Last-Write-Wins 競合解決ロジックを Amity-QSO 非依存のライブラリとして分離する。

**外部インターフェース**:

| インターフェース | 役割 | 実装責任 |
|---|---|---|
| `ILWWRecord` | ジャーナルエントリの抽象（RecordID / UpdatedAt / DeviceID / NewValue） | `lib/` 側で定義 |
| `ILWWStore` | ローカルDBへの適用と現在タイムスタンプ取得 | `src/` 側の `TAmityLWWStore` が実装 |
| `ILWWJournalSource` | ジャーナルファイルの列挙・読み取り・アーカイブ | `src/` 側の `TFileJournalSource` が実装 |

**依存**:
- `ILogger` のみ（`lib/` 外への依存は ILogger 1つのみ許可）

**テストダブル**:
- `TMemoryLWWStore`: `TDictionary` でタイムスタンプを管理するテスト用ストア
- `TMemoryJournalSource`: メモリ上の配列でファイルを模倣

**契約（事後条件）**:
- `TLWWSyncEngine.ShouldApply(Incoming, LocalTimestamp)`: `Incoming.UpdatedAt > LocalTimestamp` の場合 `True`。等値の場合は `Incoming.DeviceID` の辞書順で決定（タイブレーク）。

---

### M-02: SQLite マイグレーション

**目的**: Amity-QSO 固有のスクリプトを外部化し、汎用マイグレーターとして分離する。

**外部インターフェース**:

| インターフェース | 役割 |
|---|---|
| `IMigrationSource` | スクリプト供給（`TInlineScriptSource` / `TFileScriptSource`） |
| `TSQLiteMigrator` | バージョン管理と差分適用 |

**Amity-QSO での使用方法**:

```pascal
// src/infra/DBWorker.pas での使用例
var
  Source   : IMigrationSource;
  Migrator : TSQLiteMigrator;
begin
  Source   := TInlineScriptSource.Create(MIGRATION_STEPS);  // 定数配列を渡す
  Migrator := TSQLiteMigrator.Create(FDB, Source, FLogger);
  Migrator.MigrateToLatest;
end;
```

**契約**: マイグレーション失敗時はトランザクションをロールバックし `EAmityDB` を送出する。成功したバージョンは `schema_migrations` テーブルに記録される。

---

### M-03: Lua サンドボックスランタイム

**目的**: ED25519 署名検証・標準ライブラリ無効化・バインディングセットの差し替えを汎用ランタイムとして分離する。

**設計上の重要決定事項**:

`ILuaBindingSet` の導入により、コンテスト用バインディング（`TLuaScoringBindings`）と API パーサー用バインディング（`TLuaAPIParserBindings`）を同一ランタイムに登録できる。バインディングの追加はアプリ側の変更のみで完結し、ランタイム本体を修正しない（OCP 準拠）。

**セキュリティ制約**:
- 実行可能なLuaライブラリ: `base`, `math`, `string`, `table` のみ
- 無効化するライブラリ: `io`, `os`, `package`, `dofile`, `loadfile`, `require`, `debug`
- スクリプト実行前の ED25519 署名検証は省略できない（ビルドフラグでの無効化も禁止）

---

### H-01: ADIF I/O ライブラリ

**目的**: ADIF 3.1.4+ の解析・出力を `TQSOData` に依存しない純粋なライブラリとして分離する。

**アダプターパターンの適用**:

```
[lib/hamlib/ADIFLib/]          [src/infra/]
  TADIFReader                    TADIFQSOAdapter
  TADIFWriter          ←uses→   .ToADIF(TQSOData): TADIFRecord
  TADIFRecord                    .FromADIF(TADIFRecord): TQSOData
```

`lib/` 側は `TADIFRecord`（`TDictionary<string, string>` ラッパー）のみを知る。`TQSOData` への変換は `src/infra/TADIFQSOAdapter` が担う。

**ラウンドトリップ保証**: `TADIFReader` → `TADIFWriter` の往復でフィールドが欠落しないこと。未知タグも `TADIFRecord.Fields` にそのまま保持される。

**再利用先の例**:
- ADIF ログ変換ツール（例: Hamlog エクスポート → LoTW 用フォーマット変換）
- コンテスト採点支援ツール
- クラスタービューアの履歴インポート機能

---

### H-02: コールサイン・DXCC リゾルバ

**目的**: BigCty.dat 形式への直接依存を `ICtyDataProvider` で抽象化し、データソース切替に対して閉じた設計にする（OCP）。

**最長プレフィックス一致アルゴリズム**:
コールサインのプレフィックスは長さ降順ソート済み配列に対してバイナリサーチを行い O(log n) で解決する。ポータブル表記（`KH0/JA1ABC`・`JA1ABC/QRP` 等）は事前に分解してからマッチングする。

**提供するデータプロバイダー**:

| クラス | データソース | 用途 |
|---|---|---|
| `TBigCtyFileProvider` | BigCty.dat ファイル | 本番運用 |
| `TMemoryCtyProvider` | メモリ上の定義 | ユニットテスト |
| （将来）`TClubLogAPIProvider` | ClubLog REST API | リアルタイム最新エンティティ情報 |

---

### H-05: グリッドスクエアライブラリ

**目的**: Maidenhead グリッドロケーターの変換・距離・ベアリング計算を外部依存ゼロの純粋計算ライブラリとして提供する。

**提供機能**:

| メソッド | 入力 | 出力 | 精度 |
|---|---|---|---|
| `FromLatLon` | 緯度・経度（度） | 4文字グリッド（例: `PM85`） | 約110km |
| `FromLatLon` (6文字) | 緯度・経度 | 6文字グリッド（例: `PM85ub`） | 約5km |
| `Distance` | グリッドA, グリッドB | km（実数） | Haversine 公式 |
| `Bearing` | From グリッド, To グリッド | 度（0〜360） | 大圏航路 |
| `IsValid` | 任意文字列 | Boolean | 4/6/8 文字を検証 |

**再利用先の例**: ビーム方向計算ツール、アワード管理ツール、地図連携プラグイン

---

### D-01: デジタルモードコーデック

**目的**: `TDecodeDispatcher` の `case` 分岐を `IDigitalModeCodec` の登録テーブルに置き換え、新モード追加をコード変更なしで実現する（OCP）。

**コーデック登録フロー（Composition Root）**:

```pascal
// AmityQSO.lpr — DSP Composition Root
Dispatcher.RegisterCodec(TFT8Codec.Create(smFT8));
Dispatcher.RegisterCodec(TFT8Codec.Create(smFT4));
Dispatcher.RegisterCodec(TJT65Codec.Create(smJT65));
Dispatcher.RegisterCodec(TCWCodec.Create(25, Logger));
Dispatcher.RegisterCodec(TRTTYCodec.Create(2125, 2295, 45));
// 新モード追加 = この1行を追加するだけ。既存コードへの変更なし。
```

**シーケンス規則との連携**:
各コーデックは `GetSequenceRules` で自身のモード固有規則（D-02）を提供する。`TSeqControllerThread` はコーデック切替時に `SequenceRules` を自動更新する。

---

### R-01: リグプロトコル

**目的**: CAT 通信の具体的なプロトコル（TCP テキスト・RS-232 バイト列・XML-RPC）を `IRigProtocol` で抽象化し、`TRigController` をプロトコル非依存にする（DIP）。

**プロトコル別実装一覧**:

| クラス | プロトコル | 接続方法 | 対応リグ例 |
|---|---|---|---|
| `TRigCtldProtocol` | hamlib/rigctld | TCP | rigctld 対応全機種 |
| `TCI_VProtocol` | Icom CI-V | RS-232/USB | IC-7300, IC-9700 等 |
| `TCATProtocol` | Yaesu CAT | RS-232/USB | FT-991A, FT-710 等 |
| `TFlrigProtocol` | flrig XML-RPC | TCP | flrig 対応機種 |
| `TSimulatorProtocol` | テスト用 | — | 自動テスト・デモ用 |

**切替方法（設定変更のみで対応）**:

```pascal
// Composition Root — プロトコルを設定値で選択
case Settings.Data.RigProtocol of
  rpRigCtld   : Protocol := TRigCtldProtocol.Create(Host, Port, Logger);
  rpCI_V      : Protocol := TCI_VProtocol.Create(Serial, Baud, Addr, Logger);
  rpCAT       : Protocol := TCATProtocol.Create(Serial, Baud, Model, Logger);
end;
RigController := TRigController.Create(Protocol, Logger);
```

---

### R-03: 接続状態機械

**目的**: リグ接続管理のロジック（再接続タイミング・試行回数・バックオフ戦略）を `TRigController` から分離する（SRP）。

**状態遷移**:

```
Disconnected
  └─[Connect()]──→ Connecting
                      ├─[成功]──→ Connected
                      │              └─[通信エラー]──→ Reconnecting
                      │                                   ├─[Policy.ShouldRetry=True]──→ Connecting
                      └─[失敗]──→ Reconnecting            └─[Policy.ShouldRetry=False]──→ Failed
                                   └─[MaxRetries超過]──→ Failed
```

**再接続ポリシーの交換可能性（OCP + LSP）**:

| クラス | 戦略 | 用途 |
|---|---|---|
| `TFixedIntervalPolicy` | 固定間隔（例: 2000ms × 3回） | 通常運用 |
| `TExponentialBackoffPolicy` | 指数バックオフ（例: 1s, 2s, 4s...） | 不安定回線対応 |
| `TSimulatorPolicy` | 即時成功/失敗を注入 | ユニットテスト |

---

## 4. コンポーネント間依存グラフ

```
凡例: → 依存する（uses）
      ⇢ インターフェース経由

【lib/ コンポーネント — 外向き依存なし（ILogger のみ許可）】

  M-01 LWWSync     ← ILWWStore（src/側実装）、ILWWJournalSource（src/側実装）
  M-02 SQLiteMigrate ← IMigrationSource（src/側実装）
  M-03 LuaSandbox  ← ILuaBindingSet（src/側実装）
  M-04 AsyncDispatch ← (依存なし: OS TThread.Queue のみ)
  M-05 FTS5Search  ← (依存なし: SQLite3 API のみ)
  H-01 ADIFLib     ← (依存なし: 純粋文字列処理)
  H-02 DXCCResolver ← ICtyDataProvider（src/側実装）
  H-03 BandPlanEngine ← (依存なし: JSON ファイルのみ)
  H-04 CabrilloLib  ← (依存なし: 純粋文字列処理)
  H-05 GridSquare   ← (依存なし: 純粋計算)
  H-06 QSLStateMachine ← (依存なし: 状態遷移テーブルのみ)
  H-07 ContestRules ← ILuaRuntime（src/側実装）
  H-08 FreqFormatter ← (依存なし: 純粋計算)
  T-01 SPSCBuffer   ← (依存なし: アトミック操作のみ)
  T-02 CodeSigning  ← (依存なし: libsodium または類似ライブラリ)
  T-03 ProcessGuard ← IProcessLauncher, IHealthChecker（src/側実装）
  T-04 ConfigDSL    ← ILogger のみ

【src/ コンポーネント — lib/ への依存可】

  D-01 Codec       ← H-01(ADIF: 将来), T-01(SPSC), ILogger
  D-02 SeqRules    ← AmityTypes (TSeqEvent), ILogger
  D-03 AudioPipeline ← T-01(SPSC), ILogger
  R-01 Protocol    ← T-03(ProcessGuard: rigctld起動管理), ILogger
  R-02 機能IF      ← (インターフェース定義のみ: 依存なし)
  R-03 ConnSM      ← R-01(IRigProtocol), ILogger
  R-04 BandCoord   ← R-02(IRigVFOControl等), H-03(IBandPlanEngine), ILogger
  A-01 CTIAffinity ← AmityTypes, ILogger
  A-02 AwardCalc   ← AmityTypes, H-05(IGridSquareLib), ILogger
  A-03 PSKReporter ← AmityTypes, ILogger
  A-04 DXCluster   ← AmityTypes, ILogger
```

---

## 5. 各コンポーネントのテスト戦略

各コンポーネントには以下のテストダブルを付属させ、Amity-QSO 本体なしでテストを完結できるようにする。

| コンポーネント | テストダブル | 提供するもの |
|---|---|---|
| M-01 LWWSync | `TMemoryLWWStore`, `TMemoryJournalSource` | タイムスタンプ管理・ファイル供給の模倣 |
| M-02 SQLiteMigrate | `:memory:` SQLite 使用 | ファイルシステム不要 |
| M-03 LuaSandbox | `TMemorySignatureVerifier`（署名検証スキップ） | テスト環境での署名省略 |
| H-01 ADIFLib | `TStringStream` 使用 | ファイル不要 |
| H-02 DXCCResolver | `TMemoryCtyProvider` | Cty.dat ファイル不要 |
| D-01 Codec | `TNullCodec`（固定デコード結果を返す） | DSPエンジン不要 |
| R-01 Protocol | `TSimulatorProtocol` | 実リグ不要・コマンド応答マップ |
| R-03 ConnSM | `TSimulatorPolicy`（即時成功/失敗注入） | ネットワーク不要 |
| T-03 ProcessGuard | `TSimulatorLauncher`（プロセス起動不要） | OS プロセス不要 |

**テストダブルの LSP 適合性**: 各テストダブルは対応するインターフェースの事前・事後条件を完全に満たすこと。`TSimulatorProtocol` の `SendCommand` は設定されたマッピングに従い決定論的に動作し、タイムアウトは発生しないこと（テスト速度確保）。

---

## 6. 段階的実施ロードマップ

### フェーズ1: α版並行（初期設計と同時着手）

コスト最小・依存関係が少ない・α版の DoD に直結するコンポーネントを優先する。

| ID | コンポーネント | 理由 |
|---|---|---|
| H-01 | ADIF I/O ライブラリ | ADIFインポート・エクスポートは α版 DoD に必須。早期切り出しで全チームが恩恵 |
| H-02 | コールサイン・DXCC リゾルバ | Cty.dat 依存を切り離すことで将来の形式変更リスクを排除 |
| H-05 | グリッドスクエアライブラリ | 外部依存ゼロ・純粋計算・1日で実装・テスト完了できる |
| H-08 | 周波数フォーマッター | 純粋関数・UI と DSP 双方が使用 |
| M-02 | SQLite マイグレーション | DBWorker 実装前に確定すべき基盤 |
| M-04 | 非同期コールバックキュー | 全ワーカースレッドが使用。早期確定で並行実装を促進 |
| M-05 | FTS5 全文検索ラッパー | コマンドパレット・ログ検索で必要 |
| D-02 | モード別シーケンス規則 | SeqCtrl 設計前に確定。後からの改修コストが高い |
| R-01 | リグプロトコル（基本構造のみ） | `TRigCtldProtocol` + `TSimulatorProtocol` の2実装で α版は十分 |
| R-02 | リグ機能 I/F 定義 | インターフェース定義のみ。コスト最小で将来の拡張基盤を確保 |

### フェーズ2: β版並行

| ID | コンポーネント | 理由 |
|---|---|---|
| D-01 | デジタルモードコーデック | β版でFT8送信が必要。IDecodeEngine/IEncodeEngine の確定が必須 |
| D-03 | 音声信号処理パイプライン | FFT・フィルタの段階テストを可能にする |
| H-03 | バンドプランエンジン | バンドプランガードを H-03 経由に移行 |
| T-01 | SPSC バッファ汎用化 | ジェネリック化はコスト低・再利用価値高 |
| T-03 | 子プロセス監視状態機械 | DSP 再起動ロジックの整理 |
| R-03 | 接続状態機械 | 再接続ポリシーのテスト可能化 |

### フェーズ3: v1.0 後（高価値・高コスト）

| ID | コンポーネント | 理由 |
|---|---|---|
| M-01 | LWW 同期エンジン | TSyncWorkerThread から完全分離。v1.0 での field_journal 動作確認後 |
| M-03 | Lua サンドボックス | コンテスト Lua とAPIパーサー Lua を統合した後に汎用化 |
| H-04 | Cabrillo I/O | v1.0 でコンテスト機能完成後に切り出し |
| H-06 | QSL 状態機械 | LoTW 連携安定後に分離 |
| H-07 | コンテストルールインタープリター | H-04・M-03 完成後に統合 |
| T-02 | ED25519 署名検証器 | 鍵管理・配布フローの確定後 |
| T-04 | 設定スキーマ DSL | 設定項目が安定した後 |
| R-04 | リグ×バンドプラン連携 | スマートバンドホッピング（v2.0）準備 |
| A-01 | CTI アフィニティ | CTI 機能の安定後 |
| A-02 | アワード計算 | グリッドビンゴ実装後 |
| A-03 | PSKReporter | v1.0 リリース後 |

---

## 7. パッケージング方針

### 7.1 ディレクトリ構成

```
amity-qso/
├── lib/                            ← 独立ライブラリ群（src/ 非依存）
│   ├── middleware/
│   │   ├── LWWSync/
│   │   │   ├── LWWSyncEngine.pas
│   │   │   ├── LWWSyncEngine.lpi   ← 独立ビルドプロジェクト
│   │   │   └── tests/
│   │   │       └── TestLWWSync.pas
│   │   ├── SQLiteMigrate/
│   │   ├── LuaSandbox/
│   │   ├── AsyncDispatch/
│   │   └── FTS5Search/
│   ├── hamlib/
│   │   ├── ADIFLib/
│   │   │   ├── ADIFLib.pas
│   │   │   ├── ADIFLib.lpi         ← 独立ビルドプロジェクト
│   │   │   └── tests/
│   │   ├── DXCCResolver/
│   │   ├── BandPlanEngine/
│   │   ├── CabrilloLib/
│   │   ├── GridSquareLib/
│   │   ├── QSLStateMachine/
│   │   ├── ContestRules/
│   │   └── FreqFormatter/
│   └── infra/
│       ├── SPSCBuffer/
│       ├── CodeSigning/
│       ├── ProcessGuard/
│       └── ConfigDSL/
├── src/                            ← Amity-QSO 本体
│   ├── shared/
│   │   ├── AmityTypes.pas
│   │   ├── AmityInterfaces.pas     ← R-02 の機能I/F を含む
│   │   └── AmityConstants.pas
│   ├── platform/
│   ├── infra/
│   │   ├── adapters/               ← lib/ ↔ src/ 変換アダプター
│   │   │   ├── ADIFQSOAdapter.pas  ← TADIFRecord ↔ TQSOData
│   │   │   ├── LWWAmityAdapter.pas ← TJournalEntry → ILWWRecord
│   │   │   └── CtyAmityAdapter.pas ← ICtyDataProvider 実装
│   │   └── ...
│   ├── app/
│   └── ui/
├── dsp/                            ← DSP プロセス（D-01, D-03 含む）
└── tests/
    ├── unit/
    └── integration/
```

### 7.2 CI パイプラインでの独立ビルド検証

```yaml
# .github/workflows/lib-build.yml
jobs:
  lib-independent-build:
    strategy:
      matrix:
        lib: [LWWSync, SQLiteMigrate, ADIFLib, DXCCResolver,
              GridSquareLib, FreqFormatter, FTS5Search]
    steps:
      - name: Build lib/${{ matrix.lib }} independently
        run: lazbuild lib/${{ matrix.lib }}/${{ matrix.lib }}.lpi

      - name: Run lib unit tests
        run: |
          cd lib/${{ matrix.lib }}/tests
          lazbuild AllTests.lpi && ./AllTests --format=plain
```

`lib/` の各コンポーネントがメインプロジェクトなしで単独ビルド・テスト実行できることを全 PR で自動検証する。

---

## 付録A: インターフェース契約一覧

各インターフェースの事前条件・事後条件を明文化する。LSP 準拠のテストダブル実装時に参照すること。

| インターフェース | メソッド | 事前条件 | 事後条件 |
|---|---|---|---|
| `ILWWRecord` | `UpdatedAt` | — | UNIX タイムスタンプ（秒）。0 は無効値。 |
| `TLWWSyncEngine` | `ShouldApply` | — | `Incoming.UpdatedAt > Local` の場合 True。等値は DeviceID 辞書順。 |
| `IDecodeEngine` | `Decode` | `BufSamples > 0`, `AudioBuf != nil` | `Result.Candidates` は SNR 降順にソートされている。 |
| `IEncodeEngine` | `Encode` | `ValidateMessage` が True を返している | `SampleCount > 0`, `OutBuf` は有効なポインタ。 |
| `IRigProtocol` | `SendCommand` | `IsConnected = True` | 応答文字列が空でない場合 True。通信エラーは False（例外なし）。 |
| `IReconnectPolicy` | `ShouldRetry` | `Attempt >= 0` | `Attempt > MaxAttempts` の場合 False。 |
| `IQSORepository` | `WriteQSO` | `Data.IsValid = True` | Callback は非同期で呼ばれる。呼び出しスレッドはブロックしない。 |
| `IGridSquareLib` | `Distance` | 4 または 6 文字の有効グリッド | 非負の距離（km）。無効グリッドは -1 を返す。 |
| `IMigrationSource` | `GetScripts` | — | バージョン番号は単調増加。重複バージョンは含まない。 |

---

## 付録B: コンポーネント追加手順

新しいコンポーネントを追加する場合は以下の手順に従う。

1. **分類判定**: M・H・T・A・D・R のいずれかに分類する。分類不明の場合はアーキテクトに確認する。
2. **配置先決定**: 分類に対応するディレクトリに `.pas` + `.lpi` を作成する。
3. **インターフェース定義**: `shared/AmityInterfaces.pas`（`src/`依存の場合）または専用ユニット（`lib/`の場合）にインターフェースを定義する。
4. **テストダブル作成**: インターフェースを実装するテストダブルを `tests/Stubs/` または当該 `lib/*/tests/` に作成する。
5. **契約明文化**: 付録Aに事前条件・事後条件を追記する。
6. **CI 追加**: `lib/` コンポーネントの場合は `lib-build.yml` の matrix に追加する。
7. **本文書更新**: セクション2のカタログ一覧・セクション4の依存グラフを更新する。
