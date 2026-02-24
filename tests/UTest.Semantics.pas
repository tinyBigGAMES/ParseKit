{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

unit UTest.Semantics;

{$I Parse.Defines.inc}

interface

procedure Test01();
procedure Test02();
procedure Test03();
procedure Test04();
procedure Test05();
procedure Test06();
procedure Test07();
procedure Test08();

implementation

uses
  System.SysUtils,
  System.Rtti,
  System.Generics.Collections,
  Parse.Utils,
  Parse.Common,
  Parse.LangConfig,
  Parse.Lexer,
  Parse.Parser,
  Parse.Semantics;

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

// Build a minimal config for expression parsing: identifiers, integer
// literals, and a left-associative '+' operator. No semantic handlers
// registered — tests that need them add them separately.
// Caller owns the returned config.
function BuildBaseConfig(): TParseLangConfig;
begin
  Result := TParseLangConfig.Create();

  Result.RegisterPrefix(PARSE_KIND_IDENTIFIER, 'expr.ident',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();
      Result := LNode;
    end);

  Result.RegisterPrefix(PARSE_KIND_INTEGER, 'expr.integer',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();
      Result := LNode;
    end);

  Result.RegisterInfixLeft('op.plus', 10, 'expr.binary',
    function(AParser: TParseParserBase;
      ALeft: TParseASTNodeBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      LNode.SetAttr('op', TValue.From<string>('+'));
      AParser.Consume();
      LNode.AddChild(TParseASTNode(ALeft));
      LNode.AddChild(TParseASTNode(
        AParser.ParseExpression(AParser.CurrentInfixPower())));
      Result := LNode;
    end);

  Result.AddOperator('+', 'op.plus');
end;

// Parse ASource using AConfig, returning the AST root.
// AErrors must be created by the caller. Caller owns the returned root.
function ParseSource(const ASource: string; const AFilename: string;
  const AConfig: TParseLangConfig; const AErrors: TParseErrors): TParseASTNode;
var
  LLexer:  TParseLexer;
  LParser: TParseParser;
begin
  LLexer  := nil;
  LParser := nil;
  try
    LLexer := TParseLexer.Create();
    LLexer.SetErrors(AErrors);
    LLexer.SetConfig(AConfig);
    LLexer.LoadFromString(ASource, AFilename);
    LLexer.Tokenize();

    LParser := TParseParser.Create();
    LParser.SetErrors(AErrors);
    LParser.SetConfig(AConfig);
    LParser.LoadFromLexer(LLexer);

    Result := LParser.ParseTokens();
  finally
    FreeAndNil(LParser);
    FreeAndNil(LLexer);
  end;
end;

//=============================================================================
// Test01 — Auto-walk: nodes with no registered handler are transparently
//          visited; FNodeIndex is populated for all nodes in the tree.
//
// Parses '1 + 2' (produces root → binary → integer, integer).
// Runs Analyze() with a config that has NO semantic handlers.
// Verifies: Analyze returns True (no errors) and FindNodeAt locates nodes.
//=============================================================================
procedure Test01();
var
  LConfig:     TParseLangConfig;
  LErrors:     TParseErrors;
  LRoot:       TParseASTNode;
  LSem:        TParseSemantics;
  LFound:      TParseASTNodeBase;
  LActualFile: string;
  LPassed:     Boolean;
begin
  PrintHeader('Test01 — Auto-walk: no handlers, all nodes indexed');

  LConfig := nil;
  LErrors := TParseErrors.Create();
  LRoot   := nil;
  LSem    := nil;
  try
    LConfig := BuildBaseConfig();

    LRoot := ParseSource('1 + 2', 'test01.txt', LConfig, LErrors);

    if LErrors.HasErrors() then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: parse errors before semantic pass');
      PrintErrors(LErrors);
      PrintResult(False);
      Exit;
    end;

    TParseUtils.PrintLn(LRoot.Dump());

    // The lexer resolves the filename to a full path — read it from the
    // parsed AST so FindNodeAt uses the exact same string the tokens carry.
    LActualFile := LRoot.GetToken().Filename;

    LSem := TParseSemantics.Create();
    LSem.SetErrors(LErrors);
    LSem.SetConfig(LConfig);

    LPassed := LSem.Analyze(LRoot);

    if not LPassed then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: Analyze reported errors unexpectedly');
      PrintErrors(LErrors);
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN + '  OK: Analyze returned True (no errors)');

    // FindNodeAt should locate the integer '1' node at line 1, col 1
    LFound := LSem.FindNodeAt(LActualFile, 1, 1);
    if LFound = nil then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: FindNodeAt(1,1) returned nil');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN +
        '  OK: FindNodeAt(1,1) returned node kind=' + LFound.GetNodeKind());

    // FindNodeAt for the integer '2' at line 1 col 5
    LFound := LSem.FindNodeAt(LActualFile, 1, 5);
    if LFound = nil then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: FindNodeAt(1,5) returned nil');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN +
        '  OK: FindNodeAt(1,5) returned node kind=' + LFound.GetNodeKind());

    PrintResult(LPassed);

  finally
    FreeAndNil(LSem);
    FreeAndNil(LRoot);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

