unit ReliefBitmap;
//tato unita pracuje s bitmapovymi daty reliefu

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, IniFiles,
  StrUtils, ReliefText, VektorBasedObject, ReliefBitmapSymbols, Global, Forms,
  OblastRizeni, PGraphics, symbolHelper;

const
 _MAX_WIDTH   = 256;
 _MAX_HEIGHT  = 256;

type
 TORAskEvent = function(Pos:TPoint):Boolean of object;

 EFileLoad = class(Exception);

 TPanelBitmap=class
  private const

  private
   FPanelWidth,FPanelHeight:Integer;
   FMode:TMode;
   FSoubor:string;
   Operations:record
    Disable:Boolean;
    OpType:Byte;
   end;
   FStav:ShortInt;
   Graphics:TPanelGraphics;

   FORAskEvent: TORAskEvent;
   FOnShow : TNEvent;
   FOnTextEdit : TChangeTextEvent;

    procedure SetGroup(State:boolean);
    function GetGroup:boolean;

    function IsOperation:Boolean;

    procedure CheckOperations;

    procedure ShowEvent;
    function IsSymbolSymbolTextEvent(Pos:TPoint):boolean;
    function IsSymbolSeparVertEvent(Pos:TPoint):boolean;
    function IsSymbolSeparHorEvent(Pos:TPoint):boolean;
    function IsSymbolKPopiskyJCClickSoupravyEvent(Pos:TPoint):boolean;
    procedure NullOperationsEvent;
    procedure MoveActivateEvent;
    procedure DeleteActivateEvent;
    function IsOperationEvent:boolean;
    procedure ChangeTextEvent(Sender:TObject; var Text:string;var Color:Integer);

    function ImportObj(Data:TObject):Byte;

  public

   Symbols        :  TBitmapSymbols;
   SeparatorsVert : TVBO;
   SeparatorsHor  : TVBO;
   KPopisky       : TVBO;
   JCClick        : TVBO;
   Popisky        : TPopisky;
   Soupravy       : TVBO;

   Bitmap:array [0.._MAX_WIDTH-1, 0.._MAX_HEIGHT-1] of ShortInt;

    constructor Create(SymbolIL,TextIL:TImageList;DrawCanvas:TCanvas;Width,Height:Integer;Mode:TMode;Parent:TForm; Graphics:TPanelGraphics);
    destructor Destroy; override;

    procedure FLoad(aFile:string;var ORs:string);
    procedure FSave(aFile:string;const ORs:string);

    procedure Paint;
    function PaintCursor(CursorPos:TPoint):TCursorDraw;
    procedure PaintMove(CursorPos:TPoint);

    function SetRozmery(aWidth,aHeight:Byte):Byte;

    procedure Escape(Group:Boolean);
    procedure ResetPanel;

    procedure Move;
    procedure Delete;

    function MouseUp(Position:TPoint;Button:TMouseButton):Byte;
    function DblClick(Position:TPoint):Byte;

    function Import(Data:TObject):Byte;     // import dat zatim z TPanelObjects

    property Soubor:string read FSoubor;
    property Stav:ShortInt read FStav;
    property PanelWidth:Integer read FPanelWidth;
    property PanelHeight:Integer read FPanelHeight;
    property Group:Boolean read GetGroup write SetGroup;
    property Mode:TMode read FMode write FMode;
    property FileStav:ShortInt read FStav;

    property OnShow: TNEvent read FOnShow write FOnShow;
    property OnTextEdit: TChangeTextEvent read FOnTextEdit write FOnTextEdit;
    property OnORAsk: TORAskEvent read FORAskEvent write FORAskEvent;
 end;//class

//FileSystemStav:
 //0 - soubor zavren
 //1 - soubor neulozen
 //2 - soubor ulozen

implementation

uses ReliefObjects;

//nacitani souboru s bitmapovymi daty
procedure TPanelBitmap.FLoad(aFile:string;var ORs:string);
var myFile:File;
    Buffer:array [0..16383] of Byte;
    bytesBuf:TBytes;
    i,len:Integer;
    aCount:Integer;
    VBOData:TVBOData;
    BitmapData:TBSData;
    version:Byte;
