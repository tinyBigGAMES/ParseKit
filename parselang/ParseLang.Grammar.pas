{===============================================================================
  Parse()™ - Compiler Construction Toolkit
  ParseLang — .parse meta-language grammar configuration

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

(*
  ParseLang.Grammar — Grammar Rules for the .parse Meta-Language

  Registers all statement, prefix, and infix handlers required to parse
  .parse language definition files. Produces a well-structured AST that the
  CodeGen phase walks to configure a new TParseLang instance in memory.

  AST Node Kinds Produced:
    program.root            — root node (children = all top-level constructs)
    stmt.language_decl      — language Name ;
    stmt.tokens_block       — tokens { TokenDecl } end
    stmt.token_decl         — Ident ~ /regex/ ;
    stmt.keywords_block     — keywords [case] { KeywordDecl } end
    stmt.keyword_decl       — 'text' -> 'kind' ;
    stmt.operators_block    — operators { OpDecl } end
    stmt.operator_decl      — 'text' -> 'kind' ;
    stmt.strings_block      — strings { StringStyleDecl } end
    stmt.string_style       — 'open' 'close' -> 'kind' [escape bool] ;
    stmt.comments_block     — comments { CommentDecl } end
    stmt.line_comment       — line 'prefix' ;
    stmt.block_comment      — block 'open' 'close' [-> 'kind'] ;
    stmt.structural_block   — structural terminator/blockopen/blockclose end
    stmt.types_block        — types { TypeKeywordDecl } end
    stmt.type_keyword       — 'text' -> 'kind' ;
    stmt.literals_block     — literals { LiteralTypeDecl } end
    stmt.literal_type       — 'kind' -> 'type' ;
    stmt.typemap_block      — typemap { TypeMapEntry } end
    stmt.typemap_entry      — 'typekind' -> 'cpptype' ;
    stmt.prefix_rule        — prefix 'tok' as 'node' parse ... end end
    stmt.infix_rule         — infix left/right 'tok' power N as 'node' parse ... end end
    stmt.statement_rule     — statement 'tok' as 'node' parse ... end end
    stmt.binaryop_rule      — binaryop 'tok' power N op 'cppop' ;
    stmt.registerliterals   — registerLiterals ;
    stmt.exproverride_rule  — exproverride 'tok' override ... end end
    stmt.semantic_rule      — semantic 'nodekind' ... end
    stmt.emit_rule          — emit 'nodekind' ... end
    stmt.helper_func        — function Name(params) [-> type] ... end
    stmt.func_param         — parameter node inside helper_func
    Scripting block nodes:
    stmt.block              — sequence of scripting statements (children = stmts)
    stmt.assign             — Ident := Expr ;
    stmt.if                 — if/else-if/else/end
    stmt.if_branch          — one if/else-if branch: condition + block
    stmt.else_branch        — else block (no condition)
    stmt.while              — while Expr do Block end
    stmt.for_in             — for Ident in Expr do Block end
    stmt.repeat             — repeat Block until Expr ;
    stmt.call_stmt          — Ident(args) ;
    Scripting expression nodes:
    expr.literal_int        — integer literal
    expr.literal_str        — string literal
    expr.literal_regex      — regex literal (from / ... /)
    expr.literal_bool       — true / false
    expr.literal_nil        — nil
    expr.ident              — identifier reference
    expr.field              — a.b
    expr.index              — a[b]
    expr.call               — Ident(args)
    expr.binary             — binary operator expression
    expr.unary              — unary not / minus / plus
    expr.grouped            — (expr)
*)

unit ParseLang.Grammar;

{$I ..\src\Parse.Defines.inc}

interface

uses
  System.SysUtils,
  Parse;

procedure ConfigGrammar(const AParse: TParse);

implementation

uses
  System.Rtti;

// =========================================================================
// SHARED BLOCK PARSING HELPER
// =========================================================================

// Parse a sequence of scripting statements until 'end' or EOF is reached.
// Used inside parse blocks, semantic blocks, emit blocks, and helper func bodies.
// Returns a stmt.block node whose children are the parsed statements.
function ParseBlock(const AParser: TParseParserBase): TParseASTNode;
var
  LBlock: TParseASTNode;
  LStmt:  TParseASTNode;
begin
  LBlock := AParser.CreateNode('stmt.block');
  // Keep parsing statements until we see 'end' (the block close keyword)
  while not AParser.Check('keyword.end') and
        not AParser.Check('keyword.else') and
        not AParser.Check('keyword.until') and
        not AParser.Check(PARSE_KIND_EOF) do
  begin
    LStmt := TParseASTNode(AParser.ParseStatement());
    if LStmt <> nil then
      LBlock.AddChild(LStmt);
  end;
  Result := LBlock;
end;

// =========================================================================
// PREFIX HANDLERS — EXPRESSION ATOMS
// =========================================================================

// --- Standard literals: identifier, integer, string ---

procedure RegisterLiteralPrefixes(const AParse: TParse);
begin
  // Integer literal
  AParse.Config().RegisterPrefix(PARSE_KIND_INTEGER, 'expr.literal_int',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();
      Result := LNode;
    end);

  // String literal (single-quoted)
  AParse.Config().RegisterPrefix(PARSE_KIND_STRING, 'expr.literal_str',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();
      Result := LNode;
    end);

  // Regex literal: /pattern/ — produced by the regex string style
  AParse.Config().RegisterPrefix('literal.regex', 'expr.literal_regex',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();
      Result := LNode;
    end);

  // Identifier — may be a variable reference, or the start of field/index/call
  AParse.Config().RegisterPrefix(PARSE_KIND_IDENTIFIER, 'expr.ident',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      LNode.SetAttr('ident.name', TValue.From<string>(AParser.CurrentToken().Text));
      AParser.Consume();
      Result := LNode;
    end);
end;

// --- Boolean literals ---

procedure RegisterBooleanLiterals(const AParse: TParse);
begin
  AParse.Config().RegisterPrefix('keyword.true', 'expr.literal_bool',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      LNode.SetAttr('bool.value', TValue.From<Boolean>(True));
      AParser.Consume();
      Result := LNode;
    end);

  AParse.Config().RegisterPrefix('keyword.false', 'expr.literal_bool',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      LNode.SetAttr('bool.value', TValue.From<Boolean>(False));
      AParser.Consume();
      Result := LNode;
    end);
end;

// --- Nil literal ---

procedure RegisterNilLiteral(const AParse: TParse);
begin
  AParse.Config().RegisterPrefix('keyword.nil', 'expr.literal_nil',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();
      Result := LNode;
    end);
end;

// --- result keyword as expression (implicit return variable) ---

procedure RegisterResultPrefix(const AParse: TParse);
begin
  AParse.Config().RegisterPrefix('keyword.result', 'expr.ident',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      LNode.SetAttr('ident.name', TValue.From<string>('result'));
      AParser.Consume();
      Result := LNode;
    end);
end;

// --- left / right keywords as expressions (implicit infix context variables) ---
// 'left' and 'right' are keywords for infix associativity declarations but also
// serve as implicit variable names inside infix parse blocks.

// Helper: register a single keyword token kind as an expr.ident prefix so that
// keywords that also serve as implicit scripting variable names can appear in
// expressions without a parse error.
procedure RegisterKeywordAsIdent(const AParse: TParse;
  const ATokenKind: string; const AIdentName: string);
begin
  AParse.Config().RegisterPrefix(ATokenKind, 'expr.ident',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      LNode.SetAttr('ident.name', TValue.From<string>(AIdentName));
      AParser.Consume();
      Result := LNode;
    end);
end;

procedure RegisterKeywordIdentPrefixes(const AParse: TParse);
begin
  // Infix associativity keywords reused as implicit infix-handler variables
  RegisterKeywordAsIdent(AParse, 'keyword.left',        'left');
  RegisterKeywordAsIdent(AParse, 'keyword.right',       'right');
  // Type annotation keywords reused as implicit scripting variable names:
  //   node   — the current AST node in semantic/emit blocks
  //   token  — token values accessed via node.token / current() etc.
  //   string, int, bool — used as plain variable names in scripting blocks
  RegisterKeywordAsIdent(AParse, 'keyword.type_node',   'node');
  RegisterKeywordAsIdent(AParse, 'keyword.type_token',  'token');
  RegisterKeywordAsIdent(AParse, 'keyword.type_string', 'string');
  RegisterKeywordAsIdent(AParse, 'keyword.type_int',    'int');
  RegisterKeywordAsIdent(AParse, 'keyword.type_bool',   'bool');
end;

// --- Grouped expression: ( expr ) ---

procedure RegisterGroupedExpr(const AParse: TParse);
begin
  AParse.Config().RegisterPrefix('delimiter.lparen', 'expr.grouped',
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
end;

// --- Unary not ---

procedure RegisterUnaryNot(const AParse: TParse);
begin
  AParse.Config().RegisterPrefix('keyword.not', 'expr.unary',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      LNode.SetAttr('op', TValue.From<string>('not'));
      AParser.Consume();  // consume 'not'
      // Power 50: not binds tightly to its operand
      LNode.AddChild(TParseASTNode(AParser.ParseExpression(50)));
      Result := LNode;
    end);
end;

// --- Unary minus (for negative integer literals) ---

procedure RegisterUnaryMinus(const AParse: TParse);
begin
  AParse.Config().RegisterPrefix('op.minus', 'expr.unary',
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
end;

// =========================================================================
// INFIX HANDLERS — OPERATORS AND POSTFIX FORMS
// =========================================================================

// --- Binary operators ---

procedure RegisterBinaryOps(const AParse: TParse);
begin
  // Comparison operators (power 10, left-associative)
  AParse.Config()
    .RegisterInfixLeft('op.eq',  10, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('='));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(10)));
        Result := LNode;
      end)
    .RegisterInfixLeft('op.neq', 10, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('<>'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(10)));
        Result := LNode;
      end)
    .RegisterInfixLeft('op.lt',  10, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('<'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(10)));
        Result := LNode;
      end)
    .RegisterInfixLeft('op.gt',  10, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('>'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(10)));
        Result := LNode;
      end)
    .RegisterInfixLeft('op.lte', 10, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('<='));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(10)));
        Result := LNode;
      end)
    .RegisterInfixLeft('op.gte', 10, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('>='));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(10)));
        Result := LNode;
      end);

  // Additive operators (power 20, left-associative)
  AParse.Config()
    .RegisterInfixLeft('op.plus',  20, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('+'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(20)));
        Result := LNode;
      end)
    .RegisterInfixLeft('op.minus', 20, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('-'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(20)));
        Result := LNode;
      end)
    .RegisterInfixLeft('keyword.or', 20, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('or'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(20)));
        Result := LNode;
      end);

  // Multiplicative operators (power 30, left-associative)
  AParse.Config()
    .RegisterInfixLeft('op.multiply', 30, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('*'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(30)));
        Result := LNode;
      end)
    .RegisterInfixLeft('keyword.and', 30, 'expr.binary',
      function(AParser: TParseParserBase;
        ALeft: TParseASTNodeBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        LNode.SetAttr('op', TValue.From<string>('and'));
        AParser.Consume();
        LNode.AddChild(TParseASTNode(ALeft));
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(30)));
        Result := LNode;
      end);
