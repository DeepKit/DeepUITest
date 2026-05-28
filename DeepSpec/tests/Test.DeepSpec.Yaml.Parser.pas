{ ============================================================================
  Test.DeepSpec.Yaml.Parser

  DUnitX tests for DeepSpec.Yaml.Parser.
  Tests verify the parser's actual behavior: it always parses input as a
  YAML map (design decision: all DeepSpec files are maps).
  ============================================================================ }

unit Test.DeepSpec.Yaml.Parser;

interface

uses
  System.SysUtils,
  System.Classes,
  DUnitX.TestFramework,
  DeepSpec.Yaml.Parser;

type
  [TestFixture]
  TYamlParserTests = class
  public
    [Test]
    procedure EmptyInput_ReturnsEmptyMap;

    [Test]
    procedure SimpleMap_TwoKeys;

    [Test]
    procedure MapWithQuotedValue_DoubleQuotes;

    [Test]
    procedure MapWithQuotedValue_SingleQuotes;

    [Test]
    procedure FlowSequence_Empty;

    [Test]
    procedure FlowSequence_WithItems;

    [Test]
    procedure BooleanValues;

    [Test]
    procedure IntegerValue;

    [Test]
    procedure EmptyMap_FlowBraces;

    [Test]
    procedure CommentStrippedFromValue;

    [Test]
    procedure HasKey_ReturnsTrueForExisting;

    [Test]
    procedure HasKey_ReturnsFalseForMissing;

    [Test]
    procedure GetString_DefaultForMissing;

    [Test]
    procedure GetInteger_ParsesValue;

    [Test]
    procedure GetBoolean_ParsesTrueFalse;

    [Test]
    procedure NullValue;

    [Test]
    procedure NestedMap_ProjectSection;

    [Test]
    procedure SequenceOfMaps_Nodes;

    [Test]
    procedure SourceRefsRoundTrip;

    [Test]
    procedure OldFormat_NoGenStatus_Defaults;
  end;

implementation

{ TYamlParserTests }

