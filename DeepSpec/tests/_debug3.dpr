program _debug3;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DeepSpec.Yaml.Parser;
var
  P: TYamlParser;
  N: TYamlNode;
  S: string;
begin
  P := TYamlParser.Create;
  try
    // Simpler case: just a sequence
    S := 'items:' + sLineBreak +
         '  - one' + sLineBreak +
         '  - two';
    N := P.Parse(S);
    WriteLn('Root kind: ', Ord(N.Kind));
    var Seq := N.GetSeq('items');
    if Seq <> nil then
      WriteLn('items count: ', Seq.SeqCount)
    else
      WriteLn('items seq: nil');
    N.Free;

    // Even simpler: no indent
    WriteLn;
    S := 'items:' + sLineBreak +
         '- one' + sLineBreak +
         '- two';
    N := P.Parse(S);
    Seq := N.GetSeq('items');
    if Seq <> nil then
      WriteLn('items (no indent) count: ', Seq.SeqCount)
    else
      WriteLn('items (no indent) seq: nil');
    N.Free;

    // Just bare sequence
    WriteLn;
    S := '- one' + sLineBreak + '- two';
    N := P.Parse(S);
    WriteLn('bare kind: ', Ord(N.Kind));
    N.Free;
  finally
    P.Free;
  end;
end.