end;

// --- Field access: expr.field (a.b) ---

procedure RegisterFieldAccess(const AParse: TParse);
begin
  AParse.Config().RegisterInfixLeft('delimiter.dot', 80, 'expr.field',
    function(AParser: TParseParserBase;
      ALeft: TParseASTNodeBase): TParseASTNodeBase
    var
      LNode:     TParseASTNode;
      LFieldTok: TParseToken;
    begin
      AParser.Consume();  // consume '.'
      LFieldTok := AParser.CurrentToken();
      LNode     := AParser.CreateNode('expr.field', LFieldTok);
      LNode.SetAttr('field.name', TValue.From<string>(LFieldTok.Text));
      // Consume the field name (identifier or keyword used as field name)
      AParser.Consume();
      LNode.AddChild(TParseASTNode(ALeft));
      Result := LNode;
    end);
end;

// --- Array index: expr.index (a[b]) ---

procedure RegisterArrayIndex(const AParse: TParse);
begin
  AParse.Config().RegisterInfixLeft('delimiter.lbracket', 80, 'expr.index',
    function(AParser: TParseParserBase;
      ALeft: TParseASTNodeBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      AParser.Consume();  // consume '['
      LNode := AParser.CreateNode('expr.index');
      LNode.AddChild(TParseASTNode(ALeft));
      LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
      AParser.Expect('delimiter.rbracket');
      Result := LNode;
    end);
end;

// --- Function call expression: expr.call (f(args)) ---

procedure RegisterCallExpr(const AParse: TParse);
begin
  AParse.Config().RegisterInfixLeft('delimiter.lparen', 90, 'expr.call',
    function(AParser: TParseParserBase;
      ALeft: TParseASTNodeBase): TParseASTNodeBase
    var
      LNode:    TParseASTNode;
      LNameTok: TParseToken;
      LAttr:    TValue;
    begin
      // Get the function name from the left-hand expr.ident node
      LNameTok := ALeft.GetToken();
      ALeft.GetAttr('ident.name', LAttr);
      LNode := AParser.CreateNode('expr.call', LNameTok);
      LNode.SetAttr('call.name', LAttr);
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
end;

// =========================================================================
// SCRIPTING STATEMENT HANDLERS
// =========================================================================

// --- Assignment / call statement (dispatched on identifier) ---
// Handles both: Ident := Expr ;  and  Ident(args) ;
// Also handles: result := Expr ;  (result keyword as assignment target)

procedure RegisterIdentifierStatement(const AParse: TParse);
begin
  AParse.Config().RegisterStatement(PARSE_KIND_IDENTIFIER, 'stmt.assign',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNameTok: TParseToken;
      LName:    string;
      LNode:    TParseASTNode;
    begin
      LNameTok := AParser.CurrentToken();
      LName    := LNameTok.Text;
      AParser.Consume();  // consume identifier

      if AParser.Check('op.assign') then
      begin
        // Assignment: Ident := Expr ;
        LNode := AParser.CreateNode('stmt.assign', LNameTok);
        LNode.SetAttr('assign.target', TValue.From<string>(LName));
        AParser.Consume();  // consume ':='
        LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        AParser.Expect('delimiter.semicolon');
        Result := LNode;
      end
      else if AParser.Check('delimiter.lparen') then
      begin
        // Call statement: Ident(args) ;
        LNode := AParser.CreateNode('stmt.call_stmt', LNameTok);
        LNode.SetAttr('call.name', TValue.From<string>(LName));
        AParser.Consume();  // consume '('
        if not AParser.Check('delimiter.rparen') then
        begin
          LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
          while AParser.Match('delimiter.comma') do
            LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        end;
        AParser.Expect('delimiter.rparen');
        AParser.Expect('delimiter.semicolon');
        Result := LNode;
      end
      else
      begin
        // Unrecognised — produce an error node so parsing can continue
        LNode := AParser.CreateNode('stmt.error', LNameTok);
        LNode.SetAttr('error.text',
          TValue.From<string>('Expected := or ( after identifier ' + LName));
        Result := LNode;
      end;
    end);
end;

// --- result := Expr ;  (result is a keyword, needs its own statement handler) ---

procedure RegisterResultAssignment(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.result', 'stmt.assign',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNameTok: TParseToken;
      LNode:    TParseASTNode;
    begin
      LNameTok := AParser.CurrentToken();
      AParser.Consume();  // consume 'result'
      LNode := AParser.CreateNode('stmt.assign', LNameTok);
      LNode.SetAttr('assign.target', TValue.From<string>('result'));
      AParser.Expect('op.assign');
      LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
      AParser.Expect('delimiter.semicolon');
      Result := LNode;
    end);
end;

// --- if Expr then Block { else if Expr then Block } [ else Block ] end ---

procedure RegisterIfStatement(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.if', 'stmt.if',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:      TParseASTNode;
      LBranch:    TParseASTNode;
      LElseBr:    TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'if'

      // Primary if branch: stmt.if_branch holds [condition, block]
      LBranch := AParser.CreateNode('stmt.if_branch');
      LBranch.AddChild(TParseASTNode(AParser.ParseExpression(0)));
      AParser.Expect('keyword.then');
      LBranch.AddChild(ParseBlock(AParser));
      LNode.AddChild(LBranch);

      // Zero or more else-if branches
      while AParser.Check('keyword.else') and
            (AParser.PeekToken(1).Kind = 'keyword.if') do
      begin
        AParser.Consume();  // consume 'else'
        AParser.Consume();  // consume 'if'
        LBranch := AParser.CreateNode('stmt.if_branch');
        LBranch.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        AParser.Expect('keyword.then');
        LBranch.AddChild(ParseBlock(AParser));
        LNode.AddChild(LBranch);
      end;

      // Optional else block
      if AParser.Match('keyword.else') then
      begin
        LElseBr := AParser.CreateNode('stmt.else_branch');
        LElseBr.AddChild(ParseBlock(AParser));
        LNode.AddChild(LElseBr);
      end;

      AParser.Expect('keyword.end');
      Result := LNode;
    end);
end;

// --- while Expr do Block end ---

procedure RegisterWhileStatement(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.while', 'stmt.while',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'while'
      LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));  // condition
      AParser.Expect('keyword.do');
      LNode.AddChild(ParseBlock(AParser));  // body
      AParser.Expect('keyword.end');
      Result := LNode;
    end);
