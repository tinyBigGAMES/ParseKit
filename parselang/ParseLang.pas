{===============================================================================
  Parse()™ - Compiler Construction Toolkit
  ParseLang — .parse meta-language wrapper

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

(*
  ParseLang — TParseLang Wrapper

  A two-phase compiler that reads a .parse language definition file and then
  uses the resulting configuration to compile source files written in that
  defined language.

  Usage:
    LPL := TParseLang.Create();
    LPL.SetLangFile('mylang.parse');
    LPL.SetSourceFile('hello.ml');
    LPL.SetOutputPath('output');
    LPL.SetTargetPlatform(tpWin64);
    LPL.SetBuildMode(bmExe);
    LPL.SetOptimizeLevel(olDebug);
    LPL.SetStatusCallback(...);
    LPL.Compile();
    LPL.Free();

  LIFETIME CONTRACT
  -----------------
  FBootstrapParse owns the .parse AST. Closures registered on FCustomParse
  capture references to nodes in that AST. Therefore FCustomParse MUST be
  freed before FBootstrapParse. This ordering is enforced in Destroy() and
  at the start of each Compile() call.

  Each call to Compile() creates fresh FBootstrapParse and FCustomParse
  instances, ensuring a clean slate for repeated compilations.
*)

unit ParseLang;

{$I ..\src\Parse.Defines.inc}

interface

uses
  System.SysUtils,
  Parse,
  ParseLang.Common;

const
  PARSELANG_VERSION_MAJOR = 0;
  PARSELANG_VERSION_MINOR = 1;
  PARSELANG_VERSION_PATCH = 0;
  PARSELANG_VERSION_STR   = '0.1.0';

type

  { TParseLang }
  TParseLang = class(TParseOutputObject)
  private
    // FBootstrapParse: parses the .parse lang definition file.
    // Owns the AST that phase-2 closures reference — must outlive FCustomParse.
    FBootstrapParse: TParse;

    // FCustomParse: the configured custom language compiler.
    // Created fresh each Compile(); closures from ConfigCodeGen are wired here.
    FCustomParse: TParse;

    // Paths and settings accumulated between Compile() calls
    FLangFile:       string;
    FSourceFile:     string;
    FOutputPath:     string;
    FTargetPlatform: TParseTargetPlatform;
    FBuildMode:      TParseBuildMode;
    FOptimizeLevel:  TParseOptimizeLevel;
    FSubsystem:      TParseSubsystemType;

    // Tracks which phase produced the last set of errors:
    //   True  = bootstrap phase (.parse file errors)
    //   False = custom lang phase (source file errors)
    FLastErrorsFromBootstrap: Boolean;

    // Free both parse instances in the correct order (custom first, then bootstrap)
    procedure FreeParseInstances();

    // Forward accumulated settings to FCustomParse before running it
    procedure ForwardSettingsToCustom();

    // Build the TParseLangPipelineCallbacks record pointing at FCustomParse
    function BuildPipelineCallbacks(): TParseLangPipelineCallbacks;

  public
    constructor Create(); override;
    destructor  Destroy(); override;

    // ---- Language definition ----

    // Path to the .parse language definition file.
    // Must be set before calling Compile().
    procedure SetLangFile(const AFilename: string);
    function  GetLangFile(): string;

    // ---- Source and output ----

    procedure SetSourceFile(const AFilename: string);
    function  GetSourceFile(): string;

    procedure SetOutputPath(const APath: string);
    function  GetOutputPath(): string;

    // ---- Build configuration ----

    procedure SetTargetPlatform(const APlatform: TParseTargetPlatform);
    procedure SetBuildMode(const ABuildMode: TParseBuildMode);
    procedure SetOptimizeLevel(const ALevel: TParseOptimizeLevel);
    procedure SetSubsystem(const ASubsystem: TParseSubsystemType);

    // ---- Callbacks — forwarded to both parse instances ----

    procedure SetStatusCallback(const ACallback: TParseStatusCallback;
      const AUserData: Pointer = nil); override;
    procedure SetOutputCallback(
      const ACallback: TParseCaptureConsoleCallback;
      const AUserData: Pointer = nil); override;

    // ---- Error access ----

    // Returns True if the last Compile() produced any errors.
    function HasErrors(): Boolean;

    // Returns the error collection from the last Compile() phase that ran.
    function GetErrors(): TParseErrors;

    // ---- Pipeline ----

    // Phase 1: parse FLangFile → configure FCustomParse.
    // Phase 2: compile FSourceFile with FCustomParse.
    // ABuild:   if True, invoke the Zig toolchain to produce a native binary.
    // AAutoRun: if True and ABuild succeeded, run the produced binary.
    // Returns True if both phases completed without errors.
    function Compile(const ABuild: Boolean = True;
      const AAutoRun: Boolean = False): Boolean;

    // Run the last successfully compiled binary.
    function Run(): Cardinal;

    // Exit code from the last Run() call.
    function GetLastExitCode(): Cardinal;

    // Version string
    function GetVersionStr(): string;
  end;

implementation

uses
  System.IOUtils,
  ParseLang.Lexer,
  ParseLang.Grammar,
  ParseLang.Semantics,
  ParseLang.CodeGen;

{ TParseLang }

constructor TParseLang.Create();
begin
  inherited Create();
  FBootstrapParse           := nil;
  FCustomParse              := nil;
  FLangFile                 := '';
  FSourceFile               := '';
  FOutputPath               := '';
  FTargetPlatform           := tpWin64;
  FBuildMode                := bmExe;
  FOptimizeLevel            := olDebug;
  FSubsystem                := stConsole;
  FLastErrorsFromBootstrap  := False;
end;

destructor TParseLang.Destroy();
begin
  // Free in correct order: custom first (holds closures referencing bootstrap AST),
  // then bootstrap (owns the AST).
  FreeParseInstances();
  inherited Destroy();
end;

procedure TParseLang.FreeParseInstances();
begin
  // FCustomParse must be freed before FBootstrapParse because its registered
  // closures hold references to AST nodes owned by FBootstrapParse.
  FreeAndNil(FCustomParse);
  FreeAndNil(FBootstrapParse);
end;

procedure TParseLang.ForwardSettingsToCustom();
begin
  if FCustomParse = nil then
    Exit;
  FCustomParse.SetSourceFile(FSourceFile);
  if FOutputPath <> '' then
    FCustomParse.SetOutputPath(FOutputPath);
  FCustomParse.SetTargetPlatform(FTargetPlatform);
  FCustomParse.SetBuildMode(FBuildMode);
  FCustomParse.SetOptimizeLevel(FOptimizeLevel);
  FCustomParse.SetSubsystem(FSubsystem);
  // Forward callbacks so status/output messages flow through to the caller
  FCustomParse.SetStatusCallback(
    FStatusCallback.Callback, FStatusCallback.UserData);
  FCustomParse.SetOutputCallback(
    FOutput.Callback, FOutput.UserData);
end;

function TParseLang.BuildPipelineCallbacks(): TParseLangPipelineCallbacks;
begin
  // Each callback captures FCustomParse by reference. At the time these
  // closures fire (Phase 2), FCustomParse is alive and fully wired.
  Result.OnSetPlatform :=
    procedure(AValue: string)
    begin
      if AValue = 'win64'        then FCustomParse.SetTargetPlatform(tpWin64)
      else if AValue = 'linux64' then FCustomParse.SetTargetPlatform(tpLinux64);
    end;

  Result.OnSetBuildMode :=
    procedure(AValue: string)
    begin
      if AValue = 'exe'     then FCustomParse.SetBuildMode(bmExe)
      else if AValue = 'lib'     then FCustomParse.SetBuildMode(bmLib)
      else if AValue = 'dll'     then FCustomParse.SetBuildMode(bmDll);
    end;

  Result.OnSetOptimize :=
    procedure(AValue: string)
    begin
      if AValue = 'debug'   then FCustomParse.SetOptimizeLevel(olDebug)
      else if AValue = 'release'  then FCustomParse.SetOptimizeLevel(olReleaseSafe)
      else if AValue = 'speed'    then FCustomParse.SetOptimizeLevel(olReleaseFast)
      else if AValue = 'size'     then FCustomParse.SetOptimizeLevel(olReleaseSmall);
    end;

  Result.OnSetSubsystem :=
    procedure(AValue: string)
    begin
      if AValue = 'console' then FCustomParse.SetSubsystem(stConsole)
      else if AValue = 'gui'      then FCustomParse.SetSubsystem(stGui);
    end;

  Result.OnSetOutputPath :=
    procedure(AValue: string)
    begin
      FCustomParse.SetOutputPath(AValue);
    end;
end;

// =========================================================================
// Public Setters
// =========================================================================

procedure TParseLang.SetLangFile(const AFilename: string);
begin
  FLangFile := AFilename;
end;

function TParseLang.GetLangFile(): string;
begin
  Result := FLangFile;
end;

procedure TParseLang.SetSourceFile(const AFilename: string);
begin
  FSourceFile := AFilename;
end;

function TParseLang.GetSourceFile(): string;
begin
  Result := FSourceFile;
end;

procedure TParseLang.SetOutputPath(const APath: string);
begin
  FOutputPath := APath;
end;

function TParseLang.GetOutputPath(): string;
begin
  Result := FOutputPath;
end;

procedure TParseLang.SetTargetPlatform(const APlatform: TParseTargetPlatform);
begin
  FTargetPlatform := APlatform;
end;

procedure TParseLang.SetBuildMode(const ABuildMode: TParseBuildMode);
begin
  FBuildMode := ABuildMode;
end;

procedure TParseLang.SetOptimizeLevel(const ALevel: TParseOptimizeLevel);
begin
  FOptimizeLevel := ALevel;
end;

procedure TParseLang.SetSubsystem(const ASubsystem: TParseSubsystemType);
begin
  FSubsystem := ASubsystem;
end;

procedure TParseLang.SetStatusCallback(const ACallback: TParseStatusCallback;
  const AUserData: Pointer);
begin
  inherited SetStatusCallback(ACallback, AUserData);
  // Forward to live instances if they exist (e.g. callback set before Compile)
  if FBootstrapParse <> nil then
    FBootstrapParse.SetStatusCallback(ACallback, AUserData);
  if FCustomParse <> nil then
    FCustomParse.SetStatusCallback(ACallback, AUserData);
end;

procedure TParseLang.SetOutputCallback(
  const ACallback: TParseCaptureConsoleCallback; const AUserData: Pointer);
begin
  inherited SetOutputCallback(ACallback, AUserData);
  if FBootstrapParse <> nil then
    FBootstrapParse.SetOutputCallback(ACallback, AUserData);
  if FCustomParse <> nil then
    FCustomParse.SetOutputCallback(ACallback, AUserData);
end;

// =========================================================================
// Error Access
// =========================================================================

function TParseLang.HasErrors(): Boolean;
begin
  if FLastErrorsFromBootstrap then
  begin
    if FBootstrapParse <> nil then
      Result := FBootstrapParse.HasErrors()
    else
      Result := False;
  end
  else
  begin
    if FCustomParse <> nil then
      Result := FCustomParse.HasErrors()
    else
      Result := False;
  end;
end;

function TParseLang.GetErrors(): TParseErrors;
begin
  if FLastErrorsFromBootstrap then
  begin
    if FBootstrapParse <> nil then
      Result := FBootstrapParse.GetErrors()
    else
      Result := nil;
  end
  else
  begin
    if FCustomParse <> nil then
      Result := FCustomParse.GetErrors()
    else
      Result := nil;
  end;
end;

// =========================================================================
// Compile
// =========================================================================

function TParseLang.Compile(const ABuild: Boolean;
  const AAutoRun: Boolean): Boolean;
var
  LPipeline: TParseLangPipelineCallbacks;
begin
  Result := False;

  // --- Pre-flight validation ---
  if FLangFile = '' then
    raise Exception.Create('TParseLang.Compile: LangFile not set');
  if not TFile.Exists(FLangFile) then
    raise Exception.CreateFmt(
      'TParseLang.Compile: LangFile not found: %s', [FLangFile]);
  if FSourceFile = '' then
    raise Exception.Create('TParseLang.Compile: SourceFile not set');

  // --- Free any previous instances (custom first, then bootstrap) ---
  FreeParseInstances();

  // =======================================================================
  // PHASE 1 — Parse the .parse language definition file
  // =======================================================================

  FBootstrapParse := TParse.Create();
  FCustomParse    := TParse.Create();

  // Forward callbacks to bootstrap so status messages reach the caller
  FBootstrapParse.SetStatusCallback(
    FStatusCallback.Callback, FStatusCallback.UserData);
  FBootstrapParse.SetOutputCallback(
    FOutput.Callback, FOutput.UserData);

  // Configure the bootstrap parser to understand the .parse meta-language
  ConfigLexer(FBootstrapParse);
  ConfigGrammar(FBootstrapParse);
  ConfigSemantics(FBootstrapParse);

  // Apply caller-supplied settings as defaults on FCustomParse BEFORE Phase 1
  // runs. The .parse file can override any of these via setPlatform() etc.
  ForwardSettingsToCustom();

  // Build pipeline callbacks that delegate into FCustomParse
  LPipeline := BuildPipelineCallbacks();

  // Register emitters: walking the .parse AST will call Config() on FCustomParse
  ConfigCodeGen(FBootstrapParse, FCustomParse, LPipeline);

  // Point bootstrap at the .parse file and compile (no Zig build, no run)
  FBootstrapParse.SetSourceFile(FLangFile);
  FBootstrapParse.Compile(False, False);

  // Check for bootstrap errors before proceeding to Phase 2
  FLastErrorsFromBootstrap := True;
  if FBootstrapParse.HasErrors() then
    Exit;

  // =======================================================================
  // PHASE 2 — Compile the user source file with the configured language
  // =======================================================================

  FLastErrorsFromBootstrap := False;

  // Compile the source file: lexer/grammar/semantic/codegen fire using the
  // handlers registered by ConfigCodeGen above.
  Result := FCustomParse.Compile(ABuild, AAutoRun);
end;

// =========================================================================
// Run / Exit Code
// =========================================================================

function TParseLang.Run(): Cardinal;
begin
  if FCustomParse <> nil then
    Result := FCustomParse.Run()
  else
    Result := High(Cardinal);
end;

function TParseLang.GetLastExitCode(): Cardinal;
begin
  if FCustomParse <> nil then
    Result := FCustomParse.GetLastExitCode()
  else
    Result := High(Cardinal);
end;

function TParseLang.GetVersionStr(): string;
begin
  Result := PARSELANG_VERSION_STR;
end;

end.
