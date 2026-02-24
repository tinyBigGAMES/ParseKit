{===============================================================================
  Parse()™ - Compiler Construction Toolkit

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://parsekit.org

  See LICENSE for license information
===============================================================================}

unit Parse.Lexer;

{$I Parse.Defines.inc}

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Math,
  System.Rtti,
  System.Generics.Collections,
  Parse.Utils,
  Parse.Common,
  Parse.LangConfig,
  Parse.Resources;

type

  { TParseLexer }
  TParseLexer = class(TParseErrorsObject)
  private
    FConfig:     TParseLangConfig;  // not owned -- caller manages lifetime
    FFilename:   string;
    FSource:     string;
    FPos:        Integer;
    FLine:       Integer;
    FColumn:     Integer;
    FByteOffset: Integer;
    FTokens:     TList<TParseToken>;

    // -- Character navigation -------------------------------------------------
    function  Peek(const AOffset: Integer = 0): Char;
    function  IsEOF(): Boolean;
    procedure Advance();
    procedure AdvanceN(const ACount: Integer);
    procedure SkipWhitespace();

    // -- Token scanning -------------------------------------------------------
    function ScanLineComment(var AToken: TParseToken): Boolean;
    function ScanBlockComment(var AToken: TParseToken): Boolean;
    function ScanDirective(var AToken: TParseToken): Boolean;
    function ScanStringStyle(var AToken: TParseToken): Boolean;
    function ScanIdentifierOrKeyword(): TParseToken;
    function ScanNumber(): TParseToken;
    function ScanOperator(var AToken: TParseToken): Boolean;

    // -- Helpers --------------------------------------------------------------
    function MakeToken(const AKind: string;
      const AStartLine, AStartCol, AStartOffset: Integer): TParseToken;
    function ProcessEscapeSequence(var AValid: Boolean): Char;
    function IsIdentifierStart(const AChar: Char): Boolean;
    function IsIdentifierPart(const AChar: Char): Boolean;
    function IsDigit(const AChar: Char): Boolean;
    function IsHexDigit(const AChar: Char): Boolean;
    function HexCharToInt(const AChar: Char): Integer;
    function MatchesAt(const AText: string; const AOffset: Integer = 0): Boolean;
    function IsNumberStart(): Boolean;
    function LookupKeyword(const AText: string; out AKind: string): Boolean;

  public
    constructor Create(); override;
    destructor Destroy(); override;

    procedure SetConfig(const AConfig: TParseLangConfig);

    function LoadFromFile(const AFilename: string): Boolean;
    function LoadFromString(const ASource: string;
      const AFilename: string = ''): Boolean;
    function Tokenize(): Boolean;

    function GetTokenCount(): Integer;
    function GetToken(const AIndex: Integer): TParseToken;
    function GetTokens(): TArray<TParseToken>;
    function GetFilename(): string;
    function GetSource(): string;

    function Dump(const AId: Integer = 0): string; override;
  end;

implementation

{ TParseLexer }

constructor TParseLexer.Create();
begin
  inherited Create();

  FConfig     := nil;
  FFilename   := '';
  FSource     := '';
  FPos        := 1;
  FLine       := 1;
  FColumn     := 1;
  FByteOffset := 0;
  FTokens     := TList<TParseToken>.Create();
end;

destructor TParseLexer.Destroy();
begin
  FreeAndNil(FTokens);
  // FConfig is not owned by this lexer -- caller manages its lifetime
  inherited;
end;

procedure TParseLexer.SetConfig(const AConfig: TParseLangConfig);
begin
  FConfig := AConfig;
end;

function TParseLexer.Peek(const AOffset: Integer): Char;
var
  LIndex: Integer;
begin
  LIndex := FPos + AOffset;
  if (LIndex >= 1) and (LIndex <= Length(FSource)) then
    Result := FSource[LIndex]
  else
    Result := #0;
end;

function TParseLexer.IsEOF(): Boolean;
begin
  Result := FPos > Length(FSource);
end;

procedure TParseLexer.Advance();
var
  LChar: Char;
