{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

unit UTest.Parser;

{$I Parse.Defines.inc}

interface

procedure Test01();
procedure Test02();
procedure Test03();
procedure Test04();

implementation

uses
  System.SysUtils,
  System.Rtti,
  Parse.Utils,
  Parse.Common,
  Parse.LangConfig,
  Parse.Lexer,
  Parse.Parser;

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

// Build a minimal config sufficient for expression parsing:
//   identifiers, integer literals, and the operators in AOps.
// Caller owns the returned config.
function BuildExprConfig(): TParseLangConfig;
begin
  Result := TParseLangConfig.Create();

  // Identifier prefix handler — produces 'expr.ident'
  Result.RegisterPrefix(PARSE_KIND_IDENTIFIER, 'expr.ident',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();
      Result := LNode;
    end);

  // Integer literal prefix handler — produces 'expr.integer'
  Result.RegisterPrefix(PARSE_KIND_INTEGER, 'expr.integer',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();
      Result := LNode;
    end);
end;

//=============================================================================
// Test01 — Basic expression parsing (integer literals and addition)
//
// Configures integer literal and identifier prefix handlers plus a left-
// associative '+' infix handler. Parses '1 + 2' and verifies the Pratt
// engine produces:
//   program.root
//     expr.binary  [op=+]
//       expr.integer  [text=1]
//       expr.integer  [text=2]
//=============================================================================
procedure Test01();
var
  LSource: string;
  LConfig: TParseLangConfig;
  LErrors: TParseErrors;
  LLexer:  TParseLexer;
  LParser: TParseParser;
  LRoot:   TParseASTNode;
  LPassed: Boolean;
  LStmt:   TParseASTNode;
  LLeft:   TParseASTNode;
  LRight:  TParseASTNode;
begin
  PrintHeader('Test01 — Basic expression parsing: integer literals and addition');

  LSource := '1 + 2';

  LConfig := nil;
  LErrors := TParseErrors.Create();
  LLexer  := nil;
  LParser := nil;
  LRoot   := nil;
  try
    LConfig := BuildExprConfig();

    // Left-associative '+' infix — produces 'expr.binary', attaches op attr
    LConfig.RegisterInfixLeft('op.plus', 10, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('+'));
        AParser.Consume();  // eat '+'
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(
          AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    LConfig.AddOperator('+', 'op.plus');

    LLexer := TParseLexer.Create();
    LLexer.SetErrors(LErrors);
    LLexer.SetConfig(LConfig);
    LLexer.LoadFromString(LSource, 'test01.txt');
    LLexer.Tokenize();

    LParser := TParseParser.Create();
    LParser.SetErrors(LErrors);
    LParser.SetConfig(LConfig);
    LParser.LoadFromLexer(LLexer);

    LRoot := LParser.ParseTokens();

    TParseUtils.PrintLn(LRoot.Dump());

    LPassed := True;

    if LErrors.HasErrors() then
    begin
      PrintErrors(LErrors);
      LPassed := False;
    end
    else
    begin
      // Root must have exactly one child — the binary expression
      if LRoot.ChildCount() <> 1 then
      begin
        TParseUtils.PrintLn(COLOR_RED +
          Format('  FAIL: expected 1 child on root, got %d', [LRoot.ChildCount()]));
        LPassed := False;
      end
      else
      begin
        LStmt := LRoot.GetChildNode(0);

        if LStmt.GetNodeKind() <> 'expr.binary' then
        begin
          TParseUtils.PrintLn(COLOR_RED +
            '  FAIL: expected expr.binary, got ' + LStmt.GetNodeKind());
          LPassed := False;
        end
        else
        begin
          // Binary node must have two children: left=expr.integer, right=expr.integer
          if LStmt.ChildCount() <> 2 then
          begin
            TParseUtils.PrintLn(COLOR_RED +
              Format('  FAIL: expr.binary expected 2 children, got %d',
                [LStmt.ChildCount()]));
            LPassed := False;
          end
          else
          begin
            LLeft  := LStmt.GetChildNode(0);
            LRight := LStmt.GetChildNode(1);

            if LLeft.GetNodeKind() <> 'expr.integer' then
            begin
              TParseUtils.PrintLn(COLOR_RED +
                '  FAIL: left child expected expr.integer, got ' +
                LLeft.GetNodeKind());
              LPassed := False;
            end;

            if LRight.GetNodeKind() <> 'expr.integer' then
            begin
              TParseUtils.PrintLn(COLOR_RED +
                '  FAIL: right child expected expr.integer, got ' +
                LRight.GetNodeKind());
              LPassed := False;
            end;

            if LLeft.GetToken().Text <> '1' then
            begin
              TParseUtils.PrintLn(COLOR_RED +
                '  FAIL: left operand expected "1", got "' +
                LLeft.GetToken().Text + '"');
              LPassed := False;
            end;

            if LRight.GetToken().Text <> '2' then
            begin
              TParseUtils.PrintLn(COLOR_RED +
                '  FAIL: right operand expected "2", got "' +
                LRight.GetToken().Text + '"');
              LPassed := False;
            end;
          end;
        end;
      end;
    end;

    PrintResult(LPassed);

  finally
    FreeAndNil(LRoot);
    FreeAndNil(LParser);
    FreeAndNil(LLexer);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

//=============================================================================
// Test02 — Statement dispatch
//
// Registers an 'if' statement handler. Parses 'if x begin y end' and verifies:
//   program.root
//     stmt.if
//       expr.ident  [text=x]   (condition)
//       block.then
//         expr.ident  [text=y] (body statement)
//=============================================================================
procedure Test02();
var
  LSource: string;
  LConfig: TParseLangConfig;
  LErrors: TParseErrors;
  LLexer:  TParseLexer;
  LParser: TParseParser;
  LRoot:   TParseASTNode;
  LPassed: Boolean;
  LIf:     TParseASTNode;
  LCond:   TParseASTNode;
  LThen:   TParseASTNode;
begin
  PrintHeader('Test02 — Statement dispatch: if statement handler');

  LSource := 'if x begin y end';

  LConfig := nil;
  LErrors := TParseErrors.Create();
  LLexer  := nil;
  LParser := nil;
  LRoot   := nil;
  try
    LConfig := BuildExprConfig();

    LConfig
      .AddKeyword('if',    'keyword.if')
      .AddKeyword('begin', 'keyword.begin')
      .AddKeyword('end',   'keyword.end')
      .SetBlockOpen('keyword.begin')
      .SetBlockClose('keyword.end');

    // 'if' statement handler — parses condition then body block
    LConfig.RegisterStatement('keyword.if', 'stmt.if',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:      TParseASTNode;
        LThenBlock: TParseASTNode;
        LStmt:      TParseASTNodeBase;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // eat 'if'

        // Parse condition expression
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));

        AParser.Expect('keyword.begin');

        // Parse body until 'end'
        LThenBlock := AParser.CreateNode('block.then');
        while not AParser.Check(AParser.GetBlockCloseKind()) and
              not AParser.Check(PARSE_KIND_EOF) do
        begin
          LStmt := AParser.ParseStatement();
          if LStmt <> nil then
            LThenBlock.AddChild(TParseASTNode(LStmt));
        end;
        LNode.AddChild(LThenBlock);

        AParser.Expect(AParser.GetBlockCloseKind());
        Result := LNode;
      end);

    LLexer := TParseLexer.Create();
    LLexer.SetErrors(LErrors);
    LLexer.SetConfig(LConfig);
    LLexer.LoadFromString(LSource, 'test02.txt');
    LLexer.Tokenize();

    LParser := TParseParser.Create();
    LParser.SetErrors(LErrors);
    LParser.SetConfig(LConfig);
    LParser.LoadFromLexer(LLexer);

    LRoot := LParser.ParseTokens();

    TParseUtils.PrintLn(LRoot.Dump());

    LPassed := True;

    if LErrors.HasErrors() then
    begin
      PrintErrors(LErrors);
      LPassed := False;
    end
    else
    begin
      if LRoot.ChildCount() <> 1 then
      begin
        TParseUtils.PrintLn(COLOR_RED +
          Format('  FAIL: expected 1 child on root, got %d', [LRoot.ChildCount()]));
        LPassed := False;
      end
      else
      begin
        LIf := LRoot.GetChildNode(0);

        if LIf.GetNodeKind() <> 'stmt.if' then
        begin
          TParseUtils.PrintLn(COLOR_RED +
            '  FAIL: expected stmt.if, got ' + LIf.GetNodeKind());
          LPassed := False;
        end
        else
        begin
          // stmt.if must have 2 children: condition + block.then
          if LIf.ChildCount() <> 2 then
          begin
            TParseUtils.PrintLn(COLOR_RED +
              Format('  FAIL: stmt.if expected 2 children, got %d',
                [LIf.ChildCount()]));
            LPassed := False;
          end
          else
          begin
            LCond := LIf.GetChildNode(0);
            LThen := LIf.GetChildNode(1);

            if LCond.GetNodeKind() <> 'expr.ident' then
            begin
              TParseUtils.PrintLn(COLOR_RED +
                '  FAIL: condition expected expr.ident, got ' +
                LCond.GetNodeKind());
              LPassed := False;
            end;

            if LCond.GetToken().Text <> 'x' then
            begin
              TParseUtils.PrintLn(COLOR_RED +
                '  FAIL: condition expected text "x", got "' +
                LCond.GetToken().Text + '"');
              LPassed := False;
            end;

            if LThen.GetNodeKind() <> 'block.then' then
            begin
              TParseUtils.PrintLn(COLOR_RED +
                '  FAIL: second child expected block.then, got ' +
                LThen.GetNodeKind());
              LPassed := False;
            end;

            if LThen.ChildCount() <> 1 then
            begin
              TParseUtils.PrintLn(COLOR_RED +
                Format('  FAIL: block.then expected 1 child, got %d',
                  [LThen.ChildCount()]));
              LPassed := False;
            end
            else if LThen.GetChildNode(0).GetToken().Text <> 'y' then
            begin
              TParseUtils.PrintLn(COLOR_RED +
                '  FAIL: body statement expected "y", got "' +
                LThen.GetChildNode(0).GetToken().Text + '"');
              LPassed := False;
            end;
          end;
        end;
      end;
    end;

    PrintResult(LPassed);

  finally
    FreeAndNil(LRoot);
    FreeAndNil(LParser);
    FreeAndNil(LLexer);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

