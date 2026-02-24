# Language Authoring Guide — Parse()™

This guide explains how to define a programming language using the Parse() toolkit. It is written for developers who want to understand *why* things work the way they do, not just copy-paste patterns. Read it top to bottom the first time. After that it works as a reference.

## The Big Picture

Parse() takes a source file and produces a native binary. The path looks like this:

```
Source Text
    │
    ▼
┌─────────┐   token stream    ┌─────────┐   AST        ┌───────────┐
│  Lexer  │ ────────────────► │ Parser  │ ───────────► │ Semantics │
└─────────┘                   └─────────┘              └───────────┘
                                                             │
                                                 enriched AST (PARSE_ATTR_*)
                                                             │
                                                             ▼
                                                      ┌───────────┐
                                                      │  CodeGen  │ ──► .h + .cpp
                                                      └───────────┘          │
                                                                             ▼
                                                                        ┌──────────┐
                                                                        │   Zig    │ ──► native binary
                                                                        └──────────┘
```

Every stage is driven by a single object: **`TParse`**. You configure it once and it drives all four stages. Nothing in the toolkit has hardcoded knowledge of any language. The config is the language.

## The Three Surfaces

`TParse` has three configuration surfaces. Think of them as three separate contracts:

| Surface | What it controls | Who reads it |
|---|---|---|
| **Lexer** | What tokens exist: keywords, operators, string styles, comments, number formats | `TParseLexer` |
| **Grammar** | How tokens combine into AST nodes: prefix/infix/statement handlers | `TParseParser` |
| **Emit** | How AST nodes become C++23 text | `TParseCodeGen` |

There is a fourth optional surface — **Semantics** — for languages that need scope analysis, symbol resolution, and type checking. It is not required to get a language working, but you will need it for anything beyond toy programs.

You configure all surfaces through one fluent chain:

```delphi
LParse.Config()
  .AddKeyword(...)        // lexer surface
  .AddOperator(...)       // lexer surface
  .RegisterStatement(...) // grammar surface
  .RegisterEmitter(...)   // emit surface
  .RegisterSemanticRule(...)  // semantic surface
```

Everything chains. Every method returns `TParse` so you can keep calling.

## Token Kinds: The Contract String

The single most important concept in Parse() is the **token kind string**. It is a plain string like `'keyword.if'` or `'op.plus'` or `'literal.integer'`. It is the contract that connects every stage together.

- The **lexer** assigns a kind string to every token it produces.
- The **parser** dispatches handlers based on kind strings.
- The **semantic engine** dispatches handlers based on AST node kind strings.
- The **codegen** dispatches emit handlers based on AST node kind strings.

You invent the kind strings. There is no required naming convention enforced by the toolkit, but the convention used throughout the examples and built-in language files is:

```
category.name
```

Examples:
- `keyword.if`, `keyword.while`, `keyword.begin`
- `op.plus`, `op.assign`, `op.neq`
- `delimiter.semicolon`, `delimiter.lparen`
- `literal.integer`, `literal.real`, `literal.string`
- `expr.binary`, `expr.unary`, `expr.call`
- `stmt.if`, `stmt.while`, `stmt.var_decl`
- `type.integer`, `type.string`, `type.boolean`

**The kind string is how the stages talk to each other.** When the lexer emits a token with kind `'keyword.if'`, the parser looks up a statement handler registered for `'keyword.if'`. When that handler builds an AST node with kind `'stmt.if'`, the codegen looks up an emit handler registered for `'stmt.if'`. Each stage just looks up a string.

## Stage 1: The Lexer Surface

The lexer converts raw source text into a flat stream of tokens. You configure what the lexer recognises.

### Keywords

A keyword is any identifier that has special meaning. You register it with the text it matches and the kind string to emit:

```delphi
LParse.Config()
  .AddKeyword('if',    'keyword.if')
  .AddKeyword('while', 'keyword.while')
  .AddKeyword('begin', 'keyword.begin')
  .AddKeyword('end',   'keyword.end');
```

By default keyword matching is case-insensitive. For a case-sensitive language like Lua:

```delphi
LParse.Config()
  .CaseSensitiveKeywords(True);
```

**How it works:** The lexer scans an identifier, then looks it up in the keyword table. If found, it emits the registered kind. If not found, it emits the identifier kind (`'identifier'` by default). The identifier kind can be renamed with `SetIdentifierKind`.

### Operators and Delimiters

Operators are non-identifier, non-whitespace character sequences. The lexer uses **longest-match** automatically — you do not need to order them, but declaring multi-character operators before single-character ones makes the intent obvious:

```delphi
LParse.Config()
  .AddOperator(':=', 'op.assign')   // must match before ':'
  .AddOperator('<>', 'op.neq')
  .AddOperator('<=', 'op.lte')
  .AddOperator('>=', 'op.gte')
  .AddOperator('=',  'op.eq')
  .AddOperator('<',  'op.lt')
  .AddOperator('>',  'op.gt')
  .AddOperator(':',  'delimiter.colon')
  .AddOperator(';',  'delimiter.semicolon')
  .AddOperator('(',  'delimiter.lparen')
  .AddOperator(')',  'delimiter.rparen')
  .AddOperator(',',  'delimiter.comma');
```

