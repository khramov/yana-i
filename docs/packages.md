# Package Reference — Yana Portfolio Tracker

Complete review of every dependency: why it's here, stability, security record, performance notes, and alternatives. Updated May 2026.

---

## Quick Risk Summary

| Package | Version | Security | Stability | Action needed |
|---|---|---|---|---|
| `next` | 16.2.6 | ✅ Safe (CVEs patched) | Stable | None |
| `react` / `react-dom` | 19.2.4 | ✅ Safe (CVEs patched) | Stable | None |
| `drizzle-orm` | 0.45.2 | ✅ Safe (SQL-injection CVE fixed in this version) | Maturing | None |
| `better-sqlite3` | 12.10.0 | ✅ Safe | Stable | None |
| `react-hook-form` | 7.76.1 | ✅ Safe | Stable | None |
| `zod` | 4.4.3 | ✅ Safe | Stable | None |
| `swr` | 2.4.1 | ✅ Safe | Stable | None |
| `@base-ui/react` | 1.5.0 | ✅ Safe | Beta/Maturing | None |
| `@hookform/resolvers` | 5.4.0 | ✅ Safe | Stable | None |
| `lucide-react` | 1.16.0 | ✅ Safe | Stable | None |
| `tailwind-merge` | 3.6.0 | ✅ Safe | Stable | None |
| `clsx` | 2.1.1 | ✅ Safe | Stable (dormant) | None |
| `class-variance-authority` | 0.7.1 | ✅ Safe | Stable (dormant) | Watch for bugs |
| `tw-animate-css` | 1.4.0 | ✅ Safe | Stable | None |
| `yahoo-finance2` | 3.14.1 | ✅ Safe | Unofficial API | Have a fallback plan |
| `shadcn` | 4.8.0 | ✅ Safe | Stable | **Move to devDependencies** |
| `drizzle-kit` | 0.31.10 | ⚠️ Dep-chain issue | Maturing | Monitor esbuild fix |

---

## Runtime Dependencies

---

### `next` — 16.2.6

**What it does:** The React framework powering the entire app. Provides file-based routing (App Router), Server Components, API routes (`/app/api/`), image optimization, and the build pipeline.

**Why this project uses it:** Chosen to avoid maintaining separate frontend and backend processes. API routes run as Node.js serverless functions in the same process, which means `better-sqlite3` can be imported directly from them with no network hop.

**Stability:** Production-grade. 130k+ GitHub stars. Backed by Vercel with multiple engineers full-time on it.

**Security:**

Three major CVEs were disclosed in late 2025, all affecting React Server Components:

- **CVE-2025-66478** (CVSS 10.0) — Pre-auth Remote Code Execution via RSC. Fixed in 15.1.3 / 16.0.10.
- **CVE-2025-55184** (High) — Denial of Service via malformed RSC request. Fixed in 16.0.10.
- **CVE-2025-55183** (Medium) — Source code exposure in development mode. Fixed in 16.0.10.

**The installed version (16.2.6) is safe.** All three CVEs are patched. No action required, but stay on 16.x and apply updates promptly — this was a reminder that RSC adds server-side attack surface that didn't exist in Pages Router apps.

**Performance:** For a single-user local app, Next.js is more than adequate. Server Components reduce client bundle size by keeping data-fetching logic on the server. The main overhead is the build step (~5–15 seconds), not runtime.

**Cons / risks:**
- Genuinely complex for what is a personal local app — Remix or a plain Vite + Express setup would be simpler.
- App Router is still evolving; there are real bugs in caching behavior.
- Vercel-optimized: some features (ISR, Image Optimization with remote URLs) work best or only on Vercel.

**Alternatives:**
| Alternative | Trade-off |
|---|---|
| Remix | Simpler routing model, same full-stack approach, smaller community |
| SvelteKit | Smaller bundles, less ecosystem, different language |
| Vite + Express | Maximum control, requires manually wiring everything |
| Astro | Better for static/content-heavy sites, not ideal for data-heavy dashboards |

---

### `react` + `react-dom` — 19.2.4

**What it does:** The UI rendering library. React 19 introduces Actions (async form handling), useFormStatus, new ref behavior as props, and improved hydration error messages. `react-dom` is the DOM-specific renderer.

**Why this project uses it:** Required by Next.js. No choice here.

