MODULE JsonParser;
IMPORT Logger, CharacterStack, Strings, Out, strutils, Settings;
CONST
    ArrayMaxNumber = 30;
    ArrayMaxNumberChar = 2000;
    (* Const *)
    symbolBracketStart = "{";
    symbolBracketEnd = "}";
    (* TODO: Reverse " and ' *)
    quote = Settings.quote;
    coma = ",";
TYPE
    TString* = ARRAY ArrayMaxNumberChar OF CHAR;
    
    JsonTypePointer* = POINTER TO JsonType;

    JsonType* = RECORD
        GetTerminal* : PROCEDURE(self : JsonTypePointer; string : ARRAY OF CHAR; VAR returnValue : ARRAY OF CHAR): BOOLEAN;
        GetNonTerminal* : PROCEDURE(self : JsonTypePointer; key : ARRAY OF CHAR): JsonTypePointer;
        HasKey* : PROCEDURE(self : JsonTypePointer; key : ARRAY OF CHAR): BOOLEAN;
        TypeOfTheKey* : PROCEDURE(self : JsonTypePointer; key : ARRAY OF CHAR; VAR returnValue : ARRAY OF CHAR);
        GetTerminalKeys* : PROCEDURE(self : JsonTypePointer; VAR destination : ARRAY OF TString);
        GetTerminalValues* : PROCEDURE(self : JsonTypePointer; VAR destination : ARRAY OF TString);
        GetNoneTerminalKeys* : PROCEDURE(self : JsonTypePointer; VAR destination : ARRAY OF TString);
        GetTerminalNumber* : PROCEDURE(self : JsonTypePointer): LONGINT;
        GetNonTerminalNumber* : PROCEDURE(self : JsonTypePointer): LONGINT;

        TerminalKeys : ARRAY ArrayMaxNumber OF TString;
        TerminalValues* : ARRAY ArrayMaxNumber OF TString;
        TerminalNumber* : LONGINT;

        NonTerminalKeys : ARRAY ArrayMaxNumber OF TString;
        NonTerminalValues : POINTER TO ARRAY OF JsonTypePointer;
        NonTerminalNumber* : LONGINT;
    END;
    
VAR
    jsonRecord: JsonTypePointer;
    testValue: ARRAY ArrayMaxNumber OF CHAR;
    keyFound: BOOLEAN;

PROCEDURE GetTerminalNumber*(self : JsonTypePointer): LONGINT;
BEGIN RETURN self.TerminalNumber END GetTerminalNumber;

PROCEDURE GetNonTerminalNumber*(self : JsonTypePointer): LONGINT;
BEGIN RETURN self.NonTerminalNumber END GetNonTerminalNumber;

PROCEDURE GetNonTerminal(self : JsonTypePointer; key : ARRAY OF CHAR): JsonTypePointer;
VAR
    i: LONGINT;
BEGIN
    FOR i := 0 TO self.NonTerminalNumber - 1 DO
        IF Strings.Match(key, self.NonTerminalKeys[i]) THEN RETURN self.NonTerminalValues[i] END;
    END;

    RETURN NIL;
END GetNonTerminal;

PROCEDURE Empty *(VAR string: ARRAY OF CHAR);
VAR
    i : LONGINT;
BEGIN
    FOR i := 0 TO LEN(string) - 1 DO string[i] := 0X END;
    COPY("", string);
END Empty;

PROCEDURE GetTerminal *(self: JsonTypePointer; key: ARRAY OF CHAR; VAR returnValue: ARRAY OF CHAR): BOOLEAN;
VAR
    i: LONGINT;
    noneTerminal: JsonTypePointer;
    strings: strutils.strings;
    parent, children: ARRAY ArrayMaxNumber OF CHAR;
BEGIN

    FOR i := 0 TO self.TerminalNumber DO
        IF Strings.Match(key, self.TerminalKeys[i]) THEN COPY(self.TerminalValues[i], returnValue); RETURN TRUE END;
    END;
    
    strings := strutils.tokenize(key, '.');
    
    IF LEN(strings^) < 1 THEN RETURN FALSE END;
    
    COPY(strings^[0], parent);
    
    IF Strings.Length(parent) < 1 THEN RETURN FALSE END;
    
    noneTerminal := self.GetNonTerminal(self, parent);

    IF noneTerminal = NIL THEN RETURN FALSE END;
    
    FOR i := 1 TO LEN(strings^) - 1 DO
        Strings.Append(strings[i], children);
        IF i < LEN(strings^) - 1 THEN
            Strings.Append(".", children);
        END;
    END;
    
    RETURN noneTerminal.GetTerminal(noneTerminal, children, returnValue);

    RETURN FALSE;
END GetTerminal;

PROCEDURE GetTerminalKeys(self : JsonTypePointer; VAR destination : ARRAY OF TString);
VAR
    i: LONGINT;
BEGIN
    FOR i := 0 TO self.TerminalNumber DO
        COPY(self.TerminalKeys[i], destination[i]);
    END;
END GetTerminalKeys;

PROCEDURE GetTerminalValues(self : JsonTypePointer; VAR destination : ARRAY OF TString);
VAR
    i: LONGINT;
BEGIN
    FOR i := 0 TO self.TerminalNumber - 1 DO
        Empty(destination[i]);
        COPY(self.TerminalValues[i], destination[i]);
    END;
END GetTerminalValues;

PROCEDURE GetNoneTerminalKeys(self : JsonTypePointer; VAR destination : ARRAY OF TString);
VAR
    i: LONGINT;
BEGIN
    FOR i := 0 TO LEN(self.NonTerminalKeys) - 1 DO
        destination[i] := self.NonTerminalKeys[i];
    END;
END GetNoneTerminalKeys;
(* 
    TODO:
        Create a good validation for comas
        Create a good validation for name repetition
*)

PROCEDURE PushDownString(
    string: ARRAY OF CHAR;
    startCharacter: CHAR;
    endCharacter: CHAR;
    i: LONGINT;
    VAR returnString: ARRAY OF CHAR): LONGINT;
VAR
    characterStack: CharacterStack.CharacterStackType;
    j , k: LONGINT;
BEGIN
    NEW(characterStack);
    j := i;
    characterStack := CharacterStack.Create();
    Empty(returnString);
    REPEAT
        IF (characterStack.Count > 1) & (string[j] = endCharacter) THEN 
            REPEAT UNTIL characterStack.pop(characterStack) = startCharacter;
        ELSE
            characterStack.push(characterStack, string[j]);
            INC(j);
        END;
    UNTIL characterStack.Count = 0; (* do not trust top it btings OAX on EOL*)
    
    IF j >= LEN(returnString) THEN
        Logger.Log('ERROR string out of range in JSON parser');
    END;
    ASSERT(j < LEN(returnString));

    FOR k := i TO j DO
        returnString[k - i] := string[k];
    END;

    RETURN j; (* returning next symbol of quote *)
END PushDownString;

PROCEDURE deQuote(text: ARRAY OF CHAR; VAR result: ARRAY OF CHAR);
VAR
    i, j: LONGINT;
BEGIN
    j := 0;
    FOR i := 0 TO Strings.Length(text) DO
        IF text[i] # quote THEN
            result[j] := text[i];
            INC(j);
        END;
    END;
END deQuote;

PROCEDURE Create*(text: ARRAY OF CHAR): JsonTypePointer;
VAR
    self: JsonTypePointer; 
    i, j, terminalIterator, noneTerminalIterator: LONGINT;
    characterStack: CharacterStack.CharacterStackType;
    key, val, nonTerminalVal, string: ARRAY ArrayMaxNumberChar OF CHAR;
    symbol: CHAR;
    symbolStart: CHAR;
    quoteStart: BOOLEAN;
BEGIN
    NEW(self);
    NEW(self.NonTerminalValues, ArrayMaxNumber);
    self.GetTerminal := GetTerminal;
    self.GetNonTerminal := GetNonTerminal;
    self.GetTerminalKeys := GetTerminalKeys;
    self.GetNoneTerminalKeys := GetNoneTerminalKeys;
    NEW(characterStack);
    characterStack := CharacterStack.Create();
    
    i := 0;
    j := 0;
    terminalIterator := 0;
    noneTerminalIterator := 0;
    
    Empty(key);
    Empty(val);
    Empty(nonTerminalVal);
    Empty(string);
    
    quoteStart := FALSE;

    REPEAT
        IF (text[i] = symbolBracketStart) & (i = 0) THEN
            INC(i);
            (* Logger.Log("Starting Parse Json"); *)
        END;

        IF symbol = symbolBracketStart THEN
            (* Logger.Log("End Parsing Json"); *)
        END;
        symbol := text[i];

        (* Logger.LogIntLn(i); *)
        (* IF i > 508 THEN
            Logger.Log(text);        
        END; *)
        (* terminals *)
        IF symbol = quote THEN
            i := PushDownString(text, quote, quote, i, string);
        END;

        IF (Strings.Length(string) > 0) & (symbol = quote) THEN
            IF Strings.Length(key) > 0 THEN
                COPY(string, val);
            ELSE
                COPY(string, key);
            END;
            
            Empty(string);
        END;

        IF (Strings.Length(key) > 0) & (Strings.Length(val) > 0) THEN
            deQuote(key, self.TerminalKeys[terminalIterator]);
            deQuote(val, self.TerminalValues[terminalIterator]);

            INC(terminalIterator);
                        
            Empty(key);
            Empty(val);
        END;
        
        (* none terminals *)        
        IF symbol = symbolBracketStart THEN
            i := PushDownString(text, symbolBracketStart, symbolBracketEnd, i, string);
        END;
        
        IF (Strings.Length(string) > 0) & (symbol = symbolBracketStart) THEN
            IF Strings.Length(key) > 0 THEN
                COPY(string, nonTerminalVal);
            END;
            
            Empty(string);
        END;

        IF (Strings.Length(key) > 0) & (Strings.Length(nonTerminalVal) > 0) THEN
            deQuote(key, self.NonTerminalKeys[noneTerminalIterator]);
            self.NonTerminalValues[noneTerminalIterator] := Create(nonTerminalVal);
            
            INC(noneTerminalIterator);

            Empty(key);
            Empty(nonTerminalVal);
        END;
        
        INC(i);
    UNTIL (i >= LEN(text) - 1) OR (text[i] = 0X);
    
    self.NonTerminalNumber := noneTerminalIterator;
    self.TerminalNumber := terminalIterator;
    
    RETURN self;
END Create;

BEGIN
    (* NEW(jsonRecord);
    jsonRecord := Create("{'foo': 'bar', 'test': 'test1', 'test2': {'sub': 'dub'}}");

    keyFound := jsonRecord.GetTerminal(jsonRecord, "foo", testValue);

    IF keyFound THEN
        Logger.Log('found KEY');
        Logger.Log(testValue);
    ELSE Logger.Log('Value for the Key is not found') END;

    keyFound := jsonRecord.GetTerminal(jsonRecord, "test2.sub", testValue);

    IF keyFound THEN
        Logger.Log('found KEY');
        Logger.Log(testValue);
    ELSE Logger.Log('Value for the Key is not found') END; *)
END JsonParser.