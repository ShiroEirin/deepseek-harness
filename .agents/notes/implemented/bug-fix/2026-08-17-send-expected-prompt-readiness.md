# Agent Note: Send-declared `expectedPrompt` restores exact PTY readiness

Status: implemented

English | [中文](2026-08-17-send-expected-prompt-readiness.zh.md)

## Problem

`tool-bash-persistent` replaces `PS1` with its private `__DSH_PERSISTENT_BASH_PROMPT__ ` on an initialization send right after spawn, while `terminal-bash` pinned exact prompt readiness to its own controlled prompt `dsh> `. For that tool the printable tail after the private OSC marker never matched, so the exact readiness path never fired and every fast command settled through the silence fallback at `idleSilenceMs + handoffGraceMs` (3.5 s under shipped defaults). A session's first `bash` call paid the fallback twice: once for the prompt-assignment send, once for the command itself.

## Decision

`TerminalSendRequest` gains an optional `expectedPrompt`: the exact prompt text a send that changes `PS1` settles at. `LocalPtySession` runs the post-marker tail comparison against the active send's declared text, falling back to the controlled prompt when undeclared, and resets to the controlled prompt when the send clears. `tool-bash-persistent` declares its `SHELL_PROMPT` on the initialization send and on every command send, so the layer that changes the prompt informs the backend; startup readiness still matches the spawn-time `PS1` because `initialize()` declares nothing.

## Alternatives considered

- **Repoint the backend constant at the tool's prompt** (the circulating patch): couples the generic backend to one consumer's private prompt and renames the visible prompt for every other `shell`-type session, including interactive `tool-terminal` terminals.
- **Drop the tool's `PS1` override and reuse `dsh> `**: weakens the tool's output handling — `stripPrompt`, `promptCompleted`, and the truncated-scrollback `replaceAll` path would match a five-character string command output can plausibly contain; the nonce-marker design assumes a distinctive prompt.
- **Learn the prompt after a fallback settle**: replaces a static fact the caller already knows with a mutation state machine whose inputs (echoed input, late markers) are unreliable.
- **A backend config field set from each composing cordis.yml**: copies one package's private constant into every preset and silently reintroduces the fallback on drift.

## Consequences

Fast `bash` commands through `tool-bash-persistent` settle through exact readiness again — about one poll interval instead of the 3.5 s silence fallback — including the initialization send. The field is optional and the registry forwards requests verbatim, so other senders and backends are unaffected. The contract is per-send: a consumer that changes `PS1` declares the prompt on every later send, and a send without a declaration still falls back to silence-based readiness rather than settling on a stale prompt.
