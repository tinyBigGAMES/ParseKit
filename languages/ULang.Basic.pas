{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

(*
  ULang.Basic — Basic showcase language built on Parse()

  Proves Parse() can handle a language with:
    - Implicit program body (no header keyword)
    - Dim/As variable declarations with global/local storage
    - Sub/End Sub procedures with parameters
    - Function/End Function with function-name return convention
    - = dual role: assignment at statement level, equality in expressions
    - & string concatenation (maps to << for C++ stream chaining)
    - If/Then/Else/End If structured blocks
    - For i = start To end / Next i loops
    - While condition / Wend loops
    - Print variadic statement (std::cout chain)
    - Symbol resolution and semantic error reporting
    - Full C++23 forward declarations to .h

  Target source: languages/src/HelloWorld.bas
  Expected output: HelloWorld.h + HelloWorld.cpp -> native binary
*)

unit ULang.Basic;

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
// Demo — wire up and run the full Basic pipeline
// ---------------------------------------------------------------------------

procedure Demo(const APlatform: TParseTargetPlatform; const ALevel: TParseOptimizeLevel);
var
  LParse:    TParse;
begin
  LParse := TParse.Create();
  try

    //=========================================================================
    // LEXER
    //=========================================================================
    LParse.Config()
      .CaseSensitiveKeywords(False)
      // Keywords
      .AddKeyword('Dim',      'keyword.dim')
      .AddKeyword('As',       'keyword.as')
      .AddKeyword('Sub',      'keyword.sub')
      .AddKeyword('End',      'keyword.end')
      .AddKeyword('Function', 'keyword.function')
      .AddKeyword('If',       'keyword.if')
      .AddKeyword('Then',     'keyword.then')
      .AddKeyword('Else',     'keyword.else')
      .AddKeyword('ElseIf',   'keyword.elseif')
      .AddKeyword('For',      'keyword.for')
      .AddKeyword('To',       'keyword.to')
      .AddKeyword('Next',     'keyword.next')
      .AddKeyword('While',    'keyword.while')
      .AddKeyword('Wend',     'keyword.wend')
      .AddKeyword('Print',    'keyword.print')
      .AddKeyword('Return',   'keyword.return')
      .AddKeyword('String',   'keyword.string')
      .AddKeyword('Integer',  'keyword.integer')
      .AddKeyword('Boolean',  'keyword.boolean')
      .AddKeyword('Double',   'keyword.double')
      .AddKeyword('True',     'keyword.true')
      .AddKeyword('False',    'keyword.false')
      .AddKeyword('And',      'keyword.and')
      .AddKeyword('Or',       'keyword.or')
      .AddKeyword('Not',      'keyword.not')
      .AddKeyword('Mod',      'keyword.mod')
      // Operators — longest-match automatic, multi-char operators declared first
      .AddOperator('<>', 'op.neq')
      .AddOperator('<=', 'op.lte')
      .AddOperator('>=', 'op.gte')
      .AddOperator('=',  'op.eq_or_assign')
      .AddOperator('<',  'op.lt')
      .AddOperator('>',  'op.gt')
      .AddOperator('+',  'op.plus')
      .AddOperator('-',  'op.minus')
      .AddOperator('*',  'op.multiply')
      .AddOperator('/',  'op.divide')
      .AddOperator('\',  'op.intdivide')
      .AddOperator('&',  'op.concat')
      .AddOperator('(',  'delimiter.lparen')
      .AddOperator(')',  'delimiter.rparen')
      .AddOperator(',',  'delimiter.comma')
      // String style: double-quoted, allow escape sequences
      .AddStringStyle('"', '"', PARSE_KIND_STRING, True)
      // Line comment: single quote
      .AddLineComment('''')
      // Basic is newline-delimited — no explicit statement terminator token
      .SetStatementTerminator('')
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

    //=========================================================================
    // GRAMMAR — PREFIX HANDLERS
    //=========================================================================

    // Literal prefixes: identifier, integer, real, string
    LParse.Config().RegisterLiteralPrefixes();

    // True
    LParse.Config().RegisterPrefix('keyword.true', 'expr.bool',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();
        Result := LNode;
      end);

    // False
    LParse.Config().RegisterPrefix('keyword.false', 'expr.bool',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();
        Result := LNode;
      end);

    // Not (unary prefix — power 50 ensures tight binding)
    LParse.Config().RegisterPrefix('keyword.not', 'expr.unary',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('!'));
        AParser.Consume();  // consume 'Not'
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

    // = in expression context — equality comparison (left-assoc, power 10)
    // At statement level the identifier handler consumes = directly as assignment,
    // so this handler only fires inside expression contexts (If, While, etc.)
    LParse.Config().RegisterInfixLeft('op.eq_or_assign', 10, 'expr.binary',
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
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
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
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
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
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
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
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
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
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
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
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

    // + addition (left-assoc, power 20)
    LParse.Config().RegisterInfixLeft('op.plus', 20, 'expr.binary',
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
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

    // - subtraction (left-assoc, power 20)
    LParse.Config().RegisterInfixLeft('op.minus', 20, 'expr.binary',
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
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

    // & string concatenation (left-assoc, power 20)
    // op.concat (&) maps to << so ExprToString produces C++ stream-chain expressions
    // that thread directly into std::cout: "text" << var << "more"
    LParse.Config().RegisterInfixLeft('op.concat', 20, 'expr.binary',
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('<<'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
        Result := LNode;
      end);

    // * multiplication (left-assoc, power 30)
    LParse.Config().RegisterInfixLeft('op.multiply', 30, 'expr.binary',
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
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

    // / division (left-assoc, power 30)
    LParse.Config().RegisterInfixLeft('op.divide', 30, 'expr.binary',
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
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

    // \ integer division — maps to / in C++ (left-assoc, power 30)
    LParse.Config().RegisterInfixLeft('op.intdivide', 30, 'expr.binary',
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
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

    // Mod (left-assoc, power 30)
    LParse.Config().RegisterInfixLeft('keyword.mod', 30, 'expr.binary',
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
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

    // And (left-assoc, power 8)
    LParse.Config().RegisterInfixLeft('keyword.and', 8, 'expr.binary',
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
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

    // Or (left-assoc, power 6)
    LParse.Config().RegisterInfixLeft('keyword.or', 6, 'expr.binary',
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
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

    // ( as infix — function call expression (left-assoc, power 40)
    LParse.Config().RegisterInfixLeft('delimiter.lparen', 40, 'expr.call',
      function(AParser: TParseParserBase; ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode('expr.call', ALeft.GetToken());
        LNode.SetAttr('call.name', TValue.From<string>(ALeft.GetToken().Text));
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

    // Dim name As Type -> stmt.dim_decl
    LParse.Config().RegisterStatement('keyword.dim', 'stmt.dim_decl',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:    TParseASTNode;
        LNameTok: TParseToken;
      begin
        AParser.Consume();  // consume 'Dim'
        LNameTok := AParser.CurrentToken();
        AParser.Consume();  // consume identifier
        AParser.Expect('keyword.as');
        LNode := AParser.CreateNode('stmt.dim_decl', LNameTok);
        LNode.SetAttr('var.type_text',
          TValue.From<string>(AParser.CurrentToken().Text));
        AParser.Consume();  // consume type keyword
        Result := LNode;
      end);

    // Sub name([params]) body End Sub -> stmt.sub_decl
    LParse.Config().RegisterStatement('keyword.sub', 'stmt.sub_decl',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:      TParseASTNode;
        LBodyNode:  TParseASTNode;
        LNameTok:   TParseToken;
        LParamNode: TParseASTNode;
        LParamTok:  TParseToken;
        LChild:     TParseASTNodeBase;
      begin
        AParser.Consume();  // consume 'Sub'
        LNameTok := AParser.CurrentToken();
        LNode := AParser.CreateNode('stmt.sub_decl', LNameTok);
        LNode.SetAttr('decl.name', TValue.From<string>(LNameTok.Text));
        AParser.Consume();  // consume name
        // Optional parameter list: (param As Type [, ...])
        if AParser.Match('delimiter.lparen') then
        begin
          while not AParser.Check('delimiter.rparen') and
                not AParser.Check(PARSE_KIND_EOF) do
          begin
            LParamTok := AParser.CurrentToken();
            AParser.Consume();  // consume param name
            AParser.Expect('keyword.as');
            LParamNode := AParser.CreateNode('stmt.param_decl', LParamTok);
            LParamNode.SetAttr('param.type_text',
              TValue.From<string>(AParser.CurrentToken().Text));
            AParser.Consume();  // consume type keyword
            LNode.AddChild(LParamNode);
            if AParser.Check('delimiter.comma') then
              AParser.Consume()  // separator between params
            else
              Break;
          end;
          AParser.Expect('delimiter.rparen');
        end;
        // Parse body into stmt.sub_body until 'End'
        LBodyNode := AParser.CreateNode('stmt.sub_body', LNameTok);
        while not AParser.Check('keyword.end') and
              not AParser.Check(PARSE_KIND_EOF) do
        begin
          LChild := AParser.ParseStatement();
          if LChild <> nil then
            LBodyNode.AddChild(TParseASTNode(LChild));
        end;
        AParser.Expect('keyword.end');
        AParser.Expect('keyword.sub');
        LNode.AddChild(LBodyNode);
        Result := LNode;
      end);

    // Function name([params]) As Type body End Function -> stmt.func_decl
    LParse.Config().RegisterStatement('keyword.function', 'stmt.func_decl',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:      TParseASTNode;
        LBodyNode:  TParseASTNode;
        LNameTok:   TParseToken;
        LParamNode: TParseASTNode;
        LParamTok:  TParseToken;
        LChild:     TParseASTNodeBase;
      begin
        AParser.Consume();  // consume 'Function'
        LNameTok := AParser.CurrentToken();
        LNode := AParser.CreateNode('stmt.func_decl', LNameTok);
        LNode.SetAttr('decl.name', TValue.From<string>(LNameTok.Text));
        AParser.Consume();  // consume name
        // Optional parameter list: (param As Type [, ...])
        if AParser.Match('delimiter.lparen') then
        begin
          while not AParser.Check('delimiter.rparen') and
                not AParser.Check(PARSE_KIND_EOF) do
          begin
            LParamTok := AParser.CurrentToken();
            AParser.Consume();  // consume param name
            AParser.Expect('keyword.as');
            LParamNode := AParser.CreateNode('stmt.param_decl', LParamTok);
            LParamNode.SetAttr('param.type_text',
              TValue.From<string>(AParser.CurrentToken().Text));
            AParser.Consume();  // consume type keyword
            LNode.AddChild(LParamNode);
            if AParser.Check('delimiter.comma') then
              AParser.Consume()  // separator between params
            else
              Break;
          end;
          AParser.Expect('delimiter.rparen');
        end;
        // Return type: As Type
        AParser.Expect('keyword.as');
        LNode.SetAttr('decl.return_type',
          TValue.From<string>(AParser.CurrentToken().Text));
        AParser.Consume();  // consume return type keyword
        // Parse body into stmt.sub_body until 'End'
        LBodyNode := AParser.CreateNode('stmt.sub_body', LNameTok);
        while not AParser.Check('keyword.end') and
              not AParser.Check(PARSE_KIND_EOF) do
        begin
          LChild := AParser.ParseStatement();
          if LChild <> nil then
            LBodyNode.AddChild(TParseASTNode(LChild));
        end;
        AParser.Expect('keyword.end');
        AParser.Expect('keyword.function');
        LNode.AddChild(LBodyNode);
        Result := LNode;
      end);

    // If condition Then / [Else] / End If -> stmt.if
    // child[0] = condition expr
    // child[1] = stmt.sub_body (then-body)
    // child[2] = stmt.sub_body (else-body, optional)
    LParse.Config().RegisterStatement('keyword.if', 'stmt.if',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:     TParseASTNode;
        LBodyNode: TParseASTNode;
        LChild:    TParseASTNodeBase;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'If'
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));  // condition
        AParser.Expect('keyword.then');
        // Parse then-body until Else, ElseIf, or End
        LBodyNode := AParser.CreateNode('stmt.sub_body');
        while not AParser.Check('keyword.else') and
              not AParser.Check('keyword.elseif') and
              not AParser.Check('keyword.end') and
              not AParser.Check(PARSE_KIND_EOF) do
        begin
          LChild := AParser.ParseStatement();
          if LChild <> nil then
            LBodyNode.AddChild(TParseASTNode(LChild));
        end;
        LNode.AddChild(LBodyNode);
        // Optional else-body
        if AParser.Match('keyword.else') then
        begin
          LBodyNode := AParser.CreateNode('stmt.sub_body');
          while not AParser.Check('keyword.end') and
                not AParser.Check(PARSE_KIND_EOF) do
          begin
            LChild := AParser.ParseStatement();
            if LChild <> nil then
              LBodyNode.AddChild(TParseASTNode(LChild));
          end;
          LNode.AddChild(LBodyNode);
        end;
        AParser.Expect('keyword.end');
        AParser.Expect('keyword.if');
        Result := LNode;
      end);

    // For var = start To end body Next [var] -> stmt.for
    // child[0] = start expr, child[1] = end expr, child[2] = stmt.sub_body
    LParse.Config().RegisterStatement('keyword.for', 'stmt.for',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:     TParseASTNode;
        LBodyNode: TParseASTNode;
        LChild:    TParseASTNodeBase;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'For'
        LNode.SetAttr('for.var',
          TValue.From<string>(AParser.CurrentToken().Text));
        AParser.Consume();              // consume loop variable identifier
        AParser.Expect('op.eq_or_assign');  // the '=' in 'For i = 1 To count'
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));  // start
        AParser.Expect('keyword.to');
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));  // end
        // Parse body into stmt.sub_body until Next
        LBodyNode := AParser.CreateNode('stmt.sub_body');
        while not AParser.Check('keyword.next') and
              not AParser.Check(PARSE_KIND_EOF) do
        begin
          LChild := AParser.ParseStatement();
          if LChild <> nil then
            LBodyNode.AddChild(TParseASTNode(LChild));
        end;
        LNode.AddChild(LBodyNode);
        AParser.Expect('keyword.next');
        // Optional 'Next i' — consume the loop variable identifier if present
        if AParser.Check(PARSE_KIND_IDENTIFIER) then
          AParser.Consume();
        Result := LNode;
      end);

    // While condition body Wend -> stmt.while
    // child[0] = condition expr, child[1] = stmt.sub_body
    LParse.Config().RegisterStatement('keyword.while', 'stmt.while',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:     TParseASTNode;
        LBodyNode: TParseASTNode;
        LChild:    TParseASTNodeBase;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'While'
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));  // condition
        // Parse body into stmt.sub_body until Wend
        LBodyNode := AParser.CreateNode('stmt.sub_body');
        while not AParser.Check('keyword.wend') and
              not AParser.Check(PARSE_KIND_EOF) do
        begin
          LChild := AParser.ParseStatement();
          if LChild <> nil then
            LBodyNode.AddChild(TParseASTNode(LChild));
        end;
        LNode.AddChild(LBodyNode);
        AParser.Expect('keyword.wend');
        Result := LNode;
      end);

    // Print expr [, expr ...] -> stmt.print
    LParse.Config().RegisterStatement('keyword.print', 'stmt.print',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'Print'
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        while AParser.Match('delimiter.comma') do
          LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        Result := LNode;
      end);

    // Identifier as statement — assignment or procedure call
    // ident = expr       -> stmt.assign  (= is consumed here, never reaches infix engine)
    // ident [(args)]     -> stmt.call
    LParse.Config().RegisterStatement(PARSE_KIND_IDENTIFIER, 'stmt.ident_stmt',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:    TParseASTNode;
        LNameTok: TParseToken;
      begin
        LNameTok := AParser.CurrentToken();
        AParser.Consume();  // consume identifier
        if AParser.Check('op.eq_or_assign') then
        begin
          // Assignment statement: name = expr
          LNode := AParser.CreateNode('stmt.assign', LNameTok);
          AParser.Consume();  // consume '='
          LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
          Result := LNode;
        end
        else
        begin
          // Procedure call: name [(args)]
          LNode := AParser.CreateNode('stmt.call', LNameTok);
          LNode.SetAttr('call.name', TValue.From<string>(LNameTok.Text));
          if AParser.Match('delimiter.lparen') then
          begin
            if not AParser.Check('delimiter.rparen') then
            begin
              LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
              while AParser.Match('delimiter.comma') do
                LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
            end;
            AParser.Expect('delimiter.rparen');
          end;
          Result := LNode;
        end;
      end);

    //=========================================================================
    // SEMANTICS
    //=========================================================================

    // program.root — push global scope, visit all top-level children, pop
    LParse.Config().RegisterSemanticRule('program.root',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.PushScope('global', ANode.GetToken());
        ASem.VisitChildren(ANode);
        ASem.PopScope(ANode.GetToken());
      end);

    // stmt.dim_decl — resolve type, determine storage class, declare symbol
    LParse.Config().RegisterSemanticRule('stmt.dim_decl',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LTypeAttr: TValue;
        LTypeText: string;
        LTypeKind: string;
        LStorage:  string;
        LVarName:  string;
      begin
        ANode.GetAttr('var.type_text', LTypeAttr);
        LTypeText := LTypeAttr.AsString;
        LTypeKind := LParse.Config().TypeTextToKind(LTypeText);
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>(LTypeKind));
        // Global unless declared inside a Sub/Function scope (sentinel check)
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

    // stmt.sub_decl — declare sub, push scope, visit params + body, pop
    LParse.Config().RegisterSemanticRule('stmt.sub_decl',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LAttr:  TValue;
        LName:  string;
        LI:     Integer;
        LChild: TParseASTNodeBase;
      begin
        ANode.GetAttr('decl.name', LAttr);
        LName := LAttr.AsString;
        ASem.DeclareSymbol(LName, ANode);
        ASem.PushScope(LName, ANode.GetToken());
        // Sentinel so dim_decl handlers know they are inside a routine
        // Visit param_decl children (all but last child which is stmt.sub_body)
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

    // stmt.func_decl — declare func, push scope, declare func name as return
    // variable (Basic return convention), visit params + body, pop
    LParse.Config().RegisterSemanticRule('stmt.func_decl',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LAttr:       TValue;
        LName:       string;
        LReturnText: string;
        LReturnKind: string;
        LReturnNode: TParseASTNode;
        LReturnTok:  TParseToken;
        LI:          Integer;
      begin
        ANode.GetAttr('decl.name', LAttr);
        LName := LAttr.AsString;
        // Declare in outer scope so callers can resolve the function name
        ASem.DeclareSymbol(LName, ANode);
        ASem.PushScope(LName, ANode.GetToken());
        // Sentinel so dim_decl handlers know they are inside a routine
        // Visit param_decl children (all but last child which is stmt.sub_body)
        for LI := 0 to ANode.ChildCount() - 2 do
          ASem.VisitNode(ANode.GetChild(LI));
        // Declare the function name as a local variable with the return type.
        // This shadows the outer declaration inside the function body, allowing
        // 'FuncName = expr' assignments to be resolved as local variable writes.
        ANode.GetAttr('decl.return_type', LAttr);
        LReturnText := LAttr.AsString;
        LReturnKind := LParse.Config().TypeTextToKind(LReturnText);
        LReturnTok  := ANode.GetToken();
        LReturnNode := TParseASTNode.CreateNode('stmt.dim_decl', LReturnTok);
        LReturnNode.SetAttr('var.type_text', TValue.From<string>(LReturnText));
        LReturnNode.SetAttr(PARSE_ATTR_TYPE_KIND, TValue.From<string>(LReturnKind));
        LReturnNode.SetAttr(PARSE_ATTR_STORAGE_CLASS, TValue.From<string>('local'));
        ASem.DeclareSymbol(LName, LReturnNode);
        // Visit body (last child)
        if ANode.ChildCount() > 0 then
          ASem.VisitNode(ANode.GetChild(ANode.ChildCount() - 1));
        ASem.PopScope(ANode.GetToken());
      end);

    // stmt.param_decl — map type, set storage class, declare symbol
    LParse.Config().RegisterSemanticRule('stmt.param_decl',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LTypeAttr:  TValue;
        LTypeText:  string;
        LTypeKind:  string;
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

    // stmt.sub_body — visit children
    LParse.Config().RegisterSemanticRule('stmt.sub_body',
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

    // stmt.for — visit children
    LParse.Config().RegisterSemanticRule('stmt.for',
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

    // stmt.print — visit children
    LParse.Config().RegisterSemanticRule('stmt.print',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // stmt.assign — visit children (resolves RHS expression)
    LParse.Config().RegisterSemanticRule('stmt.assign',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // stmt.call — visit children (resolves argument expressions)
    LParse.Config().RegisterSemanticRule('stmt.call',
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

    // expr.call — visit children (resolves argument expressions)
    LParse.Config().RegisterSemanticRule('expr.call',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // expr.ident — resolve symbol, copy type kind from declaration
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

    // expr.integer -> type.integer
    LParse.Config().RegisterSemanticRule('expr.integer',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.integer'));
      end);

    // expr.real -> type.double
    LParse.Config().RegisterSemanticRule('expr.real',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.double'));
      end);

    // expr.string -> type.string
    LParse.Config().RegisterSemanticRule('expr.string',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.string'));
      end);

    // expr.bool -> type.boolean
    LParse.Config().RegisterSemanticRule('expr.bool',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.boolean'));
      end);

    //=========================================================================
    // EMITTERS
    //=========================================================================

    // program.root — write header includes, emit declarations, wrap main()
    // Two-pass approach: pass 1 emits all dim_decl/sub_decl/func_decl nodes
    // in their natural order; pass 2 wraps all executable statements in main().
    LParse.Config().RegisterEmitter('program.root',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LI:    Integer;
        LKind: string;
      begin
        AGen.EmitLine('#pragma once', sfHeader);
        AGen.Include('cstdint',  sfHeader);
        AGen.Include('iostream', sfHeader);
        AGen.Include('string',   sfHeader);
        // Pass 1: global variable declarations and sub/function definitions
        for LI := 0 to ANode.ChildCount() - 1 do
        begin
          LKind := ANode.GetChild(LI).GetNodeKind();
          if (LKind = 'stmt.dim_decl') or
             (LKind = 'stmt.sub_decl') or
             (LKind = 'stmt.func_decl') then
            AGen.EmitNode(ANode.GetChild(LI));
        end;
        // Pass 2: executable statements wrapped in int main()
        AGen.Func('main', 'int');
        for LI := 0 to ANode.ChildCount() - 1 do
        begin
          LKind := ANode.GetChild(LI).GetNodeKind();
          if (LKind <> 'stmt.dim_decl') and
             (LKind <> 'stmt.sub_decl') and
             (LKind <> 'stmt.func_decl') then
            AGen.EmitNode(ANode.GetChild(LI));
        end;
        AGen.Return(AGen.Lit(0));
        AGen.EndFunc();
      end);

    // stmt.dim_decl — emit global or local variable declaration
    LParse.Config().RegisterEmitter('stmt.dim_decl',
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

    // stmt.sub_decl — forward declaration to header, full definition to source
    LParse.Config().RegisterEmitter('stmt.sub_decl',
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
        // Build parameter string for forward declaration
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
        // Full definition to source
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
        // Body is always last child (stmt.sub_body)
        AGen.EmitNode(ANode.GetChild(ANode.ChildCount() - 1));
        AGen.EndFunc();
      end);

    // stmt.func_decl — forward declaration to header, full definition to source
    // Declares the function name as a local return variable (Basic convention).
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
        // Build parameter string
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
        // Declare function name as return variable — Basic assigns to it directly
        AGen.DeclVar(LName, LCppReturn, '{}');
        // Body is always last child (stmt.sub_body)
        AGen.EmitNode(ANode.GetChild(ANode.ChildCount() - 1));
        AGen.Return(AGen.Get(LName));
        AGen.EndFunc();
      end);

    // stmt.param_decl — no-op; params are emitted by sub/func emitters
    LParse.Config().RegisterEmitter('stmt.param_decl',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        // Intentionally empty — params are emitted inline by sub/func emitters
      end);

    // stmt.sub_body — braces are the parent's responsibility
    LParse.Config().RegisterEmitter('stmt.sub_body',
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

    // stmt.for — C++ for loop (always ascending: i <= end, i++)
    LParse.Config().RegisterEmitter('stmt.for',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LAttr:     TValue;
        LVarName:  string;
        LStartStr: string;
        LEndStr:   string;
        LCond:     string;
        LStep:     string;
      begin
        ANode.GetAttr('for.var', LAttr);
        LVarName  := LAttr.AsString;
        LStartStr := LParse.Config().ExprToString(ANode.GetChild(0));
        LEndStr   := LParse.Config().ExprToString(ANode.GetChild(1));
        LCond     := LVarName + ' <= ' + LEndStr;
        LStep     := LVarName + '++';
        AGen.EmitLine('for (' + LVarName + ' = ' + LStartStr + '; ' + LCond + '; ' + LStep + ') {');
        AGen.IndentIn();
        AGen.EmitNode(ANode.GetChild(2));
        AGen.IndentOut();
        AGen.EmitLine('}');
      end);

    // stmt.while — C++ while loop
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

    // stmt.print — std::cout chain with trailing newline
    // Because & maps to <<, concat expressions already produce stream-chain
    // strings: "text" << var << "more". The cout prefix and \n suffix complete
    // the chain: std::cout << "text" << var << "more" << "\n";
    LParse.Config().RegisterEmitter('stmt.print',
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

    // stmt.assign — variable assignment statement
    LParse.Config().RegisterEmitter('stmt.assign',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        AGen.Assign(ANode.GetToken().Text,
          LParse.Config().ExprToString(ANode.GetChild(0)));
      end);

    // stmt.call — standalone procedure call statement
    LParse.Config().RegisterEmitter('stmt.call',
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

    LParse.SetSourceFile('..\languages\src\HelloWorld.bas');
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
      TParseUtils.PrintLn(COLOR_RED + 'Basic compilation failed.');
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