**Stability:** 228k+ GitHub stars. Meta/Facebook funded. Most widely used UI library in the world.

**Security:**

React 19.2.x had a cluster of CVEs discovered simultaneously with the Next.js ones above, since they share the RSC implementation:

- **CVE-2025-55182** (CVSS 10.0) — RSC deserialization leading to RCE. Affected 19.0.0–19.2.3.
- **CVE-2025-55184** / **CVE-2025-55183** — Same DoS and source exposure as Next.js CVEs above.

**The installed version (19.2.4) is safe.** This was the patch release specifically for these CVEs.

**Performance:** React 19 includes compiler optimizations that reduce unnecessary re-renders without manually adding `useMemo` and `useCallback`. For this app the effect is minimal, but it's a net positive.

**Cons / risks:**
- React 19 had minor breaking changes from 18 (notably around refs and `useEffect` timing). Worth reading the migration guide if integrating third-party components.
- The React Compiler (auto-memoization) is still opt-in and experimental.

**Alternatives:** There are no practical alternatives when using Next.js.

---

### `better-sqlite3` — 12.10.0

**What it does:** Synchronous SQLite bindings for Node.js. The entire database layer for this app — holdings, transactions, price cache all live in `data/yana.db`.

**Why this project uses it:** For a single-user personal app, SQLite is the right database. No server to manage, no Docker, backup is a single file copy. `better-sqlite3` specifically was chosen over the older `sqlite3` package because its synchronous API is simpler (no async/await chains for every query), it is significantly faster, and it supports WAL mode which prevents read-write contention.

**Stability:** 12k+ GitHub stars. Maintained by WiseLibs. The last commit was 11 days before this review. It is the de-facto standard SQLite library for Node.js.

**Security:** No CVEs. The C++ bindings are reviewed regularly. Prebuilt binaries are distributed for common platforms, avoiding on-machine compilation risks. The biggest security consideration here is not the library itself but SQLite's threat model: the database file is trusted and local. If this app were exposed to the internet, parameterized queries (which Drizzle uses automatically) would be the critical defense.

**Performance:**
- Synchronous API avoids the overhead of Promise chains and the event loop — queries return directly.
- WAL mode (already enabled in `lib/db/index.ts`) allows multiple concurrent readers and one writer, and dramatically speeds up write throughput.
- With WAL and `synchronous=NORMAL`, typical throughput is 2,000–5,000 queries/second on a modern laptop. For a portfolio app making tens of queries per page load, this is orders of magnitude more than needed.
- The synchronous nature is also its main risk in a web server context — a very slow query blocks the Node.js event loop. For this app (millisecond queries, single user) this is irrelevant.

**Cons / risks:**
- Cannot scale beyond one machine or one process writer. Not a concern for a personal app.
- Synchronous API would be a problem in high-concurrency environments — again, not applicable here.
- Requires a native build step (C++ addon). Prebuilt binaries cover most cases but can break on unusual architectures.

**Alternatives:**
| Alternative | Trade-off |
|---|---|
| `sqlite3` (async) | Older, slower, async-only API — no advantage for this use case |
| `sql.js` | Pure JS (no native build), runs in memory only, no persistence |
| Turso / libSQL | Cloud-hosted SQLite — adds network latency and a paid dependency |
| PostgreSQL | Network overhead, requires a running server — overkill for personal use |

---

### `drizzle-orm` — 0.45.2

**What it does:** TypeScript ORM. Provides type-safe query building (`db.select().from(holdings).where(...)`) and schema definition (`lib/db/schema.ts`) that serves as the single source of truth for the database structure.

**Why this project uses it:** Raw SQL strings lose type safety — a typo in a column name only fails at runtime. Drizzle catches column name errors at compile time while staying close enough to SQL that there are no surprises. It also works synchronously with `better-sqlite3`, unlike some ORMs that force async.

**Stability:** 8k+ GitHub stars. Drizzle Team is a dedicated company. Regular releases. Pre-1.0 versioning means breaking changes are possible between minor versions — check the changelog on upgrade.

**Security:**

- **CVE-2026-39356** (High) — SQL Injection via improperly escaped SQL identifiers in `.as()` and `sql.identifier()`. Affected versions below 0.45.2.
- **The installed version (0.45.2) is the patch release for this CVE — it is safe.**
- The vulnerability required using `.as(userInput)` or `sql.identifier(userInput)` with untrusted data. In this app, identifiers are never derived from user input, so even unpatched versions would not have been exploitable here. Still, staying on 0.45.2+ is correct.