end;

// --- for Ident in Expr do Block end ---

procedure RegisterForInStatement(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.for', 'stmt.for_in',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:    TParseASTNode;
      LVarTok:  TParseToken;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'for'
      LVarTok := AParser.CurrentToken();
      LNode.SetAttr('for.var', TValue.From<string>(LVarTok.Text));
      AParser.Consume();  // consume loop variable identifier
      AParser.Expect('keyword.in');
      LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));  // range expr
      AParser.Expect('keyword.do');
      LNode.AddChild(ParseBlock(AParser));  // body
      AParser.Expect('keyword.end');
      Result := LNode;
    end);
end;

// --- repeat Block until Expr ; ---

procedure RegisterRepeatStatement(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.repeat', 'stmt.repeat',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:  TParseASTNode;
      LBlock: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'repeat'
      // Body: parse statements until 'until'
      LBlock := AParser.CreateNode('stmt.block');
      while not AParser.Check('keyword.until') and
            not AParser.Check(PARSE_KIND_EOF) do
      begin
        LBlock.AddChild(TParseASTNode(AParser.ParseStatement()));
      end;
      LNode.AddChild(LBlock);
      AParser.Expect('keyword.until');
      LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));  // condition
      AParser.Expect('delimiter.semicolon');
      Result := LNode;
    end);
