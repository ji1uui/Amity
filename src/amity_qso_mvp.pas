program AmityQSOMVP;

{$mode objfpc}{$H+}

uses
  SysUtils;

type
  TQSO = class
  private
    FCallsign: string;
    FBand: string;
    FModeName: string;
    FSignalReportSent: string;
    FSignalReportRecv: string;
    FMemo: string;
    FUTCDateTime: TDateTime;
  public
    constructor Create(
      const ACallsign, ABand, AModeName, ASignalReportSent, ASignalReportRecv, AMemo: string;
      const AUTCDateTime: TDateTime
    );
    function ToCsvLine: string;
    class function CsvHeader: string;
  end;

  TQSORepository = class
  private
    FFileName: string;
  public
    constructor Create(const AFileName: string);
    procedure Save(const AQSO: TQSO);
  end;

  TAmityQSOApp = class
  private
    FRepository: TQSORepository;
    function Prompt(const ALabel: string): string;
    function BuildQSO: TQSO;
    procedure PrintMenu;
    procedure RegisterQSO;
  public
    constructor Create(const ARepository: TQSORepository);
    procedure Run;
  end;

constructor TQSO.Create(
  const ACallsign, ABand, AModeName, ASignalReportSent, ASignalReportRecv, AMemo: string;
  const AUTCDateTime: TDateTime
);
begin
  FCallsign := UpperCase(Trim(ACallsign));
  FBand := UpperCase(Trim(ABand));
  FModeName := UpperCase(Trim(AModeName));
  FSignalReportSent := Trim(ASignalReportSent);
  FSignalReportRecv := Trim(ASignalReportRecv);
  FMemo := Trim(AMemo);
  FUTCDateTime := AUTCDateTime;
end;

function TQSO.ToCsvLine: string;
begin
  Result :=
    FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', FUTCDateTime) + ',' +
    FCallsign + ',' + FBand + ',' + FModeName + ',' +
    FSignalReportSent + ',' + FSignalReportRecv + ',' + FMemo;
end;

class function TQSO.CsvHeader: string;
begin
  Result := 'utc_datetime,callsign,band,mode,sent,recv,memo';
end;

constructor TQSORepository.Create(const AFileName: string);
begin
  FFileName := AFileName;
end;

procedure TQSORepository.Save(const AQSO: TQSO);
var
  F: TextFile;
  Exists: Boolean;
begin
  Exists := FileExists(FFileName);
  AssignFile(F, FFileName);
  if Exists then
    Append(F)
  else
  begin
    Rewrite(F);
    Writeln(F, TQSO.CsvHeader);
  end;

  Writeln(F, AQSO.ToCsvLine);
  CloseFile(F);
end;

constructor TAmityQSOApp.Create(const ARepository: TQSORepository);
begin
  FRepository := ARepository;
end;

function TAmityQSOApp.Prompt(const ALabel: string): string;
begin
  Write(ALabel);
  Readln(Result);
end;

function TAmityQSOApp.BuildQSO: TQSO;
var
  Callsign: string;
  Band: string;
  ModeName: string;
  Sent: string;
  Recv: string;
  MemoText: string;
begin
  Callsign := Prompt('コールサイン: ');
  Band := Prompt('バンド (例: 20M): ');
  ModeName := Prompt('モード (例: FT8): ');
  Sent := Prompt('送信レポート (例: -05): ');
  Recv := Prompt('受信レポート (例: -12): ');
  MemoText := Prompt('メモ: ');

  Result := TQSO.Create(Callsign, Band, ModeName, Sent, Recv, MemoText, Now);
end;

procedure TAmityQSOApp.PrintMenu;
begin
  Writeln('=== Amity-QSO MVP ===');
  Writeln('1) QSOを記録する');
  Writeln('2) 終了');
  Write('選択してください: ');
end;

procedure TAmityQSOApp.RegisterQSO;
var
  QSO: TQSO;
begin
  QSO := BuildQSO;
  try
    FRepository.Save(QSO);
    Writeln('保存しました: qso_log.csv');
  finally
    QSO.Free;
  end;
end;

procedure TAmityQSOApp.Run;
var
  Choice: string;
begin
  repeat
    PrintMenu;
    Readln(Choice);
    case Choice of
      '1': RegisterQSO;
      '2': Writeln('終了します。73!');
    else
      Writeln('無効な選択です。');
    end;
    Writeln;
  until Choice = '2';
end;

var
  Repository: TQSORepository;
  App: TAmityQSOApp;
begin
  Repository := TQSORepository.Create('qso_log.csv');
  try
    App := TAmityQSOApp.Create(Repository);
    try
      App.Run;
    finally
      App.Free;
    end;
  finally
    Repository.Free;
  end;
end.
