{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

unit UTest.Lexer;

{$I Parse.Defines.inc}

interface

procedure Test01();
procedure Test02();
procedure Test03();

implementation

uses
  System.SysUtils,
  System.Rtti,
  Parse.Utils,
  Parse.Common,
  Parse.Resources,
  Parse.LangConfig,
  Parse.Lexer;

//=============================================================================
// Shared helpers
//=============================================================================

procedure PrintHeader(const ATitle: string);
begin
  TParseUtils.PrintLn('');
  TParseUtils.PrintLn(COLOR_CYAN + StringOfChar('=', 70));
  TParseUtils.PrintLn(COLOR_CYAN + '  ' + ATitle);
  TParseUtils.PrintLn(COLOR_CYAN + StringOfChar('=', 70));
end;

procedure PrintErrors(const AErrors: TParseErrors);
var
  LI: Integer;
begin
  for LI := 0 to AErrors.GetItems().Count - 1 do
    TParseUtils.PrintLn(COLOR_RED + '  ' + AErrors.GetItems()[LI].ToFullString());
end;

procedure PrintResult(const APassed: Boolean);
begin
  if APassed then
    TParseUtils.PrintLn(COLOR_GREEN + '  RESULT: PASS')
  else
    TParseUtils.PrintLn(COLOR_RED + '  RESULT: FAIL');
  TParseUtils.PrintLn('');
end;

//=============================================================================
// Test01 — Keywords and identifiers
//
// Configures a Delphi/NitroPascal keyword set and tokenizes a simple
// procedure declaration. Verifies that registered keywords emit their
// kind strings and plain words emit 'identifier'.
//=============================================================================
procedure Test01();
var
  LSource: string;
  LConfig: TParseLangConfig;
  LErrors: TParseErrors;
  LLexer:  TParseLexer;
  LPassed: Boolean;
  LI:      Integer;
  LToken:  TParseToken;
begin
  PrintHeader('Test01 — Keywords and identifiers (Delphi/NitroPascal style)');

  LSource :=
    '''
    unit MyUnit;

    interface

    type
      TMyClass = class
      end;

    procedure DoSomething(AValue: Integer);

    implementation

    procedure DoSomething(AValue: Integer);
    var
      LResult: Boolean;
    begin
      if AValue > 0 then
        LResult := True
      else
        LResult := False;
    end;

    end.
    ''';

  LConfig := TParseLangConfig.Create();
  LErrors := TParseErrors.Create();
  LLexer  := nil;
  try
    // Delphi/NitroPascal keyword set
    LConfig
      .AddKeyword('unit',           'keyword.unit')
      .AddKeyword('interface',      'keyword.interface')
      .AddKeyword('implementation', 'keyword.implementation')
      .AddKeyword('type',           'keyword.type')
      .AddKeyword('class',          'keyword.class')
      .AddKeyword('procedure',      'keyword.procedure')
      .AddKeyword('function',       'keyword.function')
      .AddKeyword('var',            'keyword.var')
      .AddKeyword('const',          'keyword.const')
      .AddKeyword('begin',          'keyword.begin')
      .AddKeyword('end',            'keyword.end')
      .AddKeyword('if',             'keyword.if')
      .AddKeyword('then',           'keyword.then')
      .AddKeyword('else',           'keyword.else')
      .AddKeyword('while',          'keyword.while')
      .AddKeyword('do',             'keyword.do')
      .AddKeyword('for',            'keyword.for')
      .AddKeyword('to',             'keyword.to')
      .AddKeyword('downto',         'keyword.downto')
      .AddKeyword('repeat',         'keyword.repeat')
      .AddKeyword('until',          'keyword.until')
      .AddKeyword('uses',           'keyword.uses')
      .AddKeyword('true',           'keyword.true')
      .AddKeyword('false',          'keyword.false')
      .AddKeyword('nil',            'keyword.nil')
      .AddKeyword('Integer',        'type.integer')
      .AddKeyword('Boolean',        'type.boolean')
      .AddKeyword('String',         'type.string')
      .AddKeyword('Char',           'type.char');

    // Minimal punctuation needed to tokenize the snippet cleanly
    LConfig
      .AddOperator(':=', 'op.assign')
      .AddOperator(':',  'op.colon')
      .AddOperator(';',  'delimiter.semicolon')
      .AddOperator('.',  'delimiter.dot')
      .AddOperator(',',  'delimiter.comma')
      .AddOperator('(',  'delimiter.lparen')
      .AddOperator(')',  'delimiter.rparen')
      .AddOperator('>',  'op.greater')
      .AddOperator('=',  'op.equal');

    // Save config snapshot to output folder
    LConfig.SetConfigFilename('output/config/test01_keywords.toml');
    LConfig.SaveConfig();

    LLexer := TParseLexer.Create();
    LLexer.SetErrors(LErrors);
    LLexer.SetConfig(LConfig);
    LLexer.LoadFromString(LSource, 'test01.pas');
    LLexer.Tokenize();

    TParseUtils.PrintLn(LLexer.Dump());

    LPassed := True;

    if LErrors.HasErrors() then
    begin
      PrintErrors(LErrors);
      LPassed := False;
    end
    else
    begin
      for LI := 0 to LLexer.GetTokenCount() - 1 do
      begin
        LToken := LLexer.GetToken(LI);

        if SameText(LToken.Text, 'unit') and (LToken.Kind <> 'keyword.unit') then
        begin
          TParseUtils.PrintLn(COLOR_RED +
            '  FAIL: "unit" expected "keyword.unit", got "' + LToken.Kind + '"');
          LPassed := False;
        end;

        if SameText(LToken.Text, 'MyUnit') and (LToken.Kind <> 'identifier') then
        begin
          TParseUtils.PrintLn(COLOR_RED +
            '  FAIL: "MyUnit" expected "identifier", got "' + LToken.Kind + '"');
          LPassed := False;
        end;

        if SameText(LToken.Text, 'begin') and (LToken.Kind <> 'keyword.begin') then
        begin
          TParseUtils.PrintLn(COLOR_RED +
            '  FAIL: "begin" expected "keyword.begin", got "' + LToken.Kind + '"');
          LPassed := False;
        end;

        if SameText(LToken.Text, 'DoSomething') and (LToken.Kind <> 'identifier') then
        begin
          TParseUtils.PrintLn(COLOR_RED +
            '  FAIL: "DoSomething" expected "identifier", got "' + LToken.Kind + '"');
          LPassed := False;
        end;
      end;
    end;

    PrintResult(LPassed);

  finally
    FreeAndNil(LLexer);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

//=============================================================================
// Test02 — Operators, numbers and string literals
//
// Configures Delphi-style operators, hex prefix '$', decimal/real numbers,
// and single-quote string literals. Tokenizes an expression snippet and
// verifies TValue fields on literals.
//=============================================================================
procedure Test02();
var
  LSource:    string;
  LConfig:    TParseLangConfig;
  LErrors:    TParseErrors;
  LLexer:     TParseLexer;
  LPassed:    Boolean;
  LI:         Integer;
  LToken:     TParseToken;
  LFoundHex:  Boolean;
  LFoundReal: Boolean;
  LFoundStr:  Boolean;
begin
  PrintHeader('Test02 — Operators, numbers and string literals (Delphi/NitroPascal style)');

  LSource :=
    '''
    const
      MaxValue = $FF;
      Pi       = 3.14159;
      Greeting = 'Hello, World!';

    begin
      x := MaxValue + 10;
      y := x * 2 - 1;
      if (x <> y) and (x >= 0) then
        z := x .. y;
    end.
    ''';

  LConfig := TParseLangConfig.Create();
  LErrors := TParseErrors.Create();
  LLexer  := nil;
  try
    // Keywords
    LConfig
      .AddKeyword('const', 'keyword.const')
      .AddKeyword('begin', 'keyword.begin')
      .AddKeyword('end',   'keyword.end')
      .AddKeyword('if',    'keyword.if')
      .AddKeyword('then',  'keyword.then')
      .AddKeyword('and',   'keyword.and')
      .AddKeyword('or',    'keyword.or')
      .AddKeyword('not',   'keyword.not');

    // Delphi hex prefix
    LConfig.SetHexPrefix('$', 'literal.integer');

    // Delphi operators — multi-char registered before single-char;
    // the config sorts longest-first automatically
    LConfig
      .AddOperator(':=', 'op.assign')
      .AddOperator('<>', 'op.notequal')
      .AddOperator('<=', 'op.lte')
      .AddOperator('>=', 'op.gte')
      .AddOperator('..', 'op.range')
      .AddOperator('+',  'op.plus')
      .AddOperator('-',  'op.minus')
      .AddOperator('*',  'op.star')
      .AddOperator('/',  'op.slash')
      .AddOperator('=',  'op.equal')
      .AddOperator('<',  'op.lt')
      .AddOperator('>',  'op.gt')
      .AddOperator(':',  'op.colon')
      .AddOperator(';',  'delimiter.semicolon')
      .AddOperator(',',  'delimiter.comma')
      .AddOperator('.',  'delimiter.dot')
      .AddOperator('(',  'delimiter.lparen')
      .AddOperator(')',  'delimiter.rparen')
      .AddOperator('[',  'delimiter.lbracket')
      .AddOperator(']',  'delimiter.rbracket');

    // Delphi single-quote string; no backslash escaping in Pascal strings
    LConfig.AddStringStyle('''', '''', 'literal.string', False);

    // Save config snapshot to output folder
    LConfig.SetConfigFilename('output/config/test02_operators_numbers.toml');
    LConfig.SaveConfig();

    LLexer := TParseLexer.Create();
    LLexer.SetErrors(LErrors);
    LLexer.SetConfig(LConfig);
    LLexer.LoadFromString(LSource, 'test02.pas');
    LLexer.Tokenize();

    TParseUtils.PrintLn(LLexer.Dump());

    LPassed    := True;
    LFoundHex  := False;
    LFoundReal := False;
    LFoundStr  := False;

    if LErrors.HasErrors() then
    begin
      PrintErrors(LErrors);
      LPassed := False;
    end
    else
    begin
      for LI := 0 to LLexer.GetTokenCount() - 1 do
      begin
        LToken := LLexer.GetToken(LI);

        // $FF should be integer kind with Value = 255
        if (LToken.Kind = 'literal.integer') and (LToken.Text = '$FF') then
        begin
          LFoundHex := True;
          if not LToken.Value.IsEmpty and (LToken.Value.AsType<Int64>() <> 255) then
          begin
            TParseUtils.PrintLn(COLOR_RED +
              '  FAIL: $FF expected Value=255, got ' + LToken.Value.ToString());
            LPassed := False;
          end;
        end;

        // 3.14159 should be real kind
        if (LToken.Kind = 'literal.real') and (LToken.Text = '3.14159') then
          LFoundReal := True;

        // 'Hello, World!' should be string kind with correct Value
        if LToken.Kind = 'literal.string' then
        begin
          LFoundStr := True;
          if not LToken.Value.IsEmpty and
             (LToken.Value.AsType<string>() <> 'Hello, World!') then
          begin
            TParseUtils.PrintLn(COLOR_RED +
              '  FAIL: string literal expected "Hello, World!", got "' +
              LToken.Value.AsType<string>() + '"');
            LPassed := False;
          end;
        end;
      end;

      if not LFoundHex then
      begin
        TParseUtils.PrintLn(COLOR_RED + '  FAIL: hex literal $FF not found');
        LPassed := False;
      end;

      if not LFoundReal then
      begin
        TParseUtils.PrintLn(COLOR_RED + '  FAIL: real literal 3.14159 not found');
        LPassed := False;
      end;

      if not LFoundStr then
      begin
        TParseUtils.PrintLn(COLOR_RED + '  FAIL: string literal not found');
        LPassed := False;
      end;
    end;

    PrintResult(LPassed);

  finally
    FreeAndNil(LLexer);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

//=============================================================================
// Test03 — Comments, directives and error recovery
//
// Configures Delphi-style line comments (//), block comments ({ } and (* *)),
// and a directive prefix ($). Tokenizes source with all three comment styles,
// a directive, and one deliberate unknown character (@) to verify error
// reporting and that the stream still terminates with EOF.
//=============================================================================
procedure Test03();
var
  LSource:         string;
  LConfig:         TParseLangConfig;
  LErrors:         TParseErrors;
  LLexer:          TParseLexer;
  LPassed:         Boolean;
  LI:              Integer;
  LToken:          TParseToken;
  LFoundLineComm:  Boolean;
  LFoundBlockComm: Boolean;
  LFoundDirective: Boolean;
  LFoundEOF:       Boolean;
begin
  PrintHeader('Test03 — Comments, directives and error recovery (Delphi/NitroPascal style)');

  LSource :=
    '''
    // This is a line comment

    { This is a brace block comment }

    (* This is a paren-star block comment *)

    $IFDEF WIN64

    procedure Foo();
    begin
      { nested { comment } still going }
      x := 42;
      @ (* deliberate unknown char for error test *)
    end;
    ''';

  LConfig := TParseLangConfig.Create();
  LErrors := TParseErrors.Create();
  LLexer  := nil;
  try
    // Delphi comment styles
    LConfig
      .AddLineComment('//')
      .AddBlockComment('{', '}')
      .AddBlockComment('(*', '*)');

    // Standalone directive prefix
    LConfig.SetDirectivePrefix('$', 'directive');

    // Keywords
    LConfig
      .AddKeyword('procedure', 'keyword.procedure')
      .AddKeyword('begin',     'keyword.begin')
      .AddKeyword('end',       'keyword.end');

    // Minimal operators
    LConfig
      .AddOperator(':=', 'op.assign')
      .AddOperator(':',  'op.colon')
      .AddOperator(';',  'delimiter.semicolon')
      .AddOperator('(',  'delimiter.lparen')
      .AddOperator(')',  'delimiter.rparen')
      .AddOperator('.',  'delimiter.dot');

    // Save config snapshot to output folder
    LConfig.SetConfigFilename('output/config/test03_comments_directives.toml');
    LConfig.SaveConfig();

    LLexer := TParseLexer.Create();
    LLexer.SetErrors(LErrors);
    LLexer.SetConfig(LConfig);
    LLexer.LoadFromString(LSource, 'test03.pas');
    LLexer.Tokenize();

    TParseUtils.PrintLn(LLexer.Dump());

    LPassed          := True;
    LFoundLineComm   := False;
    LFoundBlockComm  := False;
    LFoundDirective  := False;
    LFoundEOF        := False;

    for LI := 0 to LLexer.GetTokenCount() - 1 do
    begin
      LToken := LLexer.GetToken(LI);

      if LToken.Kind = 'comment.line' then
        LFoundLineComm := True;

      if LToken.Kind = 'comment.block' then
        LFoundBlockComm := True;

      if LToken.Kind = 'directive' then
        LFoundDirective := True;

      if LToken.Kind = 'eof' then
        LFoundEOF := True;
    end;

    if not LFoundLineComm then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: no line comment token found');
      LPassed := False;
    end;

    if not LFoundBlockComm then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: no block comment token found');
      LPassed := False;
    end;

    if not LFoundDirective then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: no directive token found');
      LPassed := False;
    end;

    if not LFoundEOF then
    begin
      TParseUtils.PrintLn(COLOR_RED + '  FAIL: no EOF token found');
      LPassed := False;
    end;

    // The '@' character is unknown — expect exactly one error
    if LErrors.ErrorCount() <> 1 then
    begin
      TParseUtils.PrintLn(COLOR_RED +
        Format('  FAIL: expected 1 error for "@", got %d', [LErrors.ErrorCount()]));
      PrintErrors(LErrors);
      LPassed := False;
    end
    else
      TParseUtils.PrintLn(COLOR_GREEN +
        '  OK: unknown char "@" correctly produced 1 error: ' +
        LErrors.GetItems()[0].ToFullString());

    PrintResult(LPassed);

  finally
    FreeAndNil(LLexer);
    FreeAndNil(LErrors);
    FreeAndNil(LConfig);
  end;
end;

end.