**Important:** The operator list is automatically sorted longest-first internally, so `':='` will always win over `':'`. You are safe registering them in any order.

### String Literals

You tell the lexer what constitutes a string by giving it an open delimiter, a close delimiter, the kind to emit, and whether backslash escapes should be processed:

```delphi
// Pascal: single-quoted, no backslash escapes
LParse.Config()
  .AddStringStyle('''', '''', PARSE_KIND_STRING, False);

// Lua: both double and single quoted, with escapes
LParse.Config()
  .AddStringStyle('"',  '"',  PARSE_KIND_STRING, True)
  .AddStringStyle('''', '''', PARSE_KIND_STRING, True);
```

`PARSE_KIND_STRING` is the constant `'literal.string'`. You can emit any kind string you like — if you need to distinguish string types, use different kinds:

```delphi
.AddStringStyle('"',  '"',  'literal.string',      True)
.AddStringStyle('`',  '`',  'literal.raw_string',  False)
```

When `AAllowEscape` is `True`, the lexer processes these escape sequences inside the string: `\n`, `\t`, `\r`, `\0`, `\\`, `\'`, `\"`, `\xHH`.

### Comments

```delphi
// Line comments: everything from prefix to end of line
LParse.Config()
  .AddLineComment('//')    // C-style
  .AddLineComment('--');   // Lua-style

// Block comments: everything between open and close
LParse.Config()
  .AddBlockComment('{', '}')      // Pascal
  .AddBlockComment('(*', '*)')    // Pascal alternate
  .AddBlockComment('--[[', ']]'); // Lua block comment
```

Comments become first-class tokens in the stream with kinds `'comment.line'` and `'comment.block'` (or whatever you set with `SetIntegerKind`/`SetRealKind`). The parser captures them as AST nodes so emit handlers can include them in output if desired. If you do not register an emitter for comment nodes, they are silently skipped.

### Number Literals

Integer and real number scanning is built in. The lexer produces `'literal.integer'` or `'literal.real'` tokens automatically. You extend the number system with prefixes for hex and binary:

```delphi
LParse.Config()
  .SetHexPrefix('0x',  'literal.integer')   // C-style: 0xFF
  .SetHexPrefix('$',   'literal.integer')   // Pascal-style: $FF
  .SetBinaryPrefix('0b', 'literal.integer'); // binary: 0b1010
```

Multiple hex and binary prefixes are all valid at the same time. The kind string can be anything — typically you use `'literal.integer'` for all numeric bases since they all produce an integer value.

### Structural Tokens

Three tokens have special meaning to the parser engine itself:

```delphi
LParse.Config()
  .SetStatementTerminator('delimiter.semicolon')  // end of statement
  .SetBlockOpen('keyword.begin')                  // start of a block
  .SetBlockClose('keyword.end');                  // end of a block
```

These are optional. Set `SetStatementTerminator('')` for languages like Lua where statements are separated by newlines or nothing at all. The parser uses these during error recovery (Synchronize) and block parsing helpers.

## Stage 2: The Grammar Surface

The grammar surface is where you define what the token stream *means*. It uses a technique called **Pratt parsing** (top-down operator precedence). The idea is simple once you see it:

Every token has a potential **prefix** meaning (it starts an expression) and a potential **infix** meaning (it continues an expression on the left). You register handlers for each role.

### Understanding Prefix vs Infix

Take the minus sign `-`:
- In `-5`, the minus is a **prefix** — it starts an expression (unary negation).
- In `a - b`, the minus is an **infix** — it sits between two expressions (subtraction).

The same token can be both. You register it twice, once as prefix, once as infix.

Take `if`:
- `if condition then ...` — this is a **statement**, not an expression. Statements do not return a value and are handled separately.

### The Three Handler Types

**Prefix handler** — called when a token appears at the start of an expression:
```delphi
RegisterPrefix(ATokenKind, ANodeKind, AHandler)
```
The handler receives `AParser: TParseParserBase` and must return a `TParseASTNodeBase`. The current token when the handler is called is the token that triggered the dispatch.

**Infix handler** — called when a token appears after an expression:
```delphi
RegisterInfixLeft(ATokenKind, ABindingPower, ANodeKind, AHandler)
RegisterInfixRight(ATokenKind, ABindingPower, ANodeKind, AHandler)
```
The handler receives `AParser` and `ALeft: TParseASTNodeBase` (the already-parsed left side). Left-associative means `a + b + c` parses as `(a + b) + c`. Right-associative means `a := b := c` parses as `a := (b := c)`, which is correct for assignment.

**Statement handler** — called when a token appears at the start of a line/statement:
```delphi
RegisterStatement(ATokenKind, ANodeKind, AHandler)
```
The handler receives `AParser` and returns a `TParseASTNodeBase`. The parser calls statement handlers before trying to parse an expression, so `'keyword.if'` triggers your if-handler before the expression machinery gets a chance.

### Binding Power (Precedence)

Binding power is just a number. Higher number = tighter binding = higher precedence. Here is a typical table:

| Power | Operators |
|---|---|
| 2 | `:=` (assignment, right-assoc) |
| 10 | `or` |
| 15 | `and` |
| 20 | `+`, `-` |
| 30 | `*`, `/`, `div`, `mod` |
| 40 | `=`, `<>`, `<`, `>`, `<=`, `>=` |
| 50 | unary `-`, `not` |