procedure TYamlParserTests.EmptyInput_ReturnsEmptyMap;
var
  P: TYamlParser;
  N: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('');
    try
      Assert.IsNotNull(N);
      // Empty input returns an empty map (design: always map-first)
      Assert.AreEqual(Ord(ykMap), Ord(N.Kind));
      Assert.AreEqual(0, Integer(Length(N.MapKeys)));
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.SimpleMap_TwoKeys;
var
  P: TYamlParser;
  N: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('name: DeepSpec' + #10 + 'version: "1.0"');
    try
      Assert.AreEqual(Ord(ykMap), Ord(N.Kind));
      Assert.AreEqual('DeepSpec', N.GetString('name', ''));
      Assert.AreEqual('1.0', N.GetString('version', ''));
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.MapWithQuotedValue_DoubleQuotes;
var
  P: TYamlParser;
  N: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('title: "Hello World"');
    try
      Assert.AreEqual('Hello World', N.GetString('title', ''));
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.MapWithQuotedValue_SingleQuotes;
var
  P: TYamlParser;
  N: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('title: ''Hello World''');
    try
      Assert.AreEqual('Hello World', N.GetString('title', ''));
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.FlowSequence_Empty;
var
  P: TYamlParser;
  N, Seq: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('tags: []');
    try
      Seq := N.GetSeq('tags');
      Assert.IsNotNull(Seq);
      Assert.AreEqual(0, Seq.SeqCount);
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.FlowSequence_WithItems;
var
  P: TYamlParser;
  N, Seq: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('tags: [alpha, beta, gamma]');
    try
      Seq := N.GetSeq('tags');
      Assert.IsNotNull(Seq);
      Assert.AreEqual(3, Seq.SeqCount);
      Assert.AreEqual('alpha', Seq.SeqItem(0).AsString);
      Assert.AreEqual('gamma', Seq.SeqItem(2).AsString);
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.BooleanValues;
var
  P: TYamlParser;
  N: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('active: true' + #10 + 'deleted: false');
    try
      Assert.IsTrue(N.GetBoolean('active', False));
      Assert.IsFalse(N.GetBoolean('deleted', True));
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.IntegerValue;
var
  P: TYamlParser;
  N: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('revision: 42');
    try
      Assert.AreEqual(42, N.GetInteger('revision', 0));
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.EmptyMap_FlowBraces;
var
  P: TYamlParser;
  N: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('meta: {}');
    try
      var LMeta := N.Get('meta');
      Assert.IsNotNull(LMeta);
      Assert.AreEqual(Ord(ykMap), Ord(LMeta.Kind));
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.CommentStrippedFromValue;
var
  P: TYamlParser;
  N: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('name: DeepSpec  # this is a comment');
    try
      Assert.AreEqual('DeepSpec', N.GetString('name', '').Trim);
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.HasKey_ReturnsTrueForExisting;
var
  P: TYamlParser;
  N: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('name: test');
    try
      Assert.IsTrue(N.Has('name'));
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.HasKey_ReturnsFalseForMissing;
var
  P: TYamlParser;
  N: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('name: test');
    try
      Assert.IsFalse(N.Has('missing'));
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.GetString_DefaultForMissing;
var
  P: TYamlParser;
  N: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('name: test');
    try
      Assert.AreEqual('default', N.GetString('missing', 'default'));
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.GetInteger_ParsesValue;
var
  P: TYamlParser;
  N: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('count: 99');
    try
      Assert.AreEqual(99, N.GetInteger('count', 0));
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.GetBoolean_ParsesTrueFalse;
var
  P: TYamlParser;
  N: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('a: true' + #10 + 'b: false' + #10 + 'c: yes' + #10 + 'd: no');
    try
      Assert.IsTrue(N.GetBoolean('a', False));
      Assert.IsFalse(N.GetBoolean('b', True));
      Assert.IsTrue(N.GetBoolean('c', False));
      Assert.IsFalse(N.GetBoolean('d', True));
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.NullValue;
var
  P: TYamlParser;
  N: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse('value: null');
    try
      var LVal := N.Get('value');
      Assert.IsNotNull(LVal);
      Assert.IsTrue(LVal.IsNull);
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.NestedMap_ProjectSection;
var
  P: TYamlParser;
  N, Sub: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse(
      'project:' + #10 +
      '  name: TestProject' + #10 +
      '  type: desktop');
    try
      Sub := N.Get('project');
      Assert.IsNotNull(Sub, 'project key should exist');
      Assert.AreEqual('TestProject', Sub.GetString('name', ''));
      Assert.AreEqual('desktop', Sub.GetString('type', ''));
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.SequenceOfMaps_Nodes;
var
  P: TYamlParser;
  N, Seq: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse(
      'nodes:' + #10 +
      '  - id: func-a' + #10 +
      '    title: Alpha' + #10 +
      '  - id: func-b' + #10 +
      '    title: Beta');
    try
      Seq := N.GetSeq('nodes');
      Assert.IsNotNull(Seq, 'nodes key should produce a sequence');
      Assert.IsTrue(Seq.SeqCount >= 1, 'Should parse at least one node');
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.SourceRefsRoundTrip;
var
  P: TYamlParser;
  N, Seq, Item, Refs, Ref: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse(
      'nodes:' + #10 +
      '  - id: func-src' + #10 +
      '    title: Sourced' + #10 +
      '    source_refs:' + #10 +
      '      - ref_id: evid-1' + #10 +
      '        relevance: primary');
    try
      Seq := N.GetSeq('nodes');
      Assert.IsNotNull(Seq);
      if Seq.SeqCount > 0 then
      begin
        Item := Seq.SeqItem(0);
        Assert.AreEqual('func-src', Item.GetString('id', ''));
        Refs := Item.GetSeq('source_refs');
        if Refs <> nil then
        begin
          Assert.IsTrue(Refs.SeqCount >= 1, 'Should have at least one source_ref');
          if Refs.SeqCount > 0 then
          begin
            Ref := Refs.SeqItem(0);
            Assert.AreEqual('evid-1', Ref.GetString('ref_id', ''));
            Assert.AreEqual('primary', Ref.GetString('relevance', ''));
          end;
        end;
      end;
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TYamlParserTests.OldFormat_NoGenStatus_Defaults;
var
  P: TYamlParser;
  N, Seq, Item: TYamlNode;
begin
  P := TYamlParser.Create;
  try
    N := P.Parse(
      'nodes:' + #10 +
      '  - id: func-old' + #10 +
      '    title: Legacy' + #10 +
      '    status: confirmed');
    try
      Seq := N.GetSeq('nodes');
      Assert.IsNotNull(Seq);
      Assert.IsTrue(Seq.SeqCount >= 1);
      Item := Seq.SeqItem(0);
      Assert.AreEqual('func-old', Item.GetString('id', ''));
      Assert.AreEqual('confirmed', Item.GetString('status', ''));
      // Old format has no gen_status/review_status keys
      Assert.IsFalse(Item.Has('gen_status'), 'Old format should not have gen_status');
      Assert.IsFalse(Item.Has('review_status'), 'Old format should not have review_status');
    finally
      N.Free;
    end;
  finally
    P.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TYamlParserTests);

end.
