{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

unit Parse.Common;

{$I Parse.Defines.inc}

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Rtti,
  System.Generics.Collections,
  Parse.Utils,
  Parse.Config;

const
  // Standard token kind strings shared across the entire toolkit.
  // Components and language files reference these rather than
  // repeating the literal strings.
  PARSE_KIND_EOF           = 'eof';
  PARSE_KIND_UNKNOWN       = 'unknown';
  PARSE_KIND_IDENTIFIER    = 'identifier';
  PARSE_KIND_INTEGER       = 'literal.integer';
  PARSE_KIND_REAL          = 'literal.real';
  PARSE_KIND_STRING        = 'literal.string';
  PARSE_KIND_CHAR          = 'literal.char';
  PARSE_KIND_COMMENT_LINE  = 'comment.line';
  PARSE_KIND_COMMENT_BLOCK = 'comment.block';
  PARSE_KIND_DIRECTIVE     = 'directive';

  // Attribute keys written by TParseSemantics onto AST nodes during analysis.
  // These are the contract between the semantic pass, the LSP, and CodeGen.
  // After Analyze() the AST is fully self-sufficient — LSP and CodeGen read
  // these attributes directly off nodes without calling back into the engine.

  // Written on every expression and identifier use-site node.
  // Value: string — the resolved type kind string for this expression.
  PARSE_ATTR_TYPE_KIND       = 'sem.type';

  // Written on every identifier use-site node.
  // Value: string — the declared name of the symbol this identifier resolves to.
  PARSE_ATTR_RESOLVED_SYMBOL = 'sem.symbol';

  // Written on every identifier use-site and call node.
  // Value: TObject (TParseASTNodeBase) — pointer to the declaring AST node.
  // Drives: go-to-definition, hover, rename, find-references (collect all
  // nodes whose PARSE_ATTR_DECL_NODE points to the same declaring node).
  PARSE_ATTR_DECL_NODE       = 'sem.decl_node';

  // Written on every declaration node (var, const, param, type, routine).
  // Value: string — storage class: 'local', 'global', 'param', 'const', 'type', 'routine'.
  // Drives: CodeGen storage allocation decisions.
  PARSE_ATTR_STORAGE_CLASS   = 'sem.storage';

  // Written on every declaration node AND every scope-opening node
  // (routine body, block, etc.).
  // Value: string — fully-qualified scope name this node belongs to / opens.
  // Drives: LSP completion (collect declarations whose PARSE_ATTR_SCOPE_NAME
  // matches the scope at cursor position).
  PARSE_ATTR_SCOPE_NAME      = 'sem.scope';

  // Written on every call expression node.
  // Value: string — the resolved overload symbol name.
  // Drives: CodeGen — emits the correct overloaded function name.
  PARSE_ATTR_CALL_RESOLVED   = 'sem.call_symbol';

  // Written on expression nodes that require an implicit type coercion.
  // Value: string — the target type kind string to coerce to.
  // Drives: CodeGen — emits the cast; never infers coercions independently.
  PARSE_ATTR_COERCE_TO       = 'sem.coerce';

type

  { TParseToken }
  TParseToken = record
    Kind:      string;   // e.g. 'keyword.if', 'op.assign', 'literal.integer'
    Text:      string;   // raw source text
    Filename:  string;
    Line:      Integer;
    Column:    Integer;
    EndLine:   Integer;
    EndColumn: Integer;
    Value:     TValue;   // parsed value for literals (integer, float, string)
  end;

  { TParseBlockCommentDef }
  TParseBlockCommentDef = record
    OpenStr:   string;
    CloseStr:  string;
    TokenKind: string;  // when non-empty, overrides the global block-comment kind
  end;

  { TParseStringStyleDef }
  TParseStringStyleDef = record
    OpenStr:     string;   // opening delimiter, e.g. '"', "'"
    CloseStr:    string;   // closing delimiter, e.g. '"', "'"
    TokenKind:   string;   // kind string to emit
    AllowEscape: Boolean;  // whether backslash escapes are processed
  end;

  { TParseOperatorDef }
  TParseOperatorDef = record
    Text:      string;   // operator text, e.g. ':=', '+', '...'
    TokenKind: string;   // kind string to emit
  end;

  { TParseAssociativity }
  TParseAssociativity = (aoLeft, aoRight);

  { TParseSourceFile }
  TParseSourceFile = (sfHeader, sfSource);

  // Base classes and the concrete AST node type.
  // Defined here so handler types, TParseParserBase, and TParseIRBase
  // can all reference them from one shared location with no circular deps.

  { TParseASTNodeBase
    Abstract base for the AST node. Codegen walks the tree via these virtuals
    without needing to know the concrete type. }
  TParseASTNodeBase = class(TParseErrorsObject)
  public
    function GetNodeKind(): string; virtual; abstract;
    function GetToken(): TParseToken; virtual; abstract;
    function ChildCount(): Integer; virtual; abstract;
    function GetChild(const AIndex: Integer): TParseASTNodeBase; virtual; abstract;
    function GetAttr(const AKey: string; out AValue: TValue): Boolean; virtual; abstract;
  end;

  { TParseASTNode
    Concrete AST node used by every language built on Parse(). Generic —
    no language-specific knowledge here. Node kind strings are set at
    construction time by the parser dispatch engine.

    Children are owned — freeing the root frees the entire tree.
    Attributes carry arbitrary TValue payloads keyed by plain strings. }
  TParseASTNode = class(TParseASTNodeBase)
  private
    FNodeKind:   string;
    FToken:      TParseToken;
    FChildren:   TObjectList<TParseASTNode>;  // OwnsObjects = True
    FAttributes: TDictionary<string, TValue>;

    // Recursive helper for Dump() — indents each level by ADepth * 2 spaces
    function DumpNode(const ADepth: Integer): string;

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Named constructor used by TParseParser.CreateNode() implementations
    class function CreateNode(const ANodeKind: string;
      const AToken: TParseToken): TParseASTNode;

    // TParseASTNodeBase virtuals implemented
    function GetNodeKind(): string; override;
    function GetToken(): TParseToken; override;
    function ChildCount(): Integer; override;
    function GetChild(const AIndex: Integer): TParseASTNodeBase; override;
    function GetAttr(const AKey: string; out AValue: TValue): Boolean; override;

    // Typed build API — used by handlers to construct the tree
    procedure AddChild(const ANode: TParseASTNode);
    procedure SetAttr(const AKey: string; const AValue: TValue);

    // Typed child accessor — returns TParseASTNode directly (avoids casting in handlers)
    function GetChildNode(const AIndex: Integer): TParseASTNode;

    // Debug — returns an indented tree dump of this node and all descendants
    function Dump(const AId: Integer = 0): string; override;
  end;

  { TParseParserBase
    Abstract base for the parser. Handlers receive TParseParserBase and call
    back into the parser via these virtuals to drive parsing. }
  TParseParserBase = class(TParseErrorsObject)
  public
    // Token navigation
    function  CurrentToken(): TParseToken; virtual; abstract;
    function  PeekToken(const AOffset: Integer = 1): TParseToken; virtual; abstract;
    function  Consume(): TParseToken; virtual; abstract;
    procedure Expect(const AKind: string); virtual; abstract;
    function  Check(const AKind: string): Boolean; virtual; abstract;
    function  Match(const AKind: string): Boolean; virtual; abstract;

    // Recursive parsing — called by handlers to drive sub-expressions and statements
    function  ParseExpression(const AMinPower: Integer = 0): TParseASTNodeBase; virtual; abstract;
    function  ParseStatement(): TParseASTNodeBase; virtual; abstract;

    // Node creation — three overloads so handlers never hardcode kind strings
    // Form 1: kind from dispatch context, token = current
    function  CreateNode(): TParseASTNode; overload; virtual; abstract;
    // Form 2: explicit kind, token = current (for secondary/structural nodes)
    function  CreateNode(const ANodeKind: string): TParseASTNode; overload; virtual; abstract;
    // Form 3: explicit kind, explicit token (when current has moved past the relevant token)
    function  CreateNode(const ANodeKind: string;
      const AToken: TParseToken): TParseASTNode; overload; virtual; abstract;

    // Binding power helpers — infix handlers never hardcode power values
    function  CurrentInfixPower(): Integer; virtual; abstract;
    function  CurrentInfixPowerRight(): Integer; virtual; abstract;

    // Structural config access — handlers write lang-agnostic loops
    function  GetBlockCloseKind(): string; virtual; abstract;
    function  GetStatementTerminatorKind(): string; virtual; abstract;
  end;

  { TParseIRBase
    Abstract base for the IR text emitter. Emit handlers receive this type
    so they can write C++23 text and walk child nodes without a circular
    dependency on Parse.IR. The full fluent builder API is declared here as
    abstract virtuals so emit handlers can use it without casting. }
  TParseIRBase = class(TParseErrorsObject)
  public
    // ---- Low-level primitives ----

    // Append indent + AText + newline
    procedure EmitLine(const AText: string; const ATarget: TParseSourceFile = sfSource); overload; virtual; abstract;
    // Formatted overload — AText is a Format() template, AArgs are the arguments
    procedure EmitLine(const AText: string; const AArgs: array of const; const ATarget: TParseSourceFile = sfSource); overload; virtual; abstract;

    // Append AText verbatim — no indent, no newline
    procedure Emit(const AText: string; const ATarget: TParseSourceFile = sfSource); overload; virtual; abstract;
    // Formatted overload — AText is a Format() template, AArgs are the arguments
    procedure Emit(const AText: string; const AArgs: array of const; const ATarget: TParseSourceFile = sfSource); overload; virtual; abstract;

    // Append AText truly verbatim (for $cppstart/$cpp escape hatch blocks)
    procedure EmitRaw(const AText: string; const ATarget: TParseSourceFile = sfSource); overload; virtual; abstract;
    // Formatted overload — AText is a Format() template, AArgs are the arguments
    procedure EmitRaw(const AText: string; const AArgs: array of const; const ATarget: TParseSourceFile = sfSource); overload; virtual; abstract;

    // Indentation control
    procedure IndentIn(); virtual; abstract;
    procedure IndentOut(); virtual; abstract;

    // AST dispatch — used by TParseEmitHandler callbacks
    procedure EmitNode(const ANode: TParseASTNodeBase); virtual; abstract;
    procedure EmitChildren(const ANode: TParseASTNodeBase); virtual; abstract;

    // ---- Top-level declarations (fluent) ----

    // #include <AName> or #include "AName"
    function Include(const AHeaderName: string;
      const ATarget: TParseSourceFile = sfHeader): TParseIRBase; virtual; abstract;

    // struct AName { ... };
    function Struct(const AStructName: string;
      const ATarget: TParseSourceFile = sfHeader): TParseIRBase; virtual; abstract;

    // Field inside a Struct context
    function AddField(const AFieldName, AFieldType: string): TParseIRBase; virtual; abstract;

    // };  — closes Struct
    function EndStruct(): TParseIRBase; virtual; abstract;

    // constexpr auto AName = AValueExpr;
    function DeclConst(const AConstName, AConstType, AValueExpr: string;
      const ATarget: TParseSourceFile = sfHeader): TParseIRBase; virtual; abstract;

    // static AType AName = AInitExpr;
    function Global(const AGlobalName, AGlobalType, AInitExpr: string;
      const ATarget: TParseSourceFile = sfSource): TParseIRBase; virtual; abstract;

    // using AAlias = AOriginal;
    function Using(const AAlias, AOriginal: string;
      const ATarget: TParseSourceFile = sfHeader): TParseIRBase; virtual; abstract;

    // namespace AName {
    function Namespace(const ANamespaceName: string;
      const ATarget: TParseSourceFile = sfHeader): TParseIRBase; virtual; abstract;

    // } // namespace
    function EndNamespace(
      const ATarget: TParseSourceFile = sfHeader): TParseIRBase; virtual; abstract;

    // extern "C" AReturnType AName(AParams...);
    function ExternC(const AFuncName, AReturnType: string;
      const AParams: TArray<TArray<string>>;
      const ATarget: TParseSourceFile = sfHeader): TParseIRBase; virtual; abstract;

    // ---- Function builder (fluent) ----

    // AReturnType AName(...)  {
    function Func(const AFuncName, AReturnType: string): TParseIRBase; virtual; abstract;

    // Parameter inside Func context
    function Param(const AParamName, AParamType: string): TParseIRBase; virtual; abstract;

    // }  — closes Func
    function EndFunc(): TParseIRBase; virtual; abstract;

    // ---- Statement methods (fluent) ----

    // Local variable:  AType AName;
    function DeclVar(const AVarName, AVarType: string): TParseIRBase; overload; virtual; abstract;
    // Local variable:  AType AName = AInitExpr;
    function DeclVar(const AVarName, AVarType, AInitExpr: string): TParseIRBase; overload; virtual; abstract;

    // Assignment:  ALhs = AExpr;
    function Assign(const ALhs, AExpr: string): TParseIRBase; virtual; abstract;

    // Expression lhs assignment:  ATargetExpr = AValueExpr;
    function AssignTo(const ATargetExpr, AValueExpr: string): TParseIRBase; virtual; abstract;

    // Statement-form call:  AFunc(AArgs...);
    function Call(const AFuncName: string;
      const AArgs: TArray<string>): TParseIRBase; virtual; abstract;

    // Verbatim C++ statement line
    function Stmt(const ARawText: string): TParseIRBase; overload; virtual; abstract;
    // Formatted overload — ARawText is a Format() template, AArgs are the arguments
    function Stmt(const ARawText: string; const AArgs: array of const): TParseIRBase; overload; virtual; abstract;

    // return;
    function Return(): TParseIRBase; overload; virtual; abstract;
    // return AExpr;
    function Return(const AExpr: string): TParseIRBase; overload; virtual; abstract;

    // if (ACond) {
    function IfStmt(const ACondExpr: string): TParseIRBase; virtual; abstract;

    // } else if (ACond) {
    function ElseIfStmt(const ACondExpr: string): TParseIRBase; virtual; abstract;

    // } else {
    function ElseStmt(): TParseIRBase; virtual; abstract;

    // }  — closes if/else chain
    function EndIf(): TParseIRBase; virtual; abstract;

    // while (ACond) {
    function WhileStmt(const ACondExpr: string): TParseIRBase; virtual; abstract;

    // }  — closes while
    function EndWhile(): TParseIRBase; virtual; abstract;

    // for (auto AVar = AInit; ACond; AStep) {
    function ForStmt(const AVarName, AInitExpr, ACondExpr,
      AStepExpr: string): TParseIRBase; virtual; abstract;

    // }  — closes for
    function EndFor(): TParseIRBase; virtual; abstract;

    // break;
    function BreakStmt(): TParseIRBase; virtual; abstract;

    // continue;
    function ContinueStmt(): TParseIRBase; virtual; abstract;

    // Emit a blank line
    function BlankLine(
      const ATarget: TParseSourceFile = sfSource): TParseIRBase; virtual; abstract;

    // ---- Expression builders (return string — C++23 text fragments) ----

    // Literals
    function Lit(const AValue: Integer): string; overload; virtual; abstract;
    function Lit(const AValue: Int64): string; overload; virtual; abstract;
    function Float(const AValue: Double): string; virtual; abstract;
    function Str(const AValue: string): string; virtual; abstract;
    function Bool(const AValue: Boolean): string; virtual; abstract;
    function Null(): string; virtual; abstract;

    // Variable / member access
    function Get(const AVarName: string): string; virtual; abstract;
    function Field(const AObj, AMember: string): string; virtual; abstract;
    function Deref(const APtr, AMember: string): string; overload; virtual; abstract;
    function Deref(const APtr: string): string; overload; virtual; abstract;
    function AddrOf(const AVarName: string): string; virtual; abstract;
    function Index(const AArr, AIndexExpr: string): string; virtual; abstract;
    function Cast(const ATypeName, AExpr: string): string; virtual; abstract;

    // Expression-form call:  AFunc(AArgs...)  — returns string, no semicolon
    function Invoke(const AFuncName: string;
      const AArgs: TArray<string>): string; virtual; abstract;

    // Arithmetic
    function Add(const ALeft, ARight: string): string; virtual; abstract;
    function Sub(const ALeft, ARight: string): string; virtual; abstract;
    function Mul(const ALeft, ARight: string): string; virtual; abstract;
    function DivExpr(const ALeft, ARight: string): string; virtual; abstract;
    function ModExpr(const ALeft, ARight: string): string; virtual; abstract;
    function Neg(const AExpr: string): string; virtual; abstract;

    // Comparison
    function Eq(const ALeft, ARight: string): string; virtual; abstract;
    function Ne(const ALeft, ARight: string): string; virtual; abstract;
    function Lt(const ALeft, ARight: string): string; virtual; abstract;
    function Le(const ALeft, ARight: string): string; virtual; abstract;
    function Gt(const ALeft, ARight: string): string; virtual; abstract;
    function Ge(const ALeft, ARight: string): string; virtual; abstract;

    // Logical
    function AndExpr(const ALeft, ARight: string): string; virtual; abstract;
    function OrExpr(const ALeft, ARight: string): string; virtual; abstract;
    function NotExpr(const AExpr: string): string; virtual; abstract;

    // Bitwise
    function BitAnd(const ALeft, ARight: string): string; virtual; abstract;
    function BitOr(const ALeft, ARight: string): string; virtual; abstract;
    function BitXor(const ALeft, ARight: string): string; virtual; abstract;
    function BitNot(const AExpr: string): string; virtual; abstract;
    function ShlExpr(const ALeft, ARight: string): string; virtual; abstract;
    function ShrExpr(const ALeft, ARight: string): string; virtual; abstract;

    // Key/value context store for emitter handlers to share state across
    // handler calls (e.g. tracking the current function name).
    procedure SetContext(const AKey, AValue: string); virtual; abstract;
    function  GetContext(const AKey: string;
      const ADefault: string = ''): string; virtual; abstract;
  end;

  { TParseCodeGenBase
    Abstract base for the code generation orchestrator. The compiler pipeline
    calls Generate() to walk the enriched AST and produce output. Concrete
    implementations (TParseCodeGen for C++23, future backends for C/LLVM/JS)
    extend this base. }
  TParseCodeGenBase = class(TParseErrorsObject)
  public
    function Generate(const ARoot: TParseASTNodeBase): Boolean; virtual; abstract;
  end;

  { TParseSemanticBase
    Abstract base for the semantic engine. Semantic handlers registered via
    TParseLangConfig.RegisterSemanticRule receive TParseSemanticBase and call
    back via these virtuals to drive analysis, manage scope, and declare/resolve
    symbols. Handlers write enrichment attributes onto nodes using the
    PARSE_ATTR_* constants — the AST is the data store, not this base class. }
  TParseSemanticBase = class(TParseErrorsObject)
  public
    // Push a named scope level. AOpenToken is the token that opened the scope
    // (e.g. 'begin', '{') — recorded on the scope for LSP range queries.
    procedure PushScope(const AScopeName: string;
      const AOpenToken: TParseToken); virtual; abstract;

    // Pop the current scope back to its parent. ACloseToken is the token
    // that closed the scope — recorded on the scope for LSP range queries.
    procedure PopScope(const ACloseToken: TParseToken); virtual; abstract;

    // Declare a symbol in the current scope.
    // Returns False if a symbol with AName already exists in the current scope
    // (duplicate declaration — the handler should report an error).
    function DeclareSymbol(const AName: string;
      const ANode: TParseASTNodeBase): Boolean; virtual; abstract;

    // Look up a name in the current scope and all parent scopes.
    // Returns True and sets ANode to the declaring AST node if found.
    // Returns False (ANode = nil) if not found.
    function LookupSymbol(const AName: string;
      out ANode: TParseASTNodeBase): Boolean; virtual; abstract;

    // Look up a name in the current scope only (does not walk up the chain).
    // Returns True and sets ANode to the declaring AST node if found.
    // Returns False (ANode = nil) if not found in the current scope.
    function LookupSymbolLocal(const AName: string;
      out ANode: TParseASTNodeBase): Boolean; virtual; abstract;

    // Recurse into a single node — dispatch its handler or auto-visit children.
    // Handlers call this to drive traversal into child nodes they care about.
    procedure VisitNode(const ANode: TParseASTNodeBase); virtual; abstract;

    // Recurse into all children of ANode in order.
    // Handlers use this when they want the engine to walk an unstructured block.
    procedure VisitChildren(const ANode: TParseASTNodeBase); virtual; abstract;

    // Report a semantic error at the source location of ANode.
    // ACode is a short error code string (e.g. 'S200'), AMsg is human-readable.
    procedure AddSemanticError(const ANode: TParseASTNodeBase;
      const ACode, AMsg: string); virtual; abstract;

    // Returns True if currently inside a named scope (function/procedure body).
    // False at the root/global scope level.
    function IsInsideRoutine(): Boolean; virtual; abstract;
  end;

  // Handler types
  // Defined here so both TParseLangConfig and the concrete components can
  // reference them from a single shared location.

  TParseStatementHandler =
    reference to function(AParser: TParseParserBase): TParseASTNodeBase;

  TParsePrefixHandler =
    reference to function(AParser: TParseParserBase): TParseASTNodeBase;

  TParseInfixHandler =
    reference to function(AParser: TParseParserBase;
      ALeft: TParseASTNodeBase): TParseASTNodeBase;

  TParseEmitHandler =
    reference to procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase);

  // Semantic handler — called by the engine for each registered node kind.
  // The handler enriches ANode by writing PARSE_ATTR_* attributes onto it,
  // declares/resolves symbols via ASem, and drives traversal of child nodes
  // by calling ASem.VisitNode() or ASem.VisitChildren() as appropriate.
  TParseSemanticHandler =
    reference to procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase);

  // Type compatibility function — registered once per language via
  // TParseLangConfig.RegisterTypeCompat(). Called by the engine when it
  // needs to determine whether AFromType is assignable to AToType.
  // Returns True if compatible. If an implicit coercion is needed,
  // ACoerceTo is set to the target type kind string (the engine then
  // writes PARSE_ATTR_COERCE_TO onto the node). If no coercion is needed,
  // ACoerceTo is set to empty string.
  TParseTypeCompatFunc =
    reference to function(const AFromType, AToType: string;
      out ACoerceTo: string): Boolean;

  // ExprToString callback — passed to overrides to delegate child nodes.
  TParseExprToStringFunc =
    reference to function(const ANode: TParseASTNodeBase): string;

  // ExprToString override for a specific node kind.
  TParseExprOverride =
    reference to function(const ANode: TParseASTNodeBase;
      const ADefault: TParseExprToStringFunc): string;

  // Config file persistence base

  { TParseConfigFileObject
    Base class for any Parse() component that needs TOML config file
    persistence. Handles the filename, file existence checks, and
    TParseConfig lifecycle. Subclasses override DoLoadConfig and
    DoSaveConfig to read and write their specific fields. }
  TParseConfigFileObject = class(TParseBaseObject)
  private
    FConfigFilename: string;
  protected
    // Called by LoadConfig() after successfully loading the TOML file.
    // Subclasses override this to read their fields from AConfig.
    procedure DoLoadConfig(const AConfig: TParseConfig); virtual;

    // Called by SaveConfig() with a fresh TParseConfig ready to populate.
    // Subclasses override this to write their fields into AConfig.
    procedure DoSaveConfig(const AConfig: TParseConfig); virtual;
  public
    constructor Create(); override;

    // Set the TOML file path used by LoadConfig() and SaveConfig()
    procedure SetConfigFilename(const AFilename: string);
    function  GetConfigFilename(): string;

    // Overrides TParseBaseObject virtuals.
    // LoadConfig: checks filename, loads TOML file, delegates to DoLoadConfig.
    // SaveConfig: checks filename, delegates to DoSaveConfig, saves TOML file.
    procedure LoadConfig(); override;
    procedure SaveConfig(); override;
  end;