**Performance:** Drizzle adds negligible overhead — it compiles query builder calls to SQL strings at runtime, and that compilation is fast (~0.1ms). Query execution time is entirely determined by SQLite. Benchmarks show Drizzle at 95–99% of raw SQL performance.

**Cons / risks:**
- Pre-1.0: API has changed between minor versions. Pin exact versions when deploying.
- `drizzle-kit` (the migration CLI, a dev dependency) has its own vulnerability in its dependency chain — covered below.
- Smaller community than Prisma; fewer StackOverflow answers.

**Alternatives:**
| Alternative | Trade-off |
|---|---|
| Prisma | More mature, much larger community, but slower (query engine runs in Rust subprocess), poor SQLite support historically |
| Knex.js | Query builder (not ORM), less type safety, more manual |
| TypeORM | Heavier, decorator-based, more overhead |
| Raw SQL + `better-sqlite3` | Maximum control, loses type safety on queries |

---

### `swr` — 2.4.1

**What it does:** Data fetching library for React. Used in the Watchlist widget and TransactionTable to fetch from API routes, deduplicate requests, cache results, and auto-refresh prices on an interval (`refreshInterval: 60_000`).

**Why this project uses it:** The Stale-While-Revalidate pattern is ideal for a portfolio dashboard — show cached data immediately, update in the background. Without SWR, every component navigation would show a spinner while refetching data the user just saw. The `mutate()` function also provides a clean way to invalidate cache after creating/editing a transaction.

**Stability:** 32k+ GitHub stars. Vercel-backed. Actively maintained.

**Security:** No CVEs. No external dependencies. Very low attack surface for a pure client-side caching library.

**Performance:**
- Request deduplication: if two components on the same page call `useSWR("/api/holdings", ...)`, only one HTTP request is made.
- Stale cache: data loads instantly from cache while the background revalidation runs silently.
- The `refreshInterval: 60_000` on prices means Yahoo Finance is polled at most once per minute per browser tab, which, combined with the 15-minute price cache in `app/api/prices/route.ts`, means Yahoo Finance is hit at most 4 times per hour.

**Cons / risks:**
- Less powerful than TanStack Query (no query invalidation by key pattern, no optimistic updates built-in).
- Manual cache invalidation with `mutate()` can be error-prone across many components.
- No built-in pagination or infinite scroll support.

**Alternatives:**
| Alternative | Trade-off |
|---|---|
| TanStack Query (React Query) | More features (key-based invalidation, `onSuccess`, mutations), heavier (~13KB vs ~4KB) |
| Apollo Client | GraphQL-first, not relevant here |
| RTK Query | Redux ecosystem, significant extra weight |
| `fetch` + `useEffect` | Fine for simple cases, but no deduplication or background refresh |

---

### `react-hook-form` — 7.76.1

**What it does:** Form state management library. Used in `TransactionForm` to track field values, trigger validation, and submit. Works with uncontrolled inputs (the DOM holds field values, not React state), which avoids re-rendering on every keystroke.

**Why this project uses it:** Forms with many conditional fields (shares only for buy/sell, tax only for dividend) benefit from a proper form library. React Hook Form's `watch()` lets the form react to the `type` field change and show/hide fields without managing many `useState` variables.

**Stability:** 12k+ GitHub stars. Actively maintained. ~49M weekly downloads — one of the most-used React libraries.

**Security:** No CVEs in current versions. Older versions (pre-7.53.x) had a prototype pollution issue — fixed. The current version is clean.

**Performance:** The uncontrolled input approach means the component does not re-render on every keystroke. For a 9-field form this makes no visible difference, but it is a good architectural default.

**Cons / risks:**
- The resolver pattern (connecting to Zod via `@hookform/resolvers`) adds an extra abstraction layer that can be confusing when debugging type errors — as seen during P3 development where `z.default()` and the resolver's generic types conflicted.
- Documentation examples sometimes use the `Form` shadcn component (from Radix-based shadcn), which does not exist in this project's Base UI-based shadcn setup.

**Alternatives:**
| Alternative | Trade-off |
|---|---|
| Formik | Older, heavier, controlled inputs (re-renders on keystroke), but more documentation |
| React Final Form | Simpler API, smaller community |
| Native `<form>` + Server Actions | Next.js 16 approach for server-side forms, but requires restructuring |