begin
 Self.FStav   := 2;
 Self.FSoubor := aFile;

 Self.Symbols.Reset;
 Self.SeparatorsVert.Reset;
 Self.SeparatorsHor.Reset;
 Self.Popisky.Reset;

 AssignFile(myFile, aFile);
 Reset(myFile, 1);

 try
   BlockRead(myFile,Buffer,7,aCount);
   if (aCount < 7) then
     raise EFileLoad.Create('Nespr�vn� d�lka hlavi�ky!');

   //--- hlavicka zacatek ---
   //kontrola identifikace
   if ((Buffer[0] <> ord('b')) or (Buffer[1] <> ord('r'))) then
     raise EFileLoad.Create('Nespr�vn� identifika v hlavi�ce!');

   //kontrola verze
   version := Buffer[2];
   if ((version <> $21) and (version <> $30) and (version <> $31) and (version <> $32)) then
     Application.MessageBox(PChar('Otev�r�te soubor s verz� '+IntToHex(version, 2)+', kter� nen� aplikac� pln� podporov�na!'),
                            'Varov�n�', MB_OK OR MB_ICONWARNING);

   BitmapData.Width  := Buffer[3];
   BitmapData.Height := Buffer[4];
   Self.FPanelWidth  := Buffer[3];
   Self.FPanelHeight := Buffer[4];

   //kontrola 2x #255
   if ((Buffer[5] <> 255) or (Buffer[6] <> 255)) then
     raise EFileLoad.Create('Chyb� odd�lovac� sekvence mezi hlavi�kou a bitmapov�mi daty!');

   //--- hlavicka konec ---
   //-------------------------------------------
   //nacitani bitmapovych dat
   BlockRead(myFile,BitmapData.Data,BitmapData.Width*BitmapData.Height,aCount);
   if (aCount < BitmapData.Width*BitmapData.Height) then
     raise EFileLoad.Create('M�lo bitmapov�ch dat!');

   Self.Symbols.SetLoadedData(BitmapData);

   //prazdny radek
   BlockRead(myFile,Buffer,2,aCount);
   if (aCount < 2) or (Buffer[0] <> 255) or (Buffer[1] <> 255) then
     raise EFileLoad.Create('Chyb� odd�lovac� sekvence mezi bitmapov�mi daty a popisky!');
   //-------------------------------------------

   if (version >= $32) then
    begin
     //nacteni poctu popisku
     BlockRead(myFile, Buffer, 2, aCount);
     len := (Buffer[0] shl 8) + Buffer[1];

     //nacitani popisku
     SetLength(bytesBuf, len);
     BlockRead(myFile, bytesBuf[0], len, aCount);
     Self.Popisky.SetLoadedDataV32(bytesBuf);
    end else begin
     //nacteni poctu popisku
     BlockRead(myFile, Buffer, 1, aCount);
     len := Buffer[0] * ReliefText._Block_Length;

     //nacitani popisku
     SetLength(bytesBuf, len);
     BlockRead(myFile, bytesBuf[0], len, aCount);
     Self.Popisky.SetLoadedData(bytesBuf);
    end;

   //prazdny radek
   BlockRead(myFile,Buffer,2,aCount);
   if (aCount < 2) or (Buffer[0] <> 255) or (Buffer[1] <> 255) then
     raise EFileLoad.Create('Chyb� odd�lovac� sekvence mezi popisky a separ�tory!');
   //-------------------------------------------

   //nacteni poctu vertikalnich separatoru
   BlockRead(myFile,Buffer,1,aCount);

   //nacitani vertikalnich separatoru
   BlockRead(myFile,Buffer,(Buffer[0]*2),aCount);

   VBOData.Count := aCount;
   for i := 0 to aCount-1 do VBOData.Data[i] := Buffer[i];

   Self.SeparatorsVert.SetLoadedData(VBOData);

   //prazdny radek
   BlockRead(myFile,Buffer,2,aCount);
   if (aCount < 2) or (Buffer[0] <> 255) or (Buffer[1] <> 255) then
     raise EFileLoad.Create('Chyb� odd�lovac� sekvence mezi separ�tory!');
   //-------------------------------------------

   if (version >= $30) then
    begin
     //nacteni poctu horizontalnich separatoru
     BlockRead(myFile,Buffer,1,aCount);

     //nacitani horizontalnich separatoru
     BlockRead(myFile,Buffer,(Buffer[0]*2),aCount);

     VBOData.Count := aCount;
     for i := 0 to aCount-1 do VBOData.Data[i] := Buffer[i];

     Self.SeparatorsHor.SetLoadedData(VBOData);

     //prazdny radek
     BlockRead(myFile,Buffer,2,aCount);
     if (aCount < 2) or (Buffer[0] <> 255) or (Buffer[1] <> 255) then
       raise EFileLoad.Create('Chyb� odd�lovac� sekvence mezi hor. separ�tory a kpopisky!');
    end else begin
     Self.SeparatorsHor.Reset();
    end;

   //-------------------------------------------

   //nacteni poctu KPopisky
   BlockRead(myFile,Buffer,1,aCount);

   //nacitani KPopisky
   BlockRead(myFile,Buffer,(Buffer[0]*2),aCount);

   VBOData.Count := aCount;
   for i := 0 to aCount-1 do VBOData.Data[i] := Buffer[i];

   Self.KPopisky.SetLoadedData(VBOData);

   //prazdny radek
   BlockRead(myFile,Buffer,2,aCount);
   if (aCount < 2) or (Buffer[0] <> 255) or (Buffer[1] <> 255) then
     raise EFileLoad.Create('Chyb� odd�lovac� sekvence mezi kolejov�mi popisky a JCClick!');
   //-------------------------------------------

   //nacteni poctu JCClick
   BlockRead(myFile,Buffer,1,aCount);

   //nacitani JCClick
   BlockRead(myFile,Buffer,(Buffer[0]*2),aCount);

   VBOData.Count := aCount;
   for i := 0 to aCount-1 do VBOData.Data[i] := Buffer[i];

   Self.JCClick.SetLoadedData(VBOData);

   //prazdny radek
   BlockRead(myFile,Buffer,2,aCount);
   if (aCount < 2) or (Buffer[0] <> 255) or (Buffer[1] <> 255) then
     raise EFileLoad.Create('Chyb� odd�lovac� sekvence mezi JCClick a pozicemi pro souupravy!');
   //-------------------------------------------

   if (version >= $31) then
    begin
     //nacteni poctu symbolu souprav
     BlockRead(myFile, Buffer, 1, aCount);

     //nacitani symbolu souprav
     BlockRead(myFile, Buffer, (Buffer[0]*2),aCount);

     VBOData.Count := aCount;
     for i := 0 to aCount-1 do VBOData.Data[i] := Buffer[i];

     Self.Soupravy.SetLoadedData(VBOData);

     //prazdny radek
     BlockRead(myFile, Buffer, 2, aCount);
     if (aCount < 2) or (Buffer[0] <> 255) or (Buffer[1] <> 255) then
       raise EFileLoad.Create('Chyb� odd�lovac� sekvence mezi pozicemi pro soupravy a oblastmi ��zen�!');
    end;
   //-------------------------------------------

   //nacitani oblasti rizeni

   ORs := '';

   //precteme delku
   BlockRead(myFile,Buffer,2,aCount);

   //pokud je delka 0, je neco spatne
   if (aCount = 0) then
     raise EFileLoad.Create('Pr�zdn� oblasti ��zen�!');

   len := (Buffer[0] shl 8)+Buffer[1];

   SetLength(bytesBuf, len);
   BlockRead(myFile, bytesBuf[0], len, aCount);
   ORs := TEncoding.UTF8.GetString(bytesBuf, 0, aCount);
 finally
   CloseFile(myFile);
 end;
