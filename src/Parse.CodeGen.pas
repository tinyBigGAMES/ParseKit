{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

unit Parse.CodeGen;

{$I Parse.Defines.inc}

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Parse.Utils,
  Parse.Resources,
  Parse.Common,
  Parse.LangConfig,
  Parse.IR;

type

  { TParseCodeGen }
  TParseCodeGen = class(TParseCodeGenBase)
  private
    // Keyed by unit name — each entry is an owned TParseIR with its own
    // header + source buffers. Single-unit mode uses the key 'default'.
    FUnits:     TObjectDictionary<string, TParseIR>;

    // Preserves the order in which units were emitted. SaveAllFiles()
    // writes them in this order so dependencies appear before dependents.
    FUnitOrder: TStringList;

    // Points to whichever TParseIR is currently being written to.
    // Set by GenerateUnit() before walking the AST. Not owned separately.
    FCurrentIR: TParseIR;

    // Language config — not owned. Passed through to each TParseIR.
    FConfig:    TParseLangConfig;

    // Creates a new TParseIR for AUnitName, wires errors + config,
    // registers it in FUnits + FUnitOrder, and sets FCurrentIR.
    // Returns the new IR instance.
    function AcquireIR(const AUnitName: string): TParseIR;

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Configuration — must be set before Generate() / GenerateUnit()
    procedure SetConfig(const AConfig: TParseLangConfig);

    // ---- Single-unit path ----

    // TParseCodeGenBase override. Creates IR under 'default', walks tree.
    // Equivalent to GenerateUnit('default', ARoot).
    function Generate(const ARoot: TParseASTNodeBase): Boolean; override;

    // Single-unit output convenience — reads the 'default' IR
    procedure SaveToFiles(const AHeaderPath, ASourcePath: string);
    function GetHeaderContent(): string;
    function GetSourceContent(): string;

    // ---- Multi-unit path ----

    // Process one unit's AST. Call once per unit in dependency order.
    // If AUnitName was already emitted, the call is silently skipped
    // (returns True). Returns False on error.
    function GenerateUnit(const AUnitName: string;
      const ARoot: TParseASTNodeBase): Boolean;

    // Write every unit's .h + .cpp pair into AOutputDir.
    // Files are named AUnitName.h and AUnitName.cpp.
    // Written in dependency order (the order GenerateUnit was called).
    procedure SaveAllFiles(const AOutputDir: string);

    // ---- Access ----

    // Returns the IR for a given unit name, or nil if not found
    function GetIR(const AUnitName: string): TParseIR;

    // Returns the IR currently being written to (set by GenerateUnit)
    function GetCurrentIR(): TParseIR;

    // Number of units emitted so far
    function GetUnitCount(): Integer;

    // Unit name by emission order index (0-based)
    function GetUnitNameByIndex(const AIndex: Integer): string;

    // True if a unit with this name has already been emitted
    function HasUnit(const AUnitName: string): Boolean;

    // Debug
    function Dump(const AId: Integer = 0): string; override;
  end;

implementation

const
  // Default unit name for the single-unit Generate() path
  DEFAULT_UNIT_NAME = 'default';

{ TParseCodeGen }

constructor TParseCodeGen.Create();
begin
  inherited;
  FUnits     := TObjectDictionary<string, TParseIR>.Create([doOwnsValues]);
  FUnitOrder := TStringList.Create();
  FCurrentIR := nil;
  FConfig    := nil;
end;

destructor TParseCodeGen.Destroy();
begin
  FCurrentIR := nil;
  FConfig    := nil;
  FreeAndNil(FUnitOrder);
  FreeAndNil(FUnits);
  inherited;
end;

procedure TParseCodeGen.SetConfig(const AConfig: TParseLangConfig);
begin
  FConfig := AConfig;
end;

function TParseCodeGen.AcquireIR(const AUnitName: string): TParseIR;
var
  LIR:     TParseIR;
  LErrors: TParseErrors;
begin
  LIR := TParseIR.Create();

  // Wire shared errors so IR validation failures surface to the caller
  LErrors := GetErrors();
  if LErrors <> nil then
    LIR.SetErrors(LErrors);

  // Wire language config so IR can dispatch emit handlers
  if FConfig <> nil then
    LIR.SetConfig(FConfig);

  // Register and track
  FUnits.Add(AUnitName, LIR);
  FUnitOrder.Add(AUnitName);

  // Set as current
  FCurrentIR := LIR;

  Result := LIR;
end;

// ---- Single-unit path ----

function TParseCodeGen.Generate(
  const ARoot: TParseASTNodeBase): Boolean;
begin
  // Report the filename so the user can see what is being compiled to C++23
  if ARoot <> nil then
    Status('Generating code for %s...', [ARoot.GetToken().Filename])
  else
    Status('Generating code...');
  Result := GenerateUnit(DEFAULT_UNIT_NAME, ARoot);
end;

procedure TParseCodeGen.SaveToFiles(const AHeaderPath,
  ASourcePath: string);
var
  LIR: TParseIR;
begin
  LIR := GetIR(DEFAULT_UNIT_NAME);
  if LIR <> nil then
    LIR.SaveToFiles(AHeaderPath, ASourcePath);
end;

function TParseCodeGen.GetHeaderContent(): string;
var
  LIR: TParseIR;
begin
  LIR := GetIR(DEFAULT_UNIT_NAME);
  if LIR <> nil then
    Result := LIR.GetHeaderContent()
  else
    Result := '';
end;

function TParseCodeGen.GetSourceContent(): string;
var
  LIR: TParseIR;
begin
  LIR := GetIR(DEFAULT_UNIT_NAME);
  if LIR <> nil then
    Result := LIR.GetSourceContent()
  else
    Result := '';
end;

// ---- Multi-unit path ----

function TParseCodeGen.GenerateUnit(const AUnitName: string;
  const ARoot: TParseASTNodeBase): Boolean;
var
  LErrors: TParseErrors;
  LIR:     TParseIR;
begin
  Result := False;
  LErrors := GetErrors();

  // Validate unit name
  if AUnitName = '' then
  begin
    if LErrors <> nil then
      LErrors.Add(esError, ERR_CODEGEN_EMPTY_UNIT, RSCodeGenEmptyUnit);
    Exit;
  end;

  // Deduplicate — if this unit was already emitted, skip silently
  if FUnits.ContainsKey(AUnitName) then
  begin
    Result := True;
    Exit;
  end;

  // Validate AST root
  if ARoot = nil then
  begin
    if LErrors <> nil then
      LErrors.Add(esError, ERR_CODEGEN_NIL_ROOT, RSCodeGenNilRoot);
    Exit;
  end;

  // Validate config
  if FConfig = nil then
  begin
    if LErrors <> nil then
      LErrors.Add(esError, ERR_CODEGEN_NO_CONFIG, RSCodeGenNoConfig);
    Exit;
  end;

  // Create the IR for this unit and walk the AST
  LIR := AcquireIR(AUnitName);
  Result := LIR.Generate(ARoot);
end;

procedure TParseCodeGen.SaveAllFiles(const AOutputDir: string);
var
  LI:         Integer;
  LUnitName:  string;
  LIR:        TParseIR;
  LHeaderPath: string;
  LSourcePath: string;
begin
  // Ensure output directory exists (creates full chain)
  if AOutputDir <> '' then
    TParseUtils.CreateDirInPath(AOutputDir);

  // Write each unit in dependency order
  for LI := 0 to FUnitOrder.Count - 1 do
  begin
    LUnitName := FUnitOrder[LI];
    if FUnits.TryGetValue(LUnitName, LIR) then
    begin
      LHeaderPath := TPath.Combine(AOutputDir, LUnitName + '.h');
      LSourcePath := TPath.Combine(AOutputDir, LUnitName + '.cpp');
      LIR.SaveToFiles(LHeaderPath, LSourcePath);
    end;
  end;
end;

// ---- Access ----

function TParseCodeGen.GetIR(const AUnitName: string): TParseIR;
begin
  if not FUnits.TryGetValue(AUnitName, Result) then
    Result := nil;
end;

function TParseCodeGen.GetCurrentIR(): TParseIR;
begin
  Result := FCurrentIR;
end;

function TParseCodeGen.GetUnitCount(): Integer;
begin
  Result := FUnitOrder.Count;
end;

function TParseCodeGen.GetUnitNameByIndex(
  const AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FUnitOrder.Count) then
    Result := FUnitOrder[AIndex]
  else
    Result := '';
end;

function TParseCodeGen.HasUnit(const AUnitName: string): Boolean;
begin
  Result := FUnits.ContainsKey(AUnitName);
end;

// ---- Debug ----

function TParseCodeGen.Dump(const AId: Integer): string;
var
  LI:        Integer;
  LUnitName: string;
  LIR:       TParseIR;
begin
  Result := '';
  for LI := 0 to FUnitOrder.Count - 1 do
  begin
    LUnitName := FUnitOrder[LI];
    if FUnits.TryGetValue(LUnitName, LIR) then
    begin
      Result := Result +
        '=== UNIT: ' + LUnitName + ' ===' + sLineBreak +
        LIR.Dump(AId) + sLineBreak;
    end;
  end;
end;

end.
