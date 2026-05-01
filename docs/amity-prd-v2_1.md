# Amity-QSO 製品要求定義書 (PRD) v2.1

> **文書管理**
> | 項目 | 内容 |
> |---|---|
> | 文書バージョン | 2.1 |
> | ステータス | 改訂済 |
> | 作成日 | 2025年 |
> | 対象読者 | ソフトウェア開発技術者・QAエンジニア・プロジェクトマネージャー |

---

## 改訂履歴

| バージョン | 日付 | 変更概要 | 担当 |
|---|---|---|---|
| 1.0 | 初版 | 初稿作成 | — |
| 2.0 | 本版 | 要件具体化、スキーマ・IPC仕様追加、DoD整備 | — |

---

## 用語集（Glossary）

| 用語 | 定義 |
|---|---|
| QSO | アマチュア無線における交信。本文書では1交信 = 1レコード。 |
| CTI | Contact/交信記憶情報（Contact Tracking & Intelligence）。相手局の履歴・コンテキスト情報。 |
| CAT | Computer Aided Transceiver。PCからリグを制御する仕組み。 |
| DSP Plugin | 別プロセスで動作するデジタルモード信号処理エンジン。 |
| rigctld | Hamlib付属のリグ制御デーモン。TCP経由でCAT制御を抽象化する。 |
| ADIF | Amateur Data Interchange Format。QSOログの業界標準交換フォーマット。 |
| LoTW | ARRL Logbook of the World。電子QSL確認システム。 |
| FTS5 | SQLite 全文検索拡張。コールサイン・メモの高速テキスト検索に使用。 |
| Last-Write-Wins (LWW) | 同一フィールドの競合時、最新タイムスタンプを正とするマージ戦略。 |
| DT | デコード時刻ずれ（Δtime）。デコード品質の指標。 |
| IPC | Inter-Process Communication。本体↔DSPプロセス間通信。 |
| DoD | Definition of Done。フェーズ完了の判定基準。 |
| NFR | Non-Functional Requirement。非機能要件。 |
| コンポーネント | 独立してビルド・テスト・再利用できる機能単位。インターフェースのみで他モジュールと接続する。 |
| ライブラリ化候補 | Amity-QSO 外からも利用可能な独立ライブラリとして切り出す予定のコンポーネント（M/H カテゴリ）。 |

---

## 1. プロジェクト概要

### 1.1 目的

Amity-QSO は、アマチュア無線家が「交信する・記録する・思い出す・次の交信へつなげる」体験を一体化する**マルチプラットフォーム（Windows/macOS）**対応の運用支援アプリケーションである。Lazarus 4.6（Free Pascal）によるネイティブコンパイルにより、Intel N150クラスの低スペック環境でも安定動作することを最優先設計条件とする。

### 1.2 解決する課題

| # | 課題 | 影響範囲 | 解決アプローチ |
|---|---|---|---|
| P-1 | 複数アプリ（WSJT-X / JTAlert / ロガー）連携による仮想COMポート・UDP設定の複雑化 | 全ユーザー | All-in-One統合（仮想ルーティング根絶） |
| P-2 | クラウドストレージ上のSQLite直接同期によるDBロック競合・破損 | クラウド利用者 | field_journalによるジャーナルベース非同期マージ |
| P-3 | ログ・情報確認・アワード進捗が分断され、交信中にコンテキストを引き出せない | アクティブ運用者 | CTI統合（300ms以内の履歴即時表示） |
| P-4 | 低スペック環境での過剰CPU消費・発熱 | モバイル・低スペックPC利用者 | 動的リソーススケーリング＋アイドルエコモード |

### 1.3 スコープ外（Out of Scope）

以下は本プロジェクトでは実装しない。

- Webブラウザベースのインターフェース
- スマートフォン（iOS/Android）ネイティブアプリ
- LoTW以外のQSL管理システム（eQSL等）との直接連携（v1.0まで）
- DSPエンジン本体のフルスクラッチ開発（既存実装をプラグイン化する）

---

## 2. ターゲットユーザーとユースケース

### 2.1 主要ユーザーペルソナ

| ペルソナ | 説明 | 主要ニーズ |
|---|---|---|
| ホームステーション運用者 | 固定局で日常的にFT8/FT4を運用 | 安定ロギング・LoTW自動連携 |
| モバイル・移動運用者 | ノートPC（N150クラス）で移動運用 | 低消費電力・複数PC間ログ同期 |
| コンテスター | 週末コンテストに参加 | 高速Dupe判定・Cabrillo出力 |
| DXer（希少局追いかけ） | DXCC・バンドニューを積極的に狙う | CTIサジェスト・アワード進捗確認 |

### 2.2 主要ユースケース一覧

| UC-ID | ユースケース名 | 主体 | 優先度 |
|---|---|---|---|
| UC-01 | FT8信号を受信しデコード結果を表示する | システム | 最高（α） |
| UC-02 | デコード済み局を選択してQSOを開始・完了しログに保存する | 運用者 | 最高（α） |
| UC-03 | コールサインを選択した瞬間にCTI情報を表示する | システム | 高（β） |
| UC-04 | 複数PCのログをクラウド経由で同期する | 運用者 | 高（v1.0） |
| UC-05 | コンテストルールを適用してスコアをリアルタイム集計する | システム | 中（v1.0） |
| UC-06 | LoTWにADIFをバックグラウンドアップロードする | システム | 中（v1.0） |
| UC-07 | CPU負荷に応じてデコード深度を自動切替する | システム | 高（β） |

