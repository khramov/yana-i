# Personal Portfolio Tracker — Design

## Technology Stack

| Layer | Technology | Why |
|---|---|---|
| Framework | Next.js 14 (App Router) | UI and API in one repo, best LLM code generation support |
| Styling | Tailwind CSS | Utility classes in markup — LLMs generate it accurately and consistently |
| Components | shadcn/ui | Pre-built accessible components; Claude knows every prop and variant |
| Charts | Recharts | Declarative React API; covers all chart types needed (line, bar, pie, donut) |
| LLM features | Anthropic TypeScript SDK + Vercel AI SDK | Streaming responses, tool use, hooks — no Python backend needed |

## Why This Stack for LLM-Assisted Development

React + Tailwind + shadcn/ui is the combination AI models generate best. It is the most popular frontend stack, which means the most training data and the most accurate, idiomatic output.

- **Tailwind** — design expressed as class names inline. No separate CSS file. Models write one line and styling is complete.
- **shadcn/ui** — Claude knows every component in detail: props, variants, composition patterns. Prompting "add a sortable DataTable" or "add a slide-over Sheet panel" produces working code immediately.
- **v0.dev** — Vercel's tool for generating React + Tailwind + shadcn/ui from plain English descriptions. Output pastes directly into the project.

## Component Library — shadcn/ui

Key components used in this project:

| Component | Used for |
|---|---|
| `Card` | KPI summary cards on dashboard |
| `DataTable` | Holdings, transactions, dividends tables |
| `Sheet` | Slide-over panel for transaction add/edit form |
| `Select` / `Combobox` | Ticker picker, year filter, type filter |
| `DatePicker` | Transaction date input |
| `Dialog` | Confirmation dialogs |
| `Tabs` | Page-level section navigation |
| `Badge` | Transaction type labels (buy / sell / dividend / fee) |
| `Skeleton` | Loading states |
| `Toast` | Success / error notifications |

## LLM Integration (Vercel AI SDK)

```typescript
import { streamText } from 'ai'
import { anthropic } from '@anthropic-ai/sdk'

export async function POST(req: Request) {
  const { messages, portfolioContext } = await req.json()

  const result = streamText({
    model: anthropic('claude-sonnet-4-6'),
    system: `You are a portfolio analysis assistant. The user's portfolio data: ${portfolioContext}`,
    messages,
  })

  return result.toDataStreamResponse()
}
```

Portfolio data (holdings, P&L, allocations) is fetched from the local database and passed as context on each request. No data leaves the machine except what is explicitly sent to the API.

## Suggested LLM Features

| Feature | What it does |
|---|---|
| Portfolio summary | Plain-language explanation of current holdings and concentration |
| P&L analysis | Interpret recent performance, flag unusual changes |
| Rebalancing suggestion | Compare current allocation vs targets, suggest trades |
| Dividend outlook | Summarize upcoming income based on ex-div dates and holdings |

## Design Principles

- **Dense but readable** — a portfolio dashboard needs to show a lot of data; use compact table rows, not cards for every row
- **Dark mode by default** — financial dashboards are typically dark; shadcn/ui supports this with one class toggle
- **Numbers aligned right** — all currency and percentage columns right-aligned for scannability
- **Color convention** — green for positive P&L / income, red for losses, neutral gray for fees and taxes
- **No decorative elements** — charts and tables only; no marketing-style illustrations
