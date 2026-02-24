{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

unit UTest.IR;

{$I Parse.Defines.inc}

interface

procedure Test01();
procedure Test02();
procedure Test03();
procedure Test04();
procedure Test05();
procedure Test06();

implementation

uses
  System.SysUtils,
  System.Rtti,
  Parse.Utils,
  Parse.Common,
  Parse.LangConfig,
  Parse.IR;

//=============================================================================
// Shared helpers
//=============================================================================

procedure PrintHeader(const ATitle: string);
begin
  TParseUtils.PrintLn('');
  TParseUtils.PrintLn(COLOR_CYAN + StringOfChar('=', 70));
  TParseUtils.PrintLn(COLOR_CYAN + '  ' + ATitle);
  TParseUtils.PrintLn(COLOR_CYAN + StringOfChar('=', 70));
end;

procedure PrintResult(const APassed: Boolean);
begin
  if APassed then
    TParseUtils.PrintLn(COLOR_GREEN + '  RESULT: PASS')
  else
    TParseUtils.PrintLn(COLOR_RED + '  RESULT: FAIL');
  TParseUtils.PrintLn('');
end;

// Check if AText contains ASubStr; prints pass/fail message
function CheckContains(const AText, ASubStr, ALabel: string): Boolean;
begin
  Result := Pos(ASubStr, AText) > 0;
  if Result then
    TParseUtils.PrintLn(COLOR_GREEN + '  OK: ' + ALabel)
  else
    TParseUtils.PrintLn(COLOR_RED +
      '  FAIL: ' + ALabel + ' — expected to find: ' + ASubStr);
end;

// Check that AText does NOT contain ASubStr
function CheckNotContains(const AText, ASubStr, ALabel: string): Boolean;
begin
  Result := Pos(ASubStr, AText) = 0;
  if Result then
    TParseUtils.PrintLn(COLOR_GREEN + '  OK: ' + ALabel)
  else
    TParseUtils.PrintLn(COLOR_RED +
      '  FAIL: ' + ALabel + ' — should not contain: ' + ASubStr);
end;

//=============================================================================
// Test01 — Dual-buffer output: includes to header, function to source
//
// Builds:
//   #include <cstdint>   → header
//   int32_t add(...)     → source
//
// Verifies header contains #include, source contains function, and
// neither buffer leaks into the other.
//=============================================================================
procedure Test01();
var
  LGen:    TParseIR;
  LHeader: string;
  LSource: string;
  LPassed: Boolean;
begin
  PrintHeader('Test01 — Dual-buffer output: header vs source separation');

  LGen := TParseIR.Create();
  try
    LGen
      .Include('cstdint', sfHeader)
      .Include('iostream', sfHeader);

    LGen
      .Func('add', 'int32_t')
        .Param('a', 'int32_t')
        .Param('b', 'int32_t')
        .Return(LGen.Add(LGen.Get('a'), LGen.Get('b')))
      .EndFunc();

    LHeader := LGen.GetHeaderContent();
    LSource := LGen.GetSourceContent();

    TParseUtils.PrintLn('  --- HEADER ---');
    TParseUtils.PrintLn(LHeader);
    TParseUtils.PrintLn('  --- SOURCE ---');
    TParseUtils.PrintLn(LSource);

    LPassed := True;

    // Header checks
    if not CheckContains(LHeader, '#include <cstdint>', 'header has #include <cstdint>') then
      LPassed := False;
    if not CheckContains(LHeader, '#include <iostream>', 'header has #include <iostream>') then
      LPassed := False;

    // Source checks
    if not CheckContains(LSource, 'int32_t add(', 'source has function signature') then
      LPassed := False;
    if not CheckContains(LSource, 'return a + b;', 'source has return statement') then
      LPassed := False;

    // No cross-leaking
    if not CheckNotContains(LSource, '#include', 'source has no #include') then
      LPassed := False;
    if not CheckNotContains(LHeader, 'int32_t add', 'header has no function body') then
      LPassed := False;

    PrintResult(LPassed);
  finally
    LGen.Free();
  end;
end;

//=============================================================================
// Test02 — Struct to header with fields
//
// Builds:
//   struct TPoint { int32_t X; int32_t Y; };  → header
//
// Verifies struct declaration, field declarations, and closing brace.
//=============================================================================
procedure Test02();
var
  LGen:    TParseIR;
  LHeader: string;
  LPassed: Boolean;
begin
  PrintHeader('Test02 — Struct emitted to header with fields');

  LGen := TParseIR.Create();
  try
    LGen
      .Struct('TPoint', sfHeader)
        .AddField('X', 'int32_t')
        .AddField('Y', 'int32_t')
      .EndStruct();

    LHeader := LGen.GetHeaderContent();

    TParseUtils.PrintLn('  --- HEADER ---');
    TParseUtils.PrintLn(LHeader);

    LPassed := True;

    if not CheckContains(LHeader, 'struct TPoint {', 'struct opening') then
      LPassed := False;
    if not CheckContains(LHeader, 'int32_t X;', 'field X') then
      LPassed := False;
    if not CheckContains(LHeader, 'int32_t Y;', 'field Y') then
      LPassed := False;
    if not CheckContains(LHeader, '};', 'struct closing') then
      LPassed := False;

    PrintResult(LPassed);
  finally
    LGen.Free();
  end;
end;

//=============================================================================
// Test03 — Control flow: if / else if / else / while / for
//
// Builds a function with all control flow constructs and verifies the
// generated C++23 text contains correct syntax with proper indentation.
//=============================================================================
procedure Test03();
var
  LGen:    TParseIR;
  LSource: string;
  LPassed: Boolean;
begin
  PrintHeader('Test03 — Control flow statements');

  LGen := TParseIR.Create();
  try
    LGen
      .Func('test_flow', 'void')
        .Param('x', 'int')
        .IfStmt(LGen.Gt(LGen.Get('x'), LGen.Lit(10)))
          .Call('printf', [LGen.Str('big')])
        .ElseIfStmt(LGen.Eq(LGen.Get('x'), LGen.Lit(0)))
          .Call('printf', [LGen.Str('zero')])
        .ElseStmt()
          .Call('printf', [LGen.Str('small')])
        .EndIf()
        .WhileStmt(LGen.Gt(LGen.Get('x'), LGen.Lit(0)))
          .Assign('x', LGen.Sub(LGen.Get('x'), LGen.Lit(1)))
        .EndWhile()
        .ForStmt('i', LGen.Lit(0),
          LGen.Lt(LGen.Get('i'), LGen.Lit(10)),
          LGen.Get('i++'))
          .BreakStmt()
        .EndFor()
      .EndFunc();

    LSource := LGen.GetSourceContent();

    TParseUtils.PrintLn('  --- SOURCE ---');
    TParseUtils.PrintLn(LSource);

    LPassed := True;

    if not CheckContains(LSource, 'if (x > 10) {', 'if statement') then
      LPassed := False;
    if not CheckContains(LSource, '} else if (x == 0) {', 'else if') then
      LPassed := False;
    if not CheckContains(LSource, '} else {', 'else') then
      LPassed := False;
    if not CheckContains(LSource, 'while (x > 0) {', 'while loop') then
      LPassed := False;
    if not CheckContains(LSource, 'x = x - 1;', 'assignment in while') then
      LPassed := False;
    if not CheckContains(LSource, 'for (auto i = 0;', 'for loop') then
      LPassed := False;
    if not CheckContains(LSource, 'break;', 'break statement') then
      LPassed := False;

    PrintResult(LPassed);
  finally
    LGen.Free();
  end;
end;

//=============================================================================
// Test04 — Expression builders: all arithmetic, comparison, logical, bitwise
//
// Verifies each expression builder returns the correct C++23 text fragment.
//=============================================================================
procedure Test04();
var
  LGen:    TParseIR;
  LPassed: Boolean;

  function Check(const AActual, AExpected, ALabel: string): Boolean;
  begin
    Result := AActual = AExpected;
    if Result then
      TParseUtils.PrintLn(COLOR_GREEN + '  OK: ' + ALabel +
        ' → ' + AActual)
    else
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: ' + ALabel +
        ' — expected "' + AExpected + '", got "' + AActual + '"');
  end;