---

## 3. 開発フェーズと完了基準（DoD）

### 3.1 フェーズ定義

| フェーズ | 目標 | 対象スコープ |
|---|---|---|
| **α版** | 受信・記録・検索の最小動作検証 | FT8受信、CAT抽象化(rigctld)、SQLiteローカル、ADIF入出力、Callsign Resolver |
| **β版** | 実用化（送信・自動シーケンス・フェイルセーフ） | FT8送信、Auto-Seq、厳密時刻管理、動的リソーススケーリング |
| **v1.0** | 完全運用・マルチPC同期 | 主要モード送受信、Contest Engine、QSL状態管理、field_journal同期、CTIアシスト |
| **v2.0** | 独自体験（Experimental） | P2Pチャット(STUN/TURN)、デジタルQSL、スマートバンドホッピング |

### 3.2 各フェーズのDefinition of Done

#### α版 DoD

- [ ] FT8信号（テスト音源）をデコードし、コールサイン・SNR・DT・周波数を一覧表示できる。
- [ ] rigctldへ接続し、VFO周波数をUIに表示できる。VFO変更操作が反映される。
- [ ] QSOを手動で1件記録し、SQLiteに保存できる。
- [ ] 保存したQSOをADIF 3.1.4形式でエクスポートし、既存ツール（WSJT-X等）で読み込める。
- [ ] ADIFファイルをインポートし、DBに取り込める（50万件インポートが10分以内）。
- [ ] N150環境にてUIが100ms以内に応答する（デコード処理中を含む）。
- [ ] 単体テスト・統合テストのカバレッジが主要機能で70%以上。

#### β版 DoD（α版DoDを包含）

- [ ] FT8送信シーケンス（CQ発射→応答→73送信）が自動実行される。
- [ ] バンドプランJSONに `block_tx: true` が設定された帯域への送信が物理的にブロックされる。
- [ ] デコードDT中央値が ±2.0秒を超えた場合に送信がハードロックされ、UIにアラートが表示される。
- [ ] CPU使用率85%超過時にFASTモードへ自動切替し、DeepSearch処理が停止する。
- [ ] 上記の動的切替が15秒サイクル中に完了する（切替遅延 ≦ 1秒）。
- [ ] アプリ最小化時にウォーターフォール描画が停止し、CPU使用率が最小化前比20%以上低下する。

#### v1.0 DoD（β版DoDを包含）

- [ ] 2台PCでオフライン編集後に同期し、1000件のfield_journalが60秒以内にマージ完了する。
- [ ] 同一フィールドへの競合編集がLWW戦略で正しく解決され、データ欠損がない。
- [ ] CTI表示がコールサイン選択から300ms以内に完了する（50万件DB上で計測）。
- [ ] LoTWへのADIFアップロードがバックグラウンドで実行され、UIをブロックしない。
- [ ] Cabrillo 3.0形式ファイルを出力し、主要コンテストサーバーで受理される。

---

## 4. システムアーキテクチャ

### 4.1 プロセス・スレッド構成

```
┌─────────────────────────────────────────────────┐
│  Amity-QSO メインプロセス                        │
│                                                   │
│  [Main Thread]  UIレンダリング専用。DB/NW操作禁止 │
│  [SeqCtrl Thread]  送受信シーケンス制御           │
│  [RigControl Thread]  rigctld TCP通信             │
│  [DB Worker Thread]  全SQLite操作（WALモード）    │
│  [HwMonitor Thread]  CPU/メモリ/時刻監視          │
│  [Sync Worker Thread]  field_journal マージ        │
│  [ApiGateway Thread]  外部API（QRZ等）非同期取得  │
└───────────────────┬─────────────────────────────┘
                    │ IPC（共有メモリ + UDPシグナリング）
┌───────────────────▼─────────────────────────────┐
│  DSP Plugin プロセス（別プロセス / GPLv3分離）   │
│  FT8/FT4/JT65/JT9/Q65/MSK144/FST4 エンジン      │
└─────────────────────────────────────────────────┘
```

**UIスレッドルール（必須制約）:**
UIスレッドからDBアクセス・ネットワーク・ファイルI/Oを直接呼び出すことを禁止する。全ての非同期操作はキューを介してワーカースレッドへ委譲し、コールバックでUIを更新する。

### 4.2 コンポーネント責務定義

| コンポーネント | 責務 | 依存 | 実装言語/技術 |
|---|---|---|---|
| SeqCtrl | QSOシーケンス状態機械（IDLE/TX/RX/WAIT等）の管理 | DSP Plugin, RigControl | Free Pascal (TThread) |
| Callsign Resolver | Cty.datを用いたプレフィックス解決・DXCCエンティティ判定 | BigCty.dat, DB | Free Pascal |
| RigControlPort | rigctld TCP（127.0.0.1:4532）クライアント。VFO取得・設定、PTT制御 | rigctld | Free Pascal |
| HwMonitor | CPU使用率（OSネイティブAPI）・空きメモリ・NTPオフセット取得 | OS API, GPS | Free Pascal |
| DB Worker | SQLite3（WALモード・FTS5有効）の全CRUD操作。マイグレーション管理 | SQLite3 | Free Pascal |
| Dynamic API Parser | QRZ.com XML等のパースをLuaスクリプトで実行。スクリプトはED25519署名検証必須 | Lua 5.4 ランタイム | Free Pascal + Lua |
| Contest Engine | Lua定義のルール評価・マルチプライヤー計算・Dupe判定 | DB Worker, Lua | Free Pascal + Lua |

