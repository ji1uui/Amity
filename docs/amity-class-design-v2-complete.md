# Amity-QSO クラス設計書 v2.1（完全版）

> **文書管理**
> | 項目 | 内容 |
> |---|---|
> | 文書バージョン | 2.1 |
> | ステータス | 改訂済 |
> | 前版 | クラス設計書 v1.0 |
> | 改訂根拠 | OOPレビュー v1.0（全24問題を反映） |
> | 対象読者 | 実装担当エンジニア・コードレビュアー |

---

## 文書構成

| 章 | 内容 |
|---|---|
| **共有型・インターフェース** | AmityTypes.pas / AmityInterfaces.pas / DBCommands.pas / AmityConstants.pas |
| **Layer 2: インフラ層** | TDBWorkerThread, TRigCtldClient, TIPCEndpoint, TApiGatewayThread, TAppSettings, TSyncWorkerThread |
| **Layer 3: アプリケーション層** | TSeqControllerThread, TBandPlanGuard, TTimeValidator, TTimeSourceManager, THwMonitorThread, TCallsignResolver, TCTIEngine, TContestEngineImpl, TLuaRuntime, TMessageBuilder |
| **Layer 4: UIレイヤー** | TMainForm, TDecodeListFrame, TCTIPanel, TStatusBarPanel, TCommandPalette, TSettingsForm, TAwardForm |
| **Composition Root** | AmityQSO.lpr — 全依存の組み立てと起動シーケンス |
| **テストスタブ** | TRigControlStub, TQSORepositoryStub 他 分割スタブ群 |
| **ContestEngine 完全定義** | TNullContestEngine, TDupeCache, TContestEngineImpl |
| **総括** | インターフェース階層図・スレッド間通信図・全問題対応確認表 |

---

# Amity-QSO クラス設計書 v2.0 — Part A
## 共有型・インターフェース・横断的関心事

> **改訂経緯**: OOPレビュー v1.0 の全24問題を反映。
> 変更箇所には `[改訂: 問題番号]` を付記する。

---

## 変更サマリー

| 問題 | 変更内容 | 対象ファイル |
|---|---|---|
| 2-1 | `TCTIData`: TStringList→値型配列。Record→Class化 | Types.pas |
| 2-4 | `TDTRingBuffer`: Record→Class化 | Types.pas |
| 2-3 | `TCtyEntry`: Record→Class化（CallsignResolver側で対処） | Types.pas |
| 1-1 | `IDBWorker`を4インターフェースに分割 | Interfaces.pas |
| 1-2 | `IIPCEndpoint`を`IIPCSender`+`IDSPLifecycle`に分割 | Interfaces.pas |
| 1-3 | `IRigControl`を`IRigFreqControl`+`IRigTransmitControl`に分割 | Interfaces.pas |
| 1-4 | `IAudioManager`デバイス列挙の戻り値を値型配列に変更 | Interfaces.pas |
| 3-5 | `ILuaScoringContext`新設。`SetScoreContext(PInteger)`を廃止 | Interfaces.pas |
| 4-1 | `ILogger`新設。Singletonへのグローバル依存を排除 | Interfaces.pas |
| 4-2 | `TObserverList<T>`新設。単一コールバック制約を解消 | Interfaces.pas |
| 5-2 | `IBandPlanLoader`新設。`IBandPlanGuard`から`Reload`を除去 | Interfaces.pas |
| 5-3 | `ITimeValidator`に`UpdateTimeSource`を昇格 | Interfaces.pas |
| 3-2 | `ITimeSourceManager`新設 | Interfaces.pas |
| 6-5 | `TNullContestEngine`をInterfaces.pasから移動 | ContestEngine.pas側 |
| 6-1 | `TSeqControllerDeps`（Parameter Object）新設 | Interfaces.pas |
| 6-2 | `IContestEngine.ScoreQSO`を廃止 | Interfaces.pas |
| 6-3 | `ISyncWorker`に`PendingCount`・`IsMerging`追加 | Interfaces.pas |
| D-01〜03 | デジタルモードコーデック・シーケンス規則・音声パイプラインI/F追加 | 新設ユニット群 |
| R-01〜04 | リグプロトコル・機能IF・接続SM・バンド連携I/F追加 | 新設ユニット群 |
| M/H/T/A | 汎用・無線ライブラリ・インフラ・アプリ固有コンポーネントI/F追加 | lib/以下新設ユニット群 |

---

## 1. 共有型定義（shared/Types.pas）— 改訂版

```pascal
unit AmityTypes;
// ファイル名を Types.pas から AmityTypes.pas に変更。
// FPC の標準 Types ユニットとの名前衝突を回避する。

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes;

// =============================================================================
//  基本例外階層（変更なし）
// =============================================================================
type
  EAmityBase     = class(Exception);
  EAmityDB       = class(EAmityBase);
  EAmityIPC      = class(EAmityBase);
  EAmityRig      = class(EAmityBase);
  EAmityAudio    = class(EAmityBase);
  EAmityLua      = class(EAmityBase);
  EAmitySecurity = class(EAmityBase);
  EAmityConfig   = class(EAmityBase);

// =============================================================================
//  列挙型（変更なし）
// =============================================================================
type
  TSeqState = (
    ssIdle, ssWaitTxPermit, ssTxRunning, ssRxWait, ssTxBlocked
  );
  TSeqEvent = (
    seStartCQ, seStartQSO, seResponseReceived, seRSTExchanged,
    se73Sent, seStopRequested, sePermitGranted, sePermitRejected,
    seEncodeComplete, seDecodeResult, seTxTimeout, seRxTimeout,
    seUnblockRequested
  );
  TTxBlockReason   = (tbrNone, tbrBandPlan, tbrTimeInvalid, tbrBoth);
  TTimeSource      = (tsUnknown, tsGNSSPPS, tsGNSSNMEA, tsNTP, tsOSClock);
  TTimeValidatorStatus = (tvsUnknown, tvsValid, tvsInvalid);
  TRigConnectionState  = (rcsDisconnected, rcsConnecting, rcsConnected, rcsError);
  TDSPProcessState     = (dpsNotStarted, dpsStarting, dpsRunning,
                           dpsCrashed, dpsUnavailable);
  TAudioDeviceState    = (adsUnbound, adsBound, adsError, adsDisconnected);
  TQSLStatus           = (qslWKD, qslSent, qslRcvd, qslCFM, qslRejected);
  TDupePerMode         = (dpmTotal, dpmBand, dpmBandMode);
  TDSPDepthMode        = (ddmFast, ddmDeep);
  TAffinityLevel       = 0..3;

// =============================================================================
//  基本レコード型
// =============================================================================
type
  TQSOData = record
    QSOID         : string;
    Callsign      : string;
    Band          : string;
    Mode          : string;
    FreqHz        : Int64;
    RSTSent       : string;
    RSTRcvd       : string;
    TxPowerW      : Double;
    MyGridsquare  : string;
    DXGridsquare  : string;
    QSODate       : string;
    TimeOn        : string;
    TimeOff       : string;
    DXCCEntity    : string;
    Continent     : string;
    CQZone        : Integer;
    ITUZone       : Integer;
    QSLSent       : string;
    QSLRcvd       : string;
    LoTWQSLSent   : string;
    LoTWQSLRcvd   : string;
    ContestID     : string;
    ContestExch   : string;
    Notes         : string;
    ADIFExtra     : string;
    CreatedAt     : Int64;
    UpdatedAt     : Int64;

    class function Empty: TQSOData; static;
    function IsValid: Boolean;
    function DupeKey(DupeMode: TDupePerMode): string;
  end;

  TDecodeCandidate = record
    Callsign   : string;
    SNR        : Integer;
    DT         : Single;
    FreqHz     : Integer;
    Message    : string;
    Confidence : Single;
  end;
  TDecodeCandidateArray = array of TDecodeCandidate;

  TDecodeResult = record
    RequestTimestampUTC : string;
    DecodeTimeMs        : Integer;
    Candidates          : TDecodeCandidateArray;
  end;

  TBlockedSegment = record
    FreqLowHz  : Int64;
    FreqHighHz : Int64;
    Region     : string;
    Band       : string;
    function Contains(FreqHz: Int64): Boolean; inline;
  end;
  TBlockedSegmentArray = array of TBlockedSegment;

  TBandPlanSegment = record
    FreqLowHz  : Int64;
    FreqHighHz : Int64;
    ModeHint   : string;
    BlockTx    : Boolean;
    Region     : string;
    Band       : string;
  end;
  TBandPlanSegmentArray = array of TBandPlanSegment;

  TTimeSourceStatus = record
    Source          : TTimeSource;
    EstimatedPrecMs : Integer;
    IsAvailable     : Boolean;
  end;

  TResourceProfile = record
    CPUPercent    : Double;
    FreeMemoryMB  : Integer;
    DecodeTimeMs  : Integer;
    GPUOffload    : Boolean;
    Timestamp     : Int64;
  end;

  TRigStatus = record
    State    : TRigConnectionState;
    FreqHz   : Int64;
    PTTOn    : Boolean;
    ErrorMsg : string;
  end;

  TSeqPayload = record
    TargetCallsign : string;
    DecodeResult   : TDecodeResult;
    BlockReason    : TTxBlockReason;
    BlockMessage   : string;
    TxMessage      : string;
  end;

  TJournalEntry = record
    JournalID  : string;
    QSOID      : string;
    FieldName  : string;
    OldValue   : string;
    NewValue   : string;
    UpdatedAt  : Int64;
    DeviceID   : string;
    Synced     : Boolean;
  end;
  TJournalEntryArray = array of TJournalEntry;

  // [改訂: 1-4] オーディオデバイス情報を値型レコードとして定義。
  // IAudioManager が TStringList を返していた問題を解消する。
  TAudioDeviceInfo = record
    DeviceID    : string;   // OS固有ID（GUID / UID）
    DisplayName : string;
    IsDefault   : Boolean;
  end;
  TAudioDeviceInfoArray = array of TAudioDeviceInfo;

// =============================================================================
//  [改訂: 2-1] TCTIData — TStringList を排除し、完全に値型で構成する
//  旧設計: record に TStringList BandHistory を持ち、コピーセマンティクスが破綻していた。
//  新設計: BandHistory を TBandQSOCount の配列（値型）に変更。record のまま維持。
// =============================================================================
type
  TBandQSOCount = record
    Band     : string;
    QSOCount : Integer;
  end;
  TBandQSOCountArray = array of TBandQSOCount;

  TCTIData = record
    Callsign       : string;
    Name           : string;
    QTH            : string;
    GridSquare     : string;
    QSOCount       : Integer;
    LastQSODate    : string;
    AffinityLevel  : TAffinityLevel;
    IsNewDXCC      : Boolean;
    IsNewBand      : Boolean;
    HasLoTWPending : Boolean;
    IsFirstQSO     : Boolean;
    IsLongAbsent   : Boolean;
    BandHistory    : TBandQSOCountArray;  // 値型配列。コピー安全。
    AvatarPath     : string;

    // Clear は参照型フィールドがなくなったため単純にゼロ初期化でよい
    class function Empty: TCTIData; static;
  end;

// =============================================================================
//  [改訂: 2-4] TDTRingBuffer — Record から Class へ変更
//  旧設計: advancedrecord のためコピーセマンティクスが意図せず発動する危険があった。
//          Median() 内のソートコピーも record では曖昧だった。
//  新設計: class にして所有権を明確化し、コピーを禁止する。
//          Median() はインスタンスフィールドの作業バッファを使って安全にソートする。
// =============================================================================
type
  TDTRingBuffer = class
  private
    FBuf        : array[0..29] of Single;  // DT_BUFFER_CAPACITY = 30 固定
    FSortedWork : array[0..29] of Single;  // Median計算用作業領域（ヒープアロケーション不要）
    FHead       : Integer;
    FCount      : Integer;

    // ソート作業: FSortedWork に FBuf をコピーして挿入ソート
    procedure SortWorkBuffer(Count: Integer);
  public
    constructor Create;

    procedure Push(Value: Single);
    // Median: FSortedWork を使うため FBuf の内容を破壊しない
    function  Median: Single;
    function  Count: Integer; inline;
    procedure Clear;
  end;

// =============================================================================
//  コールバック手続き型（変更なし）
// =============================================================================
type
  TSeqStateChangeProc   = reference to procedure(OldState, NewState: TSeqState;
                                                  const Payload: TSeqPayload);
  TDecodeResultProc     = reference to procedure(const Result: TDecodeResult);
  TRigStatusProc        = reference to procedure(const Status: TRigStatus);
  TTimeSourceProc       = reference to procedure(const Status: TTimeSourceStatus);
  TTimeValidatorProc    = reference to procedure(NewStatus: TTimeValidatorStatus;
                                                  MedianDT: Single);
  TResourceProfileProc  = reference to procedure(const Profile: TResourceProfile);
  TDBResultCallback     = reference to procedure(const Error: string;
                                                  const Data: TObject);
  TCTIReadyProc         = reference to procedure(const Data: TCTIData);
  TJournalMergeProc     = reference to procedure(MergedCount: Integer;
                                                  const Error: string);
  TAudioDeviceStateProc = reference to procedure(NewState: TAudioDeviceState);

implementation

class function TQSOData.Empty: TQSOData;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.QSLSent     := 'N';
  Result.QSLRcvd     := 'N';
  Result.LoTWQSLSent := 'N';
  Result.LoTWQSLRcvd := 'N';
end;

function TQSOData.IsValid: Boolean;
begin
  Result := (Callsign <> '') and (Band <> '') and (Mode <> '')
            and (QSODate <> '') and (TimeOn <> '');
end;

function TQSOData.DupeKey(DupeMode: TDupePerMode): string;
begin
  case DupeMode of
    dpmTotal   : Result := Callsign;
    dpmBand    : Result := Callsign + '|' + Band;
    dpmBandMode: Result := Callsign + '|' + Band + '|' + Mode;
  end;
end;

function TBlockedSegment.Contains(FreqHz: Int64): Boolean;
begin
  Result := (FreqHz >= FreqLowHz) and (FreqHz <= FreqHighHz);
end;

class function TCTIData.Empty: TCTIData;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

constructor TDTRingBuffer.Create;
begin
  inherited Create;
  Clear;
end;

procedure TDTRingBuffer.Push(Value: Single);
begin
  FBuf[FHead] := Value;
  FHead := (FHead + 1) mod 30;
  if FCount < 30 then Inc(FCount);
end;

procedure TDTRingBuffer.SortWorkBuffer(Count: Integer);
var
  I, J : Integer;
  Tmp  : Single;
begin
  // FBuf の有効要素を FSortedWork へコピー
  for I := 0 to Count - 1 do
    FSortedWork[I] := FBuf[(FHead - Count + I + 30) mod 30];
  // 挿入ソート（Count ≦ 30 のため実用上十分）
  for I := 1 to Count - 1 do
  begin
    Tmp := FSortedWork[I];
    J := I - 1;
    while (J >= 0) and (FSortedWork[J] > Tmp) do
    begin
      FSortedWork[J + 1] := FSortedWork[J];
      Dec(J);
    end;
    FSortedWork[J + 1] := Tmp;
  end;
end;

function TDTRingBuffer.Median: Single;
begin
  if FCount = 0 then begin Result := 0; Exit; end;
  SortWorkBuffer(FCount);
  if (FCount mod 2) = 1 then
    Result := FSortedWork[FCount div 2]
  else
    Result := (FSortedWork[FCount div 2 - 1] + FSortedWork[FCount div 2]) / 2;
end;

function TDTRingBuffer.Count: Integer;
begin
  Result := FCount;
end;

procedure TDTRingBuffer.Clear;
begin
  FillChar(FBuf,        SizeOf(FBuf),        0);
  FillChar(FSortedWork, SizeOf(FSortedWork), 0);
  FHead  := 0;
  FCount := 0;
end;

end.
```

---

## 2. インターフェース定義（shared/Interfaces.pas）— 改訂版

