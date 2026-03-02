{===============================================================================
  Parse()™ - Compiler Construction Toolkit
  ParseLang — .parse meta-language lexer configuration

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

(*
  ParseLang.Lexer — Lexer Configuration for the .parse Meta-Language

  Configures a TParse instance to tokenize .parse language definition files.
  Drives the TParseLangConfig lexer surface for the .parse language itself —
  distinct from the custom language that a .parse file defines.

  Token categories produced by this lexer:
    keyword.*     — reserved words listed in BNF Section 11 + grammar-derived
    op.*          — operators and punctuation
    delimiter.*   — structural punctuation (, ; : . ( ) [ ])
    literal.*     — string, integer, regex (/ ... /)
    identifier    — user-defined identifiers
    comment.line  — -- line comments
*)

unit ParseLang.Lexer;

{$I ..\src\Parse.Defines.inc}

interface

uses
  System.SysUtils,
  Parse;

procedure ConfigLexer(const AParse: TParse);

implementation

// =========================================================================
// KEYWORDS
// =========================================================================

procedure RegisterKeywords(const AParse: TParse);
begin
  // Case-insensitive: .parse keywords may be written in any case
  AParse.Config()
    .CaseSensitiveKeywords(False)
    // ---- File structure ----
    .AddKeyword('language',         'keyword.language')
    // ---- Lexer sections ----
    .AddKeyword('tokens',           'keyword.tokens')
    .AddKeyword('keywords',         'keyword.keywords')
    .AddKeyword('casesensitive',    'keyword.casesensitive')
    .AddKeyword('caseinsensitive',  'keyword.caseinsensitive')
    .AddKeyword('operators',        'keyword.operators')
    .AddKeyword('strings',          'keyword.strings')
    .AddKeyword('escape',           'keyword.escape')
    .AddKeyword('comments',         'keyword.comments')
    .AddKeyword('line',             'keyword.line')
    .AddKeyword('block',            'keyword.block')
    .AddKeyword('structural',       'keyword.structural')
    .AddKeyword('terminator',       'keyword.terminator')
    .AddKeyword('blockopen',        'keyword.blockopen')
    .AddKeyword('blockclose',       'keyword.blockclose')
    .AddKeyword('types',            'keyword.types')
    .AddKeyword('literals',         'keyword.literals')
    .AddKeyword('typemap',          'keyword.typemap')
    .AddKeyword('registerliterals', 'keyword.registerliterals')
    // ---- Grammar rules ----
    .AddKeyword('prefix',           'keyword.prefix')
    .AddKeyword('infix',            'keyword.infix')
    .AddKeyword('left',             'keyword.left')
    .AddKeyword('right',            'keyword.right')
    .AddKeyword('power',            'keyword.power')
    .AddKeyword('as',               'keyword.as')
    .AddKeyword('op',               'keyword.op')
    .AddKeyword('binaryop',         'keyword.binaryop')
    .AddKeyword('statement',        'keyword.statement')
    .AddKeyword('exproverride',     'keyword.exproverride')
    .AddKeyword('override',         'keyword.override')
    // ---- Semantic / emit / helper ----
    .AddKeyword('semantic',         'keyword.semantic')
    .AddKeyword('emit',             'keyword.emit')
    .AddKeyword('function',         'keyword.function')
    // ---- Parse sub-block delimiter ----
    .AddKeyword('parse',            'keyword.parse')
    .AddKeyword('end',              'keyword.end')
    // ---- Scripting language control flow ----
    .AddKeyword('if',               'keyword.if')
    .AddKeyword('then',             'keyword.then')
    .AddKeyword('else',             'keyword.else')
    .AddKeyword('while',            'keyword.while')
    .AddKeyword('do',               'keyword.do')
    .AddKeyword('for',              'keyword.for')
    .AddKeyword('in',               'keyword.in')
    .AddKeyword('repeat',           'keyword.repeat')
    .AddKeyword('until',            'keyword.until')
    // ---- Scripting language logical operators ----
    .AddKeyword('not',              'keyword.not')
    .AddKeyword('and',              'keyword.and')
    .AddKeyword('or',               'keyword.or')
    // ---- Scripting language literals ----
    .AddKeyword('nil',              'keyword.nil')
    .AddKeyword('true',             'keyword.true')
    .AddKeyword('false',            'keyword.false')
    // ---- Implicit return variable ----
    .AddKeyword('result',           'keyword.result')
    // ---- Type names used in function parameter declarations ----
    .AddKeyword('string',           'keyword.type_string')
    .AddKeyword('int',              'keyword.type_int')
    .AddKeyword('bool',             'keyword.type_bool')
    .AddKeyword('node',             'keyword.type_node')
    .AddKeyword('token',            'keyword.type_token');
end;

// =========================================================================
// OPERATORS AND DELIMITERS
// =========================================================================

procedure RegisterOperators(const AParse: TParse);
begin
  AParse.Config()
    // Multi-character operators first for longest-match priority
    .AddOperator(':=', 'op.assign')
    .AddOperator('->', 'op.arrow')
    .AddOperator('<>', 'op.neq')
    .AddOperator('<=', 'op.lte')
    .AddOperator('>=', 'op.gte')
    .AddOperator('..',  'op.range')
    // Single-character operators
    .AddOperator('~',  'op.tilde')
    .AddOperator('=',  'op.eq')
    .AddOperator('<',  'op.lt')
    .AddOperator('>',  'op.gt')
    .AddOperator('+',  'op.plus')
    .AddOperator('-',  'op.minus')
    .AddOperator('*',  'op.multiply')
    // Delimiters
    .AddOperator(';',  'delimiter.semicolon')
    .AddOperator(':',  'delimiter.colon')
    .AddOperator('.',  'delimiter.dot')
    .AddOperator(',',  'delimiter.comma')
    .AddOperator('(',  'delimiter.lparen')
    .AddOperator(')',  'delimiter.rparen')
    .AddOperator('[',  'delimiter.lbracket')
    .AddOperator(']',  'delimiter.rbracket');
end;

// =========================================================================
// STRING STYLES
// =========================================================================

procedure RegisterStringStyles(const AParse: TParse);
begin
  AParse.Config()
    // Single-quoted string literals for token kind strings, operator texts, etc.
    // AllowEscape = False: '' inside a string represents a literal single-quote
    .AddStringStyle('''', '''', PARSE_KIND_STRING, False)
    // Regex literals: /pattern/ — used in token declarations (TokenDecl)
    // AllowEscape = False: regex chars are taken literally inside the slashes
    .AddStringStyle('/', '/', 'literal.regex', False);
end;

// =========================================================================
// COMMENTS
// =========================================================================

procedure RegisterComments(const AParse: TParse);
begin
  // The .parse language uses Pascal-influenced -- line comments (BNF Section 10)
  AParse.Config()
    .AddLineComment('--');
end;

// =========================================================================
// STRUCTURAL TOKENS
// =========================================================================

procedure RegisterStructural(const AParse: TParse);
begin
  AParse.Config()
    // Statement terminator: semicolons end declarations inside lexer sections
    // and terminate binaryop rules, registerliterals, etc.
    .SetStatementTerminator('delimiter.semicolon')
    // Block open: 'parse' keyword opens parse sub-blocks inside rule bodies.
    // Handlers use GetBlockCloseKind() to detect end of any block.
    .SetBlockOpen('keyword.parse')
    // Block close: all .parse blocks close with 'end'
    .SetBlockClose('keyword.end');
end;

// =========================================================================
// PUBLIC ENTRY POINT
// =========================================================================

procedure ConfigLexer(const AParse: TParse);
begin
  RegisterKeywords(AParse);
  RegisterOperators(AParse);
  RegisterStringStyles(AParse);
  RegisterComments(AParse);
  RegisterStructural(AParse);
end;

end.
