{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

unit Parse;

{$I Parse.Defines.inc}

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Rtti,
  System.Generics.Collections,
  Parse.Utils,
  Parse.Resources,
  Parse.Common,
  Parse.Config,
  Parse.LangConfig,
  Parse.Lexer,
  Parse.Parser,
  Parse.Semantics,
  Parse.CodeGen,
  Parse.IR,
  Parse.Build;

const
  PARSE_MAJOR_VERSION = 0;
  PARSE_MINOR_VERSION = 1;
  PARSE_PATCH_VERSION = 0;
  PARSE_VERSION = (PARSE_MAJOR_VERSION * 10000) + (PARSE_MINOR_VERSION * 100) + PARSE_PATCH_VERSION;
  PARSE_VERSION_STR = '0.1.0';

  // Color constants
  COLOR_RESET  = Parse.Utils.COLOR_RESET;
  COLOR_BOLD   = Parse.Utils.COLOR_BOLD;
  COLOR_RED    = Parse.Utils.COLOR_RED;
  COLOR_GREEN  = Parse.Utils.COLOR_GREEN;
  COLOR_YELLOW = Parse.Utils.COLOR_YELLOW;
  COLOR_BLUE   = Parse.Utils.COLOR_BLUE;
  COLOR_CYAN   = Parse.Utils.COLOR_CYAN;
  COLOR_WHITE  = Parse.Utils.COLOR_WHITE;

  // Token kind constants
  PARSE_KIND_EOF           = Parse.Common.PARSE_KIND_EOF;
  PARSE_KIND_UNKNOWN       = Parse.Common.PARSE_KIND_UNKNOWN;
  PARSE_KIND_IDENTIFIER    = Parse.Common.PARSE_KIND_IDENTIFIER;
  PARSE_KIND_INTEGER       = Parse.Common.PARSE_KIND_INTEGER;
  PARSE_KIND_REAL          = Parse.Common.PARSE_KIND_REAL;
  PARSE_KIND_STRING        = Parse.Common.PARSE_KIND_STRING;
  PARSE_KIND_CHAR          = Parse.Common.PARSE_KIND_CHAR;
  PARSE_KIND_COMMENT_LINE  = Parse.Common.PARSE_KIND_COMMENT_LINE;
  PARSE_KIND_COMMENT_BLOCK = Parse.Common.PARSE_KIND_COMMENT_BLOCK;
  PARSE_KIND_DIRECTIVE     = Parse.Common.PARSE_KIND_DIRECTIVE;

  // Semantic attribute constants
  PARSE_ATTR_TYPE_KIND       = Parse.Common.PARSE_ATTR_TYPE_KIND;
  PARSE_ATTR_RESOLVED_SYMBOL = Parse.Common.PARSE_ATTR_RESOLVED_SYMBOL;
  PARSE_ATTR_DECL_NODE       = Parse.Common.PARSE_ATTR_DECL_NODE;
  PARSE_ATTR_STORAGE_CLASS   = Parse.Common.PARSE_ATTR_STORAGE_CLASS;
  PARSE_ATTR_SCOPE_NAME      = Parse.Common.PARSE_ATTR_SCOPE_NAME;
  PARSE_ATTR_CALL_RESOLVED   = Parse.Common.PARSE_ATTR_CALL_RESOLVED;
  PARSE_ATTR_COERCE_TO       = Parse.Common.PARSE_ATTR_COERCE_TO;

  // Build mode values
  bmExe          = Parse.Build.bmExe;
  bmLib          = Parse.Build.bmLib;
  bmDll          = Parse.Build.bmDll;

  // Optimize level values
  olDebug        = Parse.Build.olDebug;
  olReleaseSafe  = Parse.Build.olReleaseSafe;
  olReleaseFast  = Parse.Build.olReleaseFast;
  olReleaseSmall = Parse.Build.olReleaseSmall;

  // Target platform values
  tpWin64        = Parse.Build.tpWin64;
  tpLinux64      = Parse.Build.tpLinux64;

  // Subsystem type values
  stConsole      = Parse.Build.stConsole;
  stGUI          = Parse.Build.stGUI;

  // Error severity values
  esHint         = Parse.Utils.esHint;
  esWarning      = Parse.Utils.esWarning;
  esError        = Parse.Utils.esError;
  esFatal        = Parse.Utils.esFatal;

  // Source file values
  sfHeader       = Parse.Common.sfHeader;
  sfSource       = Parse.Common.sfSource;

  // Associativity values
  aoLeft         = Parse.Common.aoLeft;
  aoRight        = Parse.Common.aoRight;

type
  // ---- Type aliases --------------------------------------------------------
  // Every type a consumer needs is aliased here. Nobody touches internal units.

  // From System.Rtti
  TValue                     = System.Rtti.TValue;

  // From Parse.Utils
  TParseUtils                = Parse.Utils.TParseUtils;
  TParseErrorSeverity        = Parse.Utils.TParseErrorSeverity;
  TParseError                = Parse.Utils.TParseError;
  TParseErrors               = Parse.Utils.TParseErrors;
  TParseStatusCallback       = Parse.Utils.TParseStatusCallback;
  TParseCaptureConsoleCallback = Parse.Utils.TParseCaptureConsoleCallback;
  TParseOutputObject         = Parse.Utils.TParseOutputObject;

  // From Parse.Build
  TParseBuildMode            = Parse.Build.TParseBuildMode;
  TParseOptimizeLevel        = Parse.Build.TParseOptimizeLevel;
  TParseTargetPlatform       = Parse.Build.TParseTargetPlatform;
  TParseSubsystemType        = Parse.Build.TParseSubsystemType;

  // From Parse.Common — records and enums
  TParseToken                = Parse.Common.TParseToken;
  TParseAssociativity        = Parse.Common.TParseAssociativity;
  TParseSourceFile           = Parse.Common.TParseSourceFile;

  // From Parse.Common — base classes and concrete AST node
  TParseASTNodeBase          = Parse.Common.TParseASTNodeBase;
  TParseASTNode              = Parse.Common.TParseASTNode;
  TParseParserBase           = Parse.Common.TParseParserBase;
  TParseIRBase               = Parse.Common.TParseIRBase;
  TParseSemanticBase         = Parse.Common.TParseSemanticBase;

  // From Parse.Common — handler types
  TParseStatementHandler     = Parse.Common.TParseStatementHandler;
  TParsePrefixHandler        = Parse.Common.TParsePrefixHandler;
  TParseInfixHandler         = Parse.Common.TParseInfixHandler;
  TParseEmitHandler          = Parse.Common.TParseEmitHandler;
  TParseSemanticHandler      = Parse.Common.TParseSemanticHandler;
  TParseTypeCompatFunc       = Parse.Common.TParseTypeCompatFunc;

  // From Parse.LangConfig
  TParseNameMangler          = Parse.LangConfig.TParseNameMangler;
  TParseTypeToIR             = Parse.LangConfig.TParseTypeToIR;
  TParseExprToStringFunc     = Parse.Common.TParseExprToStringFunc;
  TParseExprOverride         = Parse.Common.TParseExprOverride;
  TParseLangConfig           = Parse.LangConfig.TParseLangConfig;

  // ---- TParse --------------------------------------------------------------

  { TParse }
  TParse = class(TParseOutputObject)
  private
    // Configuration
    FSourceFile:    string;
    FOutputPath:    string;
    FIncludePaths:  TList<string>;
    FSourceFiles:   TList<string>;
    FLibraryPaths:  TList<string>;
    FLinkLibraries: TList<string>;
    FTargetPlatform: TParseTargetPlatform;
    FSubsystem:     TParseSubsystemType;
    FOptimizeLevel: TParseOptimizeLevel;
    FBuildMode:     TParseBuildMode;
    FRawOutput:        Boolean;
    FLineDirectives:   Boolean;

    // Owned components
    FConfig:  TParseLangConfig;
    FBuild:   TParseBuild;
    FErrors:  TParseErrors;
    FOwnsErrors: Boolean;

    // State
    FProject: TParseASTNode;

    // Internal helpers
    function GetConfigPath(): string;
    function GetGeneratedPath(): string;

    {$HINTS OFF}
    function ResolvePath(const APath: string): string;
    {$HINTS ON}


  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Language definition — returns the owned config for fluent API access
    function Config(): TParseLangConfig;

    // Config persistence — uses FOutputPath/config/lang.toml
    procedure SaveLangConfig();
    procedure LoadLangConfig();

    // Source and output configuration
    procedure SetSourceFile(const AFilename: string);
    function  GetSourceFile(): string;
    procedure SetOutputPath(const APath: string);
    function  GetOutputPath(): string;

    // Build paths
    procedure AddIncludePath(const APath: string);
    procedure AddSourceFile(const ASourceFile: string);
    procedure AddLibraryPath(const APath: string);
    procedure AddLinkLibrary(const ALibrary: string);

    // Build configuration
    procedure SetTargetPlatform(const APlatform: TParseTargetPlatform);
    function  GetTargetPlatform(): TParseTargetPlatform;
    procedure SetOptimizeLevel(const ALevel: TParseOptimizeLevel);
    function  GetOptimizeLevel(): TParseOptimizeLevel;
    procedure SetSubsystem(const ASubsystem: TParseSubsystemType);
    function  GetSubsystem(): TParseSubsystemType;
    procedure SetBuildMode(const ABuildMode: TParseBuildMode);
    function  GetBuildMode(): TParseBuildMode;

    // Callbacks
    procedure SetRawOutput(const AValue: Boolean);
    procedure SetLineDirectives(const AEnabled: Boolean);
    procedure SetStatusCallback(const ACallback: TParseStatusCallback; const AUserData: Pointer = nil); override;

    // Error handling
    procedure SetErrors(const AErrors: TParseErrors);
    function  GetErrors(): TParseErrors;
    function  HasErrors(): Boolean;

    // Pipeline
    function  Compile(const ABuild: Boolean = True; const AAutoRun: Boolean = True): Boolean;
    function  Run(): Cardinal;
    procedure Clear();

    // Results
    function  GetProject(): TParseASTNode;
    function  GetOutputFilename(): string;
    function  GetLastExitCode(): Cardinal;
    function  GetVersionStr(): string;
  end;

implementation

{$R Parse.ResData.res}

const
  LANG_CONFIG_FILENAME = 'lang.toml';
  CONFIG_DIR_NAME      = 'config';
  GENERATED_DIR_NAME   = 'generated';

{ TParse }

constructor TParse.Create();
begin
  inherited Create();

  FSourceFile    := '';
  FOutputPath    := '';
  FTargetPlatform := tpWin64;
  FOptimizeLevel := olDebug;
  FSubsystem     := stConsole;
  FBuildMode     := bmExe;
  FRawOutput      := False;
  FLineDirectives := False;

  FIncludePaths  := TList<string>.Create();
  FSourceFiles   := TList<string>.Create();
  FLibraryPaths  := TList<string>.Create();
  FLinkLibraries := TList<string>.Create();

  FConfig := TParseLangConfig.Create();
  FBuild  := nil;
  FErrors := TParseErrors.Create();
  FOwnsErrors := True;
  FProject := nil;
end;

destructor TParse.Destroy();
begin
  Clear();

  FreeAndNil(FConfig);
  FreeAndNil(FIncludePaths);
  FreeAndNil(FSourceFiles);
  FreeAndNil(FLibraryPaths);
  FreeAndNil(FLinkLibraries);

  if FOwnsErrors then
    FreeAndNil(FErrors);

  inherited Destroy();
end;

// Internal helpers

function TParse.GetConfigPath(): string;
begin
  Result := TPath.Combine(FOutputPath, CONFIG_DIR_NAME);
end;

function TParse.GetGeneratedPath(): string;
begin
  Result := TPath.Combine(FOutputPath, GENERATED_DIR_NAME);
end;

function TParse.ResolvePath(const APath: string): string;
begin
  // If already absolute, return as-is; otherwise resolve relative to source file
  if TPath.IsPathRooted(APath) then
    Result := APath
  else if FSourceFile <> '' then
    Result := TPath.Combine(TPath.GetDirectoryName(FSourceFile), APath)
  else
    Result := TPath.GetFullPath(APath);
end;

// Language definition

function TParse.Config(): TParseLangConfig;
begin
  Result := FConfig;
end;

// Config persistence

procedure TParse.SaveLangConfig();
var
  LConfigPath: string;
begin
  if FOutputPath = '' then
    Exit;

  LConfigPath := GetConfigPath();
  TDirectory.CreateDirectory(LConfigPath);

  FConfig.SetConfigFilename(TPath.Combine(LConfigPath, LANG_CONFIG_FILENAME));
  FConfig.SaveConfig();
end;

procedure TParse.LoadLangConfig();
var
  LConfigFile: string;
begin
  if FOutputPath = '' then
    Exit;

  LConfigFile := TPath.Combine(GetConfigPath(), LANG_CONFIG_FILENAME);
  if not TFile.Exists(LConfigFile) then
    Exit;

  FConfig.SetConfigFilename(LConfigFile);
  FConfig.LoadConfig();
end;

// Source and output configuration

procedure TParse.SetSourceFile(const AFilename: string);
begin
  FSourceFile := AFilename;
end;

function TParse.GetSourceFile(): string;
begin
  Result := FSourceFile;
end;

procedure TParse.SetOutputPath(const APath: string);
begin
  FOutputPath := APath;
end;

function TParse.GetOutputPath(): string;
begin
  Result := FOutputPath;
end;

// Build paths

procedure TParse.AddIncludePath(const APath: string);
begin
  if (APath <> '') and (FIncludePaths.IndexOf(APath) < 0) then
    FIncludePaths.Add(APath);
end;

procedure TParse.AddSourceFile(const ASourceFile: string);
begin
  if (ASourceFile <> '') and (FSourceFiles.IndexOf(ASourceFile) < 0) then
    FSourceFiles.Add(ASourceFile);
end;

procedure TParse.AddLibraryPath(const APath: string);
begin
  if (APath <> '') and (FLibraryPaths.IndexOf(APath) < 0) then
    FLibraryPaths.Add(APath);
end;

procedure TParse.AddLinkLibrary(const ALibrary: string);
begin
  if (ALibrary <> '') and (FLinkLibraries.IndexOf(ALibrary) < 0) then
    FLinkLibraries.Add(ALibrary);
end;

// Build configuration

procedure TParse.SetTargetPlatform(const APlatform: TParseTargetPlatform);
begin
  FTargetPlatform := APlatform;
end;

function TParse.GetTargetPlatform(): TParseTargetPlatform;
begin
  Result := FTargetPlatform;
end;

procedure TParse.SetOptimizeLevel(const ALevel: TParseOptimizeLevel);
begin
  FOptimizeLevel := ALevel;
end;

function TParse.GetOptimizeLevel(): TParseOptimizeLevel;
begin
  Result := FOptimizeLevel;
end;

procedure TParse.SetSubsystem(const ASubsystem: TParseSubsystemType);
begin
  FSubsystem := ASubsystem;
  if FBuild <> nil then
    FBuild.SetSubsystem(ASubsystem);
end;

function TParse.GetSubsystem(): TParseSubsystemType;
begin
  if FBuild <> nil then
    Result := FBuild.GetSubsystem()
  else
    Result := FSubsystem;
end;

procedure TParse.SetBuildMode(const ABuildMode: TParseBuildMode);
begin
  FBuildMode := ABuildMode;
  if FBuild <> nil then
    FBuild.SetBuildMode(ABuildMode);
end;

function TParse.GetBuildMode(): TParseBuildMode;
begin
  if FBuild <> nil then
    Result := FBuild.GetBuildMode()
  else
    Result := FBuildMode;
end;

// Callbacks

procedure TParse.SetRawOutput(const AValue: Boolean);
begin
  FRawOutput := AValue;
end;

procedure TParse.SetLineDirectives(const AEnabled: Boolean);
begin
  FLineDirectives := AEnabled;
end;

procedure TParse.SetStatusCallback(const ACallback: TParseStatusCallback; const AUserData: Pointer);
begin
  inherited SetStatusCallback(ACallback, AUserData);
  if FBuild <> nil then
    FBuild.SetStatusCallback(ACallback, AUserData);
end;

// Error handling

procedure TParse.SetErrors(const AErrors: TParseErrors);
begin
  if FOwnsErrors then
    FreeAndNil(FErrors);

  FErrors := AErrors;
  FOwnsErrors := False;
end;

function TParse.GetErrors(): TParseErrors;
begin
  Result := FErrors;
end;

function TParse.HasErrors(): Boolean;
begin
  Result := (FErrors <> nil) and (FErrors.ErrorCount > 0);
end;

// Pipeline

procedure TParse.Clear();
begin
  FreeAndNil(FProject);
  FreeAndNil(FBuild);

  if FErrors <> nil then
    FErrors.Clear();
end;

function TParse.Compile(const ABuild: Boolean; const AAutoRun: Boolean): Boolean;
var
  LLexer:         TParseLexer;
  LParser:        TParseParser;
  LSemantics:     TParseSemantics;
  LCodeGen:       TParseCodeGen;
  LGeneratedPath: string;
  LProjectName:   string;
  LPath:          string;
begin
  Result := False;
  Clear();

  // Validate source file
  if FSourceFile = '' then
  begin
    if FErrors <> nil then
      FErrors.Add(esError, 'C000', 'No source file specified', []);
    Exit;
  end;

  if not TFile.Exists(FSourceFile) then
  begin
    if FErrors <> nil then
      FErrors.Add(esError, 'C000', 'Source file not found: %s', [FSourceFile]);
    Exit;
  end;

  // Default output path to source file directory if not set
  if FOutputPath = '' then
    FOutputPath := TPath.GetDirectoryName(FSourceFile);

  Status('Compiling %s', [TParseUtils.NormalizePath(TPath.GetFullPath(FSourceFile))]);

  // Create build object early so parser directives can route through it
  FBuild := TParseBuild.Create();
  FBuild.SetStatusCallback(FStatusCallback.Callback, FStatusCallback.UserData);
  FBuild.SetErrors(FErrors);
  FBuild.SetTarget(FTargetPlatform);
  FBuild.SetOptimizeLevel(FOptimizeLevel);
  FBuild.SetSubsystem(FSubsystem);
  FBuild.SetBuildMode(FBuildMode);

  // Set subsystem defines so $ifdef works
  if FSubsystem = stGUI then
  begin
    FBuild.RemoveDefine('CONSOLE_APP');
    FBuild.SetDefine('GUI_APP');
  end
  else
  begin
    FBuild.RemoveDefine('GUI_APP');
    FBuild.SetDefine('CONSOLE_APP');
  end;

  // Add generated path to include paths
  AddIncludePath(GetGeneratedPath());

  // Step 1: Lexer
  LLexer := TParseLexer.Create();
  try
    LLexer.SetStatusCallback(FStatusCallback.Callback, FStatusCallback.UserData);
    LLexer.SetErrors(FErrors);
    LLexer.SetConfig(FConfig);

    if not LLexer.LoadFromFile(FSourceFile) then
      Exit;

    if not LLexer.Tokenize() then
      Exit;

    // Step 2: Parser
    LParser := TParseParser.Create();
    try
      LParser.SetStatusCallback(FStatusCallback.Callback, FStatusCallback.UserData);
      LParser.SetErrors(FErrors);
      LParser.SetConfig(FConfig);

      if not LParser.LoadFromLexer(LLexer) then
        Exit;

      FProject := LParser.ParseTokens();
      if FProject = nil then
        Exit;

      if HasErrors() then
        Exit;

    finally
      LParser.Free();
    end;
  finally
    LLexer.Free();
  end;

  // Step 3: Semantic analysis
  LSemantics := TParseSemantics.Create();
  try
    LSemantics.SetStatusCallback(FStatusCallback.Callback, FStatusCallback.UserData);
    LSemantics.SetErrors(FErrors);
    LSemantics.SetConfig(FConfig);

    if not LSemantics.Analyze(FProject) then
      Exit;

    if HasErrors() then
      Exit;

    // Step 4: Code generation
    LGeneratedPath := GetGeneratedPath();
    TDirectory.CreateDirectory(LGeneratedPath);

    LCodeGen := TParseCodeGen.Create();
    try
      LCodeGen.SetStatusCallback(FStatusCallback.Callback, FStatusCallback.UserData);
      LCodeGen.SetErrors(FErrors);
      LCodeGen.SetConfig(FConfig);
      LCodeGen.SetLineDirectives(FLineDirectives);

      if not LCodeGen.Generate(FProject) then
        Exit;

      // Save generated .h/.cpp to output/generated/
      LProjectName := TPath.GetFileNameWithoutExtension(FSourceFile);
      LCodeGen.SaveToFiles(
        TPath.Combine(LGeneratedPath, LProjectName + '.h'),
        TPath.Combine(LGeneratedPath, LProjectName + '.cpp')
      );
    finally
      LCodeGen.Free();
    end;
  finally
    LSemantics.Free();
  end;

  // Check for codegen errors before building
  if HasErrors() then
    Exit;

  // Skip Zig build if caller only wants codegen (e.g. compiling a unit dependency)
  if not ABuild then
  begin
    Result := True;
    Exit;
  end;

  // Step 5: Build via Zig
  FBuild.SetOutputCallback(FOutput.Callback, FOutput.UserData);
  FBuild.SetRawOutput(FRawOutput);
  FBuild.SetOutputPath(FOutputPath);
  FBuild.SetProjectName(LProjectName);

  // Add generated source to build
  FBuild.AddSourceFile(TPath.Combine(LGeneratedPath, LProjectName + '.cpp'));
  FBuild.AddIncludePath(LGeneratedPath);

  // Wire configured paths into build
  for LPath in FIncludePaths do
    FBuild.AddIncludePath(LPath);

  for LPath in FSourceFiles do
    FBuild.AddSourceFile(LPath);

  for LPath in FLibraryPaths do
    FBuild.AddLibraryPath(LPath);

  for LPath in FLinkLibraries do
    FBuild.AddLinkLibrary(LPath);

  // Sync build settings — directives during parsing may have changed them
  FTargetPlatform := FBuild.GetTarget();
  FOptimizeLevel  := FBuild.GetOptimizeLevel();
  FSubsystem      := FBuild.GetSubsystem();

  // Generate build.zig and compile
  if not FBuild.SaveBuildFile() then
  begin
    Status('Failed to create build.zig');
    Exit;
  end;

  if not FBuild.Process(False) then
    Exit;

  // Run only if requested
  if AAutoRun then
  begin
    if not FBuild.Run() then
      Exit;
  end;

  Result := True;
end;

function TParse.Run(): Cardinal;
begin
  Result := 0;
  if FBuild <> nil then
  begin
    FBuild.Run();
    Result := FBuild.GetLastExitCode();
  end;
end;

// Results

function TParse.GetProject(): TParseASTNode;
begin
  Result := FProject;
end;

function TParse.GetOutputFilename(): string;
begin
  Result := '';
  if FBuild <> nil then
    Result := FBuild.GetOutputFilename();
end;

function TParse.GetLastExitCode(): Cardinal;
begin
  Result := 0;
  if FBuild <> nil then
    Result := FBuild.GetLastExitCode();
end;

function TParse.GetVersionStr(): string;
begin
  Result := PARSE_VERSION_STR;
end;

end.
