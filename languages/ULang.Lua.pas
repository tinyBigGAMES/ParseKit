{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

(*
  ULang.Lua — Lua showcase language built on Parse()

  Proves Parse() can handle a dynamically-typed language using literal-based
  and call-site type inference entirely within the language file, with zero
  toolkit changes.

    - No explicit type annotations anywhere
    - Literal-based type inference at declaration sites
    - Call-site pre-scan for parameter type inference
    - local/global variable declarations
    - function/end with inferred return type
    - if/then/else/end, for i=start,limit do/end, while/do/end
    - print() variadic statement (std::cout chain)
    - .. string concatenation
    - Symbol resolution and semantic error reporting
    - Full C++23 forward declarations to .h

  Target source: languages/src/HelloWorld.lua
  Expected output: HelloWorld.h + HelloWorld.cpp → native binary
*)

unit ULang.Lua;

{$I Parse.Defines.inc}

interface

uses
  Parse;

procedure Demo(const APlatform: TParseTargetPlatform = tpWin64;
  const ALevel: TParseOptimizeLevel = olDebug);

implementation

uses
  System.SysUtils,
  System.Rtti;

// ---------------------------------------------------------------------------
// Demo — wire up and run the full Lua pipeline
// ---------------------------------------------------------------------------

procedure Demo(const APlatform: TParseTargetPlatform;
  const ALevel: TParseOptimizeLevel);
var
  LParse:    TParse;
begin
  LParse := TParse.Create();
  try

    //=========================================================================
    // LEXER
    //=========================================================================
    LParse.Config()
      .CaseSensitiveKeywords(True)
      // Keywords
      .AddKeyword('local',    'keyword.local')
      .AddKeyword('function', 'keyword.function')
      .AddKeyword('end',      'keyword.end')
      .AddKeyword('return',   'keyword.return')
      .AddKeyword('if',       'keyword.if')
      .AddKeyword('then',     'keyword.then')
      .AddKeyword('elseif',   'keyword.elseif')
      .AddKeyword('else',     'keyword.else')
      .AddKeyword('for',      'keyword.for')
      .AddKeyword('do',       'keyword.do')
      .AddKeyword('while',    'keyword.while')
      .AddKeyword('repeat',   'keyword.repeat')
      .AddKeyword('until',    'keyword.until')
      .AddKeyword('print',    'keyword.print')
      .AddKeyword('and',      'keyword.and')
      .AddKeyword('or',       'keyword.or')
      .AddKeyword('not',      'keyword.not')
      .AddKeyword('true',     'keyword.true')
      .AddKeyword('false',    'keyword.false')
      .AddKeyword('nil',      'keyword.nil')
      // Operators — longest-match first (multi-char before single-char)
      .AddOperator('~=', 'op.neq')
      .AddOperator('<=', 'op.lte')
      .AddOperator('>=', 'op.gte')
      .AddOperator('==', 'op.eq')
      .AddOperator('..', 'op.concat')
      .AddOperator('=',  'op.assign')
      .AddOperator('<',  'op.lt')
      .AddOperator('>',  'op.gt')
      .AddOperator('+',  'op.plus')
      .AddOperator('-',  'op.minus')
      .AddOperator('*',  'op.multiply')
      .AddOperator('/',  'op.divide')
      .AddOperator('%',  'op.mod')
      .AddOperator('(',  'delimiter.lparen')
      .AddOperator(')',  'delimiter.rparen')
      .AddOperator(',',  'delimiter.comma')
      .AddOperator(';',  'delimiter.semicolon')
      // String styles — both double and single quoted, with escape processing
      .AddStringStyle('"', '"', PARSE_KIND_STRING, True)
      .AddStringStyle('''', '''', PARSE_KIND_STRING, True)
      // Comments
      .AddLineComment('--')
      .AddBlockComment('--[[', ']]')
      // No statement terminator — Lua uses newlines as implicit separators
      .SetStatementTerminator('')
      // Type inference surface
      .AddLiteralType('expr.integer', 'type.integer')
      .AddLiteralType('expr.real',    'type.double')
      .AddLiteralType('expr.string',  'type.string')
      .AddLiteralType('expr.bool',    'type.boolean')
      .AddLiteralType('expr.nil',     'type.double')
      .AddDeclKind('stmt.local_decl')
      .AddDeclKind('stmt.global_assign')
      .AddCallKind('expr.call')
      .AddCallKind('stmt.call');

    // ExprToString override: nil → 0
    LParse.Config().RegisterExprOverride('expr.nil',
      function(const ANode: TParseASTNodeBase;
        const ADefault: TParseExprToStringFunc): string
      begin
        Result := '0';
      end);

    //=========================================================================
    // GRAMMAR — PREFIX HANDLERS
    //=========================================================================

    // Standard literal prefixes: identifier, integer, real, string
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

    // nil
    LParse.Config().RegisterPrefix('keyword.nil', 'expr.nil',
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

    // - as prefix (unary negation)
    LParse.Config().RegisterPrefix('op.minus', 'expr.unary',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('-'));
        AParser.Consume();  // consume '-'
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

    LParse.Config()
      .RegisterBinaryOp('op.eq',       10, '==')
      .RegisterBinaryOp('op.neq',      10, '!=')
      .RegisterBinaryOp('op.lt',       10, '<')
      .RegisterBinaryOp('op.gt',       10, '>')
      .RegisterBinaryOp('op.lte',      10, '<=')
      .RegisterBinaryOp('op.gte',      10, '>=')
      .RegisterBinaryOp('op.concat',   15, '<<')
      .RegisterBinaryOp('op.plus',     20, '+')
      .RegisterBinaryOp('op.minus',    20, '-')
      .RegisterBinaryOp('op.multiply', 30, '*')
      .RegisterBinaryOp('op.divide',   30, '/')
      .RegisterBinaryOp('op.mod',      30, '%')
      .RegisterBinaryOp('keyword.and',  8, '&&')
      .RegisterBinaryOp('keyword.or',   6, '||');

    // ( as infix — function call expression (left-assoc, power 40)
    LParse.Config().RegisterInfixLeft('delimiter.lparen', 40, 'expr.call',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
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

    // local x = expr → stmt.local_decl
    LParse.Config().RegisterStatement('keyword.local', 'stmt.local_decl',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:    TParseASTNode;
        LNameTok: TParseToken;
      begin
        AParser.Consume();  // consume 'local'
        LNameTok := AParser.CurrentToken();
        AParser.Consume();  // consume variable name identifier
        AParser.Expect('op.assign');
        LNode := AParser.CreateNode('stmt.local_decl', LNameTok);
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        Result := LNode;
      end);

    // function name(...) ... end → stmt.func_decl
    LParse.Config().RegisterStatement('keyword.function', 'stmt.func_decl',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:      TParseASTNode;
        LParamNode: TParseASTNode;
        LNameTok:   TParseToken;
        LParamTok:  TParseToken;
        LBodyNode:  TParseASTNode;
        LChild:     TParseASTNodeBase;
      begin
        AParser.Consume();  // consume 'function'
        LNameTok := AParser.CurrentToken();
        LNode := AParser.CreateNode('stmt.func_decl', LNameTok);
        LNode.SetAttr('decl.name', TValue.From<string>(LNameTok.Text));
        AParser.Consume();  // consume function name
        AParser.Expect('delimiter.lparen');
        // Parse parameter list (no type annotations)
        while not AParser.Check('delimiter.rparen') do
        begin
          LParamTok := AParser.CurrentToken();
          LParamNode := AParser.CreateNode('stmt.param_decl', LParamTok);
          AParser.Consume();  // consume param name
          LNode.AddChild(LParamNode);
          if AParser.Check('delimiter.comma') then
            AParser.Consume()
          else
            Break;
        end;
        AParser.Expect('delimiter.rparen');
        // Parse body until 'end'
        LBodyNode := AParser.CreateNode('stmt.func_body', LNameTok);
        while not AParser.Check('keyword.end') and
              not AParser.Check(PARSE_KIND_EOF) do
        begin
          LChild := AParser.ParseStatement();
          if LChild <> nil then
            LBodyNode.AddChild(TParseASTNode(LChild));
        end;
        AParser.Expect('keyword.end');
        LNode.AddChild(LBodyNode);
        Result := LNode;
      end);

    // if cond then ... [else ...] end → stmt.if
    LParse.Config().RegisterStatement('keyword.if', 'stmt.if',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:     TParseASTNode;
        LThenBody: TParseASTNode;
        LElseBody: TParseASTNode;
        LChild:    TParseASTNodeBase;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'if'
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));  // condition
        AParser.Expect('keyword.then');
        // Then-body: parse until else/elseif/end
        LThenBody := AParser.CreateNode('stmt.func_body');
        while not AParser.Check('keyword.else') and
              not AParser.Check('keyword.elseif') and
              not AParser.Check('keyword.end') and
              not AParser.Check(PARSE_KIND_EOF) do
        begin
          LChild := AParser.ParseStatement();
          if LChild <> nil then
            LThenBody.AddChild(TParseASTNode(LChild));
        end;
        LNode.AddChild(LThenBody);
        // Optional else body
        if AParser.Match('keyword.else') then
        begin
          LElseBody := AParser.CreateNode('stmt.func_body');
          while not AParser.Check('keyword.end') and
                not AParser.Check(PARSE_KIND_EOF) do
          begin
            LChild := AParser.ParseStatement();
            if LChild <> nil then
              LElseBody.AddChild(TParseASTNode(LChild));
          end;
          LNode.AddChild(LElseBody);
        end;
        AParser.Expect('keyword.end');
        Result := LNode;
      end);

    // for i = start, limit do ... end → stmt.for
    LParse.Config().RegisterStatement('keyword.for', 'stmt.for',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:     TParseASTNode;
        LBodyNode: TParseASTNode;
        LVarTok:   TParseToken;
        LChild:    TParseASTNodeBase;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'for'
        LVarTok := AParser.CurrentToken();
        LNode.SetAttr('for.var', TValue.From<string>(LVarTok.Text));
        AParser.Consume();  // consume loop variable identifier
        AParser.Consume();  // consume '=' (op.assign)
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));  // start
        AParser.Expect('delimiter.comma');
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));  // limit
        AParser.Expect('keyword.do');
        // Body until 'end'
        LBodyNode := AParser.CreateNode('stmt.func_body', LVarTok);
        while not AParser.Check('keyword.end') and
              not AParser.Check(PARSE_KIND_EOF) do
        begin
          LChild := AParser.ParseStatement();
          if LChild <> nil then
            LBodyNode.AddChild(TParseASTNode(LChild));
        end;
        AParser.Expect('keyword.end');
        LNode.AddChild(LBodyNode);
        Result := LNode;
      end);

    // while cond do ... end → stmt.while
    LParse.Config().RegisterStatement('keyword.while', 'stmt.while',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:     TParseASTNode;
        LBodyNode: TParseASTNode;
        LChild:    TParseASTNodeBase;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'while'
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));  // condition
        AParser.Expect('keyword.do');
        // Body until 'end'
        LBodyNode := AParser.CreateNode('stmt.func_body');
        while not AParser.Check('keyword.end') and
              not AParser.Check(PARSE_KIND_EOF) do
        begin
          LChild := AParser.ParseStatement();
          if LChild <> nil then
            LBodyNode.AddChild(TParseASTNode(LChild));
        end;
        AParser.Expect('keyword.end');
        LNode.AddChild(LBodyNode);
        Result := LNode;
      end);

    // return [expr] → stmt.return
    LParse.Config().RegisterStatement('keyword.return', 'stmt.return',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'return'
        // Parse return expression if not at a statement-closing token
        if not AParser.Check(PARSE_KIND_EOF) and
           not AParser.Check('keyword.end') and
           not AParser.Check('keyword.else') and
           not AParser.Check('keyword.elseif') then
          LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        Result := LNode;
      end);

    // print(args...) → stmt.print
    LParse.Config().RegisterStatement('keyword.print', 'stmt.print',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();  // consume 'print'
        AParser.Expect('delimiter.lparen');
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        while AParser.Match('delimiter.comma') do
          LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        AParser.Expect('delimiter.rparen');
        Result := LNode;
      end);

    // Identifier as statement — global assign or standalone call
    LParse.Config().RegisterStatement(PARSE_KIND_IDENTIFIER, 'stmt.global_assign',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:    TParseASTNode;
        LNameTok: TParseToken;
      begin
        LNameTok := AParser.CurrentToken();
        AParser.Consume();  // consume identifier
        if AParser.Check('op.assign') then
        begin
          // global_assign: name = expr
          AParser.Consume();  // consume '='
          LNode := AParser.CreateNode('stmt.global_assign', LNameTok);
          LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        end
        else
        begin
          // Standalone procedure call: name(args)
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
        end;
        Result := LNode;
      end);

    //=========================================================================
    // SEMANTIC HANDLERS
    //=========================================================================

    // program.root — pre-scan declarations, then call sites, then analyze
    LParse.Config().RegisterSemanticRule('program.root',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        // Pre-scan: collect decl types then call-site arg types
        LParse.Config().ScanAll(ANode);
        ASem.PushScope('global', ANode.GetToken());
        ASem.VisitChildren(ANode);
        ASem.PopScope(ANode.GetToken());
      end);

    // stmt.lua_program — visit children
    LParse.Config().RegisterSemanticRule('stmt.lua_program',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // stmt.local_decl — infer type from initializer, set storage, declare symbol
    LParse.Config().RegisterSemanticRule('stmt.local_decl',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LTypeKind:  string;
        LTypeAttr:  TValue;
        LVarName:   string;
        LStorage:   string;
      begin
        // Visit initializer first so its type gets resolved
        if ANode.ChildCount() > 0 then
          ASem.VisitNode(ANode.GetChild(0));
        // Read type from initializer
        LTypeKind := 'type.double';  // default
        if ANode.ChildCount() > 0 then
        begin
          if ANode.GetChild(0).GetAttr(PARSE_ATTR_TYPE_KIND, LTypeAttr) then
          begin
            if LTypeAttr.AsString <> '' then
              LTypeKind := LTypeAttr.AsString;
          end
          else
            LTypeKind := LParse.Config().InferLiteralType(ANode.GetChild(0));
        end;
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>(LTypeKind));
        // Storage: local inside routines, global at top level
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

    // stmt.global_assign — visit child, infer type, declare if new
    LParse.Config().RegisterSemanticRule('stmt.global_assign',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LTypeKind:  string;
        LTypeAttr:  TValue;
        LDeclNode:  TParseASTNodeBase;
        LVarName:   string;
      begin
        if ANode.ChildCount() > 0 then
          ASem.VisitNode(ANode.GetChild(0));
        LTypeKind := 'type.double';
        if ANode.ChildCount() > 0 then
        begin
          if ANode.GetChild(0).GetAttr(PARSE_ATTR_TYPE_KIND, LTypeAttr) then
          begin
            if LTypeAttr.AsString <> '' then
              LTypeKind := LTypeAttr.AsString;
          end
          else
            LTypeKind := LParse.Config().InferLiteralType(ANode.GetChild(0));
        end;
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>(LTypeKind));
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_STORAGE_CLASS,
          TValue.From<string>('global'));
        LVarName := ANode.GetToken().Text;
        // Only declare if not already in scope
        if not ASem.LookupSymbolLocal(LVarName, LDeclNode) then
          ASem.DeclareSymbol(LVarName, ANode);
      end);

    // stmt.func_decl — declare, push scope, assign param types, infer return
    LParse.Config().RegisterSemanticRule('stmt.func_decl',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LAttr:       TValue;
        LName:       string;
        LReturnKind: string;
        LI:          Integer;
        LChild:      TParseASTNodeBase;
        LArgTypes:   TArray<string>;
        LParamIndex: Integer;
        LParamKind:  string;
        LBodyNode:   TParseASTNodeBase;
        LFuncTok:    TParseToken;
        LResultNode: TParseASTNode;
      begin
        ANode.GetAttr('decl.name', LAttr);
        LName := LAttr.AsString;
        ASem.DeclareSymbol(LName, ANode);
        ASem.PushScope(LName, ANode.GetToken());
        // Assign types to param_decl children from call-site data
        LParamIndex := 0;
        if LParse.Config().GetCallArgTypes().ContainsKey(LName) then
          LArgTypes := LParse.Config().GetCallArgTypes()[LName]
        else
          SetLength(LArgTypes, 0);
        for LI := 0 to ANode.ChildCount() - 2 do
        begin
          LChild := ANode.GetChild(LI);
          if LChild.GetNodeKind() <> 'stmt.param_decl' then
            Continue;
          if LParamIndex < Length(LArgTypes) then
            LParamKind := LArgTypes[LParamIndex]
          else
            LParamKind := 'type.double';
          TParseASTNode(LChild).SetAttr(PARSE_ATTR_TYPE_KIND,
            TValue.From<string>(LParamKind));
          TParseASTNode(LChild).SetAttr(PARSE_ATTR_STORAGE_CLASS,
            TValue.From<string>('param'));
          ASem.DeclareSymbol(LChild.GetToken().Text, LChild);
          Inc(LParamIndex);
        end;
        // Infer return type from body's return statements
        LBodyNode := ANode.GetChild(ANode.ChildCount() - 1);
        LReturnKind := LParse.Config().ScanReturnTypeRecursive(LBodyNode, 'stmt.return');
        if LReturnKind = '' then
          LReturnKind := 'type.void';
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>(LReturnKind));
        // Declare function name as local variable for 'Add = a + b' return pattern
        if LReturnKind <> 'type.void' then
        begin
          LFuncTok    := ANode.GetToken();
          LResultNode := TParseASTNode.CreateNode('stmt.local_decl', LFuncTok);
          LResultNode.SetAttr(PARSE_ATTR_TYPE_KIND,
            TValue.From<string>(LReturnKind));
          LResultNode.SetAttr(PARSE_ATTR_STORAGE_CLASS,
            TValue.From<string>('local'));
          ASem.DeclareSymbol(LName, LResultNode);
        end;
        // Visit body
        ASem.VisitNode(LBodyNode);
        ASem.PopScope(ANode.GetToken());
      end);

    // stmt.param_decl — no-op here; fully handled by stmt.func_decl above
    LParse.Config().RegisterSemanticRule('stmt.param_decl',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        // Intentionally empty — enriched by stmt.func_decl handler
      end);

    // stmt.func_body — visit children
    LParse.Config().RegisterSemanticRule('stmt.func_body',
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

    // stmt.call — visit children
    LParse.Config().RegisterSemanticRule('stmt.call',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // stmt.assign — visit children
    LParse.Config().RegisterSemanticRule('stmt.assign',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // stmt.return — visit children
    LParse.Config().RegisterSemanticRule('stmt.return',
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

    // expr.ident — resolve symbol, copy type kind
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

    // expr.integer → type.integer
    LParse.Config().RegisterSemanticRule('expr.integer',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.integer'));
      end);

    // expr.real → type.double
    LParse.Config().RegisterSemanticRule('expr.real',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.double'));
      end);

    // expr.string → type.string
    LParse.Config().RegisterSemanticRule('expr.string',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.string'));
      end);

    // expr.bool → type.boolean
    LParse.Config().RegisterSemanticRule('expr.bool',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.boolean'));
      end);

    // expr.nil → type.double (default)
    LParse.Config().RegisterSemanticRule('expr.nil',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.double'));
      end);

    //=========================================================================
    // EMITTERS
    //=========================================================================

    // program.root — header includes, two-pass emit: declarations then main()
    // All Lua statements are direct children of program.root (no wrapper node).
    // Pass 1: emit global variable declarations and function definitions.
    // Pass 2: wrap all executable statements in int main().
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
        // Pass 1: global variable declarations and function definitions
        for LI := 0 to ANode.ChildCount() - 1 do
        begin
          LKind := ANode.GetChild(LI).GetNodeKind();
          if (LKind = 'stmt.local_decl') or (LKind = 'stmt.func_decl') then
            AGen.EmitNode(ANode.GetChild(LI));
        end;
        // Pass 2: executable statements wrapped in int main()
        AGen.Func('main', 'int');
        for LI := 0 to ANode.ChildCount() - 1 do
        begin
          LKind := ANode.GetChild(LI).GetNodeKind();
          if (LKind <> 'stmt.local_decl') and (LKind <> 'stmt.func_decl') then
            AGen.EmitNode(ANode.GetChild(LI));
        end;
        AGen.Return(AGen.Lit(0));
        AGen.EndFunc();
      end);

    // stmt.local_decl — emit global or local variable declaration
    LParse.Config().RegisterEmitter('stmt.local_decl',
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

    // stmt.global_assign — emit assignment (inside main)
    LParse.Config().RegisterEmitter('stmt.global_assign',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LVarName: string;
      begin
        LVarName := ANode.GetToken().Text;
        if ANode.ChildCount() > 0 then
          AGen.Assign(LVarName, LParse.Config().ExprToString(ANode.GetChild(0)));
      end);

    // stmt.func_decl — forward decl to header, full definition to source
    LParse.Config().RegisterEmitter('stmt.func_decl',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LAttr:      TValue;
        LName:      string;
        LReturnKind: string;
        LCppReturn:  string;
        LParams:    string;
        LI:         Integer;
        LChild:     TParseASTNodeBase;
        LParamAttr: TValue;
        LParamKind: string;
        LCppType:   string;
        LParamName: string;
        LIsVoid:    Boolean;
      begin
        ANode.GetAttr('decl.name', LAttr);
        LName := LAttr.AsString;
        ANode.GetAttr(PARSE_ATTR_TYPE_KIND, LAttr);
        LReturnKind := LAttr.AsString;
        LIsVoid     := LReturnKind = 'type.void';
        LCppReturn  := LParse.Config().TypeToIR(LReturnKind);
        // Build param string for forward declaration
        LParams := '';
        for LI := 0 to ANode.ChildCount() - 2 do
        begin
          LChild := ANode.GetChild(LI);
          if LChild.GetNodeKind() <> 'stmt.param_decl' then
            Continue;
          LChild.GetAttr(PARSE_ATTR_TYPE_KIND, LParamAttr);
          LParamKind := LParamAttr.AsString;
          LCppType   := LParse.Config().TypeToIR(LParamKind);
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
          LChild.GetAttr(PARSE_ATTR_TYPE_KIND, LParamAttr);
          LParamKind := LParamAttr.AsString;
          LCppType   := LParse.Config().TypeToIR(LParamKind);
          LParamName := LChild.GetToken().Text;
          AGen.Param(LParamName, LCppType);
        end;
        // Declare return variable (function-name convention) if not void
        if not LIsVoid then
          AGen.DeclVar(LName, LCppReturn, '{}');
        // Store current function name in context for stmt.return emitter
        AGen.SetContext('current_func', LName);
        // Emit body
        AGen.EmitNode(ANode.GetChild(ANode.ChildCount() - 1));
        // Return statement if not void
        if not LIsVoid then
          AGen.Return(AGen.Get(LName));
        AGen.EndFunc();
        // Clear current function name
        AGen.SetContext('current_func', '');
      end);

    // stmt.param_decl — no-op, handled by func emitter
    LParse.Config().RegisterEmitter('stmt.param_decl',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        // Intentionally empty — params emitted by func emitter
      end);

    // stmt.func_body — emit all children
    LParse.Config().RegisterEmitter('stmt.func_body',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        AGen.EmitChildren(ANode);
      end);

    // stmt.if — if/else structure
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

    // stmt.for — numeric for loop
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
        AGen.ForStmt(LVarName, LStartStr, LCond, LStep);
        AGen.EmitNode(ANode.GetChild(2));
        AGen.EndFor();
      end);

    // stmt.while — while loop
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

    // stmt.print — std::cout chain with trailing newline.
    // LuaExprToString renders .. concat nodes as 'left << right' (op='<<'),
    // so each argument naturally flattens into a << chain for cout.
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

    // stmt.assign — assignment inside a function body
    LParse.Config().RegisterEmitter('stmt.assign',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        if ANode.ChildCount() > 0 then
          AGen.Assign(ANode.GetToken().Text,
            LParse.Config().ExprToString(ANode.GetChild(0)));
      end);

    // stmt.call — standalone procedure call
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

    // stmt.return — assign return expression to the function-name variable.
    // current_func context key is set by stmt.func_decl emitter.
    LParse.Config().RegisterEmitter('stmt.return',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        if ANode.ChildCount() > 0 then
          AGen.Assign(AGen.GetContext('current_func'),
            LParse.Config().ExprToString(ANode.GetChild(0)));
      end);

    // expr.call used as a statement expression (should not normally appear at
    // top-level emit, but handle defensively)
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

    LParse.SetSourceFile('..\languages\src\HelloWorld.lua');
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
      TParseUtils.PrintLn(COLOR_RED + 'Lua compilation failed.');
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
