program _debug_parser;
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
    // Test 1: empty input
    N := P.Parse('');
    WriteLn('Empty: kind=', Ord(N.Kind), ' scalar=', N.AsString('XX'), ' isnull=', N.IsNull);
    N.Free;

    // Test 2: scalar
    N := P.Parse('hello world');
    WriteLn('Scalar: kind=', Ord(N.Kind), ' scalar=', N.AsString('XX'));
    N.Free;

    // Test 3: map
    N := P.Parse('name: DeepSpec' + #10 + 'version: "1.0"');
    WriteLn('Map: kind=', Ord(N.Kind), ' name=', N.GetString('name', 'MISS'), ' ver=', N.GetString('version', 'MISS'));
    N.Free;

    // Test 4: sequence
    N := P.Parse('items:' + #10 + '  - one' + #10 + '  - two' + #10 + '  - three');
    WriteLn('Seq: kind=', Ord(N.Kind));
    var S := N.GetSeq('items');
    if S <> nil then WriteLn('  SeqCount=', S.SeqCount);
    N.Free;

    // Test 5: validate missing id
    N := P.Parse(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes:' + #10 +
      '  - title: NoId' + #10 +
      '    kind: feature');
    var Seq := N.GetSeq('nodes');
    if Seq <> nil then
    begin
      WriteLn('Nodes seq count: ', Seq.SeqCount);
      if Seq.SeqCount > 0 then
        WriteLn('  item0 id=[', Seq.SeqItem(0).GetString('id', ''), '] title=[', Seq.SeqItem(0).GetString('title', ''), ']');
    end else
      WriteLn('Nodes seq is nil');
    N.Free;
  finally
    P.Free;
  end;
end.
