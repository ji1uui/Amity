# Amity-QSO 基本設計書 v1.1

> **文書管理**
> | 項目 | 内容 |
> |---|---|
> | 文書バージョン | 1.1 |
> | ステータス | 改訂済 |
> | 上位文書 | Amity-QSO PRD v2.0 |
> | 対象読者 | 実装担当エンジニア・コードレビュアー・QAエンジニア |

---

## 改訂履歴

| バージョン | 日付 | 変更概要 |
|---|---|---|
| 1.0 | 初版 | 基本設計初稿 |
| 1.1 | 本版 | 第15章 コンポーネント分割方針を新設。第1章・第2章に関連記述を追記 |

---

## 1. 設計方針

### 1.1 基本原則

本アプリケーションの設計は、以下の5原則に従う。すべての設計判断はこの優先順位で評価し、相反する場合は上位原則を優先する。

**原則1 ── 送信安全の絶対性（Safety First）**
送信制御に関わる判断ロジックは他のコンポーネントから独立させ、UIスレッド・データ同期処理と競合する余地を構造的に排除する。バンドプランガードおよび時刻ロック機構は独立した二重実装とし、一方が故障しても送信がブロックされる設計を維持する。

**原則2 ── データ損失の完全回避（Zero Data Loss）**
未保存のQSOデータ、field_journalの未コミットレコードは、プロセス異常終了時でも復元できることを設計の前提とする。DBへの書き込みは常にトランザクション内で行い、部分書き込みの状態でDBが閉じられないよう保証する。

**原則3 ── UIスレッドの完全解放（UI Responsiveness）**
UIスレッドからのブロッキング操作（DB・ネットワーク・ファイルI/O・IPC）を設計レベルで禁止する。非同期操作の完了は必ずキューを介したコールバックでUIに通知する。この制約を破る変更はコードレビューで差し戻す。

**原則4 ── N150ベースラインの設計（Constrained-First Design）**
パフォーマンス最適化の出発点を高スペック環境ではなく、Intel N150クラス（RAM 2GB, 低速eMMC）に置く。高スペック環境での追加機能（DEEPモード・GPU/NPUオフロード）は「余裕があれば有効化する」機能拡張として位置付け、基本動作パスには不要とする。

**原則5 ── ライセンス汚染の構造的排除（License Isolation）**
GPLv3ライセンスが適用されるDSPエンジンは別プロセスとして完全分離し、本体コードとの共有ヘッダ・型定義を最小化する。IPC境界を越える型はPRDで定義したJSONスキーマのみとし、コンパイル時の依存を持たせない。

### 1.2 技術スタック選定根拠

| 技術 | 採用理由 | 注意事項 |
|---|---|---|
| Lazarus 4.6 / Free Pascal | マルチプラットフォームネイティブバイナリ生成。ランタイム不要。N150での動作実績 | macOSの最新OSへの対応遅延リスクあり（R-06）。LTSリリースへの追従計画を別途策定 |
| SQLite 3.x（WAL + FTS5） | 組み込み型。マルチスレッド読み取り効率。FTS5による全文検索 | Write操作はシングルスレッド（DB Workerスレッドに集約）。WALファイルの肥大化監視が必要 |
| Lua 5.4 | コンテスト定義・APIパーサーのスクリプト化。本体バイナリを変えずに機能追加可能 | スクリプト実行はED25519署名検証後のみ。サンドボックス化（OS・ファイルへのアクセス制限）を実施 |
| hamlib / rigctld | 広範なリグ対応の実績。TCP抽象化によりOS依存を回避 | 直接シリアル制御への将来移行を見越し、RigControlPortはインターフェースで抽象化する |
| IPC: 共有メモリ + UDP | 音声バッファの高速転送（共有メモリ）と低レイテンシー制御シグナリング（UDP）の分離 | UDP通信はloopbackに限定。メッセージサイズは4096バイト上限を厳守 |

### 1.3 設計上の制約（変更禁止事項）

以下の制約はアーキテクチャレベルで固定し、実装中に覆してはならない。

- UIスレッドからのSQLite呼び出しの禁止（原則3）
- DSPプロセスとのヘッダファイル共有の禁止（原則5）
- PTT制御関数のUIスレッドからの直接呼び出しの禁止（原則1）
- `block_tx = true` 判定処理のLua委譲の禁止（Pascal実装必須、原則1）

---

## 2. アーキテクチャ設計

### 2.1 プロセス構成

Amity-QSOは**2プロセス構成**を基本とする。本体プロセス（メインアプリ）とDSPプラグインプロセスは独立して起動・停止し、IPC接続が確立できない状態でも本体は起動・ロギング機能を維持する。

```
┌─────────────────────────────────────────────────────────────┐
│  AmityQSO.exe / AmityQSO.app  （本体プロセス）              │
│                                                               │
│  スレッド構成:                                               │
│  ┌─────────────┐ ┌──────────────┐ ┌──────────────────────┐ │
│  │ Main Thread │ │ SeqCtrl Thrd │ │  RigControl Thread   │ │
│  │ (UI専用)    │ │              │ │  (rigctld TCP client)│ │
│  └─────────────┘ └──────────────┘ └──────────────────────┘ │
│  ┌─────────────┐ ┌──────────────┐ ┌──────────────────────┐ │
│  │ DB Worker   │ │ HwMonitor    │ │  Sync Worker Thread  │ │
│  │ Thread      │ │ Thread       │ │  (field_journal)     │ │
│  └─────────────┘ └──────────────┘ └──────────────────────┘ │
│  ┌─────────────┐                                            │
│  │ ApiGateway  │                                            │
│  │ Thread      │                                            │
│  └─────────────┘                                            │
│                                                               │
│  プロセス間通信（IPC）                                       │
│  ├─ 共有メモリ: 音声バッファ転送                            │
│  └─ UDP 127.0.0.1:5100(本体) / 5101(DSP): 制御シグナル     │
└────────────────────────────┬────────────────────────────────┘
                             │ IPC
┌────────────────────────────▼────────────────────────────────┐
│  AmityDSP.exe / AmityDSP.app  （DSPプラグインプロセス）     │
│  GPLv3 ライセンス分離。FT8/FT4/JT65等デコード・エンコード   │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 スレッド責務とメッセージフロー

各スレッドは単一の責務を持ち、スレッド間のデータ交換は**スレッドセーフなキュー（TThreadedQueue）**のみを通じて行う。スレッド間での直接メモリアクセスは禁止する。

```
  [デコード結果表示の例]

  DSP Process
    ↓ DECODE_RESULT (UDP)
  SeqCtrl Thread  ──→  DBWorker Thread（QSO候補記録）
    ↓ TThreadedQueue.Enqueue(DecodeResultMsg)
  Main Thread  ──→  UI更新（デコードリスト再描画）
```

```
  [QSO記録の例]

  Main Thread（ユーザー操作）
    ↓ TThreadedQueue.Enqueue(LogQsoCmd)
  SeqCtrl Thread（シーケンス検証）
    ↓ TThreadedQueue.Enqueue(WriteQsoCmd)
  DB Worker Thread（SQLite書き込み）
    ↓ TThreadedQueue.Enqueue(WriteCompleteMsg)
  Main Thread（UI: 記録完了表示）
```

### 2.3 レイヤー構造

本体プロセス内部は以下の4層で構成する。上位層は下位層の実装詳細に依存しない（依存方向は常に上→下）。

```
  ┌──────────────────────────────────────────┐
  │  Layer 4: Presentation (UI)              │  Lazarus Forms / LCL
  │  ウォーターフォール描画、一覧表示、入力   │
  ├──────────────────────────────────────────┤
  │  Layer 3: Application Logic              │  Free Pascal Units
  │  SeqCtrl, CTI Engine, Contest Engine     │
  │  BandPlanGuard, TimeValidator            │
  ├──────────────────────────────────────────┤
  │  Layer 2: Infrastructure                 │  Free Pascal Units
  │  DB Worker, RigControlPort, ApiGateway   │
  │  IPC Client/Server, SyncWorker           │
  ├──────────────────────────────────────────┤
  │  Layer 1: Platform Abstraction           │  Free Pascal Units
  │  OS API ラッパー（ファイル監視・時刻     │
  │  ・CPU使用率・キーチェーン）             │
  └──────────────────────────────────────────┘