end;

// =========================================================================
// TOP-LEVEL .PARSE FILE SECTION HANDLERS
// =========================================================================

// --- language Name ; ---

procedure RegisterLanguageDecl(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.language', 'stmt.language_decl',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'language'
      LNode.SetAttr('lang.name',
        TValue.From<string>(AParser.CurrentToken().Text));
      AParser.Consume();  // consume language name identifier
      AParser.Expect('delimiter.semicolon');
      Result := LNode;
    end);
end;

// --- tokens { Ident ~ /regex/ ; } end ---

procedure RegisterTokensBlock(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.tokens', 'stmt.tokens_block',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:     TParseASTNode;
      LDecl:     TParseASTNode;
      LNameTok:  TParseToken;
      LRegexTok: TParseToken;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'tokens'
      while not AParser.Check('keyword.end') and
            not AParser.Check(PARSE_KIND_EOF) do
      begin
        // TokenDecl = Ident ~ /regex/ ;
        LNameTok := AParser.CurrentToken();
        LDecl    := AParser.CreateNode('stmt.token_decl', LNameTok);
        LDecl.SetAttr('token.name', TValue.From<string>(LNameTok.Text));
        AParser.Consume();   // consume token name identifier
        AParser.Expect('op.tilde');
        LRegexTok := AParser.CurrentToken();
        LDecl.SetAttr('token.regex', TValue.From<string>(LRegexTok.Text));
        AParser.Consume();   // consume regex literal
        AParser.Expect('delimiter.semicolon');
        LNode.AddChild(LDecl);
      end;
      AParser.Expect('keyword.end');
      Result := LNode;
    end);
