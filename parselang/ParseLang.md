# ParseLang — The Parse() Meta-Language

> Define a complete compiled language in a single `.parse` file.

ParseLang is the meta-language layer of the Parse() toolkit. It lets you describe a programming language — its tokens, grammar rules, semantic analysis, and C++23 code generation — in a concise declarative+scripting syntax. The Parse() toolkit reads your `.parse` file and produces a live, fully configured compiler in memory, then immediately uses it to compile your source files to native binaries via Zig.

---

## Table of Contents

1. [Overview](#1-overview)
2. [File Structure](#2-file-structure)
3. [Lexer Sections](#3-lexer-sections)
   - 3.1 [tokens](#31-tokens)
   - 3.2 [keywords](#32-keywords)
   - 3.3 [operators](#33-operators)
   - 3.4 [strings](#34-strings)
   - 3.5 [comments](#35-comments)
   - 3.6 [structural](#36-structural)
   - 3.7 [types](#37-types)
   - 3.8 [literals](#38-literals)
4. [Grammar Rules](#4-grammar-rules)
   - 4.1 [prefix](#41-prefix)
   - 4.2 [infix](#42-infix)
   - 4.3 [statement](#43-statement)
   - 4.4 [binaryop](#44-binaryop)
   - 4.5 [registerLiterals](#45-registerliterals)
   - 4.6 [exproverride](#46-exproverride)
5. [Semantic Rules](#5-semantic-rules)
6. [Emit Rules](#6-emit-rules)
7. [Type Mapping](#7-type-mapping)
8. [Helper Functions](#8-helper-functions)
9. [The Scripting Language](#9-the-scripting-language)
   - 9.1 [Variables and Assignment](#91-variables-and-assignment)
   - 9.2 [Control Flow](#92-control-flow)
   - 9.3 [Expressions](#93-expressions)
   - 9.4 [Implicit Variables](#94-implicit-variables)
10. [Built-in Functions by Context](#10-built-in-functions-by-context)
    - 10.1 [Common (all contexts)](#101-common-all-contexts)
    - 10.2 [Parse context](#102-parse-context)
    - 10.3 [Semantic context](#103-semantic-context)
    - 10.4 [Emit context](#104-emit-context)
11. [Pipeline Configuration](#11-pipeline-configuration)
12. [Using TParseLang from Delphi](#12-using-tparselang-from-delphi)
13. [Complete Example — MiniCalc](#13-complete-example---minicalc)
14. [Reference — Token Kind Naming Conventions](#14-reference---token-kind-naming-conventions)
15. [Reference — Node Kind Naming Conventions](#15-reference---node-kind-naming-conventions)
16. [Known Limitations](#16-known-limitations)

---

## 1. Overview

A `.parse` file is processed in two phases:

**Phase 1 — Bootstrap compilation**
The `.parse` file itself is compiled by the ParseLang bootstrap parser. The result is a live `TParse` instance fully configured with your language's lexer, grammar, semantic rules, and emitters.

**Phase 2 — Source compilation**
The configured `TParse` instance compiles your source file: lexing → parsing → semantic analysis → C++23 code generation → Zig native binary.

```
mylang.parse  ──► ParseLang bootstrap ──► configured TParse
                                                │
myprogram.ml ──────────────────────────────────► TParse.Compile()
                                                │
                                          native binary
```

The key insight: you never write Delphi code. Everything — lexer rules, Pratt parser handlers, semantic analysis, and C++23 emitters — is expressed in the `.parse` file using ParseLang's scripting blocks.

---

## 2. File Structure

A `.parse` file consists of a `language` declaration followed by any number of sections and rules in any order:

```
language MyLang;

-- Lexer sections (define what the scanner produces)
keywords   ...  end
operators  ...  end
strings    ...  end
comments   ...  end
structural ...  end
types      ...  end
literals   ...  end
typemap    ...  end

-- Grammar rules (define what the parser produces)
registerLiterals;
binaryop   ...;
prefix     ...  end
infix      ...  end
statement  ...  end
exproverride ... end

-- Analysis and code generation
semantic   ...  end
emit       ...  end

-- Reusable scripting helpers
function   ...  end
```

Comments use `--` (line comment only):

```
-- This is a comment
language Foo;  -- inline comment
```

Statements are terminated with `;`. Blocks are closed with `end`.

---

## 3. Lexer Sections

### 3.1 tokens

Declares named token patterns using regex. In the current version these are **informational** — the token names can be referenced in grammar rules but the regex is not applied by the lexer engine (which uses the operator/keyword/string/comment tables instead). This section is reserved for future regex-based token support.

```
tokens
  digit     ~ /[0-9]+/;
  ident     ~ /[a-zA-Z_][a-zA-Z0-9_]*/;
end
```

### 3.2 keywords

Declares reserved words that the lexer will recognise and emit with the given token kind string instead of `identifier`.

```
keywords casesensitive
  'if'       -> 'keyword.if';
  'else'     -> 'keyword.else';
  'end'      -> 'keyword.end';
  'var'      -> 'keyword.var';
  'function' -> 'keyword.function';
  'return'   -> 'keyword.return';
  'true'     -> 'keyword.true';
  'false'    -> 'keyword.false';
  'nil'      -> 'keyword.nil';
end
```

The optional modifier `casesensitive` or `caseinsensitive` controls whether keyword matching is case-sensitive. Default is `caseinsensitive`.

```
keywords caseinsensitive
  'BEGIN' -> 'keyword.begin';   -- matches begin, BEGIN, Begin, etc.
end
```

### 3.3 operators

Declares multi- and single-character operator tokens. Longer operators must be listed before shorter ones to guarantee longest-match behaviour.

```
operators
  ':=' -> 'op.assign';
  '<>' -> 'op.neq';
  '<=' -> 'op.lte';
  '>=' -> 'op.gte';
  '+'  -> 'op.plus';
  '-'  -> 'op.minus';
  '*'  -> 'op.star';
  '/'  -> 'op.slash';
  '('  -> 'delimiter.lparen';
  ')'  -> 'delimiter.rparen';
  ';'  -> 'delimiter.semicolon';
  ':'  -> 'delimiter.colon';
end
```

### 3.4 strings

Declares string literal styles. Each style has an open delimiter, a close delimiter, a token kind, and an optional `escape` flag.

```
strings
  '"'  '"'  -> 'literal.string'  escape true;
  '''' '''' -> 'literal.char'    escape false;
end
```

`escape true` means backslash sequences (`\n`, `\t`, `\\`, etc.) are processed inside the string. `escape false` means the content is taken literally; two consecutive close-delimiter characters represent a single literal close delimiter (Pascal-style).

### 3.5 comments

Declares comment styles.

```
comments
  line '--';
  line '//';
  block '(*' '*)';
  block '{' '}' -> 'comment.directive';
end
```

`line` comments run from the prefix to end of line. `block` comments span multiple lines. The optional `-> 'kind'` gives block comments a distinct token kind (useful for directives).

### 3.6 structural

Declares the three structural token kinds the parser engine uses for block-aware parsing.

```
structural
  terminator 'delimiter.semicolon';
  blockopen  'keyword.begin';
  blockclose 'keyword.end';
end
```

- `terminator` — the statement separator/terminator token kind.
- `blockopen` — the token kind that opens a generic block (used by `GetBlockCloseKind()` logic).
- `blockclose` — the token kind that closes any block.

### 3.7 types

Declares type keyword tokens. These are keywords that represent type names, registered separately so the semantic engine can resolve type text to type kind strings.

```
types
  'integer' -> 'type.integer';
  'real'    -> 'type.real';
  'string'  -> 'type.string';
  'boolean' -> 'type.boolean';
end
```

### 3.8 literals

Declares which AST node kinds represent literal values, and what type kind they carry. Used by the semantic engine's `InferLiteralType()`.

```
literals
  'literal.integer' -> 'type.integer';
  'literal.real'    -> 'type.real';
  'literal.string'  -> 'type.string';
  'expr.bool'       -> 'type.boolean';
end
```

---

## 4. Grammar Rules

Grammar rules register handlers with the Pratt parser engine. All handler bodies are written in the [ParseLang scripting language](#9-the-scripting-language).

### 4.1 prefix

A prefix rule fires when the parser sees the given token kind at the start of an expression. The handler must return a node by assigning to `result`.

```
prefix 'keyword.true' as 'expr.bool'
parse
  result := createNode();
  consume();
end
end
```

Structure:
```
prefix '<token-kind>' as '<node-kind>'
parse
  -- scripting block
  -- must assign an AST node to: result
end
end
```

The `parse` keyword opens the scripting block. The first `end` closes the scripting block; the second `end` closes the `prefix` rule.

**Implicit variable:** `result` — assign the created node here.

### 4.2 infix

An infix rule fires when the given token kind appears between two expressions (binary operator, call, subscript, etc.). The left-hand expression is available as the implicit variable `left`.

```
infix left 'op.plus' power 20 as 'expr.add'
parse
  result := createNode();
  consume();
  addChild(result, left);
  addChild(result, parseExpr(20));
end
end
```

Structure:
```
infix left|right '<token-kind>' power <N> as '<node-kind>'
parse
  -- left: TParseASTNode — the already-parsed left operand
  -- result: assign the created node here
end
end
```

- `left` — left-associative (most operators).
- `right` — right-associative (assignment, power, etc.).
- `power <N>` — binding power integer. Higher numbers bind tighter. Conventional scale: comparisons 10, addition 20, multiplication 30, unary 50, call/index 80–90.

### 4.3 statement

A statement rule fires when the given token kind appears at the start of a statement position.

```
statement 'keyword.if' as 'stmt.if'
parse
  result := createNode();
  consume();                         -- consume 'if'
  addChild(result, parseExpr(0));    -- condition
  expect('keyword.then');
  addChild(result, parseStmt());     -- then-body
  if check('keyword.else') then
    consume();
    addChild(result, parseStmt());
  end
  expect('keyword.end');
end
end
```

Structure:
```
statement '<token-kind>' as '<node-kind>'
parse
  -- result: assign the created node here
end
end
```

### 4.4 binaryop

A shorthand for registering simple binary operators that map directly to a C++ infix operator. Avoids writing a full parse + emit pair for standard arithmetic/comparison operators.

```
binaryop 'op.plus'  power 20 op '+';
binaryop 'op.minus' power 20 op '-';
binaryop 'op.star'  power 30 op '*';
binaryop 'op.slash' power 30 op '/';
binaryop 'op.eq'    power 10 op '==';
binaryop 'op.neq'   power 10 op '!=';
binaryop 'op.lt'    power 10 op '<';
binaryop 'op.gt'    power 10 op '>';
binaryop 'op.lte'   power 10 op '<=';
binaryop 'op.gte'   power 10 op '>=';
```

The framework automatically registers both the infix parse handler and the emit handler for each `binaryop` declaration.

### 4.5 registerLiterals

Registers the framework's built-in literal prefix handlers for integer, real, string, and char token kinds. Call this once after your lexer sections.

```
registerLiterals;
```

### 4.6 exproverride

Overrides how a specific node kind is rendered to a C++ expression string by `ExprToString()`. Used when the default rendering is insufficient.

```
exproverride 'expr.string_literal'
override
  result := str(node.token.text);
end
end
```

The implicit variable `node` is the AST node being rendered. Call `default(node)` to invoke the framework's default renderer for sub-expressions.

---

## 5. Semantic Rules

Semantic rules fire during the semantic analysis pass when a node of the given kind is visited. They are used to manage scope, declare/resolve symbols, infer types, and report errors.

```
semantic 'stmt.var_decl'
  declare(node, node);
  setAttr(node, 'sem.storage', 'local');
  setAttr(node, 'sem.type', getAttr(node, 'decl.type_kind'));
end
```

```
semantic 'program.root'
  pushScope('global', node);
  visitChildren(node);
  popScope(node);
end
```

Structure:
```
semantic '<node-kind>'
  -- node: the AST node being analysed
  -- (no result needed)
end
```

---

## 6. Emit Rules

Emit rules fire during code generation when a node of the given kind is walked. They write C++23 text using the IR builder built-ins.

```
emit 'stmt.var_decl'
  declVar(getAttr(node, 'decl.name'), typeToIR(getAttr(node, 'sem.type')));
end
```

```
emit 'expr.add'
  result := add(exprToString(getChild(node, 0)),
                exprToString(getChild(node, 1)));
end
```

Structure:
```
emit '<node-kind>'
  -- node: the AST node being emitted
  -- result: assign a string if the node represents an expression value
end
```

**Expression nodes** (those that produce a value) should assign their C++ text to `result`. **Statement nodes** call IR builder procedures directly (e.g. `emitLine`, `stmt`, `ifStmt`).

---

## 7. Type Mapping

The `typemap` block maps your language's type kind strings to C++ type strings. The framework uses this when you call `typeToIR(kind)` in an emit rule.

```
typemap
  'type.integer' -> 'int64_t';
  'type.real'    -> 'double';
  'type.string'  -> 'std::string';
  'type.boolean' -> 'bool';
  'type.void'    -> 'void';
end
```

Multiple `typemap` blocks are merged. Unknown type kinds are passed through as-is (useful for raw C++ types).

---

## 8. Helper Functions

Helper functions are reusable scripting routines callable from any parse, semantic, emit, or exproverride block.

```
function emitBinaryOp(left: string, right: string, op: string) -> string
  result := left + ' ' + op + ' ' + right;
end
```

```
function resolveType(typeText: string) -> string
  result := typeToIR(typeTextToKind(typeText));
end
```

Structure:
```
function <Name>(<param>: <type>, ...) [-> <return-type>]
  -- body
  -- assign result to return a value
end
```

**Parameter types:** `string`, `int`, `bool`, `node`, `token`. These are informational — the interpreter does not enforce them.

**Return type:** if specified, the caller receives the value of `result` at the end of the function body. If omitted, the function is void (return value is nil).

Helper functions are called like built-ins:
```
emit 'expr.binary'
  result := emitBinaryOp(
    exprToString(getChild(node, 0)),
    exprToString(getChild(node, 1)),
    getAttr(node, 'op'));
end
```

---

## 9. The Scripting Language

The scripting language is used inside `parse`, `semantic`, `emit`, `override`, and `function` bodies. It is a simple imperative language with Pascal-influenced syntax.

### 9.1 Variables and Assignment

Variables are declared implicitly on first assignment. There is no explicit `var` declaration.

```
x := 42;
name := 'hello';
ok := true;
n := createNode();
```

### 9.2 Control Flow

**if / else if / else / end**
```
if x > 10 then
  emitLine('big');
else if x > 5 then
  emitLine('medium');
else
  emitLine('small');
end
```

**while / do / end**
```
i := 0;
while i < childCount(node) do
  emitNode(getChild(node, i));
  i := i + 1;
end
```

**for / in / do / end**

Iterates from `0` to `N-1` where `N` is the integer value of the range expression:
```
for i in childCount(node) do
  emitNode(getChild(node, i));
end
```

**repeat / until**
```
repeat
  tok := consume();
until tok.kind = 'delimiter.semicolon';
```

### 9.3 Expressions

| Expression | Syntax |
|---|---|
| Integer literal | `42`, `-7` |
| String literal | `'hello world'` |
| Boolean literal | `true`, `false` |
| Nil | `nil` |
| Variable | `x` |
| Field access | `node.token`, `tok.text`, `tok.kind` |
| Array index | `s[1]` (1-based) |
| Function call | `foo(a, b)` |
| Grouped | `(x + y)` |
| Arithmetic | `+` `-` `*` |
| Comparison | `=` `<>` `<` `>` `<=` `>=` |
| Logical | `and` `or` `not` |
| String concat | `'hello' + ' ' + name` |

**Field access on built-in types:**

| Value | Field | Result |
|---|---|---|
| `node` | `.token` | The node's source token (type: token) |
| `token` | `.text` | Raw source text (string) |
| `token` | `.kind` | Token kind string (string) |
| `target` | `.source` | sfSource sentinel for IR calls |
| `target` | `.header` | sfHeader sentinel for IR calls |

### 9.4 Implicit Variables

Each context pre-populates certain variables:

| Context | Variable | Type | Description |
|---|---|---|---|
| prefix / statement | `result` | node | Assign the created AST node here |
| infix | `result` | node | Assign the created AST node here |
| infix | `left` | node | The left-hand parsed expression |
| semantic | `node` | node | The AST node being analysed |
| emit | `node` | node | The AST node being emitted |
| emit | `result` | string | Assign expression C++ text here |
| emit | `target` | — | Use `.source` / `.header` for IR target |
| exproverride | `node` | node | The AST node being rendered |
| exproverride | `result` | string | Assign the C++ expression text |

---

## 10. Built-in Functions by Context

### 10.1 Common (all contexts)

These functions are available in every scripting block.

| Function | Returns | Description |
|---|---|---|
| `nodeKind(node)` | string | Get the kind string of a node |
| `getAttr(node, key)` | string | Read an attribute from a node |
| `setAttr(node, key, value)` | — | Write a string attribute onto a node |
| `getChild(node, index)` | node | Get child node at zero-based index |
| `childCount(node)` | int | Number of children of a node |
| `len(s)` | int | Length of string `s` |
| `substr(s, start, count)` | string | Substring (1-based start) |
| `replace(s, find, repl)` | string | Replace all occurrences |
| `uppercase(s)` | string | Convert to upper case |
| `lowercase(s)` | string | Convert to lower case |
| `trim(s)` | string | Strip leading/trailing whitespace |
| `strtoint(s)` | int | Parse string to integer (0 on failure) |
| `inttostr(n)` | string | Integer to string |
| `format(fmt, ...)` | string | Printf-style formatting (`%s`, `%d`) |
| `typeTextToKind(text)` | string | Resolve type keyword text → type kind |

### 10.2 Parse context

Available inside `prefix`, `infix`, and `statement` parse blocks.

| Function | Returns | Description |
|---|---|---|
| `createNode()` | node | Create node with the rule's node kind, current token |
| `createNode(kind)` | node | Create node with explicit kind, current token |
| `createNode(kind, tok)` | node | Create node with explicit kind and token |
| `addChild(parent, child)` | — | Append child node to parent |
| `consume()` | token | Consume current token and advance |
| `expect(kind)` | — | Assert current token is `kind`, consume it |
| `check(kind)` | bool | True if current token is `kind` (no consume) |
| `match(kind)` | bool | Consume and return true if current is `kind` |
| `current()` | token | Current token (not consumed) |
| `peek()` | token | Next token (lookahead, not consumed) |
| `parseExpr(power)` | node | Parse an expression with minimum binding power |
| `parseStmt()` | node | Parse the next statement |
| `bindPower()` | int | Binding power of current infix token |
| `bindPowerRight()` | int | Right binding power of current infix token |
| `blockCloseKind()` | string | The configured block-close token kind |
| `stmtTermKind()` | string | The configured statement terminator kind |

### 10.3 Semantic context

Available inside `semantic` blocks.

| Function | Returns | Description |
|---|---|---|
| `pushScope(name, tok_or_node)` | — | Push a named scope |
| `popScope(tok_or_node)` | — | Pop current scope |
| `visitNode(node)` | — | Dispatch semantic handler for node |
| `visitChildren(node)` | — | Visit all children of node |
| `declare(name, node)` | bool | Declare symbol; false if duplicate |
| `lookup(name)` | node/nil | Look up symbol in scope chain |
| `lookupLocal(name)` | node/nil | Look up symbol in current scope only |
| `insideRoutine()` | bool | True if inside a function/procedure scope |
| `error(node, code, msg)` | — | Report semantic error |
| `warn(node, code, msg)` | — | Report semantic warning |
| `typeTextToKind(text)` | string | Resolve type text → type kind |

### 10.4 Emit context

Available inside `emit` and `exproverride` blocks.

**Low-level output:**

| Function | Description |
|---|---|
| `emitLine(text)` | Emit indented line + newline to source |
| `emitLine(text, target.header)` | Emit to header file instead |
| `emitLine(fmt, arg1, ...)` | Formatted emit (`%s`, `%d`) |
| `emit(text)` | Emit text verbatim (no indent, no newline) |
| `emitRaw(text)` | Emit truly verbatim (no processing) |
| `indentIn()` | Increase indentation level |
| `indentOut()` | Decrease indentation level |
| `emitNode(node)` | Dispatch emit handler for node |
| `emitChildren(node)` | Emit all children of node |
| `blankLine()` | Emit a blank line |

**Function builder (fluent, must call in sequence):**

| Function | C++ output |
|---|---|
| `func(name, returnType)` | `returnType name(` |
| `param(name, type)` | Adds `, type name` to signature |
| `endFunc()` | Closes function `}` |

**Declarations:**

| Function | C++ output |
|---|---|
| `include(name)` | `#include <name>` (header) |
| `include(name, target.source)` | `#include <name>` (source) |
| `struct(name)` | `struct name {` |
| `addField(name, type)` | `type name;` inside struct |
| `endStruct()` | `};` |
| `declConst(name, type, value)` | `constexpr auto name = value;` |
| `global(name, type, init)` | `static type name = init;` |
| `usingAlias(alias, original)` | `using alias = original;` |
| `namespace(name)` | `namespace name {` |
| `endNamespace()` | `}` |

**Statements:**

| Function | C++ output |
|---|---|
| `declVar(name, type)` | `type name;` |
| `declVar(name, type, init)` | `type name = init;` |
| `assign(lhs, expr)` | `lhs = expr;` |
| `stmt(text)` | `text;` |
| `stmt(fmt, ...)` | Formatted statement |
| `returnVoid()` | `return;` |
| `returnVal(expr)` | `return expr;` |
| `ifStmt(cond)` | `if (cond) {` |
| `elseIfStmt(cond)` | `} else if (cond) {` |
| `elseStmt()` | `} else {` |
| `endIf()` | `}` |
| `whileStmt(cond)` | `while (cond) {` |
| `endWhile()` | `}` |
| `forStmt(var, init, cond, step)` | `for (auto var = init; cond; step) {` |
| `endFor()` | `}` |
| `breakStmt()` | `break;` |
| `continueStmt()` | `continue;` |

**Expression builders (return C++ string fragments):**

| Function | C++ result |
|---|---|
| `lit(n)` | Integer literal `42` |
| `str(s)` | String literal `"hello"` |
| `boolLit(b)` | `true` or `false` |
| `nullLit()` | `nullptr` |
| `get(name)` | Variable reference `name` |
| `field(obj, member)` | `obj.member` |
| `deref(ptr, member)` | `ptr->member` |
| `deref(ptr)` | `*ptr` |
| `addrOf(name)` | `&name` |
| `index(arr, i)` | `arr[i]` |
| `cast(type, expr)` | `static_cast<type>(expr)` |
| `invoke(func, ...)` | `func(args...)` |
| `add(l, r)` | `l + r` |
| `sub(l, r)` | `l - r` |
| `mul(l, r)` | `l * r` |
| `divExpr(l, r)` | `l / r` |
| `modExpr(l, r)` | `l % r` |
| `neg(e)` | `-e` |
| `eq(l, r)` | `l == r` |
| `ne(l, r)` | `l != r` |
| `lt(l, r)` | `l < r` |
| `le(l, r)` | `l <= r` |
| `gt(l, r)` | `l > r` |
| `ge(l, r)` | `l >= r` |
| `andExpr(l, r)` | `l && r` |
| `orExpr(l, r)` | `l \|\| r` |
| `notExpr(e)` | `!e` |
| `bitAnd(l, r)` | `l & r` |
| `bitOr(l, r)` | `l \| r` |
| `bitXor(l, r)` | `l ^ r` |
| `bitNot(e)` | `~e` |
| `shlExpr(l, r)` | `l << r` |
| `shrExpr(l, r)` | `l >> r` |

**Type resolution:**

| Function | Returns | Description |
|---|---|---|
| `typeToIR(kind)` | string | Type kind → C++ type (uses typemap) |
| `resolveTypeIR(text)` | string | Type text → C++ type (text → kind → IR) |
| `exprToString(node)` | string | Render expression node → C++ string |

**ExprOverride only:**

| Function | Returns | Description |
|---|---|---|
| `default(node)` | string | Invoke framework's default expression renderer |

**Cross-handler state:**

| Function | Description |
|---|---|
| `setContext(key, value)` | Store a string in the IR context bag |
| `getContext(key, default)` | Retrieve a string from the IR context bag |

---

## 11. Pipeline Configuration

These built-ins are available in **emit blocks** and configure the build pipeline for the output binary. Call them from your top-level program node's emit handler.

| Function | Values | Description |
|---|---|---|
| `setPlatform(p)` | `'win64'`, `'linux64'` | Target platform |
| `setBuildMode(m)` | `'exe'`, `'lib'`, `'dll'` | Output type |
| `setOptimize(o)` | `'debug'`, `'release'`, `'speed'`, `'size'` | Optimisation level |
| `setSubsystem(s)` | `'console'`, `'gui'` | Windows subsystem |
| `setOutputPath(p)` | any string | Override output directory |

The caller's `SetTargetPlatform()` / `SetBuildMode()` / `SetOptimizeLevel()` / `SetSubsystem()` values are applied as **defaults** before Phase 1 runs. Calls in emit blocks override those defaults.

---

## 12. Using TParseLang from Delphi

Add `ParseLang.pas` (and its companion units) to your project. The unit exposes `TParseLang`:

```delphi
uses
  ParseLang;

procedure CompileWithCustomLang();
var
  LPL: TParseLang;
begin
  LPL := TParseLang.Create();
  try
    // Point at the .parse language definition
    LPL.SetLangFile('mylang.parse');

    // Point at the user's source file
    LPL.SetSourceFile('hello.ml');

    // Output directory for generated files and binary
    LPL.SetOutputPath('output');

    // Build defaults (can be overridden from inside the .parse file)
    LPL.SetTargetPlatform(tpWin64);
    LPL.SetBuildMode(bmExe);
    LPL.SetOptimizeLevel(olDebug);
    LPL.SetSubsystem(stConsole);

    // Optional: wire status/output callbacks
    LPL.SetStatusCallback(MyStatusCallback, nil);

    // Compile: Phase 1 (.parse) + Phase 2 (source)
    // ABuild=True  → invoke Zig toolchain → native binary
    // AAutoRun=True → run binary after build
    if LPL.Compile(True, False) then
      Writeln('Success')
    else
    begin
      Writeln('Errors:');
      // LPL.GetErrors() returns errors from whichever phase failed
    end;
  finally
    LPL.Free();
  end;
end;
```

**Required files in your project:**
- `ParseLang.pas`
- `ParseLang.Lexer.pas`
- `ParseLang.Grammar.pas`
- `ParseLang.Semantics.pas`
- `ParseLang.CodeGen.pas`

All five files use `{$I ..\src\Parse.Defines.inc}` so they expect to live one directory below the Parse() `src\` folder, which is the `parselang\` directory.

---

## 13. Complete Example — MiniCalc

A minimal calculator language with integer arithmetic, variable assignment, and print.

**minicalc.parse**

```
language MiniCalc;

keywords casesensitive
  'print' -> 'keyword.print';
  'var'   -> 'keyword.var';
end

operators
  ':=' -> 'op.assign';
  '+'  -> 'op.plus';
  '-'  -> 'op.minus';
  '*'  -> 'op.star';
  '/'  -> 'op.slash';
  '('  -> 'delimiter.lparen';
  ')'  -> 'delimiter.rparen';
  ';'  -> 'delimiter.semicolon';
end

comments
  line '--';
end

structural
  terminator 'delimiter.semicolon';
end

typemap
  'type.integer' -> 'int64_t';
end

literals
  'literal.integer' -> 'type.integer';
end

registerLiterals;

binaryop 'op.plus'  power 20 op '+';
binaryop 'op.minus' power 20 op '-';
binaryop 'op.star'  power 30 op '*';
binaryop 'op.slash' power 30 op '/';

-- grouped expression: ( expr )
prefix 'delimiter.lparen' as 'expr.grouped'
parse
  consume();
  result := createNode();
  addChild(result, parseExpr(0));
  expect('delimiter.rparen');
end
end

-- variable reference
prefix 'identifier' as 'expr.ident'
parse
  result := createNode();
  consume();
end
end

-- var x := expr ;
statement 'keyword.var' as 'stmt.var_decl'
parse
  result := createNode();
  consume();
  setAttr(result, 'decl.name', current().text);
  consume();
  expect('op.assign');
  addChild(result, parseExpr(0));
  expect('delimiter.semicolon');
end
end

-- assignment: x := expr ;
statement 'identifier' as 'stmt.assign'
parse
  result := createNode();
  setAttr(result, 'assign.target', current().text);
  consume();
  expect('op.assign');
  addChild(result, parseExpr(0));
  expect('delimiter.semicolon');
end
end

-- print expr ;
statement 'keyword.print' as 'stmt.print'
parse
  result := createNode();
  consume();
  addChild(result, parseExpr(0));
  expect('delimiter.semicolon');
end
end

-- semantics: declare variables
semantic 'stmt.var_decl'
  declare(getAttr(node, 'decl.name'), node);
  setAttr(node, 'sem.storage', 'local');
  setAttr(node, 'sem.type', 'type.integer');
end

semantic 'program.root'
  pushScope('global', node);
  visitChildren(node);
  popScope(node);
end

-- emit: program root generates main()
emit 'program.root'
  include('cstdio', target.header);
  include('cstdint', target.header);
  func('main', 'int');
  emitChildren(node);
  returnVal('0');
  endFunc();
end

-- emit: var declaration
emit 'stmt.var_decl'
  declVar(getAttr(node, 'decl.name'), 'int64_t');
  assign(getAttr(node, 'decl.name'), exprToString(getChild(node, 0)));
end

-- emit: assignment
emit 'stmt.assign'
  assign(getAttr(node, 'assign.target'), exprToString(getChild(node, 0)));
end

-- emit: print
emit 'stmt.print'
  stmt(format('printf("%%lld\\n", %s)', exprToString(getChild(node, 0))));
end

-- emit: identifier reference
emit 'expr.ident'
  result := node.token.text;
end

-- emit: grouped expression
emit 'expr.grouped'
  result := '(' + exprToString(getChild(node, 0)) + ')';
end
```

**hello.mc**

```
var x := 10;
var y := 32;
print x + y;
print x * (y - 2);
```

**Delphi driver:**

```delphi
var
  LPL: TParseLang;
begin
  LPL := TParseLang.Create();
  try
    LPL.SetLangFile('minicalc.parse');
    LPL.SetSourceFile('hello.mc');
    LPL.SetOutputPath('output');
    LPL.SetBuildMode(bmExe);
    LPL.SetOptimizeLevel(olRelease);
    LPL.Compile(True, True);
  finally
    LPL.Free();
  end;
end;
```

---

## 14. Reference — Token Kind Naming Conventions

By convention, token kind strings follow a `category.name` pattern:

| Category | Examples |
|---|---|
| `keyword.*` | `keyword.if`, `keyword.while`, `keyword.end` |
| `op.*` | `op.plus`, `op.assign`, `op.arrow` |
| `delimiter.*` | `delimiter.lparen`, `delimiter.semicolon`, `delimiter.comma` |
| `literal.*` | `literal.integer`, `literal.real`, `literal.string` |
| `type.*` (type keywords) | `type.integer`, `type.string`, `type.boolean` |
| `comment.*` | `comment.line`, `comment.block` |
| `identifier` | (bare, no dot) |
| `eof` | (bare, no dot) |

---

## 15. Reference — Node Kind Naming Conventions

By convention, AST node kind strings follow a `category.name` pattern:

| Category | Examples |
|---|---|
| `program.*` | `program.root` |
| `stmt.*` | `stmt.if`, `stmt.var_decl`, `stmt.assign`, `stmt.print` |
| `expr.*` | `expr.add`, `expr.ident`, `expr.call`, `expr.grouped` |
| `decl.*` | `decl.func`, `decl.param` |
| `literal.*` | `literal.integer`, `literal.string` |

The framework uses `program.root` as the root node kind. All other node kinds are yours to define.

---

## 16. Known Limitations

**Regex token declarations (`tokens` block)**
The `tokens` section is parsed and stored but not applied. The lexer is configured entirely through the `keywords`, `operators`, `strings`, and `comments` sections. Future versions may add regex-based token support.

**Division operator inside `.parse` scripts**
The `/` character is used as the regex literal delimiter (`/pattern/`). This means `/` cannot be used as a division operator in the scripting language itself. Use `divExpr(a, b)` to emit C++ division from emit blocks. This does not affect languages you *define* — your language's `/` operator works normally; the restriction only applies to scripting code inside `.parse` files.

**`win32` platform**
Only `'win64'` and `'linux64'` are valid platform strings for `setPlatform()`. 32-bit Windows is not supported.

**Error recovery**
The bootstrap parser uses fail-fast error handling. A parse error in a `.parse` file stops Phase 1 immediately. There is no error recovery or partial compilation.