begin
  PrintHeader('Test04 — Expression builders');

  LGen := TParseIR.Create();
  try
    LPassed := True;

    // Literals
    if not Check(LGen.Lit(42),       '42',        'Lit(int)') then LPassed := False;
    if not Check(LGen.Float(3.14),   '3.14',      'Float') then LPassed := False;
    if not Check(LGen.Str('hello'),  '"hello"',   'Str') then LPassed := False;
    if not Check(LGen.Bool(True),    'true',       'Bool(true)') then LPassed := False;
    if not Check(LGen.Bool(False),   'false',      'Bool(false)') then LPassed := False;
    if not Check(LGen.Null(),        'nullptr',    'Null') then LPassed := False;

    // Access
    if not Check(LGen.Get('x'),             'x',          'Get') then LPassed := False;
    if not Check(LGen.Field('pt', 'X'),     'pt.X',       'Field') then LPassed := False;
    if not Check(LGen.Deref('ptr', 'val'),  'ptr->val',   'Deref(member)') then LPassed := False;
    if not Check(LGen.Deref('ptr'),         '*ptr',        'Deref(ptr)') then LPassed := False;
    if not Check(LGen.AddrOf('x'),          '&x',          'AddrOf') then LPassed := False;
    if not Check(LGen.Index('arr', 'i'),    'arr[i]',      'Index') then LPassed := False;
    if not Check(LGen.Cast('int', 'x'),     '(int)(x)',    'Cast') then LPassed := False;
    if not Check(LGen.Invoke('foo', ['a', 'b']), 'foo(a, b)', 'Invoke') then LPassed := False;

    // Arithmetic
    if not Check(LGen.Add('a', 'b'),      'a + b',   'Add') then LPassed := False;
    if not Check(LGen.Sub('a', 'b'),      'a - b',   'Sub') then LPassed := False;
    if not Check(LGen.Mul('a', 'b'),      'a * b',   'Mul') then LPassed := False;
    if not Check(LGen.DivExpr('a', 'b'),  'a / b',   'DivExpr') then LPassed := False;
    if not Check(LGen.ModExpr('a', 'b'),  'a % b',   'ModExpr') then LPassed := False;
    if not Check(LGen.Neg('x'),           '-x',       'Neg') then LPassed := False;

    // Comparison
    if not Check(LGen.Eq('a', 'b'),  'a == b',  'Eq') then LPassed := False;
    if not Check(LGen.Ne('a', 'b'),  'a != b',  'Ne') then LPassed := False;
    if not Check(LGen.Lt('a', 'b'),  'a < b',   'Lt') then LPassed := False;
    if not Check(LGen.Le('a', 'b'),  'a <= b',  'Le') then LPassed := False;
    if not Check(LGen.Gt('a', 'b'),  'a > b',   'Gt') then LPassed := False;
    if not Check(LGen.Ge('a', 'b'),  'a >= b',  'Ge') then LPassed := False;

    // Logical
    if not Check(LGen.AndExpr('a', 'b'),  'a && b',  'AndExpr') then LPassed := False;
    if not Check(LGen.OrExpr('a', 'b'),   'a || b',  'OrExpr') then LPassed := False;
    if not Check(LGen.NotExpr('x'),       '!x',       'NotExpr') then LPassed := False;

    // Bitwise
    if not Check(LGen.BitAnd('a', 'b'),  'a & b',   'BitAnd') then LPassed := False;
    if not Check(LGen.BitOr('a', 'b'),   'a | b',   'BitOr') then LPassed := False;
    if not Check(LGen.BitXor('a', 'b'),  'a ^ b',   'BitXor') then LPassed := False;
    if not Check(LGen.BitNot('x'),       '~x',       'BitNot') then LPassed := False;
    if not Check(LGen.ShlExpr('a', 'b'), 'a << b',   'ShlExpr') then LPassed := False;
    if not Check(LGen.ShrExpr('a', 'b'), 'a >> b',   'ShrExpr') then LPassed := False;

    PrintResult(LPassed);
  finally
    LGen.Free();
  end;
