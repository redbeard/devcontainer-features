# GitHub CLI auth from the host (`gh-auth-from-host`)

Makes `gh` work inside a dev container using **the host's** GitHub credential, refreshed on every attach — so the container never holds a credential of its own.

```jsonc
"features": {
  "ghcr.io/redbeard/devcontainer-features/gh-auth-from-host:1": {}
}
```

The `github-cli` Feature is pulled in automatically as a dependency; you don't need to list it.

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `githubHostname` | string | `github.com` | Hostname to authenticate against; set to your GHES host for Enterprise Server. |
| `overrideExisting` | boolean | `true` | Replace a container-local credential with the host's. `false` keeps a working container credential (e.g. a narrow PAT) but still repairs a dead one. |

## Why this is needed

The `github-cli` Feature installs the binary and nothing else — it forwards no credentials. The Dev Containers extension *does* forward a credential from the host, but as a **git credential helper**:

```console
$ printf 'protocol=https\nhost=github.com\n\n' | git credential fill
username=you
password=gho_…
```

**`gh` never reads git's credential helper.** Its auth sources are `GH_TOKEN`/`GITHUB_TOKEN` and its own store (keyring or `hosts.yml`) — a git helper isn't among them, and can't be. The integration runs the other way: `gh auth setup-git` makes *git* use *gh*.

So the delegation exists but is invisible to `gh`. This Feature is the missing wire: it reads the helper and hands the result to `gh auth login --with-token` on every attach.

The alternative most people land on — running `gh auth login` inside the container — creates a competing credential that *shadows* the delegation (gh prefers its own store) and is a point-in-time snapshot, so it silently rots the moment the host's token changes.

## Requirements

- The host must have `gh auth setup-git` configured, so that what the helper relays is the host's own `gh` token. Verify they match:
  ```console
  # host                                        # container
  gh auth token | shasum -a 256 | cut -c1-12    gh auth token | sha256sum | cut -c1-12
  ```
- An editor that forwards credentials must be attached. Under the `devcontainer` CLI or a bare `docker exec` there's no helper; the hook warns and leaves `gh` untouched.

## Behaviour notes

- **Never exits non-zero.** A Feature's failing lifecycle hook halts the entire sequence — later Features' hooks and the project's own — so every failure path warns and stands down.
- **gh's own credential helper is excluded from the question.** `gh auth setup-git` run *inside* the container installs gh as git's helper, and the config section it writes opens with an empty `helper =` that **resets the helper list** — wiping the editor's forwarded helper for that host. A plain `git credential fill` would then hand back gh's own stored token, which this hook would match against what gh already has and report as success, while the stale credential quietly survived. Only non-gh helpers are consulted; if that leaves none, the hook says so rather than accepting gh's answer as the host's.
- **Idempotent.** When the container already holds exactly what the host offers, it does nothing: no config rewrite, no API call. It runs on every attach, including waking from sleep.
- **This is coupling, not isolation.** The container's `gh` is exactly as alive as the host's. If you want a credential revocable independently of your laptop's, use a container PAT with `overrideExisting: false` instead.
- Git push/pull over SSH is unaffected — that's SSH agent forwarding, which the editor handles separately.