end;

// --- keywords [casesensitive | caseinsensitive] { 'text' -> 'kind' ; } end ---

procedure RegisterKeywordsBlock(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.keywords', 'stmt.keywords_block',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:    TParseASTNode;
      LDecl:    TParseASTNode;
      LTextTok: TParseToken;
      LCase:    string;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'keywords'
      // Optional case-sensitivity modifier
      LCase := 'caseinsensitive';
      if AParser.Check('keyword.casesensitive') then
      begin
        LCase := 'casesensitive';
        AParser.Consume();
      end
      else if AParser.Check('keyword.caseinsensitive') then
      begin
        LCase := 'caseinsensitive';
        AParser.Consume();
      end;
      LNode.SetAttr('keywords.case', TValue.From<string>(LCase));
      while not AParser.Check('keyword.end') and
            not AParser.Check(PARSE_KIND_EOF) do
      begin
        // KeywordDecl = 'text' -> 'kind' ;
        LTextTok := AParser.CurrentToken();
        LDecl    := AParser.CreateNode('stmt.keyword_decl', LTextTok);
        LDecl.SetAttr('keyword.text', TValue.From<string>(LTextTok.Text));
        AParser.Consume();   // consume text string
        AParser.Expect('op.arrow');
        LDecl.SetAttr('keyword.kind',
          TValue.From<string>(AParser.CurrentToken().Text));
        AParser.Consume();   // consume kind string
        AParser.Expect('delimiter.semicolon');
        LNode.AddChild(LDecl);
      end;
      AParser.Expect('keyword.end');
      Result := LNode;
    end);
end;

// --- operators { 'text' -> 'kind' ; } end ---

procedure RegisterOperatorsBlock(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.operators', 'stmt.operators_block',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:    TParseASTNode;
      LDecl:    TParseASTNode;
      LTextTok: TParseToken;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'operators'
      while not AParser.Check('keyword.end') and
            not AParser.Check(PARSE_KIND_EOF) do
      begin
        LTextTok := AParser.CurrentToken();
        LDecl    := AParser.CreateNode('stmt.operator_decl', LTextTok);
        LDecl.SetAttr('operator.text', TValue.From<string>(LTextTok.Text));
        AParser.Consume();
        AParser.Expect('op.arrow');
        LDecl.SetAttr('operator.kind',
          TValue.From<string>(AParser.CurrentToken().Text));
        AParser.Consume();
        AParser.Expect('delimiter.semicolon');
        LNode.AddChild(LDecl);
      end;
      AParser.Expect('keyword.end');
      Result := LNode;
    end);
end;

// --- strings { 'open' 'close' -> 'kind' [ escape bool ] ; } end ---

procedure RegisterStringsBlock(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.strings', 'stmt.strings_block',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:    TParseASTNode;
      LDecl:    TParseASTNode;
      LOpenTok: TParseToken;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'strings'
      while not AParser.Check('keyword.end') and
            not AParser.Check(PARSE_KIND_EOF) do
      begin
        LOpenTok := AParser.CurrentToken();
        LDecl    := AParser.CreateNode('stmt.string_style', LOpenTok);
        LDecl.SetAttr('style.open', TValue.From<string>(LOpenTok.Text));
        AParser.Consume();
        LDecl.SetAttr('style.close',
          TValue.From<string>(AParser.CurrentToken().Text));
        AParser.Consume();
        AParser.Expect('op.arrow');
        LDecl.SetAttr('style.kind',
          TValue.From<string>(AParser.CurrentToken().Text));
        AParser.Consume();
        // Optional escape modifier
        if AParser.Match('keyword.escape') then
        begin
          LDecl.SetAttr('style.escape',
            TValue.From<Boolean>(AParser.CurrentToken().Kind = 'keyword.true'));
          AParser.Consume();  // consume true/false
        end
        else
          LDecl.SetAttr('style.escape', TValue.From<Boolean>(True));
        AParser.Expect('delimiter.semicolon');
        LNode.AddChild(LDecl);
      end;
      AParser.Expect('keyword.end');
      Result := LNode;
    end);
end;

// --- comments { line 'prefix' ; | block 'open' 'close' [-> 'kind'] ; } end ---