---

## 5. データモデル（DBスキーマ）

### 5.1 SQLite設定

```sql
PRAGMA journal_mode = WAL;      -- 並行読み取り性能向上
PRAGMA synchronous  = NORMAL;   -- WALモードで安全
PRAGMA foreign_keys = ON;
PRAGMA user_version = 1;        -- マイグレーション管理に使用
```

### 5.2 テーブル定義

#### `qso_log`（QSOメインテーブル）

```sql
CREATE TABLE qso_log (
    qso_id        TEXT    PRIMARY KEY,   -- UUID v4
    callsign      TEXT    NOT NULL,
    band          TEXT    NOT NULL,      -- "20m", "15m" 等 ADIF形式
    mode          TEXT    NOT NULL,      -- "FT8", "FT4", "CW" 等
    freq_hz       INTEGER NOT NULL,      -- 周波数 Hz整数
    rst_sent      TEXT,
    rst_rcvd      TEXT,
    tx_pwr_w      REAL,
    my_gridsquare TEXT,
    dx_gridsquare TEXT,
    qso_date      TEXT    NOT NULL,      -- ISO8601 "YYYYMMDD"
    time_on       TEXT    NOT NULL,      -- "HHMM" UTC
    time_off      TEXT,
    dxcc_entity   TEXT,
    cont          TEXT,                  -- 大陸コード
    cqz           INTEGER,
    ituz          INTEGER,
    qsl_sent      TEXT    DEFAULT 'N',   -- N/Y/Q/I（ADIF準拠）
    qsl_rcvd      TEXT    DEFAULT 'N',
    lotw_qslsent  TEXT    DEFAULT 'N',
    lotw_qslrcvd  TEXT    DEFAULT 'N',
    contest_id    TEXT,
    contest_exch  TEXT,
    notes         TEXT,
    adif_extra    TEXT,                  -- 未定義タグをJSON文字列で保持
    created_at    INTEGER NOT NULL,      -- UNIXタイムスタンプ（秒）
    updated_at    INTEGER NOT NULL,
    deleted_at    INTEGER                -- NULLでない場合は論理削除
);

CREATE INDEX idx_qso_callsign ON qso_log(callsign);
CREATE INDEX idx_qso_date     ON qso_log(qso_date);
CREATE INDEX idx_qso_band     ON qso_log(band, mode);
CREATE INDEX idx_qso_dxcc     ON qso_log(dxcc_entity);
```

#### `field_journal`（同期用ジャーナルテーブル）

```sql
CREATE TABLE field_journal (
    journal_id    TEXT    PRIMARY KEY,   -- UUID v4
    qso_id        TEXT    NOT NULL REFERENCES qso_log(qso_id),
    field_name    TEXT    NOT NULL,      -- "notes", "qsl_sent" 等フィールド名
    old_value     TEXT,
    new_value     TEXT,
    updated_at    INTEGER NOT NULL,      -- UNIXタイムスタンプ（秒）。LWWの比較キー
    device_id     TEXT    NOT NULL,      -- 編集元デバイスUUID
    synced        INTEGER DEFAULT 0      -- 0:未同期 / 1:同期済み
);

CREATE INDEX idx_journal_qso_id    ON field_journal(qso_id);
CREATE INDEX idx_journal_updated   ON field_journal(updated_at);
CREATE INDEX idx_journal_synced    ON field_journal(synced);
```

#### `stations`（CTI：相手局情報キャッシュ）

```sql
CREATE TABLE stations (
    callsign      TEXT    PRIMARY KEY,
    name          TEXT,
    qth           TEXT,
    gridsquare    TEXT,
    avatar_path   TEXT,   -- クラウド同期ルートからの相対パス
    affinity_level INTEGER DEFAULT 0,  -- 0:未交信, 1:初QSO, 2:知人, 3:常連 等
    notes         TEXT,
    last_qso_date TEXT,
    qso_count     INTEGER DEFAULT 0,
    api_source    TEXT,   -- "qrz", "hamqth", "local" 等
    api_fetched_at INTEGER,
    updated_at    INTEGER NOT NULL
);
```

#### `qso_fts`（全文検索仮想テーブル）

```sql
CREATE VIRTUAL TABLE qso_fts USING fts5(
    callsign,
    notes,
    dx_gridsquare,
    content='qso_log',
    content_rowid='rowid'
);
-- qso_logの INSERT/UPDATE/DELETE トリガーでfts5を更新する
```

#### `band_plan`（バンドプラン・送信ガード）

```sql
CREATE TABLE band_plan (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    region        TEXT    NOT NULL,   -- "JA", "US", "EU", "ALL" 等
    band          TEXT    NOT NULL,
    freq_low_hz   INTEGER NOT NULL,
    freq_high_hz  INTEGER NOT NULL,
    mode_hint     TEXT,               -- 推奨モード（参考）
    block_tx      INTEGER DEFAULT 0   -- 1: この範囲への送信を物理ブロック
);
```

