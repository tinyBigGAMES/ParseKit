{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

(*
  UTest.Parse - Showcase

  This demo defines a complete, minimal programming language and compiles
  a source file to a native Win64 executable via C++23 - all through the
  TParse facade.

  The entire language definition fits in a single procedure. One unit,
  one class, one call to Compile. From grammar to binary.

  Language defined here:

    print "Hello, World!";

  Generated C++23 output:

    hello.h:
      #pragma once
      #include <cstdio>

    hello.cpp:
      #include "hello.h"

      int main() {
          printf( "Hello, World!\n" );
          return 0;
      }

  Full pipeline:
    Source -> Lexer -> Parser -> Semantics -> CodeGen -> Zig Build -> Run
*)

unit UTest.Parse;

{$I Parse.Defines.inc}

interface

procedure Test00();

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Parse;

// Display any errors collected during compilation.
// Iterates the shared error list and prints each with file, line, and message.
procedure ShowErrors(const AParse: TParse);
var
  LI: Integer;
begin
  if not AParse.HasErrors() then
    Exit;

  for LI := 0 to AParse.GetErrors().GetItems().Count - 1 do
    TParseUtils.PrintLn(COLOR_RED + AParse.GetErrors().GetItems()[LI].ToFullString());
end;

procedure Test00();
var
  LParse: TParse;
begin
  LParse := TParse.Create();
  try

    //=========================================================================
    // LEXER - Define the tokens our language recognizes.
    //
    // 'print' becomes a keyword token with kind 'keyword.print'.
    // ';' becomes a delimiter token with kind 'delimiter.semicolon'.
    // Double-quoted strings ( e.g. "hello" ) become PARSE_KIND_STRING tokens.
    // The semicolon is declared as the statement terminator so the parser
    // knows where one statement ends and the next begins.
    //=========================================================================
    LParse.Config()
      .AddKeyword('print', 'keyword.print')
      .AddOperator(';', 'delimiter.semicolon')
      .AddStringStyle('"', '"', PARSE_KIND_STRING, True)
      .SetStatementTerminator('delimiter.semicolon');

    //=========================================================================
    // GRAMMAR - Define how tokens are parsed into AST nodes.
    //
    // Parse() uses a Pratt parser. Prefix handlers fire when a token appears
    // at the start of an expression. Statement handlers fire when a keyword
    // begins a new statement. Each handler receives the parser, builds an
    // AST node, and returns it.
    //=========================================================================

    // String literal prefix handler.
    // When the parser sees a PARSE_KIND_STRING token in expression position,
    // it creates an 'expr.string' AST node and consumes the token.
    LParse.Config().RegisterPrefix(PARSE_KIND_STRING, 'expr.string',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();
        Result := LNode;
      end);

    // 'print' statement handler.
    // When the parser sees 'keyword.print', it creates a 'stmt.print' node,
    // consumes the keyword, parses the argument expression ( which becomes a
    // child node ), and expects a semicolon to terminate the statement.
    LParse.Config().RegisterStatement('keyword.print', 'stmt.print',
      function(AParser: TParseParserBase): TParseASTNodeBase
      var
        LNode: TParseASTNode;
      begin
        LNode := AParser.CreateNode();
        AParser.Consume();                                   // consume 'print'
        LNode.AddChild(TParseASTNode(AParser.ParseExpression()));  // parse arg
        AParser.Expect('delimiter.semicolon');                // consume ';'
        Result := LNode;
      end);

    //=========================================================================
    // SEMANTICS - Define how the AST is analyzed after parsing.
    //
    // Semantic rules run top-down over the AST. They handle scope management,
    // symbol declaration and resolution, type tagging, and error reporting.
    // Each rule is keyed by node kind - the same string used in the grammar.
    //=========================================================================

    // Program root: the parser wraps all top-level statements in a
    // 'program.root' node. We push a global scope, visit every child
    // statement, then pop the scope.
    LParse.Config().RegisterSemanticRule('program.root',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.PushScope('global', ANode.GetToken());
        ASem.VisitChildren(ANode);
        ASem.PopScope(ANode.GetToken());
      end);

    // print statement: nothing special to analyze - just visit the
    // argument expression so its semantic rule can run.
    LParse.Config().RegisterSemanticRule('stmt.print',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);

    // String expression: tag the node with a type so downstream passes
    // ( codegen, type checking ) know this node carries a string value.
    LParse.Config().RegisterSemanticRule('expr.string',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        TParseASTNode(ANode).SetAttr(PARSE_ATTR_TYPE_KIND,
          TValue.From<string>('string'));
      end);

    //=========================================================================
    // CODEGEN - Define how each AST node emits C++23 code.
    //
    // Emitters write to two buffers: sfHeader ( .h file ) and sfSource
    // ( .cpp file ). The IR layer automatically handles the #include of
    // the header in the source file. IndentIn/IndentOut manage indentation.
    //=========================================================================

    // Program root emitter.
    // Write the header guard and system includes to the .h file.
    // Write the main() scaffold to the .cpp file, visiting all child
    // statements in between so their emitters fire in order.
    LParse.Config().RegisterEmitter('program.root',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        AGen.EmitLine('#pragma once', sfHeader);
        AGen.EmitLine('#include <cstdio>', sfHeader);
        AGen.EmitLine('int main() {', sfSource);
        AGen.IndentIn();
        AGen.EmitChildren(ANode);
        AGen.EmitLine('return 0;', sfSource);
        AGen.IndentOut();
        AGen.EmitLine('}', sfSource);
      end);

    // print statement emitter.
    // Read the string token text from the child expression node and emit
    // a printf() call. The token text already includes the quotes and any
    // escape sequences processed by the lexer ( e.g. \n ).
    LParse.Config().RegisterEmitter('stmt.print',
      procedure(ANode: TParseASTNodeBase; AGen: TParseIRBase)
      begin
        AGen.EmitLine('printf(' + ANode.GetChild(0).GetToken().Text + ');',
          sfSource);
      end);

    //=========================================================================
    // CONFIGURE - Set source file, output path, and build options.
    //
    // The output path determines where everything lands:
    //   output/config/     - saved language configuration ( TOML )
    //   output/generated/  - emitted .h and .cpp files
    //   output/zig-out/    - compiled binary
    //=========================================================================
    // Write a minimal source file for our language.
    TDirectory.CreateDirectory('output\src');
    TFile.WriteAllText('output\src\hello.src', 'print "Hello, World!";',
      TEncoding.UTF8);

    // Point TParse at the source file and output directory.
    LParse.SetSourceFile('output\src\hello.src');
    LParse.SetOutputPath('output');
    // Set build target: Win64 executable, debug optimization.
    LParse.SetTargetPlatform(tpWin64);
    //LParse.SetTargetPlatform(tpLinux64);
    LParse.SetBuildMode(bmExe);
    LParse.SetOptimizeLevel(olDebug);

    // Output callback: receives raw build output and program stdout.
    // Print directly - no prefix - so TTY formatting ( colors, progress )
    // from the C++ compiler passes through cleanly.
    LParse.SetOutputCallback(
      procedure(const ALine: string; const AUserData: Pointer)
      begin
        TParseUtils.Print(ALine);
      end);

    // Status callback: receives pipeline progress messages from TParse
    // ( e.g. "Tokenizing...", "Building...", "Build succeeded" ).
    LParse.SetStatusCallback(
      procedure(const AText: string; const AUserData: Pointer)
      begin
        TParseUtils.PrintLn(AText);
      end);

    //=========================================================================
    // COMPILE & RUN
    //
    // Compile( True ) drives the full pipeline:
    //   1. Lexer tokenizes the source file
    //   2. Parser builds the AST from the token stream
    //   3. Semantics walks the AST ( scope, types, validation )
    //   4. CodeGen emits .h and .cpp files to output/generated/
    //   5. Zig compiles the C++23 to a native executable
    //   6. The executable runs ( AAutoRun = True )
    //
    // Returns True if every step succeeded. GetLastExitCode() returns the
    // exit code of the compiled program.
    //=========================================================================
    if not LParse.Compile(True) then
    begin
      TParseUtils.PrintLn(COLOR_RED + 'Compilation failed.');
      ShowErrors(LParse);
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