end;

//=============================================================================
// Test05 — Full example from DESIGN.md
//
// Reproduces the exact example from the design document and verifies:
//   - header: #include, struct
//   - source: add function, main function with locals, assignment, if, return
//=============================================================================
procedure Test05();
var
  LGen:    TParseIR;
  LHeader: string;
  LSource: string;
  LPassed: Boolean;
begin
  PrintHeader('Test05 — Full DESIGN.md example');

  LGen := TParseIR.Create();
  try
    LGen
      .Include('cstdint', sfHeader)
      .Include('iostream', sfHeader);

    LGen
      .Struct('TPoint', sfHeader)
        .AddField('X', 'int32_t')
        .AddField('Y', 'int32_t')
      .EndStruct();

    LGen
      .Func('add', 'int32_t')
        .Param('a', 'int32_t')
        .Param('b', 'int32_t')
        .Return(LGen.Add(LGen.Get('a'), LGen.Get('b')))
      .EndFunc();

    LGen
      .Func('main', 'int')
        .Param('argc', 'int')
        .Param('argv', 'char**')
        .DeclVar('pt', 'TPoint')
        .Assign('pt.X', LGen.Lit(10))
        .Assign('pt.Y', LGen.Lit(20))
        .IfStmt(LGen.Gt(LGen.Get('pt.X'), LGen.Lit(0)))
          .Stmt('std::cout << "positive\n"')
        .EndIf()
        .Return(LGen.Lit(0))
      .EndFunc();

    LHeader := LGen.GetHeaderContent();
    LSource := LGen.GetSourceContent();

    TParseUtils.PrintLn('  --- HEADER ---');
    TParseUtils.PrintLn(LHeader);
    TParseUtils.PrintLn('  --- SOURCE ---');
    TParseUtils.PrintLn(LSource);

    LPassed := True;

    // Header
    if not CheckContains(LHeader, '#include <cstdint>', 'cstdint include') then
      LPassed := False;
    if not CheckContains(LHeader, 'struct TPoint {', 'struct') then
      LPassed := False;
    if not CheckContains(LHeader, 'int32_t X;', 'field X') then
      LPassed := False;

    // Source — add function
    if not CheckContains(LSource, 'int32_t add(int32_t a, int32_t b)', 'add signature') then
      LPassed := False;
    if not CheckContains(LSource, 'return a + b;', 'add return') then
      LPassed := False;

    // Source — main function
    if not CheckContains(LSource, 'int main(int argc, char** argv)', 'main signature') then
      LPassed := False;
    if not CheckContains(LSource, 'TPoint pt;', 'local var') then
      LPassed := False;
    if not CheckContains(LSource, 'pt.X = 10;', 'assign X') then
      LPassed := False;
    if not CheckContains(LSource, 'pt.Y = 20;', 'assign Y') then
      LPassed := False;
    if not CheckContains(LSource, 'if (pt.X > 0) {', 'if condition') then
      LPassed := False;
    if not CheckContains(LSource, 'std::cout << "positive\n"', 'cout stmt') then
      LPassed := False;
    if not CheckContains(LSource, 'return 0;', 'return 0') then
      LPassed := False;

    PrintResult(LPassed);
  finally
    LGen.Free();
  end;