end;//function

procedure TPanelBitmap.FSave(aFile:string;const ORs:string);
var myFile:File;
    Buffer:array [0..1023] of Byte;
    bytesBuf:TBytes;
    VBOData:TVBOData;
    BitmapData:TBSData;
    len:Cardinal;
begin
 Self.FStav   := 2;
 Self.FSoubor := aFile;

 AssignFile(myFile,aFile);
 Rewrite(myFile,1);

 try
   //--- hlavicka zacatek ---
   //identifikace
   Buffer[0] := ord('b');
   Buffer[1] := ord('r');
   //verze
   Buffer[2] := $32;
   //vyska a sirka
   BitmapData := Self.Symbols.GetSaveData;

   Buffer[3] := BitmapData.Width;
   Buffer[4] := BitmapData.Height;
   //ukonceni hlavicky
   Buffer[5] := 255;
   Buffer[6] := 255;

   //zapsani hlavicky
   BlockWrite(myFile,Buffer,7);
   //--- hlavicka konec ---

   //-------------------------------------------
   //ukladani bitmapovych dat
   BitmapData := Self.Symbols.GetSaveData;
   BlockWrite(myFile,BitmapData.Data,BitmapData.Width*BitmapData.Height);

   //ukonceni bloku
   Buffer[0] := 255;
   Buffer[1] := 255;
   BlockWrite(myFile,Buffer,2);

   //-------------------------------------------
   //popisky
   bytesBuf := Self.Popisky.GetSaveData;
   BlockWrite(myFile, bytesBuf[0], Length(bytesBuf));

   //ukonceni bloku
   Buffer[0] := 255;
   Buffer[1] := 255;
   BlockWrite(myFile,Buffer,2);
   //-------------------------------------------
   //vertikalni oddelovace
   VBOData := Self.SeparatorsVert.GetSaveData;
   BlockWrite(myFile,VBOData.Data,VBOData.Count);

   //ukonceni bloku
   Buffer[0] := 255;
   Buffer[1] := 255;
   BlockWrite(myFile,Buffer,2);

   //-------------------------------------------
   //horizontalni oddelovace
   VBOData := Self.SeparatorsHor.GetSaveData;
   BlockWrite(myFile,VBOData.Data,VBOData.Count);

   //ukonceni bloku
   Buffer[0] := 255;
   Buffer[1] := 255;
   BlockWrite(myFile,Buffer,2);

   //-------------------------------------------
   //KPopisky
   VBOData := Self.KPopisky.GetSaveData;
   BlockWrite(myFile,VBOData.Data,VBOData.Count);

   //ukonceni bloku
   Buffer[0] := 255;
   Buffer[1] := 255;
   BlockWrite(myFile,Buffer,2);

   //-------------------------------------------
   //JCClick
   VBOData := Self.JCClick.GetSaveData;
   BlockWrite(myFile,VBOData.Data,VBOData.Count);

   //ukonceni bloku
   Buffer[0] := 255;
   Buffer[1] := 255;
   BlockWrite(myFile,Buffer,2);

   //-------------------------------------------
   //soupravy
   VBOData := Self.Soupravy.GetSaveData;
   BlockWrite(myFile,VBOData.Data,VBOData.Count);

   //ukonceni bloku
   Buffer[0] := 255;
   Buffer[1] := 255;
   BlockWrite(myFile,Buffer,2);

   //-------------------------------------------

   len := TEncoding.UTF8.GetByteCount(ORs);
   SetLength(bytesBuf, len);

   // delka zpravy
   Buffer[0] := hi(len);
   Buffer[1] := lo(len);
   BlockWrite(myFile, Buffer, 2);

   bytesBuf := TEncoding.UTF8.GetBytes(ORs);
   BlockWrite(myFile, bytesBuf[0], len);

   //ukonceni bloku
   Buffer[0] := 255;
   Buffer[1] := 255;
   BlockWrite(myFile,Buffer,2);
   //-------------------------------------------
 finally
   CloseFile(myFile);
 end;