//=============================================================================
// Test02 — Semantic handler writes PARSE_ATTR_TYPE_KIND onto nodes.
//
// Registers a handler for 'expr.integer' that writes 'type.int' onto the
// node, then calls VisitChildren. Parses '42', runs Analyze, reads the
// attribute back and verifies it matches.
//=============================================================================
procedure Test02();
var
  LConfig:  TParseLangConfig;
  LErrors:  TParseErrors;
  LRoot:    TParseASTNode;
  LSem:     TParseSemantics;
  LNode:    TParseASTNodeBase;
  LAttr:    TValue;
  LPassed:  Boolean;
begin
  PrintHeader('Test02 — Handler writes PARSE_ATTR_TYPE_KIND onto node');

  LConfig := nil;
  LErrors := TParseErrors.Create();
  LRoot   := nil;
  LSem    := nil;
  try
    LConfig := BuildBaseConfig();

    // Register semantic handler for integer literals — writes type attribute
    LConfig.RegisterSemanticRule('expr.integer',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LIntNode: TParseASTNode;
      begin
        LIntNode := TParseASTNode(ANode);
        LIntNode.SetAttr(PARSE_ATTR_TYPE_KIND, TValue.From<string>('type.int'));
        ASem.VisitChildren(ANode);
      end);

    LRoot := ParseSource('42', 'test02.txt', LConfig, LErrors);

    if LErrors.HasErrors() then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: parse errors before semantic pass');
      PrintErrors(LErrors);
      PrintResult(False);
      Exit;
    end;

    LSem := TParseSemantics.Create();
    LSem.SetErrors(LErrors);
    LSem.SetConfig(LConfig);
    LSem.Analyze(LRoot);

    // The root's child should be the 'expr.integer' node
    if LRoot.ChildCount() < 1 then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: root has no children');
      PrintResult(False);
      Exit;
    end;

    LNode := LRoot.GetChild(0);

    LPassed := True;

    if LNode.GetNodeKind() <> 'expr.integer' then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: expected expr.integer, got ' + LNode.GetNodeKind());
      LPassed := False;
    end
    else if not LNode.GetAttr(PARSE_ATTR_TYPE_KIND, LAttr) then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: PARSE_ATTR_TYPE_KIND not written onto node');
      LPassed := False;
    end
    else if LAttr.AsType<string>() <> 'type.int' then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: expected "type.int", got "' + LAttr.AsType<string>() + '"');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN +
        '  OK: PARSE_ATTR_TYPE_KIND = "' + LAttr.AsType<string>() + '"');

    PrintResult(LPassed);

  finally
    FreeAndNil(LSem);
    FreeAndNil(LRoot);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