The exact numbers do not matter — only the relative order does. Use gaps so you can insert operators later.

### Building a Node

Inside every handler you build an AST node. The pattern is always:

1. Create a node with `AParser.CreateNode()`.
2. Store relevant data on it as attributes with `LNode.SetAttr(key, value)`.
3. Consume tokens with `AParser.Consume()` or `AParser.Expect(kind)`.
4. Recursively parse sub-expressions or sub-statements and add them as children.
5. Return the node.

**`AParser.CreateNode()`** — creates a node using the kind string and current token that the dispatch engine set up before calling your handler. This is almost always what you want.

**`AParser.CreateNode(ANodeKind)`** — creates a node with an explicit kind, token = current. Use this for secondary structural nodes you create inside a handler.

**`AParser.CreateNode(ANodeKind, AToken)`** — explicit kind and explicit token. Use this when you have already consumed the token you want to associate with the node.

### Parsing Sub-Expressions

Inside a handler, to parse a sub-expression:

```delphi
LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
```

The `0` means "parse at minimum binding power" — accept any expression. To enforce that the right side binds tighter (left-associative infix):

```delphi
// In a left-assoc infix handler for '+':
LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPower())));
```

For right-associative (assignment):

```delphi
// In a right-assoc infix handler for ':=':
LNode.AddChild(TParseASTNode(AParser.ParseExpression(AParser.CurrentInfixPowerRight())));
```

`CurrentInfixPower()` returns the power of the currently dispatching operator. `CurrentInfixPowerRight()` returns it minus 1, which allows the right side to bind at the same level (right-assoc).

### Complete Example: Binary Operator

This is the shortest useful pattern — registering `+` as a left-associative binary operator that builds an `expr.binary` node:

```delphi
LParse.Config().RegisterInfixLeft('op.plus', 20, 'expr.binary',
  function(AParser: TParseParserBase;
    ALeft: TParseASTNodeBase): TParseASTNodeBase
  var
    LNode: TParseASTNode;
  begin
    LNode := AParser.CreateNode();               // kind='expr.binary', token=current '+'
    LNode.SetAttr('op', TValue.From<string>('+')); // store the C++ operator symbol
    AParser.Consume();                           // consume the '+' token
    LNode.AddChild(TParseASTNode(ALeft));        // left operand
    LNode.AddChild(TParseASTNode(
      AParser.ParseExpression(AParser.CurrentInfixPower()))); // right operand
    Result := LNode;
  end);
```

There is a convenience method for exactly this pattern:

```delphi
LParse.Config().RegisterBinaryOp('op.plus', 20, '+');
```

`RegisterBinaryOp` creates the `expr.binary` node, stores the C++ operator in the `'op'` attribute, and handles left-associativity. Use it for all standard arithmetic and comparison operators.

### Complete Example: Unary Prefix Operator

Unary negation — the `-` token as a prefix:

```delphi
LParse.Config().RegisterPrefix('op.minus', 'expr.unary',
  function(AParser: TParseParserBase): TParseASTNodeBase
  var
    LNode: TParseASTNode;
  begin
    LNode := AParser.CreateNode();
    LNode.SetAttr('op', TValue.From<string>('-'));
    AParser.Consume();   // consume '-'
    LNode.AddChild(TParseASTNode(AParser.ParseExpression(50)));
    Result := LNode;
  end);
```

The `50` passed to `ParseExpression` is the binding power floor — only tokens with binding power greater than 50 will be consumed as part of the right operand. Since unary operators have the highest precedence, using 50 (higher than any binary operator) ensures the operand is tightly bound.

### Complete Example: Statement Handler

A `while` statement in Pascal:

```delphi
LParse.Config().RegisterStatement('keyword.while', 'stmt.while',
  function(AParser: TParseParserBase): TParseASTNodeBase
  var
    LNode: TParseASTNode;
  begin
    LNode := AParser.CreateNode();   // kind='stmt.while', token='while'
    AParser.Consume();               // consume 'while'
    // Parse the condition expression
    LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
    // Expect 'do'
    AParser.Expect('keyword.do');
    // Parse the body — could be a single statement or a begin/end block
    LNode.AddChild(TParseASTNode(AParser.ParseStatement()));
    Result := LNode;
  end);
```

`AParser.Expect(kind)` consumes the token if it matches, otherwise records a parse error and continues (error recovery). It does not throw. `AParser.Match(kind)` is similar but returns `True`/`False` without recording an error, useful for optional tokens.

### Literal Prefixes

The four universal literal kinds (identifier, integer, real, string) are so common that there is a convenience method:

```delphi
LParse.Config().RegisterLiteralPrefixes();
```

This registers prefix handlers for `'identifier'`, `'literal.integer'`, `'literal.real'`, and `'literal.string'` that simply create a node, consume the token, and return it. Call this before registering any other prefix handlers.

### Parsing a Block of Statements

A begin/end or {/} block is just repeated `ParseStatement()` calls until the block-close token:

```delphi
LParse.Config().RegisterStatement('keyword.begin', 'stmt.begin_block',
  function(AParser: TParseParserBase): TParseASTNodeBase
  var
    LNode:  TParseASTNode;
    LStmt:  TParseASTNodeBase;
  begin
    LNode := AParser.CreateNode();
    AParser.Consume();  // consume 'begin'
    while not AParser.Check(AParser.GetBlockCloseKind()) and
          not AParser.Check(PARSE_KIND_EOF) do
    begin
      LStmt := AParser.ParseStatement();
      if LStmt <> nil then
        LNode.AddChild(TParseASTNode(LStmt));
    end;
    AParser.Expect(AParser.GetBlockCloseKind());  // consume 'end'
    Result := LNode;
  end);
```

`AParser.GetBlockCloseKind()` returns whatever you set with `SetBlockClose`. Using it rather than hardcoding `'keyword.end'` keeps handlers portable.

### Parsing Argument Lists

A comma-separated list bounded by parentheses:

```delphi
// After consuming the function name and '(' ...
while not AParser.Check('delimiter.rparen') and
      not AParser.Check(PARSE_KIND_EOF) do
begin
  LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
  if not AParser.Match('delimiter.comma') then
    Break;
end;
AParser.Expect('delimiter.rparen');
```

## The AST: What You Are Building

Every handler builds AST nodes. The result is a tree where:
- The root is a `'program.root'` node added automatically by the parser.
- Its children are top-level statements.
- Each statement node has children for its sub-parts (condition, body, else-branch, etc.).
- Expression nodes have children for their operands.

A node has:
- A **kind string** — what kind of thing it is.
- A **token** — the source location (file, line, column) and the triggering text.
- **Children** — ordered list of child nodes (owned, freed with parent).
- **Attributes** — a string-keyed dictionary of `TValue` values. This is where you store semantic data, operator symbols, declaration names, etc.

### Attributes

You set attributes in handlers:

```delphi
LNode.SetAttr('op', TValue.From<string>('+'));
LNode.SetAttr('decl.name', TValue.From<string>('MyVar'));
LNode.SetAttr('for.dir', TValue.From<string>('to'));
```

You read them in emitters or semantic handlers:

```delphi
var
  LAttr: TValue;
  LName: string;
begin
  if ANode.GetAttr('decl.name', LAttr) then
    LName := LAttr.AsString;
```

`GetAttr` returns `False` if the key does not exist. Always check the return value.

Attribute names are your invention. Use a `category.name` convention for clarity.

### Built-in Semantic Attributes

After the semantic pass runs, the engine writes standard attributes onto nodes. You read these in emit handlers:

| Attribute | Value | Meaning |
|---|---|---|
| `PARSE_ATTR_TYPE_KIND` (`'sem.type'`) | string | Resolved type kind of this expression |
| `PARSE_ATTR_RESOLVED_SYMBOL` (`'sem.symbol'`) | string | The declared name this identifier resolves to |
| `PARSE_ATTR_DECL_NODE` (`'sem.decl_node'`) | TObject | Pointer to the declaring AST node |
| `PARSE_ATTR_STORAGE_CLASS` (`'sem.storage'`) | string | `'local'`, `'global'`, `'param'`, `'const'`, `'routine'` |
| `PARSE_ATTR_SCOPE_NAME` (`'sem.scope'`) | string | Fully-qualified scope name |
| `PARSE_ATTR_CALL_RESOLVED` (`'sem.call_symbol'`) | string | Resolved overload symbol name |
| `PARSE_ATTR_COERCE_TO` (`'sem.coerce'`) | string | Target type for implicit coercion |

## Stage 3: The Semantic Surface (Optional)

The semantic stage walks the enriched AST after parsing, resolves symbols, checks types, and writes `PARSE_ATTR_*` attributes onto nodes. After the semantic pass, the AST is self-sufficient — the codegen reads everything it needs directly off the nodes.

You register a handler for each node kind that needs semantic processing:

```delphi
LParse.Config().RegisterSemanticRule('stmt.var_decl',
  procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
  var
    LName: TValue;
  begin
    ANode.GetAttr('decl.name', LName);
    // Declare the variable in the current scope
    if not ASem.DeclareSymbol(LName.AsString, ANode) then
      ASem.AddSemanticError(ANode, 'S100', 'Duplicate declaration: ' + LName.AsString);
    // Write storage class
    if ASem.IsInsideRoutine() then
      TParseASTNode(ANode).SetAttr(PARSE_ATTR_STORAGE_CLASS, TValue.From<string>('local'))
    else
      TParseASTNode(ANode).SetAttr(PARSE_ATTR_STORAGE_CLASS, TValue.From<string>('global'));
    // Visit children so sub-expressions are also walked
    ASem.VisitChildren(ANode);
  end);
```

**Key rule:** When your handler has finished processing the node, you must drive traversal of any children you care about. If you do nothing, the children are not visited. If you want the engine to visit all children automatically, call `ASem.VisitChildren(ANode)`. If you have already visited specific children yourself, do not call `VisitChildren` on them again.

For node kinds you do not register a handler for, the engine automatically visits all children. So if you only care about declarations and calls, you only need handlers for those — everything else gets walked through transparently.

### Scope Management

```delphi
// Push a named scope (e.g. entering a function body)
ASem.PushScope('MyFunction', AOpenToken);

// ... visit children ...

// Pop back to parent scope
ASem.PopScope(ACloseToken);
```

`AOpenToken` and `ACloseToken` are the tokens that delimit the scope (e.g. `'begin'` and `'end'`). They are stored on the scope for LSP position queries.

