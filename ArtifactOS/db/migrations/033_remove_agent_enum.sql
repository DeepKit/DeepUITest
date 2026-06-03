-- Migration 033: Remove 'agent' from runtime enums
-- Agent is no longer a standalone component (Stack Decision §2).
-- Replaces CHECK constraints on runtime_instance and runtime_command.

-- runtime_instance: drop old check, add new without 'agent'
alter table artifactos.runtime_instance
  drop constraint if exists chk_runtime_instance_type;

alter table artifactos.runtime_instance
  add constraint chk_runtime_instance_type check (
    instance_type in ('desk', 'engine', 'publishing_runtime', 'diagnostic')
  );

-- runtime_command: drop old check, add new without 'agent'
alter table artifactos.runtime_command
  drop constraint if exists chk_runtime_command_source;

alter table artifactos.runtime_command
  add constraint chk_runtime_command_source check (
    requested_source in ('desk', 'amy', 'test', 'diagnostic', 'system')
  );