//=============================================================================
// Test03 — DeclareSymbol and LookupSymbol: declare 'x', look it up,
//          verify the returned DeclNode matches the declaring AST node.
//
// Registers a handler for 'expr.ident' that declares the identifier text
// as a symbol and writes PARSE_ATTR_RESOLVED_SYMBOL. After Analyze, calls
// FindSymbol to confirm the symbol is in the global table.
//=============================================================================
procedure Test03();
var
  LConfig:   TParseLangConfig;
  LErrors:   TParseErrors;
  LRoot:     TParseASTNode;
  LSem:      TParseSemantics;
  LSymbol:   TParseSymbol;
  LIdentNode: TParseASTNodeBase;
  LAttr:     TValue;
  LPassed:   Boolean;
begin
  PrintHeader('Test03 — DeclareSymbol and LookupSymbol');

  LConfig := nil;
  LErrors := TParseErrors.Create();
  LRoot   := nil;
  LSem    := nil;
  try
    LConfig := BuildBaseConfig();

    // Handler for identifiers — declares the name and writes resolved symbol attr
    LConfig.RegisterSemanticRule('expr.ident',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LIdentText: string;
        LIntNode:   TParseASTNode;
      begin
        LIntNode   := TParseASTNode(ANode);
        LIdentText := ANode.GetToken().Text;

        // Declare in current scope (ignore duplicate — not testing that here)
        ASem.DeclareSymbol(LIdentText, ANode);

        // Write PARSE_ATTR_RESOLVED_SYMBOL onto the node
        LIntNode.SetAttr(PARSE_ATTR_RESOLVED_SYMBOL,
          TValue.From<string>(LIdentText));
      end);

    LRoot := ParseSource('myvar', 'test03.txt', LConfig, LErrors);

    if LErrors.HasErrors() then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: parse errors before semantic pass');
      PrintErrors(LErrors);
      PrintResult(False);
      Exit;
    end;

    LSem := TParseSemantics.Create();
    LSem.SetErrors(LErrors);
    LSem.SetConfig(LConfig);
    LSem.Analyze(LRoot);

    LPassed := True;

    // FindSymbol should find 'myvar' in the global scope
    if not LSem.FindSymbol('myvar', LSymbol) then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: FindSymbol("myvar") returned False');
      LPassed := False;
    end
    else
    begin
      TParseUtils.PrintLn(COLOR_GREEN +
        '  OK: FindSymbol found "' + LSymbol.SymbolName + '"');

      // DeclNode must point to the expr.ident node
      if (LSymbol.DeclNode = nil) or
         (LSymbol.DeclNode.GetNodeKind() <> 'expr.ident') then
      begin
        TParseUtils.PrintLn(COLOR_RED +
          '  FAIL: DeclNode kind expected "expr.ident", got "' +
          LSymbol.DeclNode.GetNodeKind() + '"');
        LPassed := False;
      end
      else
        TParseUtils.PrintLn(COLOR_GREEN +
          '  OK: DeclNode.NodeKind = "' + LSymbol.DeclNode.GetNodeKind() + '"');
    end;

    // Verify PARSE_ATTR_RESOLVED_SYMBOL was written onto the ident node
    LIdentNode := LRoot.GetChild(0);
    if (LIdentNode <> nil) and
       LIdentNode.GetAttr(PARSE_ATTR_RESOLVED_SYMBOL, LAttr) then
      TParseUtils.PrintLn(COLOR_GREEN +
        '  OK: PARSE_ATTR_RESOLVED_SYMBOL = "' + LAttr.AsType<string>() + '"')
    else
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: PARSE_ATTR_RESOLVED_SYMBOL not found on ident node');
      LPassed := False;
    end;

    PrintResult(LPassed);

  finally
    FreeAndNil(LSem);
    FreeAndNil(LRoot);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

