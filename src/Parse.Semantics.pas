{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

unit Parse.Semantics;

{$I Parse.Defines.inc}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Rtti,
  Parse.Utils,
  Parse.Common,
  Parse.LangConfig;

type

  // Forward declarations
  TParseScope     = class;
  TParseSemantics = class;

  { TParseSymbol }
  TParseSymbol = record
    SymbolName: string;                         // declared identifier text (key in scope)
    DeclKind:   string;                         // node kind of the declaring AST node
    DeclNode:   TParseASTNodeBase;              // the declaring AST node (not owned here)
    References: TList<TParseASTNodeBase>;       // all use-site nodes (owned by TParseSemantics)
  end;

  { TParseScope }
  TParseScope = class
  private
    FScopeName:  string;
    FParent:     TParseScope;                        // not owned
    FChildren:   TObjectList<TParseScope>;           // owned
    FSymbols:    TDictionary<string, TParseSymbol>;  // name → symbol record
    FOpenToken:  TParseToken;
    FCloseToken: TParseToken;

  public
    constructor Create(const AScopeName: string; const AParent: TParseScope);
    destructor Destroy(); override;

    // Declare a symbol in this scope.
    // Returns False if a symbol with ASymbol.SymbolName already exists here.
    function Declare(const ASymbol: TParseSymbol): Boolean;

    // Look up a name in this scope only — does not walk the parent chain.
    function LookupLocal(const AName: string;
      out ASymbol: TParseSymbol): Boolean;

    // Walk up the scope chain from this scope to find a name.
    function Lookup(const AName: string;
      out ASymbol: TParseSymbol): Boolean;

    // Returns True if this scope's source range contains AFile:ALine:ACol.
    // Used by FindScopeAt to locate the deepest active scope at a position.
    function ContainsPosition(const AFile: string;
      const ALine, ACol: Integer): Boolean;

    // Add a child scope (called by TParseSemantics.PushScope)
    procedure AddChild(const AChild: TParseScope);

    property ScopeName:   string      read FScopeName;
    property ParentScope: TParseScope read FParent;
    property OpenToken:   TParseToken  read FOpenToken  write FOpenToken;
    property CloseToken:  TParseToken  read FCloseToken write FCloseToken;
    property Children:    TObjectList<TParseScope>           read FChildren;
    property Symbols:     TDictionary<string, TParseSymbol>  read FSymbols;
  end;

  { TParseSemantics }
  TParseSemantics = class(TParseSemanticBase)
  private
    FConfig:      TParseLangConfig;          // not owned — caller manages lifetime
    FRootScope:   TParseScope;               // owned — root of the scope tree
    FScopeStack:  TList<TParseScope>;        // active scope chain (not owned entries)
    FNodeIndex:   TList<TParseASTNodeBase>;  // all visited nodes in document order
    FRefLists:    TObjectList<TList<TParseASTNodeBase>>;  // owns all reference lists

    // Return the innermost currently active scope
    function CurrentScope(): TParseScope;

    // Walk one node — dispatch handler if registered, else auto-visit children.
    // Also appends ANode to FNodeIndex.
    procedure DoVisitNode(const ANode: TParseASTNodeBase);

    // Recursive scope search — deepest scope whose range contains AFile:ALine:ACol
    function FindScopeAt(const AScope: TParseScope; const AFile: string;
      const ALine, ACol: Integer): TParseScope;

    // Collect all symbols visible from AScope upward into AResult
    procedure CollectScopeSymbols(const AScope: TParseScope;
      const AResult: TList<TParseSymbol>);

    // Report a semantic error using FErrors (inherited from TParseErrorsObject)
    procedure ReportError(const ANode: TParseASTNodeBase;
      const ACode, AMsg: string);

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Bind the language config. Must be called before Analyze().
    procedure SetConfig(const AConfig: TParseLangConfig);

    // Walk ARoot, dispatch semantic handlers, enrich nodes with PARSE_ATTR_*
    // attributes in place. Returns True if analysis completed with no errors.
    // TParseSemantics retains scope tree and node index after this call.
    function Analyze(const ARoot: TParseASTNodeBase): Boolean;

    // -------------------------------------------------------------------------
    // LSP query API — available after Analyze()
    // These are acceleration-structure queries over the enriched AST.
    // LSP and CodeGen do NOT need to call these — the enriched AST is
    // self-sufficient. These exist only for efficient position-based lookup.
    // -------------------------------------------------------------------------

    // Find the innermost AST node whose source range contains AFile:ALine:ACol.
    // Returns nil if no node covers that position.
    function FindNodeAt(const AFile: string;
      const ALine, ACol: Integer): TParseASTNodeBase;

    // Return all symbols visible in scope at AFile:ALine:ACol.
    // Walks from the deepest matching scope up to global.
    // Caller owns the returned TArray.
    function GetSymbolsInScopeAt(const AFile: string;
      const ALine, ACol: Integer): TArray<TParseSymbol>;

    // Look up a symbol by name across all scopes (global symbol search).
    // Returns True and sets ASymbol if found.
    function FindSymbol(const AName: string;
      out ASymbol: TParseSymbol): Boolean;

    // -------------------------------------------------------------------------
    // TParseSemanticBase virtuals — called by semantic handlers during Analyze()
    // -------------------------------------------------------------------------

    // Push a new named scope level. AOpenToken is the token that opened it
    // (e.g. 'begin', '{') — stored for LSP scope range queries.
    procedure PushScope(const AScopeName: string;
      const AOpenToken: TParseToken); override;

    // Pop the current scope back to its parent. ACloseToken is stored
    // on the scope for LSP range queries.
    procedure PopScope(const ACloseToken: TParseToken); override;

    // Declare a symbol in the current scope.
    // Returns False if AName is already declared in the current scope.
    function DeclareSymbol(const AName: string;
      const ANode: TParseASTNodeBase): Boolean; override;

    // Look up AName in current scope and all parents.
    // Returns True and sets ANode to the declaring node if found.
    function LookupSymbol(const AName: string;
      out ANode: TParseASTNodeBase): Boolean; override;

    // Look up AName in current scope only.
    // Returns True and sets ANode to the declaring node if found.
    function LookupSymbolLocal(const AName: string;
      out ANode: TParseASTNodeBase): Boolean; override;

    // Recurse into a single node — dispatches its handler or auto-visits children.
    // Handlers call this to drive traversal into specific child nodes.
    procedure VisitNode(const ANode: TParseASTNodeBase); override;

    // Recurse into all children of ANode in document order.
    // Handlers use this when they want the engine to walk a block of children.
    procedure VisitChildren(const ANode: TParseASTNodeBase); override;

    // Report a semantic error at the source location of ANode.
    procedure AddSemanticError(const ANode: TParseASTNodeBase;
      const ACode, AMsg: string); override;

    // Returns True if currently inside a named scope (function/procedure body).
    // False at the root/global scope level.
    function IsInsideRoutine(): Boolean; override;
  end;

implementation

{ TParseScope }
constructor TParseScope.Create(const AScopeName: string;
  const AParent: TParseScope);
begin
  inherited Create();
  FScopeName := AScopeName;
  FParent    := AParent;
  FChildren  := TObjectList<TParseScope>.Create(True);  // owns children
  FSymbols   := TDictionary<string, TParseSymbol>.Create();
end;

destructor TParseScope.Destroy();
begin
  FreeAndNil(FSymbols);
  FreeAndNil(FChildren);
  inherited;
end;

function TParseScope.Declare(const ASymbol: TParseSymbol): Boolean;
begin
  // Refuse duplicate declarations within the same scope level.
  if FSymbols.ContainsKey(ASymbol.SymbolName) then
  begin
    Result := False;
    Exit;
  end;
  FSymbols.Add(ASymbol.SymbolName, ASymbol);
  Result := True;
end;

function TParseScope.LookupLocal(const AName: string;
  out ASymbol: TParseSymbol): Boolean;
begin
  Result := FSymbols.TryGetValue(AName, ASymbol);
end;

function TParseScope.Lookup(const AName: string;
  out ASymbol: TParseSymbol): Boolean;
var
  LScope: TParseScope;
begin
  // Walk up the parent chain until found or we run out of scopes.
  LScope := Self;
  while LScope <> nil do
  begin
    if LScope.FSymbols.TryGetValue(AName, ASymbol) then
    begin
      Result := True;
      Exit;
    end;
    LScope := LScope.FParent;
  end;
  Result := False;
end;

function TParseScope.ContainsPosition(const AFile: string;
  const ALine, ACol: Integer): Boolean;
var
  LOpenLine:  Integer;
  LOpenCol:   Integer;
  LCloseLine: Integer;
  LCloseCol:  Integer;
begin
  // If the scope has no recorded open/close positions it cannot contain anything.
  if (FOpenToken.Filename = '') and (FCloseToken.Filename = '') then
  begin
    Result := False;
    Exit;
  end;

  // Match the file — scope ranges are per-file.
  if (FOpenToken.Filename <> '') and (FOpenToken.Filename <> AFile) then
  begin
    Result := False;
    Exit;
  end;

  LOpenLine  := FOpenToken.Line;
  LOpenCol   := FOpenToken.Column;
  LCloseLine := FCloseToken.Line;
  LCloseCol  := FCloseToken.Column;

  // ALine:ACol must fall within [open, close] inclusive.
  if ALine < LOpenLine then
  begin
    Result := False;
    Exit;
  end;
  if (ALine = LOpenLine) and (ACol < LOpenCol) then
  begin
    Result := False;
    Exit;
  end;
  if LCloseLine > 0 then
  begin
    if ALine > LCloseLine then
    begin
      Result := False;
      Exit;
    end;
    if (ALine = LCloseLine) and (ACol > LCloseCol) then
    begin
      Result := False;
      Exit;
    end;
  end;

  Result := True;
end;

procedure TParseScope.AddChild(const AChild: TParseScope);
begin
  FChildren.Add(AChild);
end;

// =============================================================================
// TParseSemantics
// =============================================================================

constructor TParseSemantics.Create();
begin
  inherited;
  FConfig     := nil;
  FRootScope  := TParseScope.Create('global', nil);
  FScopeStack := TList<TParseScope>.Create();
  FNodeIndex  := TList<TParseASTNodeBase>.Create();
  FRefLists   := TObjectList<TList<TParseASTNodeBase>>.Create(True);

  // Global scope is always the bottom of the stack.
  FScopeStack.Add(FRootScope);
end;

destructor TParseSemantics.Destroy();
begin
  FreeAndNil(FRefLists);
  FreeAndNil(FNodeIndex);
  FreeAndNil(FScopeStack);
  FreeAndNil(FRootScope);
  inherited;
end;

procedure TParseSemantics.SetConfig(const AConfig: TParseLangConfig);
begin
  FConfig := AConfig;
end;

function TParseSemantics.CurrentScope(): TParseScope;
begin
  // The stack always has at least the global scope on it.
  Result := FScopeStack[FScopeStack.Count - 1];
end;

procedure TParseSemantics.ReportError(const ANode: TParseASTNodeBase;
  const ACode, AMsg: string);
var
  LToken: TParseToken;
begin
  if FErrors = nil then
    Exit;
  if ANode <> nil then
  begin
    LToken := ANode.GetToken();
    FErrors.Add(
      LToken.Filename,
      LToken.Line,
      LToken.Column,
      esError,
      ACode,
      AMsg);
  end
  else
    FErrors.Add(esError, ACode, AMsg, []);
end;

// -----------------------------------------------------------------------------
// TParseSemanticBase virtuals
// -----------------------------------------------------------------------------

procedure TParseSemantics.PushScope(const AScopeName: string;
  const AOpenToken: TParseToken);
var
  LParent:   TParseScope;
  LNewScope: TParseScope;
begin
  LParent   := CurrentScope();
  LNewScope := TParseScope.Create(AScopeName, LParent);
  LNewScope.OpenToken := AOpenToken;

  // The scope tree (rooted at FRootScope) owns all child scopes via
  // TObjectList — register the new scope as a child of its parent.
  LParent.AddChild(LNewScope);

  FScopeStack.Add(LNewScope);
end;

procedure TParseSemantics.PopScope(const ACloseToken: TParseToken);
begin
  if FScopeStack.Count <= 1 then
    Exit;  // never pop the global scope

  // Record the close token on the scope before popping — needed by LSP
  // range queries after analysis completes.
  CurrentScope().CloseToken := ACloseToken;

  FScopeStack.Delete(FScopeStack.Count - 1);
end;

function TParseSemantics.DeclareSymbol(const AName: string;
  const ANode: TParseASTNodeBase): Boolean;
var
  LSymbol:  TParseSymbol;
  LRefList: TList<TParseASTNodeBase>;
begin
  // Create a fresh reference list owned by FRefLists so it survives scope
  // destruction and remains accessible for find-references / rename queries.
  LRefList := TList<TParseASTNodeBase>.Create();
  FRefLists.Add(LRefList);

  LSymbol.SymbolName := AName;
  LSymbol.DeclNode   := ANode;
  LSymbol.References := LRefList;

  // Record the declaring node's node kind if available.
  if ANode <> nil then
    LSymbol.DeclKind := ANode.GetNodeKind()
  else
    LSymbol.DeclKind := '';

  Result := CurrentScope().Declare(LSymbol);
end;

function TParseSemantics.LookupSymbol(const AName: string;
  out ANode: TParseASTNodeBase): Boolean;
var
  LSymbol: TParseSymbol;
begin
  ANode := nil;
  if CurrentScope().Lookup(AName, LSymbol) then
  begin
    ANode  := LSymbol.DeclNode;
    Result := True;
  end
  else
    Result := False;
end;

function TParseSemantics.LookupSymbolLocal(const AName: string;
  out ANode: TParseASTNodeBase): Boolean;
var
  LSymbol: TParseSymbol;
begin
  ANode := nil;
  if CurrentScope().LookupLocal(AName, LSymbol) then
  begin
    ANode  := LSymbol.DeclNode;
    Result := True;
  end
  else
    Result := False;
end;

procedure TParseSemantics.VisitNode(const ANode: TParseASTNodeBase);
begin
  if ANode = nil then
    Exit;
  DoVisitNode(ANode);
end;

procedure TParseSemantics.VisitChildren(const ANode: TParseASTNodeBase);
var
  LI:    Integer;
  LChild: TParseASTNodeBase;
begin
  if ANode = nil then
    Exit;
  for LI := 0 to ANode.ChildCount() - 1 do
  begin
    LChild := ANode.GetChild(LI);
    if LChild <> nil then
      DoVisitNode(LChild);
  end;
end;

procedure TParseSemantics.AddSemanticError(const ANode: TParseASTNodeBase;
  const ACode, AMsg: string);
begin
  ReportError(ANode, ACode, AMsg);
end;

function TParseSemantics.IsInsideRoutine(): Boolean;
begin
  // Root scope is always at index 0. Inside a routine, the stack has >= 2 entries.
  Result := FScopeStack.Count > 1;
end;

// -----------------------------------------------------------------------------
// Core walk engine
// -----------------------------------------------------------------------------

procedure TParseSemantics.DoVisitNode(const ANode: TParseASTNodeBase);
var
  LHandler: TParseSemanticHandler;
  LI:       Integer;
  LChild:   TParseASTNodeBase;
begin
  if ANode = nil then
    Exit;

  // Record every node in document order — enables position-based LSP queries.
  FNodeIndex.Add(ANode);

  // Dispatch: if the language registered a handler for this node kind, call it.
  // The handler is fully responsible for:
  //   - Writing PARSE_ATTR_* enrichment attributes onto ANode
  //   - Declaring/resolving symbols via DeclareSymbol / LookupSymbol
  //   - Driving traversal of child nodes via VisitNode / VisitChildren
  //   - Pushing/popping scopes where the node introduces a new scope level
  if (FConfig <> nil) and
     FConfig.GetSemanticHandler(ANode.GetNodeKind(), LHandler) then
  begin
    LHandler(ANode, Self);
    Exit;  // handler owns its subtree — do not auto-visit children
  end;

  // No handler registered for this node kind — transparently auto-visit all
  // children. This ensures that unregistered structural nodes (e.g. 'program.root',
  // arbitrary wrapper nodes) are walked through without requiring boilerplate.
  for LI := 0 to ANode.ChildCount() - 1 do
  begin
    LChild := ANode.GetChild(LI);
    if LChild <> nil then
      DoVisitNode(LChild);
  end;
end;

// -----------------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------------

function TParseSemantics.Analyze(const ARoot: TParseASTNodeBase): Boolean;
begin
  // Report the filename and AST node count so the user can see what is being analyzed
  if ARoot <> nil then
    Status('Analyzing %s (%d nodes)...', [ARoot.GetToken().Filename, ARoot.ChildCount()])
  else
    Status('Analyzing...');
  // Reset state from any previous run so TParseSemantics can be reused.
  FNodeIndex.Clear();
  FRefLists.Clear();

  // Reinitialise the scope tree — free the old root and create a fresh one.
  FreeAndNil(FRootScope);
  FRootScope := TParseScope.Create('global', nil);
  FScopeStack.Clear();
  FScopeStack.Add(FRootScope);

  // Walk the entire AST, enriching nodes in place.
  if ARoot <> nil then
    DoVisitNode(ARoot);

  // Analysis succeeded if no errors were reported.
  Result := (FErrors = nil) or (FErrors.ErrorCount() = 0);
end;

// -----------------------------------------------------------------------------
// LSP query API (acceleration-structure queries over the enriched AST)
// -----------------------------------------------------------------------------

function TParseSemantics.FindNodeAt(const AFile: string;
  const ALine, ACol: Integer): TParseASTNodeBase;
var
  LI:        Integer;
  LNode:     TParseASTNodeBase;
  LToken:    TParseToken;
  LBest:     TParseASTNodeBase;
  LBestLine: Integer;
  LBestCol:  Integer;
begin
  // Scan FNodeIndex for the node whose token position is the closest match
  // that does not exceed ALine:ACol. Nodes are in document order so we find
  // the last one that is at or before the cursor.
  LBest     := nil;
  LBestLine := 0;
  LBestCol  := 0;

  for LI := 0 to FNodeIndex.Count - 1 do
  begin
    LNode  := FNodeIndex[LI];
    LToken := LNode.GetToken();

    if LToken.Filename <> AFile then
      Continue;

    // Node must start at or before the cursor position.
    if LToken.Line > ALine then
      Continue;
    if (LToken.Line = ALine) and (LToken.Column > ACol) then
      Continue;

    // Among qualifying nodes, prefer the one with the latest (deepest) start.
    if (LToken.Line > LBestLine) or
       ((LToken.Line = LBestLine) and (LToken.Column > LBestCol)) then
    begin
      LBest     := LNode;
      LBestLine := LToken.Line;
      LBestCol  := LToken.Column;
    end;
  end;

  Result := LBest;
end;

function TParseSemantics.FindScopeAt(const AScope: TParseScope;
  const AFile: string; const ALine, ACol: Integer): TParseScope;
var
  LI:    Integer;
  LChild: TParseScope;
  LDeep:  TParseScope;
begin
  Result := AScope;

  // Try to find a deeper matching child scope.
  for LI := 0 to AScope.Children.Count - 1 do
  begin
    LChild := AScope.Children[LI];
    if LChild.ContainsPosition(AFile, ALine, ACol) then
    begin
      // Recurse — the deepest matching scope wins.
      LDeep := FindScopeAt(LChild, AFile, ALine, ACol);
      if LDeep <> nil then
        Result := LDeep;
      Exit;
    end;
  end;
end;

procedure TParseSemantics.CollectScopeSymbols(const AScope: TParseScope;
  const AResult: TList<TParseSymbol>);
var
  LPair:  TPair<string, TParseSymbol>;
  LScope: TParseScope;
begin
  // Walk from AScope up to global, collecting all symbols.
  LScope := AScope;
  while LScope <> nil do
  begin
    for LPair in LScope.Symbols do
      AResult.Add(LPair.Value);
    LScope := LScope.ParentScope;
  end;
end;

function TParseSemantics.GetSymbolsInScopeAt(const AFile: string;
  const ALine, ACol: Integer): TArray<TParseSymbol>;
var
  LScope:  TParseScope;
  LResult: TList<TParseSymbol>;
begin
  LScope  := FindScopeAt(FRootScope, AFile, ALine, ACol);
  LResult := TList<TParseSymbol>.Create();
  try
    CollectScopeSymbols(LScope, LResult);
    Result := LResult.ToArray();
  finally
    LResult.Free();
  end;
end;

function TParseSemantics.FindSymbol(const AName: string;
  out ASymbol: TParseSymbol): Boolean;
begin
  // Search from the global root scope down the chain.
  Result := FRootScope.Lookup(AName, ASymbol);
end;

end.