---

### `zod` — 4.4.3

**What it does:** Schema definition and runtime validation library. Used in `lib/validations.ts` to define the transaction shape, validate API request bodies (`transactionSchema.safeParse(body)`), and generate TypeScript types (`TransactionInput`).

**Why this project uses it:** Zod bridges the gap between TypeScript's compile-time types and runtime validation. Without it, the API route would need manual `typeof` checks, and the form would not know which fields are required. One schema serves both purposes.

**Stability:** 42k+ GitHub stars. ~145M weekly downloads. Industry standard.

**Security:** No CVEs. No external dependencies.

**Performance:** Validation runs once on form submit and once in the API route — total overhead is under 1ms for a 9-field object. Negligible.

**Note on Zod v4:** This project uses Zod v4 (released early 2026), which has a slightly different internal structure than v3. The main visible change is the `z.infer` vs `z.input` distinction — `z.infer` gives the output type (after `.default()` transforms), `z.input` gives the input type (what the form receives). This is why `.default()` was removed from the schema in P3 and defaults are handled separately in the API and form's `defaultValues`.

**Alternatives:**
| Alternative | Trade-off |
|---|---|
| Valibot | Smaller bundle (~2KB vs ~8KB), similar API, smaller ecosystem |
| Yup | Older, async-first, larger bundle, fewer TypeScript features |
| io-ts | Functional programming style, complex API, not beginner-friendly |

---

### `@hookform/resolvers` — 5.4.0

**What it does:** Adapter that connects validation libraries (Zod, Yup, etc.) to `react-hook-form`. Used as `resolver: zodResolver(transactionSchema)` in `useForm`.

**Why this project uses it:** Without this, form validation and API validation would use different code. The resolver runs the Zod schema on form submit and maps errors back to field names so the UI can display them inline.

**Stability:** 3k+ GitHub stars. ~5M weekly downloads. Stable.

**Security:** No CVEs. No independent dependencies.

**Version note:** v5 (installed) is required for Zod v4 compatibility. Earlier resolver versions do not understand Zod v4's changed internals.

---

### `@base-ui/react` — 1.5.0

**What it does:** Unstyled, accessible UI primitives from the MUI team. Provides the underlying behavior (keyboard navigation, ARIA attributes, focus management) for the Select, Dialog, and Sheet components generated by `npx shadcn`. The actual visual styling is done by Tailwind classes in the generated component files.

**Why this project uses it:** When `npx shadcn` generates components in this project, it uses Base UI as its primitive layer instead of Radix UI. This is because the project was initialized with the `base-nova` style, which targets Base UI.

**Stability:** The package is in active development by a well-funded team (MUI). However, it is newer than Radix UI and has a smaller community and less documentation. The API is subject to change between minor versions. The `onValueChange` callback signature `(value: string | null, eventDetails: ...) => void` differs from Radix's `(value: string) => void`, which caused type errors during P3 development.

**Security:** No CVEs.

**Performance:** Headless primitives add minimal overhead — they manage ARIA and focus state, both of which are DOM operations handled by the browser.

**Cons / risks:**
- Smaller community than Radix UI — fewer answers when debugging.
- The different API from Radix UI means shadcn tutorials and examples online may not match what the generated components expose. Expect to read Base UI docs, not Radix docs.
- Still pre-1.0 in spirit despite the 1.x version number.

**Alternatives:**
| Alternative | Trade-off |
|---|---|
| Radix UI | More mature, larger community, used by most shadcn tutorials online |
| Headless UI (Tailwind Labs) | Simpler, fewer components |
| React Aria (Adobe) | Best-in-class accessibility, more complex API |

---

### `lucide-react` — 1.16.0

**What it does:** SVG icon set as React components. Used for `Plus`, `Pencil`, `Trash2` icons in the transaction table and form.

**Why this project uses it:** shadcn uses Lucide as its default icon library. It is a natural pairing.

**Stability:** 8k+ GitHub stars. ~18M weekly downloads. Actively maintained with 100+ contributors.

**Security:** No CVEs. No external dependencies.

**Performance:** Icons are individual named exports, so bundlers tree-shake unused icons. Each icon is ~200 bytes gzipped. The entire library is never bundled — only the three icons imported are included.

