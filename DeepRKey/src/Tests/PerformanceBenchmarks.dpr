program PerformanceBenchmarks;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.Classes,
  DeepRKey.PerformanceBenchmark in 'DeepRKey.PerformanceBenchmark.pas';

var
  Benchmark: TPerformanceBenchmark;
  ReportFile: string;

begin
  try
    Writeln('DeepRKey 性能基准测试');
    Writeln('====================');
    Writeln;

    Benchmark := TPerformanceBenchmark.Create;
    try
      Writeln('运行基准测试...');
      Benchmark.RunAllBenchmarks;

      Writeln;
      Writeln('生成报告...');
      ReportFile := ExtractFilePath(ParamStr(0)) + 'performance_report.txt';
      Benchmark.SaveReportToFile(ReportFile);

      Writeln;
      Writeln(Benchmark.GenerateReport);

      Writeln;
      Writeln(Format('报告已保存到: %s', [ReportFile]));
    finally
      Benchmark.Free;
    end;

    Writeln;
    Writeln('按 Enter 键退出...');
    Readln;
  except
    on E: Exception do
    begin
      Writeln(Format('错误: %s', [E.Message]));
      ExitCode := 1;
    end;
  end;
end.