#### `schema_migrations`（マイグレーション管理）

```sql
CREATE TABLE schema_migrations (
    version       INTEGER PRIMARY KEY,
    applied_at    INTEGER NOT NULL,
    description   TEXT
);
```

### 5.3 マイグレーション方針

1. アプリ起動時、`PRAGMA user_version` を読み取る。
2. コード内に埋め込まれたマイグレーションスクリプト（バージョン順）を差分適用する。
3. 適用完了後、`PRAGMA user_version` を最新版番号に更新する。
4. マイグレーション失敗時は直前のバックアップへロールバックし、ユーザーに通知する。

---

## 6. IPC通信仕様（本体 ↔ DSP Plugin）

### 6.1 通信方式

| 項目 | 仕様 |
|---|---|
| 共有メモリ | 音声バッファの転送（オーディオデータ本体）。サイズ: 192,000バイト（48kHz × 2秒 × float32） |
| UDPシグナリング | 制御コマンドのみ。127.0.0.1。本体ポート: 5100、DSPポート: 5101 |
| メッセージフォーマット | JSONテキスト（UTF-8、末尾改行区切り）、最大4096バイト |
| タイムアウト | 本体→DSP: 3秒応答なしでエラー通知。DSP→本体: 500ms |

### 6.2 メッセージ定義

#### 本体 → DSP

**DECODE_REQUEST**
```json
{
  "type": "DECODE_REQUEST",
  "audio_buf_id": "<共有メモリセグメント名: string>",
  "timestamp_utc": "<ISO8601: string>",
  "freq_range": {
    "low_hz": 200,
    "high_hz": 3000
  },
  "mode": "FT8"
}
```

**ENCODE_REQUEST**（β版以降）
```json
{
  "type": "ENCODE_REQUEST",
  "message_text": "CQ JA1ABC PM95",
  "mode": "FT8",
  "freq_hz": 1500,
  "output_buf_id": "<共有メモリセグメント名: string>"
}
```

**CONFIG_UPDATE**
```json
{
  "type": "CONFIG_UPDATE",
  "depth": "FAST"
}
```
- `depth` の許容値: `"FAST"` | `"DEEP"`

**PING**（ヘルスチェック、3秒周期）
```json
{
  "type": "PING",
  "seq": 42
}
```

#### DSP → 本体

**DECODE_RESULT**
```json
{
  "type": "DECODE_RESULT",
  "request_timestamp_utc": "<元のDECODE_REQUESTのtimestamp_utc>",
  "decode_time_ms": 3200,
  "candidates": [
    {
      "callsign": "JA1ABC",
      "snr": -10,
      "dt": 0.3,
      "freq_hz": 1234,
      "msg": "CQ JA1ABC PM95",
      "confidence": 0.97
    }
  ]
}
```

**ENCODE_RESULT**（β版以降）
```json
{
  "type": "ENCODE_RESULT",
  "output_buf_id": "<共有メモリセグメント名>",
  "samples_count": 46080,
  "duration_ms": 12640
}
```

**RESOURCE_PROFILE**（5秒周期で自動送信）
```json
{
  "type": "RESOURCE_PROFILE",
  "cpu_percent": 62.5,
  "decode_time_ms": 4800,
  "gpu_offload": true
}
```

**GET_SEQUENCE_RULES**（DSP→本体。プラグインロード直後に1回送信）
```json
{
  "type": "GET_SEQUENCE_RULES",
  "mode": "MSK144",
  "rules": {
    "cycle_sec": 15,
    "tx_start_sec": [0, 15, 30, 45],
    "short_sequence_enabled": true,
    "short_seq_threshold_snr": -10
  }
}
```

**PONG**
```json
{
  "type": "PONG",
  "seq": 42
}
```

**ERROR**
```json
{
  "type": "ERROR",
  "code": "DECODE_TIMEOUT",
  "message": "デコード処理がタイムアウトしました",
  "recoverable": true
}
```

### 6.3 動的リソーススケーリング ロジック

HwMonitorスレッドはDSPからの`RESOURCE_PROFILE`を受信するたびに以下の判定を行う。判定結果に変化があった場合のみ`CONFIG_UPDATE`を発行する。

```
-- Deepモードへ移行する条件（スケールアップ）
IF cpu_percent < 50 AND decode_time_ms < 10000 THEN
    current_depth = "DEEP"

-- Fastモードへ移行する条件（フェイルセーフ）
ELSE IF cpu_percent > 85 OR decode_time_ms > 13000 THEN
    current_depth = "FAST"

-- 上記以外は現状維持（ヒステリシス帯域: 50〜85%）
END
```

---

## 7. 機能要件（機能別）

### 7.1 音声・デジタルモード