procedure RegisterCommentsBlock(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.comments', 'stmt.comments_block',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:    TParseASTNode;
      LDecl:    TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'comments'
      while not AParser.Check('keyword.end') and
            not AParser.Check(PARSE_KIND_EOF) do
      begin
        if AParser.Match('keyword.line') then
        begin
          // line 'prefix' ;
          LDecl := AParser.CreateNode('stmt.line_comment');
          LDecl.SetAttr('comment.prefix',
            TValue.From<string>(AParser.CurrentToken().Text));
          AParser.Consume();
          AParser.Expect('delimiter.semicolon');
          LNode.AddChild(LDecl);
        end
        else if AParser.Match('keyword.block') then
        begin
          // block 'open' 'close' [ -> 'kind' ] ;
          LDecl := AParser.CreateNode('stmt.block_comment');
          LDecl.SetAttr('comment.open',
            TValue.From<string>(AParser.CurrentToken().Text));
          AParser.Consume();
          LDecl.SetAttr('comment.close',
            TValue.From<string>(AParser.CurrentToken().Text));
          AParser.Consume();
          if AParser.Match('op.arrow') then
          begin
            LDecl.SetAttr('comment.kind',
              TValue.From<string>(AParser.CurrentToken().Text));
            AParser.Consume();
          end
          else
            LDecl.SetAttr('comment.kind', TValue.From<string>(''));
          AParser.Expect('delimiter.semicolon');
          LNode.AddChild(LDecl);
        end
        else
          Break;
      end;
      AParser.Expect('keyword.end');
      Result := LNode;
    end);
end;

// --- structural terminator 'kind' ; blockopen 'kind' ; blockclose 'kind' ; end ---

procedure RegisterStructuralBlock(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.structural', 'stmt.structural_block',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'structural'
      while not AParser.Check('keyword.end') and
            not AParser.Check(PARSE_KIND_EOF) do
      begin
        if AParser.Match('keyword.terminator') then
        begin
          LNode.SetAttr('structural.terminator',
            TValue.From<string>(AParser.CurrentToken().Text));
          AParser.Consume();
          AParser.Expect('delimiter.semicolon');
        end
        else if AParser.Match('keyword.blockopen') then
        begin
          LNode.SetAttr('structural.blockopen',
            TValue.From<string>(AParser.CurrentToken().Text));
          AParser.Consume();
          AParser.Expect('delimiter.semicolon');
        end
        else if AParser.Match('keyword.blockclose') then
        begin
          LNode.SetAttr('structural.blockclose',
            TValue.From<string>(AParser.CurrentToken().Text));
          AParser.Consume();
          AParser.Expect('delimiter.semicolon');
        end
        else
          Break;
      end;
      AParser.Expect('keyword.end');
      Result := LNode;
    end);
end;

// --- types { 'text' -> 'kind' ; } end ---

procedure RegisterTypesBlock(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.types', 'stmt.types_block',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:    TParseASTNode;
      LDecl:    TParseASTNode;
      LTextTok: TParseToken;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'types'
      while not AParser.Check('keyword.end') and
            not AParser.Check(PARSE_KIND_EOF) do
      begin
        LTextTok := AParser.CurrentToken();
        LDecl    := AParser.CreateNode('stmt.type_keyword', LTextTok);
        LDecl.SetAttr('typekw.text', TValue.From<string>(LTextTok.Text));
        AParser.Consume();
        AParser.Expect('op.arrow');
        LDecl.SetAttr('typekw.kind',
          TValue.From<string>(AParser.CurrentToken().Text));
        AParser.Consume();
        AParser.Expect('delimiter.semicolon');
        LNode.AddChild(LDecl);
      end;
      AParser.Expect('keyword.end');
      Result := LNode;
    end);
end;

// --- literals { 'nodekind' -> 'typekind' ; } end ---

procedure RegisterLiteralsBlock(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.literals', 'stmt.literals_block',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:    TParseASTNode;
      LDecl:    TParseASTNode;
      LKindTok: TParseToken;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'literals'
      while not AParser.Check('keyword.end') and
            not AParser.Check(PARSE_KIND_EOF) do
      begin
        LKindTok := AParser.CurrentToken();
        LDecl    := AParser.CreateNode('stmt.literal_type', LKindTok);
        LDecl.SetAttr('littype.node_kind', TValue.From<string>(LKindTok.Text));
        AParser.Consume();
        AParser.Expect('op.arrow');
        LDecl.SetAttr('littype.type_kind',
          TValue.From<string>(AParser.CurrentToken().Text));
        AParser.Consume();
        AParser.Expect('delimiter.semicolon');
        LNode.AddChild(LDecl);
      end;
      AParser.Expect('keyword.end');
      Result := LNode;
    end);
end;

// --- typemap { 'typekind' -> 'cpptype' ; } end ---

procedure RegisterTypeMapBlock(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.typemap', 'stmt.typemap_block',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:    TParseASTNode;
      LEntry:   TParseASTNode;
      LKindTok: TParseToken;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'typemap'
      while not AParser.Check('keyword.end') and
            not AParser.Check(PARSE_KIND_EOF) do
      begin
        LKindTok := AParser.CurrentToken();
        LEntry   := AParser.CreateNode('stmt.typemap_entry', LKindTok);
        LEntry.SetAttr('tmap.type_kind', TValue.From<string>(LKindTok.Text));
        AParser.Consume();
        AParser.Expect('op.arrow');
        LEntry.SetAttr('tmap.cpp_type',
          TValue.From<string>(AParser.CurrentToken().Text));
        AParser.Consume();
        AParser.Expect('delimiter.semicolon');
        LNode.AddChild(LEntry);
      end;
      AParser.Expect('keyword.end');
      Result := LNode;
    end);
end;

// --- registerLiterals ; ---

