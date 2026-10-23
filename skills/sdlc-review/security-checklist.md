# Security checklist — OWASP coverage map

The one security reference for the PR Watchdog. Referenced by `review/SKILL.md` Phase 1
step 9 — do not duplicate this content into a skill.

Taken from Monorepo `shared/security-checklist.md`, which its authors flagged as an
enhancement that should travel back to Delivery-API. Its framing rules are kept because they
are better than the Delivery-API original: coverage-not-scorecard, attack-story evidence,
framework-mitigation filtering, and zero-findings-is-a-pass. The strict/legacy severity table
below is kept from the Delivery-API version, because Delivery-API has module modes and the
Monorepo does not.

**Editions**: OWASP Top 10 — 2021. OWASP Top 10 for LLM Applications — 2025. A newer web edition exists that reorders and merges categories (promoting supply-chain risk, adding mishandling of exceptional conditions) — verify against owasp.org before migrating; do not renumber from memory.

## How to use this file

**A coverage map, not a scorecard.** Its job is to stop a category from going *unexamined* — not to produce a finding per category. The reporting rules in `flow-security-check` are unchanged and win on conflict:

- **Every finding is an attack story with a concrete `file:line` and a traceable exploitation path.** No path, no finding.
- **Filter framework-mitigated non-issues.** Prisma parameterizes ordinary queries; an existing Nest guard covers its route; a `ValidationPipe` already validates. A covered category is silently clean.
- **Zero findings is a valid pass.** Never pad the report to demonstrate coverage; never emit a per-category table of "clean" rows.
- Report only what the diff introduces or makes newly reachable. Pre-existing debt the diff doesn't touch is out of scope — cite it as `Low` only if the diff makes it exploitable.

**Severity by module mode** — Delivery-API-specific, and it overrides the generic scale below:

| Situation | Severity |
|---|---|
| Finding in code **the diff introduces** | **Critical** → verdict `Blocked` |
| Finding in **pre-existing** code, legacy module | Warning — cite `file:line`, do not block |
| Finding in **pre-existing** code, strict module | Critical → `Blocked` |
| Baseline failure on new code | Critical |
| LLM section, no AI code in the diff | N/A — omit, no impact |

**Key rule**: unlike the architectural checks, security findings on NEW code are Critical in
**both** strict and legacy mode. Legacy mode buys leniency on pre-existing security debt,
never on newly written code.

**Generic scale**, for anything the table above does not settle: **Critical** (exploitable today by an outsider — data breach, financial loss, account compromise) · **High** (same impact, needs authentication or a contingency) · **Medium** (contained blast radius, genuine risk) · **Low** (hardening). The orchestrator routes Critical/High back to write-code and blocks the PR; Medium/Low are recorded as follow-ups. The sweep never fixes and never blocks on its own.

Cite the category ID with each finding (e.g. `A03 Injection`, `LLM05 Improper Output Handling`) so repeat weak spots stay visible across tickets.

---

## Part 1 — Baseline (always)

Repo rules on the same surfaces — not OWASP categories, checked first:

- Input validation on new endpoints — `class-validator` DTOs with `ValidationPipe` actually applied
- No hardcoded secrets, API keys, connection strings, or tokens in shipped code
- Parameterized queries — audit every `$queryRaw` / `$executeRaw`; `$queryRawUnsafe` / `$executeRawUnsafe` carrying interpolated input is Critical
- Auth guards on new endpoints — no route accidentally public
- No PII in logs, Sentry breadcrumbs, or error messages (addresses, phone numbers, emails, payment data, driver/customer names)
- Migrations compliant with `.claude/rules/migrations.md` — a table lock on a high-volume table is an availability incident

---

## Part 2 — OWASP Top 10 (2021)