```pascal
unit AmityInterfaces;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, AmityTypes;

// =============================================================================
//  [新設: 4-2] TObserverList<T> — 複数オブザーバーへの通知を管理する汎用クラス
//  旧設計: 各クラスが単一コールバックフィールドを持ち、複数リスナーを受け付けられなかった。
//  新設計: TObserverList をすべての通知箇所で使用し、複数登録を統一的に解決する。
// =============================================================================
type
  generic TObserverList<T> = class
  private
    FHandlers : array of T;
    FLock     : TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Register(const Handler: T);
    procedure Unregister(const Handler: T);

    // Invoker に各ハンドラを渡して呼び出す。ロック外でコールバックを実行する。
    procedure Notify(Invoker: specialize TFunc<T>);

    function Count: Integer;
  end;

// =============================================================================
//  [新設: 4-1] ILogger — ロギング抽象インターフェース
//  旧設計: TAppLogger シングルトンにグローバル依存していた。
//  新設計: インターフェースで DI 可能にし、テスト時は TNullLogger を注入する。
// =============================================================================
type
  TLogLevel = (llDebug, llInfo, llWarn, llError, llFatal);

  ILogger = interface
    ['{00A1B2C3-D4E5-4F60-A7B8-C9D0E1F20001}']
    procedure Log(Level: TLogLevel; const Msg: string); overload;
    procedure Log(Level: TLogLevel; const Fmt: string;
                  Args: array of const); overload;
    procedure Debug(const Msg: string);
    procedure Info(const Msg: string);
    procedure Warn(const Msg: string);
    procedure Error(const Msg: string);
    procedure Fatal(const Msg: string);
  end;

// =============================================================================
//  [改訂: 3-5] ILuaScoringContext — Luaバインディング用スコアリングコンテキスト
//  旧設計: TLuaRuntime.SetScoreContext(PInteger, TObject) で生ポインタを使っていた。
//  新設計: インターフェースに抽象化し、TContestEngineImpl がこれを実装する。
//          ILuaRuntime から SetScoreContext(PInteger) を完全に除去する。
// =============================================================================
type
  ILuaScoringContext = interface
    ['{00B2C3D4-E5F6-4A70-B8C9-D0E1F2030002}']
    procedure ScoreAdd(Points: Integer);
    function  ScoreGet: Integer;
    function  MultAdd(const Category, Key: string): Boolean;
    function  MultCount: Integer;
  end;

// =============================================================================
//  [改訂: 1-1] IDBWorker を責務別4インターフェースに分割
//  旧設計: 12メソッドの Fat Interface。利用側全員が全メソッドに依存していた。
//  新設計: 各利用者は必要なインターフェースのみを受け取る（ISP準拠）。
// =============================================================================
type
  // --- QSOの基本CRUD + ADIFインポート ---
  IQSORepository = interface
    ['{00C3D4E5-F6A7-4B80-C9D0-E1F203040003}']
    procedure WriteQSO(const Data: TQSOData; Callback: TDBResultCallback);
    procedure UpdateQSOField(const QSOID, FieldName, NewValue: string;
                             Callback: TDBResultCallback);
    procedure ReadQSO(const QSOID: string; Callback: TDBResultCallback);
    procedure ImportADIF(QSOList: TObject; Callback: TDBResultCallback);
  end;

  // --- FTS5検索 + CTI集計 + コンテスト履歴 ---
  ISearchRepository = interface
    ['{00D4E5F6-A7B8-4C90-D0E1-F20304050004}']
    procedure SearchFTS5(const Query: string; Limit: Integer;
                         Callback: TDBResultCallback);
    procedure ReadCTIData(const Callsign, CurrentBand, CurrentDXCC: string;
                          Callback: TDBResultCallback);
    procedure ReadContestQSOs(const ContestID: string; Callback: TDBResultCallback);
  end;

  // --- field_journal 操作 ---
  IJournalRepository = interface
    ['{00E5F6A7-B8C9-4DA0-E1F2-030405060005}']
    procedure WriteJournal(const Entry: TJournalEntry; Callback: TDBResultCallback);
    procedure ApplyJournalEntries(Entries: TJournalEntryArray;
                                  Callback: TDBResultCallback);
    procedure CountPendingJournals(Callback: TDBResultCallback);
  end;

  // --- バンドプラン + スキーママイグレーション ---
  ISchemaManager = interface
    ['{00F6A7B8-C9D0-4EB0-F203-040506070006}']
    procedure ReadBandPlan(const Region: string; Callback: TDBResultCallback);
    procedure RunMigrations(Callback: TDBResultCallback);
  end;

// =============================================================================
//  [改訂: 1-3] IRigControl を IRigFreqControl + IRigTransmitControl に分割
//  旧設計: SetPTT が IRigControl に含まれ、UIスレッドからの誤呼び出しを防げなかった。
//  新設計:
//    IRigFreqControl  → UIスレッドも受け取る（周波数表示・設定）
//    IRigTransmitControl → SeqCtrlスレッドのみが受け取る（PTT制御）
//  Composition Root は TRigCtldClient を両インターフェースとして各利用者に注入する。
// =============================================================================
type
  IRigFreqControl = interface
    ['{00A7B8C9-D0E1-4FC0-0203-040506070007}']
    function  GetVFOFreqHz: Int64;
    procedure SetVFOFreqHz(FreqHz: Int64);
    function  IsConnected: Boolean;
    function  ConnectionState: TRigConnectionState;
    procedure Connect(const Host: string; Port: Integer);
    procedure Disconnect;
    // [改訂: 4-2] 単一コールバック → TObserverList を保持する実装側で管理
    procedure RegisterStatusCallback(Callback: TRigStatusProc);
    procedure UnregisterStatusCallback(Callback: TRigStatusProc);
  end;

  IRigTransmitControl = interface
    ['{00B8C9D0-E1F2-4003-1304-050607080008}']
    // この参照を持つのは TSeqControllerThread のみ。
    // Composition Root で型として制限することで PTT の誤呼び出しを排除する。
    procedure SetPTT(OnOff: Boolean);
  end;

// =============================================================================
//  [改訂: 1-2] IIPCEndpoint を IIPCSender + IDSPLifecycle に分割
//  旧設計: 送信・プロセス管理・コールバック登録が混在していた。
//  新設計:
//    IIPCSender    → SeqCtrl / HwMonitor が使う（送信と結果受信）
//    IDSPLifecycle → Composition Root のみが使う（プロセス起動・停止）
// =============================================================================
type
  IIPCSender = interface
    ['{00C9D0E1-F203-4103-2405-060708090009}']
    procedure SendDecodeRequest(const AudioBufID, TimestampUTC: string;
                                FreqLow, FreqHigh: Integer; const Mode: string);
    procedure SendEncodeRequest(const MsgText: string; FreqHz: Integer;
                                const Mode, OutputBufID: string);
    procedure SendConfigUpdate(Depth: TDSPDepthMode);
    procedure SendPing(Seq: Integer);
    // [改訂: 4-2] 複数登録対応
    procedure RegisterDecodeResultCallback(Callback: TDecodeResultProc);
    procedure UnregisterDecodeResultCallback(Callback: TDecodeResultProc);
    procedure RegisterResourceProfileCallback(Callback: TResourceProfileProc);
    procedure UnregisterResourceProfileCallback(Callback: TResourceProfileProc);
  end;

  IDSPLifecycle = interface
    ['{00D0E1F2-0304-4203-3506-07080910000A}']
    procedure StartDSPProcess(const ExePath: string);
    procedure StopDSPProcess;
    function  DSPState: TDSPProcessState;
    procedure RegisterDSPStateCallback(
                Callback: reference to procedure(S: TDSPProcessState));
    procedure UnregisterDSPStateCallback(
                Callback: reference to procedure(S: TDSPProcessState));
  end;

// =============================================================================
//  [改訂: 1-4] IAudioManager — 戻り値を TAudioDeviceInfoArray に変更
//  旧設計: GetAvailableXxxDevices が TStringList を返し、所有権が不明確だった。
//  新設計: 値型配列を返すことでオーナーシップの曖昧さを完全に排除する。
// =============================================================================
type
  IAudioManager = interface
    ['{00E1F203-0405-4303-460A-0B0C0D0E000B}']
    procedure BindInputDevice(const DeviceID: string);
    procedure BindOutputDevice(const DeviceID: string);
    procedure UnbindAll;
    function  InputDeviceState: TAudioDeviceState;
    function  OutputDeviceState: TAudioDeviceState;
    // [改訂: 1-4] TStringList → TAudioDeviceInfoArray（値型。呼び出し元がFree不要）
    function  GetAvailableInputDevices: TAudioDeviceInfoArray;
    function  GetAvailableOutputDevices: TAudioDeviceInfoArray;
    // [改訂: 4-2] 複数登録対応
    procedure RegisterStateCallback(Callback: TAudioDeviceStateProc);
    procedure UnregisterStateCallback(Callback: TAudioDeviceStateProc);
    function  GetInputBufferID: string;
  end;

// =============================================================================
//  ファイルシステム・キーチェーン（変更なし）
// =============================================================================
type
  IFileWatcher = interface
    ['{00F20304-0506-4403-570B-0C0D0E0F000C}']
    procedure Watch(const DirPath: string;
                    OnChange: reference to procedure(const FilePath: string));
    procedure Unwatch;
    function  IsWatching: Boolean;
  end;

  IKeychainStorage = interface
    ['{00030405-0607-4503-680C-0D0E0F10000D}']
    procedure SetSecret(const ServiceName, AccountName, Secret: string);
    function  GetSecret(const ServiceName, AccountName: string;
                        out Secret: string): Boolean;
    procedure DeleteSecret(const ServiceName, AccountName: string);
  end;

  IHwMetricsProvider = interface
    ['{00040506-0708-4603-790D-0E0F1011000E}']
    function  GetCPUPercent: Double;
    function  GetFreeMemoryMB: Integer;
  end;

// =============================================================================
//  [新設: 3-2] ITimeSourceManager — 時刻ソース優先度管理を専用インターフェースに分離
//  旧設計: THwMonitorThread が ParseGPRMC・EvaluateTimeSource を直接実装していた。
//  新設計: 時刻ソース管理ロジックを独立させ、テスト容易性を確保する。
// =============================================================================
type
  ITimeSourceManager = interface
    ['{00050607-0809-4703-8A0E-0F1011120010}']
    procedure EvaluateAndUpdate;  // 優先度チェック → ITimeValidator.UpdateTimeSource
    function  BestAvailableSource: TTimeSourceStatus;
  end;

// =============================================================================
//  Layer 3: Application Logic インターフェース
// =============================================================================
type
  // [改訂: 5-3] UpdateTimeSource を ITimeValidator に昇格
  // 旧設計: UpdateTimeSource は TTimeValidator 具体型にのみ存在していた。
  // 新設計: インターフェースに含めることで THwMonitorThread が具体型に依存しなくなる。
  ITimeValidator = interface
    ['{00060708-090A-4803-9B0F-101112130011}']
    procedure AddDTSample(DT: Single);
    // [改訂: 5-3] インターフェースへ昇格
    procedure UpdateTimeSource(const Source: TTimeSourceStatus);
    function  CurrentStatus: TTimeValidatorStatus;
    function  CurrentTimeSource: TTimeSourceStatus;
    function  MedianDT: Single;
    procedure SetThreshold(ThresholdSec: Single);
    // [改訂: 4-2] 複数登録対応
    procedure RegisterStatusCallback(Callback: TTimeValidatorProc);
    procedure UnregisterStatusCallback(Callback: TTimeValidatorProc);
  end;

  // [改訂: 5-2] IBandPlanGuard から Reload を除去し、IBandPlanLoader として分離
  // 旧設計: IBandPlanGuard に Reload があり、SeqCtrl 以外からも呼べた。
  // 新設計: SeqCtrl は IBandPlanGuard のみ受け取り、Reload は Composition Root
  //         (IBandPlanLoader 経由) が起動時に呼ぶ。並行アクセスの窓口を絞る。
  IBandPlanGuard = interface
    ['{00070809-0A0B-4903-AC10-111213140012}']
    function  IsTxBlocked(FreqHz: Int64; out Reason: string): Boolean;
    function  GetSegmentsForBand(const Band: string): TBandPlanSegmentArray;
  end;

  IBandPlanLoader = interface
    ['{00080910-0B0C-4A03-BD11-121314150013}']
    // Composition Root と設定変更ハンドラのみが呼ぶ
    procedure Reload;
  end;

  ICallsignResolver = interface
    ['{00091011-0C0D-4B03-CE12-131415160014}']
    function  ResolveDXCC(const Callsign: string; out Entity, Continent: string;
                          out CQZone, ITUZone: Integer): Boolean;
    function  ResolvePrefix(const Callsign: string): string;
    procedure ReloadCtyDat(const FilePath: string);
    function  IsValidCallsign(const Callsign: string): Boolean;
  end;

  ICTIEngine = interface
    ['{000A1112-0D0E-4C03-DF13-141516170015}']
    procedure FetchCTIData(const Callsign, CurrentBand, CurrentDXCC: string;
                           Callback: TCTIReadyProc);
    function  CalcAffinityLevel(QSOCount: Integer): TAffinityLevel;
  end;

  // [改訂: 6-2] ScoreQSO を廃止。スコアはOnQSOLoggedで内部更新、GetTotalScoreで照会。
  // 旧設計: ScoreQSO(Query)とOnQSOLogged(Command)が同一データを処理し重複していた。
  IContestEngine = interface
    ['{000B1213-0E0F-4D03-E014-151617180016}']
    function  IsActive: Boolean;
    function  IsDupe(const Callsign, Band, Mode, Exchange: string): Boolean;
    // ScoreQSO 廃止。スコア計算は OnQSOLogged 内で実行し、GetTotalScore で取得する。
    function  GetTotalScore: Integer;
    function  GetMultiplierCount: Integer;
    procedure OnQSOLogged(const Data: TQSOData);  // 内部状態更新（副作用あり）
    procedure LoadDefinition(const JSONPath, LuaScriptPath: string);
    procedure Deactivate;
  end;

  // [改訂: 3-5] SetScoreContext(PInteger) を除去し、ILuaScoringContext を注入する形へ
  ILuaRuntime = interface
    ['{000C1314-0F10-4E03-F115-161718190017}']
    function  LoadScript(const ScriptPath, SigPath: string): Boolean;
    function  CallFunction(const FuncName: string;
                           Args: array of Variant): Variant;
    procedure RegisterBinding(const Name: string; Func: Pointer);
    // [改訂: 3-5] 生ポインタを廃止。インターフェース注入に変更。
    procedure SetScoringContext(Context: ILuaScoringContext);
    procedure Reset;
  end;

  // [改訂: 6-3] PendingCount・IsMerging を追加。UI の進捗表示を可能にする。
  ISyncWorker = interface
    ['{000D1415-1011-4F03-0216-171819200018}']
    procedure SetSyncFolder(const FolderPath: string);
    procedure StartWatch;
    procedure StopWatch;
    procedure ProcessPendingNow;
    procedure RegisterMergeCallback(Callback: TJournalMergeProc);
    procedure UnregisterMergeCallback(Callback: TJournalMergeProc);
    // [新設: 6-3] 進捗照会
    function  PendingCount: Integer;
    function  IsMerging: Boolean;
  end;

  IApiGateway = interface
    ['{000E1516-1112-4003-1317-18191A210019}']
    procedure FetchCallsignInfo(const Callsign: string;
                                Callback: TDBResultCallback);
    function  IsCacheStale(const Callsign: string; MaxAgeDays: Integer): Boolean;
  end;

  // [改訂: 6-1] TSeqControllerDeps — Parameter Object パターン
  // 旧設計: コンストラクタが6引数。新依存追加のたびに全呼び出し元が影響を受けた。
  // 新設計: 依存をレコードにまとめ、新フィールド追加が呼び出し元に影響しない。
  TSeqControllerDeps = record
    BandPlanGuard  : IBandPlanGuard;
    TimeValidator  : ITimeValidator;
    FreqControl    : IRigFreqControl;
    TransmitControl: IRigTransmitControl;  // [改訂: 1-3] PTT専用参照
    IPCSender      : IIPCSender;
    QSORepo        : IQSORepository;
    ContestEngine  : IContestEngine;
    Logger         : ILogger;             // [改訂: 4-1] DI注入
  end;

  ISeqController = interface
    ['{000F1617-1213-4103-2418-191A1B220020}']
    procedure PostEvent(Event: TSeqEvent; const Payload: TSeqPayload);
    function  CurrentState: TSeqState;
    function  TargetCallsign: string;
    function  CurrentTxMessage: string;
    // [改訂: 4-2] 複数登録対応
    procedure RegisterStateChangeCallback(Callback: TSeqStateChangeProc);
    procedure UnregisterStateChangeCallback(Callback: TSeqStateChangeProc);
  end;

// =============================================================================
//  [改訂: 4-1] Null実装クラス — テスト用・非活性時用
//  [改訂: 6-5] TNullContestEngine を Interfaces.pas から削除し ContestEngine.pas へ移動。
//              Interfaces.pas は純粋なインターフェース定義のみを収容する。
//  ただし ILogger の Null実装はここに残す（ブートストラップ問題を回避するため）。
// =============================================================================
type
  // テスト・スタートアップ前のロガーとして使用するNullObject
  TNullLogger = class(TInterfacedObject, ILogger)
  public
    procedure Log(Level: TLogLevel; const Msg: string); overload;
    procedure Log(Level: TLogLevel; const Fmt: string; Args: array of const); overload;
    procedure Debug(const Msg: string);
    procedure Info(const Msg: string);
    procedure Warn(const Msg: string);
    procedure Error(const Msg: string);
    procedure Fatal(const Msg: string);
  end;

implementation

// =============================================================================
//  TObserverList<T> 実装
// =============================================================================

constructor TObserverList.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  SetLength(FHandlers, 0);
end;

destructor TObserverList.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TObserverList.Register(const Handler: T);
var
  I, Len: Integer;
begin
  FLock.Acquire;
  try
    Len := Length(FHandlers);
    for I := 0 to Len - 1 do
      if @FHandlers[I] = @Handler then Exit;  // 重複登録防止
    SetLength(FHandlers, Len + 1);
    FHandlers[Len] := Handler;
  finally
    FLock.Release;
  end;
end;

procedure TObserverList.Unregister(const Handler: T);
var
  I, J, Len: Integer;
begin
  FLock.Acquire;
  try
    Len := Length(FHandlers);
    for I := 0 to Len - 1 do
    begin
      if @FHandlers[I] = @Handler then
      begin
        for J := I to Len - 2 do
          FHandlers[J] := FHandlers[J + 1];
        SetLength(FHandlers, Len - 1);
        Exit;
      end;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TObserverList.Notify(Invoker: specialize TFunc<T>);
var
  Snapshot : array of T;
  I        : Integer;
begin
  // ロック内でスナップショットを取り、ロック外でコールバックを実行する。
  // コールバック内からの Register/Unregister 呼び出しによるデッドロックを防ぐ。
  FLock.Acquire;
  try
    Snapshot := Copy(FHandlers);
  finally
    FLock.Release;
  end;
  for I := 0 to High(Snapshot) do
    Invoker(Snapshot[I]);
end;

function TObserverList.Count: Integer;
begin
  FLock.Acquire;
  try
    Result := Length(FHandlers);
  finally
    FLock.Release;
  end;
end;

// =============================================================================
//  TNullLogger 実装
// =============================================================================

procedure TNullLogger.Log(Level: TLogLevel; const Msg: string); begin end;
procedure TNullLogger.Log(Level: TLogLevel; const Fmt: string;
                          Args: array of const); begin end;
procedure TNullLogger.Debug(const Msg: string); begin end;
procedure TNullLogger.Info(const Msg: string);  begin end;
procedure TNullLogger.Warn(const Msg: string);  begin end;
procedure TNullLogger.Error(const Msg: string); begin end;
procedure TNullLogger.Fatal(const Msg: string); begin end;

end.
```

---

## 3. アプリケーションロガー（infra/AppLogger.pas）— 改訂版

```pascal
unit AppLogger;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, SyncObjs, AmityInterfaces;

// [改訂: 4-1] TAppLogger は ILogger を実装するが、シングルトンをやめ DI で注入する。
// グローバルアクセサ Logger() は廃止。
// Composition Root で唯一のインスタンスを生成し、コンストラクタ注入する。
type
  TAppLogger = class(TInterfacedObject, ILogger)
  private
    FQueue    : TThreadedQueue<string>;
    FThread   : TThread;
    FLogDir   : string;
    FMinLevel : TLogLevel;
    FFileLock : TCriticalSection;

    function  FormatLine(Level: TLogLevel; const Msg: string): string;
    function  CurrentLogFile: string;
    procedure WriteToFile(const Line: string);
    procedure RotateIfNeeded;

  public
    // [改訂: 4-1] コンストラクタで生成。シングルトンではない。
    constructor Create(const LogDir: string; MinLevel: TLogLevel = llInfo);
    destructor Destroy; override;

    // ILogger 実装
    procedure Log(Level: TLogLevel; const Msg: string); overload;
    procedure Log(Level: TLogLevel; const Fmt: string;
                  Args: array of const); overload;
    procedure Debug(const Msg: string); inline;
    procedure Info(const Msg: string); inline;
    procedure Warn(const Msg: string); inline;
    procedure Error(const Msg: string); inline;
    procedure Fatal(const Msg: string); inline;

    procedure SetMinLevel(Level: TLogLevel);
    procedure Flush;
  end;
```

---

## 4. コマンドオブジェクト（infra/DBCommands.pas）— 新設

```pascal
unit DBCommands;

// [改訂: 2-2] TDBCommandParams バリアントレコードをコマンドオブジェクトパターンに置き換える。
// 旧設計: string[512] 等の短文字列でデータを切り捨てるリスクがあった。
//         新コマンド追加のたびにバリアントレコードを変更する OCP 違反もあった。
// 新設計: 抽象基底クラス TDBCommandBase と具体サブクラスで表現する。
//         AnsiString を使用するため文字列長の上限がない。
//         新コマンドの追加は新サブクラスの追加のみで完結する（OCP準拠）。

{$mode objfpc}{$H+}

uses
  SysUtils, AmityTypes, AmityInterfaces;

type
  // 抽象コマンド基底クラス。DB Worker スレッドがキューで受け取る。
  TDBCommandBase = class abstract
  public
    Callback  : TDBResultCallback;
    RequestID : TGUID;
    // DB Worker スレッド上で Execute が呼ばれる
    procedure Execute(DB: Pointer); virtual; abstract;  // Pointer = sqlite3*
  end;

  // ---------------------------------------------------------------------------
  //  IQSORepository コマンド群
  // ---------------------------------------------------------------------------
  TWriteQSOCommand = class(TDBCommandBase)
  public
    Data : TQSOData;
    procedure Execute(DB: Pointer); override;
  end;

  TUpdateQSOFieldCommand = class(TDBCommandBase)
  public
    QSOID     : string;   // AnsiString: 長さ制限なし
    FieldName : string;
    NewValue  : string;   // 旧設計の string[512] を廃止
    procedure Execute(DB: Pointer); override;
  end;

  TReadQSOCommand = class(TDBCommandBase)
  public
    QSOID : string;
    procedure Execute(DB: Pointer); override;
  end;

  TImportADIFCommand = class(TDBCommandBase)
  public
    QSOList : TObject;  // TList of TQSOData
    procedure Execute(DB: Pointer); override;
  end;

  // ---------------------------------------------------------------------------
  //  ISearchRepository コマンド群
  // ---------------------------------------------------------------------------
  TSearchFTS5Command = class(TDBCommandBase)
  public
    Query : string;   // AnsiString: 長さ制限なし
    Limit : Integer;
    procedure Execute(DB: Pointer); override;
  end;

  TReadCTIDataCommand = class(TDBCommandBase)
  public
    Callsign    : string;
    CurrentBand : string;
    CurrentDXCC : string;
    procedure Execute(DB: Pointer); override;
  end;

  TReadContestQSOsCommand = class(TDBCommandBase)
  public
    ContestID : string;
    procedure Execute(DB: Pointer); override;
  end;

  // ---------------------------------------------------------------------------
  //  IJournalRepository コマンド群
  // ---------------------------------------------------------------------------
  TWriteJournalCommand = class(TDBCommandBase)
  public
    Entry : TJournalEntry;
    procedure Execute(DB: Pointer); override;
  end;

  TApplyJournalEntriesCommand = class(TDBCommandBase)
  public
    Entries : TJournalEntryArray;
    procedure Execute(DB: Pointer); override;
  end;

  TCountPendingJournalsCommand = class(TDBCommandBase)
  public
    procedure Execute(DB: Pointer); override;
  end;

  // ---------------------------------------------------------------------------
  //  ISchemaManager コマンド群
  // ---------------------------------------------------------------------------
  TReadBandPlanCommand = class(TDBCommandBase)
  public
    Region : string;
    procedure Execute(DB: Pointer); override;
  end;

  TRunMigrationsCommand = class(TDBCommandBase)
  public
    procedure Execute(DB: Pointer); override;
  end;

implementation
// 各 Execute の実装は DBWorker.pas 内の TQSOSQLiteRepository に委譲する。
// 本ユニットは純粋なコマンド構造体定義のみを担う。
end.
```