```

---

## 3. コンポーネント設計

### 3.1 SeqCtrl（シーケンスコントローラ）

SeqCtrlは送受信シーケンスの状態機械を管理するコンポーネントである。状態遷移の判断にはBandPlanGuardとTimeValidatorの双方による承認が必要であり、一方でもREJECTを返した場合は送信状態へ遷移しない。

#### 状態定義

```
  IDLE
   │  CQ発射命令 / 相手局選択
   ▼
  WAIT_TX_PERMIT ──→ (BandPlanGuard.Check = REJECT) → TX_BLOCKED
   │                  (TimeValidator.Check = REJECT) → TX_BLOCKED
   │  両方ALLOW
   ▼
  TX_RUNNING ──→ (DSP ENCODE完了) → RX_WAIT
   ▼
  RX_WAIT ──→ (タイムアウト or 応答受信) → IDLE / TX_RUNNING
   │
  (手動停止)
   ▼
  IDLE

  TX_BLOCKED
   │  (ユーザー手動解除 + 原因解消確認)
   ▼
  IDLE
```

#### 主要インターフェース（Pascal宣言）

```pascal
type
  TSeqState = (ssIdle, ssWaitTxPermit, ssTxRunning, ssRxWait, ssTxBlocked);
  TSeqEvent = (seStartCQ, seStartQSO, seResponseReceived, se73Sent,
               seStopRequested, sePermitGranted, sePermitRejected);

  ISeqController = interface
    procedure PostEvent(Event: TSeqEvent; const Payload: TSeqPayload);
    function  CurrentState: TSeqState;
    procedure RegisterStateChangeCallback(Callback: TSeqStateChangeProc);
  end;
```

### 3.2 BandPlanGuard（バンドプランガード）

BandPlanGuardはLayer 3（Application Logic）に配置し、Pascal実装を必須とする。Luaへの委譲を禁止する。

起動時にSQLiteの `band_plan` テーブルを全件メモリへロードし、`block_tx = 1` のセグメントのみを整列済み配列（周波数でソート）として保持する。周波数チェックはバイナリサーチで行い、DB問い合わせは発生させない。

```pascal
type
  TBlockedSegment = record
    FreqLowHz  : Int64;
    FreqHighHz : Int64;
    Region     : string;
    Band       : string;
  end;

  TBandPlanGuard = class
  private
    FBlockedSegments : array of TBlockedSegment;  // 周波数昇順でソート済み
  public
    procedure Reload(DBWorker: IDBWorker);         // 起動時・JSON更新時に呼ぶ
    function  IsTxBlocked(FreqHz: Int64; out Reason: string): Boolean;
  end;
```

`IsTxBlocked` はSeqCtrlの `WAIT_TX_PERMIT` 状態への遷移時に必ず呼び出す。戻り値 `True` の場合はSeqCtrlへ `sePermitRejected` を送出し、`Reason` 文字列をUIに表示する。

### 3.3 TimeValidator（時刻同期バリデータ）

HwMonitorスレッド内で動作し、デコードサイクルごとにDT値を更新する。判定結果はSeqCtrlおよびUIスレッドへ通知する。

#### DT中央値計算

直近30サイクルのDT値をリングバッファで保持する。バッファが10件未満の段階ではINVALID判定を行わない（起動直後の誤検知を防ぐ）。

```pascal
type
  TTimeValidatorStatus = (tvsUnknown, tvsValid, tvsInvalid);

  TTimeValidator = class
  private
    FDTBuffer    : TCircularBuffer<Single>;  // 容量30
    FStatus      : TTimeValidatorStatus;
    FMedianDT    : Single;
    FThreshold   : Single;                   // 設定値、デフォルト 2.0
  public
    procedure AddDTSample(DT: Single);
    function  CurrentStatus: TTimeValidatorStatus;
    property  MedianDT: Single read FMedianDT;
  end;
```

`AddDTSample` 呼び出し後、中央値を再計算し、30サンプル以上かつ `|MedianDT| > FThreshold` であれば `FStatus = tvsInvalid` とし、変化があればSeqCtrlへ通知する。

#### 時刻ソース優先順位の実装

```
Priority 1: GNSS PPS（ハードウェア割り込み、精度 <1µs）
            → 利用可能判定: GPSデバイスからPPS信号を受信できている場合
Priority 2: GNSS NMEA $GPRMC（シリアルパース、精度 ~10ms）
            → 利用可能判定: $GPRMCの Validity フィールドが 'A'（有効）
Priority 3: 高精度NTP（精度 ~10〜50ms）
            → NTPサーバー応答 RTT < 200ms を条件とする
Priority 4: OSクロック（精度不定）
            → 上記すべて利用不可の場合のフォールバック
```

現在使用中のソースと推定精度は `TTimeSourceStatus` レコードとしてHwMonitorがUIへ通知する。

### 3.4 DB Worker（データベースワーカー）

DB Workerは本アプリケーション内でSQLiteへのアクセスを独占するスレッドである。他のスレッドはすべてコマンドキューを通じてDB Workerへ依頼し、結果をコールバックで受け取る。

#### コマンドキューの型定義

```pascal
type
  TDBCommandKind = (dbkReadQSO, dbkWriteQSO, dbkUpdateField,
                    dbkSearchFTS5, dbkReadBandPlan,
                    dbkWriteJournal, dbkApplyJournal,
                    dbkRunMigration);

  TDBCommand = record
    Kind      : TDBCommandKind;
    Params    : TDBParams;           // バリアントレコード（命令別パラメータ）
    Callback  : TDBResultCallback;   // 完了時にメインスレッドキューへ積む手続き
    RequestID : TGUID;
  end;
```

#### トランザクション方針

- 単一レコードのINSERT/UPDATEは自動コミット（暗黙トランザクション）。
- field_journalへのINSERTとqso_logへのUPDATEは同一トランザクション内でアトミックに実行する。
- ADIFインポートは1000件単位でバッチトランザクションを発行する（コミット頻度と書き込み性能のバランス）。

#### FTS5インデックス同期

qso_log への INSERT/UPDATE/DELETE 後に対応するFTS5トリガーを発火させる。トリガーはDBマイグレーション時に作成する。

```sql
-- INSERT トリガー例
CREATE TRIGGER qso_log_ai AFTER INSERT ON qso_log BEGIN
  INSERT INTO qso_fts(rowid, callsign, notes, dx_gridsquare)
  VALUES (new.rowid, new.callsign, new.notes, new.dx_gridsquare);
END;
```

### 3.5 RigControlPort（リグ制御ポート）

α版はrigctld TCPクライアントとして実装する。将来の直接シリアル実装への移行を考慮し、リグ操作はインターフェースで抽象化する。

```pascal
type
  IRigControl = interface
    function  GetVFOFreqHz: Int64;
    procedure SetVFOFreqHz(FreqHz: Int64);
    procedure SetPTT(OnOff: Boolean);
    function  IsConnected: Boolean;
    procedure RegisterStatusCallback(Callback: TRigStatusProc);
  end;

  TRigCtldClient = class(TThread, IRigControl)
    // rigctld TCPクライアント実装
    // ポーリング間隔: デフォルト500ms（設定可能）
    // 接続断検知: ソケットエラー発生時に再接続を最大3回試行
  end;