end;

//=============================================================================
// Test06 — Generate() dispatches emit handlers from TParseLangConfig
//
// Builds a minimal AST by hand, registers an emit handler for its node
// kind via TParseLangConfig, calls Generate(), and verifies the handler
// was invoked and produced the expected output.
//=============================================================================
procedure Test06();
var
  LGen:    TParseIR;
  LConfig: TParseLangConfig;
  LRoot:   TParseASTNode;
  LChild:  TParseASTNode;
  LToken:  TParseToken;
  LSource: string;
  LPassed: Boolean;
  LOk:     Boolean;
begin
  PrintHeader('Test06 — Generate() dispatches registered emit handlers');

  LGen    := nil;
  LConfig := nil;
  LRoot   := nil;
  try
    LConfig := TParseLangConfig.Create();

    // Register an emit handler for 'stmt.print' that emits a printf call
    LConfig.RegisterEmitter('stmt.print',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LAttrVal: TValue;
        LText:    string;
      begin
        LText := 'unknown';
        if ANode.GetAttr('message', LAttrVal) then
          LText := LAttrVal.AsType<string>();
        AGen.EmitLine('printf("' + LText + '");');
      end);

    // Register an emit handler for 'program.root' that walks children
    LConfig.RegisterEmitter('program.root',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        AGen.EmitChildren(ANode);
      end);

    // Build a minimal AST by hand:
    //   program.root
    //     stmt.print  [message='hello world']
    //     stmt.print  [message='goodbye']
    LToken := Default(TParseToken);
    LToken.Kind := 'eof';
    LToken.Filename := 'test06.txt';
    LToken.Line := 1;

    LRoot := TParseASTNode.CreateNode('program.root', LToken);

    LChild := TParseASTNode.CreateNode('stmt.print', LToken);
    LChild.SetAttr('message', TValue.From<string>('hello world'));
    LRoot.AddChild(LChild);

    LChild := TParseASTNode.CreateNode('stmt.print', LToken);
    LChild.SetAttr('message', TValue.From<string>('goodbye'));
    LRoot.AddChild(LChild);

    // Generate
    LGen := TParseIR.Create();
    LGen.SetConfig(LConfig);

    LOk := LGen.Generate(LRoot);

    LSource := LGen.GetSourceContent();

    TParseUtils.PrintLn('  --- SOURCE ---');
    TParseUtils.PrintLn(LSource);

    LPassed := True;

    if not LOk then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: Generate() returned False');
      LPassed := False;
    end;

    if not CheckContains(LSource, 'printf("hello world");', 'first print emitted') then
      LPassed := False;
    if not CheckContains(LSource, 'printf("goodbye");', 'second print emitted') then
      LPassed := False;

    PrintResult(LPassed);

  finally
    FreeAndNil(LRoot);
    FreeAndNil(LGen);
    FreeAndNil(LConfig);
  end;
end;

end.
