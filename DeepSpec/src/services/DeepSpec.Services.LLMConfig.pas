{ ============================================================================
  DeepSpec.Services.LLMConfig

  Helper to configure DeepBase LLM with common providers.
  Provides a one-shot setup for ModelScope (OpenAI-compatible).

  This service does NOT hardcode API keys. It accepts them at runtime
  and saves them through DeepBase's existing secure storage.
  ============================================================================ }

unit DeepSpec.Services.LLMConfig;

interface

uses
  System.SysUtils,
  DeepBase.LLM,
  DeepBase.LLM.Types;

type
  TDeepSpecLLMConfigHelper = class
  public
    /// <summary>
    /// Save a ModelScope (OpenAI-compatible) LLM configuration.
    /// API key is stored via DeepBase's existing secure mechanism.
    /// </summary>
    class procedure SaveModelScopeConfig(ALLM: TDeepBaseLLM;
      const AApiKey, AModel: string;
      const AConfigName: string = 'Default'); static;

    /// <summary>
    /// Save a generic OpenAI-compatible LLM configuration.
    /// </summary>
    class procedure SaveOpenAICompatible(ALLM: TDeepBaseLLM;
      const AConfigName, ABaseUrl, AApiKey, AModel: string); static;

    /// <summary>
    /// Check if a config is already saved with a non-empty API key.
    /// </summary>
    class function IsConfigured(ALLM: TDeepBaseLLM;
      const AConfigName: string = 'Default'): Boolean; static;
  end;

implementation

class procedure TDeepSpecLLMConfigHelper.SaveModelScopeConfig(ALLM: TDeepBaseLLM;
  const AApiKey, AModel: string; const AConfigName: string);
begin
  SaveOpenAICompatible(ALLM, AConfigName,
    'https://api-inference.modelscope.cn/v1', AApiKey, AModel);
end;

class procedure TDeepSpecLLMConfigHelper.SaveOpenAICompatible(ALLM: TDeepBaseLLM;
  const AConfigName, ABaseUrl, AApiKey, AModel: string);
var
  LConfig: TLLMConfig;
begin
  if ALLM = nil then
    raise Exception.Create('LLM service not available');

  LConfig.Init;
  LConfig.Name := AConfigName;
  LConfig.Provider := lpOpenAI; // OpenAI-compatible
  LConfig.BaseUrl := ABaseUrl;
  LConfig.ApiKey := AApiKey;
  LConfig.Model := AModel;
  LConfig.MaxTokens := 4096;
  LConfig.Temperature := 0.3;
  LConfig.SystemPrompt := '';
  LConfig.IsEnabled := True;
  LConfig.IsDefault := SameText(AConfigName, 'Default');

  ALLM.SaveConfig(LConfig);
  ALLM.RefreshConfigCache;
end;

class function TDeepSpecLLMConfigHelper.IsConfigured(ALLM: TDeepBaseLLM;
  const AConfigName: string): Boolean;
var
  LCfg: TLLMConfig;
begin
  Result := False;
  if ALLM = nil then Exit;
  try
    LCfg := ALLM.GetConfig(AConfigName);
    Result := LCfg.IsEnabled and (LCfg.ApiKey <> '') and (LCfg.BaseUrl <> '');
  except
    Result := False;
  end;
end;

end.
