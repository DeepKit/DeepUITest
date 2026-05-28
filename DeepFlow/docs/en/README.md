# UniFlow Workflow Engine

> A powerful, extensible workflow engine for building AI-powered applications in Delphi/Pascal

[![CI](https://github.com/user/repo/actions/workflows/ci.yml/badge.svg)](https://github.com/user/repo/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Overview

UniFlow is a complete workflow engine designed for enterprise Delphi applications. It provides:

- **Visual Workflow Editor** - Drag-and-drop workflow design
- **AI Integration** - Built-in LLM support via DeepBase.LLM
- **Multi-language Skills** - Python and Node.js skill services
- **Session Management** - Conversation context tracking
- **Audit & Monitoring** - Comprehensive logging and metrics

## Documentation

| Document | Description |
|----------|-------------|
| [Quick Start](quick-start.md) | Get started in 5 minutes |
| [API Reference](api-reference.md) | Complete API documentation |
| [Workflow Definition](workflow-definition.md) | JSON workflow format |
| [Skills Development](skills-development.md) | Creating custom skills |
| [Deployment](deployment.md) | Production deployment guide |

## Architecture

```
┌─────────────────────────────────────────────────────────────�?
�?                     Host Application                        �?
�?                    (Delphi/Pascal)                          �?
├─────────────────────────────────────────────────────────────�?
�?                    UniFlow Engine                           �?
�? ┌─────────────�?┌─────────────�?┌─────────────────────�?  �?
�? �? Workflow   �?�?  Session   �?�?   Diagnostics      �?  �?
�? �? Executor   �?�?  Manager   �?�? (Logging/Tracing)  �?  �?
�? └─────────────�?└─────────────�?└─────────────────────�?  �?
�? ┌─────────────�?┌─────────────�?┌─────────────────────�?  �?
�? �?  Audit     �?�?  Metrics   �?�?    Security        �?  �?
�? �?  Manager   �?�? Collector  �?�? (Sanitizer/Filter) �?  �?
�? └─────────────�?└─────────────�?└─────────────────────�?  �?
├─────────────────────────────────────────────────────────────�?
�?                   External Services                         �?
�? ┌─────────────�?┌─────────────�?┌─────────────────────�?  �?
�? �?  Python    �?�?  Node.js   �?�?     LLM APIs       �?  �?
�? �?  Skills    �?�?  Skills    �?�?(OpenAI/Anthropic)  �?  �?
�? └─────────────�?└─────────────�?└─────────────────────�?  �?
└─────────────────────────────────────────────────────────────�?
```

## Quick Start

### 1. Basic Usage

```pascal
uses
  UniFlow.Workflow.Definition,
  UniFlow.Workflow.Executor,
  UniFlow.Workflow.Context;

var
  Definition: TWorkflowDefinition;
  Executor: TWorkflowExecutor;
  Context: TWorkflowContext;
begin
  // Load workflow definition
  Definition := TWorkflowDefinition.FromFile('workflow.json');
  
  // Create executor and context
  Executor := TWorkflowExecutor.Create(Definition);
  Context := TWorkflowContext.Create;
  
  // Set input variables
  Context.SetVariable('user_input', 'Hello, AI!');
  
  // Execute workflow
  Executor.Execute(Context);
  
  // Get result
  ShowMessage(Context.GetVariable('result').AsString);
end;
```

### 2. With Session Management

```pascal
uses
  UniFlow.Session.Manager;

var
  Session: TWorkflowSession;
begin
  // Create or resume session
  Session := SessionManager.GetOrCreate('user-123', 'workflow-id');
  
  // Add user message
  Session.AddMessage(TSessionMessage.CreateUser('What is AI?'));
  
  // Execute with session context
  Executor.ExecuteWithSession(Session);
  
  // Get AI response
  ShowMessage(Session.Messages.Last.Content);
end;
```

### 3. Calling Skills

```pascal
uses
  UniFlow.Skill.Client;

var
  Client: TSkillClient;
  Result: TSkillResult;
begin
  Client := TSkillClient.Create('http://localhost:8000');
  
  Result := Client.Execute('code_executor', TJSONObject.Create
    .AddPair('language', 'python')
    .AddPair('code', 'print(1 + 1)')
  );
  
  if Result.Success then
    ShowMessage(Result.Output.ToString);
end;
```

## Core Components

| Component | Description |
|-----------|-------------|
| `TWorkflowDefinition` | Workflow structure and configuration |
| `TWorkflowExecutor` | Step-by-step workflow execution |
| `TWorkflowContext` | Variable scope and expression evaluation |
| `TSessionManager` | Multi-turn conversation management |
| `TAuditManager` | Structured audit logging |
| `TMetricsRegistry` | Prometheus-compatible metrics |
| `TUniFlowDiagnostics` | Debugging and tracing |

## Node Types

UniFlow supports 14 built-in node types:

| Category | Types |
|----------|-------|
| Basic | `start`, `end` |
| Action | `llm`, `skill`, `http`, `script`, `assign`, `log` |
| Flow Control | `condition`, `loop`, `parallel`, `wait` |
| Advanced | `subworkflow`, `guard` |

## Skill Services

### Python Skills (FastAPI)

```bash
cd Skills
pip install -r requirements.txt
uvicorn src.main:app --port 8000
```

Built-in skills: `code_executor`

### Node.js Skills (Express)

```bash
cd Skills/nodejs
npm install
npm start
```

Built-in skills: `json_transform`, `http_request`, `text_process`

## Docker Deployment

```bash
# Python Skills
docker pull ghcr.io/user/repo/uniflow-skills-python:latest
docker run -p 8000:8000 uniflow-skills-python

# Node.js Skills
docker pull ghcr.io/user/repo/uniflow-skills-nodejs:latest
docker run -p 3000:3000 uniflow-skills-nodejs
```

## License

MIT License - see [LICENSE](LICENSE) for details.
