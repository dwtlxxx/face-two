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

## Conventions

- **Never commit secrets.** Put local values in `.env` (ignored) and keep a committed `.env.example`.
- Keep build output (`dist/`, `build/`, `target/`, `node_modules/`) out of the repo.
- Large binaries do not belong in Git — use Git LFS or an external store.

## Note for this machine only

`github.com` is intercepted by a local accelerator (Steam++) via the `hosts`
file. This repo therefore sets `http.sslBackend=openssl` and points
`http.sslCAInfo` at a CA bundle in `.git-local/`. Those settings live in
`.git/config` only — they are **not** committed and do not travel with clones.
A fresh clone on a machine without that interception needs no such workaround.

## License

Not yet chosen. Add a `LICENSE` file before publishing if this repo is public.