```

**PTTフロー（送信安全保証）:**
`SetPTT(True)` の呼び出しはSeqCtrlスレッドからのみ許可する。SeqCtrlはこの呼び出し前に必ず `BandPlanGuard.IsTxBlocked` および `TimeValidator.CurrentStatus` を確認する。UIスレッドからの直接呼び出しは禁止する（コードレビューで検出する）。

### 3.6 HwMonitor（ハードウェア監視）

5秒周期でCPU使用率・空きメモリ・時刻ソースを収集し、`RESOURCE_PROFILE` をDSPプロセスへ転送する。動的スケーリング判定はHwMonitorスレッド内で行い、判定結果が変化した場合のみSeqCtrl経由でDSPへ `CONFIG_UPDATE` を発行する。

#### リソース収集のOS別実装

| 指標 | Windows | macOS |
|---|---|---|
| CPU使用率 | `GetSystemTimes` API | `host_processor_info` (Mach) |
| 空きメモリ | `GlobalMemoryStatusEx` API | `vm_stat` コマンド or `host_statistics` |
| ロードアベレージ | 非対応（N/A） | `getloadavg` |

#### アイドルエコモード

以下の条件が両立した場合、HwMonitorはUIへ「エコモード移行」を通知する。UIは通知を受け取ったらウォーターフォールのFPSを0に設定し描画を停止する。

- アプリウィンドウが最小化状態、またはウォーターフォールパネルが非表示
- DSPからの `RESOURCE_PROFILE` にてエネルギー閾値以下の帯域が全体の80%以上

### 3.7 field_journal 同期ワーカー

同期フォルダをOSのファイルシステム監視API（Windows: `ReadDirectoryChangesW` / macOS: FSEvents）でウォッチし、新規JSONファイルの出現を検知する。アプリ起動時は `synced = 0` のレコードを全件処理する。

#### マージアルゴリズム

```
入力: JSONファイル群（1件のJSONが1つのfield_journalレコードに対応）

1. JSONを読み込み、(qso_id, field_name) ごとにグループ化する。
2. 各グループ内で updated_at の最大値を持つレコードを「適用値」として選択する（LWW）。
3. ローカルDBの field_journal テーブルに同一 (qso_id, field_name) の
   レコードが存在し、かつ updated_at が大きい場合は上書きしない（LWW尊重）。
4. 適用値をqso_logの対応フィールドへUPDATEする。
   ─ field_journalとqso_log更新は同一トランザクションで実行。
5. 処理済みJSONを archive/ へ移動する。
6. エラー発生時はJSONを移動せず、エラーログに記録して次のファイルへ進む。
```

---

## 4. IPC 設計（詳細）

PRD v2.0で定義したIPCメッセージ仕様を前提とし、本章では実装レベルの詳細を補足する。

### 4.1 共有メモリ管理

| 項目 | 仕様 |
|---|---|
| セグメント名 | `amity_audio_{GUID}` （起動時にランダムGUIDで生成） |
| サイズ | 192,000バイト（48kHz × 1秒 × float32 × 2ch モノラル使用は1ch分） |
| アクセス制御 | 書き込みはProducerのみ（本体: 音声入力時、DSP: エンコード結果書き込み時） |
| ライフサイクル | 本体プロセス起動時に作成、終了時に削除 |

DSPプロセスはUDP経由で受け取った `audio_buf_id` を使って共有メモリへアタッチし、データを読み取る。セグメント名の事前共有により、任意のプロセスからのアタッチを防ぐ。

### 4.2 UDP通信の堅牢性

制御メッセージはUDPのため信頼性を保証しない。以下の補完機構を実装する。

- **PING/PONG による死活監視**: 本体からDSPへ3秒周期でPINGを送信する。3回連続で PONG が戻らない場合、DSPプロセスの再起動を試みる。
- **DecodeRequestの重複送信対策**: `DECODE_REQUEST` はタイムスタンプをIDとして使用する。DSP側で直近10件の処理済みタイムスタンプをキャッシュし、重複を無視する。
- **エラーの冪等性**: `ERROR` メッセージの `recoverable: true` はDSPが自己回復可能な状態を示す。本体はrecoverable=trueのエラーをUIに警告として表示するが、リスタートは行わない。

### 4.3 DSPプロセスのライフサイクル管理

```
本体起動
  └─→ DSP実行ファイルの存在確認
       ├─ 存在しない → エラーダイアログ「DSPプラグインが見つかりません」で起動続行
       └─ 存在する  → DSPプロセスをサブプロセスとして起動
                        ├─ 3秒以内にPONG受信 → 正常接続
                        └─ タイムアウト → 再試行（最大3回）→ 失敗時は受信専用モードで起動

本体終了
  └─→ DSPへQUIT_REQUESTを送信 → 3秒待機 → プロセスkill
```

---

## 5. データ設計

PRD v2.0のスキーマ定義を基準とし、本章では実装上の考慮事項を補足する。

### 5.1 UUID生成方針

`qso_id` および `journal_id` はUUID v4（ランダム）を使用する。Free Pascal標準ライブラリの `CreateGUID` を使用し、`{}` 等の装飾を除いたハイフン区切りの小文字文字列（例: `f47ac10b-58cc-4372-a567-0e02b2c3d479`）をテキスト型で格納する。

### 5.2 device_id の生成と永続化

`device_id` はアプリ初回起動時にUUID v4で生成し、以下のパスに保存する。

- Windows: `%APPDATA%\AmityQSO\device_id.txt`
- macOS: `~/Library/Application Support/AmityQSO/device_id.txt`

このファイルはアンインストール時も削除しない（再インストール後の同一デバイス識別のため）。

### 5.3 adif_extra フィールドのスキーマ

ADIFの未定義タグは以下のJSON形式で `adif_extra` カラムに格納する。SQLiteのJSON関数（`json_extract`）を使った将来的な検索を可能にするため、フラットなオブジェクト形式とする。

```json
{
  "APP_HAMLOGW_QSO_NUMBER": "12345",
  "APP_CUSTOM_TAG": "somevalue"
}
```

### 5.4 マイグレーションスクリプト管理

マイグレーションスクリプトはコンパイル済みバイナリに埋め込み、外部ファイルに依存しない。Free Pascalの文字列リソースまたは `resourcestring` を使用する。スクリプトはバージョン番号を名前空間として管理する。

```pascal
const
  MIGRATION_001 = 'CREATE TABLE qso_log (...)';
  MIGRATION_002 = 'ALTER TABLE stations ADD COLUMN api_fetched_at INTEGER';
  // ...

procedure RunMigrations(DB: TSQLite3Connection);
var
  CurrentVersion: Integer;
begin
  CurrentVersion := DB.ExecuteScalar('PRAGMA user_version');
  if CurrentVersion < 1 then ExecuteMigration(DB, 1, MIGRATION_001);
  if CurrentVersion < 2 then ExecuteMigration(DB, 2, MIGRATION_002);
  // ...
end;
```

---

## 6. UI 設計方針

### 6.1 UIスレッドへの非同期通知パターン

すべての非同期完了通知はメインスレッドのメッセージキューへ `PostMessage`（Windows）または `Synchronize`/`Queue`（LCL）で送出する。コールバックの直接呼び出しは禁止する。

```pascal
// ワーカースレッド内（例: DB Worker）
procedure TDBWorkerThread.OnWriteComplete(const QsoID: TGUID);
begin
  TThread.Queue(nil, procedure
  begin
    // メインスレッドで実行される
    MainForm.OnQSOWriteComplete(QsoID);
  end);
