{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

(*
  ULang.Scheme — Scheme showcase language built on Parse()

  Proves Parse() can handle a Lisp/S-expression language using a single
  delimiter.lparen statement handler — no infix operators, no block keywords.
  All parsing is driven by prefix dispatch inside the universal `(` handler.

    - S-expression syntax: ( op args... )
    - No infix operators — zero RegisterInfixLeft calls
    - (define var expr) — global/local variable definition
    - (define (f args) body) — named function with inferred return type
    - (set! x expr) — mutation
    - (if cond then [else]) — expression-form conditional
    - (begin expr...) — sequence form
    - (display expr) — individual cout statement
    - (newline) — separate cout newline statement
    - Tail-recursive loops — no ForStmt/WhileStmt required
    - Kebab-case → snake_case name mangling
    - #t / #f boolean literals
    - Full C++23 forward declarations to .h

  Target source: languages/src/HelloWorld.scm
  Expected output: HelloWorld.h + HelloWorld.cpp → native binary
*)

unit ULang.Scheme;

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
// Demo — wire up and run the full Scheme pipeline
// ---------------------------------------------------------------------------

procedure Demo(const APlatform: TParseTargetPlatform;
  const ALevel: TParseOptimizeLevel);
var
  LParse:     TParse;
  ParseSExpr: TParseStatementHandler;
begin
  LParse := TParse.Create();

  // ParseSExpr is an anonymous method variable so it can be captured by
  // the registered statement handler closures and call itself recursively.
  ParseSExpr := function(AParser: TParseParserBase): TParseASTNodeBase
  var
    LNode:    TParseASTNode;
    LOpKind:  string;
    LOpTok:   TParseToken;
    LOpStr:   string;
    LNameTok: TParseToken;
  begin
    // S-expression starting with (
    if AParser.Check('delimiter.lparen') then
    begin
      AParser.Consume();  // consume '('
      LOpKind := AParser.CurrentToken().Kind;

      // Arithmetic / comparison binary
      if (LOpKind = 'op.plus') or (LOpKind = 'op.minus') or
         (LOpKind = 'op.multiply') or (LOpKind = 'op.divide') or
         (LOpKind = 'op.eq') or (LOpKind = 'op.lt') or
         (LOpKind = 'op.gt') or (LOpKind = 'op.lte') or
         (LOpKind = 'op.gte') then
      begin
        LOpTok := AParser.CurrentToken();
        if LOpKind = 'op.plus' then
          LOpStr := '+'
        else if LOpKind = 'op.minus' then
          LOpStr := '-'
        else if LOpKind = 'op.multiply' then
          LOpStr := '*'
        else if LOpKind = 'op.divide' then
          LOpStr := '/'
        else if LOpKind = 'op.eq' then
          LOpStr := '=='
        else if LOpKind = 'op.lt' then
          LOpStr := '<'
        else if LOpKind = 'op.gt' then
          LOpStr := '>'
        else if LOpKind = 'op.lte' then
          LOpStr := '<='
        else
          LOpStr := '>=';
        AParser.Consume();  // consume operator
        LNode := AParser.CreateNode('expr.binary', LOpTok);
        LNode.SetAttr('op', TValue.From<string>(LOpStr));
        LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));  // left
        LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));  // right
        AParser.Expect('delimiter.rparen');
        Result := LNode;
      end
      // (if cond then [else])
      else if LOpKind = 'keyword.if' then
      begin
        AParser.Consume();  // consume 'if'
        LNode := AParser.CreateNode('expr.if');
        LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));  // condition
        LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));  // then
        if not AParser.Check('delimiter.rparen') then
          LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));  // else
        AParser.Expect('delimiter.rparen');
        Result := LNode;
      end
      // (begin expr...)
      else if LOpKind = 'keyword.begin' then
      begin
        AParser.Consume();  // consume 'begin'
        LNode := AParser.CreateNode('expr.begin');
        while not AParser.Check('delimiter.rparen') and
              not AParser.Check(PARSE_KIND_EOF) do
          LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));
        AParser.Expect('delimiter.rparen');
        Result := LNode;
      end
      // (set! name expr) — inside an expression context
      else if LOpKind = 'keyword.set' then
      begin
        AParser.Consume();  // consume 'set!'
        LNameTok := AParser.CurrentToken();
        LNode := AParser.CreateNode('expr.set', LNameTok);
        LNode.SetAttr('var.name', TValue.From<string>(LNameTok.Text));
        AParser.Consume();  // consume variable name
        LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));
        AParser.Expect('delimiter.rparen');
        Result := LNode;
      end
      // (display expr)
      else if LOpKind = 'keyword.display' then
      begin
        AParser.Consume();  // consume 'display'
        LNode := AParser.CreateNode('expr.display');
        LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));
        AParser.Expect('delimiter.rparen');
        Result := LNode;
      end
      // (newline)
      else if LOpKind = 'keyword.newline' then
      begin
        AParser.Consume();  // consume 'newline'
        LNode := AParser.CreateNode('expr.newline');
        AParser.Expect('delimiter.rparen');
        Result := LNode;
      end
      else
      begin
        // Function call expression: (name args...)
        LNameTok := AParser.CurrentToken();
        AParser.Consume();  // consume function name
        LNode := AParser.CreateNode('expr.call', LNameTok);
        LNode.SetAttr('call.name', TValue.From<string>(LNameTok.Text));
        LNode.SetAttr('call.cpp_name',
          TValue.From<string>(LParse.Config().MangleName(LNameTok.Text)));
        while not AParser.Check('delimiter.rparen') and
              not AParser.Check(PARSE_KIND_EOF) do
          LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));
        AParser.Expect('delimiter.rparen');
        Result := LNode;
      end;
    end
    else if AParser.Check(PARSE_KIND_IDENTIFIER) then
    begin
      LNode := AParser.CreateNode('expr.ident');
      AParser.Consume();
      Result := LNode;
    end
    else if AParser.Check(PARSE_KIND_INTEGER) then
    begin
      LNode := AParser.CreateNode('expr.integer');
      AParser.Consume();
      Result := LNode;
    end
    else if AParser.Check(PARSE_KIND_REAL) then
    begin
      LNode := AParser.CreateNode('expr.real');
      AParser.Consume();
      Result := LNode;
    end
    else if AParser.Check(PARSE_KIND_STRING) then
    begin
      LNode := AParser.CreateNode('expr.string');
      AParser.Consume();
      Result := LNode;
    end
    else if AParser.Check('keyword.true') then
    begin
      LNode := AParser.CreateNode('expr.bool');
      AParser.Consume();
      Result := LNode;
    end
    else if AParser.Check('keyword.false') then
    begin
      LNode := AParser.CreateNode('expr.bool');
      AParser.Consume();
      Result := LNode;
    end
    else
    begin
      // Unknown token — consume and return nil-safe empty node
      LNode := AParser.CreateNode('expr.integer');
      AParser.Consume();
      Result := LNode;
    end;
  end;

  try

    //=========================================================================
    // LEXER
    //=========================================================================
    LParse.Config()
      .CaseSensitiveKeywords(True)
      // Allow '!' as a valid identifier character so 'set!' scans as one token
      .IdentifierPart('a-zA-Z0-9_!-')
      // Keywords
      .AddKeyword('define',  'keyword.define')
      .AddKeyword('lambda',  'keyword.lambda')
      .AddKeyword('if',      'keyword.if')
      .AddKeyword('begin',   'keyword.begin')
      .AddKeyword('set!',    'keyword.set')
      .AddKeyword('let',     'keyword.let')
      .AddKeyword('and',     'keyword.and')
      .AddKeyword('or',      'keyword.or')
      .AddKeyword('not',     'keyword.not')
      .AddKeyword('display', 'keyword.display')
      .AddKeyword('newline', 'keyword.newline')
      .AddKeyword('cond',    'keyword.cond')
      .AddKeyword('else',    'keyword.else')
      // Operators / delimiters — longest-match first
      .AddOperator('#t',   'keyword.true')
      .AddOperator('#f',   'keyword.false')
      .AddOperator('<=', 'op.lte')
      .AddOperator('>=', 'op.gte')
      .AddOperator('(',  'delimiter.lparen')
      .AddOperator(')',  'delimiter.rparen')
      .AddOperator('+',  'op.plus')
      .AddOperator('-',  'op.minus')
      .AddOperator('*',  'op.multiply')
      .AddOperator('/',  'op.divide')
      .AddOperator('=',  'op.eq')
      .AddOperator('<',  'op.lt')
      .AddOperator('>',  'op.gt')
      // String: double-quoted with escape processing
      .AddStringStyle('"', '"', PARSE_KIND_STRING, True)
      // Line comment: ;
      .AddLineComment(';')
      // No statement terminator
      .SetStatementTerminator('')
      // Type inference surface
      .AddLiteralType('expr.integer', 'type.integer')
      .AddLiteralType('expr.real',    'type.double')
      .AddLiteralType('expr.string',  'type.string')
      .AddLiteralType('expr.bool',    'type.boolean')
      .AddDeclKind('expr.define_var')
      .AddCallKind('expr.call')
      .AddCallKind('expr.funcall')
      // Name mangler: kebab-case → underscores for C++
      .SetNameMangler(
        function(const AName: string): string
        var
          LI: Integer;
        begin
          Result := AName;
          for LI := 1 to Length(Result) do
            if Result[LI] = '-' then
              Result[LI] := '_';
        end);

    // ExprOverride: expr.bool — #t → true, #f → false
    LParse.Config().RegisterExprOverride('expr.bool',
      function(const ANode: TParseASTNodeBase;
        const ADefault: TParseExprToStringFunc): string
      begin
        if ANode.GetToken().Text = '#t' then
          Result := 'true'
        else
          Result := 'false';
      end);

    // ExprOverride: expr.call — use call.cpp_name attr (pre-mangled)
    LParse.Config().RegisterExprOverride('expr.call',
      function(const ANode: TParseASTNodeBase;
        const ADefault: TParseExprToStringFunc): string
      var
        LAttr: TValue;
        LName: string;
        LArgs: string;
        LI:    Integer;
      begin
        ANode.GetAttr('call.cpp_name', LAttr);
        LName := LAttr.AsString;
        LArgs := '';
        for LI := 0 to ANode.ChildCount() - 1 do
        begin
          if LI > 0 then
            LArgs := LArgs + ', ';
          LArgs := LArgs + ADefault(ANode.GetChild(LI));
        end;
        Result := LName + '(' + LArgs + ')';
      end);

    //=========================================================================
    // GRAMMAR — NO INFIX HANDLERS (Scheme is pure prefix)
    //=========================================================================

    // delimiter.lparen as statement — universal S-expression dispatch
    LParse.Config().RegisterStatement('delimiter.lparen', 'expr.funcall',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode:      TParseASTNode;
        LBodyNode:  TParseASTNode;
        LParamNode: TParseASTNode;
        LOpKind:    string;
        LNameTok:   TParseToken;
        LFuncTok:   TParseToken;
      begin
        AParser.Consume();  // consume '('
        LOpKind := AParser.CurrentToken().Kind;

        // (define ...)
        if LOpKind = 'keyword.define' then
        begin
          AParser.Consume();  // consume 'define'

          // (define (name params...) body...) — function definition
          if AParser.Check('delimiter.lparen') then
          begin
            AParser.Consume();  // consume '(' opening param list
            LFuncTok := AParser.CurrentToken();
            LNode := AParser.CreateNode('expr.define_func', LFuncTok);
            LNode.SetAttr('decl.name', TValue.From<string>(LFuncTok.Text));
            LNode.SetAttr('decl.cpp_name',
              TValue.From<string>(LParse.Config().MangleName(LFuncTok.Text)));
            AParser.Consume();  // consume function name identifier
            // Parse parameter list
            while not AParser.Check('delimiter.rparen') and
                  not AParser.Check(PARSE_KIND_EOF) do
            begin
              LParamNode := AParser.CreateNode('expr.param_decl',
                AParser.CurrentToken());
              AParser.Consume();  // consume param name
              LNode.AddChild(LParamNode);
            end;
            AParser.Expect('delimiter.rparen');  // closes param list
            // Parse body expressions
            LBodyNode := AParser.CreateNode('expr.func_body', LFuncTok);
            while not AParser.Check('delimiter.rparen') and
                  not AParser.Check(PARSE_KIND_EOF) do
              LBodyNode.AddChild(TParseASTNode(ParseSExpr(AParser)));
            LNode.AddChild(LBodyNode);
            AParser.Expect('delimiter.rparen');  // closes define form
            Result := LNode;
          end
          else
          begin
            // (define name expr) — variable definition
            LNameTok := AParser.CurrentToken();
            AParser.Consume();  // consume variable name
            LNode := AParser.CreateNode('expr.define_var', LNameTok);
            LNode.SetAttr('var.name', TValue.From<string>(LNameTok.Text));
            LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));
            AParser.Expect('delimiter.rparen');
            Result := LNode;
          end;
        end

        // (set! name expr)
        else if LOpKind = 'keyword.set' then
        begin
          AParser.Consume();  // consume 'set!'
          LNameTok := AParser.CurrentToken();
          LNode := AParser.CreateNode('expr.set', LNameTok);
          LNode.SetAttr('var.name', TValue.From<string>(LNameTok.Text));
          AParser.Consume();  // consume variable name
          LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));
          AParser.Expect('delimiter.rparen');
          Result := LNode;
        end

        // (if cond then [else])
        else if LOpKind = 'keyword.if' then
        begin
          AParser.Consume();  // consume 'if'
          LNode := AParser.CreateNode('expr.if');
          LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));  // condition
          LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));  // then
          if not AParser.Check('delimiter.rparen') then
            LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));  // else
          AParser.Expect('delimiter.rparen');
          Result := LNode;
        end

        // (begin expr...)
        else if LOpKind = 'keyword.begin' then
        begin
          AParser.Consume();  // consume 'begin'
          LNode := AParser.CreateNode('expr.begin');
          while not AParser.Check('delimiter.rparen') and
                not AParser.Check(PARSE_KIND_EOF) do
            LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));
          AParser.Expect('delimiter.rparen');
          Result := LNode;
        end

        // (display expr)
        else if LOpKind = 'keyword.display' then
        begin
          AParser.Consume();  // consume 'display'
          LNode := AParser.CreateNode('expr.display');
          LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));
          AParser.Expect('delimiter.rparen');
          Result := LNode;
        end

        // (newline)
        else if LOpKind = 'keyword.newline' then
        begin
          AParser.Consume();  // consume 'newline'
          LNode := AParser.CreateNode('expr.newline');
          AParser.Expect('delimiter.rparen');
          Result := LNode;
        end

        else
        begin
          // (funcname args...) — function call as statement
          LNameTok := AParser.CurrentToken();
          AParser.Consume();  // consume function name
          LNode := AParser.CreateNode('expr.funcall', LNameTok);
          LNode.SetAttr('call.name', TValue.From<string>(LNameTok.Text));
          LNode.SetAttr('call.cpp_name',
            TValue.From<string>(LParse.Config().MangleName(LNameTok.Text)));
          while not AParser.Check('delimiter.rparen') and
                not AParser.Check(PARSE_KIND_EOF) do
            LNode.AddChild(TParseASTNode(ParseSExpr(AParser)));
          AParser.Expect('delimiter.rparen');
          Result := LNode;
        end;
      end);

    //=========================================================================
    // SEMANTIC HANDLERS
    //=========================================================================

    // program.root — pre-scan, then analyze all children
    LParse.Config().RegisterSemanticRule('program.root',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        LParse.Config().ScanAll(ANode);
        ASem.PushScope('global', ANode.GetToken());
        ASem.VisitChildren(ANode);
        ASem.PopScope(ANode.GetToken());
      end);

    // expr.define_var — infer type from initializer, set storage, declare
    LParse.Config().RegisterSemanticRule('expr.define_var',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LTypeKind: string;
        LTypeAttr: TValue;
        LStorage:  string;
        LVarName:  string;
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

    // expr.define_func — declare, push scope, assign param types, infer return
    LParse.Config().RegisterSemanticRule('expr.define_func',
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
        // Assign param types from call-site data
        LParamIndex := 0;
        if LParse.Config().GetCallArgTypes().ContainsKey(LName) then
          LArgTypes := LParse.Config().GetCallArgTypes()[LName]
        else
          SetLength(LArgTypes, 0);
        for LI := 0 to ANode.ChildCount() - 2 do
        begin
          LChild := ANode.GetChild(LI);
          if LChild.GetNodeKind() <> 'expr.param_decl' then
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
        // Infer return type from body
        LBodyNode := ANode.GetChild(ANode.ChildCount() - 1);
        LReturnKind := LParse.Config().ScanReturnType(LBodyNode,
          ['expr.binary', 'expr.call', 'expr.integer', 'expr.real',
           'expr.string', 'expr.ident', 'expr.bool']);
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>(LReturnKind));
        // Declare function name as local return variable if not void
        if LReturnKind <> 'type.void' then
        begin
          LFuncTok    := ANode.GetToken();
          LResultNode := TParseASTNode.CreateNode('expr.define_var', LFuncTok);
          LResultNode.SetAttr(PARSE_ATTR_TYPE_KIND,
            TValue.From<string>(LReturnKind));
          LResultNode.SetAttr(PARSE_ATTR_STORAGE_CLASS,
            TValue.From<string>('local'));
          ASem.DeclareSymbol(LName, LResultNode);
        end;
        ASem.VisitNode(LBodyNode);
        ASem.PopScope(ANode.GetToken());
      end);

    // expr.param_decl — no-op; fully handled by expr.define_func
    LParse.Config().RegisterSemanticRule('expr.param_decl',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        // Intentionally empty — enriched by expr.define_func handler
      end);

    // expr.set — visit child, propagate type
    LParse.Config().RegisterSemanticRule('expr.set',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      var
        LTypeAttr: TValue;
      begin
        ASem.VisitChildren(ANode);
        if ANode.ChildCount() > 0 then
        begin
          if ANode.GetChild(0).GetAttr(PARSE_ATTR_TYPE_KIND, LTypeAttr) then
            TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND, LTypeAttr);
        end;
      end);

    // expr.if, expr.begin, expr.func_body — visit children
    LParse.Config().RegisterSemanticRule('expr.if',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    LParse.Config().RegisterSemanticRule('expr.begin',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    LParse.Config().RegisterSemanticRule('expr.func_body',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // expr.display, expr.newline, expr.funcall — visit children
    LParse.Config().RegisterSemanticRule('expr.display',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    LParse.Config().RegisterSemanticRule('expr.newline',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    LParse.Config().RegisterSemanticRule('expr.funcall',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // expr.binary, expr.call — visit children
    LParse.Config().RegisterSemanticRule('expr.binary',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

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

    // Literal type assignments
    LParse.Config().RegisterSemanticRule('expr.integer',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.integer'));
      end);

    LParse.Config().RegisterSemanticRule('expr.real',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.double'));
      end);

    LParse.Config().RegisterSemanticRule('expr.string',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.string'));
      end);

    LParse.Config().RegisterSemanticRule('expr.bool',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('type.boolean'));
      end);

    //=========================================================================
    // EMITTERS
    //=========================================================================

    // program.root — three-pass emit
    LParse.Config().RegisterEmitter('program.root',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LI:    Integer;
        LKind: string;
      begin
        // Header preamble
        AGen.EmitLine('#pragma once', sfHeader);
        AGen.Include('cstdint',  sfHeader);
        AGen.Include('iostream', sfHeader);
        AGen.Include('string',   sfHeader);

        // Pass 1: global variable declarations
        for LI := 0 to ANode.ChildCount() - 1 do
        begin
          LKind := ANode.GetChild(LI).GetNodeKind();
          if LKind = 'expr.define_var' then
            AGen.EmitNode(ANode.GetChild(LI));
        end;

        // Pass 2: function definitions (forward decls + full defs)
        for LI := 0 to ANode.ChildCount() - 1 do
        begin
          LKind := ANode.GetChild(LI).GetNodeKind();
          if LKind = 'expr.define_func' then
            AGen.EmitNode(ANode.GetChild(LI));
        end;

        // Pass 3: executable statements in main()
        AGen.Func('main', 'int');
        for LI := 0 to ANode.ChildCount() - 1 do
        begin
          LKind := ANode.GetChild(LI).GetNodeKind();
          if (LKind <> 'expr.define_var') and (LKind <> 'expr.define_func') then
            AGen.EmitNode(ANode.GetChild(LI));
        end;
        AGen.Return(AGen.Lit(0));
        AGen.EndFunc();
      end);

    // expr.define_var — emit global or local variable declaration
    LParse.Config().RegisterEmitter('expr.define_var',
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
        LVarName  := LParse.Config().MangleName(ANode.GetToken().Text);
        if LStorage = 'global' then
          AGen.Global(LVarName, LCppType, '')
        else
          AGen.DeclVar(LVarName, LCppType);
      end);

    // expr.define_func — forward decl to header, full definition to source
    LParse.Config().RegisterEmitter('expr.define_func',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LAttr:       TValue;
        LName:       string;
        LCppName:    string;
        LReturnKind: string;
        LCppReturn:  string;
        LParams:     string;
        LI:          Integer;
        LChild:      TParseASTNodeBase;
        LParamAttr:  TValue;
        LParamKind:  string;
        LCppType:    string;
        LParamName:  string;
        LIsVoid:     Boolean;
      begin
        ANode.GetAttr('decl.name', LAttr);
        LName := LAttr.AsString;
        ANode.GetAttr('decl.cpp_name', LAttr);
        LCppName := LAttr.AsString;
        ANode.GetAttr(PARSE_ATTR_TYPE_KIND, LAttr);
        LReturnKind := LAttr.AsString;
        LIsVoid     := LReturnKind = 'type.void';
        LCppReturn  := LParse.Config().TypeToIR(LReturnKind);
        // Build param string for forward declaration
        LParams := '';
        for LI := 0 to ANode.ChildCount() - 2 do
        begin
          LChild := ANode.GetChild(LI);
          if LChild.GetNodeKind() <> 'expr.param_decl' then
            Continue;
          LChild.GetAttr(PARSE_ATTR_TYPE_KIND, LParamAttr);
          LParamKind := LParamAttr.AsString;
          LCppType   := LParse.Config().TypeToIR(LParamKind);
          LParamName := LParse.Config().MangleName(LChild.GetToken().Text);
          if LParams <> '' then
            LParams := LParams + ', ';
          LParams := LParams + LCppType + ' ' + LParamName;
        end;
        // Forward declaration to header
        AGen.EmitLine(LCppReturn + ' ' + LCppName + '(' + LParams + ');',
          sfHeader);
        // Full definition to source
        AGen.Func(LCppName, LCppReturn);
        for LI := 0 to ANode.ChildCount() - 2 do
        begin
          LChild := ANode.GetChild(LI);
          if LChild.GetNodeKind() <> 'expr.param_decl' then
            Continue;
          LChild.GetAttr(PARSE_ATTR_TYPE_KIND, LParamAttr);
          LParamKind := LParamAttr.AsString;
          LCppType   := LParse.Config().TypeToIR(LParamKind);
          LParamName := LParse.Config().MangleName(LChild.GetToken().Text);
          AGen.Param(LParamName, LCppType);
        end;
        // Declare return variable if not void
        if not LIsVoid then
          AGen.DeclVar(LCppName, LCppReturn, '{}');
        AGen.SetContext('current_func', LCppName);
        // Emit body
        AGen.EmitNode(ANode.GetChild(ANode.ChildCount() - 1));
        if not LIsVoid then
          AGen.Return(AGen.Get(LCppName));
        AGen.EndFunc();
        AGen.SetContext('current_func', '');
      end);

    // expr.param_decl — no-op; handled by expr.define_func emitter
    LParse.Config().RegisterEmitter('expr.param_decl',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        // Intentionally empty
      end);

    // expr.func_body — emit children; last child becomes return assignment
    // when inside a non-void function (LCurrentFuncName is set).
    LParse.Config().RegisterEmitter('expr.func_body',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LI:        Integer;
        LLast:     TParseASTNodeBase;
        LLastKind: string;
        LIsValue:  Boolean;
      begin
        if (AGen.GetContext('current_func') <> '') and (ANode.ChildCount() > 0) then
        begin
          LLast     := ANode.GetChild(ANode.ChildCount() - 1);
          LLastKind := LLast.GetNodeKind();
          // A value expression as the last child is the implicit return
          LIsValue  := (LLastKind = 'expr.binary') or
                       (LLastKind = 'expr.call')   or
                       (LLastKind = 'expr.ident')  or
                       (LLastKind = 'expr.integer') or
                       (LLastKind = 'expr.real')    or
                       (LLastKind = 'expr.string')  or
                       (LLastKind = 'expr.bool');
          // Emit all children except last
          for LI := 0 to ANode.ChildCount() - 2 do
            AGen.EmitNode(ANode.GetChild(LI));
          // Assign last value expression to return variable
          if LIsValue then
            AGen.Assign(AGen.GetContext('current_func'), LParse.Config().ExprToString(LLast))
          else
            AGen.EmitNode(LLast);
        end
        else
          AGen.EmitChildren(ANode);
      end);

    // expr.set — emit assignment
    LParse.Config().RegisterEmitter('expr.set',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LAttr:    TValue;
        LVarName: string;
      begin
        ANode.GetAttr('var.name', LAttr);
        LVarName := LParse.Config().MangleName(LAttr.AsString);
        if ANode.ChildCount() > 0 then
          AGen.Assign(LVarName, LParse.Config().ExprToString(ANode.GetChild(0)));
      end);

    // expr.if — if/else structure
    LParse.Config().RegisterEmitter('expr.if',
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

    // expr.begin — emit all children (sequence)
    LParse.Config().RegisterEmitter('expr.begin',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        AGen.EmitChildren(ANode);
      end);

    // expr.display — individual std::cout statement
    LParse.Config().RegisterEmitter('expr.display',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        if ANode.ChildCount() > 0 then
          AGen.Stmt('std::cout << ' +
            LParse.Config().ExprToString(ANode.GetChild(0)) + ';');
      end);

    // expr.newline — std::cout newline statement
    LParse.Config().RegisterEmitter('expr.newline',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        AGen.Stmt('std::cout << "\n";');
      end);

    // expr.funcall — standalone function call statement
    LParse.Config().RegisterEmitter('expr.funcall',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LAttr:    TValue;
        LCppName: string;
        LArgs:    TArray<string>;
        LI:       Integer;
      begin
        ANode.GetAttr('call.cpp_name', LAttr);
        LCppName := LAttr.AsString;
        SetLength(LArgs, ANode.ChildCount());
        for LI := 0 to ANode.ChildCount() - 1 do
          LArgs[LI] := LParse.Config().ExprToString(ANode.GetChild(LI));
        AGen.Call(LCppName, LArgs);
      end);

    // expr.call as a statement — function call inside a body (parsed by ParseSExpr)
    // Shares the same emit logic as expr.funcall.
    LParse.Config().RegisterEmitter('expr.call',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      var
        LAttr:    TValue;
        LCppName: string;
        LArgs:    TArray<string>;
        LI:       Integer;
      begin
        ANode.GetAttr('call.cpp_name', LAttr);
        LCppName := LAttr.AsString;
        SetLength(LArgs, ANode.ChildCount());
        for LI := 0 to ANode.ChildCount() - 1 do
          LArgs[LI] := LParse.Config().ExprToString(ANode.GetChild(LI));
        AGen.Call(LCppName, LArgs);
      end);

    //=========================================================================
    // CONFIGURE & RUN
    //=========================================================================

    LParse.SetSourceFile('..\languages\src\HelloWorld.scm');
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
      TParseUtils.PrintLn(COLOR_RED + 'Scheme compilation failed.');
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