implementation

{ TParseASTNode }

constructor TParseASTNode.Create();
begin
  inherited;
  FNodeKind   := '';
  FChildren   := TObjectList<TParseASTNode>.Create(True);  // OwnsObjects = True
  FAttributes := TDictionary<string, TValue>.Create();
end;

destructor TParseASTNode.Destroy();
begin
  FreeAndNil(FAttributes);
  FreeAndNil(FChildren);
  inherited;
end;

class function TParseASTNode.CreateNode(const ANodeKind: string;
  const AToken: TParseToken): TParseASTNode;
begin
  Result           := TParseASTNode.Create();
  Result.FNodeKind := ANodeKind;
  Result.FToken    := AToken;
end;

function TParseASTNode.GetNodeKind(): string;
begin
  Result := FNodeKind;
end;

function TParseASTNode.GetToken(): TParseToken;
begin
  Result := FToken;
end;

function TParseASTNode.ChildCount(): Integer;
begin
  Result := FChildren.Count;
end;

function TParseASTNode.GetChild(const AIndex: Integer): TParseASTNodeBase;
begin
  if (AIndex >= 0) and (AIndex < FChildren.Count) then
    Result := FChildren[AIndex]
  else
    Result := nil;
end;

function TParseASTNode.GetAttr(const AKey: string;
  out AValue: TValue): Boolean;
