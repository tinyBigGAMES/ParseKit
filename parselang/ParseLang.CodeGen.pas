{===============================================================================
  Parse()™ - Compiler Construction Toolkit
  ParseLang — .parse meta-language code generation (interpreter + config builder)

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

(*
  ParseLang.CodeGen — CodeGen for the .parse Meta-Language

  Rather than emitting C++23 text, emitters registered here walk the .parse
  AST and drive a second TParse instance (ACustomParse) by calling Config()
  methods on it directly. The output is a live, fully configured TParse object
  in memory — not a file on disk.

  TWO-PHASE EXECUTION
  -------------------
  Phase 1 — .parse processing (ConfigCodeGen + AParse.Compile()):
    Lexer/structural sections → call ACustomParse.Config() methods immediately.
    Grammar/semantic/emit rules → register closures that CAPTURE block AST nodes.

  Phase 2 — Source file compilation (ACustomParse.Compile()):
    Captured closures fire. Each creates a TParseScriptInterp, populates the
    environment with implicit variables, and executes the block body AST.

  THE INTERPRETER (TParseScriptInterp)
  A lightweight tree-walking interpreter for the .parse scripting language.
  Supports: variables, if/while/for-in/repeat, function calls.
  Values: string, int, bool, node, token, nil.
  Built-ins are context-dispatched (parse / semantic / emit / exproverride).
  Helper functions recursively instantiate a child interpreter.

  SHARED STATE LIFETIME
  Helper function nodes and typemap entries must survive Phase 1 into Phase 2.
  IParseScriptStore is reference-counted and captured by all closures; freed
  automatically when all closures are freed with the custom config.
*)

unit ParseLang.CodeGen;

{$I ..\src\Parse.Defines.inc}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Parse,
  ParseLang.Common;

procedure ConfigCodeGen(
  const AParse:       TParse;
  const ACustomParse: TParse;
  const APipeline:    TParseLangPipelineCallbacks);

implementation

uses
  System.Rtti,
  Parse.Common;

// =========================================================================
// SCRIPT VALUE
// =========================================================================

type

  TScriptValueKind = (
    svkNil,
    svkInt,
    svkBool,
    svkString,
    svkNode,
    svkToken
  );

  TScriptValue = record
    Kind:    TScriptValueKind;
    IntVal:  Int64;
    BoolVal: Boolean;
    StrVal:  string;
    NodeVal: TParseASTNodeBase;
    TokVal:  TParseToken;
  end;

// =========================================================================
// CONTEXT KIND
// =========================================================================

type

  TScriptContextKind = (
    sckNone,
    sckParse,
    sckSemantic,
    sckEmit,
    sckExprOverride
  );

// =========================================================================
// SHARED STATE STORE
// =========================================================================

type

  IParseScriptStore = interface
    ['{A3F8C214-7B1E-4D5A-9C2F-0E6D3A817B45}']
    function GetHelperFuncs(): TDictionary<string, TParseASTNodeBase>;
    function GetTypeMap():     TDictionary<string, string>;
  end;

  TParseScriptStore = class(TInterfacedObject, IParseScriptStore)
  private
    FHelperFuncs: TDictionary<string, TParseASTNodeBase>;
    FTypeMap:     TDictionary<string, string>;
  public
    constructor Create();
    destructor  Destroy(); override;
    function GetHelperFuncs(): TDictionary<string, TParseASTNodeBase>;
    function GetTypeMap():     TDictionary<string, string>;
  end;

// =========================================================================
// INTERPRETER
// =========================================================================

type

  TParseScriptInterp = class
  private
    FContextKind:     TScriptContextKind;
    FCustomConfig:    TParseLangConfig;
    FStore:           IParseScriptStore;
    FPipeline:        TParseLangPipelineCallbacks;
    FNodeKindForRule: string;
    FEnv:             TDictionary<string, TScriptValue>;
    // Phase-2 context objects
    FParser:      TParseParserBase;
    FLeftNode:    TParseASTNodeBase;
    FSemantic:    TParseSemanticBase;
    FIR:          TParseIRBase;
    FExprDefault: TParseExprToStringFunc;

    function MakeInt(const AValue: Int64): TScriptValue;
    function MakeBool(const AValue: Boolean): TScriptValue;
    function MakeStr(const AValue: string): TScriptValue;
    function MakeNode(const AValue: TParseASTNodeBase): TScriptValue;
    function MakeTok(const AValue: TParseToken): TScriptValue;
    function MakeNil(): TScriptValue;

    function ResolveStr(const AVal: TScriptValue): string;
    function ResolveInt(const AVal: TScriptValue): Int64;
    function ResolveBool(const AVal: TScriptValue): Boolean;
    function IsSfSentinel(const AVal: TScriptValue): Boolean;
    function ToSf(const AVal: TScriptValue;
      const ADefault: TParseSourceFile = sfSource): TParseSourceFile;

    procedure ExecStmt(const AStmt: TParseASTNodeBase);
    function  EvalExpr(const AExpr: TParseASTNodeBase): TScriptValue;
    function  EvalBinary(const AOp: string;
      const ALeft, ARight: TScriptValue): TScriptValue;
    function  EvalField(const ABase: TScriptValue;
      const AField: string): TScriptValue;

    function CallBuiltin(const AName: string;
      const AArgs: TArray<TScriptValue>): TScriptValue;
    function CallBuiltinCommon(const AName: string;
      const AArgs: TArray<TScriptValue>;
      out AResult: TScriptValue): Boolean;
    function CallBuiltinParse(const AName: string;
      const AArgs: TArray<TScriptValue>;
      out AResult: TScriptValue): Boolean;
    function CallBuiltinSemantic(const AName: string;
      const AArgs: TArray<TScriptValue>;
      out AResult: TScriptValue): Boolean;
    function CallBuiltinEmit(const AName: string;
      const AArgs: TArray<TScriptValue>;
      out AResult: TScriptValue): Boolean;
    function CallHelper(const AName: string;
      const AArgs: TArray<TScriptValue>): TScriptValue;

  public
    constructor Create(
      const ACustomConfig:    TParseLangConfig;
      const AStore:           IParseScriptStore;
      const APipeline:        TParseLangPipelineCallbacks;
      const ANodeKindForRule: string);
    destructor Destroy(); override;

    procedure SetParseContext(const AParser: TParseParserBase;
      const ALeft: TParseASTNodeBase);
    procedure SetSemanticContext(const ASemantic: TParseSemanticBase;
      const ANode: TParseASTNodeBase);
    procedure SetEmitContext(const AIR: TParseIRBase;
      const ANode: TParseASTNodeBase);
    procedure SetExprOverrideContext(const ANode: TParseASTNodeBase;
      const ADefault: TParseExprToStringFunc);
    procedure InheritContext(const AParent: TParseScriptInterp);

    procedure ExecBlock(const ABlock: TParseASTNodeBase);

    function GetResultNode():  TParseASTNodeBase;
    function GetResultValue(): TScriptValue;
  end;

// =========================================================================
// UTILITIES
// =========================================================================

function StripQuotes(const AText: string): string;
var
  LInner: string;
begin
  if (Length(AText) >= 2) and (AText[1] = #39) and
     (AText[Length(AText)] = #39) then
  begin
    LInner := Copy(AText, 2, Length(AText) - 2);
    Result := LInner.Replace(#39#39, #39);
  end
  else
    Result := AText;
end;

function FormatArgs(const ATemplate: string;
  const AArgs: TArray<string>): string;
var
  LResult: string;
  LI:      Integer;
  LPos:    Integer;
begin
  LResult := ATemplate;
  for LI := 0 to High(AArgs) do
  begin
    LPos := Pos('%s', LResult);
    if LPos <= 0 then LPos := Pos('%d', LResult);
    if LPos <= 0 then LPos := Pos('%f', LResult);
    if LPos > 0 then
      LResult := Copy(LResult, 1, LPos - 1) + AArgs[LI] +
                 Copy(LResult, LPos + 2, MaxInt);
  end;
  Result := LResult;
end;

// =========================================================================
// TParseScriptStore
// =========================================================================

constructor TParseScriptStore.Create();
begin
  inherited Create();
  FHelperFuncs := TDictionary<string, TParseASTNodeBase>.Create();
  FTypeMap     := TDictionary<string, string>.Create();
end;

destructor TParseScriptStore.Destroy();
begin
  FreeAndNil(FHelperFuncs);
  FreeAndNil(FTypeMap);
  inherited Destroy();
end;

function TParseScriptStore.GetHelperFuncs(): TDictionary<string, TParseASTNodeBase>;
begin
  Result := FHelperFuncs;
end;

function TParseScriptStore.GetTypeMap(): TDictionary<string, string>;
begin
  Result := FTypeMap;
end;

// =========================================================================
// TParseScriptInterp — Create / Destroy
// =========================================================================

constructor TParseScriptInterp.Create(
  const ACustomConfig:    TParseLangConfig;
  const AStore:           IParseScriptStore;
  const APipeline:        TParseLangPipelineCallbacks;
  const ANodeKindForRule: string);
begin
  inherited Create();
  FCustomConfig    := ACustomConfig;
  FStore           := AStore;
  FPipeline        := APipeline;
  FNodeKindForRule := ANodeKindForRule;
  FContextKind     := sckNone;
  FParser          := nil;
  FLeftNode        := nil;
  FSemantic        := nil;
  FIR              := nil;
  FExprDefault     := nil;
  FEnv             := TDictionary<string, TScriptValue>.Create();
  FEnv.AddOrSetValue('result', MakeNil());
end;

destructor TParseScriptInterp.Destroy();
begin
  FreeAndNil(FEnv);
  inherited Destroy();
end;

// =========================================================================
// Context Setup
// =========================================================================

procedure TParseScriptInterp.SetParseContext(const AParser: TParseParserBase;
  const ALeft: TParseASTNodeBase);
begin
  FContextKind := sckParse;
  FParser      := AParser;
  FLeftNode    := ALeft;
  if ALeft <> nil then
    FEnv.AddOrSetValue('left', MakeNode(ALeft));
end;

procedure TParseScriptInterp.SetSemanticContext(
  const ASemantic: TParseSemanticBase; const ANode: TParseASTNodeBase);
begin
  FContextKind := sckSemantic;
  FSemantic    := ASemantic;
  FEnv.AddOrSetValue('node', MakeNode(ANode));
end;

procedure TParseScriptInterp.SetEmitContext(const AIR: TParseIRBase;
  const ANode: TParseASTNodeBase);
begin
  FContextKind := sckEmit;
  FIR          := AIR;
  FEnv.AddOrSetValue('node',   MakeNode(ANode));
  FEnv.AddOrSetValue('target', MakeStr('__parse_target__'));
end;

procedure TParseScriptInterp.SetExprOverrideContext(
  const ANode: TParseASTNodeBase; const ADefault: TParseExprToStringFunc);
begin
  FContextKind := sckExprOverride;
  FExprDefault := ADefault;
  FEnv.AddOrSetValue('node',   MakeNode(ANode));
  FEnv.AddOrSetValue('target', MakeStr('__parse_target__'));
end;

procedure TParseScriptInterp.InheritContext(const AParent: TParseScriptInterp);
begin
  FContextKind := AParent.FContextKind;
  FParser      := AParent.FParser;
  FLeftNode    := AParent.FLeftNode;
  FSemantic    := AParent.FSemantic;
  FIR          := AParent.FIR;
  FExprDefault := AParent.FExprDefault;
end;

// =========================================================================
// Value Constructors
// =========================================================================

function TParseScriptInterp.MakeInt(const AValue: Int64): TScriptValue;
begin
  Result.Kind    := svkInt;
  Result.IntVal  := AValue;
  Result.BoolVal := False;
  Result.StrVal  := '';
  Result.NodeVal := nil;
end;

function TParseScriptInterp.MakeBool(const AValue: Boolean): TScriptValue;
begin
  Result.Kind    := svkBool;
  Result.BoolVal := AValue;
  Result.IntVal  := 0;
  Result.StrVal  := '';
  Result.NodeVal := nil;
end;

function TParseScriptInterp.MakeStr(const AValue: string): TScriptValue;
begin
  Result.Kind    := svkString;
  Result.StrVal  := AValue;
  Result.IntVal  := 0;
  Result.BoolVal := False;
  Result.NodeVal := nil;
end;

function TParseScriptInterp.MakeNode(
  const AValue: TParseASTNodeBase): TScriptValue;
begin
  Result.Kind    := svkNode;
  Result.NodeVal := AValue;
  Result.IntVal  := 0;
  Result.BoolVal := False;
  Result.StrVal  := '';
end;

function TParseScriptInterp.MakeTok(const AValue: TParseToken): TScriptValue;
begin
  Result.Kind    := svkToken;
  Result.TokVal  := AValue;
  Result.IntVal  := 0;
  Result.BoolVal := False;
  Result.StrVal  := '';
  Result.NodeVal := nil;
end;

function TParseScriptInterp.MakeNil(): TScriptValue;
begin
  Result.Kind    := svkNil;
  Result.IntVal  := 0;
  Result.BoolVal := False;
  Result.StrVal  := '';
  Result.NodeVal := nil;
end;

// =========================================================================
// Value Coercion
// =========================================================================

function TParseScriptInterp.ResolveStr(const AVal: TScriptValue): string;
begin
  if AVal.Kind = svkString then
    Result := AVal.StrVal
  else if AVal.Kind = svkInt then
    Result := IntToStr(AVal.IntVal)
  else if AVal.Kind = svkBool then
  begin
    if AVal.BoolVal then Result := 'true' else Result := 'false';
  end
  else
    Result := '';
end;

function TParseScriptInterp.ResolveInt(const AVal: TScriptValue): Int64;
begin
  if AVal.Kind = svkInt then
    Result := AVal.IntVal
  else if AVal.Kind = svkString then
    Result := StrToInt64Def(AVal.StrVal, 0)
  else if AVal.Kind = svkBool then
  begin
    if AVal.BoolVal then Result := 1 else Result := 0;
  end
  else
    Result := 0;
end;

function TParseScriptInterp.ResolveBool(const AVal: TScriptValue): Boolean;
begin
  if AVal.Kind = svkBool then
    Result := AVal.BoolVal
  else if AVal.Kind = svkInt then
    Result := AVal.IntVal <> 0
  else if AVal.Kind = svkString then
    Result := AVal.StrVal <> ''
  else if AVal.Kind = svkNode then
    Result := AVal.NodeVal <> nil
  else
    Result := False;
end;

function TParseScriptInterp.IsSfSentinel(const AVal: TScriptValue): Boolean;
begin
  Result := (AVal.Kind = svkString) and
            ((AVal.StrVal = 'target.source') or
             (AVal.StrVal = 'target.header'));
end;

function TParseScriptInterp.ToSf(const AVal: TScriptValue;
  const ADefault: TParseSourceFile): TParseSourceFile;
begin
  if (AVal.Kind = svkString) and (AVal.StrVal = 'target.header') then
    Result := sfHeader
  else
    Result := ADefault;
end;

// =========================================================================
// ExecBlock / ExecStmt
// =========================================================================

procedure TParseScriptInterp.ExecBlock(const ABlock: TParseASTNodeBase);
var
  LI: Integer;
begin
  if ABlock = nil then Exit;
  if ABlock.GetNodeKind() = 'stmt.block' then
  begin
    for LI := 0 to ABlock.ChildCount() - 1 do
      ExecStmt(ABlock.GetChild(LI));
  end
  else
    ExecStmt(ABlock);
end;

procedure TParseScriptInterp.ExecStmt(const AStmt: TParseASTNodeBase);
var
  LKind:        string;
  LAttr:        TValue;
  LTarget:      string;
  LCondVal:     TScriptValue;
  LIter:        TScriptValue;
  LI:           Integer;
  LBranch:      TParseASTNodeBase;
  LBranchKind:  string;
  LCondNode:    TParseASTNodeBase;
  LBodyNode:    TParseASTNodeBase;
  LVarName:     string;
  LArgs:        TArray<TScriptValue>;
  LCallName:    string;
begin
  if AStmt = nil then Exit;
  LKind := AStmt.GetNodeKind();

  if LKind = 'stmt.assign' then
  begin
    AStmt.GetAttr('assign.target', LAttr);
    LTarget := LAttr.AsString;
    FEnv.AddOrSetValue(LTarget, EvalExpr(AStmt.GetChild(0)));
  end
  else if LKind = 'stmt.call_stmt' then
  begin
    AStmt.GetAttr('call.name', LAttr);
    LCallName := LAttr.AsString;
    SetLength(LArgs, AStmt.ChildCount());
    for LI := 0 to AStmt.ChildCount() - 1 do
      LArgs[LI] := EvalExpr(AStmt.GetChild(LI));
    CallBuiltin(LCallName, LArgs);
  end
  else if LKind = 'stmt.if' then
  begin
    for LI := 0 to AStmt.ChildCount() - 1 do
    begin
      LBranch     := AStmt.GetChild(LI);
      LBranchKind := LBranch.GetNodeKind();
      if LBranchKind = 'stmt.if_branch' then
      begin
        LCondNode := LBranch.GetChild(0);
        LBodyNode := LBranch.GetChild(1);
        LCondVal  := EvalExpr(LCondNode);
        if ResolveBool(LCondVal) then
        begin
          ExecBlock(LBodyNode);
          Exit;
        end;
      end
      else if LBranchKind = 'stmt.else_branch' then
      begin
        ExecBlock(LBranch.GetChild(0));
        Exit;
      end;
    end;
  end
  else if LKind = 'stmt.while' then
  begin
    LCondNode := AStmt.GetChild(0);
    LBodyNode := AStmt.GetChild(1);
    LCondVal  := EvalExpr(LCondNode);
    while ResolveBool(LCondVal) do
    begin
      ExecBlock(LBodyNode);
      LCondVal := EvalExpr(LCondNode);
    end;
  end
  else if LKind = 'stmt.for_in' then
  begin
    AStmt.GetAttr('for.var', LAttr);
    LVarName  := LAttr.AsString;
    LIter     := EvalExpr(AStmt.GetChild(0));
    LBodyNode := AStmt.GetChild(1);
    for LI := 0 to ResolveInt(LIter) - 1 do
    begin
      FEnv.AddOrSetValue(LVarName, MakeInt(LI));
      ExecBlock(LBodyNode);
    end;
  end
  else if LKind = 'stmt.repeat' then
  begin
    LBodyNode := AStmt.GetChild(0);
    LCondNode := AStmt.GetChild(1);
    repeat
      ExecBlock(LBodyNode);
      LCondVal := EvalExpr(LCondNode);
    until ResolveBool(LCondVal);
  end
  else if LKind = 'stmt.block' then
    ExecBlock(AStmt);
end;

// =========================================================================
// EvalExpr
// =========================================================================

function TParseScriptInterp.EvalExpr(
  const AExpr: TParseASTNodeBase): TScriptValue;
var
  LKind:      string;
  LAttr:      TValue;
  LName:      string;
  LArgs:      TArray<TScriptValue>;
  LI:         Integer;
  LBase:      TScriptValue;
  LIndexInt:  Integer;
  LStr:       string;
  LBoolAttr:  TValue;
begin
  Result := MakeNil();
  if AExpr = nil then Exit;
  LKind := AExpr.GetNodeKind();

  if LKind = 'expr.literal_int' then
    Result := MakeInt(StrToInt64Def(AExpr.GetToken().Text, 0))
  else if LKind = 'expr.literal_str' then
    Result := MakeStr(StripQuotes(AExpr.GetToken().Text))
  else if LKind = 'expr.literal_regex' then
    Result := MakeStr(AExpr.GetToken().Text)
  else if LKind = 'expr.literal_bool' then
  begin
    AExpr.GetAttr('bool.value', LBoolAttr);
    Result := MakeBool(LBoolAttr.AsType<Boolean>);
  end
  else if LKind = 'expr.literal_nil' then
    Result := MakeNil()
  else if LKind = 'expr.ident' then
  begin
    AExpr.GetAttr('ident.name', LAttr);
    LName := LAttr.AsString;
    if not FEnv.TryGetValue(LName, Result) then
      Result := MakeNil();
  end
  else if LKind = 'expr.field' then
  begin
    LBase := EvalExpr(AExpr.GetChild(0));
    AExpr.GetAttr('field.name', LAttr);
    Result := EvalField(LBase, LAttr.AsString);
  end
  else if LKind = 'expr.index' then
  begin
    LBase     := EvalExpr(AExpr.GetChild(0));
    LIndexInt := Integer(ResolveInt(EvalExpr(AExpr.GetChild(1))));
    LStr      := ResolveStr(LBase);
    if (LIndexInt >= 1) and (LIndexInt <= Length(LStr)) then
      Result := MakeStr(LStr[LIndexInt])
    else
      Result := MakeStr('');
  end
  else if LKind = 'expr.call' then
  begin
    AExpr.GetAttr('call.name', LAttr);
    LName := LAttr.AsString;
    SetLength(LArgs, AExpr.ChildCount());
    for LI := 0 to AExpr.ChildCount() - 1 do
      LArgs[LI] := EvalExpr(AExpr.GetChild(LI));
    Result := CallBuiltin(LName, LArgs);
  end
  else if LKind = 'expr.binary' then
  begin
    AExpr.GetAttr('op', LAttr);
    Result := EvalBinary(LAttr.AsString,
      EvalExpr(AExpr.GetChild(0)), EvalExpr(AExpr.GetChild(1)));
  end
  else if LKind = 'expr.unary' then
  begin
    AExpr.GetAttr('op', LAttr);
    LBase := EvalExpr(AExpr.GetChild(0));
    if LAttr.AsString = 'not' then
      Result := MakeBool(not ResolveBool(LBase))
    else if LAttr.AsString = '-' then
      Result := MakeInt(-ResolveInt(LBase))
    else
      Result := LBase;
  end
  else if LKind = 'expr.grouped' then
    Result := EvalExpr(AExpr.GetChild(0));
end;

function TParseScriptInterp.EvalField(const ABase: TScriptValue;
  const AField: string): TScriptValue;
begin
  Result := MakeNil();
  if ABase.Kind = svkNode then
  begin
    if AField = 'token' then
      Result := MakeTok(ABase.NodeVal.GetToken());
  end
  else if ABase.Kind = svkToken then
  begin
    if AField = 'text' then
      Result := MakeStr(ABase.TokVal.Text)
    else if AField = 'kind' then
      Result := MakeStr(ABase.TokVal.Kind);
  end
  else if ABase.Kind = svkString then
  begin
    // target.source / target.header sentinel
    if ABase.StrVal = '__parse_target__' then
    begin
      if AField = 'source' then
        Result := MakeStr('target.source')
      else if AField = 'header' then
        Result := MakeStr('target.header');
    end;
  end;
end;

function TParseScriptInterp.EvalBinary(const AOp: string;
  const ALeft, ARight: TScriptValue): TScriptValue;
begin
  Result := MakeNil();
  if AOp = '+' then
  begin
    if (ALeft.Kind = svkString) or (ARight.Kind = svkString) then
      Result := MakeStr(ResolveStr(ALeft) + ResolveStr(ARight))
    else
      Result := MakeInt(ResolveInt(ALeft) + ResolveInt(ARight));
  end
  else if AOp = '-' then
    Result := MakeInt(ResolveInt(ALeft) - ResolveInt(ARight))
  else if AOp = '*' then
    Result := MakeInt(ResolveInt(ALeft) * ResolveInt(ARight))
  else if AOp = '=' then
  begin
    if (ALeft.Kind = svkString) or (ARight.Kind = svkString) then
      Result := MakeBool(ResolveStr(ALeft) = ResolveStr(ARight))
    else if (ALeft.Kind = svkInt) or (ARight.Kind = svkInt) then
      Result := MakeBool(ResolveInt(ALeft) = ResolveInt(ARight))
    else if (ALeft.Kind = svkBool) and (ARight.Kind = svkBool) then
      Result := MakeBool(ALeft.BoolVal = ARight.BoolVal)
    else if (ALeft.Kind = svkNil) and (ARight.Kind = svkNil) then
      Result := MakeBool(True)
    else
      Result := MakeBool(False);
  end
  else if AOp = '<>' then
  begin
    if (ALeft.Kind = svkString) or (ARight.Kind = svkString) then
      Result := MakeBool(ResolveStr(ALeft) <> ResolveStr(ARight))
    else if (ALeft.Kind = svkInt) or (ARight.Kind = svkInt) then
      Result := MakeBool(ResolveInt(ALeft) <> ResolveInt(ARight))
    else
      Result := MakeBool(True);
  end
  else if AOp = '<' then
    Result := MakeBool(ResolveInt(ALeft) < ResolveInt(ARight))
  else if AOp = '>' then
    Result := MakeBool(ResolveInt(ALeft) > ResolveInt(ARight))
  else if AOp = '<=' then
    Result := MakeBool(ResolveInt(ALeft) <= ResolveInt(ARight))
  else if AOp = '>=' then
    Result := MakeBool(ResolveInt(ALeft) >= ResolveInt(ARight))
  else if AOp = 'and' then
    Result := MakeBool(ResolveBool(ALeft) and ResolveBool(ARight))
  else if AOp = 'or' then
    Result := MakeBool(ResolveBool(ALeft) or ResolveBool(ARight));
end;

// =========================================================================
// GetResult
// =========================================================================

function TParseScriptInterp.GetResultNode(): TParseASTNodeBase;
var
  LVal: TScriptValue;
begin
  if FEnv.TryGetValue('result', LVal) and (LVal.Kind = svkNode) then
    Result := LVal.NodeVal
  else
    Result := nil;
end;

function TParseScriptInterp.GetResultValue(): TScriptValue;
begin
  if not FEnv.TryGetValue('result', Result) then
    Result := MakeNil();
end;

// =========================================================================
// CallBuiltin Dispatch
// =========================================================================

function TParseScriptInterp.CallBuiltin(const AName: string;
  const AArgs: TArray<TScriptValue>): TScriptValue;
var
  LHandled: Boolean;
begin
  Result   := MakeNil();
  LHandled := CallBuiltinCommon(AName, AArgs, Result);
  if LHandled then Exit;

  if FContextKind = sckParse then
    LHandled := CallBuiltinParse(AName, AArgs, Result)
  else if FContextKind = sckSemantic then
    LHandled := CallBuiltinSemantic(AName, AArgs, Result)
  else if (FContextKind = sckEmit) or (FContextKind = sckExprOverride) then
    LHandled := CallBuiltinEmit(AName, AArgs, Result);

  if not LHandled then
    Result := CallHelper(AName, AArgs);
end;

// =========================================================================
// Common Built-ins (all contexts)
// =========================================================================

function TParseScriptInterp.CallBuiltinCommon(const AName: string;
  const AArgs: TArray<TScriptValue>; out AResult: TScriptValue): Boolean;
var
  LAttr:      TValue;
  LNodeTyped: TParseASTNode;
  LIndex:     Integer;
  LFmtArgs:   TArray<string>;
  LI:         Integer;
begin
  AResult := MakeNil();
  Result  := True;

  if AName = 'nodeKind' then
  begin
    if (Length(AArgs) >= 1) and (AArgs[0].Kind = svkNode) and
       (AArgs[0].NodeVal <> nil) then
      AResult := MakeStr(AArgs[0].NodeVal.GetNodeKind())
    else
      AResult := MakeStr('');
  end
  else if AName = 'getAttr' then
  begin
    if (Length(AArgs) >= 2) and (AArgs[0].Kind = svkNode) and
       (AArgs[0].NodeVal <> nil) then
    begin
      AArgs[0].NodeVal.GetAttr(ResolveStr(AArgs[1]), LAttr);
      if not LAttr.IsEmpty then
        AResult := MakeStr(LAttr.AsString)
      else
        AResult := MakeStr('');
    end;
  end
  else if AName = 'setAttr' then
  begin
    if (Length(AArgs) >= 3) and (AArgs[0].Kind = svkNode) and
       (AArgs[0].NodeVal <> nil) then
    begin
      LNodeTyped := TParseASTNode(AArgs[0].NodeVal);
      LNodeTyped.SetAttr(ResolveStr(AArgs[1]),
        TValue.From<string>(ResolveStr(AArgs[2])));
    end;
  end
  else if AName = 'getChild' then
  begin
    if (Length(AArgs) >= 2) and (AArgs[0].Kind = svkNode) and
       (AArgs[0].NodeVal <> nil) then
    begin
      LIndex := Integer(ResolveInt(AArgs[1]));
      if (LIndex >= 0) and (LIndex < AArgs[0].NodeVal.ChildCount()) then
        AResult := MakeNode(AArgs[0].NodeVal.GetChild(LIndex))
      else
        AResult := MakeNil();
    end;
  end
  else if AName = 'childCount' then
  begin
    if (Length(AArgs) >= 1) and (AArgs[0].Kind = svkNode) and
       (AArgs[0].NodeVal <> nil) then
      AResult := MakeInt(AArgs[0].NodeVal.ChildCount())
    else
      AResult := MakeInt(0);
  end
  else if AName = 'len' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeInt(Length(ResolveStr(AArgs[0])))
    else
      AResult := MakeInt(0);
  end
  else if AName = 'substr' then
  begin
    if Length(AArgs) >= 3 then
      AResult := MakeStr(Copy(ResolveStr(AArgs[0]),
        Integer(ResolveInt(AArgs[1])), Integer(ResolveInt(AArgs[2]))))
    else
      AResult := MakeStr('');
  end
  else if AName = 'replace' then
  begin
    if Length(AArgs) >= 3 then
      AResult := MakeStr(ResolveStr(AArgs[0]).Replace(
        ResolveStr(AArgs[1]), ResolveStr(AArgs[2])))
    else
      AResult := MakeStr('');
  end
  else if AName = 'uppercase' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeStr(UpperCase(ResolveStr(AArgs[0])))
    else
      AResult := MakeStr('');
  end
  else if AName = 'lowercase' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeStr(LowerCase(ResolveStr(AArgs[0])))
    else
      AResult := MakeStr('');
  end
  else if AName = 'trim' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeStr(Trim(ResolveStr(AArgs[0])))
    else
      AResult := MakeStr('');
  end
  else if AName = 'strtoint' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeInt(StrToInt64Def(ResolveStr(AArgs[0]), 0))
    else
      AResult := MakeInt(0);
  end
  else if AName = 'inttostr' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeStr(IntToStr(ResolveInt(AArgs[0])))
    else
      AResult := MakeStr('0');
  end
  else if AName = 'format' then
  begin
    if Length(AArgs) >= 1 then
    begin
      SetLength(LFmtArgs, Length(AArgs) - 1);
      for LI := 1 to High(AArgs) do
        LFmtArgs[LI - 1] := ResolveStr(AArgs[LI]);
      AResult := MakeStr(FormatArgs(ResolveStr(AArgs[0]), LFmtArgs));
    end
    else
      AResult := MakeStr('');
  end
  else if AName = 'typeTextToKind' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeStr(FCustomConfig.TypeTextToKind(ResolveStr(AArgs[0])))
    else
      AResult := MakeStr('type.unknown');
  end
  else
    Result := False;
end;

// =========================================================================
// Parse Built-ins
// =========================================================================

function TParseScriptInterp.CallBuiltinParse(const AName: string;
  const AArgs: TArray<TScriptValue>; out AResult: TScriptValue): Boolean;
var
  LNode: TParseASTNode;
  LKind: string;
  LPow:  Integer;
begin
  AResult := MakeNil();
  Result  := True;

  if AName = 'createNode' then
  begin
    if Length(AArgs) = 0 then
      LNode := FParser.CreateNode()
    else if Length(AArgs) = 1 then
      LNode := FParser.CreateNode(ResolveStr(AArgs[0]))
    else
    begin
      LKind := ResolveStr(AArgs[0]);
      if AArgs[1].Kind = svkToken then
        LNode := FParser.CreateNode(LKind, AArgs[1].TokVal)
      else
        LNode := FParser.CreateNode(LKind);
    end;
    AResult := MakeNode(LNode);
  end
  else if AName = 'addChild' then
  begin
    if (Length(AArgs) >= 2) and (AArgs[0].Kind = svkNode) and
       (AArgs[1].Kind = svkNode) then
      TParseASTNode(AArgs[0].NodeVal).AddChild(
        TParseASTNode(AArgs[1].NodeVal));
  end
  else if AName = 'consume' then
    AResult := MakeTok(FParser.Consume())
  else if AName = 'expect' then
  begin
    if Length(AArgs) >= 1 then
      FParser.Expect(ResolveStr(AArgs[0]));
  end
  else if AName = 'check' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeBool(FParser.Check(ResolveStr(AArgs[0])))
    else
      AResult := MakeBool(False);
  end
  else if AName = 'match' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeBool(FParser.Match(ResolveStr(AArgs[0])))
    else
      AResult := MakeBool(False);
  end
  else if AName = 'current' then
    AResult := MakeTok(FParser.CurrentToken())
  else if AName = 'peek' then
    AResult := MakeTok(FParser.PeekToken(1))
  else if AName = 'parseExpr' then
  begin
    if Length(AArgs) >= 1 then
      LPow := Integer(ResolveInt(AArgs[0]))
    else
      LPow := 0;
    AResult := MakeNode(FParser.ParseExpression(LPow));
  end
  else if AName = 'parseStmt' then
    AResult := MakeNode(FParser.ParseStatement())
  else if AName = 'bindPower' then
    AResult := MakeInt(FParser.CurrentInfixPower())
  else if AName = 'bindPowerRight' then
    AResult := MakeInt(FParser.CurrentInfixPowerRight())
  else if AName = 'blockCloseKind' then
    AResult := MakeStr(FParser.GetBlockCloseKind())
  else if AName = 'stmtTermKind' then
    AResult := MakeStr(FParser.GetStatementTerminatorKind())
  else
    Result := False;
end;

// =========================================================================
// Semantic Built-ins
// =========================================================================

function TParseScriptInterp.CallBuiltinSemantic(const AName: string;
  const AArgs: TArray<TScriptValue>; out AResult: TScriptValue): Boolean;
var
  LSymNode: TParseASTNodeBase;
begin
  AResult := MakeNil();
  Result  := True;

  if AName = 'pushScope' then
  begin
    if (Length(AArgs) >= 2) and (AArgs[1].Kind = svkToken) then
      FSemantic.PushScope(ResolveStr(AArgs[0]), AArgs[1].TokVal)
    else if (Length(AArgs) >= 2) and (AArgs[1].Kind = svkNode) then
      FSemantic.PushScope(ResolveStr(AArgs[0]),
        AArgs[1].NodeVal.GetToken());
  end
  else if AName = 'popScope' then
  begin
    if (Length(AArgs) >= 1) and (AArgs[0].Kind = svkToken) then
      FSemantic.PopScope(AArgs[0].TokVal)
    else if (Length(AArgs) >= 1) and (AArgs[0].Kind = svkNode) then
      FSemantic.PopScope(AArgs[0].NodeVal.GetToken());
  end
  else if AName = 'visitNode' then
  begin
    if (Length(AArgs) >= 1) and (AArgs[0].Kind = svkNode) then
      FSemantic.VisitNode(AArgs[0].NodeVal);
  end
  else if AName = 'visitChildren' then
  begin
    if (Length(AArgs) >= 1) and (AArgs[0].Kind = svkNode) then
      FSemantic.VisitChildren(AArgs[0].NodeVal);
  end
  else if AName = 'declare' then
  begin
    if (Length(AArgs) >= 2) and (AArgs[1].Kind = svkNode) then
      AResult := MakeBool(FSemantic.DeclareSymbol(
        ResolveStr(AArgs[0]), AArgs[1].NodeVal))
    else
      AResult := MakeBool(False);
  end
  else if AName = 'lookup' then
  begin
    if Length(AArgs) >= 1 then
    begin
      if FSemantic.LookupSymbol(ResolveStr(AArgs[0]), LSymNode) then
        AResult := MakeNode(LSymNode)
      else
        AResult := MakeNil();
    end;
  end
  else if AName = 'lookupLocal' then
  begin
    if Length(AArgs) >= 1 then
    begin
      if FSemantic.LookupSymbolLocal(ResolveStr(AArgs[0]), LSymNode) then
        AResult := MakeNode(LSymNode)
      else
        AResult := MakeNil();
    end;
  end
  else if AName = 'insideRoutine' then
    AResult := MakeBool(FSemantic.IsInsideRoutine())
  else if AName = 'error' then
  begin
    if (Length(AArgs) >= 3) and (AArgs[0].Kind = svkNode) then
      FSemantic.AddSemanticError(AArgs[0].NodeVal,
        ResolveStr(AArgs[1]), ResolveStr(AArgs[2]));
  end
  else if AName = 'warn' then
  begin
    if (Length(AArgs) >= 3) and (AArgs[0].Kind = svkNode) then
      FSemantic.AddSemanticError(AArgs[0].NodeVal,
        ResolveStr(AArgs[1]), '(warning) ' + ResolveStr(AArgs[2]));
  end
  else
    Result := False;
end;

// =========================================================================
// Emit + ExprOverride Built-ins
// =========================================================================

function TParseScriptInterp.CallBuiltinEmit(const AName: string;
  const AArgs: TArray<TScriptValue>; out AResult: TScriptValue): Boolean;
var
  LTgt:     TParseSourceFile;
  LHasTgt:  Boolean;
  LLast:    TScriptValue;
  LFmtArgs: TArray<string>;
  LArgStrs: TArray<string>;
  LText:    string;
  LI:       Integer;
begin
  AResult  := MakeNil();
  Result   := True;
  LTgt     := sfSource;
  LHasTgt  := False;

  if Length(AArgs) >= 2 then
  begin
    LLast := AArgs[High(AArgs)];
    if IsSfSentinel(LLast) then
    begin
      LTgt    := ToSf(LLast);
      LHasTgt := True;
    end;
  end;

  if AName = 'emitLine' then
  begin
    if Length(AArgs) = 0 then
      FIR.EmitLine('', sfSource)
    else if Length(AArgs) = 1 then
      FIR.EmitLine(ResolveStr(AArgs[0]), sfSource)
    else
    begin
      LText := ResolveStr(AArgs[0]);
      if LHasTgt and (Length(AArgs) = 2) then
        FIR.EmitLine(LText, LTgt)
      else
      begin
        // Format args (skip last if it was a target sentinel)
        var LCount: Integer;
        if LHasTgt then LCount := Length(AArgs) - 2
        else             LCount := Length(AArgs) - 1;
        SetLength(LFmtArgs, LCount);
        for LI := 0 to LCount - 1 do
          LFmtArgs[LI] := ResolveStr(AArgs[LI + 1]);
        if LHasTgt then
          FIR.EmitLine(FormatArgs(LText, LFmtArgs), LTgt)
        else
          FIR.EmitLine(FormatArgs(LText, LFmtArgs), sfSource);
      end;
    end;
  end
  else if AName = 'emit' then
  begin
    if Length(AArgs) >= 1 then
    begin
      if LHasTgt then
        FIR.Emit(ResolveStr(AArgs[0]), LTgt)
      else
        FIR.Emit(ResolveStr(AArgs[0]), sfSource);
    end;
  end
  else if AName = 'emitRaw' then
  begin
    if Length(AArgs) >= 1 then
    begin
      if LHasTgt then
        FIR.EmitRaw(ResolveStr(AArgs[0]), LTgt)
      else
        FIR.EmitRaw(ResolveStr(AArgs[0]), sfSource);
    end;
  end
  else if AName = 'indentIn' then
    FIR.IndentIn()
  else if AName = 'indentOut' then
    FIR.IndentOut()
  else if AName = 'emitNode' then
  begin
    if (Length(AArgs) >= 1) and (AArgs[0].Kind = svkNode) then
      FIR.EmitNode(AArgs[0].NodeVal);
  end
  else if AName = 'emitChildren' then
  begin
    if (Length(AArgs) >= 1) and (AArgs[0].Kind = svkNode) then
      FIR.EmitChildren(AArgs[0].NodeVal);
  end
  else if AName = 'func' then
  begin
    if Length(AArgs) >= 2 then
      FIR.Func(ResolveStr(AArgs[0]), ResolveStr(AArgs[1]));
  end
  else if AName = 'param' then
  begin
    if Length(AArgs) >= 2 then
      FIR.Param(ResolveStr(AArgs[0]), ResolveStr(AArgs[1]));
  end
  else if AName = 'endFunc' then
    FIR.EndFunc()
  else if AName = 'include' then
  begin
    if Length(AArgs) >= 1 then
    begin
      if LHasTgt then
        FIR.Include(ResolveStr(AArgs[0]), LTgt)
      else
        FIR.Include(ResolveStr(AArgs[0]), sfHeader);
    end;
  end
  else if AName = 'struct' then
  begin
    if Length(AArgs) >= 1 then
    begin
      if LHasTgt then
        FIR.Struct(ResolveStr(AArgs[0]), LTgt)
      else
        FIR.Struct(ResolveStr(AArgs[0]), sfHeader);
    end;
  end
  else if AName = 'addField' then
  begin
    if Length(AArgs) >= 2 then
      FIR.AddField(ResolveStr(AArgs[0]), ResolveStr(AArgs[1]));
  end
  else if AName = 'endStruct' then
    FIR.EndStruct()
  else if AName = 'declConst' then
  begin
    if Length(AArgs) >= 3 then
      FIR.DeclConst(ResolveStr(AArgs[0]), ResolveStr(AArgs[1]),
        ResolveStr(AArgs[2]))
    else if Length(AArgs) >= 2 then
      FIR.DeclConst(ResolveStr(AArgs[0]), ResolveStr(AArgs[1]), '');
  end
  else if AName = 'global' then
  begin
    if Length(AArgs) >= 3 then
      FIR.Global(ResolveStr(AArgs[0]), ResolveStr(AArgs[1]),
        ResolveStr(AArgs[2]))
    else if Length(AArgs) >= 2 then
      FIR.Global(ResolveStr(AArgs[0]), ResolveStr(AArgs[1]), '');
  end
  else if AName = 'usingAlias' then
  begin
    if Length(AArgs) >= 2 then
    begin
      if LHasTgt then
        FIR.Using(ResolveStr(AArgs[0]), ResolveStr(AArgs[1]), LTgt)
      else
        FIR.Using(ResolveStr(AArgs[0]), ResolveStr(AArgs[1]), sfHeader);
    end;
  end
  else if AName = 'namespace' then
  begin
    if Length(AArgs) >= 1 then
    begin
      if LHasTgt then
        FIR.Namespace(ResolveStr(AArgs[0]), LTgt)
      else
        FIR.Namespace(ResolveStr(AArgs[0]), sfHeader);
    end;
  end
  else if AName = 'endNamespace' then
  begin
    if LHasTgt then
      FIR.EndNamespace(LTgt)
    else
      FIR.EndNamespace(sfHeader);
  end
  else if AName = 'declVar' then
  begin
    if Length(AArgs) >= 3 then
      FIR.DeclVar(ResolveStr(AArgs[0]), ResolveStr(AArgs[1]),
        ResolveStr(AArgs[2]))
    else if Length(AArgs) >= 2 then
      FIR.DeclVar(ResolveStr(AArgs[0]), ResolveStr(AArgs[1]));
  end
  else if AName = 'assign' then
  begin
    if Length(AArgs) >= 2 then
      FIR.Assign(ResolveStr(AArgs[0]), ResolveStr(AArgs[1]));
  end
  else if AName = 'stmt' then
  begin
    if Length(AArgs) = 0 then
      FIR.Stmt('')
    else if Length(AArgs) = 1 then
      FIR.Stmt(ResolveStr(AArgs[0]))
    else
    begin
      SetLength(LFmtArgs, Length(AArgs) - 1);
      for LI := 1 to High(AArgs) do
        LFmtArgs[LI - 1] := ResolveStr(AArgs[LI]);
      FIR.Stmt(FormatArgs(ResolveStr(AArgs[0]), LFmtArgs));
    end;
  end
  else if AName = 'returnVoid' then
    FIR.Return()
  else if AName = 'returnVal' then
  begin
    if Length(AArgs) >= 1 then
      FIR.Return(ResolveStr(AArgs[0]));
  end
  else if AName = 'ifStmt' then
  begin
    if Length(AArgs) >= 1 then
      FIR.IfStmt(ResolveStr(AArgs[0]));
  end
  else if AName = 'elseIfStmt' then
  begin
    if Length(AArgs) >= 1 then
      FIR.ElseIfStmt(ResolveStr(AArgs[0]));
  end
  else if AName = 'elseStmt' then
    FIR.ElseStmt()
  else if AName = 'endIf' then
    FIR.EndIf()
  else if AName = 'whileStmt' then
  begin
    if Length(AArgs) >= 1 then
      FIR.WhileStmt(ResolveStr(AArgs[0]));
  end
  else if AName = 'endWhile' then
    FIR.EndWhile()
  else if AName = 'forStmt' then
  begin
    if Length(AArgs) >= 4 then
      FIR.ForStmt(ResolveStr(AArgs[0]), ResolveStr(AArgs[1]),
        ResolveStr(AArgs[2]), ResolveStr(AArgs[3]));
  end
  else if AName = 'endFor' then
    FIR.EndFor()
  else if AName = 'breakStmt' then
    FIR.BreakStmt()
  else if AName = 'continueStmt' then
    FIR.ContinueStmt()
  else if AName = 'blankLine' then
  begin
    if LHasTgt then
      FIR.BlankLine(LTgt)
    else
      FIR.BlankLine(sfSource);
  end
  // ---- Expression builders ----
  else if AName = 'lit' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeStr(FIR.Lit(Integer(ResolveInt(AArgs[0]))))
    else
      AResult := MakeStr('0');
  end
  else if AName = 'str' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeStr(FIR.Str(ResolveStr(AArgs[0])))
    else
      AResult := MakeStr('""');
  end
  else if AName = 'boolLit' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeStr(FIR.Bool(ResolveBool(AArgs[0])))
    else
      AResult := MakeStr('false');
  end
  else if AName = 'nullLit' then
    AResult := MakeStr(FIR.Null())
  else if AName = 'get' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeStr(FIR.Get(ResolveStr(AArgs[0])))
    else
      AResult := MakeStr('');
  end
  else if AName = 'field' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.Field(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else
      AResult := MakeStr('');
  end
  else if AName = 'deref' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.Deref(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else if Length(AArgs) >= 1 then
      AResult := MakeStr(FIR.Deref(ResolveStr(AArgs[0])))
    else
      AResult := MakeStr('');
  end
  else if AName = 'addrOf' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeStr(FIR.AddrOf(ResolveStr(AArgs[0])))
    else
      AResult := MakeStr('');
  end
  else if AName = 'index' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.Index(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else
      AResult := MakeStr('');
  end
  else if AName = 'cast' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.Cast(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else
      AResult := MakeStr('');
  end
  else if AName = 'invoke' then
  begin
    if Length(AArgs) >= 1 then
    begin
      SetLength(LArgStrs, Length(AArgs) - 1);
      for LI := 1 to High(AArgs) do
        LArgStrs[LI - 1] := ResolveStr(AArgs[LI]);
      AResult := MakeStr(FIR.Invoke(ResolveStr(AArgs[0]), LArgStrs));
    end
    else
      AResult := MakeStr('');
  end
  else if AName = 'add' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.Add(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'sub' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.Sub(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'mul' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.Mul(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'divExpr' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.DivExpr(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'modExpr' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.ModExpr(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'neg' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeStr(FIR.Neg(ResolveStr(AArgs[0])))
    else AResult := MakeStr('');
  end
  else if AName = 'eq' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.Eq(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'ne' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.Ne(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'lt' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.Lt(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'le' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.Le(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'gt' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.Gt(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'ge' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.Ge(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'andExpr' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.AndExpr(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'orExpr' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.OrExpr(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'notExpr' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeStr(FIR.NotExpr(ResolveStr(AArgs[0])))
    else AResult := MakeStr('');
  end
  else if AName = 'bitAnd' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.BitAnd(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'bitOr' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.BitOr(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'bitXor' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.BitXor(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'bitNot' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeStr(FIR.BitNot(ResolveStr(AArgs[0])))
    else AResult := MakeStr('');
  end
  else if AName = 'shlExpr' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.ShlExpr(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  else if AName = 'shrExpr' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.ShrExpr(ResolveStr(AArgs[0]), ResolveStr(AArgs[1])))
    else AResult := MakeStr('');
  end
  // ---- Type resolution ----
  else if AName = 'typeToIR' then
  begin
    if Length(AArgs) >= 1 then
      AResult := MakeStr(FCustomConfig.TypeToIR(ResolveStr(AArgs[0])))
    else
      AResult := MakeStr('');
  end
  else if AName = 'resolveTypeIR' then
  begin
    if Length(AArgs) >= 1 then
    begin
      var LKind: string;
      LKind := FCustomConfig.TypeTextToKind(ResolveStr(AArgs[0]));
      if LKind <> 'type.unknown' then
        AResult := MakeStr(FCustomConfig.TypeToIR(LKind))
      else
        AResult := MakeStr(ResolveStr(AArgs[0]));
    end
    else
      AResult := MakeStr('');
  end
  // ---- Cross-handler context store ----
  else if AName = 'setContext' then
  begin
    if Length(AArgs) >= 2 then
      FIR.SetContext(ResolveStr(AArgs[0]), ResolveStr(AArgs[1]));
  end
  else if AName = 'getContext' then
  begin
    if Length(AArgs) >= 2 then
      AResult := MakeStr(FIR.GetContext(ResolveStr(AArgs[0]),
        ResolveStr(AArgs[1])))
    else if Length(AArgs) >= 1 then
      AResult := MakeStr(FIR.GetContext(ResolveStr(AArgs[0]), ''))
    else
      AResult := MakeStr('');
  end
  else if AName = 'exprToString' then
  begin
    if (Length(AArgs) >= 1) and (AArgs[0].Kind = svkNode) then
      AResult := MakeStr(FCustomConfig.ExprToString(AArgs[0].NodeVal))
    else
      AResult := MakeStr('');
  end
  else if AName = 'default' then
  begin
    if (FContextKind = sckExprOverride) and Assigned(FExprDefault) and
       (Length(AArgs) >= 1) and (AArgs[0].Kind = svkNode) then
      AResult := MakeStr(FExprDefault(AArgs[0].NodeVal))
    else
      AResult := MakeStr('');
  end
  // ---- Pipeline built-ins ----
  else if AName = 'setPlatform' then
  begin
    if (Length(AArgs) >= 1) and Assigned(FPipeline.OnSetPlatform) then
      FPipeline.OnSetPlatform(ResolveStr(AArgs[0]));
  end
  else if AName = 'setBuildMode' then
  begin
    if (Length(AArgs) >= 1) and Assigned(FPipeline.OnSetBuildMode) then
      FPipeline.OnSetBuildMode(ResolveStr(AArgs[0]));
  end
  else if AName = 'setOptimize' then
  begin
    if (Length(AArgs) >= 1) and Assigned(FPipeline.OnSetOptimize) then
      FPipeline.OnSetOptimize(ResolveStr(AArgs[0]));
  end
  else if AName = 'setSubsystem' then
  begin
    if (Length(AArgs) >= 1) and Assigned(FPipeline.OnSetSubsystem) then
      FPipeline.OnSetSubsystem(ResolveStr(AArgs[0]));
  end
  else if AName = 'setOutputPath' then
  begin
    if (Length(AArgs) >= 1) and Assigned(FPipeline.OnSetOutputPath) then
      FPipeline.OnSetOutputPath(ResolveStr(AArgs[0]));
  end
  else
    Result := False;
end;

// =========================================================================
// Helper Function Calls
// =========================================================================

function TParseScriptInterp.CallHelper(const AName: string;
  const AArgs: TArray<TScriptValue>): TScriptValue;
var
  LHelperNode:  TParseASTNodeBase;
  LChildInterp: TParseScriptInterp;
  LParamNode:   TParseASTNodeBase;
  LAttr:        TValue;
  LParamName:   string;
  LParamIdx:    Integer;
  LBlockNode:   TParseASTNodeBase;
  LRetType:     string;
  LI:           Integer;
begin
  Result := MakeNil();
  if not FStore.GetHelperFuncs().TryGetValue(AName, LHelperNode) then
    Exit;

  LChildInterp := TParseScriptInterp.Create(
    FCustomConfig, FStore, FPipeline, FNodeKindForRule);
  try
    LChildInterp.InheritContext(Self);

    // Bind positional parameters
    LParamIdx  := 0;
    LBlockNode := nil;
    for LI := 0 to LHelperNode.ChildCount() - 1 do
    begin
      LParamNode := LHelperNode.GetChild(LI);
      if LParamNode.GetNodeKind() = 'stmt.func_param' then
      begin
        LParamNode.GetAttr('param.name', LAttr);
        LParamName := LAttr.AsString;
        if LParamIdx < Length(AArgs) then
          LChildInterp.FEnv.AddOrSetValue(LParamName, AArgs[LParamIdx])
        else
          LChildInterp.FEnv.AddOrSetValue(LParamName, MakeNil());
        Inc(LParamIdx);
      end
      else if LParamNode.GetNodeKind() = 'stmt.block' then
      begin
        LBlockNode := LParamNode;
        Break;
      end;
    end;

    // Find body block if not already found
    if LBlockNode = nil then
      for LI := 0 to LHelperNode.ChildCount() - 1 do
        if LHelperNode.GetChild(LI).GetNodeKind() = 'stmt.block' then
        begin
          LBlockNode := LHelperNode.GetChild(LI);
          Break;
        end;

    if LBlockNode <> nil then
      LChildInterp.ExecBlock(LBlockNode);

    LHelperNode.GetAttr('func.return_type', LAttr);
    LRetType := LAttr.AsString;
    if LRetType <> '' then
      Result := LChildInterp.GetResultValue();
  finally
    LChildInterp.Free();
  end;
end;

// =========================================================================
// CODEGEN REGISTRATION
// =========================================================================

procedure RegisterLexerSections(
  const AParse:       TParse;
  const ACustomParse: TParse;
  const AStore:       IParseScriptStore);
begin

  AParse.Config().RegisterEmitter('stmt.language_decl',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    begin
      // Language name is informational only
    end);

  AParse.Config().RegisterEmitter('stmt.tokens_block',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    begin
      // Custom token regexes: TParseLangConfig has no regex token API.
      // Entries are silently skipped in this version.
    end);

  AParse.Config().RegisterEmitter('stmt.keywords_block',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:  TValue;
      LChild: TParseASTNodeBase;
      LCase:  string;
      LText:  string;
      LKind:  string;
      LI:     Integer;
    begin
      ANode.GetAttr('keywords.case', LAttr);
      LCase := LAttr.AsString;
      ACustomParse.Config().CaseSensitiveKeywords(LCase = 'casesensitive');
      for LI := 0 to ANode.ChildCount() - 1 do
      begin
        LChild := ANode.GetChild(LI);
        if LChild.GetNodeKind() = 'stmt.keyword_decl' then
        begin
          LChild.GetAttr('keyword.text', LAttr);
          LText := StripQuotes(LAttr.AsString);
          LChild.GetAttr('keyword.kind', LAttr);
          LKind := StripQuotes(LAttr.AsString);
          ACustomParse.Config().AddKeyword(LText, LKind);
        end;
      end;
    end);

  AParse.Config().RegisterEmitter('stmt.operators_block',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:  TValue;
      LChild: TParseASTNodeBase;
      LText:  string;
      LKind:  string;
      LI:     Integer;
    begin
      for LI := 0 to ANode.ChildCount() - 1 do
      begin
        LChild := ANode.GetChild(LI);
        if LChild.GetNodeKind() = 'stmt.operator_decl' then
        begin
          LChild.GetAttr('operator.text', LAttr);
          LText := StripQuotes(LAttr.AsString);
          LChild.GetAttr('operator.kind', LAttr);
          LKind := StripQuotes(LAttr.AsString);
          ACustomParse.Config().AddOperator(LText, LKind);
        end;
      end;
    end);

  AParse.Config().RegisterEmitter('stmt.strings_block',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:    TValue;
      LChild:   TParseASTNodeBase;
      LOpen:    string;
      LClose:   string;
      LKind:    string;
      LEscape:  Boolean;
      LI:       Integer;
    begin
      for LI := 0 to ANode.ChildCount() - 1 do
      begin
        LChild := ANode.GetChild(LI);
        if LChild.GetNodeKind() = 'stmt.string_style' then
        begin
          LChild.GetAttr('style.open',   LAttr); LOpen   := StripQuotes(LAttr.AsString);
          LChild.GetAttr('style.close',  LAttr); LClose  := StripQuotes(LAttr.AsString);
          LChild.GetAttr('style.kind',   LAttr); LKind   := StripQuotes(LAttr.AsString);
          LChild.GetAttr('style.escape', LAttr);
          if LAttr.IsEmpty then LEscape := True
          else                  LEscape := LAttr.AsType<Boolean>;
          ACustomParse.Config().AddStringStyle(LOpen, LClose, LKind, LEscape);
        end;
      end;
    end);

  AParse.Config().RegisterEmitter('stmt.comments_block',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:   TValue;
      LChild:  TParseASTNodeBase;
      LPrefix: string;
      LOpen:   string;
      LClose:  string;
      LKind:   string;
      LI:      Integer;
    begin
      for LI := 0 to ANode.ChildCount() - 1 do
      begin
        LChild := ANode.GetChild(LI);
        if LChild.GetNodeKind() = 'stmt.line_comment' then
        begin
          LChild.GetAttr('comment.prefix', LAttr);
          LPrefix := StripQuotes(LAttr.AsString);
          ACustomParse.Config().AddLineComment(LPrefix);
        end
        else if LChild.GetNodeKind() = 'stmt.block_comment' then
        begin
          LChild.GetAttr('comment.open',  LAttr); LOpen  := StripQuotes(LAttr.AsString);
          LChild.GetAttr('comment.close', LAttr); LClose := StripQuotes(LAttr.AsString);
          LChild.GetAttr('comment.kind',  LAttr); LKind  := StripQuotes(LAttr.AsString);
          ACustomParse.Config().AddBlockComment(LOpen, LClose, LKind);
        end;
      end;
    end);

  AParse.Config().RegisterEmitter('stmt.structural_block',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr: TValue;
      LKind: string;
    begin
      ANode.GetAttr('structural.terminator', LAttr);
      if not LAttr.IsEmpty then
      begin
        LKind := StripQuotes(LAttr.AsString);
        if LKind <> '' then
          ACustomParse.Config().SetStatementTerminator(LKind);
      end;
      ANode.GetAttr('structural.blockopen', LAttr);
      if not LAttr.IsEmpty then
      begin
        LKind := StripQuotes(LAttr.AsString);
        if LKind <> '' then
          ACustomParse.Config().SetBlockOpen(LKind);
      end;
      ANode.GetAttr('structural.blockclose', LAttr);
      if not LAttr.IsEmpty then
      begin
        LKind := StripQuotes(LAttr.AsString);
        if LKind <> '' then
          ACustomParse.Config().SetBlockClose(LKind);
      end;
    end);

  AParse.Config().RegisterEmitter('stmt.types_block',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:  TValue;
      LChild: TParseASTNodeBase;
      LText:  string;
      LKind:  string;
      LI:     Integer;
    begin
      for LI := 0 to ANode.ChildCount() - 1 do
      begin
        LChild := ANode.GetChild(LI);
        if LChild.GetNodeKind() = 'stmt.type_keyword' then
        begin
          LChild.GetAttr('typekw.text', LAttr); LText := StripQuotes(LAttr.AsString);
          LChild.GetAttr('typekw.kind', LAttr); LKind := StripQuotes(LAttr.AsString);
          ACustomParse.Config().AddTypeKeyword(LText, LKind);
        end;
      end;
    end);

  AParse.Config().RegisterEmitter('stmt.literals_block',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:     TValue;
      LChild:    TParseASTNodeBase;
      LNodeKind: string;
      LTypeKind: string;
      LI:        Integer;
    begin
      for LI := 0 to ANode.ChildCount() - 1 do
      begin
        LChild := ANode.GetChild(LI);
        if LChild.GetNodeKind() = 'stmt.literal_type' then
        begin
          LChild.GetAttr('littype.node_kind', LAttr); LNodeKind := StripQuotes(LAttr.AsString);
          LChild.GetAttr('littype.type_kind', LAttr); LTypeKind := StripQuotes(LAttr.AsString);
          ACustomParse.Config().AddLiteralType(LNodeKind, LTypeKind);
        end;
      end;
    end);

  // typemap: collect into AStore then install SetTypeToIR on ACustomParse.
  // Multiple typemap blocks merge into the same store.
  AParse.Config().RegisterEmitter('stmt.typemap_block',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:     TValue;
      LChild:    TParseASTNodeBase;
      LTypeKind: string;
      LCppType:  string;
      LI:        Integer;
    begin
      for LI := 0 to ANode.ChildCount() - 1 do
      begin
        LChild := ANode.GetChild(LI);
        if LChild.GetNodeKind() = 'stmt.typemap_entry' then
        begin
          LChild.GetAttr('tmap.type_kind', LAttr); LTypeKind := StripQuotes(LAttr.AsString);
          LChild.GetAttr('tmap.cpp_type',  LAttr); LCppType  := StripQuotes(LAttr.AsString);
          AStore.GetTypeMap().AddOrSetValue(LTypeKind, LCppType);
        end;
      end;
      // Re-install the SetTypeToIR closure each time (captures AStore).
      ACustomParse.Config().SetTypeToIR(
        function(const ATypeKind: string): string
        var
          LResult: string;
        begin
          if AStore.GetTypeMap().TryGetValue(ATypeKind, LResult) then
            Result := LResult
          else
            Result := ATypeKind;  // passthrough unknown kinds
        end);
    end);
end;

// =========================================================================
// Grammar Rule Registrations
// =========================================================================

procedure RegisterGrammarRules(
  const AParse:       TParse;
  const ACustomParse: TParse;
  const AStore:       IParseScriptStore;
  const APipeline:    TParseLangPipelineCallbacks);
begin

  // registerLiterals ;
  AParse.Config().RegisterEmitter('stmt.registerliterals',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    begin
      ACustomParse.Config().RegisterLiteralPrefixes();
    end);

  // binaryop 'tok' power N op 'cppop' ;
  AParse.Config().RegisterEmitter('stmt.binaryop_rule',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:    TValue;
      LTokKind: string;
      LPower:   Integer;
      LCppOp:   string;
    begin
      ANode.GetAttr('binop.token_kind', LAttr); LTokKind := StripQuotes(LAttr.AsString);
      ANode.GetAttr('binop.power',      LAttr); LPower   := StrToIntDef(LAttr.AsString, 0);
      ANode.GetAttr('binop.cpp_op',     LAttr); LCppOp   := StripQuotes(LAttr.AsString);
      ACustomParse.Config().RegisterBinaryOp(LTokKind, LPower, LCppOp);
    end);

  // prefix 'tok' as 'node' parse ... end end
  AParse.Config().RegisterEmitter('stmt.prefix_rule',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:      TValue;
      LTokKind:   string;
      LNodeKind:  string;
      LBlockNode: TParseASTNodeBase;
    begin
      ANode.GetAttr('rule.token_kind', LAttr); LTokKind  := StripQuotes(LAttr.AsString);
      ANode.GetAttr('rule.node_kind',  LAttr); LNodeKind := StripQuotes(LAttr.AsString);
      LBlockNode := ANode.GetChild(0);
      ACustomParse.Config().RegisterPrefix(LTokKind, LNodeKind,
        function(AParser: TParseParserBase): TParseASTNodeBase
        var
          LInterp: TParseScriptInterp;
        begin
          LInterp := TParseScriptInterp.Create(
            ACustomParse.Config(), AStore, APipeline, LNodeKind);
          try
            LInterp.SetParseContext(AParser, nil);
            LInterp.ExecBlock(LBlockNode);
            Result := LInterp.GetResultNode();
          finally
            LInterp.Free();
          end;
        end);
    end);

  // infix left|right 'tok' power N as 'node' parse ... end end
  AParse.Config().RegisterEmitter('stmt.infix_rule',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:      TValue;
      LTokKind:   string;
      LNodeKind:  string;
      LAssoc:     string;
      LPower:     Integer;
      LBlockNode: TParseASTNodeBase;
    begin
      ANode.GetAttr('rule.token_kind', LAttr); LTokKind  := StripQuotes(LAttr.AsString);
      ANode.GetAttr('rule.node_kind',  LAttr); LNodeKind := StripQuotes(LAttr.AsString);
      ANode.GetAttr('rule.assoc',      LAttr); LAssoc    := LAttr.AsString;
      ANode.GetAttr('rule.power',      LAttr); LPower    := StrToIntDef(LAttr.AsString, 0);
      LBlockNode := ANode.GetChild(0);

      if LAssoc = 'right' then
        ACustomParse.Config().RegisterInfixRight(LTokKind, LPower, LNodeKind,
          function(AParser: TParseParserBase;
            ALeft: TParseASTNodeBase): TParseASTNodeBase
          var
            LInterp: TParseScriptInterp;
          begin
            LInterp := TParseScriptInterp.Create(
              ACustomParse.Config(), AStore, APipeline, LNodeKind);
            try
              LInterp.SetParseContext(AParser, ALeft);
              LInterp.ExecBlock(LBlockNode);
              Result := LInterp.GetResultNode();
            finally
              LInterp.Free();
            end;
          end)
      else
        ACustomParse.Config().RegisterInfixLeft(LTokKind, LPower, LNodeKind,
          function(AParser: TParseParserBase;
            ALeft: TParseASTNodeBase): TParseASTNodeBase
          var
            LInterp: TParseScriptInterp;
          begin
            LInterp := TParseScriptInterp.Create(
              ACustomParse.Config(), AStore, APipeline, LNodeKind);
            try
              LInterp.SetParseContext(AParser, ALeft);
              LInterp.ExecBlock(LBlockNode);
              Result := LInterp.GetResultNode();
            finally
              LInterp.Free();
            end;
          end);
    end);

  // statement 'tok' as 'node' parse ... end end
  AParse.Config().RegisterEmitter('stmt.statement_rule',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:      TValue;
      LTokKind:   string;
      LNodeKind:  string;
      LBlockNode: TParseASTNodeBase;
    begin
      ANode.GetAttr('rule.token_kind', LAttr); LTokKind  := StripQuotes(LAttr.AsString);
      ANode.GetAttr('rule.node_kind',  LAttr); LNodeKind := StripQuotes(LAttr.AsString);
      LBlockNode := ANode.GetChild(0);
      ACustomParse.Config().RegisterStatement(LTokKind, LNodeKind,
        function(AParser: TParseParserBase): TParseASTNodeBase
        var
          LInterp: TParseScriptInterp;
        begin
          LInterp := TParseScriptInterp.Create(
            ACustomParse.Config(), AStore, APipeline, LNodeKind);
          try
            LInterp.SetParseContext(AParser, nil);
            LInterp.ExecBlock(LBlockNode);
            Result := LInterp.GetResultNode();
          finally
            LInterp.Free();
          end;
        end);
    end);

  // exproverride 'tok' override ... end end
  AParse.Config().RegisterEmitter('stmt.exproverride_rule',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:      TValue;
      LNodeKind:  string;
      LBlockNode: TParseASTNodeBase;
    begin
      ANode.GetAttr('rule.token_kind', LAttr); LNodeKind  := StripQuotes(LAttr.AsString);
      LBlockNode := ANode.GetChild(0);
      ACustomParse.Config().RegisterExprOverride(LNodeKind,
        function(const AExprNode: TParseASTNodeBase;
          const ADefault: TParseExprToStringFunc): string
        var
          LInterp: TParseScriptInterp;
          LResult: TScriptValue;
        begin
          LInterp := TParseScriptInterp.Create(
            ACustomParse.Config(), AStore, APipeline, LNodeKind);
          try
            LInterp.SetExprOverrideContext(AExprNode, ADefault);
            LInterp.ExecBlock(LBlockNode);
            LResult := LInterp.GetResultValue();
            Result  := LInterp.ResolveStr(LResult);
          finally
            LInterp.Free();
          end;
        end);
    end);
end;

// =========================================================================
// Semantic Rule Registration
// =========================================================================

procedure RegisterSemanticRules(
  const AParse:       TParse;
  const ACustomParse: TParse;
  const AStore:       IParseScriptStore;
  const APipeline:    TParseLangPipelineCallbacks);
begin

  AParse.Config().RegisterEmitter('stmt.semantic_rule',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:      TValue;
      LNodeKind:  string;
      LBlockNode: TParseASTNodeBase;
    begin
      ANode.GetAttr('rule.node_kind', LAttr);
      LNodeKind  := StripQuotes(LAttr.AsString);
      LBlockNode := ANode.GetChild(0);
      ACustomParse.Config().RegisterSemanticRule(LNodeKind,
        procedure(ASemanticNode: TParseASTNodeBase;
          ASem: TParseSemanticBase)
        var
          LInterp: TParseScriptInterp;
        begin
          LInterp := TParseScriptInterp.Create(
            ACustomParse.Config(), AStore, APipeline, LNodeKind);
          try
            LInterp.SetSemanticContext(ASem, ASemanticNode);
            LInterp.ExecBlock(LBlockNode);
          finally
            LInterp.Free();
          end;
        end);
    end);
end;

// =========================================================================
// Emit Rule Registration
// =========================================================================

procedure RegisterEmitRules(
  const AParse:       TParse;
  const ACustomParse: TParse;
  const AStore:       IParseScriptStore;
  const APipeline:    TParseLangPipelineCallbacks);
begin

  AParse.Config().RegisterEmitter('stmt.emit_rule',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:      TValue;
      LNodeKind:  string;
      LBlockNode: TParseASTNodeBase;
    begin
      ANode.GetAttr('rule.node_kind', LAttr);
      LNodeKind  := StripQuotes(LAttr.AsString);
      LBlockNode := ANode.GetChild(0);
      ACustomParse.Config().RegisterEmitter(LNodeKind,
        procedure(AEmitNode: TParseASTNodeBase; AIR: TParseIRBase)
        var
          LInterp: TParseScriptInterp;
        begin
          LInterp := TParseScriptInterp.Create(
            ACustomParse.Config(), AStore, APipeline, LNodeKind);
          try
            LInterp.SetEmitContext(AIR, AEmitNode);
            LInterp.ExecBlock(LBlockNode);
          finally
            LInterp.Free();
          end;
        end);
    end);
end;

// =========================================================================
// Helper Function Collection
// =========================================================================

procedure RegisterHelperFuncCollection(
  const AParse: TParse;
  const AStore: IParseScriptStore);
begin

  AParse.Config().RegisterEmitter('stmt.helper_func',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:     TValue;
      LFuncName: string;
    begin
      ANode.GetAttr('func.name', LAttr);
      LFuncName := LAttr.AsString;
      // Store the helper node so closures can call it in Phase 2.
      // The AST node lifetime is managed by the root AST (owned by AParse),
      // which is kept alive as long as ACustomParse holds the registered
      // closures. The caller (TParseLang) must keep AParse alive until
      // ACustomParse is freed.
      AStore.GetHelperFuncs().AddOrSetValue(LFuncName, ANode);
    end);
end;

// =========================================================================
// PUBLIC ENTRY POINT
// =========================================================================

procedure ConfigCodeGen(
  const AParse:       TParse;
  const ACustomParse: TParse;
  const APipeline:    TParseLangPipelineCallbacks);
var
  LStore: IParseScriptStore;
begin
  // Create the shared state store. It is captured by all closures registered
  // below and freed automatically when the last closure is freed.
  LStore := TParseScriptStore.Create();

  RegisterLexerSections(AParse, ACustomParse, LStore);
  RegisterGrammarRules(AParse, ACustomParse, LStore, APipeline);
  RegisterSemanticRules(AParse, ACustomParse, LStore, APipeline);
  RegisterEmitRules(AParse, ACustomParse, LStore, APipeline);
  RegisterHelperFuncCollection(AParse, LStore);
end;

end.
