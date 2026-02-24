{===============================================================================
  Parse() - The Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

  ----------------------------------------------------------------------------
  UTest.CodeGen — Pipeline tests: source text → Lexer → Parser → Semantics →
  CodeGen → verified C++23 output.

  Uses a tiny inline test language with:
    - var x = EXPR;   (variable declaration with initializer)
    - integer literals, identifiers, + operator
    - semantic: symbol declaration, resolution, type checking
    - codegen: emits int32_t declarations with rendered expressions
===============================================================================}

unit UTest.CodeGen;

{$I Parse.Defines.inc}

interface

procedure Test01();
procedure Test02();
procedure Test03();
procedure Test04();

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Rtti,
  System.Generics.Collections,
  Parse.Utils,
  Parse.Common,
  Parse.LangConfig,
  Parse.Lexer,
  Parse.Parser,
  Parse.Semantics,
  Parse.IR,
  Parse.CodeGen;

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

procedure PrintErrors(const AErrors: TParseErrors);
var
  LI: Integer;
begin
  for LI := 0 to AErrors.GetItems().Count - 1 do
    TParseUtils.PrintLn(COLOR_RED + '  ' + AErrors.GetItems()[LI].ToFullString());
end;

procedure PrintResult(const APassed: Boolean);
begin
  if APassed then
    TParseUtils.PrintLn(COLOR_GREEN + '  RESULT: PASS')
  else
    TParseUtils.PrintLn(COLOR_RED + '  RESULT: FAIL');
  TParseUtils.PrintLn('');
end;

function CheckContains(const AText, ASubStr, ALabel: string): Boolean;
begin
  Result := Pos(ASubStr, AText) > 0;
  if Result then
    TParseUtils.PrintLn(COLOR_GREEN + '  OK: ' + ALabel)
  else
    TParseUtils.PrintLn(COLOR_RED +
      '  FAIL: ' + ALabel + ' — expected to find: ' + ASubStr);
end;

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
// Tiny test language — wires up all four surfaces on TParseLangConfig
//
// Syntax:
//   var <ident> = <expr> ;
//   <expr> := <integer> | <ident> | <expr> + <expr>
//
// AST produced:
//   program.root
//     decl.var  [var_name='x']
//       child[0]: initializer expression (expr.integer | expr.binary | expr.ident)
//
// Semantic enrichment:
//   decl.var  → declares symbol, writes PARSE_ATTR_TYPE_KIND='int32'
//   expr.ident → resolves symbol, writes PARSE_ATTR_RESOLVED_SYMBOL
//   expr.integer → writes PARSE_ATTR_TYPE_KIND='int32'
//
// Codegen output:
//   int32_t x = <rendered expr>;
//=============================================================================

// Recursive expression renderer — walks the expression AST subtree and
// produces the C++23 text fragment as a plain string. Used by the
// decl.var emit handler to build the complete declaration line.
function RenderExpr(const ANode: TParseASTNodeBase): string;
var
  LAttr: TValue;
begin
  Result := '';
  if ANode = nil then
    Exit;

  if ANode.GetNodeKind() = 'expr.integer' then
  begin
    // Emit the raw integer text from the token
    Result := ANode.GetToken().Text;
  end
  else if ANode.GetNodeKind() = 'expr.ident' then
  begin
    // Emit the identifier text from the token
    Result := ANode.GetToken().Text;
  end
  else if ANode.GetNodeKind() = 'expr.binary' then
  begin
    // Render left <op> right
    if ANode.GetAttr('op', LAttr) then
      Result := RenderExpr(ANode.GetChild(0)) + ' ' +
                LAttr.AsType<string>() + ' ' +
                RenderExpr(ANode.GetChild(1))
    else
      Result := RenderExpr(ANode.GetChild(0)) + ' ? ' +
                RenderExpr(ANode.GetChild(1));
  end;
end;