**Alternatives:**
| Alternative | Trade-off |
|---|---|
| Heroicons | Cleaner Apple-like design, fewer icons |
| React Icons | Includes multiple packs (FA, Material, etc.) but larger bundle if not tree-shaken carefully |
| Phosphor Icons | More icon variants (thin/bold/duotone), similar size |

---

### `shadcn` — 4.8.0

**What it does:** A CLI tool (`npx shadcn add button`) that copies component source code into `components/ui/`. The generated files use `@base-ui/react` primitives styled with Tailwind.

**Why this project uses it:** Provides production-ready, accessible components without locking into a component library's design decisions — since the source is copied into the project, it can be modified freely.

**Stability:** The most starred UI component project on GitHub (63k+). Actively maintained.

**Security:** No CVEs.

**Critical issue — wrong dependency type:**

`shadcn` is listed in `dependencies` (runtime) instead of `devDependencies`. This is an antipattern. The `shadcn` package is a CLI tool — it is only ever run with `npx shadcn add ...` to generate component files. It should never be imported by application code, and it does not need to be present at runtime.

Having it in `dependencies` pulls 241+ transitive packages into the production node_modules, increasing the install size by hundreds of MB and unnecessarily expanding the attack surface.

**Fix:**

```bash
npm uninstall shadcn
npm install --save-dev shadcn
```

Nothing else changes — `npx shadcn add <component>` works the same either way.

---

### `tailwind-merge` — 3.6.0

**What it does:** Resolves conflicting Tailwind class names. For example, `cn("p-4", "p-6")` correctly produces `"p-6"` instead of `"p-4 p-6"` (which would have browser-dependent behavior). Used via the `cn()` utility in `lib/utils.ts`.

**Why this project uses it:** Essential when composing components that accept `className` overrides. Without it, passing `className="mt-8"` to a component that already has `className="mt-4"` would produce undefined behavior depending on CSS specificity.

**Stability:** 1.8k stars, ~64M weekly downloads (used by shadcn so pulled in everywhere). Actively maintained.

**Security:** No CVEs. Note: a separate malicious package `tailwind-merge-setting` existed briefly on npm — this project uses `tailwind-merge`, not that package.

---

### `clsx` — 2.1.1

**What it does:** Utility for conditionally joining class name strings. Used inside `cn()` alongside `tailwind-merge`.

**Why this project uses it:** Required by the `cn()` function in `lib/utils.ts` which is the standard shadcn utility pattern.

**Stability:** 8k stars. ~87M weekly downloads. Last release ~1 year ago — dormant but stable. At 239 bytes gzipped, this is unlikely to need updates.

**Security:** No CVEs. No dependencies.

---

### `class-variance-authority` — 0.7.1

**What it does:** Utility for defining CSS class variants with TypeScript types. Used by shadcn's generated button and badge components to define `variant` and `size` props cleanly.

**Why this project uses it:** Generated automatically when shadcn components are added.

**Stability:** Dormant — no releases in over a year. The codebase is small and stable; there are no open bugs that would affect usage. However, if a bug were found, a fix timeline is uncertain.

**Security:** No CVEs. No dependencies.

**Action:** No immediate action needed. If `tailwind-variants` gains shadcn support officially, migration would be straightforward.

---

### `tw-animate-css` — 1.4.0

**What it does:** Provides Tailwind utility classes for CSS animations (fade-in, slide-in, zoom-out, etc.) used by shadcn's dialog and popover enter/exit transitions.

**Why this project uses it:** Added by shadcn initialization for the `base-nova` style. The Dialog and Sheet components use classes like `data-open:animate-in data-open:fade-in-0`.

**Stability:** Small package, infrequently updated, but stable. No breaking changes expected.

**Security:** No CVEs. No dependencies.

**Alternatives:** Framer Motion (JS-based, more control, much heavier) or custom CSS `@keyframes`.

---

### `yahoo-finance2` — 3.14.1

**What it does:** Fetches stock quotes, company names, and other financial data from Yahoo Finance's unofficial API. Used in `lib/yahoo.ts` for live prices displayed in the Watchlist and cached in `price_cache`.

**Why this project uses it:** No API key needed, covers most global exchanges, and returns enough data (price, currency, company name) for the current feature set.

**Stability:** 3.5k stars. ~350k weekly downloads. Actively maintained community project.