//=============================================================================
// Test04 — Duplicate declaration: declaring the same name twice in the same
//          scope must return False and the handler reports an error.
//
// Registers a handler for 'expr.ident' that attempts to declare the token
// text as a symbol twice and calls AddSemanticError on the second attempt.
// Verifies Analyze returns False and the error list is non-empty.
//=============================================================================
procedure Test04();
var
  LConfig:  TParseLangConfig;
  LErrors:  TParseErrors;
  LRoot:    TParseASTNode;
  LSem:     TParseSemantics;
  LPassed:  Boolean;
begin
  PrintHeader('Test04 — Duplicate declaration reports error');

  LConfig := nil;
  LErrors := TParseErrors.Create();
  LRoot   := nil;
  LSem    := nil;
  try
    LConfig := BuildBaseConfig();

    // Handler that tries to declare the same name twice — second must fail
    LConfig.RegisterSemanticRule('expr.ident',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LName: string;
      begin
        LName := ANode.GetToken().Text;
        // First declare — should succeed
        ASem.DeclareSymbol(LName, ANode);
        // Second declare of same name — should fail; report error
        if not ASem.DeclareSymbol(LName, ANode) then
          ASem.AddSemanticError(ANode, 'S300',
            'Duplicate declaration: "' + LName + '"');
      end);

    LRoot := ParseSource('dup', 'test04.txt', LConfig, LErrors);

    if LErrors.HasErrors() then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: parse errors before semantic pass');
      PrintErrors(LErrors);
      PrintResult(False);
      Exit;
    end;

    LSem := TParseSemantics.Create();
    LSem.SetErrors(LErrors);
    LSem.SetConfig(LConfig);

    LPassed := True;

    // Analyze must return False because the handler reported an error
    if LSem.Analyze(LRoot) then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: Analyze returned True but should have returned False');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN +
        '  OK: Analyze returned False (error reported)');

    if not LErrors.HasErrors() then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: expected at least one error in error list');
      LPassed := False;
    end
    else
    begin
      TParseUtils.PrintLn(COLOR_GREEN +
        '  OK: error list non-empty (' +
        IntToStr(LErrors.Count()) + ' error(s))');
      PrintErrors(LErrors);
    end;

    PrintResult(LPassed);

  finally
    FreeAndNil(LSem);
    FreeAndNil(LRoot);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

//=============================================================================
// Test05 — Scope isolation: symbol declared inside a PushScope/PopScope
//          block must NOT be visible after PopScope.
//
// Handler for 'expr.ident' pushes a scope, declares the name, pops the
// scope. After Analyze, LookupSymbol at the engine level (global) must
// not find the name. Uses TParseSemantics directly (no parse pipeline)
// with a hand-built TParseASTNode to keep the test simple.
//=============================================================================
procedure Test05();
var
  LConfig:   TParseLangConfig;
  LErrors:   TParseErrors;
  LSem:      TParseSemantics;
  LRoot:     TParseASTNode;
  LChild:    TParseASTNode;
  LToken:    TParseToken;
  LDeclNode: TParseASTNodeBase;
  LPassed:   Boolean;