### A01 Broken Access Control
- Object-level authorization: an ID from the JWT compared against the resource's owner before read or write — "is authenticated" is not authorization
- IDOR: route params (`:deliveryId`, `:jobId`, `:restaurantLocationId`) scoped to the caller's tenant **in the repository query**, not filtered after fetch
- No client-supplied `merchantId`/`accountId` in a body used as the authorization scope
- Admin-only operations check role, not merely presence of a token
- LaunchDarkly flags are not an access-control mechanism — they gate features, not permissions

### A02 Cryptographic Failures
- No sensitive data at rest in plaintext columns (tokens, secrets, bank details)
- TLS enforced outbound — no `rejectUnauthorized: false`, no `http://` to internal services
- No custom crypto; no `Math.random()` for tokens or IDs — use `crypto.randomUUID()` / `crypto.randomBytes`
- No secrets or PII in URL query strings (they land in access logs)

### A03 Injection
- SQL — `$queryRawUnsafe`, `$executeRawUnsafe`, template-literal-built SQL carrying user input
- Prisma operator injection — a `where` clause built by spreading an unvalidated `req.query` / `req.body`
- Command injection — user input reaching `exec` / `execSync` or a shell string
- Log injection — unsanitized newlines from user input into log messages
- Rendered output (emails, templates) escapes user-supplied values