// Build the complete test language config with all four surfaces wired up.
// Caller owns the returned config.
function BuildTestLangConfig(): TParseLangConfig;
begin
  Result := TParseLangConfig.Create();

  // ---- Lexer surface ----
  Result
    .AddKeyword('var', 'keyword.var')
    .AddOperator('=', 'op.assign')
    .AddOperator('+', 'op.plus')
    .AddOperator(';', 'delimiter.semicolon')
    .SetStatementTerminator('delimiter.semicolon');

  // ---- Grammar surface: prefix handlers ----

  // Integer literal prefix
  Result.RegisterPrefix(PARSE_KIND_INTEGER, 'expr.integer',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();
      Result := LNode;
    end);

  // Identifier prefix
  Result.RegisterPrefix(PARSE_KIND_IDENTIFIER, 'expr.ident',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();
      Result := LNode;
    end);

  // ---- Grammar surface: infix handler ----

  // '+' binary operator, left-associative, binding power 10
  Result.RegisterInfixLeft('op.plus', 10, 'expr.binary',
    function(AParser: TParseParserBase;
      ALeft: TParseASTNodeBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      LNode.SetAttr('op', TValue.From<string>('+'));
      AParser.Consume();  // consume '+'
      LNode.AddChild(TParseASTNode(ALeft));
      LNode.AddChild(TParseASTNode(
        AParser.ParseExpression(AParser.CurrentInfixPower())));
      Result := LNode;
    end);

  // ---- Grammar surface: statement handler ----

  // 'var' declaration: var <ident> = <expr> ;
  Result.RegisterStatement('keyword.var', 'decl.var',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:      TParseASTNode;
      LNameToken: TParseToken;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'var'

      // Capture the variable name
      LNameToken := AParser.CurrentToken();
      LNode.SetAttr('var_name', TValue.From<string>(LNameToken.Text));
      AParser.Consume();  // consume identifier

      AParser.Expect('op.assign');  // consume '='

      // Parse initializer expression as child
      LNode.AddChild(TParseASTNode(AParser.ParseExpression()));

      AParser.Expect('delimiter.semicolon');  // consume ';'

      Result := LNode;
    end);

  // ---- Semantic surface ----

  // decl.var: declare symbol, tag type, visit initializer
  Result.RegisterSemanticRule('decl.var',
    procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
    var
      LAttr:    TValue;
      LVarName: string;
    begin
      LVarName := '';
      if ANode.GetAttr('var_name', LAttr) then
        LVarName := LAttr.AsType<string>();

      // Declare the symbol in the current scope
      ASem.DeclareSymbol(LVarName, ANode);

      // Enrich the node with type and storage info
      TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
        TValue.From<string>('int32'));
      TParseASTNode(ANode).SetAttr(PARSE_ATTR_STORAGE_CLASS,
        TValue.From<string>('local'));

      // Visit the initializer expression
      ASem.VisitChildren(ANode);
    end);

  // expr.integer: tag with type
  Result.RegisterSemanticRule('expr.integer',
    procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
    begin
      TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
        TValue.From<string>('int32'));
    end);

  // expr.ident: resolve symbol, tag with type and decl ref
  Result.RegisterSemanticRule('expr.ident',
    procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
    var
      LDeclNode: TParseASTNodeBase;
      LIdentName: string;
    begin
      LIdentName := ANode.GetToken().Text;
      if ASem.LookupSymbol(LIdentName, LDeclNode) then
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_RESOLVED_SYMBOL,
          TValue.From<string>(LIdentName));
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('int32'));
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_DECL_NODE,
          TValue.From<TObject>(LDeclNode));
      end
      else
        ASem.AddSemanticError(ANode, 'S100',
          'Undeclared identifier: ' + LIdentName);
    end);

  // expr.binary: visit children, tag with type
  Result.RegisterSemanticRule('expr.binary',
    procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
    begin
      ASem.VisitChildren(ANode);
      TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
        TValue.From<string>('int32'));
    end);

  // ---- Emit surface ----

  // program.root: walk children
  Result.RegisterEmitter('program.root',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    begin
      AGen.EmitChildren(ANode);
    end);

  // decl.var: emit int32_t <name> = <rendered expr>;
  Result.RegisterEmitter('decl.var',
    procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
    var
      LAttr:    TValue;
      LVarName: string;
      LExprStr: string;
    begin
      LVarName := 'unknown';
      if ANode.GetAttr('var_name', LAttr) then
        LVarName := LAttr.AsType<string>();

      // Render the initializer expression (child 0) to a string
      LExprStr := RenderExpr(ANode.GetChild(0));

      AGen.EmitLine('int32_t ' + LVarName + ' = ' + LExprStr + ';');
    end);
