program Z80ASM;

   {
      PC Z-80 Assembler (Turbo Pascal 6.0)
      by Mike Wiering, 1993,94
   }

   {$I-}

   uses
      Dos, CRT;

   const
      erNoError         =    0;
      erUnknownMnemonic =    1;
      erSyntax          =    2;
      erTooMany         =    3;
      erOutOfRange      =    4;
      erDupLabel        =    5;
      erInvNumber       =    6;
      erUndefinedLabel  =    7;
      erIllegalValue    =    8;
      erTooManyErrors   =    9;

   const
      tpOneByte         =    0;   {}
      tpTwoBytes        =    1;   {}

      tpByte            =   10;   {}
      tpWord            =   11;   {}
      tpFlags           =   12;   {}
      tpAHLOneByteReg   =   13;   {}
      tpOpAOneByteReg   =   14;   {}
      tpOneByteReg      =   15;   {}

      tpFlagsWord       =   20;   {}
      tpBitReg          =   21;   {}
      tpCombReg         =   22;   {}
      tpHLIXIY          =   23;   {}
      tpFlagsRel        =   24;   {}
      tpRel             =   25;   {}

      tpLD              =   50;   {}
      tpIm012           =   51;   {}
      tpIn              =   52;   {}
      tpOut             =   53;   {}
      tpIncDec          =   54;   {}
      tpEX              =   55;   {}
      tpRST             =   56;   {}

      tpORG             =   60;

      tpDefByte         =   70;
      tpDefWord         =   71;
      tpDefSpace        =   72;



   { Flags:  $00 = NZ
             $08 = Z
             $10 = NC
             $18 = C
             $20 = PO
             $28 = PE
             $30 = P
             $38 = M }


   { Registers:  $00 = B
                 $01 = C
                 $02 = D
                 $03 = E
                 $04 = H
                 $05 = L
                 $06 = (HL)
             $DD $06 = (IX+&oo)
             $FD $06 = (IY+&oo)
                 $07 = A }


   { CombReg: $00 = BC
              $10 = DE
              $20 = HL
          $DD $20 = IX
          $FD $20 = IY
              $30 = AF }


   type
      RefPtr = ^Ref;

      Ref = record
         Tp: Byte;
         Address: Word;
         Disp: Word;
         Size: Byte;  { 1=byte/2=word }
         rpNext: RefPtr;
      end;

      LabelRecPtr = ^LabelRec;

      LabelRec = record
         Address: Word;
         AddressKnown: Boolean;
         Line: LongInt;
         RefList: RefPtr;
         lrpNext: LabelRecPtr;
         Name: String;
      end;

      BufferPtr = ^Buffer;
      Buffer = array [0..$FFFE] of Char;


      EQURecPtr = ^EQURec;

      EQURec = record
         EQULabel: ^String;
         EQUValue: ^String;
         Next: EQURecPtr;
      end;


   const
      CodePos: Word = $0000;
      OrgPos: Word = $0100;
      ErrorCount: Word = 0;
      LineCount: LongInt = 0;
      ErrorPar: String = '';


   var
      Labels: array [0..$FF] of LabelRecPtr;  { fast! }
      EQU: array [0..$FF] of EQURecPtr;
      ProgramCode: BufferPtr;
      LastLine: String;
      SourceFile,
      DestFile: String;
      TotalLines: LongInt;
      MnemoType: Byte;
      LastRef: RefPtr;


   function Count (var S: String): Byte;
   { get checksum of a string }
      var
         i, j: Byte;
   begin
      j := Length (S);
      for i := 1 to Length (S) do
         j := j + Ord (S [i]);
      Count := j;
   end;

   procedure StoreEQU (Name, Value: String);
      var
         E: EQURecPtr;
         N: Byte;
   begin
      N := Count (Name);
      GetMem (E, SizeOf (EQURec));
      with E^ do
      begin
         Next := EQU [N];
         GetMem (EQULabel, Length (Name) + 1);
         Move (Name, EQULabel^, Length (Name) + 1);
         GetMem (EQUValue, Length (Value) + 1);
         Move (Value, EQUValue^, Length (Value) + 1);
      end;
      EQU [N] := E;
   end;

   function GetEQU (Name: String): String;
      var
         E: EQURecPtr;
   begin
      E := EQU [Count (Name)];
      while E <> NIL do
      begin
         if E^.EQULabel^ = Name then
         begin
            GetEQU := E^.EQUValue^;
            Exit;
         end;
         E := E^.Next;
      end;
      GetEQU := Name;
   end;

   procedure EQUDone;
      var
         E: EQURecPtr;
         N: Byte;
   begin
      for N := 0 to $FF do
      begin
         E := EQU [N];
         while E <> Nil do
         begin
            with E^ do
            begin
               EQU [N] := Next;
               FreeMem (EQULabel, Length (EQULabel^) + 1);
               FreeMem (EQUValue, Length (EQUValue^) + 1);
            end;
            FreeMem (E, SizeOf (EQURec));
            E := EQU [N];
         end;
      end;
   end;


   function Hex (Ch: Char): String;
      const
         HexChars: String [16] = '0123456789ABCDEF';
   begin
      Hex := HexChars [Ord (Ch) div 16 + 1] + HexChars [Ord (Ch) mod 16 + 1];
   end;


   procedure Show;
   begin
      asm
         push   ds
         push   es
         lds    si, ProgramCode
         mov    cx, 2000
         mov    ax, 0B800h
         mov    es, ax
         xor    di, di
      @1:
         lodsb
         mov    ah, 1Fh
         stosw
         loop   @1
         pop    es
         pop    ds
      end;
   end;


   function ErrorText (Number: Integer): String;
      var
         ErrorTxt: String;
   begin
      case Number of
         erUnknownMnemonic:
            ErrorTxt := 'Unknown mnemonic';
         erSyntax:
            ErrorTxt := 'Syntax error';
         erTooMany:
            ErrorTxt := 'Too many operands';
         erOutOfRange:
            begin
               ErrorTxt := 'Relative address out of range (' + ErrorPar + ' bytes)';
               ErrorPar := '';
            end;
         erDupLabel:
            ErrorTxt := 'Duplicate label';
         erInvNumber:
            ErrorTxt := 'Invalid number';
         erUndefinedLabel:
            ErrorTxt := 'Undefined label';
         erIllegalValue:
            ErrorTxt := 'Illegal value';
         erTooManyErrors:
            ErrorTxt := 'Too many errors';
         else
            ErrorTxt := '';
      end;
      if ErrorPar <> '' then
         ErrorTxt := ErrorTxt + ' (' + ErrorPar + ')';
      ErrorText := ErrorTxt;
      ErrorPar := '';
   end;


   procedure ShowText (S: String);
   var
      i: Integer;
      C: Char;
   begin
      if S [Length (S)] <> #13 then
         S := S + #13#10;
      for i := 1 to Length (S) do
      begin
         C := S [i];
         asm
            push bp
            mov ah, 2
            mov dl, C
            int 21h
            pop bp
         end;
      end;
      Write ('');  { for Ctrl-Break check }
   end;


   procedure ShowLine;
      var
         S: String;
   begin
      Str (LineCount, S);
      ShowText (SourceFile + '(' + S + ')' + #13);
   end;


   procedure Error (ErrorNumber: Integer);
      var
         S: String;
         F: Text;
         i: Integer;
   begin
      Str (LineCount, S);
      ShowText (SourceFile + '(' + S + ')' + ' ' + ErrorText (ErrorNumber));
      if TotalLines <> 0 then
      begin
         Assign (F, SourceFile);
         Reset (F);
         for i := 1 to LineCount do
            ReadLn (F, LastLine);
         Close (F);
      end;
      ShowText (LastLine);
      Inc (ErrorCount);
   end;


   procedure AppendProg (Code: String);
      var
         i: Byte;
   begin
      for i := 1 to Length (Code) do
      begin
{         Write (Hex (Code [i]), ' '); }
         ProgramCode^[CodePos] := Code [i];
         Inc (CodePos);
         Inc (OrgPos);
      end;
   end;

   procedure Here;
   begin
      if LastRef <> NIL
      then
         LastRef^.Address := OrgPos;
   end;

   procedure AppendWordLH (W: Word);
   begin
      Here;
      AppendProg (Chr (Lo (W)) + Chr (Hi (W)));
   end;

   procedure WriteProg (Address: Word; Code: String);
      var
         i, j: Word;
   begin
      for i := 1 to Length (Code) do
      begin
{         Write (Hex (Code [i]), ' '); }
         j := Address + i - 1;
         ProgramCode^[j] := Code [i];
      end;
   end;

   procedure WriteWordLH (Address, W: Word; MType, Size: Byte);
      var
         Rel: Integer;
   begin
      Address := Address - OrgPos + CodePos;
   {   if Ord (ProgramCode^[Pred (Address)]) mod 8 = 0 }
      if MType in [tpRel, tpFlagsRel]
      then
      begin
         Rel := (W - (Address + OrgPos - CodePos + 1));
         if (Rel > 127) or (Rel < -128)
         then
         begin
            if Rel > 127
            then
               Str (Word (Rel - 127), ErrorPar)
            else
               Str (Word (-128 - Rel), ErrorPar);
            Error (erOutOfRange);
         end;
         WriteProg (Address, Chr (Lo (Rel)));
      end
      else
        if Size = 1 then
        begin
           WriteProg (Address, Chr (Lo (W)));
        end
        else
        begin
          { W := W + OrgPos - CodePos; }
           WriteProg (Address, Chr (Lo (W)) + Chr (Hi (W)));
        end;
   end;


   function NewLabel (Name: String; Addr: Word): LabelRecPtr;
      var
         lrp: LabelRecPtr;
   begin
      GetMem (lrp, SizeOf (LabelRec) - SizeOf (String) + Length (Name) + 1);
      Move (Name, lrp^.Name, Length (Name) + 1);
      lrp^.Address := Addr;
      lrp^.Line := LineCount;
      lrp^.RefList := NIL;
      lrp^.lrpNext := NIL;
      lrp^.AddressKnown := TRUE;
      NewLabel := lrp;
   end;



   procedure StoreLabel (Name: String; Addr: Word; Known: Boolean;
                           RefList: RefPtr);
      var
         lrp, lrpLast: LabelRecPtr;
         N: Byte;
   begin
      N := Count (Name);
      lrp := Labels [N];
      lrpLast := lrp;
      while lrp <> NIL do
      begin
         if (lrp^.Name = Name) then
         begin
            if lrp^.AddressKnown then
            begin
               ErrorPar := Name;
               Error (erDupLabel);
            end
            else
            begin
               lrp^.Address := Addr;
               lrp^.AddressKnown := TRUE;
            end;
            Exit;
         end;
         lrpLast := lrp;
         lrp := lrp^.lrpNext;
      end;
      if Labels [N] = NIL then
      begin
         Labels [N] := NewLabel (Name, Addr);
         Labels [N]^.AddressKnown := Known;
         Labels [N]^.RefList := RefList;
         Exit;
      end
      else
         lrpLast^.lrpNext := NewLabel (Name, Addr);
      if not Known
      then
      begin
         lrpLast^.lrpNext^.AddressKnown := FALSE;
         lrpLast^.lrpNext^.RefList := RefList;
      end;
   end;


   function GetAddress (Name: String; Pos, Disp, Size: Word): Word;
      var
         lrp: LabelRecPtr;
         rp, rpSave: RefPtr;
         N: Byte;
   begin
      N := Count (Name);
      lrp := Labels [N];
      while lrp <> NIL do
      begin
         if lrp^.Name = Name
         then
         begin
            GetAddress := lrp^.Address + Disp;
            if not lrp^.AddressKnown
            then
            begin
               rp := lrp^.RefList;
               while rp <> NIL do
               begin
                  rpSave := rp;
                  rp := rp^.rpNext;
               end;
               GetMem (rp, SizeOf (Ref));
               LastRef := rp;
               rp^.Tp := MnemoType;
               rp^.Address := Pos;
               rp^.Disp := Disp;
               rp^.Size := Size;
               rp^.rpNext := NIL;
               if lrp^.RefList = NIL
               then
                  lrp^.RefList := rp
               else
                  rpSave^.rpNext := rp;
               GetAddress := OrgPos;
            end;
            Exit;
         end;
         lrp := lrp^.lrpNext;
      end;

      GetMem (rp, SizeOf (Ref));
      LastRef := rp;
      rp^.Tp := MnemoType;
      rp^.Address := Pos;
      rp^.Disp := Disp;
      rp^.Size := Size;
      rp^.rpNext := NIL;
      StoreLabel (Name, 0, FALSE, rp);
      GetAddress := OrgPos;
   end;


   procedure WriteJumps;
      var
         lrp, lrpSave: LabelRecPtr;
         rp, rpSave: RefPtr;
         N: Byte;
   begin
      for N := 0 to $FF do
      begin
         lrp := Labels [N];
         while lrp <> NIL do
         begin
            LineCount := lrp^.Line;
            if not lrp^.AddressKnown then
            begin
               ErrorPar := lrp^.Name;
               Error (erUndefinedLabel);
            end;
            rp := lrp^.RefList;
            while rp <> NIL do
            begin
               rpSave := rp;
               if lrp^.AddressKnown then
                  WriteWordLH (rp^.Address, lrp^.Address + rp^.Disp,
                    rp^.Tp, rp^.Size);
               rp := rp^.rpNext;
               FreeMem (rpSave, SizeOf (Ref));
            end;
            lrpSave := lrp;
            lrp := lrp^.lrpNext;
            FreeMem (lrpSave, SizeOf (LabelRec) - SizeOf (String) +
            Length (lrpSave^.Name) + 1);
         end;
         Labels [N] := Nil;
      end;
   end;



   function UpCaseStr (Str: String): String;
      var
         i: Byte;
   begin
      for i := 1 to Length (Str) do
         Str [i] := UpCase (Str [i]);
      UpCaseStr := Str;
   end;


   procedure DelFirstSpaces (var S: String);
   begin
      while (S [0] > #0) and (S [1] in [' ', #9])  do
         Delete (S, 1, 1);
   end;


{   function GetFirst (var Str: String): String;
      const
         WordChars = ['$', '#', '&', '%', '0'..'9',
                         '@'..'Z', '_', 'a'..'z'];
      var
         Result: String;
         Skip: Byte;
         L: Byte absolute Str;

      procedure DelFirstSpaces (var S: String);
      begin
         while (Skip < Length (S)) and (S [Skip + 1] in [' ', #9]) do
            Inc (Skip);
      end;

   begin
      Skip := 0;
      GetFirst := '';
      Result := '';
      DelFirstSpaces (Str);
      if Skip >= L then
         Exit;
      if Str [Skip + 1] in WordChars then
      begin
         while (Skip < L) and (Str [Skip + 1] in WordChars) do
         begin
            Result := Result + UpCase (Str [Skip + 1]);
            Inc (Skip);
         end;
      end
      else
      begin
         case Str [Skip + 1] of
            ';': Skip := L;
            '"': begin
                    repeat
                       Result := Result + Str [Skip + 1];
                       Inc (Skip);
                    until (Skip >= L) or (Str [Skip + 1] = '"');
                    if Skip < L then
                    begin
                       Result := Result + '"';
                       Inc (Skip);
                    end;
                 end;
            #39: begin
                    repeat
                       Result := Result + Str [Skip + 1];
                       Inc (Skip);
                    until (Skip >= L) or (Str [Skip + 1] = #39);
                    if Skip < L then
                    begin
                       Result := Result + #39;
                       Inc (Skip);
                    end;
                 end;
            else
               begin
                  Result := Str [Skip + 1];
                  Inc (Skip);
               end;
         end;
      end;
      GetFirst := Result;
      Str := Copy (Str, Skip + 1, 255);
   end; }


   function GetFirst (var Str: String): String;

      function CopyFirst (var Str: String): String;
      begin
        asm
           push    ds
           push    es
           cld
           lds     si, Str
           les     di, @Result
           mov     bx, di
           mov     al, 0
           stosb
           lodsb
           mov     cl, al
           mov     ch, 0

      @1:  lodsb
           jcxz    @2
           dec     cx
           cmp     al, ' '
           jz      @1
           cmp     al, 9
           jz      @1
      @3:  call    @Compare
           jc      @4

           cmp     al, ';'
           jnz     @5
           seges
           mov     byte ptr [bx], 0
           xor     cx, cx
           jmp     @2

      @5:  cmp     al, '"'
           jnz     @6
           stosb
           seges
           inc     byte ptr [bx]
           jcxz    @2
           dec     cl
      @7:  lodsb
           seges
           inc     byte ptr [bx]
           stosb
           jcxz    @2
           dec     cl
           cmp     al, '"'
           jnz     @7
           inc     cl
           jmp     @2

      @6:  cmp     al, 39
           jnz     @8
           stosb
           seges
           inc     byte ptr [bx]
           jcxz    @2
           dec     cl
      @9:  lodsb
           seges
           inc     byte ptr [bx]
           stosb
           jcxz    @2
           dec     cl
           cmp     al, 39
           jnz     @9
           inc     cl
           jmp     @2

      @8:  stosb
           seges
           inc     byte ptr [bx]
           jmp     @2

      @4:  seges
           inc     byte ptr [bx]
           stosb
           jcxz    @2
           dec     cx
           lodsb
           call    @Compare
           jc      @4
           dec     si
           inc     cl

      @2:  les     di, Str
           mov     al, cl
           stosb
           rep     movsb
           pop     es
           pop     ds
           jmp     @Exit

      @Compare:
           cmp     al, ' '
           jz      @N
           cmp     al, 9
           jz      @N
           cmp     al, 'z'
           ja      @N
           cmp     al, 'a'
           jae     @UpCase
           cmp     al, '_'
           jz      @Y
           cmp     al, 'Z'
           ja      @N
           cmp     al, '@'
           jae     @Y
           cmp     al, '9'
           ja      @N
           cmp     al, '0'
           jae     @Y
           cmp     al, '$'
           jz      @Y
           cmp     al, '#'
           jz      @Y
           cmp     al, '&'
           jz      @Y
           cmp     al, '%'
           jz      @Y
      @N:  clc
           ret
      @Y:  stc
           ret
      @UpCase:
           sub     al, ' '
           stc
           ret

      @Exit:
        end;
      end;

   begin  { GetFirst }
      GetFirst := GetEQU (CopyFirst (Str));
   end;


   function QuickScan (var Mnemonic: String): String;
   begin
     asm
        push    ds
        push    es

        lds     si, Mnemonic
        cld
        lodsb                   { length }
        mov     ah, 0
        mov     bx, ax
        mov     cx, ax
   @1:  lodsb
        add     bx, ax          { count values of the characters }
        loop    @1
        and     bx, 000Fh       { divide all instructions in 16 groupes }
        shl     bx, 1
        call    @2

        dw      offset @Cmds00
        dw      offset @Cmds01
        dw      offset @Cmds02
        dw      offset @Cmds03
        dw      offset @Cmds04
        dw      offset @Cmds05
        dw      offset @Cmds06
        dw      offset @Cmds07
        dw      offset @Cmds08
        dw      offset @Cmds09
        dw      offset @Cmds10
        dw      offset @Cmds11
        dw      offset @Cmds12
        dw      offset @Cmds13
        dw      offset @Cmds14
        dw      offset @Cmds15


   @Cmds00:     db     4, 'CALL',  4,  tpFlagsWord, $C4
                db                     tpWord, $CD
                db     2, 'EI',    2,  tpOneByte, $FB
                db     3, 'NOP',   2,  tpOneByte, $00
                db     4, 'OUTD',  2,  tpTwoBytes, $AB
                db     2, 'RL',    2,  tpOneByteReg, $10
                db     0

   @Cmds01:     db     4, 'INDR',  2,  tpTwoBytes, $BA
                db     0

   @Cmds02:     db     3, 'BIT',   2,  tpBitReg, $40
                db     4, 'CPIR',  2,  tpTwoBytes, $B1
                db     3, 'CPL',   2,  tpOneByte, $2F
                db     2, 'LD',    1,  tpLD

                db     4, 'OTIR',  2,  tpTwoBytes, $B3
                db     3, 'POP',   2,  tpCombReg, $C1
                db     3, 'RLA',   2,  tpOneByte, $17
                db     0

   @Cmds03:     db     3, 'INI',   2,  tpTwoBytes, $A2
                db     2, 'OR',    4,  tpOpAOneByteReg, $B0
                db                     tpByte, $F6
                db     3, 'SLA',   2,  tpOneByteReg, $20
                db     0

   @Cmds04:     db     4, 'PUSH',  2,  tpCombReg, $C5
                db     3, 'RLC',   2,  tpOneByteReg, $00
                db     3, 'SRL',   2,  tpOneByteReg, $38
                db     0

   @Cmds05:     db     2, 'CP',    4,  tpOpAOneByteReg, $B8
                db                     tpByte, $FE
                db     4, 'OUTI',  2,  tpTwoBytes, $A3
                db     3, 'RLD',   2,  tpTwoBytes, $6F
                db     4, 'DEFB',  1,  tpDefByte
                db     0

   @Cmds06:     db     3, 'AND',   4,  tpOpAOneByteReg, $A0
                db                     tpByte, $E6
                db     4, 'INIR',  2,  tpTwoBytes, $B2
                db     4, 'RLCA',  2,  tpOneByte, $07
                db     2, 'RR',    2,  tpOneByteReg, $18
                db     4, 'DEFS',  1,  tpDefSpace
                db     0

   @Cmds07:     db     3, 'LDD',   2,  tpTwoBytes, $A8
                db     0

   @Cmds08:     db     3, 'EXX',   2,  tpOneByte, $D9
                db     2, 'IM',    2,  tpIm012, $46
                db     4, 'RETI',  2,  tpTwoBytes, $4D
                db     3, 'RRA',   2,  tpOneByte, $1F
                db     2, 'DB',    1,  tpDefByte
                db     0

   @Cmds09:     db     3, 'DAA',   2,  tpOneByte, $27
                db     2, 'IN',    2,  tpIn, $40
                db     3, 'SRA',   2,  tpOneByteReg, $28
                db     2, 'DS',    1,  tpDefSpace
                db     0

   @Cmds10:     db     3, 'CPD',   2,  tpTwoBytes, $A9
                db     4, 'DJNZ',  2,  tpRel, $10
                db     4, 'LDDR',  2,  tpTwoBytes, $B8
                db     3, 'RRC',   2,  tpOneByteReg, $08
                db     4, 'DEFW',  1,  tpDefWord
                db     0

   @Cmds11:     db     3, 'ADC',   6,  tpAHLOneByteReg, $88, $ED, $4A
                db                     tpByte, $CE
                db     3, 'OUT',   2,  tpOut, $41
                db     3, 'RRD',   2,  tpTwoBytes, $67
                db     3, 'SBC',   6,  tpAHLOneByteReg, $98, $ED, $42
                db                     tpByte, $DE
                db     3, 'SLI',   2,  tpOneByteReg, $30
                db     3, 'ORG',   1,  tpORG
                db     0

   @Cmds12:     db     3, 'ADD',   6,  tpAHLOneByteReg, $80, $00, $09
                db                     tpByte, $C6
                db     2, 'JP',    6,  tpHLIXIY, $E9
                db                     tpFlagsWord, $C2
                db                     tpWord, $C3
                db     3, 'LDI',   2,  tpTwoBytes, $A0
                db     4, 'RRCA',  2,  tpOneByte, $0F
                db     3, 'RST',   1,  tpRST
                db     3, 'XOR',   4,  tpOpAOneByteReg, $A8
                db                     tpByte, $EE
                db     0

   @Cmds13:     db     4, 'CPDR',  2,  tpTwoBytes, $B9
                db     4, 'HALT',  2,  tpOneByte, $76
                db     3, 'INC',   2,  tpIncDec, $00
                db     3, 'NEG',   2,  tpTwoBytes, $44
                db     4, 'OTDR',  2,  tpTwoBytes, $BB
                db     3, 'RES',   2,  tpBitReg, $80
                db     4, 'RETN',  2,  tpTwoBytes, $45
                db     3, 'SUB',   4,  tpOpAOneByteReg, $90
                db                     tpByte, $D6
                db     2, 'DW',    1,  tpDefWord
                db     0

   @Cmds14:     db     3, 'IND',   2,  tpTwoBytes, $AA
                db     2, 'JR',    4,  tpFlagsRel, $20
                db                     tpRel, $18
                db     3, 'RET',   4,  tpFlags, $C0
                db                     tpOneByte, $C9
                db     0

   @Cmds15:     db     3, 'CCF',   2,  tpOneByte, $3F
                db     3, 'CPI',   2,  tpTwoBytes, $A1
                db     3, 'DEC',   2,  tpIncDec, $01
                db     2, 'DI',    2,  tpOneByte, $F3
                db     2, 'EX',    1,  tpEX
                db     4, 'LDIR',  2,  tpTwoBytes, $B0
                db     3, 'SCF',   2,  tpOneByte, $37
                db     3, 'SET',   2,  tpBitReg, $C0
                db     0


   @2:  pop     si              { get address of tabel in SI }
        push    cs
        pop     ds
        mov     si, [bx + si]
        les     di, Mnemonic
        seges
        mov     cl, [di]
        mov     ch, 0
        inc     di

   @3:  lodsb
        mov     bl, al
        mov     bh, 0
        or      al, al
        jz      @5              { string not found }
        cmp     al, cl
        jnz     @4              { next word }
        push    si
        push    di
        push    cx
        repz
        cmpsb
        pop     cx
        pop     di
        pop     si
        jz      @6              { found }
   @4:  add     si, bx          { get offset of next string }
        lodsb
        mov     ah, 0
        add     si, ax
        jmp     @3

   @5:  les     di, @Result     { mnemonic not found }
        stosb                   { just store one 0-byte }
        jmp     @7              { exit }

   @6:  add     si, cx          { string found }
        lodsb                   { get length }
        mov     cl, al
        mov     ch, 0
        les     di, @Result
        stosb
        rep
        movsb                   { copy data to output string }

   @7:  pop     es
        pop     ds
     end;
   end;


      function Reg16 (S: String): Word;
      begin
         Reg16 := $FFFF;
         if S = 'BC' then Reg16 := $00;
         if S = 'DE' then Reg16 := $10;
         if S = 'HL' then Reg16 := $20;
         if S = 'IX' then Reg16 := $DD20;
         if S = 'IY' then Reg16 := $FD20;
         if S = 'AF' then Reg16 := $30;
      end;


   function GetUntil (var S: String; C: Char; var B: Boolean): String;
      var
         T, R: String;
   begin
      R := '';
      T := '';
      repeat
         if T <> '' then R := R + ' ' + T;
         T := GetFirst (S);
         B := T = C;
      until (T = '') or B;
      Delete (R, 1, 1);
      GetUntil := R;
   end;


{ ====== EXPRESSIONS ==================================================== }


   function CopyFirst (Str: String): String;
   begin
     CopyFirst := GetFirst (Str);
   end;


   function ReadExpression (S: String; Size: Byte): LongInt;


      function GetFirst (var Str: String): String;
      begin
        asm
            push    ds
            cld
            lds     si, Str
            les     di, @Result
            mov     bx, di          { [bx] = length }
            mov     al, 0
            stosb
            lodsb
            mov     cl, al
            mov     ch, 0
        @@1:
            jcxz    @@2             { get next char }
            lodsb
            dec     cx
            cmp     al, ' '
            jz      @@1
            cmp     al, 9
            jz      @@1
        @@3:
            call    @@Compare
            jc      @@4
            cmp     al, ';'         { comment }
            jnz     @@5
            mov     byte ptr es:[bx], 0
            xor     cx, cx
            jmp     @@2
        @@5:
            cmp     al, '"'
            jnz     @@6
            stosb
            inc     byte ptr es:[bx]
            jcxz    @@2
            dec     cl
        @@7:
            lodsb
            inc     byte ptr es:[bx]
            stosb
            jcxz    @@2
            dec     cl
            cmp     al, '"'
            jnz     @@7
            inc     cl
            jmp     @@2
        @@6:
            cmp     al, 39
            jnz     @@8
            stosb
            inc     byte ptr es:[bx]
            jcxz    @@2
            dec     cl
        @@9:
            lodsb
            inc     byte ptr es:[bx]
            stosb
            jcxz    @@2
            dec     cl
            cmp     al, 39
            jnz     @@9
            inc     cl
            jmp     @@2
        @@8:
            stosb
            inc     byte ptr es:[bx]
            jmp     @@2
        @@4:
            inc     byte ptr es:[bx]
            stosb
            jcxz    @@2
            dec     cx
            lodsb
            call    @@Compare
            jc      @@4
            dec     si
            inc     cl
        @@2:
            les     di, Str         { done }
            mov     al, cl
            stosb
            rep
            movsb
            pop     ds
            jmp     @@Exit

        @@Compare:
            cmp     al, ' '
            jz      @@N
            cmp     al, 9
            jz      @@N
            cmp     al, 'z'
            ja      @@N
            cmp     al, 'a'
            jae     @@UpCase
            cmp     al, '_'
            jz      @@Y
            cmp     al, 'Z'
            ja      @@N
            cmp     al, '@'
            jae     @@Y
            cmp     al, '9'
            ja      @@N
            cmp     al, '0'
            jae     @@Y
            cmp     al, '$'
            jz      @@Y
            cmp     al, '#'
            jz      @@Y
            cmp     al, '&'
            jz      @@Y
            cmp     al, '%'
            jz      @@Y
        @@N:
            clc
            ret
        @@Y:
            stc
            ret
        @@UpCase:
            sub     al, ' '
            stc
            ret
        @@Exit:
        end;
      end;


          function ReadNumber (var S: String; var L: LongInt): Boolean;
            var
              i, j, G: Integer;
              T: String;
              TLen: Byte absolute T;
              Neg: Boolean;
          begin
            ReadNumber := FALSE;
            L := 0;
            T := CopyFirst (S);
            if (TLen = 0)
              or (not (T[1] in ['#', '&', '$', '0'..'9', '+', '-','"',#39]))
            then
              Exit;
            ReadNumber := TRUE;
            T := GetFirst (S);
            if T[1] in ['"',#39] then
            begin
              if (T[TLen] <> T[1]) or (TLen > 4) or (TLen <= 2) then
                Error (erInvNumber);
              Move (T[2], L, 1 + Byte (TLen = 4));
              Exit;
            end;
            Neg := T = '-';
            if (T = '+') or (T = '-') then
              T := GetFirst (S);
            if (T[1] = '$') or (T[1] = '#') then
              T := GetFirst (S) + 'H';
            if T[1] = '&' then
            begin
              T := T + T[2];
              Delete (T, 1, 2);
            end;

            G := 10;
            i := 1;
            case UpCase (T[TLen]) of
              'H': G := 16;
              'B': G := 2;
              'D': G := 10;
              'O': G := 8;
            else
              i := 0;
            end;
            if i = 1 then
              Dec (TLen);
            for i := 1 to TLen do
            begin
              j := Ord (UpCase (T[i]));
              if j >= Ord ('A') then
                Dec (j, Ord ('A') - Ord ('9') - 1);
              Dec (j, Ord ('0'));
              if j >= G then
              begin
                Error (erInvNumber);
                Exit;
              end;
              L := L * G + j;
            end;
            if Neg then
              L := -L;
          end;

          const
            MAX_FORM_LEN =  32;

            _IMM         =  #1;
            _MEM         =  #2;
            _LABEL       =  #3;

            _HIGH        = #10;
            _LOW         = #11;
            _MOD         = #15;
            _SHL         = #16;
            _SHR         = #17;
            _NOT         = #18;
            _AND         = #19;
            _OR          = #20;
            _XOR         = #21;
            _BYTE        = #22;
            _WORD        = #23;

          var
            F: String[MAX_FORM_LEN];
            FLen: Byte absolute F;
            FData: array[1..MAX_FORM_LEN] of LongInt;
            LabelName: String;


          function ReadOperator (var S: String): Char;
          begin
            ReadOperator := #0;
            if S = 'HIGH'   then ReadOperator := _HIGH;
            if S = 'LOW'    then ReadOperator := _LOW;
            if S = 'MOD'    then ReadOperator := _MOD;
            if S = 'SHL'    then ReadOperator := _SHL;
            if S = 'SHR'    then ReadOperator := _SHR;
            if S = 'NOT'    then ReadOperator := _NOT;
            if S = 'AND'    then ReadOperator := _AND;
            if S = 'OR'     then ReadOperator := _OR;
            if S = 'XOR'    then ReadOperator := _XOR;
            if S = 'BYTE'   then ReadOperator := _BYTE;
            if S = 'WORD'   then ReadOperator := _WORD;
          end;

          procedure ReadFormula (S: String);
            var
              i: Integer;
              T: String;
          begin
            LabelName := '';
            FData[1] := 0;

            FLen := 0;
            while S <> '' do
            begin
              Inc (FLen);
              F[FLen] := #0;
              T := GetFirst (S);
              if FLen > MAX_FORM_LEN then
                Error (erInvNumber);
              if (T[0] = #1) then
              begin
                if (T[1] in ['-','+','*','/','[',']',':','(',')','[',']','#'])
                then
                  F[FLen] := T[1]
                else
                  if not (T[1] in [' '..#126]) then
                    Error (erInvNumber);
              end;
              if F[Flen] = #0 then
              begin
                if ReadNumber (T, FData[FLen]) then
                  F[FLen] := _IMM
                else
                begin
                  F[FLen] := ReadOperator (T);
                  if (F[FLen] = #0) and (LabelName = '') then
                  begin
                    F[FLen] := _LABEL;
                    LabelName := T;
                  end;
                end;
              end;
              if F[FLen] = #0 then
                Error (erInvNumber);
            end;
          end;

          procedure FDelete (Pos, N: Byte);
            var
              i: Integer;
          begin
            if (N <= 0) or (Pos > FLen) then
              Exit;
            Delete (F, Pos, N);
            for i := Pos to FLen do
              FData[i] := FData[i + N];
          end;

          procedure FInsert (Pos: Byte);
            var
              i: Integer;
          begin
            Insert (F[Pos], F, Pos);
            for i := FLen downto Pos + 1 do
              FData[i] := FData[i - 1];
          end;

          procedure FSwap (i1, i2: Byte);
            var
              cTmp: Char;
              lTmp: LongInt;
          begin
            cTmp := F[i1];
            lTmp := FData[i1];
            F[i1] := F[i2];
            FData[i1] := FData[i2];
            F[i2] := cTmp;
            FData[i2] := lTmp;
          end;

          procedure FReplace (P, N: Byte; NewType: Char; NewVal: LongInt);
          begin
            FDelete (P, N - 1);
            F[P] := NewType;
            FData[P] := NewVal;
          end;

          procedure CalcFormula;
            var
              OldF: String;
              i, j, k, l, m, n: Integer;
              X: LongInt;

          begin  { CalcFormula }
            if FLen > 1 then
            repeat
              OldF := F;

              { -imm }
              repeat
                i := Pos ('-' + _IMM, F);
                if (i = 1) or ((i > 1)
                  and (not (F[i - 1] in [_IMM.._MEM]))) then
                  FReplace (i, 2, _IMM, -FData[i + 1])
                else
                  i := 0;
              until i = 0;

              { +imm }
              repeat
                i := Pos ('+' + _IMM, F);
                if (i = 1) or ((i > 1)
                  and (not (F[i - 1] in [_IMM.._MEM]))) then
                  FReplace (i, 2, _IMM, FData[i + 1])
                else
                  i := 0;
              until i = 0;



              { SHL,SHR,*,/,MOD }
              repeat
                i := Pos (_IMM + '*' + _IMM, F);
                if i = 0 then i := 255;
                j := Pos (_IMM + '/' + _IMM, F);
                if j = 0 then j := 255;
                k := Pos (_IMM + _MOD + _IMM, F);
                if k = 0 then k := 255;
                l := Pos (_IMM + _SHL + _IMM, F);
                if l = 0 then l := 255;
                m := Pos (_IMM + _SHR + _IMM, F);
                if m = 0 then m := 255;

                n := i;
                if j < n then n := j;
                if k < n then n := k;
                if l < n then n := l;
                if m < n then n := m;
                if n = 255 then n := 0;

                if i = n then  { * }
                  FReplace (i, 3, _IMM, FData[i] * FData[i + 2]);
                if j = n then  { / }
                begin
                  X := 0;
                  if FData[j + 2] <> 0 then
                    X := FData[j] div FData[j + 2]
                  else
                    Error (erInvNumber);  { division by zero }
                  FReplace (j, 3, _IMM, X);
                end;
                if k = n then  { MOD }
                begin
                  X := 0;
                  if FData[k + 2] <> 0 then
                    X := FData[k] mod FData[k + 2]
                  else
                    Error (erInvNumber);  { division by zero }
                  FReplace (k, 3, _IMM, X);
                end;
                if l = n then  { SHL }
                  FReplace (l, 3, _IMM, FData[l] shl FData[l + 2]);
                if m = n then  { SHR }
                  FReplace (m, 3, _IMM, FData[m] shr FData[m + 2]);
              until n = 0;

              { +,- }
              repeat
                i := Pos (_IMM + '+' + _IMM, F);
                if i = 0 then i := 255;
                j := Pos (_IMM + '-' + _IMM, F);
                if j = 0 then j := 255;

                if (i < 255) and (i < j) then   { + }
                  FReplace (i, 3, _IMM, FData[i] + FData[i + 2]);
                if (j < 255) and (j < i) then   { - }
                  FReplace (j, 3, _IMM, FData[j] - FData[j + 2]);
              until (i = 255) and (j = 255);

              { NOT,AND,OR,XOR }
              repeat
                i := Pos (_NOT + _IMM, F);
                if i = 0 then i := 255;
                j := Pos (_IMM + _AND + _IMM, F);
                if j = 0 then j := 255;
                k := Pos (_IMM + _OR + _IMM, F);
                if k = 0 then k := 255;
                l := Pos (_IMM + _XOR + _IMM, F);
                if l = 0 then l := 255;

                n := i;
                if j < n then n := j;
                if k < n then n := k;
                if l < n then n := l;
                if n = 255 then n := 0;

                if i = n then  { NOT }
                  FReplace (i, 2, _IMM, not FData[i + 1]);
                if j = n then  { AND }
                  FReplace (j, 3, _IMM, FData[j] and FData[j + 2]);
                if k = n then  { OR }
                  FReplace (k, 3, _IMM, FData[k] or FData[k + 2]);
                if l = n then  { XOR }
                  FReplace (l, 3, _IMM, FData[l] xor FData[l + 2]);
              until n = 0;

              { imm[... }
              repeat
                i := Pos (_IMM + '[', F);
                if i > 0 then
                begin
                  FInsert (i);
                  F[i] := '[';
                  F[i + 2] := '+';
                end;
              until i = 0;

              { [imm] }
              repeat
                i := Pos ('[' + _IMM + ']', F);
                if i > 0 then
                  FReplace (i, 3, _MEM, FData[i + 1]);
              until i = 0;

              { byte/word }
              i := Pos (_BYTE + '[', F);
              j := Pos (_WORD + '[', F);
              if i > 0 then
              begin
{                if (Size <> 255) or (j + k <> 0) then
                  Error (erInvNumber); }
                FDelete (i, 1);
                Size := 1;
              end;
              if j > 0 then
              begin
{                if (Size <> 255) or (i + k <> 0) then
                  Error (erInvNumber); }
                FDelete (j, 1);
                Size := 2;
              end;

              i := Pos ('[' + _IMM + ']', F);
              if i > 0 then
                FReplace (i, 3, _IMM, FData[i + 1]);

              i := Pos ('(' + _IMM + ')', F);
              if i > 0 then
                FReplace (i, 3, _IMM, FData[i + 1]);

              i := Pos (_LABEL + '+', F);
              if i = 1 then
                FDelete (1, 2);


            until (FLen <= 1) or (F = OldF);
          end;  { CalcFormula }


      var
        N: LongInt;
        MaxSize: Byte;

   begin  { ReadExpression }
      MaxSize := Size;

      ReadFormula (S);
      CalcFormula;

      if Size > MaxSize then
         Error (erInvNumber);

      if (FLen <> 1) then
        N := $FFFFFFFF
      else
        if LabelName <> '' then
          N := GetAddress (LabelName, OrgPos, FData[1], Size)
        else
          N := FData[1];

      ReadExpression := N;
   end;


{ ======================================================================= }


   function IsNeg (var S: String): Boolean;
   var
      T: String;
   begin
      IsNeg := FALSE;
      T := S;
      if GetFirst (T) = '-' then
      begin
         S := T;
         IsNeg := TRUE;
      end;
   end;



   function GetByte (NStr: String): Word;
   { read byte value }
      var
         S: String;
         N: Word;
         Code,
         i,
         j: Integer;
         Neg: Boolean;
   begin
{      GetByte := ReadExpression (NStr, 1);
      exit;  }


      Neg := IsNeg (NStr);
      S := GetFirst (NStr);
      if GetFirst (NStr) <> '' then
      begin
         N := $FFFF;
         Error (erInvNumber);
      end;
      if Reg16 (S) <> $FFFF then
      begin
         GetByte := $FFFF;
         Exit;
      end;
      if S [1] >= '@'
      then
      begin
         N := GetAddress (S, OrgPos, 0, 1);
         if Neg then
            N := 0 - N;
         GetByte := N;
         Exit;
      end;
      if S [1] = '#'
      then
         S [1] := '$';
      if (Length (S) = 3)
         and (S [1] in ['"', #39])
         and (S [3] = S [1])
      then
         Str (Ord (S [2]), S);
      if Copy (S, 1, 2) = '&H'
      then
      begin
         Delete (S, 1, 1);
         S [1] := '$';
      end;
      if S [Length (S)] = 'H'
      then
      begin
         Delete (S, Length (S), 1);
         S := '$' + S;
      end;
      if Copy (S, 1, 2) = '&B'
      then
      begin
         Delete (S, 1, 2);
         S := S + 'B';
      end;
      if (S [Length (S)] = 'B') and (S [1] in ['0'..'1'])
      then
      begin
         Code := 0;
         N := 0;
         for i := 1 to Length (S) - 1 do
         begin
            j := Ord (S [i]) - Ord ('0');
            if (j <> 0) and (j <> 1)
            then
               Inc (Code);
            N := N shl 1 + j;
         end;
      end
      else
         Val (S, N, Code);
      if (Code <> 0) or (N > $FF) then
      begin
         N := $FFFF;
         Error (erInvNumber);
      end;
      if Neg then
         GetByte := Byte (0 - N)
      else
         GetByte := N;
   end;


   function GetWord (NStr: String): LongInt;
   { read word value }
      var
         S: String;
         N: LongInt;
         Code,
         i,
         j: Integer;

   begin
{      GetWord := ReadExpression (NStr, 2);
      exit;    }


      S := GetFirst (NStr);
      if Reg16 (S) <> $FFFF then
      begin
         GetWord := $FFFFFFFF;
         Exit;
      end;

      if CopyFirst (NStr) <> '' then
      begin
         if not (S[1] >= '@') then
         begin
           NStr := S + ' ' + NStr;
           GetWord := ReadExpression (NStr, 2);
           Exit;
         end
         else
         begin
           i := ReadExpression (NStr, 2);
           GetWord := GetAddress (S, OrgPos, i, 2);
           Exit;
         end;
      end;

      if S [1] >= '@'
      then
      begin
         GetWord := GetAddress (S, OrgPos, 0, 2);
         Exit;
      end;

      if S [1] = '#'
      then
         S [1] := '$';
      if (Length (S) = 3)
         and (S [1] in ['"', #39])
         and (S [3] = S [1])
      then
         Str (Ord (S [2]), S);
      if (Length (S) = 4)
         and (S [1] in ['"', #39])
         and (S [4] = S [1])
      then
         Str (Ord (S [2]) * $100 + Ord (S [3]), S);
      if Copy (S, 1, 2) = '&H' then
      begin
         Delete (S, 1, 1);
         S [1] := '$';
      end;
      if S [Length (S)] = 'H' then
      begin
         Delete (S, Length (S), 1);
         S := '$' + S;
      end;
      if Copy (S, 1, 2) = '&B'
      then
      begin
         Delete (S, 1, 2);
         S := S + 'B';
      end;
      if (S [Length (S)] = 'B') and (S [1] in ['0'..'1'])
      then
      begin
         Code := 0;
         N := 0;
         for i := 1 to Length (S) - 1 do
         begin
            j := Ord (S [i]) - Ord ('0');
            if (j <> 0) and (j <> 1)
            then
               Inc (Code);
            N := N shl 1 + j;
         end;
      end
      else
         Val (S, N, Code);
      if (Code <> 0) or (N > $FFFF) then
      begin
         N := $FFFFFFFF;
         Error (erInvNumber);
      end;
      GetWord := N;
   end;


   function GetRelByte (S: String; Ofs: Word): Word;
      var
         Rel: Integer;
   begin
      Rel := GetWord (GetFirst (S));
      Rel := Rel - Ofs;
      if (Rel < -128) or (Rel > 127) then
      begin
         if Rel > 127
         then
            Str (Word (Rel - 127), ErrorPar)
         else
            Str (Word (-128 - Rel), ErrorPar);
         Error (erOutOfRange);
      end;
      GetRelByte := Rel and $00FF;
   end;


   procedure SwapStrings (var S1, S2: String);
     var
        S3: String;
   begin
     S3 := S1;
     S1 := S2;
     S2 := S3;
   end;


   procedure AssembleLine (Line: String);
   var
      OpCode,
      MnemoCode,
      Tmp,
      TmpStr: String;
      FirstChar, C1, C2: Char;
      W,
      N: Word;
      i: Integer;
      L: LongInt;
      B, bTmp: Boolean;


      procedure NoMore;
      begin
         if GetFirst (Line) <> '' then          { too many operands }
            Error (erTooMany);
      end;


      function Double (S: String): Word;
      begin
         Double := $FFFF;
         if S = 'BC' then Double := $00;
         if S = 'DE' then Double := $10;
         if S = 'HL' then Double := $20;
         if S = 'SP' then Double := $30;
      end;


      function GetFlags (var S: String): Word;
         var
            Tmp: String;
            W: Word;
      begin
         W := $FFFF;
         Tmp := S;
         Tmp := GetFirst (Tmp);
         if Tmp = 'NZ' then W := $00;
         if Tmp = 'Z'  then W := $08;
         if Tmp = 'NC' then W := $10;
         if Tmp = 'C'  then W := $18;
         if Tmp = 'PO' then W := $20;
         if Tmp = 'PE' then W := $28;
         if Tmp = 'P'  then W := $30;
         if Tmp = 'M'  then W := $38;
         GetFlags := W;
         if W <> $FFFF then
            Tmp := GetFirst (S);
      end;


      function IXIY (Comma: Boolean): Boolean;
         var
            S,
            Tmp: String;
      begin
         IXIY := False;
         S := Line;
         Tmp := GetFirst (S);
         if ((Tmp = 'IX') or (Tmp = 'IY'))
         then
         begin
            if Comma
            then
               if GetFirst (S) <> ','
               then
                  Exit;
            AppendProg (Chr ($DD + $20 * Byte (Tmp [2] = 'Y')));
            Line := S;
            IXIY := True;
         end;
      end;


      function GetA: Boolean;
         var
            S: String;
      begin
         S := Line;
         GetA := False;
         if (GetFirst (S) = 'A') and (GetFirst (S) = ',')
         then
         begin
            Line := S;
            GetA := True;
         end;
      end;


      function Get8BitReg (S: String): Word;
         var
            W: Word;
      begin
         W := $FFFF;
         if S = 'B' then W := $00;
         if S = 'C' then W := $01;
         if S = 'D' then W := $02;
         if S = 'E' then W := $03;
         if S = 'H' then W := $04;
         if S = 'L' then W := $05;
         if S = 'F' then W := $06;
         if S = 'A' then W := $07;
         Get8BitReg := W;
      end;


      procedure Regs (Code: Char; Shift: Byte);
         var
            Tmp, Number, Tmp2: String;
            W,
            N,
            Ofs: Word;
      begin
         W := $FFFF;
         Ofs := $FFFF;
         Tmp := GetFirst (Line);
         if (Tmp [0] <> #1) or (not (Tmp [1] in ['(',')','A'..'Z']))
         then
         begin
            if Tmp = ''
            then
               Line := '???'
            else
               Line := Tmp + ' ' + Line;
            Exit;
         end;
         if Tmp <> 'F' then
            W := Get8BitReg (Tmp) shl Shift;
         if Tmp = '(' then
         begin
            Tmp := GetFirst (Line);
            if (Tmp = 'HL') then
               W := $06 shl Shift
            else
            begin
               Tmp2 := GetFirst (Line);
               if Tmp2 = '-' then
               begin
                  Tmp2 := '+';
                  Line := '-' + Line;
               end;
               if (Tmp2 = '+') or (Tmp2 = ')') then
               begin
                  if Tmp2 = ')'
                  then
                     Line := '0)';
                  Number := GetUntil (Line, ')', bTmp);
                  Line := ') ' + Line;
                  if (Tmp = 'IX') or (Tmp = 'IY') then
                  begin
                     N := GetByte (Number);
                     if N <> $FFFF then
                     begin
                        Ofs := N;
                        if Tmp = 'IX' then
                           AppendProg (#$DD)
                        else
                           AppendProg (#$FD);
                        W := $06 shl Shift;
                     end;
                  end;
               end
               else
               begin
                  Line := '???';
                  Exit;
               end;
            end;

            if GetFirst (Line) <> ')' then
               W := $FFFF;
         end;
         if W = $FFFF then
         begin
            Line := '???';
            Exit;
         end
         else
         begin
            if Code <> #0
            then
            begin
               AppendProg (Code);
               if Ofs <> $FFFF then
                  AppendProg (Chr (Ofs));
            end;
            AppendProg (Chr (Ord (FirstChar) + W));
            if Code = #0
            then
               if Ofs <> $FFFF then
                  AppendProg (Chr (Ofs));
         end;
      end;


      procedure CombReg;
         var
            W: Word;
      begin
         W := Reg16 (GetFirst (Line));
         if W = $FFFF then
         begin
            Error (erSyntax);
            Exit;
         end;
         if Hi (W) <> $00 then
            AppendProg (Chr (Hi (W)));
         AppendProg (Chr (Lo (W) + Ord (FirstChar)));
      end;


      procedure WordLH;
      begin
         L := GetWord (GetUntil (Line, ';', bTmp));
         if L = $FFFFFFFF then
            Error (erSyntax)
         else
           AppendWordLH (L);
      end;


   begin { AssembleLine }
      OpCode := GetFirst (Line);
      if (OpCode = '') or (OpCode = '*') then
         Exit;
      MnemoCode := QuickScan (OpCode);
      Tmp := Line;
      if (MnemoCode = '') or (GetFirst (Tmp) = ':') then
      begin
         TmpStr := Line;
         if (GetFirst (TmpStr) = 'EQU') or (GetFirst (TmpStr) = 'EQU') then
            Exit;
         StoreLabel (OpCode, OrgPos, TRUE, NIL);  { assume it was a label }
         OpCode := GetFirst (Line);               { next word is mnemonic }
         if OpCode = ':'
         then
            OpCode := GetFirst (Line);
         if OpCode = ''
         then
            Exit;
         MnemoCode := QuickScan (OpCode);
         if MnemoCode = ''
         then
         begin
            Error (erUnknownMnemonic);
            Exit;
         end;
      end;
      repeat
         MnemoType := Ord (MnemoCode [1]);
         FirstChar := MnemoCode [2];
         Delete (MnemoCode, 1, 2);
         case MnemoType of
            tpOneByte:
               begin
                  AppendProg (FirstChar);
                  NoMore;
                  Exit;
               end;
            tpTwoBytes:
               begin
                  AppendProg (#$ED);
                  AppendProg (FirstChar);
                  NoMore;
                  Exit;
               end;
            tpFlags:
               begin
                  W := GetFlags (Line);
                  if W <> $FFFF then
                  begin
                     AppendProg (Chr (Ord (FirstChar) + W));
                     NoMore;
                     Exit;
                  end;
               end;
            tpLD:
               begin
                  if IXIY (True)
                  then
                  begin
                     Tmp := GetUntil (Line, ';', bTmp);
                     N := 0;
                     TmpStr := '';
                     B := TRUE;
                     if Tmp [1] = '(' then
                     begin
                        N := 9;
                        Delete (Tmp, 1, 2);
                        Tmp := GetUntil (Tmp, ')', B);
                     end;
                     L := GetWord (Tmp);
                     if (L <> $FFFFFFFF) and B
                     then
                     begin
                        AppendProg (Chr ($21 + Lo (N)));
                        AppendWordLH (Word (L));
                        NoMore;
                        Exit;
                     end;
                  end;
                  Tmp := GetFirst (Line);
                  if Tmp = '('
                  then
                  begin
                     if IXIY (False)
                     then
                     begin
                        if Tmp = '-' then
                        begin
                           Line := '-' + Line;
                           Tmp := '+';
                        end;
                        Tmp := GetFirst (Line);
                        if Tmp = ')' then
                        begin
                           Line := '0)' + Line;
                           Tmp := '+';
                        end;
                        W := GetByte (GetUntil (Line, ')', bTmp));
                        if (W <> $FFFF)
                           and (Tmp = '+')
                           and bTmp
                           and (GetFirst (Line) = ',')
                        then
                        begin
                           Tmp := GetUntil (Line, ';', bTmp);
                           NoMore;
                           N := Get8BitReg (Tmp);
                           if N <> $FFFF
                           then
                           begin
                              AppendProg (Chr ($70 + Lo (N)) + Chr (Lo (W)));
                              Exit;
                           end;
                           N := GetByte (Tmp);
                           if N <> $FFFF
                           then
                           begin
                              AppendProg (#$36 + Chr (Lo (W)) + Chr (Lo (N)));
                              Exit;
                           end;
                        end;
                     end;

                     Tmp := GetUntil (Line, ')', B);
                     W := $FFFF;

                     if (Tmp = 'BC')
                        and B
                        and (GetFirst (Line) = ',')
                        and (GetFirst (Line) = 'A')
                     then
                        W := $02;

                     if (Tmp = 'DE')
                        and B
                        and (GetFirst (Line) = ',')
                        and (GetFirst (Line) = 'A')
                     then
                        W := $12;

                     if (Tmp = 'HL')
                        and B
                        and (GetFirst (Line) = ',')
                     then
                     begin
                        TmpStr := GetUntil (Line, ';', bTmp);
                        W := Get8BitReg (TmpStr);
                        if (W = $FFFF)
                        then
                        begin
                           W := GetByte (TmpStr);
                           if W <> $FFFF
                           then
                           begin
                              AppendProg (#$36 + Chr (Lo (W)));
                              NoMore;
                              Exit;
                           end;
                        end
                        else
                           Inc (W, $70);
                     end;

                     L := GetWord (Tmp);
                     if (L <> $FFFFFFFF)
                        and B
                        and (GetFirst (Line) = ',')
                     then
                     begin
                        Tmp := GetFirst (Line);
                        NoMore;
                        if Tmp = 'A'
                        then
                        begin
                           AppendProg (#$32);
                           AppendWordLH (Word (L));
                           Exit;
                        end;
                        Line := Tmp;
                        if IXIY (False)
                        then
                        begin
                           AppendProg (#$22);
                           AppendWordLH (Word (L));
                           Exit;
                        end;
                        W := Double (Tmp);
                        if W <> $FFFF
                        then
                        begin
                           if W = $20
                           then
                              AppendProg (#$22)
                           else
                              AppendProg (#$ED + Chr ($43 + Lo (W)));
                           AppendWordLH (Word (L));
                           Exit;
                        end;
                     end;

                     if (W <> $FFFF) and (W <> $76)
                     then
                     begin
                        AppendProg (Chr (Lo (W)));
                        NoMore;
                        Exit;
                     end;
                  end;
                  W := Get8BitReg (Tmp);
                  if (W <> $FFFF) and (Tmp <> 'F')
                  then
                     if GetFirst (Line) = ','
                     then
                     begin
                        if Tmp = 'A'
                        then
                        begin
                           TmpStr := Line;
                           TmpStr := GetUntil (TmpStr, ';', bTmp);
                           if TmpStr = 'I'
                           then
                           begin
                              AppendProg (#$ED + #$57);
                              Exit;
                           end;
                           if TmpStr = 'R'
                           then
                           begin
                              AppendProg (#$ED + #$5F);
                              Exit;
                           end;
                        end;

                        FirstChar := Chr ($40 + 8 * W);
                        TmpStr := Line;

                        Regs (#0, 0);
                        if GetFirst (Line) = ''
                        then
                           Exit;

                        TmpStr := GetUntil (TmpStr, ';', bTmp);

                        if (Tmp = 'A')
                        then
                           if (TmpStr [1] = '(')
                              and (TmpStr [Length (TmpStr)] = ')')
                           then
                           begin
                              Delete (TmpStr, 1, 2);
                              Delete (TmpStr, Length (TmpStr) - 1, 2);
                              if TmpStr = 'BC'
                              then
                              begin
                                 AppendProg (#$0A);
                                 Exit;
                              end;
                              if TmpStr = 'DE'
                              then
                              begin
                                 AppendProg (#$1A);
                                 Exit;
                              end;
                              AppendProg (#$3A);
                              L := GetWord (TmpStr);
                              if L <> $FFFFFFFF
                              then
                              begin
                                 AppendWordLH (Word (L));
                                 Exit;
                              end;
                           end;

                        N := GetByte (TmpStr);
                        if N <> $FFFF then
                        begin
                           AppendProg (Chr ($06 + 8 * Lo (W)));
                           AppendProg (Chr (Lo (N)));
                           Exit;
                        end;
                     end;
                  W := Double (Tmp);
                  if (W <> $FFFF) and (GetFirst (Line) = ',')
                  then
                  begin
                     if W = $30  { SP }
                     then
                     begin
                        Line := Line + ',';
                        if IXIY (True)
                        then
                        begin
                           AppendProg (#$F9);
                           NoMore;
                           Exit;
                        end
                        else
                        begin
                           Tmp := Line;
                           if (GetFirst (Tmp) = 'HL')
                              and (GetFirst (Tmp) = ',')
                              and (Tmp = '')
                           then
                           begin
                              AppendProg (#$F9);
                              Exit;
                           end;
                        end;
                        Line [0] := Pred (Line [0]);
                     end;
                     Inc (W);
                     Tmp := GetFirst (Line);
                     TmpStr := '';
                     if Tmp = '('
                     then
                     begin
                        TmpStr := ')';
                        Tmp := GetFirst (Line);
                        if W = $21
                        then
                           W := $2A
                        else
                        begin
                           Inc (W, $4A);
                           AppendProg (#$ED);
                        end;
                     end;
                     AppendProg (Chr (Lo (W)));

                     Tmp := Tmp + ' ' + GetUntil (Line, ')', bTmp);
                     if bTmp then Line := ')';

                     L := GetWord (Tmp);
                     if (L <> $FFFFFFFF) and (GetFirst (Line) = TmpStr)
                     then
                     begin
                        AppendWordLH (Word (L));
                        Exit;
                     end;
                  end;
                  if (Tmp = 'I')
                     and (GetFirst (Line) = ',')
                     and (GetFirst (Line) = 'A')
                  then
                  begin
                     AppendProg (#$ED + #$47);
                     NoMore;
                     Exit;
                  end;
                  if (Tmp = 'R')
                     and (GetFirst (Line) = ',')
                     and (GetFirst (Line) = 'A')
                  then
                  begin
                     AppendProg (#$ED + #$4F);
                     NoMore;
                     Exit;
                  end;
               end;
            tpCombReg:
               begin
                  CombReg;
                  NoMore;
                  Exit;
               end;
            tpBitReg:
               begin
                  TmpStr := GetFirst (Line);
                  if (TmpStr [0] <> #1)
                     or (not (TmpStr [1] in ['0'..'7']))
                     or (GetFirst (Line) <> ',')
                     then
                  begin
                     Error (erSyntax);
                     Exit;
                  end;
                  W := Ord (TmpStr [1]) - Ord ('0');
                  FirstChar := Chr (Ord (FirstChar) + 8 * W);
                  Regs (#$CB, 0);
                  NoMore;
                  Exit;
               end;
            tpHLIXIY:
               begin
                  TmpStr := Line;
                  if GetFirst (TmpStr) = '(' then
                  begin
                     W := $FFFF;
                     Tmp := GetFirst (TmpStr);
                     if GetFirst (TmpStr) = ')' then
                     begin
                        if Tmp = 'HL' then W := $00;
                        if Tmp = 'IX' then W := $DD;
                        if Tmp = 'IY' then W := $FD;
                        if W = $FFFF then
                           Error (erSyntax)
                        else
                        begin
                           if W <> 0 then
                              AppendProg (Chr (W));
                           AppendProg (FirstChar);
                        end;
                        Line := TmpStr;
                        NoMore;
                        Exit;
                     end;
                  end;
               end;
            tpFlagsWord:
               begin
                  W := GetFlags (Line);
                  if W <> $FFFF then
                  begin
                     AppendProg (Chr (Ord (FirstChar) + W));
                     if GetFirst (Line) <> ',' then
                     begin
                        Error (erSyntax);
                        Exit;
                     end;
                     WordLH;
                     NoMore;
                     Exit;
                  end;
               end;
            tpWord:
               begin
                  AppendProg (FirstChar);
                  WordLH;
                  NoMore;
                  Exit;
               end;
            tpFlagsRel:
               begin
                  W := GetFlags (Line);
                  if W <> $FFFF then
                     if Lo (W) in [$00, $08, $10, $18] then
                     begin
                        AppendProg (Chr (Ord (FirstChar) + Lo (W)));
                        if GetFirst (Line) <> ',' then
                        begin
                           Error (erSyntax);
                           Exit;
                        end;
                        W := GetRelByte (Line, OrgPos + 1);
                        if W <> $FFFF then
                        begin
                           AppendProg (Chr (Lo (W)));
                           Exit;
                        end;
                     end;
               end;
            tpRel:
               begin
                  AppendProg (FirstChar);
                  W := GetRelByte (Line, OrgPos + 1);
                  if W <> $FFFF then
                  begin
                     AppendProg (Chr (Lo (W)));
                     Exit;
                  end;
               end;
            tpIn:
               begin
                  W := Get8BitReg (GetFirst (Line));
                  if W <> $FFFF then
                  begin
                     if (GetFirst (Line) = ',') and (GetFirst (Line) = '(')
                     then
                     begin
                        Tmp := GetUntil (Line, ')', bTmp);
                        if (Tmp = 'C') and bTmp then
                        begin
                           AppendProg (#$ED + Chr (Ord (FirstChar) + 8 * Lo (W)));
                           NoMore;
                           Exit;
                        end
                        else
                           if W = 7 then
                           begin
                              if bTmp
                              then
                              begin
                                 W := GetByte (Tmp);
                                 if W <> $FFFF then
                                 begin
                                    AppendProg (#$DB + Chr (Lo (W)));
                                    Exit;
                                 end;
                              end;
                           end;
                     end;
                  end;
               end;
            tpOut:
               if GetFirst (Line) = '(' then
               begin
                  Tmp := GetUntil (Line, ')', bTmp);
                  if (Tmp = 'C') then
                  begin
                     if bTmp and (GetFirst (Line) = ',') then
                     begin
                        W := $FFFF;
                        if UpCase (Line [1]) <> 'F' then
                           W := Get8BitReg (GetFirst (Line));
                        if W <> $FFFF then
                           AppendProg (#$ED + Chr (Ord (FirstChar) + 8 * Lo (W)));
                        NoMore;
                        Exit;
                     end;
                  end
                  else
                  begin
                     if bTmp
                     then
                     begin
                        W := GetByte (Tmp);
                        if (W <> $FFFF)
                           and (GetFirst (Line) = ',')
                           and (GetFirst (Line) = 'A') then
                        begin
                           AppendProg (#$D3 + Chr (Lo (W)));
                           NoMore;
                           Exit;
                        end;
                     end;
                  end;

               end;
            tpRST:
               begin
                  W := GetByte (GetUntil (Line, ';', bTmp));
                  if (W <= $38) and (W mod 8 = 0) then
                  begin
                     AppendProg (Chr ($C7 + W));
                     NoMore;
                     Exit;
                  end;
               end;
            tpOneByteReg:
               begin
                  Regs (#$CB, 0);
                  NoMore;
                  Exit;
               end;
            tpOpAOneByteReg:
               begin
                  B := GetA;
                  Regs (#0, 0);
                  Tmp := GetFirst (Line);
                  if Tmp = ''
                  then
                     Exit
                  else
                     Line := Tmp + ' ' + Line;
               end;
            tpAHLOneByteReg:
               begin
                  C1 := MnemoCode [1];
                  C2 := MnemoCode [2];
                  Delete (MnemoCode, 1, 2);
                  if (FirstChar = #$80) and IXIY (True)  { ADD }
                  then
                  begin
                     W := Double (GetFirst (Line));
                     if W <> $FFFF
                     then
                     begin
                        AppendProg (Chr ($09 + W));
                        NoMore;
                        Exit;
                     end;
                  end;
                  if GetA
                  then
                  begin
                     Regs (#0, 0);
                     Tmp := GetFirst (Line);
                     if Tmp = ''
                     then
                        Exit
                     else
                        Line := Tmp + ' ' + Line;
                  end
                  else
                     if (GetFirst (Line) = 'HL') and (GetFirst (Line) = ',')
                     then
                     begin
                        W := Double (GetFirst (Line));
                        if W <> $FFFF then
                        begin
                           if C1 <> #0
                           then
                              AppendProg (C1);
                           AppendProg (Chr (Ord (C2) + W));
                           Exit;
                        end;
                     end;
               end;
            tpByte:
               begin
                  AppendProg (FirstChar);
                  W := GetByte (GetUntil (Line, ';', bTmp));
                  if W <> $FFFF
                  then
                  begin
                     AppendProg (Chr (W));
                     NoMore;
                     Exit;
                  end;
               end;
            tpIm012:
               begin
                  W := GetByte (GetUntil (Line, ';', bTmp));
                  case Lo (W) of
                     0: begin
                           AppendProg (#$ED + #$46);
                           Exit;
                        end;
                     1: begin
                           AppendProg (#$ED + #$56);
                           Exit;
                        end;
                     2: begin
                           AppendProg (#$ED + #$5E);
                           Exit;
                        end;
                  end;
               end;
            tpEX:
               begin
                  Tmp := GetFirst (Line);
                  if (Tmp = '(')
                  then
                  begin
                    if (GetFirst (Line) = 'SP')
                       and (GetFirst (Line) = ')')
                       and (GetFirst (Line) = ',')
                    then
                    begin
                       Tmp := GetFirst (Line);
                       W := $FFFF;
                       if Tmp = 'HL' then W := $E3;
                       if Tmp = 'IX' then W := $DD shl 8 + $E3;
                       if Tmp = 'IY' then W := $FD shl 8 + $E3;
                       if W <> $FFFF then
                       begin
                          if Hi (W) <> 0
                          then
                             AppendProg (Chr (Hi (W)));
                          AppendProg (Chr (Lo (W)));
                          NoMore;
                          Exit;
                       end;
                    end;
                  end
                  else if (Tmp = 'AF')
                  then
                  begin
                     Tmp := GetFirst (Line);
                     if (Tmp = ',')
                        and (GetFirst (Line) = 'AF')
                     then
                     begin
                        Tmp := GetFirst (Line);
                        if (Tmp = '') or (Tmp = #39)
                        then
                        begin
                           AppendProg (#$08);
                           NoMore;
                           Exit;
                        end;
                     end;
                  end
                  else if (Tmp = 'DE')
                  then
                     if (GetFirst (Line) = ',')
                        and (GetFirst (Line) = 'HL')
                     then
                     begin
                        AppendProg (#$EB);
                        NoMore;
                        Exit;
                     end;
               end;
            tpIncDec:
               begin
                  Tmp := GetFirst (Line);
                  W := Double (Tmp);
                  if W <> $FFFF
                  then
                  begin
                     AppendProg (Chr (3 + 8 * Ord (FirstChar) + W));
                     NoMore;
                     Exit;
                  end
                  else if (Tmp = 'IX')
                  then
                  begin
                     AppendProg (#$DD + Chr ($23 + 8 * Ord (FirstChar)));
                     NoMore;
                     Exit;
                  end
                  else if (Tmp = 'IY')
                  then
                  begin
                     AppendProg (#$FD + Chr ($23 + 8 * Ord (FirstChar)));
                     NoMore;
                     Exit;
                  end
                  else
                  begin
                     FirstChar := Chr ($04 + Ord (FirstChar));
                     Line := Tmp + ' ' + Line;
                     Regs (#0, 3);
                     NoMore;
                     Exit;
                  end;
               end;
            tpORG:
               begin
                  Tmp := GetFirst (Line);
                  L := GetWord (Tmp);
                  if L <> $FFFFFFFF
                  then
                  begin
                     OrgPos := L;
                     Exit;
                  end;
               end;
            tpDefByte:
               begin
                  repeat
                     Tmp := GetFirst (Line);
                     if (Tmp [0] >= #2)
                        and (Tmp [1] in [#34, #39])
                        and (Tmp [1] = Tmp [Length (Tmp)])
                     then
                        AppendProg (Copy (Tmp, 2, Length (Tmp) - 2))
                     else
                     begin
                        W := GetByte (Tmp);
                        if W = $FFFF then
                           Error (erInvNumber)
                        else
                        begin
                           Tmp := Line;
                           if GetFirst (Tmp) = 'DUP' then
                           begin
                              N := W;
                              Line := Tmp;
                              Tmp := GetFirst (Line);
                              if (Tmp [0] >= #2)
                                 and (Tmp [1] in [#34, #39])
                                 and (Tmp [1] = Tmp [Length (Tmp)])
                              then
                              begin
                                 for i := 1 to N do
                                    AppendProg (Copy (Tmp, 2, Length (Tmp) - 2))
                              end
                              else
                              begin
                                 W := GetByte (Tmp);
                                 if W = $FFFF then
                                    Error (erInvNumber);
                                 for i := 1 to N do
                                    AppendProg (Chr (Lo (W)));
                              end
                           end
                           else
                              AppendProg (Chr (Lo (W)));
                        end;
                     end;
                     Tmp := GetFirst (Line);
                     if (Tmp <> '') and (Tmp <> ',')
                     then
                        Error (erSyntax);
                  until (Line = '');
                  Exit;
               end;
            tpDefWord:
               begin
                  repeat
                     Tmp := GetFirst (Line);
                     if (Tmp [0] >= #2)
                        and (Tmp [1] in [#34, #39])
                        and (Tmp [1] = Tmp [Length (Tmp)])
                     then
                        AppendProg (Copy (Tmp, 2, Length (Tmp) - 2))
                     else
                     begin
                        L := GetWord (Tmp);
                        if L = $FFFFFFFF then
                           Error (erInvNumber)
                        else
                        begin
                           Tmp := Line;
                           if GetFirst (Tmp) = 'DUP' then
                           begin
                              N := L;
                              Line := Tmp;
                              Tmp := GetFirst (Line);
                              if (Tmp [0] >= #2)
                                 and (Tmp [1] in [#34, #39])
                                 and (Tmp [1] = Tmp [Length (Tmp)])
                              then
                              begin
                                 for i := 1 to N do
                                    AppendProg (Copy (Tmp, 2, Length (Tmp) - 2))
                              end
                              else
                              begin
                                 L := GetWord (Tmp);
                                 if W = $FFFFFFFF then
                                    Error (erInvNumber);
                                 for i := 1 to N do
                                    AppendWordLH (Word (L));
                              end
                           end
                           else
                              AppendWordLH (Word (L));
                        end;
                     end;
                     Tmp := GetFirst (Line);
                     if (Tmp <> '') and (Tmp <> ',')
                     then
                        Error (erSyntax);
                  until (Line = '');
                  Exit;
               end;
            tpDefSpace:
              begin
                Tmp := GetFirst (Line);
                L := GetWord (Tmp);
                if L <> $FFFFFFFF
                then begin
                   for W := 1 to L do
                      AppendProg (#0);
                end
                else
                   Error (erInvNumber);
                NoMore;
                Exit;
              end;

         end;

      until MnemoCode = '';
      Error (erSyntax);
   end; { AssembleLine }


  procedure FindEQU (S: String);
      var
         S1, S2: String;
   begin
      S1 := GetFirst (S);
      S2 := GetFirst (S);
      if S2 = ':'
      then
         S2 := GetFirst (S);
      if S2 <> 'EQU'
      then
         Exit;
      S2 := GetFirst (S);
      if S <> '' then
      begin
         Error (erIllegalValue);
         Exit;
      end;
      StoreEQU (S1, S2);
   end;


   var
      S, T: String;
      F: Text;
      i: Integer;
      C: Char;

begin
   ShowText ('Z80 assembler version 1.3, by Mike Wiering');
   for i := 0 to $FF do
      Labels [i] := NIL;
   TotalLines := 0;
   for i := 0 to $FF do
      EQU [i] := NIL;
   if MemAvail < SizeOf (ProgramCode^) then
   begin
      ShowText ('Not enough memory');
      Halt;
   end;
   GetMem (ProgramCode, SizeOf (ProgramCode^));
   if ParamCount = 0 then
   begin
      ShowText ('');
      ShowText ('Syntax: Z80ASM source[.SRC] [destination]');
      Halt;
   end;
   SourceFile := ParamStr (1);
   if Pos ('.', SourceFile) = 0 then
      SourceFile := SourceFile + '.SRC';
   SourceFile := UpCaseStr (SourceFile);

   if ParamCount > 1 then
      DestFile := UpCaseStr (ParamStr (2))
   else
   begin
   DestFile := SourceFile;
      i := Pos ('.', DestFile);
      DestFile [0] := Chr (i + 3);
      DestFile [i + 1] := 'C';
      DestFile [i + 2] := 'O';
      DestFile [i + 3] := 'M';
   end;

   Assign (F, SourceFile);
   Reset (F);
   if IOResult <> 0 then
   begin
      ShowText ('File not found (' + SourceFile + ')');
      Halt;
   end;
   repeat
      ReadLn (F, S);
      FindEQU (S);
   until Eof (F);
   Reset (F);
   ShowLine;
   repeat
      LastRef := Nil;
      ReadLn (F, S);
      Inc (LineCount);
      LastLine := S;
      AssembleLine (S);
      if LineCount mod 100 = 0 then
         ShowLine;
   until Eof (F) or (ErrorCount >= 10);
   Close (F);
   ShowLine;
   if ErrorCount >= 10 then
      Error (erTooManyErrors);

   TotalLines := LineCount;
   WriteJumps;
   ShowText ('');

   if ErrorCount = 0 then
   begin
      Assign (F, DestFile);
      ReWrite (F);
      if IOResult <> 0 then
      begin
         ShowText ('Cannot write file (' + DestFile + ')');
         Halt;
      end;
      for i := 0 to CodePos - 1 do
         Write (F, ProgramCode^[i]);
      Close (F);
      Str (TotalLines, S);
      Str (CodePos, T);
      ShowText (S + ' lines, compiled program: ' + DestFile + ', size: ' + T +
         ' bytes.');
   end
   else
   begin
      Str (ErrorCount, S);
      ShowText (S + ' error(s)');
   end;

   FreeMem (ProgramCode, SizeOf (ProgramCode^));
end.

