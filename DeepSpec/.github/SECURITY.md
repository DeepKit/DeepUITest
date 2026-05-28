# Security Policy

## Reporting a Vulnerability

Please do not publish security-sensitive findings in public issues if they include secrets, private project data, or exploit details.

Report privately to the project maintainer until a public process is established.

## Sensitive Data Rules

DeepSpec may inspect source code, requirements, UI files, and project metadata. Treat all of these as potentially sensitive.

Do not commit:

- API keys, tokens, cookies, credentials, or local config secrets
- private customer requirements or proprietary source snippets unless explicitly anonymized
- `.deepspec/` workspaces generated from private projects without review
- database dumps or generated binary artifacts

## Agent Safety

Coding agents should receive least-privilege context. Do not pass an entire private project to an LLM when a smaller context pack is sufficient.