end;//function

function TPanelBitmap.SetRozmery(aWidth,aHeight:Byte):Byte;
begin
 if (Self.IsOperation) then
  begin
   Result := 1;
   Exit;
  end;

 Self.FPanelWidth  := aWidth;
 Self.FPanelHeight := aHeight;

 Self.Symbols.SetRozmery(aWidth,aHeight);

 Result := 0;
end;//function

constructor TPanelBitmap.Create(SymbolIL,TextIL:TImageList;DrawCanvas:TCanvas;Width,Height:Integer;Mode:TMode;Parent:TForm; Graphics:TPanelGraphics);
begin
 inherited Create;

 Self.Mode := Mode;
 Self.Graphics := Graphics;

 Self.Symbols    := TBitmapSymbols.Create(SymbolIL,DrawCanvas,Width,Height);
 Self.Symbols.FOnShow         := Self.ShowEvent;
 Self.Symbols.FIsSymbol       := Self.IsSymbolSymbolTextEvent;
 Self.Symbols.FNullOperations := Self.NullOperationsEvent;
 Self.Symbols.FMoveActivate   := Self.MoveActivateEvent;
 Self.Symbols.FDeleteActivate := Self.DeleteActivateEvent;
 Self.Symbols.FOPAsk          := Self.IsOperationEvent;

 Self.SeparatorsVert := TVBO.Create(DrawCanvas,SymbolIL, _Separ_Vert_Index, stVert);
 Self.SeparatorsVert.FOnShow         := Self.ShowEvent;
 Self.SeparatorsVert.FIsSymbol       := Self.IsSymbolSeparVertEvent;
 Self.SeparatorsVert.FNullOperations := Self.NullOperationsEvent;
 Self.SeparatorsVert.FMoveActivate   := Self.MoveActivateEvent;
 Self.SeparatorsVert.FDeleteActivate := Self.DeleteActivateEvent;
 Self.SeparatorsVert.FOPAsk          := Self.IsOperationEvent;

 Self.SeparatorsHor := TVBO.Create(DrawCanvas,SymbolIL, _Separ_Hor_Index, stHor);
 Self.SeparatorsHor.FOnShow         := Self.ShowEvent;
 Self.SeparatorsHor.FIsSymbol       := Self.IsSymbolSeparHorEvent;
 Self.SeparatorsHor.FNullOperations := Self.NullOperationsEvent;
 Self.SeparatorsHor.FMoveActivate   := Self.MoveActivateEvent;
 Self.SeparatorsHor.FDeleteActivate := Self.DeleteActivateEvent;
 Self.SeparatorsHor.FOPAsk          := Self.IsOperationEvent;

 Self.KPopisky   := TVBO.Create(DrawCanvas,SymbolIL, _KPopisek_Index);
 Self.KPopisky.FOnShow         := Self.ShowEvent;
 Self.KPopisky.FIsSymbol       := Self.IsSymbolKPopiskyJCClickSoupravyEvent;
 Self.KPopisky.FNullOperations := Self.NullOperationsEvent;
 Self.KPopisky.FMoveActivate   := Self.MoveActivateEvent;
 Self.KPopisky.FDeleteActivate := Self.DeleteActivateEvent;
 Self.KPopisky.FOPAsk          := Self.IsOperationEvent;

 Self.JCClick    := TVBO.Create(DrawCanvas,SymbolIL, _JCPopisek_Index);
 Self.JCClick.FOnShow         := Self.ShowEvent;
 Self.JCClick.FIsSymbol       := Self.IsSymbolKPopiskyJCClickSoupravyEvent;
 Self.JCClick.FNullOperations := Self.NullOperationsEvent;
 Self.JCClick.FMoveActivate   := Self.MoveActivateEvent;
 Self.JCClick.FDeleteActivate := Self.DeleteActivateEvent;
 Self.JCClick.FOPAsk          := Self.IsOperationEvent;

 Self.Soupravy    := TVBO.Create(DrawCanvas,SymbolIL, _Soupravy_Index);
 Self.Soupravy.FOnShow         := Self.ShowEvent;
 Self.Soupravy.FIsSymbol       := Self.IsSymbolKPopiskyJCClickSoupravyEvent;
 Self.Soupravy.FNullOperations := Self.NullOperationsEvent;
 Self.Soupravy.FMoveActivate   := Self.MoveActivateEvent;
 Self.Soupravy.FDeleteActivate := Self.DeleteActivateEvent;
 Self.Soupravy.FOPAsk          := Self.IsOperationEvent;

 Self.Popisky    := TPopisky.Create(DrawCanvas, TextIL, Parent, Graphics);
 Self.Popisky.FOnShow         := Self.ShowEvent;
 Self.Popisky.FIsSymbol       := Self.IsSymbolSymbolTextEvent;
 Self.Popisky.FNullOperations := Self.NullOperationsEvent;
 Self.Popisky.FMoveActivate   := Self.MoveActivateEvent;
 Self.Popisky.FDeleteActivate := Self.DeleteActivateEvent;
 Self.Popisky.FOPAsk          := Self.IsOperationEvent;
 Self.Popisky.FOnChangeText   := Self.ChangeTextEvent;

 Self.SetRozmery(Width,Height);