begin
  PrintHeader('Test05 — Scope isolation: symbol not visible after PopScope');

  LConfig := nil;
  LErrors := TParseErrors.Create();
  LSem    := nil;
  LRoot   := nil;
  try
    LConfig := BuildBaseConfig();

    // Handler pushes scope, declares name, pops scope
    LConfig.RegisterSemanticRule('expr.ident',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LOpenTok:  TParseToken;
        LCloseTok: TParseToken;
      begin
        LOpenTok  := ANode.GetToken();
        LCloseTok := ANode.GetToken();
        ASem.PushScope('inner', LOpenTok);
        ASem.DeclareSymbol(ANode.GetToken().Text, ANode);
        ASem.PopScope(LCloseTok);
      end);

    // Build a minimal hand-crafted AST: root → expr.ident('scoped_x')
    LToken.Kind     := PARSE_KIND_IDENTIFIER;
    LToken.Text     := 'scoped_x';
    LToken.Filename := 'test05.txt';
    LToken.Line     := 1;
    LToken.Column   := 1;

    LRoot  := TParseASTNode.CreateNode('program.root', LToken);
    LChild := TParseASTNode.CreateNode('expr.ident', LToken);
    LRoot.AddChild(LChild);

    LSem := TParseSemantics.Create();
    LSem.SetErrors(LErrors);
    LSem.SetConfig(LConfig);
    LSem.Analyze(LRoot);

    LPassed := True;

    // After Analyze, 'scoped_x' must NOT be visible via LookupSymbol
    // (it was declared inside a nested scope that was popped)
    if LSem.LookupSymbol('scoped_x', LDeclNode) then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: "scoped_x" visible in global scope after PopScope — scope leak');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN +
        '  OK: "scoped_x" not visible after PopScope — scope isolated correctly');

    PrintResult(LPassed);

  finally
    FreeAndNil(LSem);
    FreeAndNil(LRoot);   // owns LChild
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

//=============================================================================
// Test06 — PARSE_ATTR_DECL_NODE links use-site to declaration node.
//
// Parses 'x + x' — two uses of the same identifier. A handler for
// 'expr.ident' declares the name on first encounter, then on subsequent
// encounters looks it up and writes PARSE_ATTR_DECL_NODE pointing to the
// declaring node. Verifies both use-site nodes carry the same DeclNode.
//=============================================================================
procedure Test06();
var
  LConfig:   TParseLangConfig;
  LErrors:   TParseErrors;
  LRoot:     TParseASTNode;
  LSem:      TParseSemantics;
  LBinary:   TParseASTNode;
  LLeft:     TParseASTNode;
  LRight:    TParseASTNode;
  LAttrL:    TValue;
  LAttrR:    TValue;
  LPassed:   Boolean;
begin
  PrintHeader(
    'Test06 — PARSE_ATTR_DECL_NODE links use-site nodes to declaration');

  LConfig := nil;
  LErrors := TParseErrors.Create();
  LRoot   := nil;
  LSem    := nil;
  try
    LConfig := BuildBaseConfig();

    // Handler: first occurrence declares; subsequent occurrences look up
    // and write PARSE_ATTR_DECL_NODE pointing to the declaring node
    LConfig.RegisterSemanticRule('expr.ident',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LName:        string;
        LDeclNode:    TParseASTNodeBase;
        LIdentNode:   TParseASTNode;
      begin
        LIdentNode := TParseASTNode(ANode);
        LName      := ANode.GetToken().Text;

        if ASem.LookupSymbol(LName, LDeclNode) then
        begin
          // Use-site: write PARSE_ATTR_DECL_NODE pointing to declaring node
          LIdentNode.SetAttr(PARSE_ATTR_DECL_NODE,
            TValue.From<TObject>(LDeclNode));
        end
        else
        begin
          // First encounter — declare
          ASem.DeclareSymbol(LName, ANode);
          // Declaration site also carries PARSE_ATTR_DECL_NODE pointing to self
          LIdentNode.SetAttr(PARSE_ATTR_DECL_NODE,
            TValue.From<TObject>(ANode));
        end;
      end);

    LRoot := ParseSource('x + x', 'test06.txt', LConfig, LErrors);

    if LErrors.HasErrors() then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: parse errors before semantic pass');
      PrintErrors(LErrors);
      PrintResult(False);
      Exit;
    end;

    LSem := TParseSemantics.Create();
    LSem.SetErrors(LErrors);
    LSem.SetConfig(LConfig);
    LSem.Analyze(LRoot);

    LPassed := True;

    // root → binary → [ident(x), ident(x)]
    if LRoot.ChildCount() < 1 then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: root has no children');
      PrintResult(False);
      Exit;
    end;

    LBinary := LRoot.GetChildNode(0);
    if (LBinary = nil) or (LBinary.ChildCount() < 2) then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: binary node not found or missing children');
      PrintResult(False);
      Exit;
    end;

    LLeft  := LBinary.GetChildNode(0);
    LRight := LBinary.GetChildNode(1);

    if not LLeft.GetAttr(PARSE_ATTR_DECL_NODE, LAttrL) then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: PARSE_ATTR_DECL_NODE not on left ident node');
      LPassed := False;
    end;

    if not LRight.GetAttr(PARSE_ATTR_DECL_NODE, LAttrR) then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: PARSE_ATTR_DECL_NODE not on right ident node');
      LPassed := False;
    end;

    if LPassed then
    begin
      // Both use-sites must point to the same declaring node (left ident = decl)
      if LAttrL.AsType<TObject>() <> LAttrR.AsType<TObject>() then
      begin
        TParseUtils.PrintLn(COLOR_RED +
          '  FAIL: left and right PARSE_ATTR_DECL_NODE point to different nodes');
        LPassed := False;
      end
      else
        TParseUtils.PrintLn(COLOR_GREEN +
          '  OK: both use-sites share the same PARSE_ATTR_DECL_NODE pointer');
    end;

    PrintResult(LPassed);

  finally
    FreeAndNil(LSem);
    FreeAndNil(LRoot);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