### Symbol Declaration and Lookup

```delphi
// Declare — returns False if already declared in current scope
ASem.DeclareSymbol(LName, ANode);

// Lookup — searches current scope and all parents
var LDeclNode: TParseASTNodeBase;
if ASem.LookupSymbol(LName, LDeclNode) then
  // found — LDeclNode is the declaring node
else
  ASem.AddSemanticError(ANode, 'S200', 'Undefined: ' + LName);
```

### Type Compatibility

If your language needs type checking, register a compatibility function:

```delphi
LParse.Config().RegisterTypeCompat(
  function(const AFromType, AToType: string;
    out ACoerceTo: string): Boolean
  begin
    ACoerceTo := '';
    if AFromType = AToType then
    begin
      Result := True;
      Exit;
    end;
    // integer is implicitly assignable to double
    if (AFromType = 'type.integer') and (AToType = 'type.double') then
    begin
      ACoerceTo := 'type.double';   // engine writes PARSE_ATTR_COERCE_TO
      Result := True;
      Exit;
    end;
    Result := False;
  end);
```

When `ACoerceTo` is non-empty, the engine writes `PARSE_ATTR_COERCE_TO` onto the node. The emit handler then reads this attribute to emit an appropriate C++ cast.

## Stage 4: The Emit Surface

The emit surface is where AST nodes become C++23 text. You register an emitter for each node kind that produces output:

```delphi
LParse.Config().RegisterEmitter('stmt.while',
  procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
  var
    LCondStr: string;
  begin
    LCondStr := LParse.Config().ExprToString(ANode.GetChild(0)); // condition
    AGen.WhileStmt(LCondStr);
    AGen.EmitNode(ANode.GetChild(1));   // body
    AGen.EndWhile();
  end);
```

`AGen.EmitNode(AChild)` dispatches the child node through the same emitter registry — it finds the emitter registered for the child's kind and calls it. `AGen.EmitChildren(ANode)` does this for all children in order.

### The IR Fluent API

The `TParseIRBase` fluent builder generates well-formed C++23. The key methods:

**Functions:**
```delphi
AGen.Func('MyFunc', 'int32_t');      // int32_t MyFunc(
AGen.Param('x', 'int32_t');         //   int32_t x,
AGen.Param('y', 'int32_t');         //   int32_t y
                                     // ) {
AGen.DeclVar('result', 'int32_t', '0');  //   int32_t result = 0;
AGen.Assign('result', 'x + y');          //   result = x + y;
AGen.Return(AGen.Get('result'));          //   return result;
AGen.EndFunc();                          // }
```

**Control flow:**
```delphi
AGen.IfStmt('x > 0');       // if (x > 0) {
AGen.Stmt('do_something();');//   do_something();
AGen.ElseStmt();             // } else {
AGen.Stmt('do_other();');    //   do_other();
AGen.EndIf();                // }

AGen.WhileStmt('i < 10');   // while (i < 10) {
AGen.EmitChildren(ABody);   //   ...body...
AGen.EndWhile();             // }

AGen.ForStmt('i', '0', 'i < count', 'i++');  // for (auto i = 0; i < count; i++) {
AGen.EmitNode(ABody);                          //   ...body...
AGen.EndFor();                                 // }
```

**Variables and assignments:**
```delphi
AGen.DeclVar('name', 'std::string');              // std::string name;
AGen.DeclVar('count', 'int32_t', '0');            // int32_t count = 0;
AGen.Assign('count', '42');                       // count = 42;
AGen.AssignTo('obj.field', 'expr');               // obj.field = expr;
```

**Statements:**
```delphi
AGen.Stmt('std::cout << "hello" << std::endl;');  // verbatim statement
AGen.Call('printf', ['"%d\n"', 'x']);             // printf("%d\n", x);
AGen.Return('42');                                // return 42;
AGen.Return();                                    // return;
```

**Top-level declarations:**
```delphi
AGen.Include('iostream');                          // #include <iostream>
AGen.Include('mylib.h', sfHeader);                 // #include "mylib.h" in header
AGen.Global('g_count', 'int32_t', '0');            // static int32_t g_count = 0;
AGen.DeclConst('MAX', 'int32_t', '100');           // constexpr auto MAX = 100;
AGen.Using('String', 'std::string');               // using String = std::string;
```

**Emitting to header vs source:**
Most methods default to `sfSource` (the .cpp file). Pass `sfHeader` to send output to the .h file:

```delphi
AGen.EmitLine('// Forward declaration', sfHeader);
AGen.DeclConst('VERSION', 'int32_t', '1', sfHeader);
```

**Expression string helpers (return strings, not lines):**
```delphi
AGen.Lit(42)                 // '42'
AGen.Lit(Int64(1000000))     // '1000000'
AGen.Float(3.14)             // '3.14'
AGen.Str('hello')            // '"hello"'
AGen.Bool(True)              // 'true'
AGen.Get('myVar')            // 'myVar'
AGen.Field('obj', 'member')  // 'obj.member'
AGen.Invoke('fn', ['a','b']) // 'fn(a, b)'
AGen.Add('x', 'y')           // 'x + y'
AGen.Eq('a', 'b')            // 'a == b'
AGen.Cast('int32_t', 'expr') // 'static_cast<int32_t>(expr)'
```

