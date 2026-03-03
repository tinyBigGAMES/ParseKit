{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

(*
  ULang.Pascal — Pascal showcase language built on Parse()

  Proves Parse() can handle a real language with:
    - Global var blocks with type annotations
    - Procedures and functions with parameters
    - Pascal Result return convention
    - if/then/else, while/do, for/to/downto/do
    - writeln with multiple arguments
    - Symbol resolution and semantic error reporting
    - Full C++23 forward declarations to .h

  Target source: languages/src/HelloWorld.pas
  Expected output: HelloWorld.h + HelloWorld.cpp → native binary
*)

unit ULang.Pascal;

{$I Parse.Defines.inc}

interface

uses
  Parse;

procedure Demo(const APlatform: TParseTargetPlatform=tpWin64; const ALevel: TParseOptimizeLevel=olDebug);

implementation

uses
  System.SysUtils,
  System.Rtti;

// ---------------------------------------------------------------------------
// RunPascalDemo — wire up and run the full Pascal pipeline
// ---------------------------------------------------------------------------

procedure Demo(const APlatform: TParseTargetPlatform; const ALevel: TParseOptimizeLevel);
var
  LParse:        TParse;
  LExprOverride: TParseExprOverride;
begin
  LParse := TParse.Create();
  try

    //=========================================================================
    // LEXER
    //=========================================================================
    LParse.Config()
      .CaseSensitiveKeywords(False)
      // Keywords
      .AddKeyword('program',   'keyword.program')
      .AddKeyword('var',       'keyword.var')
      .AddKeyword('begin',     'keyword.begin')
      .AddKeyword('end',       'keyword.end')
      .AddKeyword('procedure', 'keyword.procedure')
      .AddKeyword('function',  'keyword.function')
      .AddKeyword('if',        'keyword.if')
      .AddKeyword('then',      'keyword.then')
      .AddKeyword('else',      'keyword.else')
      .AddKeyword('while',     'keyword.while')
      .AddKeyword('for',       'keyword.for')
      .AddKeyword('to',        'keyword.to')
      .AddKeyword('downto',    'keyword.downto')
      .AddKeyword('do',        'keyword.do')
      .AddKeyword('writeln',   'keyword.writeln')
      .AddKeyword('write',     'keyword.write')
      .AddKeyword('string',    'keyword.string')
      .AddKeyword('integer',   'keyword.integer')
      .AddKeyword('boolean',   'keyword.boolean')
      .AddKeyword('double',    'keyword.double')
      .AddKeyword('true',      'keyword.true')
      .AddKeyword('false',     'keyword.false')
      .AddKeyword('and',       'keyword.and')
      .AddKeyword('or',        'keyword.or')
      .AddKeyword('not',       'keyword.not')
      .AddKeyword('div',       'keyword.div')
      .AddKeyword('mod',       'keyword.mod')
      // Operators — longest-match automatic, declare multi-char first
      .AddOperator(':=', 'op.assign')
      .AddOperator('<>', 'op.neq')
      .AddOperator('<=', 'op.lte')
      .AddOperator('>=', 'op.gte')
      .AddOperator('=',  'op.eq')
      .AddOperator('<',  'op.lt')
      .AddOperator('>',  'op.gt')
      .AddOperator('+',  'op.plus')
      .AddOperator('-',  'op.minus')
      .AddOperator('*',  'op.multiply')
      .AddOperator('/',  'op.divide')
      .AddOperator(':',  'delimiter.colon')
      .AddOperator(';',  'delimiter.semicolon')
      .AddOperator('.',  'delimiter.dot')
      .AddOperator(',',  'delimiter.comma')
      .AddOperator('(',  'delimiter.lparen')
      .AddOperator(')',  'delimiter.rparen')
      // String style: single-quoted, no escape
      .AddStringStyle('''', '''', PARSE_KIND_STRING, False)
      // Comments
      .AddLineComment('//')
      .AddBlockComment('{', '}')
      // Structural
      .SetStatementTerminator('delimiter.semicolon')
      .SetBlockOpen('keyword.begin')
      .SetBlockClose('keyword.end')
      // Type keywords for TypeTextToKind()
      .AddTypeKeyword('string',  'type.string')
      .AddTypeKeyword('integer', 'type.integer')
      .AddTypeKeyword('boolean', 'type.boolean')
      .AddTypeKeyword('double',  'type.double')
      // Literal type inference
      .AddLiteralType('expr.integer', 'type.integer')
      .AddLiteralType('expr.real',    'type.double')
      .AddLiteralType('expr.string',  'type.string')
      .AddLiteralType('expr.bool',    'type.boolean');

    // expr.string override: Pascal single-quoted strings -> C++ double-quoted
    LExprOverride :=
      function(const ANode: TParseASTNodeBase;
        const ADefault: TParseExprToStringFunc): string
      var
        LInner: string;
        LText:  string;
      begin
        LText := ANode.GetToken().Text;
        if (Length(LText) >= 2) and (LText[1] = #39) and
           (LText[Length(LText)] = #39) then
          LInner := Copy(LText, 2, Length(LText) - 2)
        else
          LInner := LText;
        LInner := LInner.Replace(#39#39, #39);
        Result := '"' + LInner + '"';
      end;
    LParse.Config().RegisterExprOverride('expr.string', LExprOverride);

    //=========================================================================
    // GRAMMAR — PREFIX HANDLERS
    //=========================================================================

    // Literal prefixes: identifier, integer, real, string
    LParse.Config().RegisterLiteralPrefixes();

    // true
    LParse.Config().RegisterPrefix('keyword.true', 'expr.bool',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();
        Result := LNode;
      end);

    // false
    LParse.Config().RegisterPrefix('keyword.false', 'expr.bool',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();
        Result := LNode;
      end);

    // not (unary prefix)
    LParse.Config().RegisterPrefix('keyword.not', 'expr.unary',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('!'));
        AParser.Consume();  // consume 'not'
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(50)));
        Result := LNode;
      end);

    // Grouped expression: (expr)
    LParse.Config().RegisterPrefix('delimiter.lparen', 'expr.grouped',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        AParser.Consume();  // consume '('
        LNode := AParser.CreateNode('expr.grouped');
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        AParser.Expect('delimiter.rparen');
        Result := LNode;
      end);

    //=========================================================================
    // GRAMMAR — INFIX HANDLERS
    //=========================================================================

    // := assignment (right-assoc, power 2)
    LParse.Config().RegisterInfixRight('op.assign', 2, 'expr.assign',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>(':='));
        AParser.Consume();  // consume ':='
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPowerRight())));
        Result := LNode;
      end);

    // + (left-assoc, power 20)
    LParse.Config().RegisterInfixLeft('op.plus', 20, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('+'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    // - (left-assoc, power 20)
    LParse.Config().RegisterInfixLeft('op.minus', 20, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('-'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    // * (left-assoc, power 30)
    LParse.Config().RegisterInfixLeft('op.multiply', 30, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('*'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    // / (left-assoc, power 30)
    LParse.Config().RegisterInfixLeft('op.divide', 30, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('/'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    // div (left-assoc, power 30)
    LParse.Config().RegisterInfixLeft('keyword.div', 30, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('/'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    // mod (left-assoc, power 30)
    LParse.Config().RegisterInfixLeft('keyword.mod', 30, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('%'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    // = comparison (left-assoc, power 10)
    LParse.Config().RegisterInfixLeft('op.eq', 10, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('=='));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    // <> (left-assoc, power 10)
    LParse.Config().RegisterInfixLeft('op.neq', 10, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('!='));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    // < (left-assoc, power 10)
    LParse.Config().RegisterInfixLeft('op.lt', 10, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('<'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    // > (left-assoc, power 10)
    LParse.Config().RegisterInfixLeft('op.gt', 10, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('>'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    // <= (left-assoc, power 10)
    LParse.Config().RegisterInfixLeft('op.lte', 10, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('<='));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    // >= (left-assoc, power 10)
    LParse.Config().RegisterInfixLeft('op.gte', 10, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('>='));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    // and (left-assoc, power 8)
    LParse.Config().RegisterInfixLeft('keyword.and', 8, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('&&'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    // or (left-assoc, power 6)
    LParse.Config().RegisterInfixLeft('keyword.or', 6, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('||'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    // ( as infix — function/procedure call (left-assoc, power 40)
    LParse.Config().RegisterInfixLeft('delimiter.lparen', 40, 'expr.call',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode('expr.call', ALeft.GetToken());
        LNode.SetAttr('call.name', TValue.From<string>(ALeft.GetToken().Text));
        // ALeft is the callee ident node — name is now captured in the attribute.
        // It was never added to the tree as a child, so we own it here and must
        // free it to avoid an orphaned-node memory leak.
        ALeft.Free();
        AParser.Consume();  // consume '('
        if not AParser.Check('delimiter.rparen') then
        begin
          LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
          while AParser.Match('delimiter.comma') do
            LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        end;
        AParser.Expect('delimiter.rparen');
        Result := LNode;
      end);

    //=========================================================================
    // GRAMMAR — STATEMENT HANDLERS
    //=========================================================================

    // program header → stmt.pascal_program
    LParse.Config().RegisterStatement('keyword.program', 'stmt.pascal_program',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'program'
        LNode.SetAttr('decl.name', TValue.From<string>(AParser.CurrentToken().Text));
        AParser.Consume();  // consume program name identifier
        AParser.Expect('delimiter.semicolon');
        // Optional var block
        if AParser.Check('keyword.var') then
          LNode.AddChild(TParseASTNode(AParser.ParseStatement()));
        // Zero or more procedure/function declarations
        while AParser.Check('keyword.procedure') or AParser.Check('keyword.function') do
          LNode.AddChild(TParseASTNode(AParser.ParseStatement()));
        // Main begin..end. block
        LNode.AddChild(TParseASTNode(AParser.ParseStatement()));
        AParser.Expect('delimiter.dot');
        Result := LNode;
      end);

    // var block → stmt.var_block
    LParse.Config().RegisterStatement('keyword.var', 'stmt.var_block',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:     TParseASTNode;
        LVarNode:  TParseASTNode;
        LNameTok:  TParseToken;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'var'
        // Parse one or more identifier : type ; declarations
        while AParser.Check(PARSE_KIND_IDENTIFIER) do
        begin
          LNameTok := AParser.CurrentToken();
          AParser.Consume();  // consume identifier
          AParser.Expect('delimiter.colon');
          LVarNode := AParser.CreateNode('stmt.var_decl', LNameTok);
          LVarNode.SetAttr('var.type_text',
            TValue.From<string>(AParser.CurrentToken().Text));
          AParser.Consume();  // consume type keyword
          AParser.Expect('delimiter.semicolon');
          LNode.AddChild(LVarNode);
        end;
        Result := LNode;
      end);

    // procedure declaration → stmt.proc_decl
    LParse.Config().RegisterStatement('keyword.procedure', 'stmt.proc_decl',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:      TParseASTNode;
        LParamNode: TParseASTNode;
        LNameTok:   TParseToken;
        LParamTok:  TParseToken;
      begin
        AParser.Consume();  // consume 'procedure'
        LNameTok := AParser.CurrentToken();
        LNode := AParser.CreateNode('stmt.proc_decl', LNameTok);
        LNode.SetAttr('decl.name', TValue.From<string>(LNameTok.Text));
        AParser.Consume();  // consume name
        // Parameter list
        if AParser.Match('delimiter.lparen') then
        begin
          while not AParser.Check('delimiter.rparen') do
          begin
            LParamTok := AParser.CurrentToken();
            AParser.Consume();  // consume param name
            AParser.Expect('delimiter.colon');
            LParamNode := AParser.CreateNode('stmt.param_decl', LParamTok);
            LParamNode.SetAttr('param.type_text',
              TValue.From<string>(AParser.CurrentToken().Text));
            AParser.Consume();  // consume type keyword
            LNode.AddChild(LParamNode);
            if AParser.Check('delimiter.semicolon') then
              AParser.Consume()  // separator between params
            else
              Break;
          end;
          AParser.Expect('delimiter.rparen');
        end;
        AParser.Expect('delimiter.semicolon');
        // Body
        LNode.AddChild(TParseASTNode(AParser.ParseStatement()));
        AParser.Expect('delimiter.semicolon');  // ; after end
        Result := LNode;
      end);

    // function declaration → stmt.func_decl
    LParse.Config().RegisterStatement('keyword.function', 'stmt.func_decl',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:      TParseASTNode;
        LParamNode: TParseASTNode;
        LNameTok:   TParseToken;
        LParamTok:  TParseToken;
      begin
        AParser.Consume();  // consume 'function'
        LNameTok := AParser.CurrentToken();
        LNode := AParser.CreateNode('stmt.func_decl', LNameTok);
        LNode.SetAttr('decl.name', TValue.From<string>(LNameTok.Text));
        AParser.Consume();  // consume name
        // Parameter list
        if AParser.Match('delimiter.lparen') then
        begin
          while not AParser.Check('delimiter.rparen') do
          begin
            LParamTok := AParser.CurrentToken();
            AParser.Consume();  // consume param name
            AParser.Expect('delimiter.colon');
            LParamNode := AParser.CreateNode('stmt.param_decl', LParamTok);
            LParamNode.SetAttr('param.type_text',
              TValue.From<string>(AParser.CurrentToken().Text));
            AParser.Consume();  // consume type keyword
            LNode.AddChild(LParamNode);
            if AParser.Check('delimiter.semicolon') then
              AParser.Consume()  // separator between params
            else
              Break;
          end;
          AParser.Expect('delimiter.rparen');
        end;
        AParser.Expect('delimiter.colon');
        LNode.SetAttr('decl.return_type',
          TValue.From<string>(AParser.CurrentToken().Text));
        AParser.Consume();  // consume return type keyword
        AParser.Expect('delimiter.semicolon');
        // Body
        LNode.AddChild(TParseASTNode(AParser.ParseStatement()));
        AParser.Expect('delimiter.semicolon');  // ; after end
        Result := LNode;
      end);

    // begin..end block → stmt.begin_block
    LParse.Config().RegisterStatement('keyword.begin', 'stmt.begin_block',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:  TParseASTNode;
        LChild: TParseASTNodeBase;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'begin'
        while not AParser.Check('keyword.end') and
              not AParser.Check(PARSE_KIND_EOF) do
        begin
          LChild := AParser.ParseStatement();
          if LChild <> nil then
            LNode.AddChild(TParseASTNode(LChild));
        end;
        AParser.Expect('keyword.end');
        // Caller handles trailing ';' or '.'
        Result := LNode;
      end);

    // if/then/else → stmt.if
    LParse.Config().RegisterStatement('keyword.if', 'stmt.if',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'if'
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));  // condition
        AParser.Expect('keyword.then');
        LNode.AddChild(TParseASTNode(AParser.ParseStatement()));    // then body
        if AParser.Match('keyword.else') then
          LNode.AddChild(TParseASTNode(AParser.ParseStatement()));  // else body
        AParser.Match('delimiter.semicolon');  // optional — not present before else
        Result := LNode;
      end);

    // while/do → stmt.while
    LParse.Config().RegisterStatement('keyword.while', 'stmt.while',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'while'
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));  // condition
        AParser.Expect('keyword.do');
        LNode.AddChild(TParseASTNode(AParser.ParseStatement()));    // body
        AParser.Match('delimiter.semicolon');  // optional — begin..end body leaves ';' unconsumed
        Result := LNode;
      end);

    // for/to/downto/do → stmt.for
    LParse.Config().RegisterStatement('keyword.for', 'stmt.for',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'for'
        LNode.SetAttr('for.var',
          TValue.From<string>(AParser.CurrentToken().Text));
        AParser.Consume();  // consume loop variable identifier
        AParser.Expect('op.assign');
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));  // start
        if AParser.Check('keyword.to') then
        begin
          LNode.SetAttr('for.dir', TValue.From<string>('to'));
          AParser.Consume();
        end
        else
        begin
          AParser.Expect('keyword.downto');
          LNode.SetAttr('for.dir', TValue.From<string>('downto'));
        end;
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));  // end
        AParser.Expect('keyword.do');
        LNode.AddChild(TParseASTNode(AParser.ParseStatement()));    // body
        AParser.Match('delimiter.semicolon');  // optional — begin..end body leaves ';' unconsumed
        Result := LNode;
      end);

    // writeln(...) → stmt.writeln
    LParse.Config().RegisterStatement('keyword.writeln', 'stmt.writeln',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'writeln'
        AParser.Expect('delimiter.lparen');
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        while AParser.Match('delimiter.comma') do
          LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        AParser.Expect('delimiter.rparen');
        AParser.Match('delimiter.semicolon');  // optional consume
        Result := LNode;
      end);

    // write(...) → stmt.write
    LParse.Config().RegisterStatement('keyword.write', 'stmt.write',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'write'
        AParser.Expect('delimiter.lparen');
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        while AParser.Match('delimiter.comma') do
          LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        AParser.Expect('delimiter.rparen');
        AParser.Match('delimiter.semicolon');  // optional consume
        Result := LNode;
      end);

    //=========================================================================
    // SEMANTICS
    //=========================================================================

    // program.root — push global scope, visit children, pop
    LParse.Config().RegisterSemanticRule('program.root',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.PushScope('global', ANode.GetToken());
        ASem.VisitChildren(ANode);
        ASem.PopScope(ANode.GetToken());
      end);

    // stmt.pascal_program — visit children
    LParse.Config().RegisterSemanticRule('stmt.pascal_program',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // stmt.var_block — visit children
    LParse.Config().RegisterSemanticRule('stmt.var_block',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // stmt.var_decl — resolve type, set storage class, declare symbol
    LParse.Config().RegisterSemanticRule('stmt.var_decl',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LTypeAttr:  TValue;
        LTypeText:  string;
        LTypeKind:  string;
        LVarName:   string;
        LStorage:   string;
      begin
        ANode.GetAttr('var.type_text', LTypeAttr);
        LTypeText := LTypeAttr.AsString;
        LTypeKind := LParse.Config().TypeTextToKind(LTypeText);
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>(LTypeKind));
        // Determine storage: global if no proc/func scope owns this var
        if ASem.IsInsideRoutine() then
          LStorage := 'local'
        else
          LStorage := 'global';
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_STORAGE_CLASS,
          TValue.From<string>(LStorage));
        LVarName := ANode.GetToken().Text;
        if not ASem.DeclareSymbol(LVarName, ANode) then
          ASem.AddSemanticError(ANode, 'S100',
            'Duplicate declaration: ' + LVarName);
      end);

    // stmt.proc_decl — declare, push scope, visit params + body, pop
    LParse.Config().RegisterSemanticRule('stmt.proc_decl',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LAttr:    TValue;
        LName:    string;
        LI:       Integer;
        LChild:   TParseASTNodeBase;
      begin
        ANode.GetAttr('decl.name', LAttr);
        LName := LAttr.AsString;
        ASem.DeclareSymbol(LName, ANode);
        ASem.PushScope(LName, ANode.GetToken());
        // Sentinel so var_decl handlers know they are inside a routine
        // Visit param_decl children (all but last which is begin_block)
        for LI := 0 to ANode.ChildCount() - 2 do
        begin
          LChild := ANode.GetChild(LI);
          ASem.VisitNode(LChild);
        end;
        // Visit body (last child)
        if ANode.ChildCount() > 0 then
          ASem.VisitNode(ANode.GetChild(ANode.ChildCount() - 1));
        ASem.PopScope(ANode.GetToken());
      end);

    // stmt.func_decl — declare, push scope, declare Result, visit, pop
    LParse.Config().RegisterSemanticRule('stmt.func_decl',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LAttr:       TValue;
        LName:       string;
        LReturnText: string;
        LReturnKind: string;
        LI:          Integer;
      begin
        ANode.GetAttr('decl.name', LAttr);
        LName := LAttr.AsString;
        ASem.DeclareSymbol(LName, ANode);
        ASem.PushScope(LName, ANode.GetToken());
        // Sentinel so var_decl knows we're inside a routine
        // Visit param_decl children
        for LI := 0 to ANode.ChildCount() - 2 do
          ASem.VisitNode(ANode.GetChild(LI));
        // Declare implicit 'Result' in function scope. Point DeclNode at the
        // func_decl node itself (already carries decl.return_type) — avoids
        // creating a synthetic orphan node that is never parented to the AST
        // tree and therefore never freed, causing a memory leak.
        ANode.GetAttr('decl.return_type', LAttr);
        LReturnText := LAttr.AsString;
        LReturnKind := LParse.Config().TypeTextToKind(LReturnText);
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>(LReturnKind));
        ASem.DeclareSymbol('Result', ANode);
        // Visit body
        if ANode.ChildCount() > 0 then
          ASem.VisitNode(ANode.GetChild(ANode.ChildCount() - 1));
        ASem.PopScope(ANode.GetToken());
      end);

    // stmt.param_decl — map type, set storage, declare symbol
    LParse.Config().RegisterSemanticRule('stmt.param_decl',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LTypeAttr: TValue;
        LTypeText: string;
        LTypeKind: string;
        LParamName: string;
      begin
        ANode.GetAttr('param.type_text', LTypeAttr);
        LTypeText := LTypeAttr.AsString;
        LTypeKind := LParse.Config().TypeTextToKind(LTypeText);
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>(LTypeKind));
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_STORAGE_CLASS,
          TValue.From<string>('param'));
        LParamName := ANode.GetToken().Text;
        if not ASem.DeclareSymbol(LParamName, ANode) then
          ASem.AddSemanticError(ANode, 'S100',
            'Duplicate declaration: ' + LParamName);
      end);

    // stmt.begin_block — visit children
    LParse.Config().RegisterSemanticRule('stmt.begin_block',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // stmt.if — visit children
    LParse.Config().RegisterSemanticRule('stmt.if',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // stmt.while — visit children
    LParse.Config().RegisterSemanticRule('stmt.while',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // stmt.for — visit children
    LParse.Config().RegisterSemanticRule('stmt.for',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // stmt.writeln — visit children
    LParse.Config().RegisterSemanticRule('stmt.writeln',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // stmt.write — visit children
    LParse.Config().RegisterSemanticRule('stmt.write',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // expr.assign — visit children
    LParse.Config().RegisterSemanticRule('expr.assign',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // expr.binary — visit children
    LParse.Config().RegisterSemanticRule('expr.binary',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // expr.unary — visit children
    LParse.Config().RegisterSemanticRule('expr.unary',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // expr.grouped — visit children
    LParse.Config().RegisterSemanticRule('expr.grouped',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // expr.call — visit children
    LParse.Config().RegisterSemanticRule('expr.call',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // expr.ident — resolve symbol, copy type
    LParse.Config().RegisterSemanticRule('expr.ident',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LDeclNode:  TParseASTNodeBase;
        LTypeAttr:  TValue;
        LIdentName: string;
      begin
        LIdentName := ANode.GetToken().Text;
        if ASem.LookupSymbol(LIdentName, LDeclNode) then
        begin
          TParseASTNode(ANode).SetAttr(PARSE_ATTR_DECL_NODE,
            TValue.From<TObject>(LDeclNode));
          if LDeclNode.GetAttr(PARSE_ATTR_TYPE_KIND, LTypeAttr) then
            TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND, LTypeAttr);
        end
        else
          ASem.AddSemanticError(ANode, 'S200',
            'Undeclared identifier: ' + LIdentName);
      end);

    // expr.integer
    LParse.Config().RegisterSemanticRule('expr.integer',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.integer'));
      end);

    // expr.real
    LParse.Config().RegisterSemanticRule('expr.real',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.real'));
      end);

    // expr.string
    LParse.Config().RegisterSemanticRule('expr.string',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.string'));
      end);

    // expr.bool
    LParse.Config().RegisterSemanticRule('expr.bool',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.boolean'));
      end);

    //=========================================================================
    // EMITTERS
    //=========================================================================

    // program.root — write headers, wrap all content
    LParse.Config().RegisterEmitter('program.root',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        AGen.EmitLine('#pragma once', sfHeader);
        AGen.Include('cstdint',  sfHeader);
        AGen.Include('iostream', sfHeader);
        AGen.Include('string',   sfHeader);
        AGen.EmitChildren(ANode);
      end);

    // stmt.pascal_program — emit globals/procs/funcs, then wrap main()
    LParse.Config().RegisterEmitter('stmt.pascal_program',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LI: Integer;
      begin
        // Emit all children except the last (main begin_block)
        for LI := 0 to ANode.ChildCount() - 2 do
          AGen.EmitNode(ANode.GetChild(LI));
        // Wrap last child in main()
        AGen.Func('main', 'int');
        AGen.EmitNode(ANode.GetChild(ANode.ChildCount() - 1));
        AGen.Return(AGen.Lit(0));
        AGen.EndFunc();
      end);

    // stmt.var_block — delegate to each var_decl emitter
    LParse.Config().RegisterEmitter('stmt.var_block',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        AGen.EmitChildren(ANode);
      end);

    // stmt.var_decl — emit global or local variable
    LParse.Config().RegisterEmitter('stmt.var_decl',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LTypeAttr:    TValue;
        LStorageAttr: TValue;
        LTypeKind:    string;
        LStorage:     string;
        LCppType:     string;
        LVarName:     string;
      begin
        ANode.GetAttr(PARSE_ATTR_TYPE_KIND, LTypeAttr);
        ANode.GetAttr(PARSE_ATTR_STORAGE_CLASS, LStorageAttr);
        LTypeKind := LTypeAttr.AsString;
        LStorage  := LStorageAttr.AsString;
        LCppType  := LParse.Config().TypeToIR(LTypeKind);
        LVarName  := ANode.GetToken().Text;
        if LStorage = 'global' then
          AGen.Global(LVarName, LCppType, '')
        else
          AGen.DeclVar(LVarName, LCppType);
      end);

    // stmt.proc_decl — forward decl to header, then full definition to source
    LParse.Config().RegisterEmitter('stmt.proc_decl',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LAttr:      TValue;
        LName:      string;
        LParams:    string;
        LI:         Integer;
        LChild:     TParseASTNodeBase;
        LParamAttr: TValue;
        LParamType: string;
        LCppType:   string;
        LParamName: string;
      begin
        ANode.GetAttr('decl.name', LAttr);
        LName := LAttr.AsString;
        // Build param string for forward declaration
        LParams := '';
        for LI := 0 to ANode.ChildCount() - 2 do
        begin
          LChild := ANode.GetChild(LI);
          if LChild.GetNodeKind() <> 'stmt.param_decl' then
            Continue;
          LChild.GetAttr('param.type_text', LParamAttr);
          LParamType := LParamAttr.AsString;
          LCppType   := LParse.Config().TypeToIR(LParse.Config().TypeTextToKind(LParamType));
          LParamName := LChild.GetToken().Text;
          if LParams <> '' then
            LParams := LParams + ', ';
          LParams := LParams + LCppType + ' ' + LParamName;
        end;
        // Forward declaration to header
        AGen.EmitLine('void ' + LName + '(' + LParams + ');', sfHeader);
        // Full function definition to source
        AGen.Func(LName, 'void');
        for LI := 0 to ANode.ChildCount() - 2 do
        begin
          LChild := ANode.GetChild(LI);
          if LChild.GetNodeKind() <> 'stmt.param_decl' then
            Continue;
          LChild.GetAttr('param.type_text', LParamAttr);
          LParamType := LParamAttr.AsString;
          LCppType   := LParse.Config().TypeToIR(LParse.Config().TypeTextToKind(LParamType));
          LParamName := LChild.GetToken().Text;
          AGen.Param(LParamName, LCppType);
        end;
        // Body is last child
        AGen.EmitNode(ANode.GetChild(ANode.ChildCount() - 1));
        AGen.EndFunc();
      end);

    // stmt.func_decl — forward decl to header, then full definition to source
    LParse.Config().RegisterEmitter('stmt.func_decl',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LAttr:       TValue;
        LName:       string;
        LReturnText: string;
        LCppReturn:  string;
        LParams:     string;
        LI:          Integer;
        LChild:      TParseASTNodeBase;
        LParamAttr:  TValue;
        LParamType:  string;
        LCppType:    string;
        LParamName:  string;
      begin
        ANode.GetAttr('decl.name', LAttr);
        LName := LAttr.AsString;
        ANode.GetAttr('decl.return_type', LAttr);
        LReturnText := LAttr.AsString;
        LCppReturn  := LParse.Config().TypeToIR(LParse.Config().TypeTextToKind(LReturnText));
        // Build param string
        LParams := '';
        for LI := 0 to ANode.ChildCount() - 2 do
        begin
          LChild := ANode.GetChild(LI);
          if LChild.GetNodeKind() <> 'stmt.param_decl' then
            Continue;
          LChild.GetAttr('param.type_text', LParamAttr);
          LParamType := LParamAttr.AsString;
          LCppType   := LParse.Config().TypeToIR(LParse.Config().TypeTextToKind(LParamType));
          LParamName := LChild.GetToken().Text;
          if LParams <> '' then
            LParams := LParams + ', ';
          LParams := LParams + LCppType + ' ' + LParamName;
        end;
        // Forward declaration to header
        AGen.EmitLine(LCppReturn + ' ' + LName + '(' + LParams + ');', sfHeader);
        // Full definition to source
        AGen.Func(LName, LCppReturn);
        for LI := 0 to ANode.ChildCount() - 2 do
        begin
          LChild := ANode.GetChild(LI);
          if LChild.GetNodeKind() <> 'stmt.param_decl' then
            Continue;
          LChild.GetAttr('param.type_text', LParamAttr);
          LParamType := LParamAttr.AsString;
          LCppType   := LParse.Config().TypeToIR(LParse.Config().TypeTextToKind(LParamType));
          LParamName := LChild.GetToken().Text;
          AGen.Param(LParamName, LCppType);
        end;
        // Declare Result variable
        AGen.DeclVar('Result', LCppReturn, '{}');
        // Body
        AGen.EmitNode(ANode.GetChild(ANode.ChildCount() - 1));
        AGen.Return(AGen.Get('Result'));
        AGen.EndFunc();
      end);

    // stmt.param_decl — no-op, handled by proc/func emitters
    LParse.Config().RegisterEmitter('stmt.param_decl',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        // Intentionally empty — params emitted by proc/func emitters
      end);

    // stmt.begin_block — braces are the parent's responsibility
    LParse.Config().RegisterEmitter('stmt.begin_block',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        AGen.EmitChildren(ANode);
      end);

    // stmt.if — if/else chain
    LParse.Config().RegisterEmitter('stmt.if',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LCondStr: string;
      begin
        LCondStr := LParse.Config().ExprToString(ANode.GetChild(0));
        AGen.IfStmt(LCondStr);
        AGen.EmitNode(ANode.GetChild(1));
        if ANode.ChildCount() >= 3 then
        begin
          AGen.ElseStmt();
          AGen.EmitNode(ANode.GetChild(2));
        end;
        AGen.EndIf();
      end);

    // stmt.while
    LParse.Config().RegisterEmitter('stmt.while',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LCondStr: string;
      begin
        LCondStr := LParse.Config().ExprToString(ANode.GetChild(0));
        AGen.WhileStmt(LCondStr);
        AGen.EmitNode(ANode.GetChild(1));
        AGen.EndWhile();
      end);

    // stmt.for
    LParse.Config().RegisterEmitter('stmt.for',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LAttr:     TValue;
        LVarName:  string;
        LDir:      string;
        LStartStr: string;
        LEndStr:   string;
        LCond:     string;
        LStep:     string;
      begin
        ANode.GetAttr('for.var', LAttr);
        LVarName  := LAttr.AsString;
        ANode.GetAttr('for.dir', LAttr);
        LDir      := LAttr.AsString;
        LStartStr := LParse.Config().ExprToString(ANode.GetChild(0));
        LEndStr   := LParse.Config().ExprToString(ANode.GetChild(1));
        if LDir = 'to' then
        begin
          LCond := LVarName + ' <= ' + LEndStr;
          LStep := LVarName + '++';
        end
        else
        begin
          LCond := LVarName + ' >= ' + LEndStr;
          LStep := LVarName + '--';
        end;
        AGen.ForStmt(LVarName, LStartStr, LCond, LStep);
        AGen.EmitNode(ANode.GetChild(2));
        AGen.EndFor();
      end);

    // stmt.writeln — std::cout chain with trailing \n
    LParse.Config().RegisterEmitter('stmt.writeln',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LChain: string;
        LI:     Integer;
      begin
        LChain := 'std::cout';
        for LI := 0 to ANode.ChildCount() - 1 do
          LChain := LChain + ' << ' + LParse.Config().ExprToString(ANode.GetChild(LI));
        LChain := LChain + ' << "\n"';
        AGen.Stmt(LChain + ';');
      end);

    // stmt.write — std::cout chain without trailing \n
    LParse.Config().RegisterEmitter('stmt.write',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LChain: string;
        LI:     Integer;
      begin
        LChain := 'std::cout';
        for LI := 0 to ANode.ChildCount() - 1 do
          LChain := LChain + ' << ' + LParse.Config().ExprToString(ANode.GetChild(LI));
        AGen.Stmt(LChain + ';');
      end);

    // expr.assign used as a statement (inside begin_block)
    LParse.Config().RegisterEmitter('expr.assign',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        AGen.Assign(
          LParse.Config().ExprToString(ANode.GetChild(0)),
          LParse.Config().ExprToString(ANode.GetChild(1)));
      end);

    // expr.call used as a statement (procedure call in begin_block)
    LParse.Config().RegisterEmitter('expr.call',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LAttr:  TValue;
        LName:  string;
        LArgs:  TArray<string>;
        LI:     Integer;
      begin
        ANode.GetAttr('call.name', LAttr);
        LName := LAttr.AsString;
        SetLength(LArgs, ANode.ChildCount());
        for LI := 0 to ANode.ChildCount() - 1 do
          LArgs[LI] := LParse.Config().ExprToString(ANode.GetChild(LI));
        AGen.Call(LName, LArgs);
      end);

    //=========================================================================
    // CONFIGURE & RUN
    //=========================================================================

    LParse.SetSourceFile('..\languages\src\HelloWorld.pas');
    LParse.SetOutputPath('output');
    LParse.SetTargetPlatform(APlatform);
    LParse.SetBuildMode(bmExe);
    LParse.SetOptimizeLevel(ALevel);

    LParse.SetOutputCallback(
      procedure(const ALine: string; const AUserData: Pointer)
      begin
        TParseUtils.Print(ALine);
      end);

    LParse.SetStatusCallback(
      procedure(const AText: string; const AUserData: Pointer)
      begin
        TParseUtils.PrintLn(AText);
      end);

    if not LParse.Compile(True) then
    begin
      TParseUtils.PrintLn(COLOR_RED + 'Pascal compilation failed.');
      Exit;
    end;

    if LParse.GetLastExitCode() <> 0 then
      TParseUtils.PrintLn(COLOR_RED + 'Program exited with code: ' +
        IntToStr(LParse.GetLastExitCode()));

  finally
    LParse.Free();
  end;
end;

end.