end;//contructor

destructor TPanelBitmap.Destroy;
begin
 FreeAndNil(Self.Symbols);
 FreeAndNil(Self.SeparatorsVert);
 FreeAndNIl(Self.SeparatorsHor);
 FreeAndNil(Self.KPopisky);
 FreeAndNil(Self.JCClick);
 FreeAndNil(Self.Soupravy);
 FreeAndNil(Self.Popisky);

 inherited;
end;//contructor

//vykresleni vseho
procedure TPanelBitmap.Paint;
begin
 Self.JCClick.Paint;
 Self.Soupravy.Paint;
 Self.KPopisky.Paint;
 Self.Symbols.Paint;
 Self.SeparatorsVert.Paint;
 Self.SeparatorsHor.Paint;
 Self.Popisky.Paint;
end;//procedure

function TPanelBitmap.MouseUp(Position:TPoint;Button:TMouseButton):Byte;
var return:array [0..4] of Byte;
    i:Integer;
    AllStav:Boolean;
begin
 Result := 0;

 Self.Operations.Disable := true;

 case (Self.Mode) of
  dmBitmap:begin
            //reseni ignorace chyby 2 tak, aby se vypisovala pouze, pokud je u vsech typu objektu
            Return[0] := Self.KPopisky.MouseUp(Position,Button);
            Return[1] := Self.JCClick.MouseUp(Position,Button);
            Return[2] := Self.Soupravy.MouseUp(Position,Button);
            Return[3] := Self.Symbols.MouseUp(Position,Button);
            Return[4] := Self.Popisky.MouseUp(Position,Button);

            Result := 0;

            //pokud neni zadna chyba
            AllStav := true;
            for i := 0 to 4 do if (Return[i] <> 0) then AllStav := false;
            if (not AllStav) then
             begin
              for i := 0 to 4 do
                if ((Return[i] = 1) or (Return[i] > 2)) then
                  Result := Return[i];

              if (Result = 0) then
               begin
                AllStav := true;
                for i := 0 to 4 do if (Return[i] <> 2) then AllStav := false;
                if (AllStav) then Result := 2;
               end;//if Result = 0
             end;//if not AllStav
           end;//dmBitmap

   dmSepHor:Result := Self.SeparatorsHor.MouseUp(Position,Button);
   dmSepVert:Result := Self.SeparatorsVert.MouseUp(Position,Button);
  end;//case

 Self.Operations.Disable := false;
 Self.CheckOperations;