### ExprToString: Converting Expression Nodes to C++ Strings

Many statement emitters need a C++ expression string built from a sub-expression node, without emitting it as a statement. Use `LParse.Config().ExprToString(ANode)`:

```delphi
// In a 'stmt.if' emitter:
LCondStr := LParse.Config().ExprToString(ANode.GetChild(0));
AGen.IfStmt(LCondStr);
```

`ExprToString` recursively converts an AST expression node to a C++ string. It handles the built-in expression kinds automatically:
- `expr.identifier` → the identifier text (after name mangling)
- `expr.integer`, `expr.real` → the literal text
- `expr.string` → double-quoted string
- `expr.bool` → `true` / `false`
- `expr.unary` → `op + child`
- `expr.binary` → `left op right`
- `expr.grouped` → `(child)`
- `expr.call` → `name(args...)`

For node kinds that need different rendering (e.g. Pascal single-quoted strings need re-quoting as double-quoted), register an override:

```delphi
LParse.Config().RegisterExprOverride('expr.string',
  function(const ANode: TParseASTNodeBase;
    const ADefault: TParseExprToStringFunc): string
  var
    LText:  string;
    LInner: string;
  begin
    LText  := ANode.GetToken().Text;
    // Strip Pascal single quotes and re-wrap in C++ double quotes
    LInner := Copy(LText, 2, Length(LText) - 2);
    LInner := LInner.Replace(#39#39, #39);   // '' → ' inside Pascal strings
    Result := '"' + LInner + '"';
  end);
```

The second parameter `ADefault` is the original `ExprToString` function. You can call it for children: `ADefault(ANode.GetChild(0))`.

### The Context Store

Emit handlers sometimes need to share state across calls — for example, knowing the current function name to emit a correct `return` statement. Use the context store:

```delphi
// In the function header emitter:
AGen.SetContext('current_func', LFuncName);

// In a return statement emitter inside the same function:
LFuncName := AGen.GetContext('current_func', '');
```

The context store is a flat string-to-string dictionary on the IR object, persisted for the lifetime of the `Generate()` call.

## Type Inference Surface

For dynamically-typed languages (like Lua) where types are inferred from literals and call sites rather than declared, Parse() has a built-in scanning system.

Register which literal node kinds map to which type kinds:

```delphi
LParse.Config()
  .AddLiteralType('expr.integer', 'type.integer')
  .AddLiteralType('expr.real',    'type.double')
  .AddLiteralType('expr.string',  'type.string')
  .AddLiteralType('expr.bool',    'type.boolean');
```

Register which node kinds are declaration sites (where a variable gets its type from its initialiser):

```delphi
LParse.Config()
  .AddDeclKind('stmt.local_decl')
  .AddDeclKind('stmt.global_assign');
```

Register which node kinds are call sites (so parameter types can be inferred from arguments):

```delphi
LParse.Config()
  .AddCallKind('expr.call')
  .AddCallKind('stmt.call');
```

Then in your semantic handler, call `ScanAll` before walking the AST to populate the type maps:

```delphi
LParse.Config().ScanAll(ARoot);

// Now you can look up inferred types:
var LTypes: TDictionary<string, string>;
LTypes := LParse.Config().GetDeclTypes();
if LTypes.TryGetValue('myVar', LTypeKind) then
  // LTypeKind = 'type.integer' etc.
```

`InferLiteralType(ANode)` gives you the type kind for a specific literal node directly using the `AddLiteralType` table.

## Name Mangling and TypeToIR

### Name Mangling

If your language uses identifiers that cannot appear as C++ identifiers directly (e.g. keywords, dashes, non-ASCII), register a name mangler:

```delphi
LParse.Config().SetNameMangler(
  function(const AName: string): string
  begin
    // Prefix all user identifiers to avoid clashing with C++ keywords
    Result := 'np_' + AName;
  end);
```

`ExprToString` calls `MangleName` automatically for `expr.identifier` nodes. Emit handlers call it explicitly when needed:

```delphi
LMangledName := LParse.Config().MangleName(LRawName);
```

If no mangler is registered, `MangleName` returns the name unchanged.

### TypeToIR

`TypeToIR` maps a type kind string (`'type.integer'`) to a C++ type string (`'int32_t'`). Register a function to override the defaults:

```delphi
LParse.Config().SetTypeToIR(
  function(const ATypeKind: string): string
  begin
    if ATypeKind = 'type.integer' then
      Result := 'int32_t'
    else if ATypeKind = 'type.double' then
      Result := 'double'
    else if ATypeKind = 'type.string' then
      Result := 'std::string'
    else if ATypeKind = 'type.boolean' then
      Result := 'bool'
    else if ATypeKind = 'type.void' then
      Result := 'void'
    else
      Result := 'auto';   // fallback
  end);
```

Use `TypeToIR` in emit handlers wherever you need a C++ type string:

```delphi
LCppType := LParse.Config().TypeToIR(LParse.Config().TypeTextToKind('integer'));
// = 'int32_t'
```

`TypeTextToKind` converts a source-language type keyword text (e.g. `'integer'`) to a type kind string (e.g. `'type.integer'`) using the table you built with `AddTypeKeyword`.

## Running the Pipeline