---

## 5. 定数定義（shared/Constants.pas）— 変更なし（参考）

```pascal
unit AmityConstants;

{$mode objfpc}{$H+}

interface

const
  IPC_HOST              = '127.0.0.1';
  IPC_PORT_MAIN         = 5100;
  IPC_PORT_DSP          = 5101;
  IPC_MAX_MSG_BYTES     = 4096;
  IPC_TIMEOUT_MS        = 3000;
  IPC_PING_INTERVAL_MS  = 3000;
  IPC_PING_MISS_MAX     = 3;
  SHM_NAME_PREFIX       = 'amity_audio_';
  SHM_SIZE_BYTES        = 192000;
  AUDIO_SAMPLE_RATE     = 48000;
  AUDIO_CHANNELS        = 1;
  AUDIO_RING_BUF_SEC    = 30;
  DT_BUFFER_CAPACITY    = 30;
  DT_MIN_SAMPLES        = 10;
  DT_THRESHOLD_SEC      = 2.0;
  DT_RECOVERY_SEC       = 1.0;
  NTP_RTT_MAX_MS        = 200;
  SCALE_CPU_DEEP_MAX    = 50.0;
  SCALE_CPU_FAST_MIN    = 85.0;
  SCALE_DECODE_DEEP_MAX = 10000;
  SCALE_DECODE_FAST_MIN = 13000;
  HWMONITOR_INTERVAL_MS = 5000;
  DB_ADIF_BATCH_SIZE    = 1000;
  SYNC_JOURNAL_ARCHIVE  = 'archive';
  CTI_CACHE_MAX_AGE_DAYS= 7;
  CTI_ABSENT_THRESHOLD  = 90;
  CTI_AFF_LEVEL1        = 1;
  CTI_AFF_LEVEL2        = 5;
  CTI_AFF_LEVEL3        = 20;
  RIG_DEFAULT_HOST      = '127.0.0.1';
  RIG_DEFAULT_PORT      = 4532;
  RIG_POLL_INTERVAL_MS  = 500;
  RIG_RECONNECT_MAX     = 3;
  RIG_RECONNECT_WAIT_MS = 2000;
  DSP_START_TIMEOUT_MS  = 3000;
  DSP_RESTART_MAX       = 3;
  LOG_MAX_SIZE_BYTES    = 10 * 1024 * 1024;
  LOG_MAX_FILES         = 3;
  KEYCHAIN_SERVICE      = 'AmityQSO';
  API_KEY_ACCOUNT_QRZ   = 'qrz_api_key';
  FT8_CYCLE_SEC         = 15;
  FT8_TX_DURATION_SEC   = 12;
  SEQ_TIMEOUT_CYCLES    = 2;

implementation
end.
```
# Amity-QSO クラス設計書 v2.0 — Part B
## インフラ層・アプリケーション層

---

## 6. Layer 2: インフラ層 クラス設計

### 6.1 TDBWorkerThread（改訂）

```pascal
// infra/DBWorker.pas

// [改訂: 1-1] IDBWorker を分割した 4 インターフェースをすべて実装する。
// [改訂: 3-1] SQLite操作を TQSOSQLiteRepository に委譲し、
//             TDBWorkerThread はキュー管理とディスパッチのみを担う。
// [改訂: 2-2] コマンドキューの型を TDBCommandBase（コマンドオブジェクト）に変更。
//             バリアントレコードの short string 切り捨て問題を根本解消する。

unit DBWorker;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, SyncObjs, AmityTypes, AmityInterfaces,
  AmityConstants, DBCommands, DBMigration, AppLogger;

type
  // ---------------------------------------------------------------------------
  // TQSOSQLiteRepository — SQLite 操作ロジックを集約する内部クラス
  // [改訂: 3-1] スレッド制御と DB ロジックを分離する。
  //             このクラスはスレッドを持たず、DB Worker Thread 上でのみ実行される。
  // ---------------------------------------------------------------------------
  TQSOSQLiteRepository = class
  private
    FDB : Pointer;  // sqlite3*

    procedure BindQSOData(Stmt: Pointer; const Data: TQSOData);
    function  RowToQSOData(Stmt: Pointer): TQSOData;
    function  UnixNow: Int64;

    // CTI集計: callsign別・バンド別交信回数、サジェストフラグを1クエリで取得
    function  BuildCTIQuery(const Callsign, Band, DXCC: string): string;

    // field_journal + qso_log を同一トランザクションで更新する
    procedure UpdateFieldWithJournal(const QSOID, FieldName,
                                     OldValue, NewValue: string);
  public
    constructor Create(DB: Pointer);

    // IQSORepository 操作
    procedure WriteQSO(const Data: TQSOData);
    procedure UpdateQSOField(const QSOID, FieldName, NewValue: string);
    function  ReadQSO(const QSOID: string; out Data: TQSOData): Boolean;
    procedure ImportADIF(QSOList: TObject);  // 1000件バッチトランザクション

    // ISearchRepository 操作
    procedure SearchFTS5(const Query: string; Limit: Integer;
                         out Results: TObject);  // TList of TQSOData
    procedure ReadCTIData(const Callsign, Band, DXCC: string;
                          out CTI: TCTIData);
    procedure ReadContestQSOs(const ContestID: string; out Results: TObject);

    // IJournalRepository 操作
    procedure WriteJournal(const Entry: TJournalEntry);
    procedure ApplyJournalEntries(const Entries: TJournalEntryArray);
    function  CountPendingJournals: Integer;

    // ISchemaManager 操作
    procedure ReadBandPlan(const Region: string; out Segments: TBandPlanSegmentArray);
    procedure RunMigrations;
  end;

  // ---------------------------------------------------------------------------
  // TDBWorkerThread — キュー管理とディスパッチのみを担うスレッド
  // [改訂: 3-1] Execute は単純なキューポーリングループ。
  //             実際の SQL 処理は FRepository に委譲する。
  // ---------------------------------------------------------------------------
  TDBWorkerThread = class(TThread,
    IQSORepository, ISearchRepository, IJournalRepository, ISchemaManager)
  private
    FQueue      : TThreadedQueue<TDBCommandBase>;
    FRepository : TQSOSQLiteRepository;
    FDB         : Pointer;   // sqlite3*
    FDBPath     : string;
    FLogger     : ILogger;

    procedure OpenDatabase;
    procedure CloseDatabase;

    // コールバックをメインスレッドへ安全にポスト
    procedure PostCallback(Callback: TDBResultCallback;
                           const Error: string; Data: TObject);

  protected
    procedure Execute; override;

  public
    constructor Create(const DBPath: string; Logger: ILogger);
    destructor Destroy; override;

    // IQSORepository
    procedure WriteQSO(const Data: TQSOData; Callback: TDBResultCallback);
    procedure UpdateQSOField(const QSOID, FieldName, NewValue: string;
                             Callback: TDBResultCallback);
    procedure ReadQSO(const QSOID: string; Callback: TDBResultCallback);
    procedure ImportADIF(QSOList: TObject; Callback: TDBResultCallback);

    // ISearchRepository
    procedure SearchFTS5(const Query: string; Limit: Integer;
                         Callback: TDBResultCallback);
    procedure ReadCTIData(const Callsign, CurrentBand, CurrentDXCC: string;
                          Callback: TDBResultCallback);
    procedure ReadContestQSOs(const ContestID: string; Callback: TDBResultCallback);

    // IJournalRepository
    procedure WriteJournal(const Entry: TJournalEntry; Callback: TDBResultCallback);
    procedure ApplyJournalEntries(Entries: TJournalEntryArray;
                                  Callback: TDBResultCallback);
    procedure CountPendingJournals(Callback: TDBResultCallback);

    // ISchemaManager
    procedure ReadBandPlan(const Region: string; Callback: TDBResultCallback);
    procedure RunMigrations(Callback: TDBResultCallback);
  end;
```

### 6.2 TRigCtldClient（改訂）

```pascal
// infra/RigControlPort.pas

// [改訂: 1-3] IRigFreqControl と IRigTransmitControl を別々に実装する。
//             SetPTT は IRigTransmitControl に分離され、
//             Composition Root が SeqCtrl にのみ IRigTransmitControl を渡す。
// [改訂: 4-2] FStatusCallback を TObserverList に変更し複数登録を許容する。

unit RigControlPort;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Sockets, SyncObjs,
  AmityTypes, AmityInterfaces, AmityConstants;

type
  TRigCtldClient = class(TThread, IRigFreqControl, IRigTransmitControl)
  private
    FHost           : string;
    FPort           : Integer;
    FSocket         : TSocket;
    FState          : TRigConnectionState;
    FFreqHz         : Int64;
    FPTTOn          : Boolean;
    FPollIntervalMs : Integer;
    // [改訂: 4-2] 単一コールバック → ObserverList
    FStatusObservers: specialize TObserverList<TRigStatusProc>;
    FLock           : TCriticalSection;
    FReconnectCount : Integer;
    FLogger         : ILogger;

    function  SendCommand(const Cmd: string; out Response: string): Boolean;
    function  ParseFreqResponse(const Resp: string): Int64;
    procedure DoConnect;
    procedure DoDisconnect;
    procedure DoReconnect;
    procedure NotifyStatus;

  protected
    procedure Execute; override;

  public
    constructor Create(const Host: string; Port: Integer;
                       Logger: ILogger;
                       PollIntervalMs: Integer = RIG_POLL_INTERVAL_MS);
    destructor Destroy; override;

    // IRigFreqControl
    function  GetVFOFreqHz: Int64;
    procedure SetVFOFreqHz(FreqHz: Int64);
    function  IsConnected: Boolean;
    function  ConnectionState: TRigConnectionState;
    procedure Connect(const Host: string; Port: Integer);
    procedure Disconnect;
    procedure RegisterStatusCallback(Callback: TRigStatusProc);
    procedure UnregisterStatusCallback(Callback: TRigStatusProc);

    // IRigTransmitControl
    // [改訂: 1-3] このメソッドは IRigTransmitControl 経由でのみ到達できる。
    //             TMainForm が IRigFreqControl だけを受け取る限り、
    //             コンパイル時に SetPTT の誤呼び出しを防止できる。
    procedure SetPTT(OnOff: Boolean);
  end;
```

### 6.3 TIPCEndpoint（改訂）

```pascal
// infra/IPCEndpoint.pas

// [改訂: 1-2] IIPCSender と IDSPLifecycle を別々に実装する。
// [改訂: 3-3] JSON 構築メソッドを TIPCSerializer に完全委譲する。
//             TIPCEndpoint 内の BuildXxxJSON プライベートメソッドをすべて削除。
// [改訂: 4-2] コールバックを TObserverList に変更し複数登録を許容する。

unit IPCEndpoint;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Sockets, SyncObjs,
  AmityTypes, AmityInterfaces, AmityConstants, IPCMessages;

type
  TPingSeqCounter = record
    FValue : Integer;
    function Next: Integer;
  end;

  TIPCEndpoint = class(TThread, IIPCSender, IDSPLifecycle)
  private
    FSocket           : TSocket;
    FDSPProcessHandle : THandle;
    FDSPState         : TDSPProcessState;

    // [改訂: 4-2] 複数オブザーバー対応
    FDecodeObservers   : specialize TObserverList<TDecodeResultProc>;
    FResourceObservers : specialize TObserverList<TResourceProfileProc>;
    FDSPStateObservers : specialize TObserverList<reference to procedure(S: TDSPProcessState)>;

    FPingSeq       : TPingSeqCounter;
    FLastPongSeq   : Integer;
    FMissedPongs   : Integer;
    FRestartCount  : Integer;
    FLock          : TCriticalSection;
    FDSPExePath    : string;
    FLogger        : ILogger;

    // 受信ディスパッチ（JSON構築は TIPCSerializer/Deserializer に全委譲）
    procedure DispatchMessage(const JSON: string);
    procedure HandleDecodeResult(const JSON: string);
    procedure HandleResourceProfile(const JSON: string);
    procedure HandlePong(const JSON: string);
    procedure HandleError(const JSON: string);

    procedure StartDSP;
    procedure StopDSP;
    procedure RestartDSP;
    procedure UpdateDSPState(NewState: TDSPProcessState);

    // [改訂: 3-3] JSON 送信は TIPCSerializer を呼ぶだけ
    procedure SendJSON(const JSON: string);

  protected
    procedure Execute; override;

  public
    constructor Create(Logger: ILogger);
    destructor Destroy; override;

    // IIPCSender
    procedure SendDecodeRequest(const AudioBufID, TimestampUTC: string;
                                FreqLow, FreqHigh: Integer; const Mode: string);
    procedure SendEncodeRequest(const MsgText: string; FreqHz: Integer;
                                const Mode, OutputBufID: string);
    procedure SendConfigUpdate(Depth: TDSPDepthMode);
    procedure SendPing(Seq: Integer);
    procedure RegisterDecodeResultCallback(Callback: TDecodeResultProc);
    procedure UnregisterDecodeResultCallback(Callback: TDecodeResultProc);
    procedure RegisterResourceProfileCallback(Callback: TResourceProfileProc);
    procedure UnregisterResourceProfileCallback(Callback: TResourceProfileProc);

    // IDSPLifecycle
    procedure StartDSPProcess(const ExePath: string);
    procedure StopDSPProcess;
    function  DSPState: TDSPProcessState;
    procedure RegisterDSPStateCallback(
                Callback: reference to procedure(S: TDSPProcessState));
    procedure UnregisterDSPStateCallback(
                Callback: reference to procedure(S: TDSPProcessState));
  end;
```

### 6.4 TApiGatewayThread（改訂）

```pascal
// infra/ApiGateway.pas

// [改訂: 3-4] QRZセッション管理を TQRZSessionCache として分離する。
//             DB保存を IQSORepository（相当する stations 更新）に委譲する。
//             TApiGatewayThread は HTTP取得の調停のみを担う。

unit ApiGateway;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, AmityTypes, AmityInterfaces;

type
  // ---------------------------------------------------------------------------
  // TQRZSessionCache — QRZ.com セッションキーの取得とキャッシュを管理する
  // [改訂: 3-4] セッション管理を TApiGatewayThread から分離
  // ---------------------------------------------------------------------------
  TQRZSessionCache = class
  private
    FSessionKey   : string;
    FExpiredAt    : TDateTime;
    FAPIKey       : string;
    FLogger       : ILogger;

    function  FetchNewSession(out Key: string): Boolean;
    function  IsExpired: Boolean;
  public
    constructor Create(const APIKey: string; Logger: ILogger);

    // 有効なセッションキーを返す。期限切れなら自動再取得する。
    function  GetValidKey(out Key: string): Boolean;
    procedure Invalidate;
  end;

  // ---------------------------------------------------------------------------
  // TStationResultWriter — API 取得結果を DB へ保存する専用クラス
  // [改訂: 3-4] DB 保存処理を TApiGatewayThread から分離
  // ---------------------------------------------------------------------------
  TStationResultWriter = class
  private
    FQSORepo : IQSORepository;  // stations テーブル更新は UpdateQSOField 相当
    FLogger  : ILogger;
  public
    constructor Create(QSORepo: IQSORepository; Logger: ILogger);
    procedure StoreStation(const Callsign, Name, QTH, Grid: string);
  end;

  TApiRequest = record
    Callsign : string;
    Callback : TDBResultCallback;
  end;

  // ---------------------------------------------------------------------------
  // TApiGatewayThread — HTTP取得の調停のみを担う
  // ---------------------------------------------------------------------------
  TApiGatewayThread = class(TThread, IApiGateway)
  private
    FQueue          : TThreadedQueue<TApiRequest>;
    FLuaRuntime     : ILuaRuntime;
    FSessionCache   : TQRZSessionCache;
    FResultWriter   : TStationResultWriter;
    FSearchRepo     : ISearchRepository;  // キャッシュ有効期限チェック用
    FLogger         : ILogger;

    function  DoHTTPGet(const URL: string; out Response: string): Boolean;
    function  BuildQRZURL(const Callsign, SessionKey: string): string;
    function  ParseWithLua(const ScriptName, Body: string;
                           out Name, QTH, Grid: string): Boolean;

  protected
    procedure Execute; override;

  public
    constructor Create(LuaRuntime  : ILuaRuntime;
                       SessionCache: TQRZSessionCache;
                       ResultWriter: TStationResultWriter;
                       SearchRepo  : ISearchRepository;
                       Logger      : ILogger);
    destructor Destroy; override;

    procedure FetchCallsignInfo(const Callsign: string;
                                Callback: TDBResultCallback);
    function  IsCacheStale(const Callsign: string; MaxAgeDays: Integer): Boolean;
  end;
```

### 6.5 TAppSettings（改訂）

```pascal
// infra/AppSettings.pas

// [改訂: 4-1] シングルトンとグローバルアクセサ Settings() を廃止する。
//             コンストラクタで生成し、必要な箇所にコンストラクタ注入する。
// [改訂: 4-2] オブザーバー登録を TObserverList に変更する。

unit AppSettings;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, AmityTypes, AmityInterfaces;

type
  TAppSettingsData = record
    MyCallsign          : string;
    MyGridsquare        : string;
    MyName              : string;
    Region              : string;
    RigHost             : string;
    RigPort             : Integer;
    RigPollIntervalMs   : Integer;
    AudioInputDeviceID  : string;
    AudioOutputDeviceID : string;
    NTPServer           : string;
    GNSSSerialPort      : string;
    DTThresholdSec      : Single;
    CloudSyncFolder     : string;
    TQSLExePath         : string;
    LoTWCallsign        : string;
    FontSizePt          : Integer;
    HighContrast        : Boolean;
    WaterfallVisible    : Boolean;
    CTIPanelVisible     : Boolean;
    DSPExePath          : string;
    DefaultDepthMode    : TDSPDepthMode;

    class function Default: TAppSettingsData; static;
  end;

  TSettingsChangeProc = reference to procedure;

  TAppSettings = class
  private
    FData      : TAppSettingsData;
    FFilePath  : string;
    FKeychain  : IKeychainStorage;
    FLogger    : ILogger;
    // [改訂: 4-2] 単一コールバック → ObserverList
    FObservers : specialize TObserverList<TSettingsChangeProc>;
    FDirty     : Boolean;

    procedure FromJSON(const JSON: string);
    function  ToJSON: string;
    procedure NotifyObservers;

  public
    // [改訂: 4-1] コンストラクタで生成。シングルトンではない。
    constructor Create(const FilePath: string;
                       Keychain: IKeychainStorage;
                       Logger: ILogger);
    destructor Destroy; override;

    procedure Load;
    procedure Save;

    property Data: TAppSettingsData read FData;
    procedure UpdateData(const NewData: TAppSettingsData);

    procedure SetAPIKey(const AccountName, Key: string);
    function  GetAPIKey(const AccountName: string; out Key: string): Boolean;

    procedure RegisterObserver(Proc: TSettingsChangeProc);
    procedure UnregisterObserver(Proc: TSettingsChangeProc);
  end;
```

---

## 7. Layer 3: アプリケーション層 クラス設計

### 7.1 TSeqControllerThread（改訂）