| 要件ID | 要件 | 優先度 | フェーズ |
|---|---|---|---|
| F-AUD-01 | OSデバイスをGUID(Win) / UID(Mac)で識別し設定を保存する。起動時に自動バインドする | 必須 | α |
| F-AUD-02 | サンプリングレートは48000Hzに固定する | 必須 | α |
| F-AUD-03 | 音声デバイスのホットプラグ（抜き差し）を検知し、再接続時に自動バインドを試みる | 必須 | β |
| F-DSP-01 | FT8/FT4/JT65/JT9/Q65/MSK144/FST4を別プロセスDSPプラグインで対応する | 必須 | α(受信) / β(送信) |
| F-DSP-02 | DSPプラグインとのIPC接続が3秒以内に確立しない場合、エラーダイアログを表示する | 必須 | α |
| F-DSP-03 | DSPプラグインがクラッシュした場合、メインプロセスは継続稼働し再起動を試みる | 必須 | β |
| F-DSP-04 | GPU(OpenCL) / NPU(ONNX Runtime)が利用可能な場合、DSPのFFT処理をオフロードする | 推奨 | β |

### 7.2 リグ制御（CAT）

| 要件ID | 要件 | 優先度 | フェーズ |
|---|---|---|---|
| F-CAT-01 | α版ではrigctld TCP（デフォルト127.0.0.1:4532）クライアントとして実装する | 必須 | α |
| F-CAT-02 | VFO-A周波数の取得（GET_FREQ）・設定（SET_FREQ）をサポートする | 必須 | α |
| F-CAT-03 | PTTのON/OFF制御をサポートする | 必須 | β |
| F-CAT-04 | CATデバイスのホットプラグを検知し自動再接続する | 必須 | β |
| F-CAT-05 | CATポーリング間隔を設定可能にする（デフォルト: 500ms） | 推奨 | β |

### 7.3 時刻同期と送信安全機構

| 要件ID | 要件 | 優先度 | フェーズ |
|---|---|---|---|
| F-TIME-01 | 時刻ソースの優先順位を守る: GNSS PPS > GNSS NMEA ($GPRMC) > 高精度NTP > OSクロック | 必須 | β |
| F-TIME-02 | 現在使用中の時刻ソースと推定精度（ms）をUIに常時表示する | 必須 | β |
| F-TIME-03 | 直近30デコードサイクルのDT中央値を計算し、±2.0秒超過時を「Invalid」と判定する | 必須 | β |
| F-TIME-04 | Invalid判定中は送信コマンドの発行をハードロックし、UIに赤色アラートを表示する | 必須 | β |
| F-TIME-05 | Invalid判定からの復帰条件: DT中央値が±1.0秒以内に戻り、かつ手動承認またはNTP再同期完了 | 必須 | β |

### 7.4 バンドプランガード（送信安全）

| 要件ID | 要件 | 優先度 | フェーズ |
|---|---|---|---|
| F-BAND-01 | band_plan テーブルから `block_tx = 1` の帯域をメモリにキャッシュする | 必須 | β |
| F-BAND-02 | PTTがONになる前に現在のVFO周波数をチェックし、ブロック帯域であれば送信コマンドを発行しない | 必須 | β |
| F-BAND-03 | バンドプランJSONファイルのインポートと上書き更新をサポートする | 必須 | β |
| F-BAND-04 | ブロック帯域への送信試行時、理由を明記したポップアップを表示する | 必須 | β |

### 7.5 QSOロギングとADIF

| 要件ID | 要件 | 優先度 | フェーズ |
|---|---|---|---|
| F-LOG-01 | QSOを手動入力またはシーケンス完了時に自動記録する | 必須 | α |
| F-LOG-02 | ADIF 3.1.4+ のタグを完全にサポートし、未定義タグもキー＆バリューで保持する | 必須 | α |
| F-LOG-03 | ADIFファイルのエクスポート（全件・日付範囲指定・バンド指定）をサポートする | 必須 | α |
| F-LOG-04 | ADIFファイルのインポート時、重複QSOを uuid と (callsign, qso_date, time_on, band, mode) のいずれかで検出しスキップ/上書きを選択できる | 必須 | α |
| F-LOG-05 | 50万件インポートを10分以内に完了する（NFR F-PERF-03 参照） | 必須 | α |

### 7.6 CTIリレーションと次アクション支援

| 要件ID | 要件 | 優先度 | フェーズ |
|---|---|---|---|
| F-CTI-01 | デコードリスト上でコールサインを選択すると300ms以内にCTIパネルを表示する | 必須 | v1.0 |
| F-CTI-02 | CTIパネルに表示する情報: 過去QSO回数・最終交信日・バンド別交信実績・LoTW CFM状況・メモ | 必須 | v1.0 |
| F-CTI-03 | 「New Band」「LoTW未CFM」「New DXCC」に該当する場合、サジェストバッジを表示する | 必須 | v1.0 |
| F-CTI-04 | QSO回数に応じてアフィニティレベル（0〜3）を算出し、リスト上のアイコンに反映する | 推奨 | v1.0 |
| F-CTI-05 | コールサイン選択時にQRZ.com XML APIを非同期で取得し、名前・QTHを更新する（Luaスクリプト） | 推奨 | v1.0 |

### 7.7 クラウド同期（field_journal）