end;//procedure

function TPanelBitmap.DblClick(Position:TPoint):Byte;
begin
 Result := 0;
end;//function

procedure TPanelBitmap.ShowEvent;
begin
 if (Assigned(FOnShow)) then FOnShow;
end;//procedure

function TPanelBitmap.IsSymbolSymbolTextEvent(Pos:TPoint):boolean;
begin
 Result := false;

 if (Self.Symbols.GetSymbol(Pos)  <> -1) then Exit(true);
 if (Self.Popisky.GetPopisek(Pos) <> -1) then Exit(true);
 if (Assigned(Self.FORAskEvent)) then Exit(Self.FORAskEvent(Pos));
end;//function

function TPanelBitmap.IsSymbolSeparVertEvent(Pos:TPoint):boolean;
begin
 Result := (Self.SeparatorsVert.GetObject(Pos) <> -1);
end;//function

function TPanelBitmap.IsSymbolSeparHorEvent(Pos:TPoint):boolean;
begin
 Result := (Self.SeparatorsHor.GetObject(Pos) <> -1);
end;//function

function TPanelBitmap.IsSymbolKPopiskyJCClickSoupravyEvent(Pos:TPoint):boolean;
begin
 Result := false;

 if (Self.KPopisky.GetObject(Pos) <> -1) then Result := true
 else if (Self.JCClick.GetObject(Pos)  <> -1) then Result := true
 else if (Self.Soupravy.GetObject(Pos)  <> -1) then Result := true;
end;//function

procedure TPanelBitmap.NullOperationsEvent;
begin
 Self.Escape(false);
end;//procedure

procedure TPanelBitmap.MoveActivateEvent;
begin
 if (Self.Operations.Disable) then Self.Operations.OpType := 1 else Self.Move;
end;//procedure

procedure TPanelBitmap.DeleteActivateEvent;
begin
 if (Self.Operations.Disable) then Self.Operations.OpType := 2 else Self.Delete;
end;//procedure

function TPanelBitmap.IsOperationEvent:boolean;
begin
 Result := Self.IsOperation;
end;//procedure

procedure TPanelBitmap.SetGroup(State:boolean);
begin
 if (Assigned(Self.Symbols)) then Self.Symbols.Group := State;
end;//procedure

function TPanelBitmap.GetGroup:boolean;
begin
 Result := false;

 if (Assigned(Self.Symbols)) then Result := Self.Symbols.Group;
end;//fucntion

