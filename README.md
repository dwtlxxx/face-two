# Face two

Coding workspace.

## Getting started

```bash
git clone <repo-url>
cd "Face two"
```

## Layout

| Path | Purpose |
| --- | --- |
| `.gitignore` | Excludes dependencies, build output, secrets, and large media |
| `.gitattributes` | Normalizes line endings to LF in the repo, CRLF on Windows checkout |
| `.editorconfig` | Shared indentation / charset / newline rules across editors |
| `tools/` | Local automation scripts (auto-push) |

## Auto-push

`tools/git-autopush.ps1` pushes commits that already exist. It **never** runs
`git add` or `git commit` — commit content and messages stay a human decision,
so work in progress can never be pushed by accident. It exits quietly when
there is nothing to push.

Install it as a scheduled task (runs at logon, then every 10 minutes).
**Requires an elevated PowerShell** — creating a scheduled task needs admin:

```powershell
& "D:\desktop\Face two\tools\install-autopush-task.ps1"
```

Test it immediately, and read its output:

```powershell
Start-ScheduledTask -TaskName 'FaceTwo-Git-AutoPush'
Get-Content '.git-local\autopush.log' -Tail 20
```

Remove it:

```powershell
Unregister-ScheduledTask -TaskName 'FaceTwo-Git-AutoPush' -Confirm:$false
```

### Why commits are never automated

Auto-committing would put half-finished, possibly non-compiling code into the
public history on every file save. Saves are cheap; commits should be
deliberate.

### Note for this machine only

`github.com` is intercepted by a local accelerator (Steam++) via the `hosts`
file. This repo therefore sets `http.sslBackend=openssl` and a CA bundle in
`.git-local/` locally. Those settings are **not** committed and do not travel
with clones.

## Conventions

- **Never commit secrets.** Put local values in `.env` (ignored) and keep a committed `.env.example`.
- Keep build output (`dist/`, `build/`, `target/`, `node_modules/`) out of the repo.
- Large binaries do not belong in Git — use Git LFS or an external store.

## License

Not yet chosen. Add a `LICENSE` file before publishing if this repo is public.