procedure RegisterLiteralsRule(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.registerliterals',
    'stmt.registerliterals',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'registerLiterals'
      AParser.Expect('delimiter.semicolon');
      Result := LNode;
    end);
end;

// --- binaryop 'tok' power N op 'cppop' ; ---

procedure RegisterBinaryOpRule(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.binaryop', 'stmt.binaryop_rule',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:     TParseASTNode;
      LTokKind:  string;
      LPower:    string;
      LCppOp:    string;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'binaryop'
      LTokKind := AParser.CurrentToken().Text;
      LNode.SetAttr('binop.token_kind', TValue.From<string>(LTokKind));
      AParser.Consume();  // consume token kind string
      AParser.Expect('keyword.power');
      LPower := AParser.CurrentToken().Text;
      LNode.SetAttr('binop.power', TValue.From<string>(LPower));
      AParser.Consume();  // consume power integer
      AParser.Expect('keyword.op');
      LCppOp := AParser.CurrentToken().Text;
      LNode.SetAttr('binop.cpp_op', TValue.From<string>(LCppOp));
      AParser.Consume();  // consume C++ operator string
      AParser.Expect('delimiter.semicolon');
      Result := LNode;
    end);
end;

// --- prefix 'tok' as 'node' parse ... end end ---

procedure RegisterPrefixRule(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.prefix', 'stmt.prefix_rule',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:     TParseASTNode;
      LTokKind:  string;
      LNodeKind: string;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'prefix'
      LTokKind := AParser.CurrentToken().Text;
      LNode.SetAttr('rule.token_kind', TValue.From<string>(LTokKind));
      AParser.Consume();  // consume token kind string
      AParser.Expect('keyword.as');
      LNodeKind := AParser.CurrentToken().Text;
      LNode.SetAttr('rule.node_kind', TValue.From<string>(LNodeKind));
      AParser.Consume();  // consume node kind string
      // parse ... end (ParseBlock)
      AParser.Expect('keyword.parse');
      LNode.AddChild(ParseBlock(AParser));
      AParser.Expect('keyword.end');  // closes ParseBlock
      AParser.Expect('keyword.end');  // closes PrefixRule
      Result := LNode;
    end);
end;

// --- infix left|right 'tok' power N as 'node' parse ... end end ---

procedure RegisterInfixRule(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.infix', 'stmt.infix_rule',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:     TParseASTNode;
      LAssoc:    string;
      LTokKind:  string;
      LPower:    string;
      LNodeKind: string;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'infix'
      // Associativity
      if AParser.Check('keyword.left') then
        LAssoc := 'left'
      else
        LAssoc := 'right';
      AParser.Consume();  // consume left/right
      LNode.SetAttr('rule.assoc', TValue.From<string>(LAssoc));
      LTokKind := AParser.CurrentToken().Text;
      LNode.SetAttr('rule.token_kind', TValue.From<string>(LTokKind));
      AParser.Consume();  // consume token kind string
      AParser.Expect('keyword.power');
      LPower := AParser.CurrentToken().Text;
      LNode.SetAttr('rule.power', TValue.From<string>(LPower));
      AParser.Consume();  // consume power integer
      AParser.Expect('keyword.as');
      LNodeKind := AParser.CurrentToken().Text;
      LNode.SetAttr('rule.node_kind', TValue.From<string>(LNodeKind));
      AParser.Consume();  // consume node kind string
      // parse ... end (ParseBlock)
      AParser.Expect('keyword.parse');
      LNode.AddChild(ParseBlock(AParser));
      AParser.Expect('keyword.end');  // closes ParseBlock
      AParser.Expect('keyword.end');  // closes InfixRule
      Result := LNode;
    end);
end;

// --- statement 'tok' as 'node' parse ... end end ---

procedure RegisterStatementRule(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.statement', 'stmt.statement_rule',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:     TParseASTNode;
      LTokKind:  string;
      LNodeKind: string;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'statement'
      LTokKind := AParser.CurrentToken().Text;
      LNode.SetAttr('rule.token_kind', TValue.From<string>(LTokKind));
      AParser.Consume();  // consume token kind string
      AParser.Expect('keyword.as');
      LNodeKind := AParser.CurrentToken().Text;
      LNode.SetAttr('rule.node_kind', TValue.From<string>(LNodeKind));
      AParser.Consume();  // consume node kind string
      // parse ... end (ParseBlock)
      AParser.Expect('keyword.parse');
      LNode.AddChild(ParseBlock(AParser));
      AParser.Expect('keyword.end');  // closes ParseBlock
      AParser.Expect('keyword.end');  // closes StatementRule
      Result := LNode;
    end);
end;

// --- exproverride 'tok' override ... end end ---

procedure RegisterExprOverrideRule(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.exproverride',
    'stmt.exproverride_rule',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:    TParseASTNode;
      LTokKind: string;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'exproverride'
      LTokKind := AParser.CurrentToken().Text;
      LNode.SetAttr('rule.token_kind', TValue.From<string>(LTokKind));
      AParser.Consume();  // consume token kind string
      // override ... end (the override sub-block)
      AParser.Expect('keyword.override');
      LNode.AddChild(ParseBlock(AParser));
      AParser.Expect('keyword.end');  // closes override block
      AParser.Expect('keyword.end');  // closes exproverride rule
      Result := LNode;
    end);