procedure TPanelBitmap.Escape(Group:Boolean);
begin
 if (Assigned(Self.Symbols)) then Self.Symbols.Escape(Group);
 if (Assigned(Self.SeparatorsVert)) then Self.SeparatorsVert.Escape;
 if (Assigned(Self.SeparatorsHor)) then Self.SeparatorsHor.Escape;
 if (Assigned(Self.KPopisky)) then Self.KPopisky.Escape;
 if (Assigned(Self.JCClick)) then Self.JCClick.Escape;
 if (Assigned(Self.Soupravy)) then Self.Soupravy.Escape;
 if (Assigned(Self.Popisky)) then Self.Popisky.Escape;
end;//procedure

procedure TPanelBitmap.ResetPanel;
begin
 if (Assigned(Self.Symbols)) then Self.Symbols.Reset;
 if (Assigned(Self.SeparatorsVert)) then Self.SeparatorsVert.Reset;
 if (Assigned(Self.SeparatorsHor)) then Self.SeparatorsHor.Reset;
 if (Assigned(Self.KPopisky)) then Self.KPopisky.Reset;
 if (Assigned(Self.JCClick)) then Self.JCClick.Reset;
 if (Assigned(Self.Soupravy)) then Self.Soupravy.Reset;
 if (Assigned(Self.Popisky)) then Self.Popisky.Reset;
end;//procedure

function TPanelBitmap.PaintCursor(CursorPos:TPoint):TCursorDraw;
var Return:array [0..6] of TCursorDraw;
    i:Integer;
    AllSame:Boolean;
    Same:TCursorDraw;
begin
 Return[0] := Self.Symbols.PaintCursor(CursorPos);
 Return[1] := Self.SeparatorsVert.PaintCursor(CursorPos);
 Return[2] := Self.SeparatorsHor.PaintCursor(CursorPos);
 Return[3] := Self.KPopisky.PaintCursor(CursorPos);
 Return[4] := Self.JCClick.PaintCursor(CursorPos);
 Return[5] := Self.Popisky.PaintCursor(CursorPos);
 Return[6] := Self.Soupravy.PaintCursor(CursorPos);

 if (Self.Mode = dmSepVert) then
  begin
   for i := 0 to 6 do
    begin
     Return[i].Pos1.X := Return[i].Pos1.X + (_Symbol_Sirka div 2);
     Return[i].Pos2.X := Return[i].Pos2.X + (_Symbol_Sirka div 2);
    end;//for i
  end else begin if (Self.Mode = dmSepHor) then
   for i := 0 to 6 do
    begin
     Return[i].Pos1.Y := Return[i].Pos1.Y + (_Symbol_Vyska div 2);
     Return[i].Pos2.Y := Return[i].Pos2.Y + (_Symbol_Vyska div 2);
    end;//for i
  end;

 //zde se zajistuje vytvoreni 1 barvy a pozice kurzoru z celkem 5 pozic a barev - osetreni priorit

 //pokud jsou vsechny stejne
 Same := Return[0];
 AllSame := true;
 for i := 1 to 6 do
  begin
   if ((Return[i].Color <> Same.Color) or (Return[i].Pos1.X <> Same.Pos1.X) or (Return[i].Pos1.Y <> Same.Pos1.Y) or
       (Return[i].Pos2.X <> Same.Pos2.X) or (Return[i].Pos2.Y <> Same.Pos2.Y)) then
    begin
     AllSame := false;
     Break;
    end;//if (Return[i].Color <> Same)
  end;//for i
 if (AllSame) then Exit(Same);

 //pokud je 1 OnObject
 for i := 0 to 6 do
   if (Return[i].Color = 2) then
     Exit(Return[i]);

 //pokud je 1 Operation
 for i := 0 to 6 do
   if (Return[i].Color = 1) then
     Exit(Return[i]);
end;//function

