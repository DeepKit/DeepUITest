program _debug2;
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
    S := 'version: "1.0"' + sLineBreak +
         'tree: function' + sLineBreak +
         'nodes:' + sLineBreak +
         '  - id: func-login' + sLineBreak +
         '    title: User Login' + sLineBreak +
         '    kind: feature';
    N := P.Parse(S);
    WriteLn('Root kind: ', Ord(N.Kind));
    WriteLn('version: ', N.GetString('version', 'MISS'));
    WriteLn('tree: ', N.GetString('tree', 'MISS'));
    var Seq := N.GetSeq('nodes');
    if Seq <> nil then
    begin
      WriteLn('nodes count: ', Seq.SeqCount);
      if Seq.SeqCount > 0 then
        WriteLn('  item0.id: [', Seq.SeqItem(0).GetString('id', 'MISS'), ']');
    end else
      WriteLn('nodes seq: nil');
    N.Free;
  finally
    P.Free;
  end;
end.
