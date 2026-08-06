# devcontainer-features

Personal [Dev Container Features](https://containers.dev/implementors/features/).

| Feature | Description |
|---|---|
| [`gh-auth-from-host`](src/gh-auth-from-host) | Authenticates the `gh` CLI inside a dev container from the **host's** GitHub credential, refreshed on every attach — so the container never holds a credential of its own. |

```jsonc
"features": {
  "ghcr.io/redbeard/devcontainer-features/gh-auth-from-host:1": {}
}
```