function TPanelBitmap.IsOperation:Boolean;
begin
 if ((Self.Symbols.AddKrok <> 0) or (Self.Symbols.MoveKrok > 1) or (Self.Symbols.DeleteKrok > 1) or
     (Self.SeparatorsVert.AddKrok <> 0) or (Self.SeparatorsVert.MoveKrok > 1) or (Self.SeparatorsVert.DeleteKrok > 1) or
     (Self.SeparatorsHor.AddKrok <> 0) or (Self.SeparatorsHor.MoveKrok > 1) or (Self.SeparatorsHor.DeleteKrok > 1) or
     (Self.KPopisky.AddKrok <> 0) or (Self.KPopisky.MoveKrok > 1) or (Self.KPopisky.DeleteKrok > 1) or
     (Self.JCClick.AddKrok <> 0) or (Self.JCClick.MoveKrok > 1) or (Self.JCClick.DeleteKrok > 1) or
     (Self.Soupravy.AddKrok <> 0) or (Self.Soupravy.MoveKrok > 1) or (Self.Soupravy.DeleteKrok > 1) or
     (Self.Popisky.AddKrok <> 0) or (Self.Popisky.MoveKrok > 1) or (Self.Popisky.DeleteKrok > 1)) then Result := true else Result := false;
end;//function

procedure TPanelBitmap.Move;
begin
 case (Self.Mode) of
  dmBitmap:begin
            if (Assigned(Self.Symbols)) then Self.Symbols.Move;
            if (Assigned(Self.KPopisky)) then Self.KPopisky.Move;
            if (Assigned(Self.JCClick)) then Self.JCClick.Move;
            if (Assigned(Self.Soupravy)) then Self.Soupravy.Move;
            if (Assigned(Self.Popisky)) then Self.Popisky.Move;
           end;

  dmSepHor: if (Assigned(Self.SeparatorsHor)) then Self.SeparatorsHor.Move;
  dmSepVert: if (Assigned(Self.SeparatorsVert)) then Self.SeparatorsVert.Move;
 end;
end;//procedure

procedure TPanelBitmap.Delete;
begin
 case (Self.Mode) of
  dmBitmap:begin
            if (Assigned(Self.Symbols)) then Self.Symbols.Delete;
            if (Assigned(Self.KPopisky)) then Self.KPopisky.Delete;
            if (Assigned(Self.JCClick)) then Self.JCClick.Delete;
            if (Assigned(Self.Soupravy)) then Self.Soupravy.Delete;
            if (Assigned(Self.Popisky)) then Self.Popisky.Delete;
           end;
  dmSepHor: if (Assigned(Self.SeparatorsHor)) then Self.SeparatorsHor.Delete;
  dmSepVert: if (Assigned(Self.SeparatorsVert)) then Self.SeparatorsVert.Delete;
 end;
end;//procedure

procedure TPanelBitmap.PaintMove(CursorPos:TPoint);
begin
 if (Assigned(Self.Symbols)) then Self.Symbols.PaintBitmapMove(CursorPos);
 if (Assigned(Self.SeparatorsVert)) then Self.SeparatorsVert.PaintMove(CursorPos);
 if (Assigned(Self.SeparatorsHor)) then Self.SeparatorsHor.PaintMove(CursorPos);
 if (Assigned(Self.KPopisky)) then Self.KPopisky.PaintMove(CursorPos);
 if (Assigned(Self.JCClick)) then Self.JCClick.PaintMove(CursorPos);
 if (Assigned(Self.Soupravy)) then Self.Soupravy.PaintMove(CursorPos);
 if (Assigned(Self.Popisky)) then Self.Popisky.PaintTextMove(CursorPos);
end;//procedure

procedure TPanelBitmap.CheckOperations;
begin
 if ((not Self.Operations.Disable) and (Self.Operations.OpType <> 0)) then
  begin
   case (Self.Operations.OpType) of
    1:Self.Move;
    2:Self.Delete;
   end;//case
  end;
end;//procedure

procedure TPanelBitmap.ChangeTextEvent(Sender:TObject; var Text:string;var Color:Integer);
begin
 if (Assigned(FOnTextEdit)) then FOnTextEdit(Self, Text, Color);
end;//procedure

///////////////////////////////////////////////////////////////////////////////

// import dat zatim z TPanelObjects
function TPanelBitmap.Import(Data:TObject):Byte;
begin
 Result := 0;

 if (Data.ClassType = TPanelObjects) then
  begin
   Result := Self.ImportObj(Data);
  end;//if (Data.ClassType = TPanelBitmap)
end;//function

// import objektovych dat
function TPanelBitmap.ImportObj(Data:TObject):Byte;
//var obj:TPanelObjects;
begin
// obj := (Data as TPanelObjects);

 // tohleto zatim neni dodelano

 Result := 0;
end;//procedure

///////////////////////////////////////////////////////////////////////////////

end.//unit