end;
```

### 6.2 画面構成とレイアウト

メイン運用画面（UI-01）は1024×600pxを基準解像度とし、以下のパネル構成とする。各パネルの可視・非可視はユーザーが設定可能とし、設定は `settings.json` に永続化する。

```
┌─────────────────────────────────────────────────┐ ← 1024px
│ メニューバー / ツールバー                        │ 28px
├─────────────────────────────────────────────────┤
│ ステータスバー（VFO周波数・モード・時刻ソース）  │ 32px
├───────────────────────┬─────────────────────────┤
│                       │                          │
│  ウォーターフォール   │  デコードリスト          │ 220px
│  （可視/非可視切替）  │  （常時表示）            │
│                       │                          │
├───────────────────────┴─────────────────────────┤
│  QSO入力フォーム / Auto-Seqステータス            │ 80px
├─────────────────────────────────────────────────┤
│  CTIパネル / ログ検索（タブで切替）              │ 残余px
└─────────────────────────────────────────────────┘
```

### 6.3 ウォーターフォール描画設計

ウォーターフォールはビットマップのスキャンラインシフトで実装する。新しいFFTラインを上端に追加し、過去の行を1px下にシフトする。

- **描画スレッド**: メインスレッド（LCLのCanvasはスレッドセーフでないため）
- **FFTデータ供給**: DSPからの `DECODE_RESULT` に含まれるスペクトルデータ、またはDSPが別途提供するFFTラインデータ
- **エコモード時**: `TTimer` を停止し描画ルーチンを完全にスキップする（CPU使用率ゼロを保証）

### 6.4 コマンドパレット（UC-06）

`Ctrl+K` でフォーカス可能なドロップダウンUIを実装する。入力文字列をFTS5のMATCH句に渡し、100ms以内に候補を最大20件表示する。

```sql
SELECT callsign, notes, qso_date
FROM qso_fts
WHERE qso_fts MATCH :query
ORDER BY rank
LIMIT 20;
```

---

## 7. エラーハンドリング方針

### 7.1 エラー分類と対処

| 分類 | 例 | 対処 | UIへの通知 |
|---|---|---|---|
| Fatal | DBファイルが読み込めない | アプリ終了 | エラーダイアログ（終了必須） |
| Recoverable | DSPプロセスクラッシュ | 自動再起動（最大3回） | ステータスバーに警告 |
| Warning | NTP同期失敗 | OSクロックへフォールバック | ステータスバーにアイコン |
| Info | field_journalマージ完了 | ログ記録のみ | なし（ログファイルのみ） |
| TX Blocked | バンドプランブロック | 送信停止 | モーダルダイアログ（理由明記） |

### 7.2 ログ設計

アプリログはローテーション付きでテキストファイルに出力する。ログレベルは `DEBUG / INFO / WARN / ERROR / FATAL` の5段階とし、リリースビルドのデフォルトは `INFO` とする。

- ファイルパス: `{AppDataRoot}/logs/amity_{YYYYMMDD}.log`
- ローテーション: 10MB超過または日付変更時に新ファイルへ切替
- 保持: 最新3ファイルまで

すべてのスレッドからのログ書き込みはスレッドセーフなロガーシングルトン経由で行い、ファイルI/Oはロガー専用スレッドに集約する。

### 7.3 未処理例外の捕捉

各スレッドの `Execute` メソッド最外殻でtry-exceptを実装し、未処理例外をFatalログに記録した上でメインスレッドへ通知する。メインスレッドは例外内容をダイアログ表示し、ユーザーにバグレポートの提出を促す。

---

## 8. セキュリティ設計

### 8.1 Lua スクリプトサンドボックス

Luaランタイムの初期化時に以下の標準ライブラリを無効化し、OSリソースへのアクセスを遮断する。

```pascal
// 無効化するLuaライブラリ
// io, os, package, dofile, loadfile, require
// debug（リフレクション禁止）
```

スクリプトが使用できるAPIは、以下のAmity提供のLuaバインディングに限定する。

- `amity.qso_get(field_name)`: 現在のQSOフィールド読み取り
- `amity.score_set(points)`: スコア加算
- `amity.log(message)`: ログ出力

### 8.2 ED25519 署名検証フロー

Luaスクリプトは `.lua` 本体と `.sig` 署名ファイルのペアで配布する。ロード時に以下の手順で検証する。

```
1. スクリプトファイルをバイナリとして読み込む。
2. `.sig` ファイルを読み込む（Base64デコード）。
3. 組み込みの公開鍵（バイナリに埋め込み）でED25519署名を検証する。
4. 検証成功 → Luaステートへロード。
5. 検証失敗 → エラーログ記録、スクリプト実行禁止、ユーザーへ警告。
```

公開鍵はビルド時にバイナリへ埋め込み、設定ファイルやコマンドライン引数での上書きを不可とする。

### 8.3 APIキーの保護

QRZ等の外部APIキーはOSキーチェーンへ保存し、`settings.json` への平文保存を禁止する。

- Windows: Data Protection API (DPAPI) + CryptProtectData
- macOS: Security.framework / SecKeychainAddGenericPassword

---

## 9. テスト設計

### 9.1 テスト対象と手法の対応

| コンポーネント | テスト種別 | 手法・ツール | 自動化 |
|---|---|---|---|
| BandPlanGuard | 単体 | 境界値テスト（block_tx境界周波数±1Hz） | 可 |
| TimeValidator | 単体 | DTサンプル列の注入テスト | 可 |
| field_journalマージ | 統合 | 2デバイスシミュレーション（競合ケース） | 可 |
| SeqCtrl状態機械 | 統合 | イベント列注入によるstateトレース検証 | 可 |
| DB Worker | 統合 | インメモリSQLiteを使用 | 可 |
| IPC通信 | 統合 | DSPスタブプロセス（テスト用） | 可 |
| ウォーターフォール描画 | システム | 目視確認（自動化困難） | 不可 |
| デバイスホットプラグ | システム | 手動（物理デバイス必要） | 不可 |

### 9.2 テスト用スタブ設計

自動テストのためのスタブを以下の単位で用意する。

- **RigControlStub**: `IRigControl` を実装するスタブ。VFO周波数・PTT状態をメモリ上で管理し、テストコードから検証できる。
- **DSPStub**: UDPシグナリングに応答するシンプルなプロセス。事前定義されたデコード結果をJSONで返す。
- **InMemoryDB**: テスト用にオンディスクDBを使用せず、`:memory:` でSQLiteを初期化するヘルパー。

### 9.3 性能テスト基準とオートメーション

N150相当環境（またはCI環境でのソフトウェアスロットル）で以下の自動計測を実施する。各PRの mergeに際し、基準値の120%超過をregression alertとして扱う。

| 計測項目 | 基準値 | 計測方法 |
|---|---|---|
| ADIF 50万件インポート | 10分以内 | タイムスタンプ差分 |
| FTS5コールサイン検索 | 100ms以内（50万件） | クエリ前後の時刻差 |
| field_journal 1000件マージ | 60秒以内 | 処理開始〜完了コールバックまで |
| アプリ起動（コールドスタート） | 5秒以内 | プロセス起動〜メイン画面表示まで |

---

## 付録A: モジュール間インターフェース一覧

| インターフェース名 | 提供者 | 利用者 | 主なメソッド |
|---|---|---|---|
| `ISeqController` | SeqCtrl Thread | Main Thread, HwMonitor | PostEvent, CurrentState |
| `IRigControl` | RigCtldClient | SeqCtrl Thread | GetVFOFreqHz, SetPTT |
| `IDBWorker` | DB Worker Thread | SeqCtrl, CTI Engine, SyncWorker, ApiGateway | PostCommand (非同期) |
| `IBandPlanGuard` | BandPlanGuard | SeqCtrl Thread | IsTxBlocked |
| `ITimeValidator` | TimeValidator | SeqCtrl Thread, HwMonitor | CurrentStatus, AddDTSample |
| `IHwMonitor` | HwMonitor Thread | SeqCtrl Thread | RegisterResourceCallback |
| `IIPCClient` | IPC Client | SeqCtrl Thread | SendCommand, RegisterResultCallback |

---

## 付録B: α版実装チェックリスト

以下のタスクをα版DoDの達成に必要な最小実装セットとして定義する。

**インフラ整備**
- [ ] Lazarusプロジェクト構成・ディレクトリ構造の決定と初期コミット
- [ ] SQLiteラッパー（WAL・FTS5設定含む）の実装
- [ ] マイグレーション実行エンジンの実装
- [ ] スレッドセーフキュー（TThreadedQueue wrapper）の実装
- [ ] アプリログ（ローテーション付き）の実装

**コアコンポーネント**
- [ ] DB Worker Thread（CRUD・FTS5同期）
- [ ] RigControlPort（rigctld TCPクライアント）
- [ ] IPC Client/Server（UDP + 共有メモリ）
- [ ] Callsign Resolver（Cty.dat読み込み・プレフィックス解決）
- [ ] BandPlanGuard（メモリキャッシュ・バイナリサーチ）

**UI**
- [ ] メイン運用画面フレーム（1024×600px対応）
- [ ] デコードリスト表示
- [ ] VFO / 時刻ソース ステータスバー
- [ ] QSO手動入力フォーム
- [ ] 設定画面（音声・CAT・基本設定タブ）

**データ入出力**
- [ ] ADIF 3.1.4エクスポート
- [ ] ADIFインポート（重複検出・バッチトランザクション）

**テスト**
- [ ] RigControlStub / InMemoryDB の実装
- [ ] BandPlanGuard 単体テスト
- [ ] ADIF 50万件インポート性能テスト

---

## 10. 音声パイプライン設計

### 10.1 概要とスレッド配置

音声入出力はOSのオーディオAPIを介して行う。コールバックベースのAPIがほとんどのOSで採用されているため、本設計では**オーディオコールバックスレッド**を独立した最高優先度スレッドとして確保し、バッファアンダーランを防ぐ。

```
  [入力系]
  マイク/ライン入力
    ↓ OS Audio Callback (高優先度スレッド)
  Ring Buffer (入力) ── 共有メモリ ──→ DSP Plugin (DECODE_REQUEST)

  [出力系]
  DSP Plugin (ENCODE_RESULT) ── 共有メモリ ──→ Ring Buffer (出力)
    ↓ OS Audio Callback (高優先度スレッド)
  スピーカー/ライン出力