| 要件ID | 要件 | 優先度 | フェーズ |
|---|---|---|---|
| F-SYNC-01 | QSOフィールド更新時、field_journalレコードをJSONファイルとして同期フォルダへ書き出す | 必須 | v1.0 |
| F-SYNC-02 | JSONファイル名形式: `{device_id}_{updated_at}_{journal_id}.json` | 必須 | v1.0 |
| F-SYNC-03 | アプリ起動時および同期フォルダ変更検知時、未処理のJSONを読み込みLWWでマージする | 必須 | v1.0 |
| F-SYNC-04 | 同一 (qso_id, field_name) で競合した場合、updated_atが大きい方を採用する（LWW） | 必須 | v1.0 |
| F-SYNC-05 | 1000件のJSON処理を60秒以内に完了する（バックグラウンド処理） | 必須 | v1.0 |
| F-SYNC-06 | マージ完了後、処理済みJSONを `archive/` サブフォルダへ移動する | 推奨 | v1.0 |

### 7.8 QSL管理（LoTW連携）

| 要件ID | 要件 | 優先度 | フェーズ |
|---|---|---|---|
| F-QSL-01 | QSL状態の遷移: `WKD → SENT → Rcvd → CFM / Rejected` を管理する | 必須 | v1.0 |
| F-QSL-02 | `tqsl.exe` をコマンドラインで呼び出しADIFを署名・送信する（バックグラウンド） | 必須 | v1.0 |
| F-QSL-03 | アプリ起動時および24時間毎に、LoTW APIへ差分照会を行い過去QSOを遡及的にCFM更新する | 必須 | v1.0 |
| F-QSL-04 | tqslのパスと証明書設定をUI設定画面から指定できる | 必須 | v1.0 |

### 7.9 コンテストエンジン

| 要件ID | 要件 | 優先度 | フェーズ |
|---|---|---|---|
| F-CNT-01 | コンテスト定義をJSONメタデータ + Luaスクリプトで記述できる | 必須 | v1.0 |
| F-CNT-02 | コンテストJSON必須フィールド: name, start_utc, end_utc, bands[], required_fields[], exchange_format | 必須 | v1.0 |
| F-CNT-03 | Luaスクリプト内でマルチプライヤー判定・スコア計算を実装できる | 必須 | v1.0 |
| F-CNT-04 | 重複（Dupe）判定をリアルタイムで行い、デコードリストに即時反映する | 必須 | v1.0 |
| F-CNT-05 | Cabrillo 3.0形式でエクスポートできる | 必須 | v1.0 |
| F-CNT-06 | コンテスト定義ファイルのインポートとUI上での有効/無効切替をサポートする | 必須 | v1.0 |

---

## 8. 非機能要件（NFR）

### 8.1 性能要件

| 要件ID | 要件 | 計測条件 | フェーズ |
|---|---|---|---|
| F-PERF-01 | UIレスポンスタイム ≦ 100ms（操作からUI更新まで） | N150, デコード処理中, P95 | α |
| F-PERF-02 | CTI表示完了 ≦ 300ms（コールサイン選択からパネル表示まで） | 50万件DB, P95 | v1.0 |
| F-PERF-03 | ADIFインポート ≦ 10分（50万件） | N150 | α |
| F-PERF-04 | 1000件field_journalマージ ≦ 60秒 | バックグラウンド処理 | v1.0 |
| F-PERF-05 | アプリ起動（コールドスタート）≦ 5秒 | N150 + 50万件DB | α |
| F-PERF-06 | アイドル時のCPU使用率 ≦ 3%（ウォーターフォール非表示・無信号帯域） | N150 | β |
| F-PERF-07 | メモリ使用量 ≦ 150MB（アイドル時）/ ≦ 300MB（デコード処理中） | N150 | β |

### 8.2 信頼性・可用性要件

| 要件ID | 要件 | フェーズ |
|---|---|---|
| F-REL-01 | DSPプロセスクラッシュ時、メインプロセスは継続稼働し自動再起動を3回試みる | β |
| F-REL-02 | DB書き込み失敗時、エラーをログに記録しユーザーに通知する（データ破棄禁止） | α |
| F-REL-03 | アプリ異常終了後の再起動時、未コミットのQSOデータを復元できる | β |
| F-REL-04 | 送信ハードロック（F-TIME-04）の解除には必ずユーザーの明示的操作を必要とする | β |

### 8.3 セキュリティ要件

| 要件ID | 要件 | フェーズ |
|---|---|---|
| F-SEC-01 | Dynamic API Parser（Lua）のスクリプトはED25519署名検証を通過したもののみ実行する | v1.0 |
| F-SEC-02 | APIキー（QRZ等）はOSキーチェーン（Win: DPAPI / Mac: Keychain）に保存する | v1.0 |
| F-SEC-03 | DSP IPCのUDPポートはloopbackアドレス（127.0.0.1）のみ受け付ける | α |
| F-SEC-04 | P2P通信（v2.0）ではTLS 1.3以上を使用する | v2.0 |

### 8.4 保守性・拡張性要件

| 要件ID | 要件 | フェーズ |
|---|---|---|
| F-MNT-01 | DBスキーマ変更はマイグレーションスクリプト経由で行い、ダウングレードパスも提供する | α |
| F-MNT-02 | アプリバージョン・DSPプラグインバージョンの組み合わせ互換表をREADMEに明記する | α |
| F-MNT-03 | 自動更新はバックグラウンドでダウンロードし、次回起動時にファイルリネームで適用する | v1.0 |
| F-MNT-04 | アプリログはローテーション付きで書き出す（最大10MB × 3ファイル） | α |


