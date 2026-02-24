{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

unit Parse.Parser;

{$I Parse.Defines.inc}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Parse.Utils,
  Parse.Common,
  Parse.LangConfig,
  Parse.Lexer;

type

  { TParseParser }
  TParseParser = class(TParseParserBase)
  private
    FConfig:            TParseLangConfig;  // not owned — caller manages lifetime
    FTokens:            TArray<TParseToken>;
    FPos:               Integer;
    FCurrentNodeKind:   string;   // set by engine before each handler dispatch
    FCurrentInfixPower: Integer;  // set by engine before each infix handler dispatch

    // Returns True if position is at or past the last token
    function IsAtEnd(): Boolean;

    // Returns a synthetic EOF token for safe out-of-bounds access
    function MakeEOFToken(): TParseToken;

    // Advance position by one — does NOT skip comments (they are AST nodes)
    procedure Advance();

    // Report a parse error at the given token's location via FErrors
    procedure AddError(const AToken: TParseToken; const AMsg: string);

    // Error recovery — advance until a statement boundary is found
    {$HINTS OFF}
    procedure Synchronize();
    {$HINTS ON}

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Bind the language config. Must be called before LoadFromLexer.
    procedure SetConfig(const AConfig: TParseLangConfig);

    // Copy the token array from a fully tokenized lexer.
    // Returns False if ALexer is nil or has no tokens.
    function LoadFromLexer(const ALexer: TParseLexer): Boolean;

    // Parse the full token stream and return the root AST node.
    // The caller owns the returned node and is responsible for freeing it
    // (which frees the entire tree).
    function ParseTokens(): TParseASTNode;

    // TParseParserBase virtuals — implemented here

    // Returns the token at the current position (or a synthetic EOF token)
    function  CurrentToken(): TParseToken; override;

    // Returns the token at current + AOffset (or a synthetic EOF token)
    function  PeekToken(const AOffset: Integer = 1): TParseToken; override;

    // Advances past the current token and returns it
    function  Consume(): TParseToken; override;

    // If current token kind = AKind, consume it. Otherwise add an error.
    procedure Expect(const AKind: string); override;

    // Returns True if the current token kind matches AKind
    function  Check(const AKind: string): Boolean; override;

    // If Check() is True, consumes the token and returns True. Else False.
    function  Match(const AKind: string): Boolean; override;

    // Pratt expression parser — AMinPower is the caller's binding power floor
    function  ParseExpression(const AMinPower: Integer = 0): TParseASTNodeBase; override;

    // Parse one statement — dispatches via statement handlers or falls back
    // to expression-statement. Comments become first-class AST nodes here.
    function  ParseStatement(): TParseASTNodeBase; override;

    // Node creation — three overloads (kind comes from dispatch context or caller)
    function  CreateNode(): TParseASTNode; override;
    function  CreateNode(const ANodeKind: string): TParseASTNode; override;
    function  CreateNode(const ANodeKind: string;
      const AToken: TParseToken): TParseASTNode; override;

    // Returns the binding power of the currently dispatching infix operator
    function  CurrentInfixPower(): Integer; override;

    // Returns binding power - 1 for right-associative recursive calls
    function  CurrentInfixPowerRight(): Integer; override;

    // Returns the configured block-close kind string
    function  GetBlockCloseKind(): string; override;

    // Returns the configured statement terminator kind string
    function  GetStatementTerminatorKind(): string; override;
  end;

implementation

{ TParseParser }

constructor TParseParser.Create();
begin
  inherited;
  FConfig            := nil;
  FPos               := 0;
  FCurrentNodeKind   := '';
  FCurrentInfixPower := 0;
  SetLength(FTokens, 0);
end;

destructor TParseParser.Destroy();
begin
  inherited;
end;

procedure TParseParser.SetConfig(const AConfig: TParseLangConfig);
begin
  FConfig := AConfig;
end;

function TParseParser.LoadFromLexer(const ALexer: TParseLexer): Boolean;
begin
  Result := False;
  if ALexer = nil then
    Exit;
  if ALexer.GetTokenCount() = 0 then
    Exit;

  FTokens := ALexer.GetTokens();
  FPos    := 0;
  Result  := True;
end;

function TParseParser.IsAtEnd(): Boolean;
begin
  Result := FPos >= Length(FTokens);

  // Also treat EOF token kind as end-of-stream
  if not Result then
    Result := FTokens[FPos].Kind = FConfig.GetEOFKind();
end;

function TParseParser.MakeEOFToken(): TParseToken;
begin
  Result.Kind      := PARSE_KIND_EOF;
  Result.Text      := '';
  Result.Filename  := '';
  Result.Line      := 0;
  Result.Column    := 0;
  Result.EndLine   := 0;
  Result.EndColumn := 0;
end;

procedure TParseParser.Advance();
begin
  if FPos < Length(FTokens) then
    Inc(FPos);
end;

procedure TParseParser.AddError(const AToken: TParseToken;
  const AMsg: string);
begin
  if FErrors = nil then
    Exit;
  FErrors.Add(
    AToken.Filename,
    AToken.Line,
    AToken.Column,
    esError,
    'P0001',
    AMsg);
end;

procedure TParseParser.Synchronize();
var
  LTerminator: string;
  LBlockClose: string;
begin
  // Advance until we find a statement terminator, block close, or EOF.
  // This gives the parser a chance to continue after an error and report
  // further errors rather than cascading from one bad token.
  LTerminator := FConfig.GetStructural().StatementTerminator;
  LBlockClose := FConfig.GetStructural().BlockClose;

  while not IsAtEnd() do
  begin
    if (LTerminator <> '') and (CurrentToken().Kind = LTerminator) then
    begin
      Advance();  // consume the terminator and stop
      Exit;
    end;

    if (LBlockClose <> '') and (CurrentToken().Kind = LBlockClose) then
      Exit;  // leave block-close for the caller to consume

    Advance();
  end;
end;

function TParseParser.CurrentToken(): TParseToken;
begin
  if FPos < Length(FTokens) then
    Result := FTokens[FPos]
  else
    Result := MakeEOFToken();
end;

function TParseParser.PeekToken(const AOffset: Integer): TParseToken;
var
  LIndex: Integer;
begin
  LIndex := FPos + AOffset;
  if (LIndex >= 0) and (LIndex < Length(FTokens)) then
    Result := FTokens[LIndex]
  else
    Result := MakeEOFToken();
end;

function TParseParser.Consume(): TParseToken;
begin
  Result := CurrentToken();
  Advance();
end;

procedure TParseParser.Expect(const AKind: string);
var
  LToken: TParseToken;
begin
  LToken := CurrentToken();
  if LToken.Kind = AKind then
    Advance()
  else
    AddError(LToken,
      'Expected ' + AKind + ' but found ' + LToken.Kind +
      ' (' + LToken.Text + ')');
end;

function TParseParser.Check(const AKind: string): Boolean;
begin
  Result := CurrentToken().Kind = AKind;
end;

function TParseParser.Match(const AKind: string): Boolean;
begin
  if Check(AKind) then
  begin
    Advance();
    Result := True;
  end
  else
    Result := False;
end;

function TParseParser.CreateNode(): TParseASTNode;
begin
  // Uses the dispatch context set by the engine immediately before the
  // current handler was called. Token = current at time of creation.
  Result := TParseASTNode.CreateNode(FCurrentNodeKind, CurrentToken());
end;

function TParseParser.CreateNode(const ANodeKind: string): TParseASTNode;
begin
  // Explicit kind, token = current. Used for secondary/structural nodes
  // created within a handler (e.g. 'block.then', 'block.else').
  Result := TParseASTNode.CreateNode(ANodeKind, CurrentToken());
end;

function TParseParser.CreateNode(const ANodeKind: string;
  const AToken: TParseToken): TParseASTNode;
begin
  // Explicit kind and explicit token. Used when the handler has already
  // consumed past the token it wants to associate with the node.
  Result := TParseASTNode.CreateNode(ANodeKind, AToken);
end;

function TParseParser.CurrentInfixPower(): Integer;
begin
  // Returns the binding power of the currently dispatching infix entry.
  // Infix handlers call ParseExpression(AParser.CurrentInfixPower()) for
  // left-associative operators — same power stops equal-precedence operators.
  Result := FCurrentInfixPower;
end;

function TParseParser.CurrentInfixPowerRight(): Integer;
begin
  // Returns binding power - 1 for right-associative recursive calls.
  // Infix handlers call ParseExpression(AParser.CurrentInfixPowerRight())
  // to allow the right operand to bind at the same precedence level.
  Result := FCurrentInfixPower - 1;
end;

function TParseParser.GetBlockCloseKind(): string;
begin
  Result := FConfig.GetStructural().BlockClose;
end;

function TParseParser.GetStatementTerminatorKind(): string;
begin
  Result := FConfig.GetStructural().StatementTerminator;
end;

function TParseParser.ParseExpression(
  const AMinPower: Integer): TParseASTNodeBase;
var
  LToken:        TParseToken;
  LPrefixEntry:  TParsePrefixEntry;
  LInfixEntry:   TParseInfixEntry;
  LLeft:         TParseASTNodeBase;
begin
  Result := nil;

  if IsAtEnd() then
    Exit;

  LToken := CurrentToken();

  // Look up prefix handler — every expression must start with one
  if not FConfig.GetPrefixEntry(LToken.Kind, LPrefixEntry) then
  begin
    AddError(LToken, 'Unexpected token in expression: ' +
      LToken.Kind + ' (' + LToken.Text + ')');
    Advance();  // consume the bad token to avoid an infinite loop
    Exit;
  end;

  // Set dispatch context then call prefix handler
  FCurrentNodeKind   := LPrefixEntry.NodeKind;
  FCurrentInfixPower := 0;
  LLeft := LPrefixEntry.Handler(Self);

  // Pratt loop — keep consuming infix operators while binding power allows
  while not IsAtEnd() do
  begin
    LToken := CurrentToken();

    if not FConfig.GetInfixEntry(LToken.Kind, LInfixEntry) then
      Break;  // not a known infix operator at this position

    if LInfixEntry.BindingPower <= AMinPower then
      Break;  // caller's binding power wins — stop here

    // Set dispatch context then call infix handler
    FCurrentNodeKind   := LInfixEntry.NodeKind;
    FCurrentInfixPower := LInfixEntry.BindingPower;
    LLeft := LInfixEntry.Handler(Self, LLeft);
  end;

  Result := LLeft;
end;

function TParseParser.ParseStatement(): TParseASTNodeBase;
var
  LToken:       TParseToken;
  LStmtEntry:   TParseStatementEntry;
  LStructural:  TParseStructuralConfig;
  LCommentNode: TParseASTNode;
  LExprNode:    TParseASTNodeBase;
begin
  Result := nil;

  if IsAtEnd() then
    Exit;

  LToken      := CurrentToken();
  LStructural := FConfig.GetStructural();

  // Comments are first-class AST nodes — captured in document order.
  // The language author decides what to do with them via RegisterEmitter.
  if (LToken.Kind = FConfig.GetLineCommentKind()) or
     (LToken.Kind = FConfig.GetBlockCommentKind()) then
  begin
    // Dispatch context: kind = comment kind, no handler involved
    FCurrentNodeKind   := LToken.Kind;
    FCurrentInfixPower := 0;
    LCommentNode       := CreateNode();  // captures kind + current token
    Advance();
    Result := LCommentNode;
    Exit;
  end;

  // Statement handler dispatch — fully data-driven from LangConfig
  if FConfig.GetStatementEntry(LToken.Kind, LStmtEntry) then
  begin
    FCurrentNodeKind   := LStmtEntry.NodeKind;
    FCurrentInfixPower := 0;
    Result := LStmtEntry.Handler(Self);
    Exit;
  end;

  // Fallback — expression statement.
  // Parse an expression then expect the configured statement terminator.
  LExprNode := ParseExpression(0);
  if LStructural.StatementTerminator <> '' then
  begin
    if not IsAtEnd() then
      Expect(LStructural.StatementTerminator);
  end;
  Result := LExprNode;
end;

function TParseParser.ParseTokens(): TParseASTNode;
var
  LRoot:     TParseASTNode;
  LStmt:     TParseASTNodeBase;
  LFilename: string;
begin
  // Report the filename and token count so the user can see what is being parsed
  if Length(FTokens) > 0 then
    LFilename := FTokens[0].Filename
  else
    LFilename := '';
  Status('Parsing %s (%d tokens)...', [LFilename, Length(FTokens) - 1]);

  // Synthesise a root node from the very first token for location tracking
  FCurrentNodeKind   := 'program.root';
  FCurrentInfixPower := 0;
  LRoot := TParseASTNode.CreateNode('program.root', CurrentToken());

  while not IsAtEnd() do
  begin
    LStmt := ParseStatement();
    if LStmt <> nil then
      LRoot.AddChild(TParseASTNode(LStmt));
  end;

  Result := LRoot;
end;

end.
