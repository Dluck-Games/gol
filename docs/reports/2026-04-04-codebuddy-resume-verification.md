# CodeBuddy `--resume` + `-p` Verification

Date: 2026-04-04
Worktree: `/Users/dluckdu/Documents/Github/gol/.worktrees/manual/multi-phase-resume/foreman`

## Result

`--resume <session-id> -p` works in this environment.

- Process started without error.
- The resumed run retained context from the previous prompt.
- A new init message was emitted.
- Caveat: in this verification, the resumed init message reused the same `session_id` rather than emitting a different one.

## Exact CLI invocations used

Step 1:

```bash
cd /tmp
codebuddy -p --output-format stream-json "echo hello" 2>/dev/null | head -5
```

Step 2:

```bash
cd /tmp
codebuddy --resume 32ccf53c-f1cf-46df-ba20-608c87cde5bb -p --output-format stream-json "What was the previous task you performed?" 2>/dev/null | head -20
```

## Captured output snippets

### Step 1 init snippet

```json
{"type":"system","subtype":"init","uuid":"32ccf53c-f1cf-46df-ba20-608c87cde5bb","session_id":"32ccf53c-f1cf-46df-ba20-608c87cde5bb",...}
{"type":"file-history-snapshot","id":"3424a936-d4c8-46c4-8560-ba6115ecc43b",...}
{"type":"assistant","uuid":"cbfdd758-6b3d-4379-9c9b-478e31b34e34","session_id":"32ccf53c-f1cf-46df-ba20-608c87cde5bb",...}
{"type":"assistant","uuid":"chatcmpl-JZG9O7fRQV0rbsZd5rhJW5C5","session_id":"32ccf53c-f1cf-46df-ba20-608c87cde5bb",...}
{"type":"assistant","uuid":"chatcmpl-JZG9O7fRQV0rbsZd5rhJW5C5","session_id":"32ccf53c-f1cf-46df-ba20-608c87cde5bb",...}
```

Captured session ID:

```text
32ccf53c-f1cf-46df-ba20-608c87cde5bb
```

### Step 2 resume snippet

```json
{"type":"system","subtype":"init","uuid":"32ccf53c-f1cf-46df-ba20-608c87cde5bb","session_id":"32ccf53c-f1cf-46df-ba20-608c87cde5bb",...}
{"type":"file-history-snapshot","id":"3940c9cb-bf5d-4042-95cc-a756d6b384d2",...}
{"type":"assistant","uuid":"chatcmpl-XXEeO8HHoWRAaqRG1IIv2zyG","session_id":"32ccf53c-f1cf-46df-ba20-608c87cde5bb","message":{"content":[{"type":"text","text":"The previous task I performed was running `echo hello` in the shell, which printed \"hello\" to the terminal."}]},...}
{"type":"result","subtype":"success","is_error":false,"result":"The previous task I performed was running `echo hello` in the shell, which printed \"hello\" to the terminal.",...}
```

## Findings

### Does `--resume` + `-p` work?

Yes.

### Evidence

1. The resume command launched successfully with no startup error.
2. The model accurately recalled the prior task: running `echo hello`.
3. The JSON stream began with a fresh `system/init` event.

## Caveats

- The resumed session emitted a new init event, but the `session_id` matched the original captured session ID in this environment.
- The task requirement allowed for a possibly different session ID; observed behavior here is same-ID resume.
- Because stderr was redirected to `/dev/null`, this verification only confirms successful startup and streamed output, not any suppressed warnings.

## Conclusion

Proceeding assumption is valid: `codebuddy --resume <session-id> -p` is usable for subsequent tasks.

Fallback is not needed for this environment. If future environments fail to support this combination, `--continue` should be treated as the fallback approach.