### 8.5 再利用性・コンポーネント独立性要件

本節はコンポーネント設計書 v1.0 と対になる要件定義である。コンポーネント化の設計詳細はコンポーネント設計書を参照すること。

| 要件ID | 要件 | 対象コンポーネント | フェーズ |
|---|---|---|---|
| F-REUSE-01 | デジタルモードコーデック（IDecodeEngine）は Amity-QSO 本体に依存せず、独立してビルド・ユニットテストできること | D-01 コーデック群 | β |
| F-REUSE-02 | リグプロトコル実装（IRigProtocol）はアプリ本体を変更せずに差し替えられること。少なくともrigctld・シミュレーター実装を提供すること | R-01 プロトコル群 | β |
| F-REUSE-03 | ADIF I/O ライブラリは TQSOData 型に依存せず、TADIFRecord を中心とした独立ユニットとして設計すること | H-01 ADIF Lib | α |
| F-REUSE-04 | コールサイン・DXCCリゾルバは Cty.dat 形式への直接依存を持たず、ICtyDataProvider 経由でデータを受け取ること | H-02 Callsign Resolver | α |
| F-REUSE-05 | LWW ジャーナル同期エンジンは ILWWRecord / ILWWStore インターフェース経由でのみ動作し、QSOデータ型を直接参照しないこと | M-01 LWW Sync | v1.0 |
| F-REUSE-06 | Lua サンドボックスランタイムはバインディングセット（ILuaBindingSet）を差し替えることでコンテスト・APIパーサー双方に使用できること | M-03 Lua Runtime | v1.0 |
| F-REUSE-07 | グリッドスクエアライブラリ（IGridSquareLib）は外部依存ゼロの純粋計算ユニットとして実装すること | H-05 GridSquare | α |
| F-REUSE-08 | 各コンポーネントはコンポーネント設計書 v1.0 に定義された「ライブラリ化候補」分類に従い、lib/ ディレクトリ下に独立ユニットとして配置すること | 全ライブラリ候補 | v1.0 |

**コンポーネント独立性の検証基準:**
- コンポーネントが「独立している」とは、そのユニットのみをコンパイルして単体テストを実行できることを指す。
- Amity-QSO 固有の型（TQSOData, TDecodeResult 等）への直接依存は、アダプターパターンで吸収すること。
- ライブラリ化候補（M・H カテゴリ）は `lib/` サブディレクトリに配置し、アプリ本体の `src/` と物理的に分離すること。

---

## 9. UI/UX要件

### 9.1 画面一覧

| 画面ID | 画面名 | 主な構成要素 | フェーズ |
|---|---|---|---|
| UI-01 | メイン運用画面 | ウォーターフォール、デコードリスト、送受信ステータス、VFO表示 | α |
| UI-02 | CTIパネル（サイドバー） | 相手局情報、過去QSO履歴、サジェストバッジ | v1.0 |
| UI-03 | ログ検索画面 | FTS5全文検索バー、フィルター、QSOリスト | α |
| UI-04 | コンテスト画面 | スコアサマリー、Dupe判定リスト、エクスチェンジ入力欄 | v1.0 |
| UI-05 | 設定画面（タブ式） | 音声・CAT・時刻・バンドプラン・LoTW・クラウド同期・一般 | α |
| UI-06 | コマンドパレット | FTS5コールサイン・メモ検索ドロップダウン（Ctrl+K） | v1.0 |
| UI-07 | アワード進捗画面 | グリッドビンゴ、DXCC進捗、バンド別統計 | v1.0 |

### 9.2 最小解像度対応

全画面は **1024 × 600 px** で全機能が操作可能なこと。スクロール・折りたたみパネルを使用して構わないが、デコードリストとVFO表示は常時表示を維持すること。

### 9.3 アクセシビリティ

- フォントサイズを12px/14px/16pxから選択できること。
- 高コントラストカラーモードを用意すること（ウォーターフォール含む）。

---

## 10. 外部インターフェース

### 10.1 外部サービス・ツール依存一覧

| サービス/ツール | 用途 | 依存フェーズ | 代替案 |
|---|---|---|---|
| hamlib/rigctld | CAT制御 | α | 将来的に直接シリアル実装へ移行可 |
| QRZ.com XML API | コールサイン情報取得 | v1.0 | HamQTH API（同じLuaアダプター経由） |
| LoTW (ARRL) API | QSL照会 | v1.0 | なし（必須） |
| tqsl.exe | LoTW ADIFアップロード署名 | v1.0 | なし（必須） |
| PSKReporter API | 受信レポート送信・スポット受信 | v1.0 | なし |
| NTPサーバー | 時刻同期（フォールバック） | β | GNSS優先 |

### 10.2 ファイル・フォルダ構成（ユーザーデータ）

```
{AppDataRoot}/                    # Win: %APPDATA%\AmityQSO / Mac: ~/Library/Application Support/AmityQSO
  amity.db                        # SQLiteメインDB
  settings.json                   # アプリ設定
  band_plan/                      # バンドプランJSON（地域別）
    JA.json
    US.json
  lua_scripts/                    # Lua APIパーサー・コンテスト定義
  logs/                           # アプリログ（ローテーション）

{CloudSyncRoot}/                  # ユーザー指定（Dropbox等）
  field_journal/                  # ジャーナルJSONファイル
    {device_id}_{updated_at}_{journal_id}.json
    archive/                      # 処理済みジャーナル
  media/                          # アバター画像等（相対パスで参照）
```