Once configuration is complete, set up the source and output, then compile:

```delphi
LParse.SetSourceFile('path\to\source.pas');
LParse.SetOutputPath('output');
LParse.SetTargetPlatform(tpWin64);
LParse.SetBuildMode(bmExe);
LParse.SetOptimizeLevel(olDebug);

LParse.SetStatusCallback(
  procedure(const ALine: string; const AUserData: Pointer)
  begin
    WriteLn(ALine);
  end);

if LParse.Compile(True) then    // True = run the binary after compilation
  WriteLn('Success')
else
  WriteLn('Failed');
```

`Compile` runs: Tokenize → Parse → Semantics → CodeGen → Zig compilation → (optional) execute. Status messages are emitted at each stage showing filenames, token counts, and node counts.

## A Complete Minimal Language

To make everything concrete, here is the smallest possible language that can print a string and exit. The full source language is one line: `print("hello")`.

```delphi
LParse.Config()

  // --- LEXER ---
  .CaseSensitiveKeywords(True)
  .AddKeyword('print', 'keyword.print')
  .AddOperator('(', 'delimiter.lparen')
  .AddOperator(')', 'delimiter.rparen')
  .AddStringStyle('"', '"', PARSE_KIND_STRING, True)
  .SetStatementTerminator('')    // no semicolons required

  // --- GRAMMAR ---

  // Register standard literal prefixes (identifier, integer, real, string)
  // (call as a separate statement — not chainable from Config() setup above
  //  since it returns TParse, but shown here conceptually)
```

Then separately:

```delphi
LParse.Config().RegisterLiteralPrefixes();

LParse.Config().RegisterPrefix('delimiter.lparen', 'expr.grouped',
  function(AParser: TParseParserBase): TParseASTNodeBase
  var
    LNode: TParseASTNode;
  begin
    AParser.Consume();  // '('
    LNode := AParser.CreateNode('expr.grouped');
    LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
    AParser.Expect('delimiter.rparen');
    Result := LNode;
  end);

LParse.Config().RegisterStatement('keyword.print', 'stmt.print',
  function(AParser: TParseParserBase): TParseASTNodeBase
  var
    LNode: TParseASTNode;
  begin
    LNode := AParser.CreateNode();   // 'stmt.print'
    AParser.Consume();               // consume 'print'
    AParser.Expect('delimiter.lparen');
    LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
    AParser.Expect('delimiter.rparen');
    Result := LNode;
  end);

// --- EMIT ---

LParse.Config().RegisterEmitter('stmt.print',
  procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
  begin
    AGen.Include('iostream');
    AGen.Stmt('std::cout << ' +
      LParse.Config().ExprToString(ANode.GetChild(0)) + ' << std::endl;');
  end);
```

That is a complete language. One keyword, one string literal, one statement, one emitter. The AST for `print("hello")` is:

```
[program.root]
  [stmt.print]  text=print
    [literal.string]  text="hello"
```

The emitter turns that into:

```cpp
#include <iostream>
int main() {
    std::cout << "hello" << std::endl;
}
```

Every language in the toolkit — Pascal, Lua, Basic, Scheme — is just this pattern scaled up. The same three surfaces, the same handler types, the same AST building blocks.

## Worked Example: Pascal `if/then/else`

Source:
```pascal
if x > 0 then
  writeln('positive')
else
  writeln('negative');
```

### Step 1: Lexer — tokens produced

```
keyword.if      "if"
identifier      "x"
op.gt           ">"
literal.integer "0"
keyword.then    "then"
keyword.writeln "writeln"
...
```

### Step 2: Grammar — parsing

The parser calls `ParseStatement()`. It sees `keyword.if`, looks up the statement handler, and dispatches it.

The handler:
1. Creates `stmt.if` node.
2. Consumes `if`.
3. Calls `ParseExpression(0)` → produces an `expr.binary` node (`x > 0`).
4. Expects `keyword.then`.
5. Calls `ParseStatement()` for the then-branch → produces `stmt.writeln`.
6. If next token is `keyword.else`, consumes it and calls `ParseStatement()` for the else-branch.
7. Returns the `stmt.if` node.

AST result:
```
[stmt.if]
  [expr.binary]   attr: op=">"
    [identifier]  text="x"
    [literal.integer] text="0"
  [stmt.writeln]
    [literal.string] text="'positive'"
  [stmt.writeln]
    [literal.string] text="'negative'"
```

### Step 3: Emit — C++23 output

The `stmt.if` emitter:
```delphi
LCondStr := LParse.Config().ExprToString(ANode.GetChild(0));  // "x > 0"
AGen.IfStmt(LCondStr);
AGen.EmitNode(ANode.GetChild(1));   // stmt.writeln → std::cout << "positive"...
AGen.ElseStmt();
AGen.EmitNode(ANode.GetChild(2));   // stmt.writeln → std::cout << "negative"...
AGen.EndIf();
```

Output:
```cpp
if (x > 0) {
    std::cout << "positive" << "\n";
} else {
    std::cout << "negative" << "\n";
}
```

## Common Patterns Quick Reference

### Pattern: Boolean literals

