{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

unit Parse.LangConfig;

{$I Parse.Defines.inc}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Rtti,
  Parse.Utils,
  Parse.Config,
  Parse.Common;

type

  { TParseInfixEntry }
  TParseInfixEntry = record
    NodeKind:     string;
    BindingPower: Integer;
    Assoc:        TParseAssociativity;
    Handler:      TParseInfixHandler;
  end;

  { TParseStatementEntry }
  TParseStatementEntry = record
    NodeKind: string;
    Handler:  TParseStatementHandler;
  end;

  { TParsePrefixEntry }
  TParsePrefixEntry = record
    NodeKind: string;
    Handler:  TParsePrefixHandler;
  end;

  { TParseStructuralConfig }
  TParseStructuralConfig = record
    StatementTerminator: string;
    BlockOpen:           string;
    BlockClose:          string;
  end;

  // Name mangling: maps a source identifier to a C++ identifier.
  TParseNameMangler = reference to function(const AName: string): string;

  // Type-to-IR mapping: maps a type kind string to a C++ type string.
  TParseTypeToIR    = reference to function(const ATypeKind: string): string;

  { TParseLangConfig }
  TParseLangConfig = class(TParseConfigFileObject)
  private
    // Lexer surface
    FCaseSensitive:    Boolean;
    FIdentStartChars:  TSysCharSet;
    FIdentPartChars:   TSysCharSet;
    FLineComments:     TList<string>;
    FBlockComments:    TList<TParseBlockCommentDef>;
    FStringStyles:     TList<TParseStringStyleDef>;
    FOperators:        TList<TParseOperatorDef>;
    FKeywords:         TDictionary<string, string>;
    FHexPrefixes:      TList<string>;
    FBinaryPrefixes:   TList<string>;
    FHexKind:          string;
    FBinaryKind:       string;
    FIntegerKind:      string;
    FRealKind:         string;
    FIdentifierKind:   string;
    FEOFKind:          string;
    FUnknownKind:      string;
    FLineCommentKind:  string;
    FBlockCommentKind: string;
    FDirectivePrefix:  string;
    FDirectiveKind:    string;

    // Grammar surface
    FStatementHandlers: TDictionary<string, TParseStatementEntry>;
    FPrefixHandlers:    TDictionary<string, TParsePrefixEntry>;
    FInfixHandlers:     TDictionary<string, TParseInfixEntry>;
    FStructural:        TParseStructuralConfig;

    // Emit surface
    FEmitHandlers: TDictionary<string, TParseEmitHandler>;

    // Semantic surface
    FSemanticHandlers: TDictionary<string, TParseSemanticHandler>;
    FTypeCompatFunc:   TParseTypeCompatFunc;

    // Type inference surface
    FLiteralTypes: TDictionary<string, string>;   // node kind → type kind
    FDeclKinds:    TList<string>;                 // node kinds that declare vars
    FCallKinds:    TList<string>;                 // node kinds that are call sites
    FCallNameAttr: string;                        // attr holding callee name
    FTypeKeywords: TDictionary<string, string>;   // type keyword text → type kind

    // Post-scan results — cleared and repopulated each ScanAll call
    FDeclTypes:    TDictionary<string, string>;           // var name → type kind
    FCallArgTypes: TDictionary<string, TArray<string>>;   // func name → arg types

    // Name mangling and type mapping
    FNameMangler: TParseNameMangler;
    FTypeToIR:    TParseTypeToIR;

    // ExprToString overrides: node kind → override handler
    FExprOverrides: TDictionary<string, TParseExprOverride>;

    // Parse a character-class pattern like 'a-zA-Z_' into a TSysCharSet
    procedure ParseCharSet(const APattern: string; out ASet: TSysCharSet);

    // Re-sort operators longest-first after each addition
    procedure SortOperators();

    // Reset all data back to construction defaults
    procedure ResetToDefaults();

    // Convert a TSysCharSet back to a compact range-notation pattern string
    function CharSetToPattern(const ASet: TSysCharSet): string;

  protected
    procedure DoLoadConfig(const AConfig: TParseConfig); override;
    procedure DoSaveConfig(const AConfig: TParseConfig); override;

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Lexer surface — fluent

    // Whether keyword lookup is case-sensitive (default: false)
    function CaseSensitiveKeywords(const AValue: Boolean): TParseLangConfig;

    // Character classes for identifiers, using range notation e.g. 'a-zA-Z_'
    function IdentifierStart(const AChars: string): TParseLangConfig;
    function IdentifierPart(const AChars: string): TParseLangConfig;

    // Comment styles
    function AddLineComment(const APrefix: string): TParseLangConfig;
    function AddBlockComment(const AOpen, AClose: string): TParseLangConfig;

    // String literal styles; AAllowEscape controls backslash escape processing
    function AddStringStyle(const AOpen, AClose, AKind: string;
      const AAllowEscape: Boolean = True): TParseLangConfig;

    // Keywords: text → kind string, e.g. 'begin' → 'keyword.begin'
    function AddKeyword(const AText, AKind: string): TParseLangConfig;

    // Operators/delimiters: text → kind string; longest-match is automatic
    function AddOperator(const AText, AKind: string): TParseLangConfig;

    // Number literal prefixes
    function SetHexPrefix(const APrefix, AKind: string): TParseLangConfig;
    function SetBinaryPrefix(const APrefix, AKind: string): TParseLangConfig;

    // Directive prefix (e.g. '$' for '$ifdef')
    function SetDirectivePrefix(const APrefix, AKind: string): TParseLangConfig;

    // Override default kind strings for built-in token categories
    function SetIntegerKind(const AKind: string): TParseLangConfig;
    function SetRealKind(const AKind: string): TParseLangConfig;
    function SetIdentifierKind(const AKind: string): TParseLangConfig;

    // Grammar surface — fluent

    // Register a statement handler — ANodeKind is the AST node kind the handler produces
    function RegisterStatement(const AKind, ANodeKind: string;
      const AHandler: TParseStatementHandler): TParseLangConfig;

    // Register a prefix expression handler — ANodeKind is the AST node kind produced
    function RegisterPrefix(const AKind, ANodeKind: string;
      const AHandler: TParsePrefixHandler): TParseLangConfig;

    // Register a left-associative infix operator — ANodeKind is the AST node kind produced
    function RegisterInfixLeft(const AKind: string;
      const ABindingPower: Integer; const ANodeKind: string;
      const AHandler: TParseInfixHandler): TParseLangConfig;

    // Register a right-associative infix operator — ANodeKind is the AST node kind produced
    function RegisterInfixRight(const AKind: string;
      const ABindingPower: Integer; const ANodeKind: string;
      const AHandler: TParseInfixHandler): TParseLangConfig;

    // Structural tokens the parser engine itself needs to operate
    function SetStatementTerminator(const AKind: string): TParseLangConfig;
    function SetBlockOpen(const AKind: string): TParseLangConfig;
    function SetBlockClose(const AKind: string): TParseLangConfig;

    // Emit surface — fluent

    // Register a code emitter for a given AST node kind string
    function RegisterEmitter(const ANodeKind: string;
      const AHandler: TParseEmitHandler): TParseLangConfig;

    // Semantic surface — fluent

    // Register a semantic analysis handler for a given AST node kind string.
    // The handler receives the node and the semantic engine base, enriches
    // the node with PARSE_ATTR_* attributes, and drives child traversal.
    function RegisterSemanticRule(const ANodeKind: string;
      const AHandler: TParseSemanticHandler): TParseLangConfig;

    // Register the language type compatibility function.
    // Called by the engine to resolve assignment/argument type compatibility
    // and to determine when an implicit coercion attribute must be written.
    function RegisterTypeCompat(
      const AFunc: TParseTypeCompatFunc): TParseLangConfig;

    // ---- Type inference surface — fluent ----

    // Map a literal node kind to a type kind string.
    function AddLiteralType(const ANodeKind, ATypeKind: string): TParseLangConfig;

    // Register a node kind as a variable declaration site.
    function AddDeclKind(const ANodeKind: string): TParseLangConfig;

    // Register a node kind as a call site.
    function AddCallKind(const ANodeKind: string): TParseLangConfig;

    // Set the attribute name that holds the callee name on call nodes.
    function SetCallNameAttr(const AAttr: string): TParseLangConfig;

    // Map a type keyword text (case-insensitive) to a type kind string.
    // e.g. AddTypeKeyword('integer', 'type.integer')
    function AddTypeKeyword(const AText, ATypeKind: string): TParseLangConfig;

    // Set the name mangling function.
    function SetNameMangler(const AFunc: TParseNameMangler): TParseLangConfig;

    // Set the type-to-IR mapping function.
    function SetTypeToIR(const AFunc: TParseTypeToIR): TParseLangConfig;

    // Register an ExprToString override for a specific node kind.
    function RegisterExprOverride(const ANodeKind: string;
      const AHandler: TParseExprOverride): TParseLangConfig;

    // Convenience: register a standard left-associative binary operator handler.
    // Creates an 'expr.binary' node with attr 'op' = ACppOp.
    function RegisterBinaryOp(const ATokenKind: string;
      const ABindingPower: Integer;
      const ACppOp: string): TParseLangConfig;

    // Convenience: register standard literal prefix handlers for the four
    // universal token kinds: identifier, integer, real, string.
    function RegisterLiteralPrefixes(): TParseLangConfig;

    // ---- Type inference behaviour methods ----

    // Infer type kind from a literal node using FLiteralTypes.
    // Returns 'type.double' if not found.
    function InferLiteralType(const ANode: TParseASTNodeBase): string;

    // Walk ARoot collecting variable name → type kind into FDeclTypes.
    procedure ScanDeclTypes(const ARoot: TParseASTNodeBase);

    // Walk ARoot collecting call-site arg types into FCallArgTypes.
    procedure ScanCallSites(const ARoot: TParseASTNodeBase);

    // Clear FDeclTypes and FCallArgTypes, then run ScanDeclTypes + ScanCallSites.
    procedure ScanAll(const ARoot: TParseASTNodeBase);

    // Read accessors for post-scan results.
    function GetDeclTypes(): TDictionary<string, string>;
    function GetCallArgTypes(): TDictionary<string, TArray<string>>;

    // Scan last child of ABodyNode for implicit return type.
    // Returns 'type.void' if last child kind is not in AValueKinds.
    function ScanReturnType(const ABodyNode: TParseASTNodeBase;
      const AValueKinds: array of string): string;

    // Scan ABodyNode recursively for a node of kind AReturnNodeKind.
    // Returns type kind of child[0] of the first match, or '' if none.
    function ScanReturnTypeRecursive(const ABodyNode: TParseASTNodeBase;
      const AReturnNodeKind: string): string;

    // ---- Type keyword lookup ----

    // Map a type keyword text to a type kind string (case-insensitive).
    // Returns 'type.unknown' if not registered.
    function TypeTextToKind(const AText: string): string;

    // ---- TypeToIR ----

    // Map a type kind string to a C++ type string.
    // Uses FTypeToIR if set; otherwise uses built-in defaults.
    function TypeToIR(const ATypeKind: string): string;

    // ---- Name mangling ----

    // Apply FNameMangler to AName. Returns AName unchanged if nil.
    function MangleName(const AName: string): string;

    // ---- ExprToString ----

    // Recursive node → C++ expression string.
    // Languages call RegisterExprOverride for node kinds that differ.
    function ExprToString(const ANode: TParseASTNodeBase): string;

    // Lexer surface — read accessors (used by TParseLexer)
    function GetCaseSensitive(): Boolean;
    function GetIdentStartChars(): TSysCharSet;
    function GetIdentPartChars(): TSysCharSet;
    function GetLineComments(): TList<string>;
    function GetBlockComments(): TList<TParseBlockCommentDef>;
    function GetStringStyles(): TList<TParseStringStyleDef>;
    function GetOperators(): TList<TParseOperatorDef>;
    function GetKeywords(): TDictionary<string, string>;
    function GetHexPrefixes(): TList<string>;
    function GetHexKind(): string;
    function GetBinaryPrefixes(): TList<string>;
    function GetBinaryKind(): string;
    function GetIntegerKind(): string;
    function GetRealKind(): string;
    function GetIdentifierKind(): string;
    function GetEOFKind(): string;
    function GetUnknownKind(): string;
    function GetLineCommentKind(): string;
    function GetBlockCommentKind(): string;
    function GetDirectivePrefix(): string;
    function GetDirectiveKind(): string;

    // Grammar surface — read accessors (used by TParseParser)
    function GetStatementEntry(const AKind: string;
      out AEntry: TParseStatementEntry): Boolean;
    function GetPrefixEntry(const AKind: string;
      out AEntry: TParsePrefixEntry): Boolean;
    function GetInfixEntry(const AKind: string;
      out AEntry: TParseInfixEntry): Boolean;
    function GetStructural(): TParseStructuralConfig;

    // Emit surface — read accessors (used by TParseCodeGen)
    function GetEmitHandler(const ANodeKind: string;
      out AHandler: TParseEmitHandler): Boolean;

    // Semantic surface — read accessors (used by TParseSemantics)
    function GetSemanticHandler(const ANodeKind: string;
      out AHandler: TParseSemanticHandler): Boolean;
    function GetTypeCompatFunc(): TParseTypeCompatFunc;
  end;

implementation

{ TParseLangConfig }

procedure TParseLangConfig.ResetToDefaults();
begin
  FCaseSensitive    := False;
  FIntegerKind      := PARSE_KIND_INTEGER;
  FRealKind         := PARSE_KIND_REAL;
  FIdentifierKind   := PARSE_KIND_IDENTIFIER;
  FEOFKind          := PARSE_KIND_EOF;
  FUnknownKind      := PARSE_KIND_UNKNOWN;
  FLineCommentKind  := PARSE_KIND_COMMENT_LINE;
  FBlockCommentKind := PARSE_KIND_COMMENT_BLOCK;
  FDirectiveKind    := PARSE_KIND_DIRECTIVE;
  FDirectivePrefix  := '';
  FHexKind          := PARSE_KIND_INTEGER;
  FBinaryKind       := PARSE_KIND_INTEGER;

  FLineComments.Clear();
  FBlockComments.Clear();
  FStringStyles.Clear();
  FOperators.Clear();
  FKeywords.Clear();
  FHexPrefixes.Clear();
  FBinaryPrefixes.Clear();

  FStatementHandlers.Clear();
  FPrefixHandlers.Clear();
  FInfixHandlers.Clear();
  FEmitHandlers.Clear();
  FSemanticHandlers.Clear();
  FTypeCompatFunc := nil;

  // Clear type inference surface
  if FLiteralTypes  <> nil then FLiteralTypes.Clear();
  if FDeclKinds     <> nil then FDeclKinds.Clear();
  if FCallKinds     <> nil then FCallKinds.Clear();
  if FTypeKeywords  <> nil then FTypeKeywords.Clear();
  if FDeclTypes     <> nil then FDeclTypes.Clear();
  if FCallArgTypes  <> nil then FCallArgTypes.Clear();
  if FExprOverrides <> nil then FExprOverrides.Clear();
  FCallNameAttr := 'call.name';
  FNameMangler  := nil;
  FTypeToIR     := nil;

  FStructural.StatementTerminator := '';
  FStructural.BlockOpen           := '';
  FStructural.BlockClose          := '';

  // Default identifier character classes: standard ASCII letters + underscore
  ParseCharSet('a-zA-Z_',    FIdentStartChars);
  ParseCharSet('a-zA-Z0-9_', FIdentPartChars);
end;

function TParseLangConfig.CharSetToPattern(const ASet: TSysCharSet): string;
var
  LI:     Integer;
  LStart: Integer;
  LEnd:   Integer;
begin
  Result := '';
  LI     := 32; // start from printable ASCII

  while LI <= 127 do
  begin
    if AnsiChar(LI) in ASet then
    begin
      LStart := LI;
      LEnd   := LI;
      while (LEnd + 1 <= 127) and (AnsiChar(LEnd + 1) in ASet) do
        Inc(LEnd);

      if LEnd - LStart >= 2 then
      begin
        Result := Result + Char(LStart) + '-' + Char(LEnd);
        LI     := LEnd + 1;
      end
      else
      begin
        Result := Result + Char(LStart);
        LI     := LStart + 1;
      end;
    end
    else
      Inc(LI);
  end;
end;

constructor TParseLangConfig.Create();
begin
  inherited;

  FLineComments      := TList<string>.Create();
  FBlockComments     := TList<TParseBlockCommentDef>.Create();
  FStringStyles      := TList<TParseStringStyleDef>.Create();
  FOperators         := TList<TParseOperatorDef>.Create();
  FKeywords          := TDictionary<string, string>.Create();
  FHexPrefixes       := TList<string>.Create();
  FBinaryPrefixes    := TList<string>.Create();
  FStatementHandlers := TDictionary<string, TParseStatementEntry>.Create();
  FPrefixHandlers    := TDictionary<string, TParsePrefixEntry>.Create();
  FInfixHandlers     := TDictionary<string, TParseInfixEntry>.Create();
  FEmitHandlers      := TDictionary<string, TParseEmitHandler>.Create();
  FSemanticHandlers  := TDictionary<string, TParseSemanticHandler>.Create();
  FTypeCompatFunc    := nil;

  // Type inference surface
  FLiteralTypes  := TDictionary<string, string>.Create();
  FDeclKinds     := TList<string>.Create();
  FCallKinds     := TList<string>.Create();
  FCallNameAttr  := 'call.name';
  FTypeKeywords  := TDictionary<string, string>.Create();
  FDeclTypes     := TDictionary<string, string>.Create();
  FCallArgTypes  := TDictionary<string, TArray<string>>.Create();
  FExprOverrides := TDictionary<string, TParseExprOverride>.Create();
  FNameMangler   := nil;
  FTypeToIR      := nil;

  ResetToDefaults();
end;

destructor TParseLangConfig.Destroy();
begin
  FreeAndNil(FExprOverrides);
  FreeAndNil(FCallArgTypes);
  FreeAndNil(FDeclTypes);
  FreeAndNil(FTypeKeywords);
  FreeAndNil(FCallKinds);
  FreeAndNil(FDeclKinds);
  FreeAndNil(FLiteralTypes);
  FreeAndNil(FSemanticHandlers);
  FreeAndNil(FEmitHandlers);
  FreeAndNil(FInfixHandlers);
  FreeAndNil(FPrefixHandlers);
  FreeAndNil(FStatementHandlers);
  FreeAndNil(FBinaryPrefixes);
  FreeAndNil(FHexPrefixes);
  FreeAndNil(FKeywords);
  FreeAndNil(FOperators);
  FreeAndNil(FStringStyles);
  FreeAndNil(FBlockComments);
  FreeAndNil(FLineComments);
  inherited;
end;

procedure TParseLangConfig.ParseCharSet(const APattern: string;
  out ASet: TSysCharSet);
var
  LI:     Integer;
  LCh:    AnsiChar;
  LStart: Integer;
  LEnd:   Integer;
  LC:     Integer;
begin
  ASet := [];
  LI   := 1;
  while LI <= Length(APattern) do
  begin
    LCh := AnsiChar(APattern[LI]);
    if (LI + 2 <= Length(APattern)) and (APattern[LI + 1] = '-') then
    begin
      LStart := Ord(LCh);
      LEnd   := Ord(AnsiChar(APattern[LI + 2]));
      for LC := LStart to LEnd do
        Include(ASet, AnsiChar(LC));
      Inc(LI, 3);
    end
    else
    begin
      Include(ASet, LCh);
      Inc(LI);
    end;
  end;
end;

procedure TParseLangConfig.SortOperators();
begin
  // Operators must be sorted longest-first so that multi-char tokens like
  // ':=' are always tried before single-char tokens like ':'
  FOperators.Sort(TComparer<TParseOperatorDef>.Construct(
    function(const A, B: TParseOperatorDef): Integer
    begin
      Result := Length(B.Text) - Length(A.Text);
    end));
end;

// Lexer surface — fluent

function TParseLangConfig.CaseSensitiveKeywords(
  const AValue: Boolean): TParseLangConfig;
begin
  FCaseSensitive := AValue;
  Result := Self;
end;

function TParseLangConfig.IdentifierStart(
  const AChars: string): TParseLangConfig;
begin
  ParseCharSet(AChars, FIdentStartChars);
  Result := Self;
end;

function TParseLangConfig.IdentifierPart(
  const AChars: string): TParseLangConfig;
begin
  ParseCharSet(AChars, FIdentPartChars);
  Result := Self;
end;

function TParseLangConfig.AddLineComment(
  const APrefix: string): TParseLangConfig;
begin
  if APrefix <> '' then
    FLineComments.Add(APrefix);
  Result := Self;
end;

function TParseLangConfig.AddBlockComment(const AOpen,
  AClose: string): TParseLangConfig;
var
  LEntry: TParseBlockCommentDef;
begin
  if (AOpen <> '') and (AClose <> '') then
  begin
    LEntry.OpenStr  := AOpen;
    LEntry.CloseStr := AClose;
    FBlockComments.Add(LEntry);
  end;
  Result := Self;
end;

function TParseLangConfig.AddStringStyle(const AOpen, AClose, AKind: string;
  const AAllowEscape: Boolean): TParseLangConfig;
var
  LEntry: TParseStringStyleDef;
begin
  if (AOpen <> '') and (AClose <> '') and (AKind <> '') then
  begin
    LEntry.OpenStr     := AOpen;
    LEntry.CloseStr    := AClose;
    LEntry.TokenKind   := AKind;
    LEntry.AllowEscape := AAllowEscape;
    FStringStyles.Add(LEntry);
  end;
  Result := Self;
end;

function TParseLangConfig.AddKeyword(const AText,
  AKind: string): TParseLangConfig;
var
  LKey: string;
begin
  if (AText <> '') and (AKind <> '') then
  begin
    if FCaseSensitive then
      LKey := AText
    else
      LKey := AText.ToLower();
    FKeywords.AddOrSetValue(LKey, AKind);
  end;
  Result := Self;
end;

function TParseLangConfig.AddOperator(const AText,
  AKind: string): TParseLangConfig;
var
  LEntry: TParseOperatorDef;
begin
  if (AText <> '') and (AKind <> '') then
  begin
    LEntry.Text      := AText;
    LEntry.TokenKind := AKind;
    FOperators.Add(LEntry);
    SortOperators();
  end;
  Result := Self;
end;

function TParseLangConfig.SetHexPrefix(const APrefix,
  AKind: string): TParseLangConfig;
begin
  if APrefix <> '' then
  begin
    FHexPrefixes.Add(APrefix);
    if AKind <> '' then
      FHexKind := AKind;
  end;
  Result := Self;
end;

function TParseLangConfig.SetBinaryPrefix(const APrefix,
  AKind: string): TParseLangConfig;
begin
  if APrefix <> '' then
  begin
    FBinaryPrefixes.Add(APrefix);
    if AKind <> '' then
      FBinaryKind := AKind;
  end;
  Result := Self;
end;

function TParseLangConfig.SetDirectivePrefix(const APrefix,
  AKind: string): TParseLangConfig;
begin
  FDirectivePrefix := APrefix;
  if AKind <> '' then
    FDirectiveKind := AKind;
  Result := Self;
end;

function TParseLangConfig.SetIntegerKind(
  const AKind: string): TParseLangConfig;
begin
  if AKind <> '' then
    FIntegerKind := AKind;
  Result := Self;
end;

function TParseLangConfig.SetRealKind(const AKind: string): TParseLangConfig;
begin
  if AKind <> '' then
    FRealKind := AKind;
  Result := Self;
end;

function TParseLangConfig.SetIdentifierKind(
  const AKind: string): TParseLangConfig;
begin
  if AKind <> '' then
    FIdentifierKind := AKind;
  Result := Self;
end;

// Grammar surface — fluent

function TParseLangConfig.RegisterStatement(const AKind, ANodeKind: string;
  const AHandler: TParseStatementHandler): TParseLangConfig;
var
  LEntry: TParseStatementEntry;
begin
  if (AKind <> '') and (ANodeKind <> '') then
  begin
    LEntry.NodeKind := ANodeKind;
    LEntry.Handler  := AHandler;
    FStatementHandlers.AddOrSetValue(AKind, LEntry);
  end;
  Result := Self;
end;

function TParseLangConfig.RegisterPrefix(const AKind, ANodeKind: string;
  const AHandler: TParsePrefixHandler): TParseLangConfig;
var
  LEntry: TParsePrefixEntry;
begin
  if (AKind <> '') and (ANodeKind <> '') then
  begin
    LEntry.NodeKind := ANodeKind;
    LEntry.Handler  := AHandler;
    FPrefixHandlers.AddOrSetValue(AKind, LEntry);
  end;
  Result := Self;
end;

function TParseLangConfig.RegisterInfixLeft(const AKind: string;
  const ABindingPower: Integer; const ANodeKind: string;
  const AHandler: TParseInfixHandler): TParseLangConfig;
var
  LEntry: TParseInfixEntry;
begin
  if (AKind <> '') and (ANodeKind <> '') then
  begin
    LEntry.NodeKind     := ANodeKind;
    LEntry.BindingPower := ABindingPower;
    LEntry.Assoc        := aoLeft;
    LEntry.Handler      := AHandler;
    FInfixHandlers.AddOrSetValue(AKind, LEntry);
  end;
  Result := Self;
end;

function TParseLangConfig.RegisterInfixRight(const AKind: string;
  const ABindingPower: Integer; const ANodeKind: string;
  const AHandler: TParseInfixHandler): TParseLangConfig;
var
  LEntry: TParseInfixEntry;
begin
  if (AKind <> '') and (ANodeKind <> '') then
  begin
    LEntry.NodeKind     := ANodeKind;
    LEntry.BindingPower := ABindingPower;
    LEntry.Assoc        := aoRight;
    LEntry.Handler      := AHandler;
    FInfixHandlers.AddOrSetValue(AKind, LEntry);
  end;
  Result := Self;
end;

function TParseLangConfig.SetStatementTerminator(
  const AKind: string): TParseLangConfig;
begin
  FStructural.StatementTerminator := AKind;
  Result := Self;
end;

function TParseLangConfig.SetBlockOpen(const AKind: string): TParseLangConfig;
begin
  FStructural.BlockOpen := AKind;
  Result := Self;
end;

function TParseLangConfig.SetBlockClose(const AKind: string): TParseLangConfig;
begin
  FStructural.BlockClose := AKind;
  Result := Self;
end;

// Emit surface — fluent

function TParseLangConfig.RegisterEmitter(const ANodeKind: string;
  const AHandler: TParseEmitHandler): TParseLangConfig;
begin
  if ANodeKind <> '' then
    FEmitHandlers.AddOrSetValue(ANodeKind, AHandler);
  Result := Self;
end;

// Semantic surface — fluent

function TParseLangConfig.RegisterSemanticRule(const ANodeKind: string;
  const AHandler: TParseSemanticHandler): TParseLangConfig;
begin
  if ANodeKind <> '' then
    FSemanticHandlers.AddOrSetValue(ANodeKind, AHandler);
  Result := Self;
end;

function TParseLangConfig.RegisterTypeCompat(
  const AFunc: TParseTypeCompatFunc): TParseLangConfig;
begin
  FTypeCompatFunc := AFunc;
  Result := Self;
end;

// Lexer surface — read accessors

function TParseLangConfig.GetCaseSensitive(): Boolean;
begin
  Result := FCaseSensitive;
end;

function TParseLangConfig.GetIdentStartChars(): TSysCharSet;
begin
  Result := FIdentStartChars;
end;

function TParseLangConfig.GetIdentPartChars(): TSysCharSet;
begin
  Result := FIdentPartChars;
end;

function TParseLangConfig.GetLineComments(): TList<string>;
begin
  Result := FLineComments;
end;

function TParseLangConfig.GetBlockComments(): TList<TParseBlockCommentDef>;
begin
  Result := FBlockComments;
end;

function TParseLangConfig.GetStringStyles(): TList<TParseStringStyleDef>;
begin
  Result := FStringStyles;
end;

function TParseLangConfig.GetOperators(): TList<TParseOperatorDef>;
begin
  Result := FOperators;
end;

function TParseLangConfig.GetKeywords(): TDictionary<string, string>;
begin
  Result := FKeywords;
end;

function TParseLangConfig.GetHexPrefixes(): TList<string>;
begin
  Result := FHexPrefixes;
end;

function TParseLangConfig.GetHexKind(): string;
begin
  Result := FHexKind;
end;

function TParseLangConfig.GetBinaryPrefixes(): TList<string>;
begin
  Result := FBinaryPrefixes;
end;

function TParseLangConfig.GetBinaryKind(): string;
begin
  Result := FBinaryKind;
end;

function TParseLangConfig.GetIntegerKind(): string;
begin
  Result := FIntegerKind;
end;

function TParseLangConfig.GetRealKind(): string;
begin
  Result := FRealKind;
end;

function TParseLangConfig.GetIdentifierKind(): string;
begin
  Result := FIdentifierKind;
end;

function TParseLangConfig.GetEOFKind(): string;
begin
  Result := FEOFKind;
end;

function TParseLangConfig.GetUnknownKind(): string;
begin
  Result := FUnknownKind;
end;

function TParseLangConfig.GetLineCommentKind(): string;
begin
  Result := FLineCommentKind;
end;

function TParseLangConfig.GetBlockCommentKind(): string;
begin
  Result := FBlockCommentKind;
end;

function TParseLangConfig.GetDirectivePrefix(): string;
begin
  Result := FDirectivePrefix;
end;

function TParseLangConfig.GetDirectiveKind(): string;
begin
  Result := FDirectiveKind;
end;

// Grammar surface — read accessors

function TParseLangConfig.GetStatementEntry(const AKind: string;
  out AEntry: TParseStatementEntry): Boolean;
begin
  Result := FStatementHandlers.TryGetValue(AKind, AEntry);
end;

function TParseLangConfig.GetPrefixEntry(const AKind: string;
  out AEntry: TParsePrefixEntry): Boolean;
begin
  Result := FPrefixHandlers.TryGetValue(AKind, AEntry);
end;

function TParseLangConfig.GetInfixEntry(const AKind: string;
  out AEntry: TParseInfixEntry): Boolean;
begin
  Result := FInfixHandlers.TryGetValue(AKind, AEntry);
end;

function TParseLangConfig.GetStructural(): TParseStructuralConfig;
begin
  Result := FStructural;
end;

// Emit surface — read accessors

function TParseLangConfig.GetEmitHandler(const ANodeKind: string;
  out AHandler: TParseEmitHandler): Boolean;
begin
  Result := FEmitHandlers.TryGetValue(ANodeKind, AHandler);
end;

// Semantic surface — read accessors

function TParseLangConfig.GetSemanticHandler(const ANodeKind: string;
  out AHandler: TParseSemanticHandler): Boolean;
begin
  Result := FSemanticHandlers.TryGetValue(ANodeKind, AHandler);
end;

function TParseLangConfig.GetTypeCompatFunc(): TParseTypeCompatFunc;
begin
  Result := FTypeCompatFunc;
end;

// ---- Type inference surface — fluent ----

function TParseLangConfig.AddLiteralType(const ANodeKind,
  ATypeKind: string): TParseLangConfig;
begin
  if (ANodeKind <> '') and (ATypeKind <> '') then
    FLiteralTypes.AddOrSetValue(ANodeKind, ATypeKind);
  Result := Self;
end;

function TParseLangConfig.AddDeclKind(const ANodeKind: string): TParseLangConfig;
begin
  if (ANodeKind <> '') and (not FDeclKinds.Contains(ANodeKind)) then
    FDeclKinds.Add(ANodeKind);
  Result := Self;
end;

function TParseLangConfig.AddCallKind(const ANodeKind: string): TParseLangConfig;
begin
  if (ANodeKind <> '') and (not FCallKinds.Contains(ANodeKind)) then
    FCallKinds.Add(ANodeKind);
  Result := Self;
end;

function TParseLangConfig.SetCallNameAttr(
  const AAttr: string): TParseLangConfig;
begin
  if AAttr <> '' then
    FCallNameAttr := AAttr;
  Result := Self;
end;

function TParseLangConfig.AddTypeKeyword(const AText,
  ATypeKind: string): TParseLangConfig;
begin
  // Store keys lowercase for case-insensitive lookup
  if (AText <> '') and (ATypeKind <> '') then
    FTypeKeywords.AddOrSetValue(LowerCase(AText), ATypeKind);
  Result := Self;
end;

function TParseLangConfig.SetNameMangler(
  const AFunc: TParseNameMangler): TParseLangConfig;
begin
  FNameMangler := AFunc;
  Result := Self;
end;

function TParseLangConfig.SetTypeToIR(
  const AFunc: TParseTypeToIR): TParseLangConfig;
begin
  FTypeToIR := AFunc;
  Result := Self;
end;

function TParseLangConfig.RegisterExprOverride(const ANodeKind: string;
  const AHandler: TParseExprOverride): TParseLangConfig;
begin
  if ANodeKind <> '' then
    FExprOverrides.AddOrSetValue(ANodeKind, AHandler);
  Result := Self;
end;

function TParseLangConfig.RegisterBinaryOp(const ATokenKind: string;
  const ABindingPower: Integer;
  const ACppOp: string): TParseLangConfig;
begin
  // Capture ACppOp in the anonymous handler closure
  RegisterInfixLeft(ATokenKind, ABindingPower, 'expr.binary',
    function(AParser: TParseParserBase;
      ALeft: TParseASTNodeBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      LNode.SetAttr('op', TValue.From<string>(ACppOp));
      AParser.Consume();
      LNode.AddChild(TParseASTNode(ALeft));
      LNode.AddChild(TParseASTNode(
        AParser.ParseExpression(AParser.CurrentInfixPower())));
      Result := LNode;
    end);
  Result := Self;
end;

function TParseLangConfig.RegisterLiteralPrefixes(): TParseLangConfig;
begin
  // identifier
  RegisterPrefix(PARSE_KIND_IDENTIFIER, 'expr.ident',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();
      Result := LNode;
    end);

  // integer literal
  RegisterPrefix(PARSE_KIND_INTEGER, 'expr.integer',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();
      Result := LNode;
    end);

  // real literal
  RegisterPrefix(PARSE_KIND_REAL, 'expr.real',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();
      Result := LNode;
    end);

  // string literal
  RegisterPrefix(PARSE_KIND_STRING, 'expr.string',
    function(AParser: TParseParserBase): TParseASTNodeBase
    var
      LNode: TParseASTNode;
    begin
      LNode := AParser.CreateNode();
      AParser.Consume();
      Result := LNode;
    end);

  Result := Self;
end;

// ---- Type inference behaviour methods ----

function TParseLangConfig.InferLiteralType(
  const ANode: TParseASTNodeBase): string;
begin
  if not FLiteralTypes.TryGetValue(ANode.GetNodeKind(), Result) then
    Result := 'type.double';
end;

procedure TParseLangConfig.ScanDeclTypes(const ARoot: TParseASTNodeBase);
var
  LI:    Integer;
  LKind: string;
begin
  if ARoot = nil then
    Exit;
  LKind := ARoot.GetNodeKind();
  // If this node is a declaration site, record var name → type kind
  if FDeclKinds.Contains(LKind) then
    FDeclTypes.AddOrSetValue(ARoot.GetToken().Text,
      InferLiteralType(ARoot.GetChild(0)));
  // Always recurse into children
  for LI := 0 to ARoot.ChildCount() - 1 do
    ScanDeclTypes(ARoot.GetChild(LI));
end;

procedure TParseLangConfig.ScanCallSites(const ARoot: TParseASTNodeBase);
var
  LI:       Integer;
  LKind:    string;
  LName:    TValue;
  LFuncName: string;
  LArgTypes: TArray<string>;
  LArgNode:  TParseASTNodeBase;
  LArgKind:  string;
  LArgType:  string;
begin
  if ARoot = nil then
    Exit;
  LKind := ARoot.GetNodeKind();
  if FCallKinds.Contains(LKind) then
  begin
    // Get callee name from the designated attribute
    if ARoot.GetAttr(FCallNameAttr, LName) then
    begin
      LFuncName := LName.AsString;
      SetLength(LArgTypes, ARoot.ChildCount());
      for LI := 0 to ARoot.ChildCount() - 1 do
      begin
        LArgNode := ARoot.GetChild(LI);
        LArgKind := LArgNode.GetNodeKind();
        // Try to resolve type from literal kinds first, then from declared vars
        if FLiteralTypes.TryGetValue(LArgKind, LArgType) then
          LArgTypes[LI] := LArgType
        else if LArgKind = 'expr.ident' then
        begin
          if not FDeclTypes.TryGetValue(LArgNode.GetToken().Text, LArgTypes[LI]) then
            LArgTypes[LI] := 'type.double';
        end
        else
          LArgTypes[LI] := 'type.double';
      end;
      FCallArgTypes.AddOrSetValue(LFuncName, LArgTypes);
    end;
  end;
  // Always recurse
  for LI := 0 to ARoot.ChildCount() - 1 do
    ScanCallSites(ARoot.GetChild(LI));
end;

procedure TParseLangConfig.ScanAll(const ARoot: TParseASTNodeBase);
begin
  FDeclTypes.Clear();
  FCallArgTypes.Clear();
  ScanDeclTypes(ARoot);
  ScanCallSites(ARoot);
end;

function TParseLangConfig.GetDeclTypes(): TDictionary<string, string>;
begin
  Result := FDeclTypes;
end;

function TParseLangConfig.GetCallArgTypes(): TDictionary<string, TArray<string>>;
begin
  Result := FCallArgTypes;
end;

function TParseLangConfig.ScanReturnType(const ABodyNode: TParseASTNodeBase;
  const AValueKinds: array of string): string;
var
  LLast:     TParseASTNodeBase;
  LLastKind: string;
  LKind:     string;
  LFound:    Boolean;
begin
  Result := 'type.void';
  if (ABodyNode = nil) or (ABodyNode.ChildCount() = 0) then
    Exit;
  LLast     := ABodyNode.GetChild(ABodyNode.ChildCount() - 1);
  LLastKind := LLast.GetNodeKind();
  LFound    := False;
  for LKind in AValueKinds do
    if LKind = LLastKind then
    begin
      LFound := True;
      Break;
    end;
  if LFound then
    Result := InferLiteralType(LLast);
end;

function TParseLangConfig.ScanReturnTypeRecursive(
  const ABodyNode: TParseASTNodeBase;
  const AReturnNodeKind: string): string;
var
  LI:    Integer;
  LChild: TParseASTNodeBase;
begin
  Result := '';
  if ABodyNode = nil then
    Exit;
  if ABodyNode.GetNodeKind() = AReturnNodeKind then
  begin
    // Found a return node — get type kind of child[0]
    if ABodyNode.ChildCount() > 0 then
      Result := InferLiteralType(ABodyNode.GetChild(0));
    Exit;
  end;
  // Recurse into children
  for LI := 0 to ABodyNode.ChildCount() - 1 do
  begin
    LChild := ABodyNode.GetChild(LI);
    Result := ScanReturnTypeRecursive(LChild, AReturnNodeKind);
    if Result <> '' then
      Exit;
  end;
end;

// ---- Type keyword lookup ----

function TParseLangConfig.TypeTextToKind(const AText: string): string;
begin
  if not FTypeKeywords.TryGetValue(LowerCase(AText), Result) then
    Result := 'type.unknown';
end;

// ---- TypeToIR ----

function TParseLangConfig.TypeToIR(const ATypeKind: string): string;
begin
  // Delegate to language-specific override if set
  if Assigned(FTypeToIR) then
  begin
    Result := FTypeToIR(ATypeKind);
    Exit;
  end;
  // Built-in defaults
  if ATypeKind = 'type.string' then
    Result := 'std::string'
  else if ATypeKind = 'type.integer' then
    Result := 'int32_t'
  else if ATypeKind = 'type.double' then
    Result := 'double'
  else if ATypeKind = 'type.boolean' then
    Result := 'bool'
  else if ATypeKind = 'type.void' then
    Result := 'void'
  else
    Result := 'double';
end;

// ---- Name mangling ----

function TParseLangConfig.MangleName(const AName: string): string;
begin
  if Assigned(FNameMangler) then
    Result := FNameMangler(AName)
  else
    Result := AName;
end;

// ---- ExprToString ----

function TParseLangConfig.ExprToString(const ANode: TParseASTNodeBase): string;
var
  LOverride:  TParseExprOverride;
  LKind:      string;
  LText:      string;
  LAttr:      TValue;
  LOp:        string;
  LArgs:      string;
  LI:         Integer;
  LDefault:   TParseExprToStringFunc;
begin
  Result := '';
  if ANode = nil then
    Exit;

  LKind := ANode.GetNodeKind();

  // Build the default function reference for overrides to call
  LDefault := function(const AChild: TParseASTNodeBase): string
    begin
      Result := ExprToString(AChild);
    end;

  // Check for a language-specific override first
  if FExprOverrides.TryGetValue(LKind, LOverride) then
  begin
    Result := LOverride(ANode, LDefault);
    Exit;
  end;

  // Default handling
  if LKind = 'expr.ident' then
    Result := MangleName(ANode.GetToken().Text)
  else if (LKind = 'expr.integer') or (LKind = 'expr.real') then
    Result := ANode.GetToken().Text
  else if LKind = 'expr.bool' then
    // Default: pass through token text (override for language-specific True/False)
    Result := ANode.GetToken().Text
  else if LKind = 'expr.string' then
  begin
    // Strip outer quotes and re-wrap in double quotes
    LText := ANode.GetToken().Text;
    if (Length(LText) >= 2) and
       ((LText[1] = '"') or (LText[1] = '''')) and
       (LText[Length(LText)] = LText[1]) then
      Result := '"' + Copy(LText, 2, Length(LText) - 2) + '"'
    else
      Result := '"' + LText + '"';
  end
  else if LKind = 'expr.unary' then
  begin
    ANode.GetAttr('op', LAttr);
    LOp    := LAttr.AsString;
    Result := LOp + ExprToString(ANode.GetChild(0));
  end
  else if LKind = 'expr.binary' then
  begin
    ANode.GetAttr('op', LAttr);
    LOp    := LAttr.AsString;
    Result := ExprToString(ANode.GetChild(0)) + ' ' + LOp + ' ' +
              ExprToString(ANode.GetChild(1));
  end
  else if LKind = 'expr.grouped' then
    Result := '(' + ExprToString(ANode.GetChild(0)) + ')'
  else if LKind = 'expr.call' then
  begin
    ANode.GetAttr('call.name', LAttr);
    LArgs := '';
    for LI := 0 to ANode.ChildCount() - 1 do
    begin
      if LI > 0 then
        LArgs := LArgs + ', ';
      LArgs := LArgs + ExprToString(ANode.GetChild(LI));
    end;
    Result := MangleName(LAttr.AsString) + '(' + LArgs + ')';
  end;
  // else: return '' for unrecognised node kinds
end;

// TOML persistence

procedure TParseLangConfig.DoLoadConfig(const AConfig: TParseConfig);
var
  LCount:    Integer;
  LI:        Integer;
  LOpen:     string;
  LClose:    string;
  LKind:     string;
  LText:     string;
  LAllowEsc: Boolean;
  LPrefix:   string;
  LPrefixes: TArray<string>;
begin
  ResetToDefaults();

  // Scalar fields
  FCaseSensitive    := AConfig.GetBoolean('case_sensitive',     False);
  FIntegerKind      := AConfig.GetString('integer_kind',        PARSE_KIND_INTEGER);
  FRealKind         := AConfig.GetString('real_kind',           PARSE_KIND_REAL);
  FIdentifierKind   := AConfig.GetString('identifier_kind',     PARSE_KIND_IDENTIFIER);
  FLineCommentKind  := AConfig.GetString('line_comment_kind',   PARSE_KIND_COMMENT_LINE);
  FBlockCommentKind := AConfig.GetString('block_comment_kind',  PARSE_KIND_COMMENT_BLOCK);
  FDirectivePrefix  := AConfig.GetString('directive_prefix',    '');
  FDirectiveKind    := AConfig.GetString('directive_kind',      PARSE_KIND_DIRECTIVE);
  FHexKind          := AConfig.GetString('hex_kind',            PARSE_KIND_INTEGER);
  FBinaryKind       := AConfig.GetString('binary_kind',         PARSE_KIND_INTEGER);

  LText := AConfig.GetString('identifier_start', '');
  if LText <> '' then
    ParseCharSet(LText, FIdentStartChars);

  LText := AConfig.GetString('identifier_part', '');
  if LText <> '' then
    ParseCharSet(LText, FIdentPartChars);

  LPrefixes := AConfig.GetStringArray('line_comments');
  for LPrefix in LPrefixes do
    AddLineComment(LPrefix);

  LPrefixes := AConfig.GetStringArray('hex_prefixes');
  for LPrefix in LPrefixes do
    if LPrefix <> '' then
      FHexPrefixes.Add(LPrefix);

  LPrefixes := AConfig.GetStringArray('binary_prefixes');
  for LPrefix in LPrefixes do
    if LPrefix <> '' then
      FBinaryPrefixes.Add(LPrefix);

  LCount := AConfig.GetTableCount('block_comments');
  for LI := 0 to LCount - 1 do
  begin
    LOpen  := AConfig.GetTableString('block_comments', LI, 'open',  '');
    LClose := AConfig.GetTableString('block_comments', LI, 'close', '');
    AddBlockComment(LOpen, LClose);
  end;

  LCount := AConfig.GetTableCount('string_styles');
  for LI := 0 to LCount - 1 do
  begin
    LOpen     := AConfig.GetTableString('string_styles',  LI, 'open',         '');
    LClose    := AConfig.GetTableString('string_styles',  LI, 'close',        '');
    LKind     := AConfig.GetTableString('string_styles',  LI, 'kind',         '');
    LAllowEsc := AConfig.GetTableBoolean('string_styles', LI, 'allow_escape', True);
    AddStringStyle(LOpen, LClose, LKind, LAllowEsc);
  end;

  LCount := AConfig.GetTableCount('operators');
  for LI := 0 to LCount - 1 do
  begin
    LText := AConfig.GetTableString('operators', LI, 'text', '');
    LKind := AConfig.GetTableString('operators', LI, 'kind', '');
    AddOperator(LText, LKind);
  end;

  LCount := AConfig.GetTableCount('keywords');
  for LI := 0 to LCount - 1 do
  begin
    LText := AConfig.GetTableString('keywords', LI, 'text', '');
    LKind := AConfig.GetTableString('keywords', LI, 'kind', '');
    AddKeyword(LText, LKind);
  end;

  // Grammar surface structural tokens
  FStructural.StatementTerminator :=
    AConfig.GetString('structural.statement_terminator', '');
  FStructural.BlockOpen  :=
    AConfig.GetString('structural.block_open',  '');
  FStructural.BlockClose :=
    AConfig.GetString('structural.block_close', '');
end;

procedure TParseLangConfig.DoSaveConfig(const AConfig: TParseConfig);
var
  LPair:     TPair<string, string>;
  LBC:       TParseBlockCommentDef;
  LSS:       TParseStringStyleDef;
  LOp:       TParseOperatorDef;
  LIdx:      Integer;
  LPrefixes: TArray<string>;
  LI:        Integer;
begin
  AConfig.SetBoolean('case_sensitive',    FCaseSensitive);
  AConfig.SetString('identifier_start',   CharSetToPattern(FIdentStartChars));
  AConfig.SetString('identifier_part',    CharSetToPattern(FIdentPartChars));
  AConfig.SetString('integer_kind',       FIntegerKind);
  AConfig.SetString('real_kind',          FRealKind);
  AConfig.SetString('identifier_kind',    FIdentifierKind);
  AConfig.SetString('line_comment_kind',  FLineCommentKind);
  AConfig.SetString('block_comment_kind', FBlockCommentKind);
  AConfig.SetString('directive_prefix',   FDirectivePrefix);
  AConfig.SetString('directive_kind',     FDirectiveKind);
  AConfig.SetString('hex_kind',           FHexKind);
  AConfig.SetString('binary_kind',        FBinaryKind);

  SetLength(LPrefixes, FLineComments.Count);
  for LI := 0 to FLineComments.Count - 1 do
    LPrefixes[LI] := FLineComments[LI];
  AConfig.SetStringArray('line_comments', LPrefixes);

  SetLength(LPrefixes, FHexPrefixes.Count);
  for LI := 0 to FHexPrefixes.Count - 1 do
    LPrefixes[LI] := FHexPrefixes[LI];
  AConfig.SetStringArray('hex_prefixes', LPrefixes);

  SetLength(LPrefixes, FBinaryPrefixes.Count);
  for LI := 0 to FBinaryPrefixes.Count - 1 do
    LPrefixes[LI] := FBinaryPrefixes[LI];
  AConfig.SetStringArray('binary_prefixes', LPrefixes);

  for LBC in FBlockComments do
  begin
    LIdx := AConfig.AddTableEntry('block_comments');
    AConfig.SetTableString('block_comments', LIdx, 'open',  LBC.OpenStr);
    AConfig.SetTableString('block_comments', LIdx, 'close', LBC.CloseStr);
  end;

  for LSS in FStringStyles do
  begin
    LIdx := AConfig.AddTableEntry('string_styles');
    AConfig.SetTableString('string_styles',  LIdx, 'open',         LSS.OpenStr);
    AConfig.SetTableString('string_styles',  LIdx, 'close',        LSS.CloseStr);
    AConfig.SetTableString('string_styles',  LIdx, 'kind',         LSS.TokenKind);
    AConfig.SetTableBoolean('string_styles', LIdx, 'allow_escape', LSS.AllowEscape);
  end;

  for LOp in FOperators do
  begin
    LIdx := AConfig.AddTableEntry('operators');
    AConfig.SetTableString('operators', LIdx, 'text', LOp.Text);
    AConfig.SetTableString('operators', LIdx, 'kind', LOp.TokenKind);
  end;

  for LPair in FKeywords do
  begin
    LIdx := AConfig.AddTableEntry('keywords');
    AConfig.SetTableString('keywords', LIdx, 'text', LPair.Key);
    AConfig.SetTableString('keywords', LIdx, 'kind', LPair.Value);
  end;

  AConfig.SetString('structural.statement_terminator',
    FStructural.StatementTerminator);
  AConfig.SetString('structural.block_open',  FStructural.BlockOpen);
  AConfig.SetString('structural.block_close', FStructural.BlockClose);
end;

end.