//=============================================================================
// Test07 — GetSymbolsInScopeAt returns visible symbols at a position.
//
// Hand-builds an AST with two scope levels. Outer scope has 'a', inner
// scope has 'b'. A handler pushes/pops scopes with real token positions.
// After Analyze, GetSymbolsInScopeAt at the inner position must return
// both 'a' and 'b'. At the outer position only 'a' is returned.
//=============================================================================
procedure Test07();
var
  LConfig:    TParseLangConfig;
  LErrors:    TParseErrors;
  LSem:       TParseSemantics;
  LRoot:      TParseASTNode;
  LOuterDecl: TParseASTNode;
  LScope:     TParseASTNode;
  LInnerDecl: TParseASTNode;
  LTokenOuter: TParseToken;
  LTokenInner: TParseToken;
  LTokenClose: TParseToken;
  LSymbols:   TArray<TParseSymbol>;
  LFoundA:    Boolean;
  LFoundB:    Boolean;
  LI:         Integer;
  LPassed:    Boolean;
begin
  PrintHeader(
    'Test07 — GetSymbolsInScopeAt returns symbols from correct scope depth');

  LConfig := nil;
  LErrors := TParseErrors.Create();
  LSem    := nil;
  LRoot   := nil;
  try
    LConfig := BuildBaseConfig();

    // 'decl.outer' handler: declares the symbol in the current (outer) scope
    LConfig.RegisterSemanticRule('decl.outer',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.DeclareSymbol(ANode.GetToken().Text, ANode);
      end);

    // 'scope.block' handler: opens a new scope, visits children, closes it
    LConfig.RegisterSemanticRule('scope.block',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LOpenTok:  TParseToken;
        LCloseTok: TParseToken;
      begin
        LOpenTok  := ANode.GetToken();
        LCloseTok := ANode.GetToken();
        // Simulate close token at a later column to give the scope a real range
        LCloseTok.Column := LOpenTok.Column + 10;
        ASem.PushScope('inner', LOpenTok);
        ASem.VisitChildren(ANode);
        ASem.PopScope(LCloseTok);
      end);

    // 'decl.inner' handler: declares the symbol in the current (inner) scope
    LConfig.RegisterSemanticRule('decl.inner',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.DeclareSymbol(ANode.GetToken().Text, ANode);
      end);

    // Build AST:
    //   program.root (line 1)
    //     decl.outer 'a'  (line 1, col 1)
    //     scope.block     (line 2, col 1..11)
    //       decl.inner 'b' (line 2, col 3)

    LTokenOuter.Kind     := PARSE_KIND_IDENTIFIER;
    LTokenOuter.Text     := 'a';
    LTokenOuter.Filename := 'test07.txt';
    LTokenOuter.Line     := 1;
    LTokenOuter.Column   := 1;

    LTokenInner.Kind     := PARSE_KIND_IDENTIFIER;
    LTokenInner.Text     := 'b';
    LTokenInner.Filename := 'test07.txt';
    LTokenInner.Line     := 2;
    LTokenInner.Column   := 3;

    LTokenClose.Filename := 'test07.txt';
    LTokenClose.Line     := 2;
    LTokenClose.Column   := 11;

    LRoot      := TParseASTNode.CreateNode('program.root', LTokenOuter);
    LOuterDecl := TParseASTNode.CreateNode('decl.outer', LTokenOuter);
    LScope     := TParseASTNode.CreateNode('scope.block', LTokenInner);
    LInnerDecl := TParseASTNode.CreateNode('decl.inner', LTokenInner);

    LScope.AddChild(LInnerDecl);
    LRoot.AddChild(LOuterDecl);
    LRoot.AddChild(LScope);

    LSem := TParseSemantics.Create();
    LSem.SetErrors(LErrors);
    LSem.SetConfig(LConfig);
    LSem.Analyze(LRoot);

    LPassed := True;

    // At inner position (line 2, col 5) both 'a' and 'b' must be visible
    LSymbols := LSem.GetSymbolsInScopeAt('test07.txt', 2, 5);

    LFoundA := False;
    LFoundB := False;
    for LI := 0 to High(LSymbols) do
    begin
      if LSymbols[LI].SymbolName = 'a' then LFoundA := True;
      if LSymbols[LI].SymbolName = 'b' then LFoundB := True;
    end;

    if not LFoundA then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: "a" not visible at inner scope position');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN + '  OK: "a" visible at inner position');

    if not LFoundB then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: "b" not visible at inner scope position');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN + '  OK: "b" visible at inner position');

    // At outer position (line 1, col 1) only 'a' should be visible
    LSymbols := LSem.GetSymbolsInScopeAt('test07.txt', 1, 1);

    LFoundA := False;
    LFoundB := False;
    for LI := 0 to High(LSymbols) do
    begin
      if LSymbols[LI].SymbolName = 'a' then LFoundA := True;
      if LSymbols[LI].SymbolName = 'b' then LFoundB := True;
    end;

    if not LFoundA then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: "a" not visible at outer scope position');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN + '  OK: "a" visible at outer position');

    if LFoundB then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: "b" visible at outer scope position — scope leak');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN +
        '  OK: "b" not visible at outer position — scope boundary correct');

    PrintResult(LPassed);

  finally
    FreeAndNil(LSem);
    FreeAndNil(LRoot);   // owns LOuterDecl, LScope (which owns LInnerDecl)
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