```

### 10.2 OS別オーディオAPI

| OS | 採用API | 理由 |
|---|---|---|
| Windows | WASAPI (Shared Mode) | Vista以降で標準。低レイテンシー。排他モードは他アプリとの共存を妨げるためSharedを選択 |
| macOS | Core Audio (AudioUnit) | macOS標準。コールバックベースでレイテンシーが安定 |

WASAPIのデバイス識別はGUID文字列、Core AudioはUIDでそれぞれ `settings.json` に保存する。起動時にデバイス一覧を取得して保存済みGUID/UIDと照合し、一致するデバイスへ自動バインドする。

### 10.3 リングバッファ設計

オーディオコールバックとSeqCtrlスレッドの間はロックフリーなリングバッファで接続する。サイズはFT8の1送信サイクル（12.64秒 × 48000Hz × 4バイト = 約2.4MB）の2倍を確保する。

```pascal
type
  TAudioRingBuffer = record
    Data        : array[0..RING_BUF_SIZE - 1] of Single;  // float32
    WritePos    : Int64;  // アトミック書き込み（Interlocked）
    ReadPos     : Int64;  // アトミック読み取り（Interlocked）
    SampleRate  : Integer;  // 48000固定
    Channels    : Integer;  // 1（モノラル）
  end;
  // RING_BUF_SIZE = 48000 * 30  // 30秒分
```

WritePos / ReadPos の更新にはアトミック操作（`InterlockedExchangeAdd64`）を使用し、ミューテックス不要とする。バッファが満杯の場合は最古のデータを上書きし、警告ログを出力する。

### 10.4 デバイスホットプラグ検知

```
  Windows: IMMNotificationClient::OnDeviceStateChanged を実装して登録
  macOS:   kAudioHardwarePropertyDevices の Property Listener を登録

  検知イベント受信時の処理フロー:
  1. 現在バインド中のデバイスが消えた場合 → 音声ストリームを停止
  2. 設定済みデバイスGUID/UIDが再出現した場合 → 自動再バインドを試みる
  3. 5秒以内に再バインド成功 → ステータスバーに「オーディオ再接続」通知
  4. 失敗 → エラーとしてユーザーに手動選択を促す
```

---

## 11. Auto-Seq 詳細設計

### 11.1 シーケンス状態機械（FT8標準QSOフロー）

FT8の標準的なQSOシーケンスを状態機械として実装する。各状態はSeqCtrlスレッドが保持し、DSPからの `DECODE_RESULT` イベントおよびタイマーイベントによって遷移する。

```
                    ┌────────────────────────────────────────┐
                    │  ユーザーがデコードリスト上の局を選択  │
                    └───────────────┬────────────────────────┘
                                    ▼
  ┌─────────┐   TX許可      ┌───────────────┐  送信完了   ┌──────────────┐
  │  IDLE   │ ──────────→  │ TX: CQ / QRZ  │ ─────────→ │ RX_WAIT_RSP  │
  └─────────┘              └───────────────┘             └──────┬───────┘
       ▲                                                         │
       │                                             応答受信    │  タイムアウト
       │                                          (callsign一致) │  (次サイクル)
       │                                                         ▼
       │                                             ┌──────────────────┐
       │                                             │ TX: RST EXCHANGE │
       │                                             └────────┬─────────┘
       │                                                      │ 送信完了
       │                                                      ▼
       │                                             ┌──────────────────┐
       │                                             │  RX_WAIT_RST     │
       │                                             └────────┬─────────┘
       │                                                      │ RST受信
       │                                                      ▼
       │                                             ┌──────────────────┐
       │                                             │  TX: RR73 / 73   │
       │                                             └────────┬─────────┘
       │                                                      │ 送信完了
       │                                                      ▼
       │                             ┌───────────────────────────────────┐
       │                             │  QSO_COMPLETE: DBへ記録           │
       │                             │  field_journalへ出力              │
       └─────────────────────────────┘
```

### 11.2 Auto-Seq判断ロジック

各RX_WAITサイクル（15秒）の終了時点で、デコード結果に対して以下の順序で判定する。

```
1. デコード結果の中から、自局のコールサインが含まれるメッセージを抽出する。
2. 抽出されたメッセージの送信局が、現在交信対象の局（TargetCallsign）と一致するか確認する。
3. 一致した場合、メッセージタイプを判定する:
   - RST交換 → TX: RR73 送信へ遷移
   - RR73 / 73 → QSO_COMPLETE へ遷移
4. タイムアウト（2サイクル連続応答なし）の場合:
   - Wait & Reply モード（New DXCC等の設定時）→ IDLE に戻り次サイクル待機
   - 通常モード → QSOを中断してIDLEへ
```

### 11.3 送信メッセージ生成

送信メッセージのテキストはDSPへ送る前にSeqCtrlが生成する。変数展開は以下のルールで行う。

| 変数 | 展開値 |
|---|---|
| `{MYCALL}` | 自局のコールサイン（設定値） |
| `{DXCALL}` | 相手局のコールサイン |
| `{RST}` | 現在設定中のRSTレポート（デフォルト: 59 / -10） |
| `{GRID}` | 自局のグリッドスクエア（設定値） |
| `{EXCH}` | コンテスト時のエクスチェンジ文字列（Contest Engine提供） |

FT8のメッセージ長上限（13文字相当）の検証はDSPのエンコード前にSeqCtrlで行い、超過する場合はエラーとして送信を中断する。

### 11.4 Wait & Reply（New DXCC等の優先応答）

CTIエンジンが「New DXCC」または「New Band」のサジェストを返した局については、ユーザー設定で「Wait & Reply」モードを有効化できる。このモードでは以下の動作となる。

- CQを出している対象局が見つかった瞬間、現在のシーケンスより優先して呼び出しを開始する。
- Wait & Replyの発動にはユーザーの確認（UIポップアップへの承認）を必須とするか、設定で自動発動に切り替えられる。

---

## 12. CTIエンジン詳細設計

### 12.1 CTI表示の処理フロー

CTIエンジンはDB Worker Threadへの非同期クエリと外部API取得を並列に実行し、300ms以内にUIへ描画データを返す。

```
  ユーザーがコールサインを選択（Main Thread）
    ↓ PostCommand(dbkReadCTI, callsign)  [非同期]
  DB Worker Thread
    ├─ qso_logから過去QSOを集計（バンド別・日付別）
    ├─ stationsテーブルからキャッシュ取得
    └─ 結果をMain Threadへコールバック
         ↓ UIへ即時反映（ここまでで目標: 200ms以内）

  並列で:
  ApiGateway Thread（キャッシュが古い場合のみ）
    └─ QRZ.com XML API取得（Luaスクリプト経由）
         ↓ stationsテーブルへ更新
         ↓ UIへ差分更新（追加で100ms以内）