begin
  Result := FAttributes.TryGetValue(AKey, AValue);
end;

procedure TParseASTNode.AddChild(const ANode: TParseASTNode);
begin
  if ANode <> nil then
    FChildren.Add(ANode);
end;

procedure TParseASTNode.SetAttr(const AKey: string; const AValue: TValue);
begin
  if AKey <> '' then
    FAttributes.AddOrSetValue(AKey, AValue);
end;

function TParseASTNode.GetChildNode(const AIndex: Integer): TParseASTNode;
begin
  if (AIndex >= 0) and (AIndex < FChildren.Count) then
    Result := FChildren[AIndex]
  else
    Result := nil;
end;

function TParseASTNode.DumpNode(const ADepth: Integer): string;
var
  LIndent: string;
  LPair:   TPair<string, TValue>;
  LI:      Integer;
  LChild:  TParseASTNode;
begin
  LIndent := StringOfChar(' ', ADepth * 2);

  // Node kind and triggering token location
  Result := LIndent + '[' + FNodeKind + ']';
  if FToken.Filename <> '' then
    Result := Result + ' @ ' + FToken.Filename +
              '(' + IntToStr(FToken.Line) + ':' + IntToStr(FToken.Column) + ')';
  if FToken.Text <> '' then
    Result := Result + ' text=' + FToken.Text;
  Result := Result + sLineBreak;

  // Attributes
  for LPair in FAttributes do
    Result := Result + LIndent + '  attr.' + LPair.Key +
              ' = ' + LPair.Value.ToString() + sLineBreak;

  // Children — recursive
  for LI := 0 to FChildren.Count - 1 do
  begin
    LChild := FChildren[LI];
    Result := Result + LChild.DumpNode(ADepth + 1);
  end;