---

## 11. リスクレジスタ

| リスクID | リスク内容 | 発生確率 | 影響度 | 対応策 |
|---|---|---|---|---|
| R-01 | rigctldとのCAT互換問題（リグ機種依存） | 高 | 中 | 対応確認済みリグリストを公開。問題報告窓口を設置 |
| R-02 | DSPプラグイン（GPLv3）のライセンス汚染 | 低 | 高 | プロセス分離を厳守。本体コードとの共有ヘッダを最小化 |
| R-03 | クラウドストレージAPIの変更によるfield_journal同期障害 | 中 | 中 | ファイルシステム監視（OS watchdog）に依存し、クラウドAPIには依存しない |
| R-04 | N150環境でのデコード処理タイムアウト頻発 | 中 | 高 | FASTモードをデフォルト設定。DEEPモードは手動または高スペック環境のみ |
| R-05 | LoTW APIの仕様変更・廃止 | 低 | 高 | LoTW連携をプラグイン化し、APIラッパーの差し替えを容易にする |
| R-06 | Free Pascal / LazarusのmacOS最新版非対応 | 中 | 高 | Lazaros LTSリリースへの追従計画を策定。macOS対応を先行検証 |
| R-07 | 送信安全機構のバグによる違法送信 | 低 | 最高 | バンドプランガードと時刻同期ロックを独立二重実装。コードレビュー必須 |

---

## 12. テスト戦略

### 12.1 テスト種別と担当

| テスト種別 | 対象 | ツール/手法 | フェーズ |
|---|---|---|---|
| 単体テスト | Callsign Resolver, Band Plan Guard, LWWマージロジック | Free Pascal標準テストフレームワーク | α |
| 統合テスト | IPC通信、DB CRUD、CAT制御（RigSimulator使用） | RigSimulator + AudioLoopback | α |
| 性能テスト | 50万件DB上での各操作速度 | 自動計測スクリプト | α |
| 送信安全テスト | バンドプランブロック・時刻ロック | 自動回帰スクリプト | β |
| DB破損耐性テスト | 2台同時オフライン編集後のマージ | 手動+自動（テストシナリオ書面化） | v1.0 |
| デバイスホットプラグテスト | 運用中のオーディオIF・CATケーブル抜き差し | 手動 | β |

### 12.2 テストシナリオ（重要ケース詳細）

#### TC-SYNC-01: 競合マージ正常動作
1. PC-AとPC-Bで同一QSOの `notes` フィールドを異なる値でオフライン編集する。
2. 両機をネットワーク復帰させ、同期フォルダを同期させる。
3. **期待結果**: 後から編集したPC側の値が採用され、データ欠損がないこと。

#### TC-BAND-01: バンドプランブロック動作確認
1. `block_tx: true` の帯域（例: 7.074MHz）にVFOを設定する。
2. 送信コマンドを発行する（ボタン押下またはAuto-Seq起動）。
3. **期待結果**: PTTがONにならず、ブロック理由を明記したポップアップが表示される。

#### TC-TIME-01: 送信ハードロック動作確認
1. NTPを意図的に2.5秒ずらした状態でアプリを起動する。
2. デコードサイクルを30回以上実行する。
3. **期待結果**: DT中央値の異常を検出し、UIに赤色アラートが表示される。送信ボタンが無効化される。

---

## 付録A: コンポーネント間依存関係

```
[α版 必須]
SeqCtrl ─────────────► DSP Plugin (IPC)
SeqCtrl ─────────────► RigControlPort
SeqCtrl ─────────────► DB Worker
Callsign Resolver ───► DB Worker
Callsign Resolver ───► BigCty.dat
UI ──────────────────► SeqCtrl (非同期コールバック)
UI ──────────────────► DB Worker (非同期コールバック)

[β版 追加]
HwMonitor ──────────► SeqCtrl (動的スケーリング通知)
HwMonitor ──────────► GPS/NTP

[v1.0 追加]
CTI Panel ──────────► DB Worker
CTI Panel ──────────► ApiGateway
ApiGateway ─────────► Lua Runtime (Dynamic API Parser)
Sync Worker ────────► DB Worker
Contest Engine ─────► DB Worker
Contest Engine ─────► Lua Runtime
```

## 付録B: 設定ファイルスキーマ（band_plan JSON）

```json
{
  "region": "JA",
  "version": "2025-01",
  "bands": [
    {
      "band": "40m",
      "freq_low_hz": 7000000,
      "freq_high_hz": 7200000,
      "segments": [
        {
          "freq_low_hz":  7000000,
          "freq_high_hz": 7010000,
          "mode_hint": "CW",
          "block_tx": false
        },
        {
          "freq_low_hz":  7074000,
          "freq_high_hz": 7076000,
          "mode_hint": "FT8",
          "block_tx": false
        },
        {
          "freq_low_hz":  7100000,
          "freq_high_hz": 7100500,
          "mode_hint": "BEACON",
          "block_tx": true
        }
      ]
    }
  ]
}
```