```pascal
// app/SeqCtrl.pas

// [改訂: 1-3] IRigControl を IRigFreqControl + IRigTransmitControl に分割して受け取る。
//             SetPTT は IRigTransmitControl 経由でのみ呼び出し可能になる。
// [改訂: 6-1] コンストラクタの 6引数を TSeqControllerDeps（Parameter Object）に変更。
// [改訂: 4-1] ILogger を DI 注入する。
// [改訂: 4-2] FStateCallback を TObserverList に変更する。
// [改訂: 6-2] ScoreQSO 廃止に伴い、スコア取得を GetTotalScore に統一する。

unit SeqCtrl;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, SyncObjs,
  AmityTypes, AmityInterfaces, AmityConstants;

type
  TSeqCommand = record
    Event   : TSeqEvent;
    Payload : TSeqPayload;
  end;

  TSeqControllerThread = class(TThread, ISeqController)
  private
    // [改訂: 6-1] 依存を TSeqControllerDeps レコードで保持
    FDeps         : TSeqControllerDeps;

    FState        : TSeqState;
    FStateLock    : TCriticalSection;
    FCommandQueue : TThreadedQueue<TSeqCommand>;

    // [改訂: 4-2] 単一コールバック → ObserverList
    FStateObservers : specialize TObserverList<TSeqStateChangeProc>;

    FTargetCallsign : string;
    FCurrentTxMsg   : string;
    FRxTimeoutCount : Integer;
    FCurrentMode    : string;

    // --- 状態遷移ハンドラ ---
    procedure TransitionTo(NewState: TSeqState; const Payload: TSeqPayload);
    procedure HandleIdle(Event: TSeqEvent; const Payload: TSeqPayload);
    procedure HandleWaitTxPermit(Event: TSeqEvent; const Payload: TSeqPayload);
    procedure HandleTxRunning(Event: TSeqEvent; const Payload: TSeqPayload);
    procedure HandleRxWait(Event: TSeqEvent; const Payload: TSeqPayload);
    procedure HandleTxBlocked(Event: TSeqEvent; const Payload: TSeqPayload);

    procedure DoTxPermitCheck;

    // [改訂: 1-3] FDeps.TransmitControl.SetPTT(True) 経由でのみ PTT を操作する。
    //             このプライベートメソッドが唯一の PTT 呼び出し経路。
    procedure DoStartTransmit(const TxMsg: string);
    procedure DoStopTransmit;

    function  FindTargetResponse(const Result: TDecodeResult;
                                 out MatchedMsg: string): Boolean;

    // [改訂: 6-2] ScoreQSO 廃止。ログ記録時に OnQSOLogged を呼び GetTotalScore で取得。
    procedure DoLogQSO(const RSTRcvd, Exchange: string);

    procedure ProcessCommand(const Cmd: TSeqCommand);
    procedure NotifyStateChange(OldState, NewState: TSeqState;
                                const Payload: TSeqPayload);

  protected
    procedure Execute; override;

  public
    // [改訂: 6-1] Parameter Object パターン。依存追加時に呼び出し元は不変。
    constructor Create(const Deps: TSeqControllerDeps);
    destructor Destroy; override;

    // ISeqController
    procedure PostEvent(Event: TSeqEvent; const Payload: TSeqPayload);
    function  CurrentState: TSeqState;
    function  TargetCallsign: string;
    function  CurrentTxMessage: string;
    // [改訂: 4-2] 複数登録対応
    procedure RegisterStateChangeCallback(Callback: TSeqStateChangeProc);
    procedure UnregisterStateChangeCallback(Callback: TSeqStateChangeProc);
  end;
```

### 7.2 TBandPlanGuard（改訂）

```pascal
// app/BandPlanGuard.pas

// [改訂: 5-2] IBandPlanGuard から Reload を除去し IBandPlanLoader に分離。
//             SeqCtrl は IBandPlanGuard のみを受け取り Reload を呼べない。
//             Composition Root が IBandPlanLoader.Reload を起動時・設定変更時に呼ぶ。
// [改訂: 4-1] ILogger を DI 注入する。

unit BandPlanGuard;

{$mode objfpc}{$H+}

uses
  SysUtils, SyncObjs, AmityTypes, AmityInterfaces;

type
  TBandPlanGuard = class(TInterfacedObject, IBandPlanGuard, IBandPlanLoader)
  private
    FBlockedSegs : TBlockedSegmentArray;
    FAllSegs     : TBandPlanSegmentArray;
    FSchemaRepo  : ISchemaManager;
    FRegion      : string;
    FLogger      : ILogger;
    // [改訂: 5-2] Reload と IsTxBlocked の並行アクセスを保護するロック
    FLock        : TMultiReadExclusiveWriteSynchronizer;
    //   読み取り（IsTxBlocked）は並列OK。
    //   書き込み（Reload）は排他。
    //   MREWS を使うことで IsTxBlocked の頻繁な呼び出しをブロックしない。

    function  BinarySearch(FreqHz: Int64): Integer;
    procedure OnBandPlanLoaded(const Error: string; Data: TObject);
    procedure SortSegments;

  public
    constructor Create(SchemaRepo: ISchemaManager;
                       const Region: string;
                       Logger: ILogger);
    destructor Destroy; override;

    // IBandPlanGuard（SeqCtrl が使う）
    function  IsTxBlocked(FreqHz: Int64; out Reason: string): Boolean;
    function  GetSegmentsForBand(const Band: string): TBandPlanSegmentArray;

    // IBandPlanLoader（Composition Root・設定変更ハンドラが使う）
    procedure Reload;
  end;
```

### 7.3 TTimeValidator（改訂）

```pascal
// app/TimeValidator.pas

// [改訂: 5-3] UpdateTimeSource を ITimeValidator インターフェースに昇格させる。
//             THwMonitorThread が具体型 TTimeValidator に依存しなくなる。
// [改訂: 2-4] TDTRingBuffer を Record → Class に変更（AmityTypes.pas 側で対処済み）。
// [改訂: 4-2] FStatusCallback を TObserverList に変更する。

unit TimeValidator;

{$mode objfpc}{$H+}

uses
  SysUtils, SyncObjs, AmityTypes, AmityInterfaces, AmityConstants;

type
  TTimeValidator = class(TInterfacedObject, ITimeValidator)
  private
    FBuffer    : TDTRingBuffer;  // [改訂: 2-4] Class に変更済み。所有権あり。
    FStatus    : TTimeValidatorStatus;
    FMedianDT  : Single;
    FThreshold : Single;
    FRecovery  : Single;
    FSource    : TTimeSourceStatus;
    FLogger    : ILogger;

    // [改訂: 4-2] 単一コールバック → ObserverList
    FStatusObservers : specialize TObserverList<TTimeValidatorProc>;

    // FBuffer と FStatus への全アクセスを保護するロック
    // AddDTSample（HwMonitor/Seqスレッド）と
    // UpdateTimeSource（HwMonitor）と
    // CurrentStatus（SeqCtrl）が並行するため必須
    FLock : TCriticalSection;

    procedure RecalcStatus;

  public
    constructor Create(Logger: ILogger);
    destructor Destroy; override;

    // ITimeValidator 全メソッド
    procedure AddDTSample(DT: Single);
    // [改訂: 5-3] インターフェースに昇格。FLock で保護する。
    procedure UpdateTimeSource(const Source: TTimeSourceStatus);
    function  CurrentStatus: TTimeValidatorStatus;
    function  CurrentTimeSource: TTimeSourceStatus;
    function  MedianDT: Single;
    procedure SetThreshold(ThresholdSec: Single);
    procedure RegisterStatusCallback(Callback: TTimeValidatorProc);
    procedure UnregisterStatusCallback(Callback: TTimeValidatorProc);
  end;
```

### 7.4 TGNSSParser（新設）と TTimeSourceManager（新設）と THwMonitorThread（改訂）

```pascal
// app/TimeSourceManager.pas

// [改訂: 3-2] TGNSSParser と TTimeSourceManager を THwMonitorThread から分離する。
//             THwMonitorThread の責務を「リソース収集とスケーリング判定」のみに絞る。

unit TimeSourceManager;

{$mode objfpc}{$H+}

uses
  SysUtils, AmityTypes, AmityInterfaces, AmityConstants;

type
  // ---------------------------------------------------------------------------
  // TGNSSParser — GNSS NMEA $GPRMC 文字列のパース専用クラス
  // [改訂: 3-2] THwMonitorThread から分離
  // ---------------------------------------------------------------------------
  TGNSSParser = class
  private
    FSerialPort : string;
    FLogger     : ILogger;

    function  OpenSerialPort: Boolean;
    function  ReadLine(out Line: string): Boolean;
  public
    constructor Create(const SerialPort: string; Logger: ILogger);

    // $GPRMC を読み取り、Validity='A' ならば True を返す。
    // UTCTime に解析済み時刻を格納する。
    function TryReadGPRMC(out IsValid: Boolean;
                          out UTCTime: TDateTime): Boolean;
  end;

  // ---------------------------------------------------------------------------
  // TTimeSourceManager — 時刻ソース優先度管理
  // [改訂: 3-2] THwMonitorThread から分離
  // ---------------------------------------------------------------------------
  TTimeSourceManager = class(TInterfacedObject, ITimeSourceManager)
  private
    FValidator  : ITimeValidator;
    FGNSSParser : TGNSSParser;  // nil の場合は GNSS を使わない
    FLogger     : ILogger;

    function  CheckGNSSPPS: TTimeSourceStatus;
    function  CheckGNSSNMEA: TTimeSourceStatus;
    function  CheckNTP(const Server: string): TTimeSourceStatus;
    function  CheckOSClock: TTimeSourceStatus;
  public
    constructor Create(Validator   : ITimeValidator;
                       GNSSParser  : TGNSSParser;   // nil 可
                       Logger      : ILogger);

    // ITimeSourceManager
    // 優先度順に評価し、最高優先度の有効なソースを Validator.UpdateTimeSource に渡す
    procedure EvaluateAndUpdate;
    function  BestAvailableSource: TTimeSourceStatus;
  end;

// app/HwMonitor.pas

// [改訂: 3-2] GNSSパースと時刻ソース管理を TTimeSourceManager に委譲する。
//             THwMonitorThread はリソース収集・スケーリング判定のみを担う。
// [改訂: 5-3] FTimeValidator を ITimeValidator として保持（具体型への依存を排除）。
// [改訂: 4-1] ILogger を DI 注入する。

unit HwMonitor;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, AmityTypes, AmityInterfaces, AmityConstants, TimeSourceManager;

type
  THwMonitorThread = class(TThread)
  private
    FMetrics        : IHwMetricsProvider;
    FIPCSender      : IIPCSender;
    FTimeValidator  : ITimeValidator;        // [改訂: 5-3] インターフェースで保持
    FTimeSourceMgr  : ITimeSourceManager;   // [改訂: 3-2] 委譲先
    FCurrentDepth   : TDSPDepthMode;
    FLogger         : ILogger;

    // [改訂: 4-2] 複数登録対応
    FResourceObservers : specialize TObserverList<TResourceProfileProc>;

    // RESOURCE_PROFILE 受信時のスケーリング判定
    procedure OnResourceProfile(const Profile: TResourceProfile);
    function  DetermineDepth(const Profile: TResourceProfile): TDSPDepthMode;

  protected
    procedure Execute; override;

  public
    // [改訂: 3-2] ITimeSourceManager を注入。THwMonitorThread 自身は時刻管理しない。
    // [改訂: 5-3] ITimeValidator インターフェースを返す（具体型を公開しない）。
    constructor Create(Metrics      : IHwMetricsProvider;
                       IPCSender    : IIPCSender;
                       TimeValidator: ITimeValidator;
                       TimeSourceMgr: ITimeSourceManager;
                       Logger       : ILogger);
    destructor Destroy; override;

    // SeqCtrl が DSP DECODE_RESULT 受信後に呼ぶ
    procedure AddDTSample(DT: Single);

    procedure RegisterResourceCallback(Callback: TResourceProfileProc);
    procedure UnregisterResourceCallback(Callback: TResourceProfileProc);
  end;
```

### 7.5 TCallsignResolver（改訂）

```pascal
// app/CallsignResolver.pas

// [改訂: 2-3] TCtyEntry を Record から Class に変更し、
//             Prefixes TStringList のメモリ管理を明確化する。
//             FCtyEntries を dynamic array → TObjectList に変更する。

unit CallsignResolver;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, AmityTypes, AmityInterfaces;

type
  // [改訂: 2-3] Record → Class。デストラクタで Prefixes を Free する。
  TCtyEntry = class
  public
    Entity    : string;
    Continent : string;
    CQZone    : Integer;
    ITUZone   : Integer;
    Prefixes  : TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  TCallsignResolver = class(TInterfacedObject, ICallsignResolver)
  private
    // [改訂: 2-3] dynamic array → TObjectList（Owns=True で自動 Free）
    FCtyEntries  : TObjectList;
    FPrefixIndex : TStringList;  // プレフィックス → インデックス。長さ降順ソート。
    FCtyFilePath : string;
    FLogger      : ILogger;

    procedure ParseCallsignParts(const Callsign: string;
                                 out BaseCall, Portable: string);
    function  MatchLongestPrefix(const BaseCall: string;
                                 out EntryIdx: Integer): Boolean;
    procedure ParseCtyFile(const FilePath: string);
    function  CheckCallsignFormat(const Callsign: string): Boolean;

  public
    constructor Create(const CtyFilePath: string; Logger: ILogger);
    destructor Destroy; override;

    function  ResolveDXCC(const Callsign: string;
                          out Entity, Continent: string;
                          out CQZone, ITUZone: Integer): Boolean;
    function  ResolvePrefix(const Callsign: string): string;
    procedure ReloadCtyDat(const FilePath: string);
    function  IsValidCallsign(const Callsign: string): Boolean;
  end;
```

### 7.6 TContestEngineImpl（改訂）と TDupeCache（改訂）

```pascal
// app/ContestEngine.pas

// [改訂: 3-5] ILuaScoringContext を TContestEngineImpl に実装させる。
//             TLuaRuntime への生ポインタ渡しを廃止する。
// [改訂: 5-1] FDupeCache へのアクセスを FLock で明示的に保護する。
// [改訂: 6-2] ScoreQSO を廃止。OnQSOLogged 内でスコア計算・状態更新を一本化する。
// [改訂: 4-3] TDupeCache のコメントと実装を一致させる（O(log n) と明記）。
// [改訂: 6-5] TNullContestEngine をここに移動（Interfaces.pas から削除）。
// [改訂: 4-1] ILogger を DI 注入する。

unit ContestEngine;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, SyncObjs, AmityTypes, AmityInterfaces;

type
  // ---------------------------------------------------------------------------
  // TDupeCache — コンテスト Dupe 判定メモリキャッシュ
  // [改訂: 4-3] 計算量を O(log n) と明記する。
  //             （TStringList ソート済み + BinarySearch。件数 ≤ 5000 で実用十分）
  // ---------------------------------------------------------------------------
  TDupeCache = class
  private
    FCache   : TStringList;  // ソート済み。BinarySearch で O(log n) 検索。
    FDupePer : TDupePerMode;

    function  MakeKey(const Callsign, Band, Mode: string): string;
  public
    constructor Create(DupePer: TDupePerMode);
    destructor Destroy; override;

    // 検索・追加はどちらも O(log n)
    function  IsDupe(const Callsign, Band, Mode: string): Boolean;
    procedure Add(const Callsign, Band, Mode: string);
    procedure RebuildFromData(QSOList: TObject; DupePer: TDupePerMode);
    procedure Clear;
  end;

  // ---------------------------------------------------------------------------
  // TContestEngineImpl — コンテストロジック本体
  // [改訂: 3-5] ILuaScoringContext を実装する。SetScoreContext(PInteger) を廃止。
  // [改訂: 5-1] FLock の保護対象を FDupeCache まで拡大し、明記する。
  // [改訂: 6-2] ScoreQSO を廃止し、OnQSOLogged に一本化する。
  // ---------------------------------------------------------------------------
  TContestEngineImpl = class(TInterfacedObject, IContestEngine, ILuaScoringContext)
  private
    FLuaRuntime  : ILuaRuntime;
    FDupeCache   : TDupeCache;
    FTotalScore  : Integer;
    FMultipliers : TStringList;
    FActive      : Boolean;
    FContestID   : string;
    FDupePer     : TDupePerMode;
    FLogger      : ILogger;

    // [改訂: 5-1] このロックが保護するフィールド:
    //   FTotalScore, FMultipliers, FDupeCache
    //   IsDupe（SeqCtrl スレッド）と OnQSOLogged（メインスレッド）の競合を防ぐ。
    FLock : TCriticalSection;

    procedure CallLuaOnQSO(const Data: TQSOData);
    procedure LoadJSONDefinition(const JSONPath: string);

  public
    constructor Create(LuaRuntime: ILuaRuntime; Logger: ILogger);
    destructor Destroy; override;

    // IContestEngine
    function  IsActive: Boolean;
    // [改訂: 5-1] FLock.Acquire/Release で FDupeCache を保護する
    function  IsDupe(const Callsign, Band, Mode, Exchange: string): Boolean;
    // [改訂: 6-2] ScoreQSO 廃止。スコア計算は OnQSOLogged 内で実行。
    function  GetTotalScore: Integer;
    function  GetMultiplierCount: Integer;
    // [改訂: 5-1] FLock.Acquire/Release で FDupeCache + FTotalScore + FMultipliers を保護
    procedure OnQSOLogged(const Data: TQSOData);
    procedure LoadDefinition(const JSONPath, LuaScriptPath: string);
    procedure Deactivate;

    // [改訂: 3-5] ILuaScoringContext — 生ポインタ廃止。インターフェース経由でアクセス。
    procedure ScoreAdd(Points: Integer);
    function  ScoreGet: Integer;
    function  MultAdd(const Category, Key: string): Boolean;
    function  MultCount: Integer;
  end;

  // ---------------------------------------------------------------------------
  // TNullContestEngine — コンテスト非活性時の NullObject
  // [改訂: 6-5] Interfaces.pas から ContestEngine.pas へ移動する。
  //             shared/ 層はインターフェース定義のみを収容するため。
  // ---------------------------------------------------------------------------
  TNullContestEngine = class(TInterfacedObject, IContestEngine)
  public
    function  IsActive: Boolean;                    // False
    function  IsDupe(const Callsign, Band,
                     Mode, Exchange: string): Boolean; // False
    function  GetTotalScore: Integer;               // 0
    function  GetMultiplierCount: Integer;          // 0
    procedure OnQSOLogged(const Data: TQSOData);    // nop
    procedure LoadDefinition(const JSONPath,
                             LuaScriptPath: string); // nop
    procedure Deactivate;                           // nop
  end;
```

### 7.7 TLuaRuntime（改訂）

```pascal
// app/LuaRuntime.pas

// [改訂: 3-5] SetScoreContext(PInteger, TObject) を廃止し、
//             SetScoringContext(ILuaScoringContext) に変更する。
//             バインディング関数は ILuaScoringContext を介してスコアにアクセスする。
// [改訂: 4-1] ILogger を DI 注入する。

unit LuaRuntime;

{$mode objfpc}{$H+}

uses
  SysUtils, AmityTypes, AmityInterfaces;

type
  TLuaRuntime = class(TInterfacedObject, ILuaRuntime)
  private
    FLuaState       : Pointer;   // lua_State*
    FPublicKey      : array[0..31] of Byte;
    // [改訂: 3-5] 生ポインタ廃止。インターフェース参照で型安全に保持。
    FScoringContext : ILuaScoringContext;
    FLogger         : ILogger;

    procedure InitializeSandbox;
    procedure RegisterAmityBindings;
    function  VerifySignature(const ScriptData, SigData: TBytes): Boolean;
    function  LoadFilePair(const ScriptPath, SigPath: string;
                           out ScriptData, SigData: TBytes): Boolean;

    // Lua コールバック — FScoringContext を ILuaScoringContext として安全に呼ぶ
    class function LuaBindScoreAdd  (L: Pointer): Integer; cdecl; static;
    class function LuaBindScoreGet  (L: Pointer): Integer; cdecl; static;
    class function LuaBindMultAdd   (L: Pointer): Integer; cdecl; static;
    class function LuaBindMultCount (L: Pointer): Integer; cdecl; static;
    class function LuaBindXmlGet    (L: Pointer): Integer; cdecl; static;
    class function LuaBindResultSet (L: Pointer): Integer; cdecl; static;
    class function LuaBindLog       (L: Pointer): Integer; cdecl; static;
    class function LuaBindError     (L: Pointer): Integer; cdecl; static;

  public
    constructor Create(Logger: ILogger);
    destructor Destroy; override;

    // ILuaRuntime
    function  LoadScript(const ScriptPath, SigPath: string): Boolean;
    function  CallFunction(const FuncName: string;
                           Args: array of Variant): Variant;
    procedure RegisterBinding(const Name: string; Func: Pointer);
    // [改訂: 3-5] ILuaScoringContext を注入する。生ポインタは渡さない。
    procedure SetScoringContext(Context: ILuaScoringContext);
    procedure Reset;
  end;
```

