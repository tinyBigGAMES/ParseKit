{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

unit Parse.IR;

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
  Parse.LangConfig;

type

  { TParseIR }
  TParseIR = class(TParseIRBase)
  private
    FHeaderBuffer:     TStringBuilder;
    FSourceBuffer:     TStringBuilder;
    FIndentLevel:      Integer;
    FConfig:           TParseLangConfig;  // not owned
    FInFuncSignature:  Boolean;  // True between Func() and first statement/EndFunc
    FContext:          TDictionary<string, string>;  // key/value context store for emitters
    FLineDirectives:   Boolean;  // When True, #line directives are emitted before each node
    FLastLineFile:     string;   // Filename of the last emitted #line directive
    FLastLineNum:      Integer;  // Line number of the last emitted #line directive

    // Returns the buffer for the given target
    function GetBuffer(const ATarget: TParseSourceFile): TStringBuilder;

    // Returns the current indentation string (2 spaces per level)
    function GetIndent(): string;

    // Closes the function signature with ) { if still open
    procedure CloseFuncSignature();

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Configuration — must be set before Generate()
    procedure SetConfig(const AConfig: TParseLangConfig);

    // Enable or disable #line directive emission into the source buffer.
    // When enabled, a #line N "file" is written before each dispatched node.
    procedure SetLineDirectives(const AEnabled: Boolean);

    // ---- TParseIRBase virtuals (low-level primitives) ----

    // Append indent + AText + newline
    procedure EmitLine(const AText: string; const ATarget: TParseSourceFile = sfSource); overload; override;
    procedure EmitLine(const AText: string; const AArgs: array of const; const ATarget: TParseSourceFile = sfSource); overload; override;

    // Append AText verbatim — no indent, no newline
    procedure Emit(const AText: string; const ATarget: TParseSourceFile = sfSource); overload; override;
    procedure Emit(const AText: string; const AArgs: array of const; const ATarget: TParseSourceFile = sfSource); overload; override;

    // Append AText truly verbatim (for $cppstart/$cpp escape hatch blocks)
    procedure EmitRaw(const AText: string; const ATarget: TParseSourceFile = sfSource); overload; override;
    procedure EmitRaw(const AText: string; const AArgs: array of const; const ATarget: TParseSourceFile = sfSource); overload; override;

    // Indentation control
    procedure IndentIn(); override;
    procedure IndentOut(); override;

    // AST dispatch — walks tree via registered TParseEmitHandler callbacks
    procedure EmitNode(const ANode: TParseASTNodeBase); override;
    procedure EmitChildren(const ANode: TParseASTNodeBase); override;

    // ---- Top-level declarations (fluent) ----

    // #include <AName> or #include "AName"
    function Include(const AHeaderName: string;
      const ATarget: TParseSourceFile = sfHeader): TParseIRBase; override;

    // struct AName { ... };
    function Struct(const AStructName: string;
      const ATarget: TParseSourceFile = sfHeader): TParseIRBase; override;

    // Field inside a Struct context
    function AddField(const AFieldName, AFieldType: string): TParseIRBase; override;

    // };  — closes Struct
    function EndStruct(): TParseIRBase; override;

    // constexpr auto AName = AValueExpr;
    function DeclConst(const AConstName, AConstType, AValueExpr: string;
      const ATarget: TParseSourceFile = sfHeader): TParseIRBase; override;

    // static AType AName = AInitExpr;
    function Global(const AGlobalName, AGlobalType, AInitExpr: string;
      const ATarget: TParseSourceFile = sfSource): TParseIRBase; override;

    // using AAlias = AOriginal;
    function Using(const AAlias, AOriginal: string;
      const ATarget: TParseSourceFile = sfHeader): TParseIRBase; override;

    // namespace AName {
    function Namespace(const ANamespaceName: string;
      const ATarget: TParseSourceFile = sfHeader): TParseIRBase; override;

    // } // namespace
    function EndNamespace(
      const ATarget: TParseSourceFile = sfHeader): TParseIRBase; override;

    // extern "C" AReturnType AName(AParams...);
    function ExternC(const AFuncName, AReturnType: string;
      const AParams: TArray<TArray<string>>;
      const ATarget: TParseSourceFile = sfHeader): TParseIRBase; override;

    // ---- Function / method builder (fluent) ----

    // AReturnType AName(...)  {
    function Func(const AFuncName, AReturnType: string): TParseIRBase; override;

    // Parameter inside Func context
    function Param(const AParamName, AParamType: string): TParseIRBase; override;

    // }  — closes Func, emits the complete function
    function EndFunc(): TParseIRBase; override;

    // ---- Statement methods inside Func context (fluent) ----

    // Local variable:  AType AName;
    function DeclVar(const AVarName, AVarType: string): TParseIRBase; overload; override;
    // Local variable:  AType AName = AInitExpr;
    function DeclVar(const AVarName, AVarType, AInitExpr: string): TParseIRBase; overload; override;

    // Assignment:  ALhs = AExpr;
    function Assign(const ALhs, AExpr: string): TParseIRBase; override;

    // Expression lhs assignment:  ATargetExpr = AValueExpr;
    function AssignTo(const ATargetExpr, AValueExpr: string): TParseIRBase; override;

    // Statement-form call:  AFunc(AArgs...);
    function Call(const AFuncName: string;
      const AArgs: TArray<string>): TParseIRBase; override;

    // Verbatim C++ statement line
    function Stmt(const ARawText: string): TParseIRBase; overload; override;
    function Stmt(const ARawText: string; const AArgs: array of const): TParseIRBase; overload; override;

    // return;
    function Return(): TParseIRBase; overload; override;
    // return AExpr;
    function Return(const AExpr: string): TParseIRBase; overload; override;

    // if (ACond) {
    function IfStmt(const ACondExpr: string): TParseIRBase; override;

    // } else if (ACond) {
    function ElseIfStmt(const ACondExpr: string): TParseIRBase; override;

    // } else {
    function ElseStmt(): TParseIRBase; override;

    // }  — closes if/else chain
    function EndIf(): TParseIRBase; override;

    // while (ACond) {
    function WhileStmt(const ACondExpr: string): TParseIRBase; override;

    // }  — closes while
    function EndWhile(): TParseIRBase; override;

    // for (auto AVar = AInit; ACond; AStep) {
    function ForStmt(const AVarName, AInitExpr, ACondExpr,
      AStepExpr: string): TParseIRBase; override;

    // }  — closes for
    function EndFor(): TParseIRBase; override;

    // break;
    function BreakStmt(): TParseIRBase; override;

    // continue;
    function ContinueStmt(): TParseIRBase; override;

    // Emit a blank line
    function BlankLine(
      const ATarget: TParseSourceFile = sfSource): TParseIRBase; override;

    // ---- Expression builders (return string — C++23 text fragments) ----

    // Literals
    function Lit(const AValue: Integer): string; overload; override;
    function Lit(const AValue: Int64): string; overload; override;
    function Float(const AValue: Double): string; override;
    function Str(const AValue: string): string; override;
    function Bool(const AValue: Boolean): string; override;
    function Null(): string; override;

    // Variable / member access
    function Get(const AVarName: string): string; override;
    function Field(const AObj, AMember: string): string; override;
    function Deref(const APtr, AMember: string): string; overload; override;
    function Deref(const APtr: string): string; overload; override;
    function AddrOf(const AVarName: string): string; override;
    function Index(const AArr, AIndexExpr: string): string; override;
    function Cast(const ATypeName, AExpr: string): string; override;

    // Expression-form call:  AFunc(AArgs...)  — returns string, no semicolon
    function Invoke(const AFuncName: string;
      const AArgs: TArray<string>): string; override;

    // Arithmetic
    function Add(const ALeft, ARight: string): string; override;
    function Sub(const ALeft, ARight: string): string; override;
    function Mul(const ALeft, ARight: string): string; override;
    function DivExpr(const ALeft, ARight: string): string; override;
    function ModExpr(const ALeft, ARight: string): string; override;
    function Neg(const AExpr: string): string; override;

    // Comparison
    function Eq(const ALeft, ARight: string): string; override;
    function Ne(const ALeft, ARight: string): string; override;
    function Lt(const ALeft, ARight: string): string; override;
    function Le(const ALeft, ARight: string): string; override;
    function Gt(const ALeft, ARight: string): string; override;
    function Ge(const ALeft, ARight: string): string; override;

    // Logical
    function AndExpr(const ALeft, ARight: string): string; override;
    function OrExpr(const ALeft, ARight: string): string; override;
    function NotExpr(const AExpr: string): string; override;

    // Bitwise
    function BitAnd(const ALeft, ARight: string): string; override;
    function BitOr(const ALeft, ARight: string): string; override;
    function BitXor(const ALeft, ARight: string): string; override;
    function BitNot(const AExpr: string): string; override;
    function ShlExpr(const ALeft, ARight: string): string; override;
    function ShrExpr(const ALeft, ARight: string): string; override;

    // ---- AST walk entry point ----

    // Walks the enriched AST and dispatches registered TParseEmitHandler
    // callbacks from TParseLangConfig. Called by the compiler pipeline
    // after TParseSemantics.Analyze().
    function Generate(const ARoot: TParseASTNodeBase): Boolean;

    // ---- Output ----

    // Write header and source buffers to disk.
    // The .cpp automatically receives:  #include "headerfilename.h"
    procedure SaveToFiles(const AHeaderPath, ASourcePath: string);

    // Direct access to generated content
    function GetHeaderContent(): string;
    function GetSourceContent(): string;

    // Context store — for emitter handlers to share state (e.g. current function name)
    procedure SetContext(const AKey, AValue: string); override;
    function  GetContext(const AKey: string; const ADefault: string = ''): string; override;

    // Debug
    function Dump(const AId: Integer = 0): string; override;
  end;

implementation

{ TParseIR }

constructor TParseIR.Create();
begin
  inherited;
  FHeaderBuffer    := TStringBuilder.Create();
  FSourceBuffer    := TStringBuilder.Create();
  FIndentLevel     := 0;
  FConfig          := nil;
  FInFuncSignature := False;
  FContext         := TDictionary<string, string>.Create();
  FLineDirectives  := False;
  FLastLineFile     := '';
  FLastLineNum      := 0;
end;

destructor TParseIR.Destroy();
begin
  FreeAndNil(FContext);
  FreeAndNil(FSourceBuffer);
  FreeAndNil(FHeaderBuffer);
  inherited;
end;

procedure TParseIR.SetConfig(const AConfig: TParseLangConfig);
begin
  FConfig := AConfig;
end;

procedure TParseIR.SetLineDirectives(const AEnabled: Boolean);
begin
  FLineDirectives := AEnabled;
end;

function TParseIR.GetBuffer(
  const ATarget: TParseSourceFile): TStringBuilder;
begin
  if ATarget = sfHeader then
    Result := FHeaderBuffer
  else
    Result := FSourceBuffer;
end;

function TParseIR.GetIndent(): string;
begin
  Result := StringOfChar(' ', FIndentLevel * 2);
end;

procedure TParseIR.CloseFuncSignature();
begin
  if FInFuncSignature then
  begin
    FInFuncSignature := False;
    FSourceBuffer.AppendLine(') {');
    IndentIn();
  end;
end;

// ---- TParseIRBase virtuals (low-level primitives) ----

procedure TParseIR.EmitLine(const AText: string;
  const ATarget: TParseSourceFile);
begin
  GetBuffer(ATarget).AppendLine(GetIndent() + AText);
end;

procedure TParseIR.EmitLine(const AText: string;
  const AArgs: array of const; const ATarget: TParseSourceFile);
begin
  EmitLine(Format(AText, AArgs), ATarget);
end;

procedure TParseIR.Emit(const AText: string;
  const ATarget: TParseSourceFile);
begin
  GetBuffer(ATarget).Append(AText);
end;

procedure TParseIR.Emit(const AText: string;
  const AArgs: array of const; const ATarget: TParseSourceFile);
begin
  Emit(Format(AText, AArgs), ATarget);
end;

procedure TParseIR.EmitRaw(const AText: string;
  const ATarget: TParseSourceFile);
begin
  GetBuffer(ATarget).Append(AText);
end;

procedure TParseIR.EmitRaw(const AText: string;
  const AArgs: array of const; const ATarget: TParseSourceFile);
begin
  EmitRaw(Format(AText, AArgs), ATarget);
end;

procedure TParseIR.IndentIn();
begin
  Inc(FIndentLevel);
end;

procedure TParseIR.IndentOut();
begin
  if FIndentLevel > 0 then
    Dec(FIndentLevel);
end;

procedure TParseIR.EmitNode(const ANode: TParseASTNodeBase);
var
  LHandler:  TParseEmitHandler;
  LTok:      TParseToken;
  LFilename: string;
begin
  if ANode = nil then
    Exit;

  // Emit a #line directive so debuggers map generated C++ back to the Pascal source.
  // Written directly to the buffer at column 0 — preprocessor directives must
  // never be indented.
  if FLineDirectives and not FInFuncSignature then
  begin
    LTok := ANode.GetToken();
    if (LTok.Filename <> '') and (LTok.Line > 0) then
    begin
      LFilename := LTok.Filename.Replace('\', '/');
      // Only emit when the location actually changes — avoids duplicate
      // #line directives from container nodes sharing the same source position.
      if (LFilename <> FLastLineFile) or (LTok.Line <> FLastLineNum) then
      begin
        FLastLineFile := LFilename;
        FLastLineNum  := LTok.Line;
        FSourceBuffer.AppendLine('#line ' + IntToStr(LTok.Line) +
          ' "' + LFilename + '"');
      end;
    end;
  end;

  // Look up a registered handler for this node kind
  if (FConfig <> nil) and FConfig.GetEmitHandler(ANode.GetNodeKind(), LHandler) then
    LHandler(ANode, Self)
  else
    // No handler registered — auto-walk children
    EmitChildren(ANode);
end;

procedure TParseIR.EmitChildren(const ANode: TParseASTNodeBase);
var
  LI: Integer;
begin
  if ANode = nil then
    Exit;

  for LI := 0 to ANode.ChildCount() - 1 do
    EmitNode(ANode.GetChild(LI));
end;

// ---- Top-level declarations ----

function TParseIR.Include(const AHeaderName: string;
  const ATarget: TParseSourceFile): TParseIRBase;
begin
  // Standard library headers use <>, everything else uses ""
  if (AHeaderName <> '') and (AHeaderName[1] <> '"') and (AHeaderName[1] <> '<') then
    EmitLine('#include <' + AHeaderName + '>', ATarget)
  else
    EmitLine('#include ' + AHeaderName, ATarget);
  Result := Self;
end;

function TParseIR.Struct(const AStructName: string;
  const ATarget: TParseSourceFile): TParseIRBase;
begin
  EmitLine('struct ' + AStructName + ' {', ATarget);
  IndentIn();
  Result := Self;
end;

function TParseIR.AddField(const AFieldName,
  AFieldType: string): TParseIRBase;
begin
  // Fields always go to whatever target the Struct was opened on.
  // Since we don't track target stack, fields emit to sfHeader (struct default).
  EmitLine(AFieldType + ' ' + AFieldName + ';', sfHeader);
  Result := Self;
end;

function TParseIR.EndStruct(): TParseIRBase;
begin
  IndentOut();
  EmitLine('};', sfHeader);
  Result := Self;
end;

function TParseIR.DeclConst(const AConstName, AConstType,
  AValueExpr: string; const ATarget: TParseSourceFile): TParseIRBase;
begin
  if AConstType = '' then
    EmitLine('constexpr auto ' + AConstName + ' = ' + AValueExpr + ';', ATarget)
  else
    EmitLine('constexpr ' + AConstType + ' ' + AConstName + ' = ' + AValueExpr + ';', ATarget);
  Result := Self;
end;

function TParseIR.Global(const AGlobalName, AGlobalType,
  AInitExpr: string; const ATarget: TParseSourceFile): TParseIRBase;
begin
  if AInitExpr = '' then
    EmitLine(AGlobalType + ' ' + AGlobalName + ';', ATarget)
  else
    EmitLine(AGlobalType + ' ' + AGlobalName + ' = ' + AInitExpr + ';', ATarget);
  Result := Self;
end;

function TParseIR.Using(const AAlias, AOriginal: string;
  const ATarget: TParseSourceFile): TParseIRBase;
begin
  EmitLine('using ' + AAlias + ' = ' + AOriginal + ';', ATarget);
  Result := Self;
end;

function TParseIR.Namespace(const ANamespaceName: string;
  const ATarget: TParseSourceFile): TParseIRBase;
begin
  EmitLine('namespace ' + ANamespaceName + ' {', ATarget);
  IndentIn();
  Result := Self;
end;

function TParseIR.EndNamespace(
  const ATarget: TParseSourceFile): TParseIRBase;
begin
  IndentOut();
  EmitLine('} // namespace', ATarget);
  Result := Self;
end;

function TParseIR.ExternC(const AFuncName, AReturnType: string;
  const AParams: TArray<TArray<string>>;
  const ATarget: TParseSourceFile): TParseIRBase;
var
  LParamList: string;
  LI: Integer;
begin
  LParamList := '';
  for LI := 0 to Length(AParams) - 1 do
  begin
    if LI > 0 then
      LParamList := LParamList + ', ';
    // Each param is [name, type]
    LParamList := LParamList + AParams[LI][1] + ' ' + AParams[LI][0];
  end;

  EmitLine('extern "C" ' + AReturnType + ' ' + AFuncName +
    '(' + LParamList + ');', ATarget);
  Result := Self;
end;

// ---- Function / method builder ----

function TParseIR.Func(const AFuncName,
  AReturnType: string): TParseIRBase;
begin
  // Emit the function signature opening — params follow via Param() calls.
  // We buffer the signature and emit the opening brace at the first
  // statement or at EndFunc if no params.
  // Simple approach: emit return type + name, then track state.
  // For simplicity, we emit the signature line-by-line.
  FInFuncSignature := True;
  Emit(GetIndent() + AReturnType + ' ' + AFuncName + '(', sfSource);
  Result := Self;
end;

function TParseIR.Param(const AParamName,
  AParamType: string): TParseIRBase;
begin
  // Params are accumulated inline on the signature line.
  // First param has no comma, subsequent ones do.
  if FSourceBuffer.Length > 0 then
  begin
    if FSourceBuffer.Chars[FSourceBuffer.Length - 1] = '(' then
      Emit(AParamType + ' ' + AParamName, sfSource)
    else
      Emit(', ' + AParamType + ' ' + AParamName, sfSource);
  end;
  Result := Self;
end;

function TParseIR.EndFunc(): TParseIRBase;
begin
  CloseFuncSignature();
  IndentOut();
  EmitLine('}', sfSource);
  GetBuffer(sfSource).AppendLine('');
  Result := Self;
end;

// ---- Statement methods inside Func context ----

function TParseIR.DeclVar(const AVarName,
  AVarType: string): TParseIRBase;
begin
  CloseFuncSignature();
  EmitLine(AVarType + ' ' + AVarName + ';', sfSource);
  Result := Self;
end;

function TParseIR.DeclVar(const AVarName, AVarType,
  AInitExpr: string): TParseIRBase;
begin
  CloseFuncSignature();
  EmitLine(AVarType + ' ' + AVarName + ' = ' + AInitExpr + ';', sfSource);
  Result := Self;
end;

function TParseIR.Assign(const ALhs, AExpr: string): TParseIRBase;
begin
  CloseFuncSignature();
  EmitLine(ALhs + ' = ' + AExpr + ';', sfSource);
  Result := Self;
end;

function TParseIR.AssignTo(const ATargetExpr,
  AValueExpr: string): TParseIRBase;
begin
  CloseFuncSignature();
  EmitLine(ATargetExpr + ' = ' + AValueExpr + ';', sfSource);
  Result := Self;
end;

function TParseIR.Call(const AFuncName: string;
  const AArgs: TArray<string>): TParseIRBase;
var
  LArgList: string;
  LI: Integer;
begin
  CloseFuncSignature();
  LArgList := '';
  for LI := 0 to Length(AArgs) - 1 do
  begin
    if LI > 0 then
      LArgList := LArgList + ', ';
    LArgList := LArgList + AArgs[LI];
  end;
  EmitLine(AFuncName + '(' + LArgList + ');', sfSource);
  Result := Self;
end;

function TParseIR.Stmt(const ARawText: string): TParseIRBase;
begin
  CloseFuncSignature();
  EmitLine(ARawText, sfSource);
  Result := Self;
end;

function TParseIR.Stmt(const ARawText: string;
  const AArgs: array of const): TParseIRBase;
begin
  Result := Stmt(Format(ARawText, AArgs));
end;

function TParseIR.Return(): TParseIRBase;
begin
  CloseFuncSignature();
  EmitLine('return;', sfSource);
  Result := Self;
end;

function TParseIR.Return(const AExpr: string): TParseIRBase;
begin
  CloseFuncSignature();
  EmitLine('return ' + AExpr + ';', sfSource);
  Result := Self;
end;

function TParseIR.IfStmt(const ACondExpr: string): TParseIRBase;
begin
  CloseFuncSignature();
  EmitLine('if (' + ACondExpr + ') {', sfSource);
  IndentIn();
  Result := Self;
end;

function TParseIR.ElseIfStmt(const ACondExpr: string): TParseIRBase;
begin
  IndentOut();
  EmitLine('} else if (' + ACondExpr + ') {', sfSource);
  IndentIn();
  Result := Self;
end;

function TParseIR.ElseStmt(): TParseIRBase;
begin
  IndentOut();
  EmitLine('} else {', sfSource);
  IndentIn();
  Result := Self;
end;

function TParseIR.EndIf(): TParseIRBase;
begin
  IndentOut();
  EmitLine('}', sfSource);
  Result := Self;
end;

function TParseIR.WhileStmt(const ACondExpr: string): TParseIRBase;
begin
  CloseFuncSignature();
  EmitLine('while (' + ACondExpr + ') {', sfSource);
  IndentIn();
  Result := Self;
end;

function TParseIR.EndWhile(): TParseIRBase;
begin
  IndentOut();
  EmitLine('}', sfSource);
  Result := Self;
end;

function TParseIR.ForStmt(const AVarName, AInitExpr, ACondExpr,
  AStepExpr: string): TParseIRBase;
begin
  CloseFuncSignature();
  EmitLine('for (' + AVarName + ' = ' + AInitExpr + '; ' +
    ACondExpr + '; ' + AStepExpr + ') {', sfSource);
  IndentIn();
  Result := Self;
end;

function TParseIR.EndFor(): TParseIRBase;
begin
  IndentOut();
  EmitLine('}', sfSource);
  Result := Self;
end;

function TParseIR.BreakStmt(): TParseIRBase;
begin
  CloseFuncSignature();
  EmitLine('break;', sfSource);
  Result := Self;
end;

function TParseIR.ContinueStmt(): TParseIRBase;
begin
  CloseFuncSignature();
  EmitLine('continue;', sfSource);
  Result := Self;
end;

function TParseIR.BlankLine(
  const ATarget: TParseSourceFile): TParseIRBase;
begin
  GetBuffer(ATarget).AppendLine('');
  Result := Self;
end;

// ---- Expression builders ----

function TParseIR.Lit(const AValue: Integer): string;
begin
  Result := IntToStr(AValue);
end;

function TParseIR.Lit(const AValue: Int64): string;
begin
  Result := IntToStr(AValue) + 'LL';
end;

function TParseIR.Float(const AValue: Double): string;
var
  LFS: TFormatSettings;
begin
  LFS := TFormatSettings.Create();
  LFS.DecimalSeparator := '.';
  Result := FormatFloat('0.0###############', AValue, LFS);
end;

function TParseIR.Str(const AValue: string): string;
begin
  // C++ string literal — basic escaping
  Result := '"' + AValue + '"';
end;

function TParseIR.Bool(const AValue: Boolean): string;
begin
  if AValue then
    Result := 'true'
  else
    Result := 'false';
end;

function TParseIR.Null(): string;
begin
  Result := 'nullptr';
end;

function TParseIR.Get(const AVarName: string): string;
begin
  Result := AVarName;
end;

function TParseIR.Field(const AObj, AMember: string): string;
begin
  Result := AObj + '.' + AMember;
end;

function TParseIR.Deref(const APtr, AMember: string): string;
begin
  Result := APtr + '->' + AMember;
end;

function TParseIR.Deref(const APtr: string): string;
begin
  Result := '*' + APtr;
end;

function TParseIR.AddrOf(const AVarName: string): string;
begin
  Result := '&' + AVarName;
end;

function TParseIR.Index(const AArr, AIndexExpr: string): string;
begin
  Result := AArr + '[' + AIndexExpr + ']';
end;

function TParseIR.Cast(const ATypeName, AExpr: string): string;
begin
  Result := '(' + ATypeName + ')(' + AExpr + ')';
end;

function TParseIR.Invoke(const AFuncName: string;
  const AArgs: TArray<string>): string;
var
  LArgList: string;
  LI: Integer;
begin
  LArgList := '';
  for LI := 0 to Length(AArgs) - 1 do
  begin
    if LI > 0 then
      LArgList := LArgList + ', ';
    LArgList := LArgList + AArgs[LI];
  end;
  Result := AFuncName + '(' + LArgList + ')';
end;

// Arithmetic

function TParseIR.Add(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' + ' + ARight;
end;

function TParseIR.Sub(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' - ' + ARight;
end;

function TParseIR.Mul(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' * ' + ARight;
end;

function TParseIR.DivExpr(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' / ' + ARight;
end;

function TParseIR.ModExpr(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' % ' + ARight;
end;

function TParseIR.Neg(const AExpr: string): string;
begin
  Result := '-' + AExpr;
end;

// Comparison

function TParseIR.Eq(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' == ' + ARight;
end;

function TParseIR.Ne(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' != ' + ARight;
end;

function TParseIR.Lt(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' < ' + ARight;
end;

function TParseIR.Le(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' <= ' + ARight;
end;

function TParseIR.Gt(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' > ' + ARight;
end;

function TParseIR.Ge(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' >= ' + ARight;
end;

// Logical

function TParseIR.AndExpr(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' && ' + ARight;
end;

function TParseIR.OrExpr(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' || ' + ARight;
end;

function TParseIR.NotExpr(const AExpr: string): string;
begin
  Result := '!' + AExpr;
end;

// Bitwise

function TParseIR.BitAnd(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' & ' + ARight;
end;

function TParseIR.BitOr(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' | ' + ARight;
end;

function TParseIR.BitXor(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' ^ ' + ARight;
end;

function TParseIR.BitNot(const AExpr: string): string;
begin
  Result := '~' + AExpr;
end;

function TParseIR.ShlExpr(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' << ' + ARight;
end;

function TParseIR.ShrExpr(const ALeft, ARight: string): string;
begin
  Result := ALeft + ' >> ' + ARight;
end;

// ---- AST walk entry point ----

function TParseIR.Generate(const ARoot: TParseASTNodeBase): Boolean;
var
  LErrors: TParseErrors;
begin
  Result := False;
  LErrors := GetErrors();

  if ARoot = nil then
  begin
    if LErrors <> nil then
      LErrors.Add(esError, ERR_CODEGEN_NIL_ROOT, RSCodeGenNilRoot);
    Exit;
  end;

  if FConfig = nil then
  begin
    if LErrors <> nil then
      LErrors.Add(esError, ERR_CODEGEN_NO_CONFIG, RSCodeGenNoConfig);
    Exit;
  end;

  EmitNode(ARoot);

  if (LErrors <> nil) and LErrors.HasErrors() then
    Exit;

  Result := True;
end;

// ---- Output ----

procedure TParseIR.SaveToFiles(const AHeaderPath,
  ASourcePath: string);
var
  LHeaderDir:  string;
  LSourceDir:  string;
  LHeaderName: string;
begin
  // Ensure output directories exist
  LHeaderDir := ExtractFilePath(AHeaderPath);
  if (LHeaderDir <> '') and (not TDirectory.Exists(LHeaderDir)) then
    TDirectory.CreateDirectory(LHeaderDir);

  LSourceDir := ExtractFilePath(ASourcePath);
  if (LSourceDir <> '') and (not TDirectory.Exists(LSourceDir)) then
    TDirectory.CreateDirectory(LSourceDir);

  // Write header
  TFile.WriteAllText(AHeaderPath, FHeaderBuffer.ToString(), TEncoding.UTF8);

  // Write source — prepend #include "header.h"
  LHeaderName := ExtractFileName(AHeaderPath);
  TFile.WriteAllText(ASourcePath,
    '#include "' + LHeaderName + '"' + sLineBreak + sLineBreak +
    FSourceBuffer.ToString(), TEncoding.UTF8);
end;

function TParseIR.GetHeaderContent(): string;
begin
  Result := FHeaderBuffer.ToString();
end;

function TParseIR.GetSourceContent(): string;
begin
  Result := FSourceBuffer.ToString();
end;

procedure TParseIR.SetContext(const AKey, AValue: string);
begin
  FContext.AddOrSetValue(AKey, AValue);
end;

function TParseIR.GetContext(const AKey: string; const ADefault: string): string;
begin
  if not FContext.TryGetValue(AKey, Result) then
    Result := ADefault;
end;

function TParseIR.Dump(const AId: Integer): string;
begin
  Result := '--- HEADER ---' + sLineBreak +
            FHeaderBuffer.ToString() + sLineBreak +
            '--- SOURCE ---' + sLineBreak +
            FSourceBuffer.ToString();
end;

end.
