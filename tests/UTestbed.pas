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
  System.Math,
  System.StrUtils,
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
  ULang.Scheme,
  ParseLang;

procedure ShowErrors(const AParseLang: TParseLang);
var
  LErrors: TParseErrors;
  LError:  TParseError;
  LColor:  string;
  LI:      Integer;
begin
  if not AParseLang.HasErrors() then
    Exit;

  LErrors := AParseLang.GetErrors();
  if LErrors = nil then
    Exit;

  TParseUtils.PrintLn('');
  TParseUtils.PrintLn(COLOR_WHITE + Format('Errors (%d):', [LErrors.Count()]));
  for LI := 0 to LErrors.GetItems().Count - 1 do
  begin
    LError := LErrors.GetItems()[LI];
    case LError.Severity of
      esHint:    LColor := COLOR_CYAN;
      esWarning: LColor := COLOR_YELLOW;
      esError:   LColor := COLOR_RED;
      esFatal:   LColor := COLOR_BOLD + COLOR_RED;
    else
      LColor := COLOR_WHITE;
    end;
    TParseUtils.PrintLn(LColor + LError.ToFullString());
  end;
end;

procedure TestParseLang();
var
  LParseLang: TParseLang;
begin
  LParseLang := TParseLang.Create();
  try
    LParseLang.SetLangFile('..\parselang\mylang.parse');
    LParseLang.SetSourceFile('..\parselang\hello.ml');
    LParseLang.SetOutputPath('output');
    LParseLang.SetStatusCallback(
      procedure(const AText: string; const AUserData: Pointer)
      begin
        TParseUtils.PrintLn(AText);
      end
    );

    LParseLang.SetOutputCallback(
      procedure(const ALine: string; const AUserData: Pointer)
      begin
        TParseUtils.Print(ALine);
      end
    );

    LParseLang.Compile(True, True);
    ShowErrors(LParseLang);

  finally
    LParseLang.Free();
  end;
end;

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

    LNum := 98;

    case LNum of
      01: ULang.Pascal.Demo(LPlatform, LLevel);
      02: ULang.Basic.Demo(LPlatform, LLevel);
      03: ULang.Lua.Demo(LPlatform, LLevel);
      04: ULang.Scheme.Demo(LPlatform, LLevel);
      98: TestParseLang();
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