```delphi
LParse.Config().RegisterPrefix('keyword.true', 'expr.bool',
  function(AParser: TParseParserBase): TParseASTNodeBase
  var LNode: TParseASTNode;
  begin
    LNode := AParser.CreateNode();
    AParser.Consume();
    Result := LNode;
  end);
// Same for 'keyword.false' → 'expr.bool'
```

### Pattern: Grouped expression `(expr)`

```delphi
LParse.Config().RegisterPrefix('delimiter.lparen', 'expr.grouped',
  function(AParser: TParseParserBase): TParseASTNodeBase
  var LNode: TParseASTNode;
  begin
    AParser.Consume();  // '('
    LNode := AParser.CreateNode('expr.grouped');
    LNode.AddChild(TParseASTNode(AParser.ParseExpression(0)));
    AParser.Expect('delimiter.rparen');
    Result := LNode;
  end);
```

### Pattern: Function call `name(args...)`

```delphi
// Register identifier as prefix; detect '(' to build a call node
LParse.Config().RegisterPrefix('identifier', 'expr.identifier',
  function(AParser: TParseParserBase): TParseASTNodeBase
  var
    LIdNode:  TParseASTNode;
    LCall:    TParseASTNode;
    LNameTok: TParseToken;
  begin
    LNameTok := AParser.CurrentToken();
    AParser.Consume();  // consume identifier
    if AParser.Check('delimiter.lparen') then
    begin
      // It is a function call
      LCall := AParser.CreateNode('expr.call', LNameTok);
      LCall.SetAttr('call.name', TValue.From<string>(LNameTok.Text));
      AParser.Consume();  // consume '('
      while not AParser.Check('delimiter.rparen') and
            not AParser.Check(PARSE_KIND_EOF) do
      begin
        LCall.AddChild(TParseASTNode(AParser.ParseExpression(0)));
        if not AParser.Match('delimiter.comma') then
          Break;
      end;
      AParser.Expect('delimiter.rparen');
      Result := LCall;
    end
    else
    begin
      // Plain identifier reference
      LIdNode := AParser.CreateNode('expr.identifier', LNameTok);
      Result := LIdNode;
    end;
  end);
```

### Pattern: Right-associative assignment `:=`

```delphi
LParse.Config().RegisterInfixRight('op.assign', 2, 'expr.assign',
  function(AParser: TParseParserBase;
    ALeft: TParseASTNodeBase): TParseASTNodeBase
  var LNode: TParseASTNode;
  begin
    LNode := AParser.CreateNode();
    LNode.SetAttr('op', TValue.From<string>(':='));
    AParser.Consume();  // ':='
    LNode.AddChild(TParseASTNode(ALeft));
    LNode.AddChild(TParseASTNode(
      AParser.ParseExpression(AParser.CurrentInfixPowerRight())));
    Result := LNode;
  end);
```

### Pattern: All standard arithmetic and comparison operators

```delphi
LParse.Config()
  .RegisterBinaryOp('op.plus',     20, '+')
  .RegisterBinaryOp('op.minus',    20, '-')
  .RegisterBinaryOp('op.multiply', 30, '*')
  .RegisterBinaryOp('op.divide',   30, '/')
  .RegisterBinaryOp('op.eq',       40, '==')
  .RegisterBinaryOp('op.neq',      40, '!=')
  .RegisterBinaryOp('op.lt',       40, '<')
  .RegisterBinaryOp('op.lte',      40, '<=')
  .RegisterBinaryOp('op.gt',       40, '>')
  .RegisterBinaryOp('op.gte',      40, '>=');
```

## Checklist for a New Language

1. **Lexer surface**
   - [ ] Case sensitivity set
   - [ ] All keywords registered
   - [ ] All operators registered (multi-char before single-char)
   - [ ] String style(s) registered
   - [ ] Comment style(s) registered
   - [ ] Statement terminator set (or `''` if none)
   - [ ] Block open/close set (if applicable)
   - [ ] Hex/binary prefixes registered (if applicable)

2. **Grammar surface**
   - [ ] `RegisterLiteralPrefixes()` called
   - [ ] All keywords that start expressions registered as prefix handlers
   - [ ] All operators registered as infix (left or right) with correct binding powers
   - [ ] Unary operators registered as prefix with high binding power (40–50)
   - [ ] All statement-starting keywords registered as statement handlers
   - [ ] Grouped expression `(expr)` registered

3. **Emit surface**
   - [ ] Emitter registered for every node kind produced by grammar handlers
   - [ ] `TypeToIR` registered
   - [ ] `NameMangler` registered (if needed)
   - [ ] `ExprOverride` registered for non-standard expression nodes

4. **Semantic surface** (if used)
   - [ ] Handlers for declaration nodes (call `DeclareSymbol`)
   - [ ] Handlers for identifier use-sites (call `LookupSymbol`, write `PARSE_ATTR_RESOLVED_SYMBOL`)
   - [ ] Handlers for scope-opening nodes (call `PushScope`/`PopScope`)
   - [ ] `RegisterTypeCompat` registered (if type checking needed)
   - [ ] `AddLiteralType`, `AddDeclKind`, `AddCallKind` registered (if type inference needed)

5. **Pipeline**
   - [ ] `SetSourceFile` and `SetOutputPath` called
   - [ ] `SetTargetPlatform`, `SetBuildMode`, `SetOptimizeLevel` called
   - [ ] Status and output callbacks set
   - [ ] `Compile()` called
