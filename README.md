# Olives DB Drift Tool

Desktop-first tool to compare Master (105) vs client SQL Server schemas, review drift, and assemble safe apply scripts.

## Run (desktop)

```bash
./run-desktop.sh
```

Desktop shortcut (after clone):

```bash
INSTALL_ROOT="$(pwd)"
sed "s|@INSTALL_ROOT@|$INSTALL_ROOT|g" olives-drift-tool.desktop \
  > ~/.local/share/applications/olives-drift-tool.desktop
update-desktop-database ~/.local/share/applications 2>/dev/null || true
```

Requires: Docker (`drift-tool-mssql` scratch SQL Server), `sqlpackage` + .NET runtime (see `drift/config.py`), system PyGObject + WebKit2 (`python3-gi`, `gir1.2-webkit2-4.1`).

## Environment

| Variable | Purpose |
|----------|---------|
| `DRIFT_MSSQL_SA_PASSWORD` | SA password for the scratch Docker container (set once; recreate container if you change it: `docker rm -f drift-tool-mssql`) |
| `DEEPSEEK_API_KEY` | AI merge proposals (optional) |
| `OPENROUTER_API_KEY` | AI triage on findings (optional) |

Optional: create `apps/drift-tool/.env` with the above; `run-desktop.sh` loads it if present.

## Browser mode (secondary)

```bash
./run.sh
```

Opens `http://localhost:5057` in the system browser.

## Docs

- [Architecture](docs/ARCHITECTURE.md)
- [Tutorial](docs/TUTORIAL.md)

## Tests

```bash
cd apps/drift-tool && python3.13 -m pytest -q
```