### A04 Insecure Design
- Business-logic limits enforced server-side: quantities, gratuity/fee ranges, order totals, refund amounts — never trusted from the client
- State-machine transitions validated (a delivery can't jump to `DELIVERED` from an arbitrary state)
- Idempotency on money-moving and dispatch operations — a replayed SQS message or retried request must not double-charge or double-dispatch
- Abuse cases considered, not just the happy path: what does a hostile merchant or driver do with this endpoint?

### A05 Security Misconfiguration
- CORS not `origin: '*'` on authenticated routes
- Stack traces and Prisma error details not returned to clients — errors mapped to safe HTTP exceptions
- `ValidationPipe` uses `whitelist: true` / `forbidNonWhitelisted` so unexpected fields can't mass-assign
- No debug endpoints, seed routes, or test bypasses reachable in deployed environments
- Lambda IAM policy scoped to what the handler needs — no wildcard resources

### A06 Vulnerable and Outdated Components
- A new dependency is justified, actively maintained, and not a typosquat of a known package
- `package-lock.json` committed with the change; no lockfile drift
- No `--force` / `--legacy-peer-deps` workaround hiding a vulnerable transitive dep

### A07 Identification and Authentication Failures
- Token/JWT validation covers signature, expiry, issuer, and audience — not just decode
- No auth bypass path (`if (process.env.NODE_ENV !== 'production')` style skips)
- Token lifetime bounded; a refresh flow can't extend indefinitely
- Brute-force protection on login/OTP-style endpoints
- Service-to-service calls authenticate — an internal URL from `ServiceRegistryService` is not a trust boundary on its own

### A08 Software and Data Integrity Failures
- Inbound webhooks (partner/POS callbacks) verify signature or shared secret **before** acting on the payload
- No deserialization of untrusted input into executable structures; no `eval`, no dynamic `require` from input
- Integration payloads validated against a DTO, not spread into a Prisma write
- CI/deploy config changes reviewed — the pipeline is a supply-chain surface

### A09 Security Logging and Monitoring Failures
- Auth failures, authorization denials, and privilege-relevant actions logged with entity IDs
- Mutations of financial or delivery-state data leave an audit trail
- No silently swallowed `catch {}` on a security-relevant path
- Logs structured via PinoLogger and free of PII (Part 1)

### A10 Server-Side Request Forgery (SSRF)
- No outbound HTTP to a URL derived from user input without an allowlist
- Merchant-supplied webhook/callback URLs validated against an allowlist and blocked from internal ranges — `169.254.169.254`, `127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `.internal`
- Redirects not followed blindly to a user-controlled host
- Fetch-by-URL features constrained by scheme and host

---

## Part 3 — OWASP Top 10 for LLM Applications (2025)

### Applicability gate — check first

Phase 1's attack-surface map already covers AI features. Scan the diff for:

- Packages — `@anthropic-ai/*`, `openai`, `@aws-sdk/client-bedrock*`, `langchain`, `@ai-sdk/*`, `llamaindex`, `@modelcontextprotocol/*`
- Concepts — prompt construction or templates, chat/completion/embedding calls, vector stores or similarity search, tool/function definitions exposed to a model, agent loops, RAG retrieval, MCP servers or clients, model output driving a side effect
- Config — model IDs, model-provider API keys, prompt files

**None present** → one line under "Attack surface reviewed": `AI/LLM: none in diff`. Skip the rest of Part 3.

**Any present** → work every item below. There is no LLM SDK usage in `apps/` or `libs/` today, so the first change introducing one warrants a design conversation, not just a sweep — say so in the report.

### LLM01 Prompt Injection
- Untrusted content (merchant notes, customer instructions, driver messages, scraped pages, tool results, file contents) delimited and labeled as data, never concatenated into the instruction region
- The system prompt states that instructions found inside retrieved or user content are not to be followed
- Indirect injection considered — any document, DB field, or API response the model reads is an attack vector
- High-impact actions require a deterministic check or human confirmation, not the model's say-so

### LLM02 Sensitive Information Disclosure
- No PII, payment data, credentials, or full DB rows sent to a model provider unless required and justified
- Provider data-retention/training terms reviewed for the data being sent
- Responses can't leak across tenants via a shared cache or shared vector index
- Prompts and completions excluded from logs, or redacted, when they can carry PII

### LLM03 Supply Chain
- Model IDs, provider SDKs, and prompt templates pinned and version-controlled — no floating "latest" on a path affecting money or dispatch
- Third-party MCP servers, plugins, and agent tools vetted before being connected; each is remote influence on the agent
- Model artifacts come from a trusted source with integrity verification

### LLM04 Data and Model Poisoning
- Data entering a vector store or fine-tuning set has trusted provenance and is validated on ingest
- User-generated content cannot silently enter a retrieval index other tenants query
- Feedback signals (thumbs up/down, corrections) can't steer behavior for other users

### LLM05 Improper Output Handling
- Model output validated against a schema before use — never trusted as well-formed
- Model-generated SQL, shell commands, code, file paths, or URLs never executed or fetched directly; treat output as untrusted input for every downstream sink (A03 and A10 apply in full)
- Output rendered in a UI or email is escaped (XSS)
- Output driving a state change passes the same authorization checks a human request would

### LLM06 Excessive Agency
- Tools exposed to the model are the minimum needed; no general-purpose escape hatch (raw SQL, arbitrary HTTP, shell)
- Each tool's permissions scoped — the agent's DB credential is not the app's full-access credential
- Irreversible or money-moving actions (dispatch, refund, payout, cancel, delete) require human approval or a deterministic guard outside the model
- Blast radius bounded — per-run caps on tool calls, spend, and records touched

### LLM07 System Prompt Leakage
- System prompts contain no secrets, keys, connection strings, or internal URLs — assume the prompt is public
- Security never depends on the prompt staying hidden; authorization is enforced in code
- Prompts not returned in API responses or error payloads

### LLM08 Vector and Embedding Weaknesses
- Retrieval filtered by tenant/permission **in the query**, not after the fact — a shared index without a tenant filter leaks across merchants
- Embedded content is untrusted data on retrieval (see LLM01)
- Vector-store access authenticated and scoped
- Deleted source records removed from the index (erasure and stale-data correctness)

### LLM09 Misinformation
- Output presented as fact or written to the DB is verified against an authoritative source, or labeled as generated
- No decision with financial, legal, or safety impact rests on unverified model output
- Failure mode is safe — uncertain output escalates rather than committing a guess

### LLM10 Unbounded Consumption
- Timeouts, token caps, and max retries on every model call
- Rate limiting per caller/tenant on any endpoint that triggers inference
- Agent loops have an iteration ceiling and a cost/token budget with a hard stop
- Cost and latency observable — spend spikes alert rather than surprise