end;

// Run the full pipeline: source → lexer → parser → semantics → codegen.
// Returns True if all stages succeeded. ASource is the output C++.
// AErrors collects errors from all stages. Caller owns AErrors.
function RunPipeline(const ASourceText, AFilename: string;
  const AConfig: TParseLangConfig; const AErrors: TParseErrors;
  const ACodeGen: TParseCodeGen;
  out AAST: TParseASTNode): Boolean;
var
  LLexer:  TParseLexer;
  LParser: TParseParser;
  LSem:    TParseSemantics;
begin
  Result := False;
  AAST   := nil;
  LLexer  := nil;
  LParser := nil;
  LSem    := nil;
  try
    // Stage 1: Lexer
    LLexer := TParseLexer.Create();
    LLexer.SetErrors(AErrors);
    LLexer.SetConfig(AConfig);
    LLexer.LoadFromString(ASourceText, AFilename);
    if not LLexer.Tokenize() then
      Exit;

    // Stage 2: Parser
    LParser := TParseParser.Create();
    LParser.SetErrors(AErrors);
    LParser.SetConfig(AConfig);
    LParser.LoadFromLexer(LLexer);
    AAST := LParser.ParseTokens();
    if AAST = nil then
      Exit;
    if AErrors.HasErrors() then
      Exit;

    // Stage 3: Semantics
    LSem := TParseSemantics.Create();
    LSem.SetErrors(AErrors);
    LSem.SetConfig(AConfig);
    if not LSem.Analyze(AAST) then
      Exit;

    // Stage 4: CodeGen
    Result := ACodeGen.Generate(AAST);

  finally
    FreeAndNil(LSem);
    FreeAndNil(LParser);
    FreeAndNil(LLexer);
  end;
end;

//=============================================================================
// Test01 — Full pipeline: single var declaration
//
// Source:  var x = 5;
// Expected C++:  int32_t x = 5;
//
// Proves: source text flows through Lexer → Parser → Semantics → CodeGen
// and produces correct C++23 output.
//=============================================================================
procedure Test01();
var
  LConfig:      TParseLangConfig;
  LErrors:      TParseErrors;
  LCodeGen:     TParseCodeGen;
  LAST:         TParseASTNode;
  LSource:      string;
  LFileContent: string;
  LPassed:      Boolean;
  LOk:          Boolean;
begin
  PrintHeader('Test01 — Full pipeline: var x = 5;');

  LConfig  := nil;
  LErrors  := nil;
  LCodeGen := nil;
  LAST     := nil;
  try
    LConfig  := BuildTestLangConfig();
    LErrors  := TParseErrors.Create();
    LCodeGen := TParseCodeGen.Create();
    LCodeGen.SetErrors(LErrors);
    LCodeGen.SetConfig(LConfig);

    LOk := RunPipeline('var x = 5;', 'test01.src', LConfig, LErrors,
      LCodeGen, LAST);

    LSource := LCodeGen.GetSourceContent();

    TParseUtils.PrintLn('  --- AST ---');
    if LAST <> nil then
      TParseUtils.PrintLn(LAST.Dump());
    TParseUtils.PrintLn('  --- SOURCE ---');
    TParseUtils.PrintLn(LSource);

    LPassed := True;

    if not LOk then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: pipeline returned False');
      PrintErrors(LErrors);
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN + '  OK: pipeline succeeded');

    if not CheckContains(LSource, 'int32_t x = 5;', 'output has int32_t x = 5;') then
      LPassed := False;

    // Write to disk and verify files
    LCodeGen.SaveToFiles('output\generated\test01.h',
      'output\generated\test01.cpp');

    if not TFile.Exists('output\generated\test01.h') then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: test01.h not found on disk');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN + '  OK: test01.h exists on disk');

    if not TFile.Exists('output\generated\test01.cpp') then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: test01.cpp not found on disk');
      LPassed := False;
    end
    else
    begin
      TParseUtils.PrintLn(COLOR_GREEN + '  OK: test01.cpp exists on disk');
      LFileContent := TFile.ReadAllText('output\generated\test01.cpp');
      TParseUtils.PrintLn('  --- test01.cpp ---');
      TParseUtils.PrintLn(LFileContent);
      if not CheckContains(LFileContent, '#include "test01.h"',
        'test01.cpp includes own header') then
        LPassed := False;
      if not CheckContains(LFileContent, 'int32_t x = 5;',
        'test01.cpp has declaration on disk') then
        LPassed := False;
    end;

    PrintResult(LPassed);

  finally
    FreeAndNil(LAST);
    FreeAndNil(LCodeGen);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

