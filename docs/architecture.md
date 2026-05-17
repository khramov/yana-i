# Personal Portfolio Tracker — Architecture

## Core Principle: Local-First, API-Centric

The application is designed to run on your own machine. There is no cloud backend, no third-party account, and no data leaves your computer unless you explicitly move it. The database is a single SQLite file — portable by design.

```
┌─────────────────────────────────────────────────┐
│                  Your Machine                   │
│                                                 │
│   ┌─────────────┐       ┌──────────────────┐   │
│   │  SQLite DB  │ ←───► │  Next.js Server  │   │
│   │ portfolio.db│       │  (API + Web UI)  │   │
│   └─────────────┘       └────────┬─────────┘   │
│                                  │              │
└──────────────────────────────────┼──────────────┘
                                   │ HTTP
              ┌────────────────────┼────────────────────┐
              │                    │                     │
        ┌─────▼──────┐    ┌────────▼───────┐   ┌────────▼───────┐
        │  Browser   │    │  iOS / Android │   │  macOS native  │
        │ (web app)  │    │  (future)      │   │  (future)      │
        │ localhost  │    │  via local IP  │   │  Tauri/Electron│
        └────────────┘    └────────────────┘   └────────────────┘
```

## Database — Local SQLite

- One file: `portfolio.db` (path configurable via `DATABASE_URL` in `.env.local`)
- **Migrating to another computer:** copy `portfolio.db` to the new machine and run `npm run db:migrate` — done
- **Backup:** copy `portfolio.db` anywhere (USB, cloud storage, etc.)
- WAL mode enabled for safe concurrent reads

## Current Client: Web App

A Next.js app running on `localhost:3000` is the starting point. It is the simplest approach because:
- No native build toolchain required
- Single codebase for UI and API
- Works on any OS immediately
- The browser is the UI — no installation needed

## Future Clients: Mobile and Native

The Next.js API layer is the integration boundary. Future clients (iOS, Android, macOS native) connect to the same API — they do **not** access the SQLite file directly.

| Client | How it connects | Effort to add |
|---|---|---|
| Web (now) | `localhost:3000` in browser | — |
| macOS native | Tauri or Electron wraps the web UI | Low — same HTML/JS |
| iOS / Android | Native app calls the Next.js API over local network | Medium — separate app, same API |
| Remote access | Tailscale VPN or nginx reverse proxy on a home server | Low infra change |

To make the server reachable from mobile devices on the same network, start with:
```json
"start": "next start -H 0.0.0.0"
```

## What This Is Not

- Not a SaaS — no multi-user support, no cloud hosting required
- Not a brokerage — read/track only, no trade execution
- Not dependent on any external account — Yahoo Finance data is fetched anonymously

---

## Related

- [Design — UI stack, component library, LLM integration](design.md)