//=============================================================================
// Test08 — RegisterTypeCompat drives PARSE_ATTR_COERCE_TO on nodes.
//
// Registers a type compat function: int → float requires coercion to
// 'type.float'. Registers a semantic handler for 'expr.integer' that
// writes 'type.int', and for 'expr.binary' that calls GetTypeCompatFunc
// to check left vs right types and writes PARSE_ATTR_COERCE_TO onto the
// left child if needed. Parses '1 + 2', runs Analyze, verifies the
// coerce attribute is written.
//=============================================================================
procedure Test08();
var
  LConfig:  TParseLangConfig;
  LErrors:  TParseErrors;
  LRoot:    TParseASTNode;
  LSem:     TParseSemantics;
  LBinary:  TParseASTNode;
  LLeft:    TParseASTNode;
  LAttr:    TValue;
  LPassed:  Boolean;
begin
  PrintHeader(
    'Test08 — RegisterTypeCompat drives PARSE_ATTR_COERCE_TO on node');

  LConfig := nil;
  LErrors := TParseErrors.Create();
  LRoot   := nil;
  LSem    := nil;
  try
    LConfig := BuildBaseConfig();

    // Language-specific type compatibility: int → float requires a coercion
    LConfig.RegisterTypeCompat(
      function(const AFromType, AToType: string;
        out ACoerceTo: string): Boolean
      begin
        ACoerceTo := '';
        // int is compatible with float but needs a coercion cast
        if (AFromType = 'type.int') and (AToType = 'type.float') then
        begin
          ACoerceTo := 'type.float';
          Result    := True;
          Exit;
        end;
        // Same type: compatible, no coercion
        Result := AFromType = AToType;
      end);

    // Handler for integer literals — tags them as 'type.int'
    LConfig.RegisterSemanticRule('expr.integer',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.int'));
      end);

    // Handler for binary expressions — visits children first (so integer
    // handlers run and write PARSE_ATTR_TYPE_KIND), then calls the language's
    // type compat function (captured from LConfig via closure) to check
    // whether the left operand needs a coercion to 'type.float'.
    LConfig.RegisterSemanticRule('expr.binary',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LBinNode:     TParseASTNode;
        LLeftNode:    TParseASTNode;
        LCompatFunc:  TParseTypeCompatFunc;
        LCoerceTo:    string;
        LLeftType:    TValue;
        LLeftTypeStr: string;
      begin
        LBinNode := TParseASTNode(ANode);

        // Visit children first so their handlers write type attributes
        ASem.VisitChildren(ANode);

        // Retrieve the language's registered type compat function via the
        // captured LConfig reference. This is the idiomatic pattern: handlers
        // close over the config to access language-specific callbacks.
        LCompatFunc := LConfig.GetTypeCompatFunc();
        if not Assigned(LCompatFunc) then
          Exit;

        if LBinNode.ChildCount() < 1 then
          Exit;

        LLeftNode := LBinNode.GetChildNode(0);
        if not LLeftNode.GetAttr(PARSE_ATTR_TYPE_KIND, LLeftType) then
          Exit;

        LLeftTypeStr := LLeftType.AsType<string>();

        // For this test, simulate that the target type is 'type.float'
        // (as it would be if the right operand were a float literal).
        // Call compat func: if int → float needs coercion, write the attr.
        LCoerceTo := '';
        if LCompatFunc(LLeftTypeStr, 'type.float', LCoerceTo) and
           (LCoerceTo <> '') then
          LLeftNode.SetAttr(PARSE_ATTR_COERCE_TO,
            TValue.From<string>(LCoerceTo));
      end);

    LRoot := ParseSource('1 + 2', 'test08.txt', LConfig, LErrors);

    if LErrors.HasErrors() then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: parse errors before semantic pass');
      PrintErrors(LErrors);
      PrintResult(False);
      Exit;
    end;

    LSem := TParseSemantics.Create();
    LSem.SetErrors(LErrors);
    LSem.SetConfig(LConfig);
    LSem.Analyze(LRoot);

    LPassed := True;

    if LRoot.ChildCount() < 1 then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: root has no children');
      PrintResult(False);
      Exit;
    end;

    LBinary := LRoot.GetChildNode(0);
    if (LBinary = nil) or (LBinary.ChildCount() < 1) then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: binary node not found');
      PrintResult(False);
      Exit;
    end;

    LLeft := LBinary.GetChildNode(0);

    // PARSE_ATTR_COERCE_TO must be written onto the left integer child
    if not LLeft.GetAttr(PARSE_ATTR_COERCE_TO, LAttr) then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: PARSE_ATTR_COERCE_TO not written onto left integer node');
      LPassed := False;
    end
    else if LAttr.AsType<string>() <> 'type.float' then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        '  FAIL: expected coerce target "type.float", got "' +
        LAttr.AsType<string>() + '"');
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN +
        '  OK: PARSE_ATTR_COERCE_TO = "' + LAttr.AsType<string>() +
        '" written onto integer node');

    PrintResult(LPassed);

  finally
    FreeAndNil(LSem);
    FreeAndNil(LRoot);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

end.