```

### 12.2 サジェストバッジの判定ルール

サジェストバッジは DB集計結果から同期的に算出する。外部APIの結果を待たずに表示する（表示速度を優先）。

| バッジ名 | 判定条件 | 表示色 |
|---|---|---|
| New DXCC | `qso_log` に同一 `dxcc_entity` のレコードが存在しない | 金 |
| New Band | 同一 `callsign` の `band` が現在VFO帯域と一致するレコードが存在しない | 緑 |
| LoTW未CFM | `lotw_qslsent = 'Y'` かつ `lotw_qslrcvd = 'N'` のレコードが存在する | 橙 |
| 初QSO | `qso_log` に同一 `callsign` のレコードが存在しない | 青 |
| 久しぶり | 最終QSOから90日以上経過している | グレー |

### 12.3 アフィニティレベルの算出

アフィニティレベルは `stations.qso_count` に基づいて算出し、QSO記録時に `stations` テーブルを更新する。

| レベル | 条件 | アイコン |
|---|---|---|
| 0 | 未交信（callsignがstationsに存在しない） | 無アイコン |
| 1 | 1〜4回 | ⭐ |
| 2 | 5〜19回 | ⭐⭐ |
| 3 | 20回以上 | ⭐⭐⭐ |

アフィニティレベルの閾値は将来の設定項目候補とするが、v1.0では固定値とする。

### 12.4 外部APIキャッシュ方針

`stations.api_fetched_at` が現在時刻より7日以上古い場合のみAPIを再取得する。APIが失敗した場合はキャッシュをそのまま使用し、次回起動時に再試行する。APIへの通信はApiGateway Threadが行い、メインスレッドは待機しない。

---

## 13. Contest Engine 詳細設計

### 13.1 コンポーネント構成

Contest Engineはコンテスト定義（JSON + Lua）を読み込み、QSOごとのDupe判定・マルチプライヤー計算・スコア集計を提供する。エンジン自体は `IContestEngine` インターフェースで抽象化し、コンテスト非活性時は空実装（NullObject）を差し込む。

```pascal
type
  IContestEngine = interface
    function  IsDupe(const Callsign, Band, Mode, Exchange: string): Boolean;
    function  ScoreQSO(const QSOData: TQSOData): Integer;
    function  GetMultipliers: TMultiplierList;
    function  GetTotalScore: Integer;
    procedure OnQSOLogged(const QSOData: TQSOData);
    procedure LoadDefinition(const JSONPath, LuaPath: string);
  end;
```

### 13.2 コンテスト定義ファイル仕様

#### JSON メタデータ（例: JA0 QSO Party）

```json
{
  "contest_id":    "JA0QSO",
  "name":          "JA0 QSO Party",
  "start_utc":     "2025-06-07T00:00:00Z",
  "end_utc":       "2025-06-07T09:00:00Z",
  "bands":         ["80m","40m","20m","15m","10m"],
  "modes":         ["FT8","CW","SSB"],
  "required_fields": ["callsign", "rst", "exchange"],
  "exchange_format": "^[0-9]{2}[0-9a-zA-Z]{1,6}$",
  "dupe_per":      "band",
  "lua_script":    "ja0qso.lua"
}
```

`dupe_per` の選択肢は `"total"` / `"band"` / `"band_mode"` とし、Contest Engineの汎用Dupeキャッシュキーとして使用する。

#### Lua スクリプト（スコア算出）

```lua
-- ja0qso.lua
-- Amity-QSO Contest Engine Lua API バインディング使用

function on_qso(qso)
  local pts = 0

  -- QSOポイント判定
  if qso.dxcc == "JA" then
    pts = 1
  else
    pts = 3
  end

  -- マルチプライヤー登録（バンドごとのJA0エリア局）
  if string.match(qso.exchange, "^0") then
    amity.mult_add("JA0_" .. qso.band, qso.exchange)
  end

  amity.score_add(pts)
end

function get_total_score()
  return amity.score_get() * amity.mult_count()
end
```

### 13.3 Dupeキャッシュ設計

コンテスト開始時、過去QSOからDupeキャッシュをメモリに構築する。以降はQSO記録のたびにキャッシュを更新し、DB問い合わせなしでリアルタイム判定する。

```pascal
type
  TDupeCache = class
  private
    // Key: "<callsign>|<band>"（dupe_per="band"の場合）
    FCache: TDictionary<string, Boolean>;
  public
    function IsDupe(const Key: string): Boolean;
    procedure Add(const Key: string);
    procedure RebuildFromDB(DBWorker: IDBWorker;
                            const ContestID: string;
                            DupePer: TDupePerMode);
  end;
```

DupeキャッシュはSeqCtrlスレッドが保持し、UIスレッドからは読み取り専用でアクセスする（コピーオンリード）。

### 13.4 Cabrillo 3.0 出力

Cabrillo出力はDB Workerへのクエリ結果をUIスレッドではなくSync Worker Thread上でファイル出力する。出力完了後にファイルパスをUIへ通知する。

必須ヘッダーフィールドの値は設定画面で事前入力させ、不足時はエクスポートダイアログで警告する。

```
START-OF-LOG: 3.0
CALLSIGN: JA1ABC
CONTEST: JA0-QSO-PARTY
CATEGORY-OPERATOR: SINGLE-OP
CATEGORY-BAND: ALL
CATEGORY-MODE: MIXED
CLAIMED-SCORE: 1234
QSO: 14074 FT8 2025-06-07 0123 JA1ABC 59 001 JA0XYZ 59 0001
END-OF-LOG:
```

---

## 14. ビルド・開発環境設計

### 14.1 ディレクトリ構成

```
amity-qso/
├── src/
│   ├── app/                    # アプリケーション層（Layer 3）
│   │   ├── SeqCtrl.pas
│   │   ├── BandPlanGuard.pas
│   │   ├── TimeValidator.pas
│   │   ├── CTIEngine.pas
│   │   └── ContestEngine.pas
│   ├── infra/                  # インフラ層（Layer 2）
│   │   ├── DBWorker.pas
│   │   ├── RigControlPort.pas
│   │   ├── IPCClient.pas
│   │   ├── ApiGateway.pas
│   │   └── SyncWorker.pas
│   ├── platform/               # プラットフォーム抽象層（Layer 1）
│   │   ├── AudioWASAPI.pas     # Windows
│   │   ├── AudioCoreAudio.pas  # macOS
│   │   ├── HwMonitorWin.pas
│   │   ├── HwMonitorMac.pas
│   │   └── KeychainStorage.pas
│   ├── ui/                     # プレゼンテーション層（Layer 4）
│   │   ├── MainForm.pas
│   │   ├── CTIPanel.pas
│   │   ├── SettingsForm.pas
│   │   ├── ContestForm.pas
│   │   └── AwardForm.pas
│   └── shared/                 # 共有型・インターフェース定義
│       ├── Interfaces.pas      # ISeqController, IRigControl 等
│       ├── Types.pas           # TQSOData, TSeqState 等
│       └── Constants.pas
├── dsp/                        # DSPプラグイン（別プロジェクト）
│   ├── AmityDSP.lpr
│   └── FT8Engine.pas
├── tests/
│   ├── unit/                   # 単体テスト
│   │   ├── TestBandPlanGuard.pas
│   │   ├── TestTimeValidator.pas
│   │   └── TestFieldJournalMerge.pas
│   └── integration/            # 統合テスト
│       ├── TestDBWorker.pas
│       ├── TestSeqCtrl.pas
│       └── Stubs/
│           ├── RigControlStub.pas
│           └── DSPStub/        # UDP応答スタブプロセス
├── resources/
│   ├── band_plan/
│   │   ├── JA.json
│   │   └── US.json
│   └── lua_scripts/
│       └── qrz_parser.lua
├── docs/
│   ├── prd-v2.md
│   └── basic-design-v1.md      # 本文書
├── AmityQSO.lpr                # メインプロジェクトファイル
└── AmityQSO.lpi                # Lazarus IDEプロジェクト
```

### 14.2 ビルド設定

| 設定項目 | Debug | Release |
|---|---|---|
| 最適化レベル | -O0（無効） | -O2 |
| デバッグ情報 | -g（有効） | なし |
| アサーション | 有効 | 無効 |
| ログレベル | DEBUG | INFO |
| DSP連携 | スタブ（オプション） | 実プロセス |

ビルドは `lazbuild` コマンドラインツールを使用し、GUIのIDEに依存しない。

```bash
# Releaseビルド（Windows向け）
lazbuild --bm=Release --os=win64 --cpu=x86_64 AmityQSO.lpr

