{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

unit UTestbed;

interface

procedure RunTestbed();

implementation

uses
  System.SysUtils,
  Parse,
  UTest.Lexer,
  UTest.Parser,
  UTest.Semantics,
  UTest.IR,
  UTest.CodeGen,
  UTest.Parse,
  ULang.Pascal,
  ULang.Basic,
  ULang.Lua,
  ULang.Scheme;

procedure RunTestbed();
var
  LPlatform: TParseTargetPlatform;
  LLevel: TParseOptimizeLevel;
  LNum: Integer;
begin
  try

    { Lexer }
    //UTest.Lexer.Test01();
    //UTest.Lexer.Test02();
    //UTest.Lexer.Test03();

    { Parser }
    //UTest.Parser.Test01();
    //UTest.Parser.Test02();
    //UTest.Parser.Test03();
    //UTest.Parser.Test04();

    { Semantics }
    //UTest.Semantics.Test01();
    //UTest.Semantics.Test02();
    //UTest.Semantics.Test03();
    //UTest.Semantics.Test04();
    //UTest.Semantics.Test05();
    //UTest.Semantics.Test06();
    //UTest.Semantics.Test07();
    //UTest.Semantics.Test08();

    { IR }
    //UTest.IR.Test01();
    //UTest.IR.Test02();
    //UTest.IR.Test03();
    //UTest.IR.Test04();
    //UTest.IR.Test05();
    //UTest.IR.Test06();

    { CodeGen }
    //UTest.CodeGen.Test01();
    //UTest.CodeGen.Test02();
    //UTest.CodeGen.Test03();
    //UTest.CodeGen.Test04();

    { Language }
    LPlatform := tpWin64;
    //LPlatform := tpLinux64;

    LLevel := olDebug;
    //LLevel := olReleaseSmall;

    LNum := 1;

    case LNum of
      01: ULang.Pascal.Demo(LPlatform, LLevel);
      02: ULang.Basic.Demo(LPlatform, LLevel);
      03: ULang.Lua.Demo(LPlatform, LLevel);
      04: ULang.Scheme.Demo(LPlatform, LLevel);
    end;
  except
    on E: Exception do
    begin
      TParseUtils.PrintLn('');
      TParseUtils.PrintLn(COLOR_RED + 'EXCEPTION: ' + E.Message);
    end;
  end;

  if TParseUtils.RunFromIDE() then
    TParseUtils.Pause();
end;

end.
