{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

program Testbed;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  Parse.Common in '..\src\Parse.Common.pas',
  Parse.Config in '..\src\Parse.Config.pas',
  Parse.LangConfig in '..\src\Parse.LangConfig.pas',
  Parse.Lexer in '..\src\Parse.Lexer.pas',
  Parse.Parser in '..\src\Parse.Parser.pas',
  Parse.Resources in '..\src\Parse.Resources.pas',
  Parse.IR in '..\src\Parse.IR.pas',
  Parse.Semantics in '..\src\Parse.Semantics.pas',
  Parse.TOML in '..\src\Parse.TOML.pas',
  Parse.Utils in '..\src\Parse.Utils.pas',
  UTest.IR in 'UTest.IR.pas',
  UTest.Lexer in 'UTest.Lexer.pas',
  UTest.Parser in 'UTest.Parser.pas',
  UTest.Semantics in 'UTest.Semantics.pas',
  UTestbed in 'UTestbed.pas',
  Parse.CodeGen in '..\src\Parse.CodeGen.pas',
  Parse.Build in '..\src\Parse.Build.pas',
  Parse in '..\src\Parse.pas',
  UTest.Parse in 'UTest.Parse.pas',
  ULang.Pascal in '..\languages\ULang.Pascal.pas',
  ULang.Basic in '..\languages\ULang.Basic.pas',
  ULang.Lua in '..\languages\ULang.Lua.pas',
  ULang.Scheme in '..\languages\ULang.Scheme.pas';

begin
  RunTestbed();
end.