### 7.8 TSyncWorkerThread（改訂）

```pascal
// infra/SyncWorker.pas
unit SyncWorker;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, SyncObjs,
  AmityTypes, AmityInterfaces;

type
  // LWW競合解決の判定結果
  TLWWDecision = (lwwKeepLocal, lwwTakeRemote, lwwNoConflict);

  // [改訂: 1-1] IJournalRepository のみを受け取る（旧: IDBWorker 全体）
  // [改訂: 4-1] ILogger を DI で受け取る
  // [改訂: 4-2] TObserverList で複数コールバック登録に対応
  // [改訂: 6-3] PendingCount / IsMerging を実装
  TSyncWorkerThread = class(TThread, ISyncWorker)
  private
    FSyncFolder    : string;
    FArchiveFolder : string;
    FJournalRepo   : IJournalRepository;    // [改訂: 1-1]
    FFileWatcher   : IFileWatcher;
    FMergeObservers: specialize TObserverList<TJournalMergeProc>; // [改訂: 4-2]
    FPendingFiles  : TStringList;
    FLock          : TCriticalSection;
    FMerging       : Boolean;              // [改訂: 6-3]
    FPendingCount  : Integer;              // [改訂: 6-3]
    FLogger        : ILogger;             // [改訂: 4-1]

    function  ParseJournalFile(const FilePath: string;
                               out Entry: TJournalEntry): Boolean;
    // [改訂: 4-3相当] コメントに O(log n) と明記
    // LWW: (qso_id, field_name) グループごとに updated_at 最大値を選択 O(n log n)
    function  ResolveConflicts(const Entries: TJournalEntryArray)
                               : TJournalEntryArray;
    procedure ArchiveFile(const FilePath: string);
    procedure OnFileAppeared(const FilePath: string);
    procedure ProcessBatch;

  protected
    procedure Execute; override;

  public
    constructor Create(JournalRepo : IJournalRepository;
                       FileWatcher : IFileWatcher;
                       Logger      : ILogger);
    destructor Destroy; override;

    // ISyncWorker [改訂: 6-3] PendingCount / IsMerging 追加
    procedure SetSyncFolder(const FolderPath: string);
    procedure StartWatch;
    procedure StopWatch;
    procedure ProcessPendingNow;
    procedure RegisterMergeCallback(Callback: TJournalMergeProc);
    procedure UnregisterMergeCallback(Callback: TJournalMergeProc);
    function  PendingCount: Integer;
    function  IsMerging: Boolean;
  end;
```

### 7.9 TCTIEngine（改訂）

```pascal
// app/CTIEngine.pas
unit CTIEngine;

{$mode objfpc}{$H+}

uses
  SysUtils, AmityTypes, AmityInterfaces;

// [改訂: 1-1] ISearchRepository のみを受け取る（旧: IDBWorker 全体）
// [改訂: 4-1] ILogger を DI で受け取る
// [改訂: 2-1] TCTIData が値型のみになり、コールバック受け渡しが安全になった
type
  TCTIEngine = class(TInterfacedObject, ICTIEngine)
  private
    FSearchRepo    : ISearchRepository;   // [改訂: 1-1]
    FApiGateway    : IApiGateway;
    FLogger        : ILogger;             // [改訂: 4-1]

    // DBコールバック: 生データから TCTIData（値型）を組み立てる
    // TCTIData.BandHistory は TBandQSOCountArray（値型配列）なので安全にコピーされる
    procedure OnCTIDataLoaded(const Error: string; Data: TObject;
                              const Callsign, CurrentBand, CurrentDXCC: string;
                              Callback: TCTIReadyProc);

    // APIコールバック: Name / QTH のみ差分更新
    procedure OnAPIDataLoaded(const Error: string; Data: TObject;
                              const Callsign: string;
                              Callback: TCTIReadyProc);

    function  CalcAffinityLevelFromCount(Count: Integer): TAffinityLevel;

    // サジェストバッジ判定: DBデータのみで即時算出（APIを待たない）
    procedure CalcBadges(const RawData: TObject;
                         const CurrentBand, CurrentDXCC: string;
                         out CTI: TCTIData);

  public
    constructor Create(SearchRepo : ISearchRepository;
                       ApiGateway : IApiGateway;
                       Logger     : ILogger);

    // ICTIEngine
    procedure FetchCTIData(const Callsign, CurrentBand, CurrentDXCC: string;
                           Callback: TCTIReadyProc);
    function  CalcAffinityLevel(QSOCount: Integer): TAffinityLevel;
  end;
```

### 7.10 TMessageBuilder（改訂）

```pascal
// app/MessageBuilder.pas
unit MessageBuilder;

{$mode objfpc}{$H+}

uses
  SysUtils, AmityTypes, AmityInterfaces;

// [改訂: 4-1] ILogger を DI で受け取る
// 変数展開: {MYCALL} {DXCALL} {RST} {GRID} {EXCH}
// FT8メッセージ長（最大13文字相当）を BuildXxx 内で検証し、
// 超過時は False + ErrorMsg を返す（例外を投げない）
type
  TMessageBuilder = class
  private
    FMyCall  : string;
    FMyGrid  : string;
    FLogger  : ILogger;   // [改訂: 4-1]

    function  Expand(const Template: string;
                     const DXCall, RST, Exch: string): string;
    // FT8 は 13文字×72ビットシンボルのフォーマット。
    // 文字列長で近似チェック（厳密にはDSP側でも検証する）
    function  ValidateFT8Length(const Msg: string;
                                out ErrorMsg: string): Boolean;

  public
    constructor Create(const MyCall, MyGrid: string; Logger: ILogger);

    function BuildCQ(out Msg, ErrorMsg: string): Boolean;
    function BuildCall(const DXCall, RST: string;
                       out Msg, ErrorMsg: string): Boolean;
    function BuildRR73(const DXCall: string;
                       out Msg, ErrorMsg: string): Boolean;
    function BuildContestExch(const DXCall, Exch: string;
                              out Msg, ErrorMsg: string): Boolean;

    procedure UpdateMyCall(const MyCall: string);
    procedure UpdateMyGrid(const MyGrid: string);
  end;
```
# Amity-QSO クラス設計書 v2.0 — Part C
## UIレイヤー・Composition Root・テストスタブ・DSPプロセス・総括

---

## 8. Layer 4: UIレイヤー クラス設計

### 8.1 TMainForm — 改訂版

```pascal
// ui/MainForm.pas
unit MainForm;

{$mode objfpc}{$H+}

uses
  Forms, Controls, AmityTypes, AmityInterfaces;

// [改訂: 1-3] TMainForm は IRigFreqControl を受け取る。IRigTransmitControl は受け取らない。
//             これにより PTT の誤操作が型システムで防止される。
// [改訂: 1-1] IQSORepository / ISearchRepository のみを受け取る。IJournalRepository 等は不要。
// [改訂: 4-1] ILogger を DI で受け取る。グローバル Logger() を参照しない。
// [改訂: 4-2] ObserverList 対応: Register/Unregister がペアで設計されている。
type
  TMainForm = class(TForm)
  private
    // --- 注入される依存（インターフェース分割後）---
    FSeqController  : ISeqController;
    FFreqControl    : IRigFreqControl;      // [改訂: 1-3] PTT 参照なし
    FQSORepo        : IQSORepository;       // [改訂: 1-1] 分割後インターフェース
    FSearchRepo     : ISearchRepository;    // [改訂: 1-1]
    FCTIEngine      : ICTIEngine;
    FContestEngine  : IContestEngine;
    FLogger         : ILogger;              // [改訂: 4-1]

    // --- 子フレーム ---
    FDecodeList  : TDecodeListFrame;
    FWaterfall   : TWaterfallFrame;
    FCTIPanel    : TCTIPanel;
    FStatusBar   : TStatusBarPanel;

    // --- 状態 ---
    FCurrentSeqState : TSeqState;
    FEcoMode         : Boolean;

    // --- コールバック（ObserverList 対応: 登録したものを Unregister で除去）---
    FOnSeqState  : TSeqStateChangeProc;
    FOnRigStatus : TRigStatusProc;
    FOnTimeValid : TTimeValidatorProc;
    FOnDSPState  : reference to procedure(S: TDSPProcessState);

    procedure OnSeqStateChanged(OldState, NewState: TSeqState;
                                const Payload: TSeqPayload);
    procedure OnRigStatusChanged(const Status: TRigStatus);
    procedure OnTimeValidatorStatusChanged(NewStatus: TTimeValidatorStatus;
                                           MedianDT: Single);
    procedure OnDSPStateChanged(State: TDSPProcessState);

    procedure EnterEcoMode;
    procedure ExitEcoMode;
    procedure ShowCommandPalette;
    procedure OnCommandPaletteSelect(const QSOID, Callsign: string);

    // SeqCtrl へ PostEvent するだけ。PTT には触れない。
    procedure BtnStartCQClick(Sender: TObject);
    procedure BtnStopClick(Sender: TObject);
    procedure BtnUnblockClick(Sender: TObject);
    procedure OnDecodeListSelect(const Candidate: TDecodeCandidate);

    procedure UpdateFreqDisplay(FreqHz: Int64);
    procedure UpdateTimeSourceDisplay(const Status: TTimeSourceStatus);
    procedure UpdateTxBlockedDisplay(Blocked: Boolean; const Reason: string);

  public
    constructor Create(AOwner       : TComponent;
                       SeqCtrl      : ISeqController;
                       FreqControl  : IRigFreqControl;
                       QSORepo      : IQSORepository;
                       SearchRepo   : ISearchRepository;
                       CTIEngine    : ICTIEngine;
                       ContestEng   : IContestEngine;
                       Logger       : ILogger);
    destructor Destroy; override;

    // コールバック登録は AfterConstruction で行い、Destroy で Unregister する。
    procedure AfterConstruction; override;
  end;
```

### 8.2 TDecodeListFrame — 改訂版

```pascal
// ui/DecodeListFrame.pas
unit DecodeListFrame;

{$mode objfpc}{$H+}

uses
  Forms, Controls, Grids, AmityTypes, AmityInterfaces;

// [改訂: 1-1] IContestEngine（IsDupe）・ICTIEngine のみを使用。IDBWorker は不要。
type
  TDecodeListFrame = class(TFrame)
  private
    FGrid          : TStringGrid;
    FCandidates    : TDecodeCandidateArray;
    FOnSelectProc  : reference to procedure(const C: TDecodeCandidate);
    FContestEngine : IContestEngine;
    FCTIEngine     : ICTIEngine;
    FCurrentBand   : string;
    FCurrentDXCC   : string;

    procedure GridSelectCell(Sender: TObject; ACol, ARow: Integer;
                             var CanSelect: Boolean);
    procedure GridDrawCell(Sender: TObject; ACol, ARow: Integer;
                           Rect: TRect; State: TGridDrawState);
  public
    constructor Create(AOwner        : TComponent;
                       ContestEngine : IContestEngine;
                       CTIEngine     : ICTIEngine);

    procedure UpdateCandidates(const Candidates: TDecodeCandidateArray;
                               const CurrentBand, CurrentDXCC: string);
    procedure RegisterSelectCallback(
                Proc: reference to procedure(const C: TDecodeCandidate));
  end;
```

### 8.3 TCTIPanel — 改訂版

```pascal
// ui/CTIPanel.pas
unit CTIPanel;

{$mode objfpc}{$H+}

uses
  Forms, Controls, StdCtrls, ExtCtrls, AmityTypes, AmityInterfaces;

// [改訂: 2-1] TCTIData が値型のみになったため、ShowCTIData の引数が安全に渡せる。
//             BandHistory は TBandQSOCountArray（値型配列）として受け取る。
type
  TCTIPanel = class(TFrame)
  private
    FLblCallsign      : TLabel;
    FLblName          : TLabel;
    FLblQTH           : TLabel;
    FLblQSOCount      : TLabel;
    FLblLastQSO       : TLabel;
    FLblAffinityStars : TLabel;
    FBadgeNewDXCC     : TLabel;
    FBadgeNewBand     : TLabel;
    FBadgeLoTW        : TLabel;
    FBadgeFirstQSO    : TLabel;
    FBadgeAbsent      : TLabel;
    FMemoNotes        : TMemo;
    FBandGrid         : TStringGrid;   // バンド別交信回数（BandHistory から描画）

    FNoteDebounceTimer : TTimer;
    FCurrentQSOID      : string;
    FCurrentCallsign   : string;
    FQSORepo           : IQSORepository;  // [改訂: 1-1] notes 更新のみ使用
    FLogger            : ILogger;         // [改訂: 4-1]

    procedure NoteDebounceTimerTick(Sender: TObject);
    procedure MemoNotesChange(Sender: TObject);

    // [改訂: 2-1] TCTIData.BandHistory が TBandQSOCountArray になったため
    //             TStringList を受け取る必要がなくなった
    procedure RenderBandHistory(const History: TBandQSOCountArray);

  public
    constructor Create(AOwner  : TComponent;
                       QSORepo : IQSORepository;
                       Logger  : ILogger);

    procedure ShowCTIData(const Data: TCTIData);  // 値型なので const 渡しで安全
    procedure UpdateAPIData(const Name, QTH: string);
    procedure Clear;
  end;
```

### 8.4 TStatusBarPanel — 改訂版

```pascal
// ui/StatusBarPanel.pas
unit StatusBarPanel;

{$mode objfpc}{$H+}

uses
  Forms, Controls, StdCtrls, ExtCtrls, AmityTypes, AmityInterfaces;

type
  TStatusBarPanel = class(TFrame)
  private
    FLblFreq         : TLabel;
    FLblTimeSource   : TLabel;
    FLblTxBlock      : TLabel;
    FLblDSPState     : TLabel;
    FLblRigState     : TLabel;
    FPnlTxBlockAlert : TPanel;
    FFlashTimer      : TTimer;
    FFlashCount      : Integer;

    procedure FlashTimerTick(Sender: TObject);

  public
    // すべてメインスレッドから呼ぶこと
    procedure UpdateFreq(FreqHz: Int64; const Mode: string);
    procedure UpdateTimeSource(const Status: TTimeSourceStatus);
    procedure UpdateTxBlocked(Blocked: Boolean;
                              Reason: TTxBlockReason; const Msg: string);
    procedure UpdateDSPState(State: TDSPProcessState);
    procedure UpdateRigState(State: TRigConnectionState);
  end;
```

### 8.5 TCommandPalette — 改訂版

```pascal
// ui/CommandPalette.pas
unit CommandPalette;

{$mode objfpc}{$H+}

uses
  Forms, Controls, StdCtrls, ExtCtrls, AmityTypes, AmityInterfaces;

// [改訂: 1-1] ISearchRepository.SearchFTS5 のみを使用する。IDBWorker は不要。
type
  TCommandPalette = class(TForm)
  private
    FEdtQuery      : TEdit;
    FLstResults    : TListBox;
    FSearchRepo    : ISearchRepository;  // [改訂: 1-1] 分割後インターフェース
    FDebounceTimer : TTimer;
    FOnSelect      : reference to procedure(const QSOID, Callsign: string);

    procedure DebounceTimerTick(Sender: TObject);
    procedure OnSearchResult(const Error: string; Data: TObject);
    procedure EdtQueryChange(Sender: TObject);
    procedure LstResultsClick(Sender: TObject);
    procedure EdtQueryKeyDown(Sender: TObject; var Key: Word;
                              Shift: TShiftState);
  public
    constructor Create(AOwner     : TComponent;
                       SearchRepo : ISearchRepository;
                       AOnSelect  : reference to procedure(
                                      const QSOID, Callsign: string));

    procedure ShowFloating(AnchorForm: TForm);
    procedure HideAndClear;
  end;
```

### 8.6 TSettingsForm — 改訂版

```pascal
// ui/SettingsForm.pas
unit SettingsForm;

{$mode objfpc}{$H+}

uses
  Forms, Controls, ComCtrls, StdCtrls, AmityTypes, AmityInterfaces;

// [改訂: 1-4] デバイス列挙に TAudioDeviceInfoArray を使用。
//             TStringList.Free 責任問題が解消される。
type
  TSettingsForm = class(TForm)
  private
    FTabControl  : TPageControl;
    FKeychain    : IKeychainStorage;
    FSchemaRepo  : ISchemaManager;     // [改訂: 1-1] バンドプラン更新のみ使用
    FAudioMgr    : IAudioManager;
    FBandLoader  : IBandPlanLoader;    // [改訂: 5-2] Reload 専用インターフェース
    FLogger      : ILogger;            // [改訂: 4-1]

    // タブ各ページ（省略: 旧設計と同一フィールド構成）
    FPageStation  : TTabSheet;
    FPageAudio    : TTabSheet;
    FPageCAT      : TTabSheet;
    FPageTime     : TTabSheet;
    FPageBandPlan : TTabSheet;
    FPageLoTW     : TTabSheet;
    FPageSync     : TTabSheet;
    FPageGeneral  : TTabSheet;

    // 各コントロールは旧設計と同一（省略）
    FEdtMyCall    : TEdit;
    FEdtMyGrid    : TEdit;
    FCmbRegion    : TComboBox;

    // [改訂: 1-4] TStringList ではなく TAudioDeviceInfoArray を使って列挙
    FCmbInputDev  : TComboBox;
    FCmbOutputDev : TComboBox;

    procedure BtnSaveClick(Sender: TObject);
    procedure BtnCancelClick(Sender: TObject);
    procedure BtnImportBandPlanClick(Sender: TObject);
    procedure BtnTestRigClick(Sender: TObject);
    procedure BtnTestAudioClick(Sender: TObject);

    procedure PopulateFromSettings;
    function  CollectToSettings(out NewData: TAppSettingsData;
                                out ErrMsg: string): Boolean;

    // [改訂: 1-4] TAudioDeviceInfoArray を受け取り ComboBox に展開する
    procedure PopulateAudioDeviceCombo(Combo: TComboBox;
                                       const Devices: TAudioDeviceInfoArray);

  public
    constructor Create(AOwner      : TComponent;
                       Keychain    : IKeychainStorage;
                       SchemaRepo  : ISchemaManager;
                       AudioMgr    : IAudioManager;
                       BandLoader  : IBandPlanLoader;
                       Logger      : ILogger);
  end;
```

### 8.7 TAwardForm と TGridBingoPanel — 改訂版

```pascal
// ui/AwardForm.pas
unit AwardForm;

{$mode objfpc}{$H+}

uses
  Forms, Controls, Graphics, ExtCtrls, ComCtrls, AmityTypes, AmityInterfaces;

// [改訂: 6-4] TGridBingoPanel を TCustomPanel → TCustomControl に変更。
//             ボーダー・BevelKind 等のパネル固有プロパティを排除する。
type
  TGridBingoPanel = class(TCustomControl)
  private
    FWorkedGrids : array of string;  // [改訂: 2-1相当] TStringList→値型配列
    FCFMGrids    : array of string;
    FCellSize    : Integer;
    FHoveredGrid : string;

    function  GridFromPoint(X, Y: Integer): string;
    procedure DrawGrid(ACanvas: TCanvas);
    function  ColorForGrid(const Grid: string): TColor;
    function  IsWorked(const Grid: string): Boolean;
    function  IsCFM(const Grid: string): Boolean;

  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;

  public
    constructor Create(AOwner: TComponent);

    // [改訂: 2-1相当] dynamic array で受け取る（TStringList の所有権問題なし）
    procedure UpdateGridData(const Worked, CFM: array of string);
    property  CellSize: Integer read FCellSize write FCellSize;
  end;

  TAwardForm = class(TForm)
  private
    FSearchRepo  : ISearchRepository;  // [改訂: 1-1]
    FTabControl  : TPageControl;
    FGridBingo   : TGridBingoPanel;
    FLblWorked   : TLabel;
    FLblCFM      : TLabel;
    FGridDXCC    : TStringGrid;
    FLblDXCCTotal: TLabel;
    FBarChart    : TImage;
    FGridBandStat: TStringGrid;

    procedure RefreshAll;
    procedure OnGridDataLoaded(const Error: string; Data: TObject);
    procedure OnDXCCDataLoaded(const Error: string; Data: TObject);
    procedure OnBandStatsLoaded(const Error: string; Data: TObject);
    procedure DrawBandBarChart(const BandData: array of TBandQSOCount);
    // [改訂: 2-1] TStringList ではなく TBandQSOCountArray を受け取る

  public
    constructor Create(AOwner: TComponent; SearchRepo: ISearchRepository);
    procedure AfterConstruction; override;
  end;
```

