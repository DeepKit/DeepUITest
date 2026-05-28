program _debug4;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DeepSpec.Yaml.Parser;
var
  P: TYamlParser;
  N: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    // Use real file
    N := P.ParseFile('..\spec\DeepSpec\function_tree.yaml');
    if N <> nil then
    begin
      WriteLn('Root kind: ', Ord(N.Kind));
      WriteLn('version: ', N.GetString('version', 'MISS'));
      var Seq := N.GetSeq('nodes');
      if Seq <> nil then
        WriteLn('nodes count: ', Seq.SeqCount)
      else
        WriteLn('nodes: nil');
      N.Free;
    end else
      WriteLn('Parse returned nil');
  finally
    P.Free;
  end;
end.
