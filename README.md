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

## License

Not yet chosen. Add a `LICENSE` file before publishing if this repo is public.