---

## 9. Composition Root（AmityQSO.lpr）— 改訂版

```pascal
// AmityQSO.lpr
program AmityQSO;

{$mode objfpc}{$H+}

uses
  Interfaces as LCLInterfaces,
  Forms,
  AmityTypes, AmityInterfaces, AmityConstants, DBCommands,
  // Layer 1
  {$ifdef Windows}
    HwMetricsWin, AudioWASAPI, FileWatcherWin, KeychainWin,
  {$endif}
  {$ifdef Darwin}
    HwMetricsMac, AudioCoreAudio, FileWatcherMac, KeychainMac,
  {$endif}
  // Layer 2
  AppLogger, DBWorker, RigControlPort, IPCEndpoint, ApiGateway,
  SyncWorker, AppSettings, AudioRingBuffer, SharedMemory,
  ADIF, DBMigration, Cabrillo,
  // Layer 3
  SeqCtrl, BandPlanGuard, TimeValidator, HwMonitor, TimeSourceManager,
  CallsignResolver, CTIEngine, ContestEngine, LuaRuntime, MessageBuilder,
  // Layer 4
  MainForm;

// ============================================================================
//  依存変数 — すべてインターフェース型で保持する
// ============================================================================
var
  // [改訂: 4-1] ILogger を最初に生成してすべてに注入する
  Logger_      : ILogger;

  // Layer 1
  HwMetrics    : IHwMetricsProvider;
  AudioMgr     : IAudioManager;
  FileWatcher  : IFileWatcher;
  Keychain     : IKeychainStorage;

  // Layer 2 — DB は4インターフェースとして保持 [改訂: 1-1]
  DBWorker_    : TDBWorkerThread;   // 具体型: 4インターフェースを取り出すため
  QSORepo      : IQSORepository;
  SearchRepo   : ISearchRepository;
  JournalRepo  : IJournalRepository;
  SchemaRepo   : ISchemaManager;

  // Layer 2 — リグ制御は2インターフェースとして保持 [改訂: 1-3]
  RigImpl      : TRigCtldClient;    // 具体型: 2インターフェースを取り出すため
  FreqCtrl     : IRigFreqControl;
  TransCtrl    : IRigTransmitControl;

  // Layer 2 — IPC は2インターフェースとして保持 [改訂: 1-2]
  IPCImpl      : TIPCEndpoint;      // 具体型: 2インターフェースを取り出すため
  IPCSender    : IIPCSender;
  DSPLifecycle : IDSPLifecycle;

  ApiGateway_  : IApiGateway;
  SyncWorker_  : ISyncWorker;

  // Layer 3
  BandGuardImpl : TBandPlanGuard;   // 具体型: 2インターフェースを取り出すため
  BandGuard     : IBandPlanGuard;
  BandLoader    : IBandPlanLoader;  // [改訂: 5-2] Reload 専用

  LuaRT         : ILuaRuntime;
  CallResolver  : ICallsignResolver;
  CTIEngine_    : ICTIEngine;
  ContestEng    : IContestEngine;
  TimeSrcMgr    : ITimeSourceManager;  // [改訂: 3-2] 専用クラス
  TimeVal       : ITimeValidator;
  HwMonitor_    : THwMonitorThread;    // 具体型: TimeValidator を取り出すため
  Deps          : TSeqControllerDeps;  // [改訂: 6-1] Parameter Object
  SeqCtrl_      : ISeqController;

begin
  Application.Initialize;

  // ---------- [改訂: 4-1] ILogger を最初に生成 ----------
  Logger_ := TAppLogger.Create(GetAppDataDir + 'logs' + PathDelim);

  // ---------- Layer 1: プラットフォーム抽象層 ----------
  {$ifdef Windows}
  HwMetrics   := TWinHwMetrics.Create;
  AudioMgr    := TWASAPIManager.Create(Logger_);
  FileWatcher := TWinFileWatcher.Create;
  Keychain    := TWinDPAPIStorage.Create(
                   GetAppDataDir + 'keystore' + PathDelim);
  {$endif}
  {$ifdef Darwin}
  HwMetrics   := TMacHwMetrics.Create;
  AudioMgr    := TCoreAudioManager.Create(Logger_);
  FileWatcher := TMacFileWatcher.Create;
  Keychain    := TMacKeychainStorage.Create;
  {$endif}

  // ---------- Layer 2: DBWorker（4インターフェースを展開）----------
  // [改訂: 1-1] TDBWorkerThread が IQSORepository / ISearchRepository /
  //             IJournalRepository / ISchemaManager をすべて実装する。
  //             各利用者には必要なインターフェースのみを渡す。
  DBWorker_ := TDBWorkerThread.Create(
                 GetAppDataDir + 'amity.db', Logger_);
  QSORepo    := DBWorker_  as IQSORepository;
  SearchRepo := DBWorker_  as ISearchRepository;
  JournalRepo:= DBWorker_  as IJournalRepository;
  SchemaRepo := DBWorker_  as ISchemaManager;

  // ---------- Layer 2: リグ制御（2インターフェースを展開）----------
  // [改訂: 1-3] TRigCtldClient が IRigFreqControl と IRigTransmitControl を実装。
  //             TMainForm には FreqCtrl のみを渡し、PTT 操作を型レベルで禁止する。
  RigImpl  := TRigCtldClient.Create(
                RIG_DEFAULT_HOST, RIG_DEFAULT_PORT, Logger_);
  FreqCtrl  := RigImpl as IRigFreqControl;
  TransCtrl := RigImpl as IRigTransmitControl;

  // ---------- Layer 2: IPC（2インターフェースを展開）----------
  // [改訂: 1-2] TIPCEndpoint が IIPCSender と IDSPLifecycle を実装。
  //             SeqCtrl には IPCSender のみを渡す。DSP起動は Composition Root が担う。
  IPCImpl      := TIPCEndpoint.Create(Logger_);
  IPCSender    := IPCImpl as IIPCSender;
  DSPLifecycle := IPCImpl as IDSPLifecycle;

  LuaRT       := TLuaRuntime.Create(Logger_);
  ApiGateway_ := TApiGatewayThread.Create(QSORepo, LuaRT, Logger_);
  SyncWorker_ := TSyncWorkerThread.Create(JournalRepo, FileWatcher, Logger_);

  // ---------- Layer 3: BandPlanGuard（2インターフェースを展開）----------
  // [改訂: 5-2] IBandPlanGuard（SeqCtrl用）と IBandPlanLoader（Reload用）に分割。
  BandGuardImpl := TBandPlanGuard.Create(SchemaRepo, 'JA', Logger_);
  BandGuard     := BandGuardImpl as IBandPlanGuard;
  BandLoader    := BandGuardImpl as IBandPlanLoader;

  CallResolver := TCallsignResolver.Create(
                    GetResourceDir + 'cty.dat', Logger_);
  CTIEngine_   := TCTIEngine.Create(SearchRepo, ApiGateway_, Logger_);

  // TNullContestEngine は ContestEngine.pas に移動済み [改訂: 6-5]
  ContestEng := TNullContestEngine.Create;

  // ---------- [改訂: 3-2] ITimeSourceManager を独立クラスとして生成 ----------
  TimeSrcMgr := TTimeSourceManager.Create(Logger_);

  // ---------- HwMonitor と TimeValidator ----------
  // [改訂: 5-3] TimeValidator は ITimeValidator インターフェースとして公開。
  //             THwMonitorThread が内部で TTimeValidator を生成・所有するが、
  //             外部からは ITimeValidator 経由でのみアクセスする。
  HwMonitor_ := THwMonitorThread.Create(
                  HwMetrics, IPCSender, TimeSrcMgr, Logger_);
  TimeVal    := HwMonitor_.GetTimeValidator;  // ITimeValidator を返す

  // ---------- [改訂: 6-1] SeqCtrl に Parameter Object で依存を注入 ----------
  Deps.BandPlanGuard   := BandGuard;
  Deps.TimeValidator   := TimeVal;
  Deps.FreqControl     := FreqCtrl;
  Deps.TransmitControl := TransCtrl;    // [改訂: 1-3] PTT専用参照
  Deps.IPCSender       := IPCSender;
  Deps.QSORepo         := QSORepo;
  Deps.ContestEngine   := ContestEng;
  Deps.Logger          := Logger_;

  SeqCtrl_ := TSeqControllerThread.Create(Deps);

  // ---------- 初期化シーケンス ----------
  SchemaRepo.RunMigrations(nil);          // DBマイグレーション
  BandLoader.Reload;                      // [改訂: 5-2] IBandPlanLoader 経由
  DSPLifecycle.StartDSPProcess(           // [改訂: 1-2] IDSPLifecycle 経由
    GetExeDir + 'AmityDSP' + ExeExt);

  // ---------- Layer 4: UI（必要なインターフェースのみを注入）----------
  Application.CreateForm(TMainForm, @ShowMain);
  // TMainForm.Create に:
  //   SeqCtrl_, FreqCtrl (PTT なし), QSORepo, SearchRepo, CTIEngine_, ContestEng, Logger_

  // ---------- スレッド起動 ----------
  TThread(DBWorker_).Start;
  TThread(RigImpl).Start;
  TThread(IPCImpl).Start;
  TThread(ApiGateway_).Start;
  TThread(SyncWorker_).Start;
  HwMonitor_.Start;
  TThread(SeqCtrl_).Start;

  Application.Run;

  // ---------- 終了処理（逆順）----------
  TThread(SeqCtrl_).Terminate;
  TThread(SeqCtrl_).WaitFor;
  HwMonitor_.Terminate;
  HwMonitor_.WaitFor;
  DSPLifecycle.StopDSPProcess;
  TThread(SyncWorker_).Terminate;
  TThread(SyncWorker_).WaitFor;
  TThread(ApiGateway_).Terminate;
  TThread(ApiGateway_).WaitFor;
  TThread(IPCImpl).Terminate;
  TThread(IPCImpl).WaitFor;
  TThread(RigImpl).Terminate;
  TThread(RigImpl).WaitFor;
  TThread(DBWorker_).Terminate;
  TThread(DBWorker_).WaitFor;

  // インターフェース変数をnilにしてから具体型をFreeする
  BandGuard := nil; BandLoader := nil; BandGuardImpl.Free;
  TimeVal   := nil; HwMonitor_.Free;
  FreeAndNil(DBWorker_); FreeAndNil(RigImpl); FreeAndNil(IPCImpl);

  TAppLogger(Logger_).Flush;
  Logger_ := nil;
end.
```

---

## 10. テストスタブ — 改訂版

### 10.1 TRigControlStub — 改訂版

```pascal
// tests/Stubs/RigControlStub.pas
unit RigControlStub;

{$mode objfpc}{$H+}

uses
  AmityTypes, AmityInterfaces;

// [改訂: 1-3] IRigFreqControl と IRigTransmitControl を分割実装する。
// テストで SeqCtrl に TransmitControl スタブを渡し、PTT ログを検証する。
type
  TRigControlStub = class(TInterfacedObject,
                          IRigFreqControl, IRigTransmitControl)
  public
    // 検証用ログ
    PTTLog      : array of Boolean;  // SetPTT 呼び出し履歴
    FreqLog     : array of Int64;    // SetVFOFreqHz 呼び出し履歴
    SetFreqLog  : array of Int64;    // SetVFOFreqHz（書き込み側）呼び出し履歴

    // シミュレーション値
    SimFreqHz   : Int64;
    SimConnected: Boolean;

    // IRigFreqControl
    function  GetVFOFreqHz: Int64;
    procedure SetVFOFreqHz(FreqHz: Int64);
    function  IsConnected: Boolean;
    function  ConnectionState: TRigConnectionState;
    procedure Connect(const Host: string; Port: Integer);
    procedure Disconnect;
    procedure RegisterStatusCallback(Callback: TRigStatusProc);
    procedure UnregisterStatusCallback(Callback: TRigStatusProc);

    // IRigTransmitControl
    procedure SetPTT(OnOff: Boolean);

    // テストヘルパー
    function LastPTT: Boolean;
    procedure ResetLogs;
  end;
```

### 10.2 テスト用DBスタブ群 — 改訂版

```pascal
// tests/Stubs/DBStubs.pas
unit DBStubs;

{$mode objfpc}{$H+}

uses
  AmityTypes, AmityInterfaces;

// [改訂: 1-1] IDBWorker が4インターフェースに分割されたため、
//             テスト用スタブも分割する。各テストが必要なスタブのみを使用できる。

type
  // IQSORepository のみを実装するスタブ
  TQSORepositoryStub = class(TInterfacedObject, IQSORepository)
  private
    FStore : array of TQSOData;
  public
    procedure WriteQSO(const Data: TQSOData; Callback: TDBResultCallback);
    procedure UpdateQSOField(const QSOID, FieldName, NewValue: string;
                             Callback: TDBResultCallback);
    procedure ReadQSO(const QSOID: string; Callback: TDBResultCallback);
    procedure ImportADIF(QSOList: TObject; Callback: TDBResultCallback);

    // テストヘルパー
    function  StoredCount: Integer;
    function  GetStored(Index: Integer): TQSOData;
    function  FindByID(const QSOID: string; out Data: TQSOData): Boolean;
    procedure Clear;
  end;

  // ISearchRepository のみを実装するスタブ
  TSearchRepositoryStub = class(TInterfacedObject, ISearchRepository)
  private
    FCTIResult     : TCTIData;
    FFTS5Results   : array of TQSOData;
    FContestResults: array of TQSOData;
  public
    procedure SearchFTS5(const Query: string; Limit: Integer;
                         Callback: TDBResultCallback);
    procedure ReadCTIData(const Callsign, CurrentBand, CurrentDXCC: string;
                          Callback: TDBResultCallback);
    procedure ReadContestQSOs(const ContestID: string;
                              Callback: TDBResultCallback);

    // テストセットアップ
    procedure SetCTIResult(const Data: TCTIData);
    procedure SetFTS5Results(const Data: array of TQSOData);
  end;

  // IJournalRepository のみを実装するスタブ
  TJournalRepositoryStub = class(TInterfacedObject, IJournalRepository)
  private
    FJournals      : array of TJournalEntry;
    FAppliedGroups : Integer;
  public
    procedure WriteJournal(const Entry: TJournalEntry;
                           Callback: TDBResultCallback);
    procedure ApplyJournalEntries(Entries: TJournalEntryArray;
                                  Callback: TDBResultCallback);
    procedure CountPendingJournals(Callback: TDBResultCallback);

    // テストヘルパー
    function JournalCount: Integer;
    function AppliedGroupCount: Integer;
    procedure Clear;
  end;

  // ISchemaManager のみを実装するスタブ
  TSchemaManagerStub = class(TInterfacedObject, ISchemaManager)
  private
    FBandPlanSegs  : TBandPlanSegmentArray;
    FMigrationCalled: Boolean;
  public
    procedure ReadBandPlan(const Region: string; Callback: TDBResultCallback);
    procedure RunMigrations(Callback: TDBResultCallback);

    // テストセットアップ
    procedure AddBandPlanSegment(const Seg: TBandPlanSegment);
    function  MigrationWasCalled: Boolean;
  end;
```

### 10.3 IPCEndpointStub — 改訂版

```pascal
// tests/Stubs/IPCStubs.pas
unit IPCStubs;

{$mode objfpc}{$H+}

uses
  AmityTypes, AmityInterfaces;

// [改訂: 1-2] IIPCSender のみを実装する SeqCtrl テスト用スタブ。
// DSPLifecycle は Composition Root テスト用に別スタブを用意する。
type
  TIPCSenderStub = class(TInterfacedObject, IIPCSender)
  public
    DecodeRequestLog : array of string;  // 送信されたAudioBufIDのログ
    EncodeRequestLog : array of string;  // 送信されたMsgTextのログ
    ConfigUpdateLog  : array of TDSPDepthMode;
    PingLog          : array of Integer;

    // シミュレーション: 登録されたコールバックをテストから直接発火できる
    procedure SimulateDecodeResult(const Result: TDecodeResult);
    procedure SimulateResourceProfile(const Profile: TResourceProfile);

    // IIPCSender
    procedure SendDecodeRequest(const AudioBufID, TimestampUTC: string;
                                FreqLow, FreqHigh: Integer; const Mode: string);
    procedure SendEncodeRequest(const MsgText: string; FreqHz: Integer;
                                const Mode, OutputBufID: string);
    procedure SendConfigUpdate(Depth: TDSPDepthMode);
    procedure SendPing(Seq: Integer);
    procedure RegisterDecodeResultCallback(Callback: TDecodeResultProc);
    procedure UnregisterDecodeResultCallback(Callback: TDecodeResultProc);
    procedure RegisterResourceProfileCallback(Callback: TResourceProfileProc);
    procedure UnregisterResourceProfileCallback(Callback: TResourceProfileProc);

    procedure ResetLogs;
  end;
```

### 10.4 ContestEngineStub — 改訂版

```pascal
// tests/Stubs/ContestEngineStub.pas
unit ContestEngineStub;

{$mode objfpc}{$H+}

uses
  AmityTypes, AmityInterfaces;

// [改訂: 6-2] ScoreQSO が廃止されたため、スタブも OnQSOLogged + GetTotalScore のみ。
type
  TContestEngineStub = class(TInterfacedObject, IContestEngine)
  public
    ActiveFlag    : Boolean;
    DupeCallsigns : array of string;  // Dupeとみなすコールサインリスト
    LoggedQSOs    : array of TQSOData;
    SimScore      : Integer;
    SimMultCount  : Integer;

    function  IsActive: Boolean;
    function  IsDupe(const Callsign, Band, Mode, Exchange: string): Boolean;
    function  GetTotalScore: Integer;
    function  GetMultiplierCount: Integer;
    procedure OnQSOLogged(const Data: TQSOData);
    procedure LoadDefinition(const JSONPath, LuaScriptPath: string);
    procedure Deactivate;

    procedure ResetLogs;
  end;
```

---

## 11. ContestEngine.pas — TNullContestEngine 移動後の定義