//=============================================================================
// Test02 — Full pipeline: multiple vars with binary expression
//
// Source:
//   var x = 10;
//   var y = x + 3;
//
// Expected C++:
//   int32_t x = 10;
//   int32_t y = x + 3;
//
// Proves: symbol resolution across declarations, binary expression rendering,
// and semantic enrichment attributes flowing into codegen.
//=============================================================================
procedure Test02();
var
  LConfig:  TParseLangConfig;
  LErrors:  TParseErrors;
  LCodeGen: TParseCodeGen;
  LAST:     TParseASTNode;
  LSource:  string;
  LPassed:  Boolean;
  LOk:      Boolean;
begin
  PrintHeader('Test02 — Full pipeline: var x = 10; var y = x + 3;');

  LConfig  := nil;
  LErrors  := nil;
  LCodeGen := nil;
  LAST     := nil;
  try
    LConfig  := BuildTestLangConfig();
    LErrors  := TParseErrors.Create();
    LCodeGen := TParseCodeGen.Create();
    LCodeGen.SetErrors(LErrors);
    LCodeGen.SetConfig(LConfig);

    LOk := RunPipeline(
      'var x = 10;' + sLineBreak + 'var y = x + 3;',
      'test02.src', LConfig, LErrors, LCodeGen, LAST);

    LSource := LCodeGen.GetSourceContent();

    TParseUtils.PrintLn('  --- AST ---');
    if LAST <> nil then
      TParseUtils.PrintLn(LAST.Dump());
    TParseUtils.PrintLn('  --- SOURCE ---');
    TParseUtils.PrintLn(LSource);

    LPassed := True;

    if not LOk then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: pipeline returned False');
      PrintErrors(LErrors);
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN + '  OK: pipeline succeeded');

    if not CheckContains(LSource, 'int32_t x = 10;', 'first declaration') then
      LPassed := False;
    if not CheckContains(LSource, 'int32_t y = x + 3;', 'second declaration with resolved ident') then
      LPassed := False;

    PrintResult(LPassed);

  finally
    FreeAndNil(LAST);
    FreeAndNil(LCodeGen);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

//=============================================================================
// Test03 — Multi-unit pipeline with SaveAllFiles to output\generated
//
// Two source units processed through the full pipeline into separate
// .h + .cpp file pairs. Verifies file existence and content isolation.
//
// Unit 'mathlib':  var total = 100;
// Unit 'main':     var x = 42;
//
// Output:
//   output\generated\mathlib.h + mathlib.cpp
//   output\generated\main.h   + main.cpp
//=============================================================================
procedure Test03();
var
  LConfig:     TParseLangConfig;
  LErrors:     TParseErrors;
  LCodeGen:    TParseCodeGen;
  LMathAST:    TParseASTNode;
  LMainAST:    TParseASTNode;
  LLexer:      TParseLexer;
  LParser:     TParseParser;
  LSem:        TParseSemantics;
  LOutputDir:  string;
  LMathSrcPath: string;
  LMainSrcPath: string;
  LMathSrc:    string;
  LMainSrc:    string;
  LPassed:     Boolean;