end;

function TParseASTNode.Dump(const AId: Integer): string;
begin
  Result := DumpNode(0);
end;

{ TParseConfigFileObject }

constructor TParseConfigFileObject.Create();
begin
  inherited;
  FConfigFilename := '';
end;

procedure TParseConfigFileObject.SetConfigFilename(const AFilename: string);
begin
  FConfigFilename := AFilename;
end;

function TParseConfigFileObject.GetConfigFilename(): string;
begin
  Result := FConfigFilename;
end;

procedure TParseConfigFileObject.DoLoadConfig(const AConfig: TParseConfig);
begin
  // Base does nothing — subclasses override to read their specific fields
end;

procedure TParseConfigFileObject.DoSaveConfig(const AConfig: TParseConfig);
begin
  // Base does nothing — subclasses override to write their specific fields
end;

procedure TParseConfigFileObject.LoadConfig();
var
  LConfig: TParseConfig;
begin
  if FConfigFilename = '' then
    Exit;

  if not TFile.Exists(FConfigFilename) then
    Exit;

  LConfig := TParseConfig.Create();
  try
    if LConfig.LoadFromFile(FConfigFilename) then
      DoLoadConfig(LConfig);
  finally
    LConfig.Free();
  end;
end;

procedure TParseConfigFileObject.SaveConfig();
var
  LConfig: TParseConfig;
begin
  if FConfigFilename = '' then
    Exit;

  LConfig := TParseConfig.Create();
  try
    DoSaveConfig(LConfig);
    LConfig.SaveToFile(FConfigFilename);
  finally
    LConfig.Free();
  end;
end;

end.