begin
  if IsEOF() then
    Exit;

  LChar := FSource[FPos];
  Inc(FPos);
  Inc(FByteOffset);

  if LChar = #10 then
  begin
    Inc(FLine);
    FColumn := 1;
  end
  else if LChar <> #13 then
    Inc(FColumn);
end;

procedure TParseLexer.AdvanceN(const ACount: Integer);
var
  LI: Integer;
begin
  for LI := 1 to ACount do
    Advance();
end;

procedure TParseLexer.SkipWhitespace();
var
  LChar: Char;
begin
  while not IsEOF() do
  begin
    LChar := Peek();
    if (LChar = ' ') or (LChar = #9) or (LChar = #13) or (LChar = #10) then
      Advance()
    else
      Break;
  end;
end;

function TParseLexer.MakeToken(const AKind: string;
  const AStartLine, AStartCol, AStartOffset: Integer): TParseToken;
begin
  Result.Kind      := AKind;
  Result.Filename  := FFilename;
  Result.Line      := AStartLine;
  Result.Column    := AStartCol;
  Result.EndLine   := FLine;
  Result.EndColumn := FColumn;
  Result.Text      := '';
  Result.Value     := TValue.Empty;
end;

function TParseLexer.MatchesAt(const AText: string;
  const AOffset: Integer): Boolean;
var
  LI:   Integer;
  LPos: Integer;
begin
  Result := False;
  if AText = '' then
    Exit;
  LPos := FPos + AOffset;
  if LPos + Length(AText) - 1 > Length(FSource) then
    Exit;
  for LI := 1 to Length(AText) do
  begin
    if FSource[LPos + LI - 1] <> AText[LI] then
      Exit;
  end;
  Result := True;
end;

function TParseLexer.IsIdentifierStart(const AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, FConfig.GetIdentStartChars());
end;

function TParseLexer.IsIdentifierPart(const AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, FConfig.GetIdentPartChars());
end;

function TParseLexer.IsDigit(const AChar: Char): Boolean;
begin
  Result := (AChar >= '0') and (AChar <= '9');
end;

function TParseLexer.IsHexDigit(const AChar: Char): Boolean;
begin
  Result := ((AChar >= '0') and (AChar <= '9')) or
            ((AChar >= 'A') and (AChar <= 'F')) or
            ((AChar >= 'a') and (AChar <= 'f'));
end;

function TParseLexer.HexCharToInt(const AChar: Char): Integer;
begin
  if (AChar >= '0') and (AChar <= '9') then
    Result := Ord(AChar) - Ord('0')
  else if (AChar >= 'A') and (AChar <= 'F') then
    Result := 10 + Ord(AChar) - Ord('A')
  else if (AChar >= 'a') and (AChar <= 'f') then
    Result := 10 + Ord(AChar) - Ord('a')
  else
    Result := 0;
end;

function TParseLexer.LookupKeyword(const AText: string;
  out AKind: string): Boolean;
var
  LKey: string;
begin
  if FConfig.GetCaseSensitive() then
    LKey := AText
  else
    LKey := AText.ToLower();
  Result := FConfig.GetKeywords().TryGetValue(LKey, AKind);
end;

function TParseLexer.IsNumberStart(): Boolean;
var
  LI: Integer;
begin
  if IsDigit(Peek()) then
  begin
    Result := True;
    Exit;
  end;

  for LI := 0 to FConfig.GetHexPrefixes().Count - 1 do
  begin
    if MatchesAt(FConfig.GetHexPrefixes()[LI]) then
    begin
      Result := True;
      Exit;
    end;
  end;

  for LI := 0 to FConfig.GetBinaryPrefixes().Count - 1 do
  begin
    if MatchesAt(FConfig.GetBinaryPrefixes()[LI]) then
    begin
      Result := True;
      Exit;
    end;
  end;

  Result := False;
end;

function TParseLexer.ProcessEscapeSequence(var AValid: Boolean): Char;
var
  LHexVal: Integer;
begin
  AValid := True;
  Result := #0;

  Advance(); // skip the backslash

  if IsEOF() then
  begin
    AValid := False;
    Exit;
  end;

  case Peek() of
    'n':  begin Result := #10;  Advance(); end;
    't':  begin Result := #9;   Advance(); end;
    'r':  begin Result := #13;  Advance(); end;
    '0':  begin Result := #0;   Advance(); end;
    '\':  begin Result := '\';  Advance(); end;
    '''': begin Result := ''''; Advance(); end;
    '"':  begin Result := '"';  Advance(); end;
    'x':
      begin
        Advance(); // skip 'x'
        if IsHexDigit(Peek()) and IsHexDigit(Peek(1)) then
        begin
          LHexVal := HexCharToInt(Peek()) * 16 + HexCharToInt(Peek(1));
          Result  := Char(LHexVal);
          Advance();
          Advance();
        end
        else
        begin
          AValid := False;
          if Assigned(FErrors) then
            FErrors.Add(FFilename, FLine, FColumn, esError,
              ERR_LEXER_INVALID_HEX_ESCAPE, RSLexerInvalidHexEscape);
        end;
      end;
  else
    AValid := False;
    if Assigned(FErrors) then
      FErrors.Add(FFilename, FLine, FColumn, esError,
        ERR_LEXER_INVALID_ESCAPE, RSLexerInvalidEscape, [Peek()]);
    Advance();
  end;
end;

function TParseLexer.ScanLineComment(var AToken: TParseToken): Boolean;
var
  LI:           Integer;
  LPrefix:      string;
  LStartLine:   Integer;
  LStartCol:    Integer;
  LStartOffset: Integer;
begin
  Result := False;

  for LI := 0 to FConfig.GetLineComments().Count - 1 do
  begin
    LPrefix := FConfig.GetLineComments()[LI];
    if MatchesAt(LPrefix) then
    begin
      LStartLine   := FLine;
      LStartCol    := FColumn;
      LStartOffset := FByteOffset;

      while not IsEOF() and (Peek() <> #10) do
        Advance();
      if Peek() = #10 then
        Advance();

      AToken      := MakeToken(FConfig.GetLineCommentKind(),
                       LStartLine, LStartCol, LStartOffset);
      AToken.Text := FSource.Substring(LStartOffset,
                       FByteOffset - LStartOffset).Trim();
      Result      := True;
      Exit;
    end;
  end;
end;

function TParseLexer.ScanBlockComment(var AToken: TParseToken): Boolean;
var
  LI:           Integer;
  LBC:          TParseBlockCommentDef;
  LStartLine:   Integer;
  LStartCol:    Integer;
  LStartOffset: Integer;
  LNestLevel:   Integer;
begin
  Result := False;

  for LI := 0 to FConfig.GetBlockComments().Count - 1 do
  begin
    LBC := FConfig.GetBlockComments()[LI];
    if MatchesAt(LBC.OpenStr) then
    begin
      LStartLine   := FLine;
      LStartCol    := FColumn;
      LStartOffset := FByteOffset;
      LNestLevel   := 1;

      AdvanceN(Length(LBC.OpenStr));

      // Scan until matching close, supporting nested block comments
      while not IsEOF() and (LNestLevel > 0) do
      begin
        if MatchesAt(LBC.OpenStr) then
        begin
          Inc(LNestLevel);
          AdvanceN(Length(LBC.OpenStr));
        end
        else if MatchesAt(LBC.CloseStr) then
        begin
          Dec(LNestLevel);
          AdvanceN(Length(LBC.CloseStr));
        end
        else
          Advance();
      end;

      if LNestLevel > 0 then
      begin
        if Assigned(FErrors) then
          FErrors.Add(FFilename, LStartLine, LStartCol, esError,
            ERR_LEXER_UNTERMINATED_COMMENT, RSLexerUnterminatedComment);
      end;

      AToken      := MakeToken(FConfig.GetBlockCommentKind(),
                       LStartLine, LStartCol, LStartOffset);
      AToken.Text := FSource.Substring(LStartOffset,
                       FByteOffset - LStartOffset);
      Result      := True;
      Exit;
    end;
  end;
end;

function TParseLexer.ScanDirective(var AToken: TParseToken): Boolean;
var
  LPrefix:      string;
  LStartLine:   Integer;
  LStartCol:    Integer;
  LStartOffset: Integer;
  LStartPos:    Integer;
begin
  Result  := False;
  LPrefix := FConfig.GetDirectivePrefix();

  if (LPrefix = '') or not MatchesAt(LPrefix) then
    Exit;

  LStartLine   := FLine;
  LStartCol    := FColumn;
  LStartOffset := FByteOffset;
  LStartPos    := FPos;

  AdvanceN(Length(LPrefix));

  while not IsEOF() and IsIdentifierPart(Peek()) do
    Advance();

  AToken      := MakeToken(FConfig.GetDirectiveKind(),
                   LStartLine, LStartCol, LStartOffset);
  AToken.Text := FSource.Substring(LStartPos - 1, FPos - LStartPos);
  Result      := True;
end;

function TParseLexer.ScanStringStyle(var AToken: TParseToken): Boolean;
var
  LI:           Integer;
  LStyle:       TParseStringStyleDef;
  LStartLine:   Integer;
  LStartCol:    Integer;
  LStartOffset: Integer;
  LStartPos:    Integer;
  LBuilder:     TStringBuilder;
  LValid:       Boolean;
  LEscChar:     Char;
begin
  Result := False;

  for LI := 0 to FConfig.GetStringStyles().Count - 1 do
  begin
    LStyle := FConfig.GetStringStyles()[LI];
    if MatchesAt(LStyle.OpenStr) then
    begin
      LStartLine   := FLine;
      LStartCol    := FColumn;
      LStartOffset := FByteOffset;
      LStartPos    := FPos;

      AdvanceN(Length(LStyle.OpenStr));

      LBuilder := TStringBuilder.Create();
      try
        while not IsEOF() do
        begin
          if MatchesAt(LStyle.CloseStr) then
          begin
            AdvanceN(Length(LStyle.CloseStr));
            Break;
          end
          else if LStyle.AllowEscape and (Peek() = '\') then
          begin
            LEscChar := ProcessEscapeSequence(LValid);
            if LValid then
              LBuilder.Append(LEscChar);
          end
          else if (Peek() = #10) or (Peek() = #13) then
          begin
            if Assigned(FErrors) then
              FErrors.Add(FFilename, LStartLine, LStartCol, esError,
                ERR_LEXER_UNTERMINATED_STRING, RSLexerUnterminatedString);
            Break;
          end
          else
          begin
            LBuilder.Append(Peek());
            Advance();
          end;
        end;

        AToken       := MakeToken(LStyle.TokenKind,
                          LStartLine, LStartCol, LStartOffset);
        AToken.Text  := FSource.Substring(LStartPos - 1, FPos - LStartPos);
        AToken.Value := TValue.From<string>(LBuilder.ToString());
      finally
        LBuilder.Free();
      end;

      Result := True;
      Exit;
    end;
  end;
end;

function TParseLexer.ScanIdentifierOrKeyword(): TParseToken;
var
  LStartLine:   Integer;
  LStartCol:    Integer;
  LStartOffset: Integer;
  LStartPos:    Integer;
  LText:        string;
  LKind:        string;
begin
  LStartLine   := FLine;
  LStartCol    := FColumn;
  LStartOffset := FByteOffset;
  LStartPos    := FPos;

  while not IsEOF() and IsIdentifierPart(Peek()) do
    Advance();

  LText := FSource.Substring(LStartPos - 1, FPos - LStartPos);

  if LookupKeyword(LText, LKind) then
    Result := MakeToken(LKind, LStartLine, LStartCol, LStartOffset)
  else
    Result := MakeToken(FConfig.GetIdentifierKind(),
                LStartLine, LStartCol, LStartOffset);

  Result.Text := LText;
end;

function TParseLexer.ScanNumber(): TParseToken;
var
  LStartLine:   Integer;
  LStartCol:    Integer;
  LStartOffset: Integer;
  LStartPos:    Integer;
  LText:        string;
  LBody:        string;
  LMatchPrefix: string;
  LI:           Integer;
  LIsHex:       Boolean;
  LIsBinary:    Boolean;
  LIsReal:      Boolean;
  LHexValue:    UInt64;
  LIntValue:    Int64;
  LRealValue:   Double;
begin
  LStartLine   := FLine;
  LStartCol    := FColumn;
  LStartOffset := FByteOffset;
  LStartPos    := FPos;
  LIsHex       := False;
  LIsBinary    := False;
  LIsReal      := False;
  LMatchPrefix := '';

  // Check registered hex prefixes (e.g. '$', '0x')
  for LI := 0 to FConfig.GetHexPrefixes().Count - 1 do
  begin
    if MatchesAt(FConfig.GetHexPrefixes()[LI]) then
    begin
      LIsHex       := True;
      LMatchPrefix := FConfig.GetHexPrefixes()[LI];
      AdvanceN(Length(LMatchPrefix));
      while not IsEOF() and IsHexDigit(Peek()) do
        Advance();
      Break;
    end;
  end;

  // Check registered binary prefixes (e.g. '0b')
  if not LIsHex then
  begin
    for LI := 0 to FConfig.GetBinaryPrefixes().Count - 1 do
    begin
      if MatchesAt(FConfig.GetBinaryPrefixes()[LI]) then
      begin
        LIsBinary    := True;
        LMatchPrefix := FConfig.GetBinaryPrefixes()[LI];
        AdvanceN(Length(LMatchPrefix));
        while not IsEOF() and ((Peek() = '0') or (Peek() = '1')) do
          Advance();
        Break;
      end;
    end;
  end;

  // Decimal integer or float
  if not LIsHex and not LIsBinary then
  begin
    while not IsEOF() and IsDigit(Peek()) do
      Advance();

    // Decimal point — only if followed by a digit (avoids consuming '..')
    if (Peek() = '.') and (Peek(1) <> '.') and IsDigit(Peek(1)) then
    begin
      LIsReal := True;
      Advance();
      while not IsEOF() and IsDigit(Peek()) do
        Advance();
    end;

    // Exponent
    if (Peek() = 'e') or (Peek() = 'E') then
    begin
      LIsReal := True;
      Advance();
      if (Peek() = '+') or (Peek() = '-') then
        Advance();
      while not IsEOF() and IsDigit(Peek()) do
        Advance();
    end;

    // Optional float32 suffix 'f' or 'F'
    if LIsReal and ((Peek() = 'f') or (Peek() = 'F')) then
      Advance();
  end;

  LText := FSource.Substring(LStartPos - 1, FPos - LStartPos);

  if LIsHex then
  begin
    Result      := MakeToken(FConfig.GetHexKind(),
                     LStartLine, LStartCol, LStartOffset);
    Result.Text := LText;
    LBody       := LText.Substring(Length(LMatchPrefix));
    LHexValue   := 0;
    if TryStrToUInt64('$' + LBody, LHexValue) then
      Result.Value := TValue.From<Int64>(Int64(LHexValue))
    else
    begin
      if Assigned(FErrors) then
        FErrors.Add(FFilename, LStartLine, LStartCol, esError,
          ERR_LEXER_INVALID_NUMBER, RSLexerInvalidNumber, [LText]);
    end;
  end
  else if LIsBinary then
  begin
    Result      := MakeToken(FConfig.GetBinaryKind(),
                     LStartLine, LStartCol, LStartOffset);
    Result.Text := LText;
    LBody       := LText.Substring(Length(LMatchPrefix));
    LIntValue   := 0;
    for LI := 1 to Length(LBody) do
    begin
      LIntValue := LIntValue * 2;
      if LBody[LI] = '1' then
        Inc(LIntValue);
    end;
    Result.Value := TValue.From<Int64>(LIntValue);
  end
  else if LIsReal then
  begin
    Result      := MakeToken(FConfig.GetRealKind(),
                     LStartLine, LStartCol, LStartOffset);
    Result.Text := LText;
    LBody       := LText;
    if (LBody <> '') and
       ((LBody[Length(LBody)] = 'f') or (LBody[Length(LBody)] = 'F')) then
      LBody := LBody.Substring(0, LBody.Length - 1);
    if TryStrToFloat(LBody, LRealValue, TFormatSettings.Invariant) then
      Result.Value := TValue.From<Double>(LRealValue)
    else
    begin
      if Assigned(FErrors) then
        FErrors.Add(FFilename, LStartLine, LStartCol, esError,
          ERR_LEXER_INVALID_NUMBER, RSLexerInvalidNumber, [LText]);
    end;
  end
  else
  begin
    Result      := MakeToken(FConfig.GetIntegerKind(),
                     LStartLine, LStartCol, LStartOffset);
    Result.Text := LText;
    if TryStrToInt64(LText, LIntValue) then
      Result.Value := TValue.From<Int64>(LIntValue)
    else
    begin
      if Assigned(FErrors) then
        FErrors.Add(FFilename, LStartLine, LStartCol, esError,
          ERR_LEXER_INVALID_NUMBER, RSLexerInvalidNumber, [LText]);
    end;
  end;
end;

function TParseLexer.ScanOperator(var AToken: TParseToken): Boolean;
var
  LI:           Integer;
  LOp:          TParseOperatorDef;
  LStartLine:   Integer;
  LStartCol:    Integer;
  LStartOffset: Integer;
begin
  Result       := False;
  LStartLine   := FLine;
  LStartCol    := FColumn;
  LStartOffset := FByteOffset;

  // Operators are pre-sorted longest-first; first match wins
  for LI := 0 to FConfig.GetOperators().Count - 1 do
  begin
    LOp := FConfig.GetOperators()[LI];
    if MatchesAt(LOp.Text) then
    begin
      AdvanceN(Length(LOp.Text));
      AToken      := MakeToken(LOp.TokenKind, LStartLine, LStartCol, LStartOffset);
      AToken.Text := LOp.Text;
      Result      := True;
      Exit;
    end;
  end;
end;

function TParseLexer.LoadFromFile(const AFilename: string): Boolean;
begin
  Result := False;

  if not TFile.Exists(AFilename) then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, ERR_LEXER_FILE_NOT_FOUND, RSLexerFileNotFound,
        [AFilename]);
    Exit;
  end;

  try
    FFilename   := TPath.GetFullPath(AFilename).Replace('\', '/');
    FSource     := TFile.ReadAllText(FFilename);
    FPos        := 1;
    FLine       := 1;
    FColumn     := 1;
    FByteOffset := 0;
    FTokens.Clear();
    Result := True;
  except
    on E: Exception do
    begin
      if Assigned(FErrors) then
        FErrors.Add(esError, ERR_LEXER_FILE_READ_ERROR, RSLexerFileReadError,
          [AFilename, E.Message]);
    end;
  end;
end;

function TParseLexer.LoadFromString(const ASource: string;
  const AFilename: string): Boolean;
begin
  Result := False;

  if AFilename <> '' then
  begin
    try
      FFilename := TPath.GetFullPath(AFilename).Replace('\', '/');
    except
      on E: Exception do
      begin
        if Assigned(FErrors) then
          FErrors.Add(esFatal, ERR_LEXER_INVALID_FILENAME,
            RSLexerInvalidFilename, [AFilename, E.Message]);
        Exit;
      end;
    end;
  end
  else
    FFilename := '';

  FSource     := ASource;
  FPos        := 1;
  FLine       := 1;
  FColumn     := 1;
  FByteOffset := 0;
  FTokens.Clear();
  Result := True;
end;

function TParseLexer.Tokenize(): Boolean;
var
  LChar:  Char;
  LToken: TParseToken;
begin
  FTokens.Clear();

  Status(RSLexerTokenizing, [FFilename]);

  while not IsEOF() do
  begin
    SkipWhitespace();

    if IsEOF() then
      Break;

    // 1. Line comments — checked before operators so '//' beats '/'
    if ScanLineComment(LToken) then
    begin
      FTokens.Add(LToken);
      Continue;
    end;

    // 2. Block comments
    if ScanBlockComment(LToken) then
    begin
      FTokens.Add(LToken);
      Continue;
    end;

    // 3. Directives (e.g. '$ifdef' when prefix = '$')
    if ScanDirective(LToken) then
    begin
      FTokens.Add(LToken);
      Continue;
    end;

    // 4. String literals (all registered styles, first match wins)
    if ScanStringStyle(LToken) then
    begin
      FTokens.Add(LToken);
      Continue;
    end;

    // 5. Identifiers and keywords
    if IsIdentifierStart(Peek()) then
    begin
      LToken := ScanIdentifierOrKeyword();
      FTokens.Add(LToken);
      Continue;
    end;

    // 6. Numbers (digits and all registered hex/binary prefixes)
    if IsNumberStart() then
    begin
      LToken := ScanNumber();
      FTokens.Add(LToken);
      Continue;
    end;

    // 7. Operators and delimiters (longest-match among registered operators)
    if ScanOperator(LToken) then
    begin
      FTokens.Add(LToken);
      Continue;
    end;

    // 8. Unknown character — emit error and advance past it
    LChar := Peek();
    if Assigned(FErrors) then
    begin
      FErrors.Add(FFilename, FLine, FColumn, esError,
        ERR_LEXER_UNEXPECTED_CHAR, RSLexerUnexpectedChar, [LChar]);
      if FErrors.ReachedMaxErrors() then
      begin
        Advance();
        Break;
      end;
    end;
    Advance();
  end;

  // Always terminate the token stream with an EOF token
  LToken      := MakeToken(FConfig.GetEOFKind(), FLine, FColumn, FByteOffset);
  LToken.Text := '';
  FTokens.Add(LToken);

  Status('Tokenized %s: %d tokens', [FFilename, FTokens.Count - 1]);

  Result := not Assigned(FErrors) or not FErrors.HasErrors();
end;

function TParseLexer.GetTokenCount(): Integer;
begin
  Result := FTokens.Count;
end;

function TParseLexer.GetToken(const AIndex: Integer): TParseToken;
begin
  if (AIndex >= 0) and (AIndex < FTokens.Count) then
    Result := FTokens[AIndex]
  else
  begin
    Result      := Default(TParseToken);
    Result.Kind := FConfig.GetEOFKind();
  end;
end;

function TParseLexer.GetTokens(): TArray<TParseToken>;
begin
  Result := FTokens.ToArray();
end;

function TParseLexer.GetFilename(): string;
begin
  Result := FFilename;
end;

function TParseLexer.GetSource(): string;
begin
  Result := FSource;
end;

function TParseLexer.Dump(const AId: Integer): string;
var
  LBuilder:  TStringBuilder;
  LToken:    TParseToken;
  LI:        Integer;
  LLocation: string;
  LExtra:    string;
begin
  LBuilder := TStringBuilder.Create();
  try
    LBuilder.AppendLine(
      Format('Lexer Dump: %s (%d tokens)', [FFilename, FTokens.Count]));
    LBuilder.AppendLine(StringOfChar('-', 80));

    for LI := 0 to FTokens.Count - 1 do
    begin
      LToken    := FTokens[LI];
      LLocation := Format('%d:%d-%d:%d',
        [LToken.Line, LToken.Column, LToken.EndLine, LToken.EndColumn]);

      LExtra := '';
      if not LToken.Value.IsEmpty then
        LExtra := Format(' value=%s', [LToken.Value.ToString()]);

      LBuilder.AppendLine(Format('[%3.3d] %-28s "%s"%s  %s%s', [
        LI + 1,
        LToken.Kind,
        LToken.Text,
        StringOfChar(' ', Max(0, 20 - Length(LToken.Text))),
        LLocation,
        LExtra
      ]));
    end;

    LBuilder.AppendLine(StringOfChar('-', 80));

    if Assigned(FErrors) and (FErrors.Count() > 0) then
    begin
      LBuilder.AppendLine(Format('Errors: %d', [FErrors.Count()]));
      for LI := 0 to FErrors.GetItems().Count - 1 do
        LBuilder.AppendLine('  ' + FErrors.GetItems()[LI].ToFullString());
      LBuilder.AppendLine(StringOfChar('-', 80));
    end;

    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

end.