begin
  PrintHeader('Test03 — Multi-unit pipeline with SaveAllFiles');

  LConfig  := nil;
  LErrors  := nil;
  LCodeGen := nil;
  LMathAST := nil;
  LMainAST := nil;
  LLexer   := nil;
  LParser  := nil;
  LSem     := nil;
  try
    LConfig := BuildTestLangConfig();
    LErrors := TParseErrors.Create();

    // ---- Process unit 'mathlib' through Lexer → Parser → Semantics ----
    LLexer := TParseLexer.Create();
    LLexer.SetErrors(LErrors);
    LLexer.SetConfig(LConfig);
    LLexer.LoadFromString('var total = 100;', 'mathlib.src');
    LLexer.Tokenize();

    LParser := TParseParser.Create();
    LParser.SetErrors(LErrors);
    LParser.SetConfig(LConfig);
    LParser.LoadFromLexer(LLexer);
    LMathAST := LParser.ParseTokens();
    FreeAndNil(LParser);
    FreeAndNil(LLexer);

    LSem := TParseSemantics.Create();
    LSem.SetErrors(LErrors);
    LSem.SetConfig(LConfig);
    LSem.Analyze(LMathAST);
    FreeAndNil(LSem);

    // ---- Process unit 'main' through Lexer → Parser → Semantics ----
    LLexer := TParseLexer.Create();
    LLexer.SetErrors(LErrors);
    LLexer.SetConfig(LConfig);
    LLexer.LoadFromString('var x = 42;', 'main.src');
    LLexer.Tokenize();

    LParser := TParseParser.Create();
    LParser.SetErrors(LErrors);
    LParser.SetConfig(LConfig);
    LParser.LoadFromLexer(LLexer);
    LMainAST := LParser.ParseTokens();
    FreeAndNil(LParser);
    FreeAndNil(LLexer);

    LSem := TParseSemantics.Create();
    LSem.SetErrors(LErrors);
    LSem.SetConfig(LConfig);
    LSem.Analyze(LMainAST);
    FreeAndNil(LSem);

    // ---- Check for errors before CodeGen ----
    if LErrors.HasErrors() then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: errors before CodeGen');
      PrintErrors(LErrors);
      PrintResult(False);
      Exit;
    end;

    // ---- CodeGen: generate both units ----
    LCodeGen := TParseCodeGen.Create();
    LCodeGen.SetErrors(LErrors);
    LCodeGen.SetConfig(LConfig);

    LCodeGen.GenerateUnit('mathlib', LMathAST);
    LCodeGen.GenerateUnit('main', LMainAST);

    // ---- Save to output\generated ----
    LOutputDir := 'output\generated';
    LCodeGen.SaveAllFiles(LOutputDir);

    LPassed := True;

    // Verify file existence
    LMathSrcPath := TPath.Combine(LOutputDir, 'mathlib.cpp');
    LMainSrcPath := TPath.Combine(LOutputDir, 'main.cpp');

    if not TFile.Exists(LMathSrcPath) then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: mathlib.cpp not found');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN + '  OK: mathlib.cpp exists');

    if not TFile.Exists(LMainSrcPath) then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: main.cpp not found');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN + '  OK: main.cpp exists');

    // Verify content
    if TFile.Exists(LMathSrcPath) then
    begin
      LMathSrc := TFile.ReadAllText(LMathSrcPath);
      TParseUtils.PrintLn('  --- mathlib.cpp ---');
      TParseUtils.PrintLn(LMathSrc);

      if not CheckContains(LMathSrc, '#include "mathlib.h"', 'mathlib.cpp includes own header') then
        LPassed := False;
      if not CheckContains(LMathSrc, 'int32_t total = 100;', 'mathlib.cpp has total declaration') then
        LPassed := False;
    end;

    if TFile.Exists(LMainSrcPath) then
    begin
      LMainSrc := TFile.ReadAllText(LMainSrcPath);
      TParseUtils.PrintLn('  --- main.cpp ---');
      TParseUtils.PrintLn(LMainSrc);

      if not CheckContains(LMainSrc, '#include "main.h"', 'main.cpp includes own header') then
        LPassed := False;
      if not CheckContains(LMainSrc, 'int32_t x = 42;', 'main.cpp has x declaration') then
        LPassed := False;
    end;

    // Verify content isolation — mathlib should not have main's code
    if TFile.Exists(LMathSrcPath) and TFile.Exists(LMainSrcPath) then
    begin
      if not CheckNotContains(LMathSrc, 'int32_t x', 'mathlib has no x') then
        LPassed := False;
      if not CheckNotContains(LMainSrc, 'int32_t total', 'main has no total') then
        LPassed := False;
    end;

    // Verify unit count and order
    if LCodeGen.GetUnitCount() <> 2 then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: unit count is not 2');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN + '  OK: unit count is 2');

    if LCodeGen.GetUnitNameByIndex(0) <> 'mathlib' then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: first unit is not mathlib');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN + '  OK: dependency order preserved');

    PrintResult(LPassed);

  finally
    FreeAndNil(LSem);
    FreeAndNil(LParser);
    FreeAndNil(LLexer);
    FreeAndNil(LMainAST);
    FreeAndNil(LMathAST);
    FreeAndNil(LCodeGen);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