# Releaseビルド（macOS向け）
lazbuild --bm=Release --os=darwin --cpu=x86_64 AmityQSO.lpr
```

### 14.3 CI/CD パイプライン設計

GitHub Actions（または同等のCIシステム）を前提とした自動ビルド・テストパイプラインを構築する。

```yaml
# ビルドマトリクス
strategy:
  matrix:
    os: [windows-latest, macos-latest]
    build_mode: [Debug, Release]

steps:
  - name: Install Lazarus
    # FPC + Lazarusをセットアップ（キャッシュ利用）

  - name: Build
    run: lazbuild --bm=${{ matrix.build_mode }} AmityQSO.lpr

  - name: Unit Tests
    run: lazbuild tests/unit/AllTests.lpr && ./AllTests --format=plain

  - name: Integration Tests
    run: |
      # DSPスタブを起動してから統合テストを実行
      ./DSPStub &
      lazbuild tests/integration/AllIntegTests.lpr && ./AllIntegTests

  - name: Performance Tests（Releaseのみ）
    if: matrix.build_mode == 'Release'
    run: ./PerformanceTest --adif-rows=500000 --time-limit=600
```

プルリクエストへのマージにはすべてのCIジョブの成功を必須とする。

### 14.4 バージョン管理方針

- **ブランチ戦略**: `main`（リリース済み）/ `develop`（開発中）/ `feature/*`（機能別）
- **コミットメッセージ規約**: Conventional Commits に準拠。
  例: `feat(seq): Add Wait & Reply mode for new DXCC detection`
- **タグ規則**: `v0.1.0-alpha`, `v0.2.0-beta`, `v1.0.0` のセマンティックバージョニング
- **変更禁止ファイル**: `src/app/BandPlanGuard.pas` および `src/app/TimeValidator.pas` への変更は必ずセキュリティレビューを経る（CODEOWNERS設定）

---

## 付録C: β版実装チェックリスト

α版DoDの達成を前提とし、以下のタスクをβ版DoDの達成に必要な実装セットとして定義する。

**送信制御と安全機構**
- [ ] SeqCtrl状態機械の実装（IDLE / WAIT_TX_PERMIT / TX_RUNNING / RX_WAIT / TX_BLOCKED）
- [ ] BandPlanGuardとTimeValidatorによる二重送信許可チェックの実装
- [ ] PTT制御のSeqCtrlスレッド専用化（UIスレッドからの直接呼び出し禁止をlintルールで強制）
- [ ] 送信ハードロック（TX_BLOCKED状態）のUI表示（赤色アラート・送信ボタン無効化）
- [ ] TX_BLOCKEDからの解除フロー（ユーザー明示操作必須）の実装

**時刻同期**
- [ ] GNSS NMEA $GPRMCシリアルパーサーの実装
- [ ] NTPクライアントの実装（精度・RTT取得含む）
- [ ] 時刻ソース優先度管理とフォールバックロジックの実装
- [ ] DTリングバッファ（30サンプル）と中央値計算の実装
- [ ] 時刻ソース・推定精度のステータスバー表示

**動的リソーススケーリング**
- [ ] HwMonitor ThreadのOS別CPU使用率収集実装（Win: GetSystemTimes / mac: host_processor_info）
- [ ] RESOURCE_PROFILEを受信してDEEP/FAST切替判定するロジックの実装
- [ ] アイドルエコモード（ウォーターフォール描画停止）の実装

**音声・DSP**
- [ ] WASAPI（Windows）音声入出力の実装
- [ ] Core Audio（macOS）音声入出力の実装
- [ ] オーディオデバイスホットプラグ検知と自動再バインドの実装
- [ ] DSPプロセスクラッシュ検知と自動再起動（最大3回）の実装

**Auto-Seq**
- [ ] FT8標準QSOシーケンス状態機械の実装
- [ ] デコード結果から自局コールサイン含有メッセージの抽出ロジックの実装
- [ ] タイムアウト（2サイクル無応答）による中断ロジックの実装
- [ ] 送信メッセージ変数展開（{MYCALL}, {DXCALL}, {RST}, {GRID}）の実装

**テスト**
- [ ] SeqCtrl状態機械の統合テスト（イベント列注入によるstateトレース）
- [ ] TimeValidator DTサンプル注入テスト（境界値: 29 / 30サンプル・閾値±2.0秒）
- [ ] DSPスタブプロセスを用いたIPC送受信統合テスト
- [ ] バンドプランブロックおよび時刻ロックの送信安全自動テスト（TC-BAND-01, TC-TIME-01）
- [ ] アプリ最小化時のCPU使用率計測テスト（エコモード検証）

---

## 付録D: Lua スクリプト仕様

### D.1 Amity提供バインディング一覧

Luaスクリプトから呼び出せる関数を以下に限定する。これ以外の関数（標準ライブラリ含む）は呼び出し時にエラーとなる。

#### 共通バインディング

| 関数 | 引数 | 戻り値 | 説明 |
|---|---|---|---|
| `amity.log(msg)` | string | なし | INFOレベルでアプリログへ出力 |
| `amity.error(msg)` | string | なし | ERRORレベルでアプリログへ出力し実行継続 |

#### Contest Engine用バインディング

| 関数 | 引数 | 戻り値 | 説明 |
|---|---|---|---|
| `amity.score_add(pts)` | integer | なし | 現在のスコアに加算 |
| `amity.score_get()` | なし | integer | 現在の累計スコアを返す |
| `amity.mult_add(category, key)` | string, string | boolean | マルチプライヤーを登録。既存なら false |
| `amity.mult_count()` | なし | integer | 登録済みマルチプライヤー数を返す |

#### APIパーサー用バインディング

| 関数 | 引数 | 戻り値 | 説明 |
|---|---|---|---|
| `amity.xml_get(path)` | string（XPath式） | string | HTTP応答XML文字列から値を取得 |
| `amity.result_set(field, value)` | string, string | なし | パース結果フィールドに値をセット |

### D.2 APIパーサースクリプトサンプル（QRZ.com）

```lua
-- qrz_parser.lua  (ED25519署名検証済みのみ実行)
-- QRZ.com XML APIのレスポンスをパースし、stationsテーブル更新用データを返す

function parse(xml_body)
  local name  = amity.xml_get("//QRZDatabase/Callsign/fname")
              .. " "
              .. amity.xml_get("//QRZDatabase/Callsign/name")
  local qth   = amity.xml_get("//QRZDatabase/Callsign/addr2")
  local grid  = amity.xml_get("//QRZDatabase/Callsign/grid")

  if name == " " then
    amity.error("QRZ: name not found in response")
    return
  end

  amity.result_set("name",       name)
  amity.result_set("qth",        qth)
  amity.result_set("gridsquare", grid)
  amity.log("QRZ parse complete: " .. name)
end
```

### D.3 スクリプト署名の生成手順（開発者向け）

```bash
# ED25519キーペアの生成（初回のみ。秘密鍵は厳重管理）
openssl genpkey -algorithm ED25519 -out amity_sign_private.pem
openssl pkey -in amity_sign_private.pem -pubout -out amity_sign_public.pem

# スクリプトへの署名
openssl pkeyutl -sign \
  -inkey amity_sign_private.pem \
  -in qrz_parser.lua \
  -out qrz_parser.lua.sig

# 署名の検証（配布前確認）
openssl pkeyutl -verify \
  -pubin -inkey amity_sign_public.pem \
  -in qrz_parser.lua \
  -sigfile qrz_parser.lua.sig
```

公開鍵（`amity_sign_public.pem` の内容）はリリースビルド時に `Constants.pas` の定数としてバイナリへ埋め込む。

---

## 付録E: 用語別実装担当マトリクス（推奨）

| モジュール | 推奨担当スキル | 依存モジュール | 実装順序 |
|---|---|---|---|
| Interfaces.pas / Types.pas | シニアエンジニア | なし | 最初（全員が参照） |
| DBWorker | SQLite経験者 | なし | 2番目 |
| BandPlanGuard | Free Pascal基礎 | DBWorker | 3番目 |
| RigControlPort | TCP/ソケット経験者 | Interfaces | 3番目（並行可） |
| IPC Client/Server | 共有メモリ・UDP経験者 | Interfaces | 3番目（並行可） |
| SeqCtrl | 状態機械設計経験者 | BandPlanGuard, TimeValidator, RigControlPort, IPC | 4番目 |
| HwMonitor / TimeValidator | OS API経験者 | Interfaces | 4番目（並行可） |
| UI / MainForm | LCL / Lazarus Forms経験者 | SeqCtrl（インターフェース経由） | 5番目 |
| CTIEngine | SQLite FTS5経験者 | DBWorker | 5番目（並行可） |
| Contest Engine + Lua | Lua組み込み経験者 | DBWorker | v1.0フェーズ |
| SyncWorker（field_journal） | ファイルシステム・並行処理経験者 | DBWorker | v1.0フェーズ |

---

## 15. コンポーネント分割方針（v1.1 新設）

本章はコンポーネント設計書 v1.0 のアーキテクチャ上の根拠を記述する。具体的なインターフェース宣言・カタログ・ロードマップはコンポーネント設計書を参照すること。

### 15.1 コンポーネント分割の目的

本プロジェクトのコンポーネント分割は以下の3目的を持つ。

**目的1 — 保守性の向上:** 変更頻度の高い領域（デジタルモード追加・リグプロトコル追加）を独立コンポーネントにすることで、変更の影響範囲を限定する。新モード追加が SeqCtrl・UI・DBWorker に波及しない設計を構造で保証する。

**目的2 — テスト容易性の向上:** コンポーネントが独立してビルド・テストできることを要件（F-REUSE-01〜08）とし、ハードウェア（リグ・音声デバイス・DSPプロセス）なしで機能テストを完結できる環境を整える。

**目的3 — 再利用性の確保:** ADIF I/O・コールサインリゾルバ・LWW同期エンジン等をアマチュア無線ドメインの共有ライブラリとして抽出し、Amity-QSO 以外のツール開発基盤とする。

### 15.2 コンポーネント分類

コンポーネントを4カテゴリに分類する。各カテゴリの詳細定義・カタログはコンポーネント設計書 v1.0 を参照すること。

| カテゴリ | 記号 | 説明 | 配置先 |
|---|---|---|---|
| 汎用ミドルウェア | M | SQLite操作・Luaランタイム・同期エンジン等。無線ドメインに依存しない | `lib/middleware/` |
| 無線ドメインライブラリ | H | ADIF・コールサインリゾルバ・バンドプラン等。アマチュア無線固有だが Amity-QSO 非依存 | `lib/hamlib/` |
| 技術インフラ部品 | T | 音声バッファ・ED25519検証・プロセス監視等。OS固有実装を含む | `lib/infra/` |
| アプリ固有コンポーネント | A | CTIアフィニティ・アワード計算・外部サービス連携等。Amity-QSO 固有 | `src/app/` |
| 信号処理コンポーネント | D | デジタルモードコーデック・音声パイプライン・シーケンス規則 | `dsp/` + `src/app/` |
| リグ制御コンポーネント | R | リグプロトコル・機能インターフェース・接続状態機械 | `src/infra/` |

### 15.3 ディレクトリ構成（コンポーネント分割後）

```
amity-qso/
├── lib/                         ← ライブラリ（アプリ非依存）
│   ├── middleware/              ← M カテゴリ
│   │   ├── LWWSync/             M-01 LWWジャーナル同期エンジン
│   │   ├── SQLiteMigrate/       M-02 DBマイグレーション
│   │   ├── LuaSandbox/          M-03 Luaサンドボックスランタイム
│   │   ├── AsyncDispatch/       M-04 非同期コールバックキュー
│   │   └── FTS5Search/          M-05 FTS5全文検索ラッパー
│   ├── hamlib/                  ← H カテゴリ（無線ドメインライブラリ）
│   │   ├── ADIFLib/             H-01 ADIF I/Oライブラリ
│   │   ├── DXCCResolver/        H-02 コールサイン・DXCCリゾルバ
│   │   ├── BandPlanEngine/      H-03 バンドプランエンジン
│   │   ├── CabrilloLib/         H-04 Cabrillo I/Oライブラリ
│   │   ├── GridSquareLib/       H-05 グリッドスクエアライブラリ
│   │   ├── QSLStateMachine/     H-06 QSL状態機械
│   │   ├── ContestRules/        H-07 コンテストルールインタープリター
│   │   └── FreqFormatter/       H-08 周波数フォーマッター
│   └── infra/                   ← T カテゴリ（技術インフラ）
│       ├── SPSCBuffer/          T-01 SPSCオーディオリングバッファ
│       ├── CodeSigning/         T-02 ED25519署名検証器
│       ├── ProcessGuard/        T-03 子プロセス監視状態機械
│       └── ConfigDSL/           T-04 設定スキーマDSL
├── src/                         ← アプリ本体
│   ├── shared/                  AmityTypes / AmityInterfaces / AmityConstants
│   ├── platform/                OS別実装（Layer 1）
│   ├── infra/                   インフラ層（Layer 2）+ R カテゴリ
│   ├── app/                     アプリ層（Layer 3）+ A カテゴリ
│   └── ui/                      UIレイヤー（Layer 4）
├── dsp/                         ← DSPプロセス + D カテゴリ
└── tests/
    ├── unit/
    └── integration/
```

### 15.4 コンポーネント境界の設計ルール

以下のルールは第1章の設計制約と同等の強制力を持ち、コードレビューで確認する。

**ルール1: 一方向依存の強制**
`lib/` 内のコンポーネントは `src/` のコードを `uses` してはならない。依存方向は `src/` → `lib/` の一方向のみ。

**ルール2: インターフェース接続の原則**
コンポーネント間の接続は宣言されたインターフェース型のみを通じて行う。具体クラスを別コンポーネントから直接参照することを禁止する。

**ルール3: アダプターパターンの使用**
`lib/` コンポーネントが `src/` の型（TQSOData等）を必要とする場合、アダプタークラスを `src/` 側に置き、`lib/` 側は抽象インターフェースのみに依存させる。

**ルール4: ライブラリ化候補の独立ビルド**
M・H カテゴリのコンポーネントは、Lazarus プロジェクトファイルを個別に持ち、`AmityQSO.lpr` なしに単独でビルド・テストできること。CI パイプラインでこれを検証する。

### 15.5 コンポーネント化の段階的実施計画

コンポーネント化は既存の開発フェーズと並行して段階的に実施する。詳細ロードマップはコンポーネント設計書 v1.0 付録Bを参照すること。

| フェーズ | 対象 | タイミング |
|---|---|---|
| フェーズ1 | H-01 ADIF, H-02 Callsign, H-05 GridSquare, H-08 FreqFormatter, M-02 DBMigrate, M-05 FTS5 | α版並行 |
| フェーズ2 | D-01 Codec, D-02 SeqRules, R-01 Protocol, R-02 機能IF, M-04 AsyncCB, T-01 SPSCBuffer | β版並行 |
| フェーズ3 | M-01 LWWSync, M-03 LuaSandbox, H-06 QSL, H-07 ContestRules, T-02 CodeSign, R-03/R-04 | v1.0後 |

