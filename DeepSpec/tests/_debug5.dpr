program _debug5;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DeepSpec.Yaml.Parser;
var
  P: TYamlParser;
  N, Sub: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    // Test nested map
    N := P.Parse('project:' + #10 + '  name: TestProject' + #10 + '  type: desktop');
    WriteLn('Root kind: ', Ord(N.Kind));
    WriteLn('Has project: ', N.Has('project'));
    Sub := N.Get('project');
    if Sub <> nil then
    begin
      WriteLn('Project kind: ', Ord(Sub.Kind));
      WriteLn('  name: [', Sub.GetString('name', 'MISS'), ']');
      WriteLn('  type: [', Sub.GetString('type', 'MISS'), ']');
    end
    else
      WriteLn('project sub is nil');
    N.Free;

    // Try with different spacing
    WriteLn;
    N := P.Parse('project:' + #10 + '    name: TestProject' + #10 + '    type: desktop');
    Sub := N.Get('project');
    if Sub <> nil then
      WriteLn('4-space indent: name=[', Sub.GetString('name', 'MISS'), ']')
    else
      WriteLn('4-space indent: project sub is nil');
    N.Free;
  finally
    P.Free;
  end;
end.