**Security:** No CVEs in the library itself. The dependency `node-fetch` should be kept current.

**The core risk is not a security issue — it is reliability:**

Yahoo Finance's API is unofficial and undocumented. Yahoo has broken it before (2022, 2024) without warning. When it breaks, all price data in the app becomes unavailable until either Yahoo fixes it or the library ships a workaround. This is not a hypothetical — it has happened.

The app already handles this gracefully: `lib/yahoo.ts` wraps calls in `try/catch` and returns `null` prices, which the Watchlist displays as `"—"`. The price cache means a brief API outage shows stale data rather than errors.

**For a personal portfolio tracker the risk is acceptable.** If this were production software, an official API would be required.

**Alternatives:**
| Alternative | Trade-off |
|---|---|
| Alpha Vantage | Free tier (25 calls/day), official API, key required |
| Polygon.io | Official, comprehensive, paid ($29+/month) |
| Finnhub | Free tier (60 calls/min), official, key required |
| IEX Cloud | Official, generous free tier, key required |

---

## Dev Dependencies

---

### `tailwindcss` — 4.x + `@tailwindcss/postcss` — 4.x

**What it does:** CSS framework. Tailwind v4 (a major rewrite) generates utility classes by scanning source files. `@tailwindcss/postcss` is the PostCSS plugin that integrates it with the Next.js build.

**Why this project uses it:** Utility-first CSS eliminates the context-switching between CSS files and component files. v4 is the current major version.

**Stability:** 85k+ GitHub stars. Production-ready. v4 introduced a CSS-first configuration approach (no `tailwind.config.ts` required in v4 projects).

**Security:** No CVEs in v4. A past CVE (CVE-2021-23382) in older PostCSS versions is long fixed.

**Note:** Tailwind v4 broke a number of v3 plugins and configurations. If adding third-party Tailwind plugins, verify they support v4.

---

### `drizzle-kit` — 0.31.10

**What it does:** CLI companion to `drizzle-orm`. Generates SQL migration files from schema changes and applies them. Used via `npx drizzle-kit` — never imported at runtime.

**Stability:** Tied to `drizzle-orm` releases. Actively maintained.

**Security — dependency chain issue:**

`drizzle-kit` depends on `esbuild` at a version that includes:
- **CVE-2025-22871** — HTTP request smuggling in esbuild's development server.

This CVE is in `esbuild`'s HTTP server, not in the bundling logic. `drizzle-kit` uses esbuild only for bundling, not as a development HTTP server, so the CVE is not directly exploitable through `drizzle-kit`. However, npm audit will flag it.

`drizzle-kit` also has a dependency on `@esbuild-kit/esm-loader` which is deprecated.

**Risk: Low** (build-time only, not shipped to production). **Watch** the Drizzle releases for an updated esbuild dependency.

---

### `eslint` — 9.x + `eslint-config-next` — 16.2.6

Standard linting. No CVEs relevant to usage. `eslint-config-next` should stay in sync with the `next` version (both are 16.2.6 here — correct).

---

### `typescript` — 5.x

**What it does:** TypeScript compiler. Provides type checking across the entire codebase. Version 5.x (latest stable).

**Security:** No CVEs.

**Note:** The `tsconfig.json` should have `"strict": true` enabled. Strict mode catches a class of bugs (null checks, implicit any) that non-strict mode misses.

---

### `@types/*` packages

`@types/better-sqlite3`, `@types/node`, `@types/react`, `@types/react-dom` — TypeScript definition packages. Zero runtime impact. No CVEs.

---

## Recommended Actions

### Immediate (5 minutes)

**Move `shadcn` to devDependencies:**
```bash
npm uninstall shadcn
npm install --save-dev shadcn
```
This removes ~241 transitive packages from the production dependency tree.

### Short-term (next upgrade cycle)

**Watch for `drizzle-kit` update** fixing the esbuild CVE-2025-22871 dependency. Run `npm audit` before each deployment to check. No action needed until an updated version ships.

### Long-term (if app grows beyond personal use)

**Replace `yahoo-finance2` with an official financial API.** For a personal app the unofficial API is fine. If the app is ever shared or deployed publicly, reliability and terms-of-service compliance require an official source with an API key.

**Consider migrating `class-variance-authority` to `tailwind-variants`** if the former shows signs of bugs — `tailwind-variants` is the actively maintained successor with a compatible API.
