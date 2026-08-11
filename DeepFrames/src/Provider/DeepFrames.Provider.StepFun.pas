unit DeepFrames.Provider.StepFun;

/// <summary>
/// StepFun provider 聚合壳(DBA-3 拆分,2026-07-21)。
/// 原单体 StepFun.pas (1394行/4类) 已按能力拆为五子 unit:
///   .Shared(const 共享)、.LLM、.TTS、.ASR、.Image。
/// 本壳用类型别名 re-export 四能力类,使原 uses DeepFrames.Provider.StepFun
/// 的代码(Registry.pas)零修改即可继续引用 TStepFunLLMProvider/TTS/ASR/Image。
/// 行为零变化——所有实现已逐字搬入子 unit。
/// </summary>

interface

uses
  DeepFrames.Provider.StepFun.Shared,
  DeepFrames.Provider.StepFun.LLM,
  DeepFrames.Provider.StepFun.TTS,
  DeepFrames.Provider.StepFun.ASR,
  DeepFrames.Provider.StepFun.Image;

type
  TStepFunLLMProvider = DeepFrames.Provider.StepFun.LLM.TStepFunLLMProvider;
  TStepFunTTSProvider = DeepFrames.Provider.StepFun.TTS.TStepFunTTSProvider;
  TStepFunASRProvider = DeepFrames.Provider.StepFun.ASR.TStepFunASRProvider;
  TStepFunImageProvider = DeepFrames.Provider.StepFun.Image.TStepFunImageProvider;

implementation

// 纯转发壳,无实现体。共享 const(STEPFUN_*_URL/SECRET_*/MAX_RETRIES/
// RETRY_DELAY_MS)在 .Shared 子 unit 公开,四能力子 unit 均已 uses .Shared
// 直接引用,壳不重复声明以避免符号歧义。

end.