//=============================================================================
// Test03 — Comments as first-class AST nodes
//
// Parses source with a line comment before a statement and a block comment
// after it. Verifies both comment nodes appear in document order in the
// tree alongside the real statement — no information is lost.
//
//   program.root
//     comment.line   [text=// hello]
//     expr.ident     [text=x]
//     comment.block  [text={ world }]
//=============================================================================
procedure Test03();
var
  LSource:       string;
  LConfig:       TParseLangConfig;
  LErrors:       TParseErrors;
  LLexer:        TParseLexer;
  LParser:       TParseParser;
  LRoot:         TParseASTNode;
  LPassed:       Boolean;
  LFoundLine:    Boolean;
  LFoundBlock:   Boolean;
  LFoundIdent:   Boolean;
  LLineIdx:      Integer;
  LIdentIdx:     Integer;
  LBlockIdx:     Integer;
  LI:            Integer;
  LChild:        TParseASTNode;
begin
  PrintHeader('Test03 — Comments as first-class AST nodes in document order');

  LSource :=
    '// hello' + #10 +
    'x' + #10 +
    '{ world }';

  LConfig := nil;
  LErrors := TParseErrors.Create();
  LLexer  := nil;
  LParser := nil;
  LRoot   := nil;
  try
    LConfig := BuildExprConfig();
    LConfig
      .AddLineComment('//')
      .AddBlockComment('{', '}');

    LLexer := TParseLexer.Create();
    LLexer.SetErrors(LErrors);
    LLexer.SetConfig(LConfig);
    LLexer.LoadFromString(LSource, 'test03.txt');
    LLexer.Tokenize();

    LParser := TParseParser.Create();
    LParser.SetErrors(LErrors);
    LParser.SetConfig(LConfig);
    LParser.LoadFromLexer(LLexer);

    LRoot := LParser.ParseTokens();

    TParseUtils.PrintLn(LRoot.Dump());

    LPassed     := True;
    LFoundLine  := False;
    LFoundBlock := False;
    LFoundIdent := False;
    LLineIdx    := -1;
    LIdentIdx   := -1;
    LBlockIdx   := -1;

    if LErrors.HasErrors() then
    begin
      PrintErrors(LErrors);
      LPassed := False;
    end
    else
    begin
      // Walk children and record what we find and at what index
      for LI := 0 to LRoot.ChildCount() - 1 do
      begin
        LChild := LRoot.GetChildNode(LI);

        if LChild.GetNodeKind() = PARSE_KIND_COMMENT_LINE then
        begin
          LFoundLine := True;
          LLineIdx   := LI;
        end;

        if LChild.GetNodeKind() = PARSE_KIND_COMMENT_BLOCK then
        begin
          LFoundBlock := True;
          LBlockIdx   := LI;
        end;

        if LChild.GetNodeKind() = 'expr.ident' then
        begin
          LFoundIdent := True;
          LIdentIdx   := LI;
        end;
      end;

      if not LFoundLine then
      begin
        TParseUtils.PrintLn(COLOR_RED + '  FAIL: line comment node not found in AST');
        LPassed := False;
      end;

      if not LFoundBlock then
      begin
        TParseUtils.PrintLn(COLOR_RED + '  FAIL: block comment node not found in AST');
        LPassed := False;
      end;

      if not LFoundIdent then
      begin
        TParseUtils.PrintLn(COLOR_RED + '  FAIL: identifier node not found in AST');
        LPassed := False;
      end;

      // Verify document order: line comment < identifier < block comment
      if LFoundLine and LFoundIdent and LFoundBlock then
      begin
        if not ((LLineIdx < LIdentIdx) and (LIdentIdx < LBlockIdx)) then
        begin
          TParseUtils.PrintLn(COLOR_RED +
            Format('  FAIL: document order wrong — line=%d ident=%d block=%d',
              [LLineIdx, LIdentIdx, LBlockIdx]));
          LPassed := False;
        end
        else
          TParseUtils.PrintLn(COLOR_GREEN +
            '  OK: comment nodes in correct document order');
      end;
    end;

    PrintResult(LPassed);

  finally
    FreeAndNil(LRoot);
    FreeAndNil(LParser);
    FreeAndNil(LLexer);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

