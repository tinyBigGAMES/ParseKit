{===============================================================================
  Parse()™ - Compiler Construction Toolkit
  ParseLang — .parse meta-language semantic rules

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

(*
  ParseLang.Semantics — Semantic Rules for the .parse Meta-Language

  Registers semantic analysis handlers for .parse AST nodes. The primary
  responsibilities are:
    - Validate that exactly one language declaration appears
    - Walk all top-level rule/section nodes so their children are visited
    - Collect helper function declarations into a shared scope for name lookup

  The semantic pass here is intentionally lightweight. Most validation is
  deferred: if a .parse file is structurally correct (the Grammar accepted it)
  and the CodeGen can walk the AST successfully, that is sufficient. Heavy
  semantic validation would add complexity without meaningful benefit for a
  meta-language whose primary consumer is the CodeGen interpreter.
*)

unit ParseLang.Semantics;

{$I ..\src\Parse.Defines.inc}

interface

uses
  System.SysUtils,
  Parse;

procedure ConfigSemantics(const AParse: TParse);

implementation

uses
  System.Rtti;

// =========================================================================
// SCOPE AND STRUCTURE
// =========================================================================

// --- Program Root ---
// Walk all children under the root node after entering a global scope.

procedure RegisterProgramRoot(const AParse: TParse);
begin
  AParse.Config().RegisterSemanticRule('program.root',
    procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
    begin
      ASem.PushScope('global', ANode.GetToken());
      ASem.VisitChildren(ANode);
      ASem.PopScope(ANode.GetToken());
    end);
end;

// =========================================================================
// LANGUAGE DECLARATION
// =========================================================================

procedure RegisterLanguageDecl(const AParse: TParse);
begin
  AParse.Config().RegisterSemanticRule('stmt.language_decl',
    procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
    var
      LAttr:    TValue;
      LLangName: string;
    begin
      ANode.GetAttr('lang.name', LAttr);
      LLangName := LAttr.AsString;
      // Declare the language name so duplicate declarations can be detected
      if not ASem.DeclareSymbol(LLangName, ANode) then
        ASem.AddSemanticError(ANode, 'PL001',
          'Duplicate language declaration: ' + LLangName);
    end);
end;

// =========================================================================
// TOP-LEVEL SECTION WALKERS
// =========================================================================

// These handlers exist solely to satisfy the semantic engine traversal.
// Each one walks its children so child nodes with their own handlers get visited.

procedure RegisterSectionWalkers(const AParse: TParse);
begin
  AParse.Config()
    .RegisterSemanticRule('stmt.tokens_block',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end)
    .RegisterSemanticRule('stmt.keywords_block',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end)
    .RegisterSemanticRule('stmt.operators_block',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end)
    .RegisterSemanticRule('stmt.strings_block',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end)
    .RegisterSemanticRule('stmt.comments_block',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end)
    .RegisterSemanticRule('stmt.structural_block',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end)
    .RegisterSemanticRule('stmt.types_block',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end)
    .RegisterSemanticRule('stmt.literals_block',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end)
    .RegisterSemanticRule('stmt.typemap_block',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);
end;

// =========================================================================
// GRAMMAR RULE WALKERS
// =========================================================================

procedure RegisterRuleWalkers(const AParse: TParse);
begin
  AParse.Config()
    .RegisterSemanticRule('stmt.prefix_rule',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        // No deep validation: block bodies are interpreter-executed at CodeGen time
        ASem.VisitChildren(ANode);
      end)
    .RegisterSemanticRule('stmt.infix_rule',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end)
    .RegisterSemanticRule('stmt.statement_rule',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end)
    .RegisterSemanticRule('stmt.exproverride_rule',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end)
    .RegisterSemanticRule('stmt.semantic_rule',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end)
    .RegisterSemanticRule('stmt.emit_rule',
      procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
      begin
        ASem.VisitChildren(ANode);
      end);
end;

// =========================================================================
// HELPER FUNCTION DECLARATIONS
// =========================================================================

procedure RegisterHelperFuncSem(const AParse: TParse);
begin
  AParse.Config().RegisterSemanticRule('stmt.helper_func',
    procedure(ANode: TParseASTNodeBase; ASem: TParseSemanticBase)
    var
      LAttr:     TValue;
      LFuncName: string;
    begin
      ANode.GetAttr('func.name', LAttr);
      LFuncName := LAttr.AsString;
      // Declare helper function in global scope for duplicate detection
      if not ASem.DeclareSymbol(LFuncName, ANode) then
        ASem.AddSemanticError(ANode, 'PL010',
          'Duplicate helper function: ' + LFuncName);
      // Enter the helper's scope for body traversal
      ASem.PushScope(LFuncName, ANode.GetToken());
      ASem.VisitChildren(ANode);
      ASem.PopScope(ANode.GetToken());
    end);
end;

// =========================================================================
// PUBLIC ENTRY POINT
// =========================================================================

procedure ConfigSemantics(const AParse: TParse);
begin
  RegisterProgramRoot(AParse);
  RegisterLanguageDecl(AParse);
  RegisterSectionWalkers(AParse);
  RegisterRuleWalkers(AParse);
  RegisterHelperFuncSem(AParse);
end;

end.