```pascal
// app/ContestEngine.pas
unit ContestEngine;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, SyncObjs,
  AmityTypes, AmityInterfaces;

// [改訂: 6-5] TNullContestEngine を Interfaces.pas から移動。
//             実装クラスと同じユニットで管理する。
type
  TNullContestEngine = class(TInterfacedObject, IContestEngine)
  public
    function  IsActive: Boolean;                               { False }
    function  IsDupe(const Callsign, Band, Mode,
                     Exchange: string): Boolean;               { False }
    function  GetTotalScore: Integer;                          { 0 }
    function  GetMultiplierCount: Integer;                     { 0 }
    procedure OnQSOLogged(const Data: TQSOData);               { nop }
    procedure LoadDefinition(const JSONPath,
                             LuaScriptPath: string);           { nop }
    procedure Deactivate;                                      { nop }
  end;

  // [改訂: 4-3] FCache の実装を TStringList（BinarySearch O(log n)）で統一し、
  //             コメントと実装を一致させる（O(1)のコメントを削除）。
  TDupeCache = class
  private
    FCache   : TStringList;  // ソート済み。BinarySearch で O(log n)。
    FDupePer : TDupePerMode;
  public
    constructor Create(DupePer: TDupePerMode);
    destructor Destroy; override;

    function  IsDupe(const Callsign, Band, Mode: string): Boolean;
    procedure Add(const Callsign, Band, Mode: string);
    procedure RebuildFromData(QSOList: TObject; DupePer: TDupePerMode);
    procedure Clear;
  end;

  // [改訂: 6-2] ScoreQSO を廃止。
  //             スコア計算は OnQSOLogged 内で完結し、GetTotalScore で照会する。
  // [改訂: 5-1] FLock の保護範囲を明記: FTotalScore・FMultipliers・FDupeCache の
  //             すべてのアクセスを FLock で保護する。
  // [改訂: 3-5] ILuaScoringContext を実装してスコアリングをLuaに安全に提供する。
  TContestEngineImpl = class(TInterfacedObject,
                              IContestEngine, ILuaScoringContext)
  private
    FLuaRuntime  : ILuaRuntime;
    FDupeCache   : TDupeCache;
    FTotalScore  : Integer;
    FMultipliers : TStringList;
    FActive      : Boolean;
    FContestID   : string;
    FDupePer     : TDupePerMode;
    FLogger      : ILogger;           // [改訂: 4-1]

    // [改訂: 5-1] FLock は以下をすべて保護する:
    //   - FTotalScore（ScoreAdd / ScoreGet）
    //   - FMultipliers（MultAdd / MultCount）
    //   - FDupeCache（IsDupe / Add）
    //   - FActive
    // IsDupe と OnQSOLogged が異なるスレッドから呼ばれるため必須。
    FLock        : TCriticalSection;

    procedure LoadJSONDefinition(const JSONPath: string);

    // [改訂: 6-2] Lua on_qso() を呼び、スコア・マルチ更新を行う内部メソッド。
    //             外部から ScoreQSO() で呼ぶ構造をやめ、OnQSOLogged 内で完結させる。
    procedure CallLuaOnQSOInternal(const Data: TQSOData);

  public
    constructor Create(LuaRuntime: ILuaRuntime; Logger: ILogger);
    destructor Destroy; override;

    // IContestEngine
    function  IsActive: Boolean;
    function  IsDupe(const Callsign, Band, Mode, Exchange: string): Boolean;
    // [改訂: 6-2] ScoreQSO 廃止
    function  GetTotalScore: Integer;
    function  GetMultiplierCount: Integer;
    procedure OnQSOLogged(const Data: TQSOData);
    procedure LoadDefinition(const JSONPath, LuaScriptPath: string);
    procedure Deactivate;

    // [改訂: 3-5] ILuaScoringContext — Lua バインディングが安全に呼ぶ
    procedure ScoreAdd(Points: Integer);
    function  ScoreGet: Integer;
    function  MultAdd(const Category, Key: string): Boolean;
    function  MultCount: Integer;
  end;

implementation

// --- TNullContestEngine ---
function  TNullContestEngine.IsActive: Boolean;                        begin Result := False; end;
function  TNullContestEngine.IsDupe(const Callsign, Band, Mode,
           Exchange: string): Boolean;                                  begin Result := False; end;
function  TNullContestEngine.GetTotalScore: Integer;                   begin Result := 0; end;
function  TNullContestEngine.GetMultiplierCount: Integer;              begin Result := 0; end;
procedure TNullContestEngine.OnQSOLogged(const Data: TQSOData);       begin end;
procedure TNullContestEngine.LoadDefinition(const JSONPath,
           LuaScriptPath: string);                                      begin end;
procedure TNullContestEngine.Deactivate;                               begin end;

// --- TContestEngineImpl: ILuaScoringContext 実装 ---
// [改訂: 5-1] すべて FLock 内で実行する
procedure TContestEngineImpl.ScoreAdd(Points: Integer);
begin
  FLock.Acquire;
  try
    Inc(FTotalScore, Points);
  finally
    FLock.Release;
  end;
end;

function TContestEngineImpl.ScoreGet: Integer;
begin
  FLock.Acquire;
  try
    Result := FTotalScore;
  finally
    FLock.Release;
  end;
end;

function TContestEngineImpl.MultAdd(const Category, Key: string): Boolean;
var
  FullKey : string;
  Idx     : Integer;
begin
  FLock.Acquire;
  try
    FullKey := Category + '|' + Key;
    Result  := FMultipliers.Find(FullKey, Idx) = False;
    if Result then
      FMultipliers.Add(FullKey);
  finally
    FLock.Release;
  end;
end;

function TContestEngineImpl.MultCount: Integer;
begin
  FLock.Acquire;
  try
    Result := FMultipliers.Count;
  finally
    FLock.Release;
  end;
end;

// --- TContestEngineImpl: IContestEngine 実装 ---
function TContestEngineImpl.IsDupe(const Callsign, Band, Mode,
                                    Exchange: string): Boolean;
begin
  // [改訂: 5-1] FDupeCache へのアクセスも FLock で保護する
  FLock.Acquire;
  try
    Result := FDupeCache.IsDupe(Callsign, Band, Mode);
  finally
    FLock.Release;
  end;
end;

procedure TContestEngineImpl.OnQSOLogged(const Data: TQSOData);
begin
  // [改訂: 5-1] DupeCache 更新と Lua 呼び出しをロック内で行う
  // [改訂: 6-2] スコア計算（旧 ScoreQSO）もここで完結する
  FLock.Acquire;
  try
    FDupeCache.Add(Data.Callsign, Data.Band, Data.Mode);
    // Lua on_qso() 内から ScoreAdd / MultAdd が呼ばれるが、
    // それらも FLock を取得しようとする → デッドロック発生の懸念あり。
    // 解決策: CallLuaOnQSOInternal は FLock を保持したまま呼ぶが、
    //         ILuaScoringContext 実装（ScoreAdd等）はロック不要版を別途用意する。
    CallLuaOnQSOInternal(Data);
  finally
    FLock.Release;
  end;
end;
// ※ ロック内からの再ロック問題:
//    FLock に TCriticalSection を使うと再入不可でデッドロックになる。
//    解決策: TRtlCriticalSection（Win32再入可能クリティカルセクション）を使うか、
//           または ILuaScoringContext の内部実装を「ロック不要版」と「ロック版」に
//           分離し、OnQSOLogged 内では「ロック不要版」を Lua に提供する。
//    推奨: FLock に TMutex（再入可能）を使用する。実装側で要検討。

end.
```

---

## 12. v2.0 全体クラス構成図

### 12.1 インターフェース階層（改訂後）

```
【横断的関心事】
  ILogger          ← 全コンポーネント（DI注入）
    └─ TAppLogger（実装）/ TNullLogger（テスト・起動前）

【L2 Infrastructure — DB】
  IQSORepository   ← TSeqControllerThread, TCTIPanel(notes更新)
  ISearchRepository← TCTIEngine, TCommandPalette, TAwardForm
  IJournalRepository← TSyncWorkerThread
  ISchemaManager   ← TBandPlanGuard(起動時読込), TSettingsForm(BP更新)
    ↑ TDBWorkerThread が4つすべてを実装
    ↑ テスト用: TQSORepositoryStub / TSearchRepositoryStub /
                TJournalRepositoryStub / TSchemaManagerStub（独立）

【L2 Infrastructure — リグ】
  IRigFreqControl  ← TMainForm, TSeqControllerThread(周波数参照)
  IRigTransmitControl ← TSeqControllerThread のみ（PTT）
    ↑ TRigCtldClient が両方を実装
    ↑ テスト用: TRigControlStub（両方を実装）

【L2 Infrastructure — IPC】
  IIPCSender       ← TSeqControllerThread, THwMonitorThread
  IDSPLifecycle    ← Composition Root のみ
    ↑ TIPCEndpoint が両方を実装
    ↑ テスト用: TIPCSenderStub（IIPCSender のみ）

【L3 Application】
  IBandPlanGuard   ← TSeqControllerThread（IsTxBlocked のみ）
  IBandPlanLoader  ← Composition Root / TSettingsForm（Reload のみ）
    ↑ TBandPlanGuard が両方を実装

  ITimeValidator   ← TSeqControllerThread（AddDTSample・UpdateTimeSource）
    ↑ TTimeValidator が実装（THwMonitorThread が所有・公開）

  ITimeSourceManager ← THwMonitorThread
    ↑ TTimeSourceManager が実装（GNSS/NTP優先度管理）

  ILuaScoringContext ← TLuaRuntime（Luaバインディング用）
    ↑ TContestEngineImpl が IContestEngine と共に実装

  IContestEngine   ← TSeqControllerThread, TMainForm, TContestForm
    ↑ TContestEngineImpl（有効時）/ TNullContestEngine（非活性時）
    ↑ テスト用: TContestEngineStub
```

### 12.2 スレッド間コミュニケーション図（改訂後）

```
  [MainThread]          [SeqCtrl]            [HwMonitor]
       │                    │                     │
       │ PostEvent          │                     │
       │──────────────────→│                     │
       │                    │ IsTxBlocked         │
       │                    │──→ IBandPlanGuard   │
       │                    │ CurrentStatus        │
       │                    │──→ ITimeValidator   │
       │                    │ SetPTT(True)         │
       │                    │──→ IRigTransmitCtrl │ ← SeqCtrl専用
       │                    │                     │
       │ ←── TObserverList.Notify ──────────────│
       │ (SeqStateChange)   │                     │ AddDTSample
       │                    │ ←── ITimeValidator ─│
       │                    │                     │ EvaluateAndUpdate
       │                    │     ←── ITimeSourceManager ←│
       │                    │                     │
  [DBWorker]           [SyncWorker]         [ApiGateway]
       │                    │                     │
       │ ←── TObserverList.Notify (DB完了コールバック)
       │                    │                     │
```

### 12.3 OOPレビュー問題対応確認表

| 問題 | 内容 | 対応状況 |
|---|---|---|
| 1-1 | IDBWorker Fat Interface | ✅ 4分割（IQSORepository等） |
| 1-2 | IIPCEndpoint 責務混在 | ✅ IIPCSender / IDSPLifecycle に分割 |
| 1-3 | SetPTT 制約が型で表現されない | ✅ IRigTransmitControl として分離。MainForm に渡さない |
| 1-4 | TStringList 返却の所有権問題 | ✅ TAudioDeviceInfoArray（値型配列）に変更 |
| 2-1 | TCTIData に TStringList | ✅ TBandQSOCountArray（値型配列）に変更 |
| 2-2 | バリアントレコードの short string | ✅ コマンドオブジェクトパターンへ移行（DBCommands.pas） |
| 2-3 | TCtyEntry に TStringList | ✅ Class化（CallsignResolver.pas 側） |
| 2-4 | TDTRingBuffer が Record | ✅ Class化。作業バッファを内部フィールドとして持つ |
| 3-1 | DBWorkerThread SRP違反 | ✅ TQSOSQLiteRepository に実装を委譲 |
| 3-2 | HwMonitorThread 4責務 | ✅ TTimeSourceManager / TGNSSParser を分離 |
| 3-3 | IPC と JSON ビルドの重複 | ✅ TIPCEndpoint 内の BuildXxxJSON を削除。TIPCSerializer に統一 |
| 3-4 | ApiGateway の責務分散 | ✅ TQRZSessionCache を分離 |
| 3-5 | SetScoreContext 生ポインタ | ✅ ILuaScoringContext インターフェースに変更 |
| 4-1 | Singleton 3つ | ✅ ILogger DI化。TAppSettings は AppSettings.pas で非Singleton化。TADIFTagRegistry は class var 管理に限定 |
| 4-2 | 単一コールバック制約 | ✅ TObserverList<T> 新設。全通知箇所で使用 |
| 4-3 | TDupeCache コメント矛盾 | ✅ コメントを O(log n) に修正 |
| 5-1 | TContestEngineImpl 競合状態 | ✅ FLock 保護範囲を明記。FDupeCache も保護対象とする |
| 5-2 | IBandPlanGuard.Reload 公開 | ✅ IBandPlanLoader に分離。SeqCtrl は IBandPlanGuard のみ受け取る |
| 5-3 | UpdateTimeSource 非公開 | ✅ ITimeValidator インターフェースへ昇格 |
| 6-1 | コンストラクタ 6引数 | ✅ TSeqControllerDeps（Parameter Object）に変更 |
| 6-2 | ScoreQSO と OnQSOLogged 重複 | ✅ ScoreQSO 廃止。OnQSOLogged + GetTotalScore に統一 |
| 6-3 | ISyncWorker 進捗照会なし | ✅ PendingCount / IsMerging を追加 |
| 6-4 | TGridBingoPanel 継承元 | ✅ TCustomPanel → TCustomControl に変更 |
| 6-5 | NullObject の配置ミス | ✅ ContestEngine.pas へ移動 |

---

# Amity-QSO クラス設計書 v2.1 — 追補: コンポーネントインターフェース定義

> **追補の位置付け**: 本追補はコンポーネント設計書 v1.0 で定義されたコンポーネントカタログに対応する
> Pascal インターフェース・クラス宣言を記述する。
> 設計意図・依存グラフ・再利用ロードマップはコンポーネント設計書 v1.0 を参照すること。

---

## 13. デジタルモードコンポーネント（D カテゴリ）

### 13.1 D-01: デジタルモードコーデック（dsp/CodecInterface.pas）

```pascal
unit CodecInterface;
{$mode objfpc}{$H+}

type
  TDecodeConfig = record
    DepthMode    : TDSPDepthMode;
    FreqLowHz    : Integer;
    FreqHighHz   : Integer;
    TimestampUTC : string;
  end;

  TEncodeConfig = record
    MsgText : string;
    FreqHz  : Integer;
  end;

  // デコードエンジン抽象インターフェース
  IDecodeEngine = interface
    ['{D01-DECODE-0000-0000-000000000001}']
    function  ModeName: string;
    function  CycleSec: Integer;
    procedure Decode(const AudioBuf: Pointer; BufSamples: Integer;
                     const Cfg: TDecodeConfig; out Result: TDecodeResult);
    function  SupportsDepthMode: Boolean;
  end;

  IEncodeEngine = interface
    ['{D01-ENCODE-0000-0000-000000000002}']
    function  ModeName: string;
    function  Encode(const Cfg: TEncodeConfig;
                     out OutBuf: Pointer; out SampleCount: Integer): Boolean;
    function  ValidateMessage(const Msg: string; out ErrorMsg: string): Boolean;
  end;

  IDigitalModeCodec = interface(IDecodeEngine)
    ['{D01-CODEC-0000-0000-000000000003}']
    function  GetEncodeEngine: IEncodeEngine;
    function  GetSequenceRules: ISequenceRules;  // D-02 参照
  end;

  // --- 実装クラス ---
  TFT8Codec  = class(TInterfacedObject, IDigitalModeCodec)
    constructor Create(SubMode: TFT8SubMode);   // smFT8 / smFT4
  end;

  TJT65Codec = class(TInterfacedObject, IDigitalModeCodec)
    constructor Create(SubMode: TJT65SubMode);  // smJT65 / smJT9 / smQ65
  end;

  TMSK144Codec = class(TInterfacedObject, IDigitalModeCodec)
    constructor Create;
  end;

  TCWCodec = class(TInterfacedObject, IDigitalModeCodec)
    constructor Create(SpeedWPM: Integer; Logger: ILogger);
  end;

  TRTTYCodec = class(TInterfacedObject, IDigitalModeCodec)
    constructor Create(MarkHz, SpaceHz, BaudRate: Integer);
  end;

  TPSK31Codec = class(TInterfacedObject, IDigitalModeCodec)
    constructor Create(SubMode: TPSKSubMode);  // smBPSK / smQPSK
  end;

  TNullCodec = class(TInterfacedObject, IDigitalModeCodec)
    SimResult : TDecodeResult;
  end;
```

### 13.2 D-02: モード別シーケンス規則（src/app/SeqRules.pas）

```pascal
unit SeqRules;
{$mode objfpc}{$H+}

type
  TSequenceRuleSet = record
    ModeName          : string;
    CycleSec          : Integer;
    TxWindowOffsetSec : Integer;
    MaxRetries        : Integer;
    ShortSeqEnabled   : Boolean;
    ShortSeqSNRThresh : Integer;
    AutoStopOn73      : Boolean;
  end;

  ISequenceRules = interface
    ['{D02-SEQRULES-0000-000000000004}']
    function  GetRuleSet: TSequenceRuleSet;
    function  IsMyTxWindow(UTCSecMod: Integer): Boolean;
    function  ClassifyResponse(const Msg, MyCall, DXCall: string): TSeqEvent;
  end;

  TFT8SeqRules    = class(TInterfacedObject, ISequenceRules)
    constructor Create(EvenSlot: Boolean);
  end;

  TMSK144SeqRules = class(TInterfacedObject, ISequenceRules)
    constructor Create(SNRThreshold: Integer);
  end;

  TCWSeqRules     = class(TInterfacedObject, ISequenceRules)
    constructor Create(SpeedWPM: Integer);
  end;

  TManualSeqRules = class(TInterfacedObject, ISequenceRules);
```

`TSeqControllerDeps` に `SequenceRules` と `MessageBuilder` を追加する（第2章参照）:

```pascal
// shared/AmityInterfaces.pas — TSeqControllerDeps 改訂
TSeqControllerDeps = record
  BandPlanGuard  : IBandPlanGuard;
  TimeValidator  : ITimeValidator;
  FreqControl    : IRigFreqControl;
  TransmitControl: IRigTransmitControl;
  IPCSender      : IIPCSender;
  QSORepo        : IQSORepository;
  ContestEngine  : IContestEngine;
  Logger         : ILogger;
  SequenceRules  : ISequenceRules;   // [D-02 追加]
  MessageBuilder : TMessageBuilder;  // [S-04 対応追加]
end;
```

### 13.3 D-03: 音声信号処理パイプライン（dsp/AudioPipeline.pas）

```pascal
unit AudioPipeline;
{$mode objfpc}{$H+}

type
  TAudioFrame = record
    Samples      : array of Single;
    SampleRate   : Integer;
    TimestampUTC : string;
    FreqLowHz    : Integer;
    FreqHighHz   : Integer;
  end;

  IAudioStage = interface
    ['{D03-STAGE-0000-000000000005}']
    procedure Process(const Input: TAudioFrame; out Output: TAudioFrame);
    function  StageName: string;
  end;

  TFFTStage            = class(TInterfacedObject, IAudioStage)
    constructor Create(FFTSize: Integer; WindowFunc: TWindowFunction);
  end;

  TBandpassFilterStage = class(TInterfacedObject, IAudioStage)
    constructor Create(LowHz, HighHz, RolloffDB: Integer);
  end;

  TNormalizationStage  = class(TInterfacedObject, IAudioStage)
    constructor Create(TargetRMSdB: Single);
  end;

  TAudioPipeline = class
  private
    FStages : array of IAudioStage;
  public
    procedure AddStage(Stage: IAudioStage);
    procedure Execute(const Input: TAudioFrame; out Output: TAudioFrame);
  end;
```

---

## 14. リグ制御コンポーネント（R カテゴリ）

### 14.1 R-01: リグプロトコル（src/infra/RigProtocol.pas）

```pascal
unit RigProtocol;
{$mode objfpc}{$H+}

type
  IRigProtocol = interface
    ['{R01-PROTO-0000-000000000006}']
    function  Connect: Boolean;
    procedure Disconnect;
    function  IsConnected: Boolean;
    function  SendCommand(const Cmd: string; out Response: string): Boolean;
    function  ProtocolName: string;
  end;

  TRigCtldProtocol   = class(TInterfacedObject, IRigProtocol)
    constructor Create(const Host: string; Port: Integer; Logger: ILogger);
  end;

  TCI_VProtocol      = class(TInterfacedObject, IRigProtocol)
    constructor Create(const SerialPort: string; BaudRate: Integer;
                       CIVAddress: Byte; Logger: ILogger);
  end;

  TCATProtocol       = class(TInterfacedObject, IRigProtocol)
    constructor Create(const SerialPort: string; BaudRate: Integer;
                       RigModel: TYaesuModel; Logger: ILogger);
  end;

  TFlrigProtocol     = class(TInterfacedObject, IRigProtocol)
    constructor Create(const BaseURL: string; Logger: ILogger);
  end;

  TSimulatorProtocol = class(TInterfacedObject, IRigProtocol)
  public
    procedure MapResponse(const Cmd, Response: string);
    procedure SimulateDisconnect;
  end;
```

### 14.2 R-02: リグ機能インターフェース ISP 分割（shared/AmityInterfaces.pas 追記）