//=============================================================================
// Test04 — Operator precedence and associativity
//
// Part A — Precedence: parses 'a + b * c'
//   '*' (power 20) must bind tighter than '+' (power 10), producing:
//     expr.binary [op=+]
//       expr.ident [a]
//       expr.binary [op=*]
//         expr.ident [b]
//         expr.ident [c]
//
// Part B — Right-associativity: parses 'a := b := c'
//   ':=' is right-associative (power 5), producing:
//     expr.binary [op=:=]
//       expr.ident [a]
//       expr.binary [op=:=]
//         expr.ident [b]
//         expr.ident [c]
//=============================================================================
procedure Test04();
var
  LSourceA:  string;
  LSourceB:  string;
  LConfig:   TParseLangConfig;
  LErrors:   TParseErrors;
  LLexer:    TParseLexer;
  LParser:   TParseParser;
  LRoot:     TParseASTNode;
  LPassed:   Boolean;
  LTop:      TParseASTNode;
  LRight:    TParseASTNode;
  LAttrVal:  TValue;
begin
  PrintHeader('Test04 — Operator precedence and right-associativity');

  LConfig := nil;
  LErrors := TParseErrors.Create();
  LLexer  := nil;
  LParser := nil;
  LRoot   := nil;

  try
    LConfig := BuildExprConfig();

    // Infix handler factory — reused for all binary operators
    LConfig
      .RegisterInfixLeft('op.plus', 10, 'expr.binary',
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
        end)
      .RegisterInfixLeft('op.star', 20, 'expr.binary',
        function(AParser: TParseParserBase;
          ALeft: TParseASTNodeBase): TParseASTNodeBase
        var
          LNode: TParseASTNode;
        begin
          LNode := AParser.CreateNode();
          LNode.SetAttr('op', TValue.From<string>('*'));
          AParser.Consume();
          LNode.AddChild(TParseASTNode(ALeft));
          LNode.AddChild(TParseASTNode(
            AParser.ParseExpression(AParser.CurrentInfixPower())));
          Result := LNode;
        end)
      .RegisterInfixRight('op.assign', 5, 'expr.binary',
        function(AParser: TParseParserBase;
          ALeft: TParseASTNodeBase): TParseASTNodeBase
        var
          LNode: TParseASTNode;
        begin
          LNode := AParser.CreateNode();
          LNode.SetAttr('op', TValue.From<string>(':='));
          AParser.Consume();
          LNode.AddChild(TParseASTNode(ALeft));
          // Right-associative: use CurrentInfixPowerRight() so equal-precedence
          // operators on the right side are consumed into this node
          LNode.AddChild(TParseASTNode(
            AParser.ParseExpression(AParser.CurrentInfixPowerRight())));
          Result := LNode;
        end);

    LConfig
      .AddOperator('+',  'op.plus')
      .AddOperator('*',  'op.star')
      .AddOperator(':=', 'op.assign');

    // --- Part A: precedence ---

    LSourceA := 'a + b * c';

    LLexer := TParseLexer.Create();
    LLexer.SetErrors(LErrors);
    LLexer.SetConfig(LConfig);
    LLexer.LoadFromString(LSourceA, 'test04a.txt');
    LLexer.Tokenize();

    LParser := TParseParser.Create();
    LParser.SetErrors(LErrors);
    LParser.SetConfig(LConfig);
    LParser.LoadFromLexer(LLexer);

    LRoot := LParser.ParseTokens();

    TParseUtils.PrintLn('  Part A: ' + LSourceA);
    TParseUtils.PrintLn(LRoot.Dump());

    LPassed := True;

    if LErrors.HasErrors() then
    begin
      PrintErrors(LErrors);
      LPassed := False;
    end
    else
    begin
      LTop := LRoot.GetChildNode(0);

      // Top node must be '+' with right child being '*'
      if (LTop = nil) or (LTop.GetNodeKind() <> 'expr.binary') then
      begin
        TParseUtils.PrintLn(COLOR_RED + '  FAIL: top node expected expr.binary');
        LPassed := False;
      end
      else
      begin
        LTop.GetAttr('op', LAttrVal);
        if LAttrVal.AsType<string>() <> '+' then
        begin
          TParseUtils.PrintLn(COLOR_RED +
            '  FAIL: top operator expected "+", got "' +
            LAttrVal.AsType<string>() + '"');
          LPassed := False;
        end;

        LRight := LTop.GetChildNode(1);
        if (LRight = nil) or (LRight.GetNodeKind() <> 'expr.binary') then
        begin
          TParseUtils.PrintLn(COLOR_RED +
            '  FAIL: right subtree expected expr.binary (the * node)');
          LPassed := False;
        end
        else
        begin
          LRight.GetAttr('op', LAttrVal);
          if LAttrVal.AsType<string>() <> '*' then
          begin
            TParseUtils.PrintLn(COLOR_RED +
              '  FAIL: right subtree operator expected "*", got "' +
              LAttrVal.AsType<string>() + '"');
            LPassed := False;
          end
          else
            TParseUtils.PrintLn(COLOR_GREEN +
              '  OK: precedence correct — * binds tighter than +');
        end;
      end;
    end;

    FreeAndNil(LRoot);
    FreeAndNil(LParser);
    FreeAndNil(LLexer);
    LErrors.Clear();

    // --- Part B: right-associativity ---

    LSourceB := 'a := b := c';

    LLexer := TParseLexer.Create();
    LLexer.SetErrors(LErrors);
    LLexer.SetConfig(LConfig);
    LLexer.LoadFromString(LSourceB, 'test04b.txt');
    LLexer.Tokenize();

    LParser := TParseParser.Create();
    LParser.SetErrors(LErrors);
    LParser.SetConfig(LConfig);
    LParser.LoadFromLexer(LLexer);

    LRoot := LParser.ParseTokens();

    TParseUtils.PrintLn('  Part B: ' + LSourceB);
    TParseUtils.PrintLn(LRoot.Dump());

    if LErrors.HasErrors() then
    begin
      PrintErrors(LErrors);
      LPassed := False;
    end
    else
    begin
      LTop := LRoot.GetChildNode(0);

      if (LTop = nil) or (LTop.GetNodeKind() <> 'expr.binary') then
      begin
        TParseUtils.PrintLn(COLOR_RED + '  FAIL: top node expected expr.binary');
        LPassed := False;
      end
      else
      begin
        // Right child of top ':=' must itself be a ':=' node (right-assoc)
        LRight := LTop.GetChildNode(1);
        if (LRight = nil) or (LRight.GetNodeKind() <> 'expr.binary') then
        begin
          TParseUtils.PrintLn(COLOR_RED +
            '  FAIL: right child expected expr.binary (nested :=)');
          LPassed := False;
        end
        else
        begin
          LRight.GetAttr('op', LAttrVal);
          if LAttrVal.AsType<string>() <> ':=' then
          begin
            TParseUtils.PrintLn(COLOR_RED +
              '  FAIL: nested operator expected ":=", got "' +
              LAttrVal.AsType<string>() + '"');
            LPassed := False;
          end
          else
            TParseUtils.PrintLn(COLOR_GREEN +
              '  OK: right-associativity correct — a := (b := c)');
        end;
      end;
    end;

    PrintResult(LPassed);

  finally
    FreeAndNil(LRoot);
    FreeAndNil(LParser);
    FreeAndNil(LLexer);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

end.