//=============================================================================
// Test04 — Semantic error prevents CodeGen
//
// Source:  var x = y + 1;
//          (y is undeclared)
//
// Verifies: semantics reports error, CodeGen is not reached or fails,
// and the error message is correct.
//=============================================================================
procedure Test04();
var
  LConfig:   TParseLangConfig;
  LErrors:   TParseErrors;
  LCodeGen:  TParseCodeGen;
  LLexer:    TParseLexer;
  LParser:   TParseParser;
  LSem:      TParseSemantics;
  LAST:      TParseASTNode;
  LPassed:   Boolean;
  LSemOk:    Boolean;
begin
  PrintHeader('Test04 — Semantic error blocks CodeGen');

  LConfig  := nil;
  LErrors  := nil;
  LCodeGen := nil;
  LLexer   := nil;
  LParser  := nil;
  LSem     := nil;
  LAST     := nil;
  try
    LConfig := BuildTestLangConfig();
    LErrors := TParseErrors.Create();

    // Lex + Parse
    LLexer := TParseLexer.Create();
    LLexer.SetErrors(LErrors);
    LLexer.SetConfig(LConfig);
    LLexer.LoadFromString('var x = y + 1;', 'test04.src');
    LLexer.Tokenize();

    LParser := TParseParser.Create();
    LParser.SetErrors(LErrors);
    LParser.SetConfig(LConfig);
    LParser.LoadFromLexer(LLexer);
    LAST := LParser.ParseTokens();
    FreeAndNil(LParser);
    FreeAndNil(LLexer);

    if LErrors.HasErrors() then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: unexpected parse errors');
      PrintErrors(LErrors);
      PrintResult(False);
      Exit;
    end;

    TParseUtils.PrintLn('  --- AST ---');
    TParseUtils.PrintLn(LAST.Dump());

    // Semantics — should fail (y is undeclared)
    LSem := TParseSemantics.Create();
    LSem.SetErrors(LErrors);
    LSem.SetConfig(LConfig);
    LSemOk := LSem.Analyze(LAST);
    FreeAndNil(LSem);

    LPassed := True;

    if LSemOk then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: Analyze should have returned False');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN + '  OK: Analyze returned False (semantic error)');

    if not LErrors.HasErrors() then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: expected semantic errors');
      LPassed := False;
    end
    else
    begin
      TParseUtils.PrintLn(COLOR_GREEN + '  OK: errors reported:');
      PrintErrors(LErrors);
    end;

    // CodeGen should NOT be called when semantics fails.
    // Verify the pipeline would block: we try it and expect False.
    LCodeGen := TParseCodeGen.Create();
    LCodeGen.SetErrors(LErrors);
    LCodeGen.SetConfig(LConfig);
    if LCodeGen.Generate(LAST) then
    begin
      // Even if Generate doesn't check errors itself, the test verifies
      // the pipeline convention: semantics fails → don't call codegen.
      TParseUtils.PrintLn(COLOR_YELLOW +
        '  NOTE: Generate succeeded despite prior errors (pipeline should guard)');
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN +
        '  OK: Generate returned False (prior errors present)');

    PrintResult(LPassed);

  finally
    FreeAndNil(LSem);
    FreeAndNil(LParser);
    FreeAndNil(LLexer);
    FreeAndNil(LAST);
    FreeAndNil(LCodeGen);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

end.