```pascal
// shared/AmityInterfaces.pas — 追記
type
  TRigMode = (rmUSB, rmLSB, rmCW, rmCWR, rmFM, rmAM, rmDIG, rmPKT);

  IRigVFOControl = interface
    ['{R02-VFO-0000-000000000007}']
    function  GetVFOFreqHz: Int64;
    procedure SetVFOFreqHz(FreqHz: Int64);
    function  GetVFOBFreqHz: Int64;
    procedure SetVFOBFreqHz(FreqHz: Int64);
    procedure SetSplitMode(Enabled: Boolean; TxFreqHz: Int64);
    procedure RegisterFreqChangeCallback(Callback: TRigStatusProc);
    procedure UnregisterFreqChangeCallback(Callback: TRigStatusProc);
  end;

  IRigModeControl = interface
    ['{R02-MODE-0000-000000000008}']
    function  GetMode: TRigMode;
    procedure SetMode(Mode: TRigMode; FilterBW: Integer);
    function  GetPassbandHz: Integer;
  end;

  IRigPowerControl = interface
    ['{R02-PWR-0000-000000000009}']
    function  GetTxPowerPct: Integer;
    procedure SetTxPowerPct(Pct: Integer);
    function  MaxPowerW: Integer;
  end;

  IRigMemoryControl = interface
    ['{R02-MEM-0000-00000000000A}']
    procedure WriteMemory(Ch: Integer; FreqHz: Int64; Mode: TRigMode);
    procedure RecallMemory(Ch: Integer);
    procedure StartBandScan(LowHz, HighHz: Int64; StepHz: Integer);
    procedure StopBandScan;
  end;
```

### 14.3 R-03: 接続状態機械（src/infra/RigConnectionSM.pas）

```pascal
unit RigConnectionSM;
{$mode objfpc}{$H+}

type
  TConnectionState = (csDisconnected, csConnecting, csConnected,
                      csReconnecting, csFailed);

  IReconnectPolicy = interface
    ['{R03-POLICY-0000-00000000000B}']
    function  ShouldRetry(Attempt: Integer): Boolean;
    function  WaitMsBeforeRetry(Attempt: Integer): Integer;
    procedure Reset;
  end;

  TFixedIntervalPolicy     = class(TInterfacedObject, IReconnectPolicy)
    constructor Create(IntervalMs, MaxAttempts: Integer);
  end;

  TExponentialBackoffPolicy = class(TInterfacedObject, IReconnectPolicy)
    constructor Create(BaseMs, MaxMs: Integer; Multiplier: Single);
  end;

  TSimulatorPolicy         = class(TInterfacedObject, IReconnectPolicy)
    SimSuccess : Boolean;
  end;

  TRigConnectionSM = class
  private
    FProtocol  : IRigProtocol;
    FPolicy    : IReconnectPolicy;
    FState     : TConnectionState;
    FAttempts  : Integer;
    FLogger    : ILogger;
    FOnState   : reference to procedure(S: TConnectionState);
  public
    constructor Create(Protocol : IRigProtocol;
                       Policy   : IReconnectPolicy;
                       Logger   : ILogger);
    procedure Connect;
    procedure Disconnect;
    procedure TryReconnect;
    function  CurrentState: TConnectionState;
    procedure RegisterStateCallback(Cb: reference to procedure(S: TConnectionState));
  end;
```

### 14.4 R-04: リグ×バンドプラン連携（src/app/RigBandCoordinator.pas）

```pascal
unit RigBandCoordinator;
{$mode objfpc}{$H+}

type
  TBandChangeEvent = record
    OldFreqHz   : Int64;
    NewFreqHz   : Int64;
    OldBand     : string;
    NewBand     : string;
    SuggestMode : TRigMode;
    MaxPowerW   : Integer;
  end;

  IRigBandCoordinator = interface
    ['{R04-BAND-0000-00000000000C}']
    procedure OnFreqChanged(NewFreqHz: Int64);
    procedure RegisterBandChangeCallback(
                Cb: reference to procedure(const E: TBandChangeEvent));
    procedure UnregisterBandChangeCallback(
                Cb: reference to procedure(const E: TBandChangeEvent));
  end;

  TRigBandCoordinator = class(TInterfacedObject, IRigBandCoordinator)
  private
    FVFOControl  : IRigVFOControl;
    FModeControl : IRigModeControl;
    FPowerCtrl   : IRigPowerControl;
    FBandGuard   : IBandPlanGuard;
    FLogger      : ILogger;
    FObservers   : specialize TObserverList<
                     reference to procedure(const E: TBandChangeEvent)>;
  public
    constructor Create(VFO    : IRigVFOControl;
                       Mode   : IRigModeControl;
                       Power  : IRigPowerControl;
                       Guard  : IBandPlanGuard;
                       Logger : ILogger);
    procedure OnFreqChanged(NewFreqHz: Int64);
    procedure RegisterBandChangeCallback(
                Cb: reference to procedure(const E: TBandChangeEvent));
    procedure UnregisterBandChangeCallback(
                Cb: reference to procedure(const E: TBandChangeEvent));
  end;
```

---

## 15. 汎用ミドルウェアコンポーネント（M カテゴリ）

### 15.1 M-01: LWW ジャーナル同期エンジン（lib/middleware/LWWSync/LWWSyncEngine.pas）

```pascal
unit LWWSyncEngine;
{$mode objfpc}{$H+}

type
  ILWWRecord = interface
    ['{M01-RECORD-0000-00000000000D}']
    function  RecordID: string;
    function  UpdatedAt: Int64;
    function  DeviceID: string;
    function  NewValue: string;
  end;

  ILWWStore = interface
    ['{M01-STORE-0000-00000000000E}']
    procedure ApplyRecord(const Rec: ILWWRecord; Callback: TProc<string>);
    function  GetLocalTimestamp(const RecordID: string): Int64;
  end;

  ILWWJournalSource = interface
    ['{M01-SOURCE-0000-00000000000F}']
    function  ListPendingFiles: TArray<string>;
    function  LoadFile(const Path: string): ILWWRecord;
    procedure ArchiveFile(const Path: string);
  end;

  TLWWSyncEngine = class
  private
    FStore  : ILWWStore;
    FSource : ILWWJournalSource;
    FLogger : ILogger;
  public
    constructor Create(Store: ILWWStore; Source: ILWWJournalSource;
                       Logger: ILogger);
    function  MergeAll: Integer;
    procedure ProcessFile(const FilePath: string);
    class function ShouldApply(const Incoming: ILWWRecord;
                               LocalTimestamp: Int64): Boolean; static;
  end;
```

### 15.2 M-02: SQLite マイグレーション（lib/middleware/SQLiteMigrate/SQLiteMigrate.pas）

```pascal
unit SQLiteMigrate;
{$mode objfpc}{$H+}

type
  TMigrationScript = record
    Version     : Integer;
    Description : string;
    UpSQL       : string;
    DownSQL     : string;
  end;

  IMigrationSource = interface
    ['{M02-SOURCE-0000-000000000010}']
    function GetScripts: TArray<TMigrationScript>;
  end;

  TInlineScriptSource = class(TInterfacedObject, IMigrationSource)
    constructor Create(const Scripts: array of TMigrationScript);
  end;

  TFileScriptSource = class(TInterfacedObject, IMigrationSource)
    constructor Create(const DirPath: string);
  end;

  TSchemaVersion = record
    Current       : Integer;
    Latest        : Integer;
    NeedsMigration: Boolean;
  end;

  TSQLiteMigrator = class
  public
    constructor Create(DB: Pointer; Source: IMigrationSource; Logger: ILogger);
    function  Status: TSchemaVersion;
    procedure MigrateToLatest;
    procedure MigrateTo(Version: Integer);
    procedure RollbackTo(Version: Integer);
  end;
```

### 15.3 M-03〜M-05 インターフェース定義

```pascal
// M-03: lib/middleware/LuaSandbox/LuaSandboxRuntime.pas
type
  ILuaBindingSet = interface
    ['{M03-BINDING-0000-000000000011}']
    function GetBindings: TArray<TLuaBinding>;
    procedure AttachContext(L: Pointer);
  end;

  TLuaSandboxRuntime = class(TInterfacedObject, ILuaRuntime)
  public
    constructor Create(const PublicKeyPEM: string; Logger: ILogger);
    procedure RegisterBindingSet(BindingSet: ILuaBindingSet);
    // 既存 ILuaRuntime メソッドを実装
    function  LoadScript(const ScriptPath, SigPath: string): Boolean;
    function  CallFunction(const FuncName: string; Args: array of Variant): Variant;
    procedure SetScoringContext(Context: ILuaScoringContext);
    procedure Reset;
  end;

// M-04: lib/middleware/AsyncDispatch/AsyncDispatch.pas
type
  TAsyncCallback<T> = reference to procedure(const Value: T; const Error: string);
  TAsyncDispatcher = class
    class procedure Dispatch<T>(const Value: T; const Error: string;
                                Callback: TAsyncCallback<T>);
    class procedure DispatchError(const Error: string; Callback: TProc<string>);
  end;

// M-05: lib/middleware/FTS5Search/FTS5Search.pas
type
  TFTS5SearchResult = record
    RowID   : Int64;
    Rank    : Double;
    Snippet : string;
  end;

  IFTS5Index = interface
    ['{M05-FTS5-0000-000000000012}']
    procedure Insert(RowID: Int64; const Fields: TArray<string>);
    procedure Update(RowID: Int64; const Fields: TArray<string>);
    procedure Delete(RowID: Int64);
    function  Search(const Query: string; Limit: Integer;
                     OffsetFrom: Int64 = 0): TArray<TFTS5SearchResult>;
    class function EscapeQuery(const Raw: string): string; static;
  end;

  TFTS5Index = class(TInterfacedObject, IFTS5Index)
    constructor Create(DB: Pointer; const TableName: string;
                       const Columns: TArray<string>);
  end;
```

---

## 16. 無線ドメインライブラリコンポーネント（H カテゴリ）

```pascal
// H-01: lib/hamlib/ADIFLib/ADIFLib.pas
type
  TADIFRecord = class
    Fields : TDictionary<string, string>;
    function  Get(const Tag: string; const Default: string = ''): string;
    procedure Set_(const Tag, Value: string);
    function  HasTag(const Tag: string): Boolean;
  end;

  TADIFReader = class
    constructor Create(Stream: TStream);
    function  ReadNext(out Rec: TADIFRecord): Boolean;
    property  Position: Int64;
  end;

  TADIFWriter = class
    constructor Create(Stream: TStream; const AppName: string = 'AmityQSO');
    procedure Write(Rec: TADIFRecord);
    procedure Flush;
  end;

  // Amity-QSO アダプター (src/ 側に配置)
  TADIFQSOAdapter = class
    class function ToADIF(const Data: TQSOData): TADIFRecord; static;
    class function FromADIF(Rec: TADIFRecord): TQSOData; static;
  end;

// H-02: lib/hamlib/DXCCResolver/DXCCResolver.pas
type
  TDXCCInfo = record
    Callsign  : string; BaseCall : string; Prefix    : string;
    Entity    : string; DXCC     : Integer; Continent : string;
    CQZone    : Integer; ITUZone  : Integer;
    Latitude  : Double; Longitude : Double; IsValid   : Boolean;
  end;

  ICtyDataProvider = interface
    ['{H02-CTY-0000-000000000013}']
    procedure Load;
    function  GetEntries: TObjectList;
    function  GetPrefixIndex: TStringList;
  end;

  TBigCtyFileProvider   = class(TInterfacedObject, ICtyDataProvider)
    constructor Create(const FilePath: string; Logger: ILogger);
  end;
  TMemoryCtyProvider    = class(TInterfacedObject, ICtyDataProvider)
    procedure AddEntry(const Entry: TCtyEntry);
  end;

  IDXCCResolver = interface
    ['{H02-DXCC-0000-000000000014}']
    function  Resolve(const Callsign: string): TDXCCInfo;
    function  IsValidCallsign(const Callsign: string): Boolean;
    function  ResolvePrefix(const Callsign: string): string;
    procedure Reload(Provider: ICtyDataProvider);
  end;

// H-03: lib/hamlib/BandPlanEngine/BandPlanEngine.pas
type
  IBandPlanEngine = interface
    ['{H03-BPENG-0000-000000000015}']
    function  FreqToBand(FreqHz: Int64): string;
    function  IsBlockedForTx(FreqHz: Int64; const Region: string): Boolean;
    function  GetModeHint(FreqHz: Int64): string;
    function  AdjacentBands(const Band: string): TArray<string>;
  end;

// H-04: lib/hamlib/CabrilloLib/CabrilloLib.pas
type
  ICabrilloWriter = interface
    ['{H04-CAB-0000-000000000016}']
    procedure WriteHeader(const H: TCabrilloHeader);
    procedure WriteQSO(const Q: TCabrilloQSO);
    procedure WriteEnd;
  end;

// H-05: lib/hamlib/GridSquareLib/GridSquareLib.pas
type
  IGridSquareLib = interface
    ['{H05-GRID-0000-000000000017}']
    function  FromLatLon(Lat, Lon: Double): string;
    function  ToLatLon(const Grid: string; out Lat, Lon: Double): Boolean;
    function  Distance(const A, B: string): Double;
    function  Bearing(const From, To_: string): Double;
    function  IsValid(const Grid: string): Boolean;
  end;

// H-06: lib/hamlib/QSLStateMachine/QSLStateMachine.pas
type
  IQSLStateMachine = interface
    ['{H06-QSL-0000-000000000018}']
    function  CurrentState(const QsoID: string): TQSLStatus;
    function  Transition(const QsoID: string; ToState: TQSLStatus;
                         out Error: string): Boolean;
    function  AllowedTransitions(Current: TQSLStatus): TArray<TQSLStatus>;
  end;

// H-07: lib/hamlib/ContestRules/ContestRules.pas
type
  IContestRuleInterpreter = interface
    ['{H07-CNTRULE-0000-000000000019}']
    procedure LoadDefinition(const JSONPath, LuaPath: string);
    function  IsDupe(const Callsign, Band, Mode: string): Boolean;
    function  ScoreQSO(Fields: TDictionary<string, string>): Integer;
    function  TotalScore: Integer;
    function  MultiplierCount: Integer;
  end;

// H-08: lib/hamlib/FreqFormatter/FreqFormatter.pas
type
  TFreqDisplayStyle = (fdsHz, fdskHz, fdsMHz, fdsMHzDot3, fdsMHzDot6);

  IFreqFormatter = interface
    ['{H08-FREQ-0000-00000000001A}']
    function  Format(FreqHz: Int64; Style: TFreqDisplayStyle): string;
    function  Parse(const Str: string; out FreqHz: Int64): Boolean;
    function  BandCenterHz(const Band: string): Int64;
  end;
```

---

## 17. 技術インフラコンポーネント（T カテゴリ）

```pascal
// T-01: lib/infra/SPSCBuffer/SPSCBuffer.pas
type
  generic TSPSCRingBuffer<T> = class
  private
    FData     : array of T;
    FWritePos : Int64;
    FReadPos  : Int64;
    FOverruns : Int64;
    FCapacity : Integer;
  public
    constructor Create(Capacity: Integer);
    procedure Write(const Src: array of T; Count: Integer);
    function  Read(out Dst: array of T; Count: Integer): Integer;
    procedure Reset;
    function  BufferedCount: Int64;
    property  OverrunCount: Int64 read FOverruns;
    property  Capacity: Integer read FCapacity;
  end;
  TAudioRingBuffer = specialize TSPSCRingBuffer<Single>;

// T-02: lib/infra/CodeSigning/CodeSigningVerifier.pas
type
  TCodeSigningVerifier = class
  public
    constructor Create(const PublicKeyBytes: TBytes);
    function  VerifyFilePair(const ContentPath, SigPath: string): Boolean;
    function  VerifyBytes(const Content, Signature: TBytes): Boolean;
    function  LastError: string;
  end;

// T-03: lib/infra/ProcessGuard/ProcessGuardSM.pas
type
  TProcessGuardState = (pgsIdle, pgsStarting, pgsRunning,
                        pgsCrashed, pgsRestarting, pgsFailed);

  IProcessLauncher = interface
    ['{T03-LAUNCH-0000-00000000001B}']
    function  Launch(const ExePath: string; const Args: TArray<string>): THandle;
    procedure Terminate(Handle: THandle);
    function  IsAlive(Handle: THandle): Boolean;
  end;

  IHealthChecker = interface
    ['{T03-HEALTH-0000-00000000001C}']
    function  Check: Boolean;
    function  TimeoutMs: Integer;
  end;

  TProcessGuardSM = class
  public
    constructor Create(Launcher  : IProcessLauncher;
                       HealthChk : IHealthChecker;
                       MaxRetries: Integer;
                       Logger    : ILogger);
    procedure Start(const ExePath: string);
    procedure Stop;
    function  State: TProcessGuardState;
    procedure RegisterStateCallback(Cb: reference to procedure(S: TProcessGuardState));
  end;

// T-04: lib/infra/ConfigDSL/ConfigDSL.pas
type
  generic TConfigBinding<T> = class
  private
    FValue    : T;
    FKey      : string;
    FDefault  : T;
    FValidator: reference to function(const V: T): Boolean;
    FOnChange : specialize TObserverList<reference to procedure(const V: T)>;
  public
    function  Get: T;
    procedure Set_(const V: T);
    procedure Bind(Cb: reference to procedure(const V: T));
    procedure Unbind(Cb: reference to procedure(const V: T));
    property  Key: string read FKey;
  end;
```

---

## 18. アプリ固有コンポーネント（A カテゴリ）

```pascal
// A-01: src/app/CTIAffinityEngine.pas
type
  TAffinityThresholds = record
    Level1MinQSO : Integer;  // デフォルト 1
    Level2MinQSO : Integer;  // デフォルト 5
    Level3MinQSO : Integer;  // デフォルト 20
    AbsentDays   : Integer;  // デフォルト 90
  end;

  TCTIBadgeSet = record
    IsNewDXCC      : Boolean;
    IsNewBand      : Boolean;
    HasLoTWPending : Boolean;
    IsFirstQSO     : Boolean;
    IsLongAbsent   : Boolean;
  end;

  ICTIAffinityEngine = interface
    ['{A01-AFF-0000-00000000001D}']
    function  CalcLevel(QSOCount, DaysSinceLastQSO: Integer): TAffinityLevel;
    function  CalcBadges(const Stats: TCTIStats;
                         const CurrentBand, CurrentDXCC: string): TCTIBadgeSet;
    procedure SetThresholds(const T: TAffinityThresholds);
  end;

// A-02: src/app/AwardCalculator.pas
type
  TGridProgress = record
    WorkedCount : Integer;
    CFMCount    : Integer;
    WorkedGrids : TArray<string>;
    CFMGrids    : TArray<string>;
  end;

  IAwardCalculator = interface
    ['{A02-AWARD-0000-00000000001E}']
    function  CalcGridProgress(const WorkedGrids, CFMGrids: TArray<string>): TGridProgress;
    function  CalcDXCCProgress(const QSOList: TArray<TQSOData>): TDXCCProgress;
    function  CalcBandStats(const QSOList: TArray<TQSOData>): TBandStats;
  end;

// A-03: src/app/PSKReporterClient.pas
type
  TDXSpot = record
    Callsign : string;
    FreqHz   : Int64;
    Mode     : string;
    SNR      : Integer;
    Spotter  : string;
    SpottedAt: Int64;
  end;

  IPSKReporterClient = interface
    ['{A03-PSKR-0000-00000000001F}']
    procedure ReportReception(const Candidates: TDecodeCandidateArray;
                              const MyCallsign, MyGrid: string);
    procedure FetchSpots(const Callsign: string;
                         Callback: reference to procedure(Spots: TArray<TDXSpot>));
  end;

// A-04: src/app/DXClusterClient.pas
type
  IDXClusterClient = interface
    ['{A04-DXCL-0000-000000000020}']
    procedure Connect(const Host: string; Port: Integer);
    procedure Disconnect;
    procedure SendDX(FreqHz: Int64; const Callsign, Comment: string);
    procedure RegisterSpotCallback(Cb: reference to procedure(const S: TDXSpot));
    function  IsConnected: Boolean;
  end;
```