end;

// --- semantic 'nodekind' ... end ---

procedure RegisterSemanticRule(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.semantic', 'stmt.semantic_rule',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:     TParseASTNode;
      LNodeKind: string;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'semantic'
      LNodeKind := AParser.CurrentToken().Text;
      LNode.SetAttr('rule.node_kind', TValue.From<string>(LNodeKind));
      AParser.Consume();  // consume node kind string
      LNode.AddChild(ParseBlock(AParser));
      AParser.Expect('keyword.end');
      Result := LNode;
    end);
end;

// --- emit 'nodekind' ... end ---

procedure RegisterEmitRule(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.emit', 'stmt.emit_rule',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:     TParseASTNode;
      LNodeKind: string;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'emit'
      LNodeKind := AParser.CurrentToken().Text;
      LNode.SetAttr('rule.node_kind', TValue.From<string>(LNodeKind));
      AParser.Consume();  // consume node kind string
      LNode.AddChild(ParseBlock(AParser));
      AParser.Expect('keyword.end');
      Result := LNode;
    end);
end;

// --- function Name(params) [-> type] ... end ---

procedure RegisterHelperFunc(const AParse: TParse);
begin
  AParse.Config().RegisterStatement('keyword.function', 'stmt.helper_func',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode:      TParseASTNode;
      LParam:     TParseASTNode;
      LFuncName:  string;
      LParamName: string;
      LTypeName:  string;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();  // consume 'function'
      LFuncName := AParser.CurrentToken().Text;
      LNode.SetAttr('func.name', TValue.From<string>(LFuncName));
      AParser.Consume();  // consume function name
      AParser.Expect('delimiter.lparen');
      // Parameter list
      if not AParser.Check('delimiter.rparen') then
      begin
        repeat
          LParamName := AParser.CurrentToken().Text;
          AParser.Consume();  // consume param name
          AParser.Expect('delimiter.colon');
          LTypeName := AParser.CurrentToken().Text;
          AParser.Consume();  // consume type name
          LParam := AParser.CreateNode('stmt.func_param');
          LParam.SetAttr('param.name', TValue.From<string>(LParamName));
          LParam.SetAttr('param.type', TValue.From<string>(LTypeName));
          LNode.AddChild(LParam);
        until not AParser.Match('delimiter.comma');
      end;
      AParser.Expect('delimiter.rparen');
      // Optional return type
      if AParser.Match('op.arrow') then
      begin
        LTypeName := AParser.CurrentToken().Text;
        LNode.SetAttr('func.return_type', TValue.From<string>(LTypeName));
        AParser.Consume();  // consume return type
      end
      else
        LNode.SetAttr('func.return_type', TValue.From<string>(''));
      LNode.AddChild(ParseBlock(AParser));
      AParser.Expect('keyword.end');
      Result := LNode;
    end);
end;

// =========================================================================
// PUBLIC ENTRY POINT
// =========================================================================

procedure ConfigGrammar(const AParse: TParse);
begin
  // ---- Expression prefix handlers ----
  RegisterLiteralPrefixes(AParse);
  RegisterBooleanLiterals(AParse);
  RegisterNilLiteral(AParse);
  RegisterResultPrefix(AParse);
  RegisterKeywordIdentPrefixes(AParse);
  RegisterGroupedExpr(AParse);
  RegisterUnaryNot(AParse);
  RegisterUnaryMinus(AParse);

  // ---- Expression infix handlers ----
  RegisterBinaryOps(AParse);
  RegisterFieldAccess(AParse);
  RegisterArrayIndex(AParse);
  RegisterCallExpr(AParse);

  // ---- Scripting statement handlers ----
  RegisterIdentifierStatement(AParse);
  RegisterResultAssignment(AParse);
  RegisterIfStatement(AParse);
  RegisterWhileStatement(AParse);
  RegisterForInStatement(AParse);
  RegisterRepeatStatement(AParse);

  // ---- Lexer section handlers ----
  RegisterLanguageDecl(AParse);
  RegisterTokensBlock(AParse);
  RegisterKeywordsBlock(AParse);
  RegisterOperatorsBlock(AParse);
  RegisterStringsBlock(AParse);
  RegisterCommentsBlock(AParse);
  RegisterStructuralBlock(AParse);
  RegisterTypesBlock(AParse);
  RegisterLiteralsBlock(AParse);
  RegisterTypeMapBlock(AParse);

  // ---- Grammar rule handlers ----
  RegisterLiteralsRule(AParse);
  RegisterBinaryOpRule(AParse);
  RegisterPrefixRule(AParse);
  RegisterInfixRule(AParse);
  RegisterStatementRule(AParse);
  RegisterExprOverrideRule(AParse);

  // ---- Semantic / emit / helper handlers ----
  RegisterSemanticRule(AParse);
  RegisterEmitRule(AParse);
  RegisterHelperFunc(AParse);
end;

end.
