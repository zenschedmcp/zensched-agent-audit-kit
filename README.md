# ZenSched Agent-Audit Reference Kit

A copy-pasteable setup for a small mobile-money agent-network audit shop (an owner plus one to three dispatchers and a pool of independent-contractor field auditors) working for telcos, MMOs, and banks in Kenya, Tanzania, Bangladesh, Pakistan, Nigeria, and similar markets. The AI assistant runs shop-visit dispatch, GPS-verified Audit Records (float count, branding, KYC-poster and shopfront photos), auditor pay reconciliation, and telco billing. ZenSched handles the live schedule, the auditor's phone app, GPS check-ins at the shop, the Audit Record form, and every submission. A small local database on your computer holds your clients, programs, the agent-shop list (including till numbers and real names), the auditor pool, each visit's status and result, QA decisions, invoices, and pay runs.

**You do not need to know how to program or write SQL to use this.** You type plain English to your AI assistant ("set up the PesaNet wave from this list", "give Amina the Nairobi shops next week", "pull this week's results", "invoice PesaNet", "run auditor pay") and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

## What this kit is not — read this first

**What it is:** GPS-verified proof that an auditor stood at the shop, inside the assigned window, for a plausible length of time, counted the visible float, marked branding, and photographed the KYC poster and shopfront — and a way to turn those proofs into telco invoices and auditor pay with an AI doing the clerical work.

**What it is not:**

- **Not a telco or central-bank official KYC / AML / CICO record.** The Audit Record is an internal stop record. It is not a CBK, Bank of Tanzania, Bangladesh Bank, SBP, or CBN filing, not the principal's AML procedures file, and not a cash-in / cash-out ledger. Photographing a poster is not certifying a customer and not a CDD file. Do not tell an examiner "it's in ZenSched." There is no signature field on purpose: on ZenSched a signature replaces the Submit button, and submitting this form must not look like anyone signed a legal document.
- **Not a float-reconciliation or settlement system.** `float_count` is what the auditor typed. It is not a wallet-balance pull, not a till close, and not a cash-in / cash-out ledger.
- **Not a client portal or auditor marketplace.** Clients never log in. You bring the people; the kit tracks their reliability locally.
- **Agent names and till numbers never leave your computer.** ZenSched only ever sees a de-identified shop label (`Stop 12 - Ngong Rd`) and the street address. The AI is forbidden from putting a till number, an agent name, or a wallet ID into any ZenSched field.

If you need a signed KYC attestation, a central-bank return, a live wallet API, or a telco login portal, this kit is not for you. If you need enforceable proof-of-visit for a few dozen shop audits a month and an assistant that keeps the books, read on.

## What lives where

**ZenSched (source of truth for what happened, when, and where):**

- Locations (shops with GPS coordinates; the check-in radius is a **policy** setting)
- Workers (auditors with the mobile app)
- Events (one per shop per program wave, at most 60 days)
- Shifts (each assigned visit: one auditor, one shop, one time slot, with a push notification)
- GPS punches (check-in / check-out with distance-from-the-shop verification)
- The Audit Record form (float count, branding Yes/No/Partial, KYC poster max 2, shopfront max 1) and every submission
- Timesheets (rarely needed here; auditors are paid per visit)

**Local SQLite database (`agent-audit.db`, on your computer):**

- Clients: telcos / MMOs / banks — contact, billing email, payment terms
- Programs: wave dates, daily window, allowed weekdays, quota per shop, client fee, auditor fee, minimum minutes, the brief, which ZenSched form
- Agents: the client's shop list with a normalized address so each shop is geocoded once, its own time zone, its real name and till number (**local only**), and its de-identified `zensched_label`
- Program × agent rows with the ZenSched event for that wave
- Auditors: contact, home city, pay handle, ZenSched worker id
- Visits: one row per shop visit, open → assigned → completed / no-show / rejected / cancelled, with the check-in and check-out stamps, duration, float, branding, photo URLs, QA status and notes, invoiced and paid flags
- Client invoices and auditor payouts
- Your settings (default time zone, default visit length, invoice prefix and terms, Audit Record form id)

**Never duplicated:** the live schedule, punches, and the original submissions and photos stay in ZenSched. The local database stores *references* to them plus the handful of values billing and QA need.

### Privacy note

Agent names, till numbers, agent IDs, MSISDNs, and wallet IDs are stored only in `agents.agent_name` and `agents.agent_code` in the local database. `SKILL.md` forbids the AI from putting them into any ZenSched field. The only name that crosses is `agents.zensched_label` (`Stop 12 - Ngong Rd`). Auditors see the label, the time slot, and the form. Clients get label-and-date results, never auditor names. Give a till-number list to an auditor yourself, by whatever channel you trust, only if they actually need it — they do not need it to fill the form.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `event_create`, `form_create`, `shift_create`, `shift_list`, `shift_status`, `form_export`, `policy_update`, `brand_create`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `agent-audit.db` on your computer.

When a telco sends an agent list, you paste it. The AI creates the client and program locally, adds each shop to the agent cache (geocoding only the ones it has never seen, labelled `Stop {id} - {street}`), attaches the Audit Record to one ≤60-day event per shop, and generates the open visits from the quota. You say "give Amina the Nairobi shops next week, morning window" and the AI picks dates inside the allowed weekdays and window, creates one shift per visit, and confirms. Amina sees the visits in the app, checks in at the shop (GPS-verified), counts the float, photographs the KYC poster and shopfront, marks branding, and checks out. Later you say "pull results" and the AI matches completed shifts to visits, records the punch times and the form summary, and leads with anything suspicious: a check-in 40 minutes after the slot, a 4-minute "visit", branding Partial, a form with no check-in at all. You approve or reject; approved visits flow to the telco invoice and the auditor pay sheet. You never run SQL yourself. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

A typical visit costs about **$0.35** on ZenSched: GPS in $0.10 + GPS out $0.10 + reading an Audit Record that has photos $0.15. Geocoding a new shop is $0.03 once. The AI states the cost before it spends.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\agent-audit`
- Mac: `/Users/yourname/agent-audit`

The database file will be created automatically inside this folder the first time the AI uses it. It will hold till numbers, agent names, and auditor pay details; keep it backed up.

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\agent-audit.db` (Windows) or `/agent-audit.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "agent-audit-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/agent-audit/agent-audit.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\agent-audit\\agent-audit.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My Agent Audit Co" (use my real business name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my agent-audit database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run the statements one at a time and confirm the tables exist. The `agent-audit.db` file now exists in your folder with default settings (East Africa time `+03:00`, 20-minute visits, net-30 invoices) you can change.

If you happen to have the `sqlite3` command-line tool, `sqlite3 agent-audit.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> We're Riftline Audits in Nairobi, Kenya, East Africa time. Save that in settings, set the check-in radius to 75 m, give auditors a 30-minute reminder, and set up the Audit Record form.

It writes those to the `settings` table, sets the check-in policy on ZenSched (free), and creates the Audit Record form once (free): float count, branding Yes/No/Partial, KYC poster (max 2), shopfront (max 1). No signature. It stores the form id so every shop visit gets it automatically.

**Check-in radius.** The default pin uses `checkin_radius_m=75` on `location_create`, but ZenSched **enforces** the radius through the account's policy, not per shop. With geofencing on it raises anything under 100 m to about 91 m (300 ft), so 75 behaves as roughly a kiosk-and-veranda circle. For a market stall, a petrol-station shop, or a pin that lands on the road, ask the AI to "set the check-in radius to 150 m" (`policy_update`) or to move the pin onto the building (`location_update`, free). Do not ask it to widen the radius "on that location" — that field is informational only. `remote_checkin` turns GPS verification off for **every** program on that policy and should not be flipped on policy 0; see Troubleshooting and the brand/policy recipe in `SKILL.md` if you also run phone audits.

**Reminders.** A `checkin_reminder_min_before` of 30 cuts no-shows. `checkout_reminder_min_after` (0–60) catches auditors who forget to check out.

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Some things are metered: creating a shop location (geocoding, $0.03, once per shop ever), inviting an auditor ($0.25), each GPS-verified check-in or check-out ($0.10), and reading a submission ($0.05, or $0.15 when it has a photo; each submission is billed once, ever, so a later CSV export for the telco is free). Creating forms, events, and shifts, and listing them, is free. When a metered call happens without funds, the AI gets a `payment_required` response and tells you how to add the $5 activation deposit, which is credited to your balance. You will not be charged without seeing this first.

Per completed visit that is about **$0.35** (two punches and one form read with photos), plus $0.03 for each shop you have never visited before. A 40-visit wave across 12 new shops is about $14.36; the AI states the cost before it spends.

## Using it

Everything after setup is plain English. Examples:

- "New program. Client is PesaNet, contact Wanjiku Mwangi. Weekday shop audits, one per agent, 8 to 6, Sep 8 through Sep 30, $8 per visit, auditors get $3. Agents: (paste the list)."
- "Invite Amina Yusuf, amina@example.com, Nairobi, M-Pesa 0712 555 014."
- "Give Amina the two Nairobi shops next week, morning window."
- "Fill the open visits." (the AI proposes auditor-to-shop matches by home city and reliability, and asks)
- "Pull this week's results."
- "Approve Amina's two. Reject Tunde, he checked in after the slot. Reopen it."
- "How's the PesaNet program doing?"
- "Send PesaNet their results and invoice."
- "Run auditor pay."
- "Who's my most reliable auditor?"
- "Move Amina's Ngong Road visit to Thursday 09:30."
- "Tunde can't do Wednesday, give it to someone else."
- "PesaNet paid INV-2026-0001."

See `QUICKSTART.md` for the first-wave walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### What "invoice" means here

"Invoice PesaNet" records the invoice in your database (number, date, due date from the client's payment terms, visit count, fees, which visits) and the AI writes out a plain-text invoice you can paste into an email, with a line per approved visit (date, shop **label**, fee, float, branding) and a note that every visit was GPS-verified with timestamped KYC-poster and shopfront photos. It does **not** generate a PDF, email it for you, or collect payment. Auditor names never appear on it. Till numbers appear only if you explicitly ask. When the client pays, tell the AI ("PesaNet paid INV-2026-0001") and it marks it paid.

### What "auditor pay" means here

"Run auditor pay" totals approved visits per auditor, records a payout row with the visit list, and writes a pay sheet with each auditor's pay handle (M-Pesa, bKash, JazzCash, bank nickname). You pay them outside the kit and say "paid". Rejected and no-show visits are not on the sheet; if you want to pay one anyway, say so. The kit does not handle taxes.

### What "results" means here

"Send PesaNet their results" runs `form_export` for the Audit Record and wave dates and gives you a CSV download link plus a summary from the local database (visits per label, float counts, branding breakdown, what was rejected). The CSV includes a `worker_name` column; the AI reminds you to remove it before it goes to the telco. If the telco wants till numbers on *their* report, the AI joins them locally from `agents.agent_code` — it does not put codes into ZenSched to get them back out.

## Mobile app for auditors

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [TestFlight](https://testflight.apple.com/join/Wp51m5Yq)

When you invite an auditor, they get an email, install the app, and can immediately see their assigned visits, check in and out with GPS verification, and fill in the Audit Record. The KYC-poster and shopfront photos are required; the form cannot be submitted without them. There is no signature step — they tap Submit. The brief is something you tell the auditor yourself; ZenSched shows them the shop **label**, the slot, and the form.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `agent-audit-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit |
| Lagos visit created at the wrong hour | Shop has the wrong `tz_offset` | "Set the Ikeja shop to West Africa time (+01:00)"; the AI fixes the shop and updates the shift |
| AI refuses a program longer than 60 days | Working as intended; ZenSched events are capped at 60 days | Ask for it as monthly waves; the AI creates one program row and one set of events per wave |
| Auditor's check-in not GPS-verified at a market stall | Auditor was outside the policy radius, or the pin is on the road | "Set the check-in radius to 150 m" (`policy_update`, account-wide), or "move the Stop 12 pin onto the kiosk" (`location_update`, free), or `location_refine` ($0.10). Do **not** ask for `remote_checkin` on policy 0: it turns GPS proof off for every in-shop program |
| You also run phone or desk audits | Those cannot have a GPS punch | Keep policy 0 geofenced for in-shop work; ask the AI to give phone programs their own brand and policy (`policy_create` → `brand_create(policy_id=…)` → `event_create(brand_id=…)`) rather than flipping `remote_checkin` account-wide |
| Auditor forgot to check out | Shift still `checked_in` | Tell the AI to use the form's submission time as check-out; ask for a check-out reminder (`checkout_reminder_min_after`) |
| Auditor does not see the Audit Record | Form not assigned to that shop's event | "Attach the Audit Record to Stop 12's event" (`form_assign`) |
| AI refuses to put a till number in ZenSched | Working as intended | Give it to the auditor directly if they need it |
| A visit is flagged but the telco is fine with it | Working as intended; flags are for you, not automatic rejections | Approve it and put the reason in the QA note |
| Same shop pasted twice in a list | Address written differently | The AI normalizes addresses; if it still created two shops, say "these are the same shop" and it merges them (one geocode is wasted, $0.03) |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |
| AI offers a signed KYC certificate, a wallet-balance pull, or a CBK / BOT / CBN filing | It shouldn't | This kit is not a telco or central-bank official KYC / AML record |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations (locations, events, shifts, punches, forms, submissions); SQLite is authoritative for the commercial model (clients, programs, fees, quotas, agent cache, auditor pool, visit lifecycle, QA, billing, payouts) and for **agent identity** (`agent_name`, `agent_code`); each side stores only the other's **integer** IDs plus the few per-visit values billing needs (`submission_dc_id`, punch stamps, `float_count`, `branding_ok`, photo URLs). The privacy boundary is enforced by data placement (`zensched_label` is the only name that crosses) and by `SKILL.md` rule 1.

**Data model decisions.**

- **Agents are a cache of places, not a per-program list.** `agents` is `UNIQUE (client_id, normalized_address)`; `SKILL.md` gives the normalization recipe. One `location_create(name=<zensched_label>, street_address=..., checkin_radius_m=<settings default>, idempotency_key="loc-agent-{agent_id}")` per shop, ever ($0.03), stored on `agents.zensched_location_id`. `checkin_radius_m` on `location_create` is informational; the enforced radius is `policy_update(0, '{"checkin_radius_m": N}')`, and with geofencing on the platform raises values under 100 m to 300 ft.
- **`zensched_label` is the only identifier ZenSched sees.** Format: `Stop {agent_id} - {short street}` (e.g. `Stop 12 - Ngong Rd`). `agent_name` and `agent_code` (till / agent ID / wallet ID) are local-only columns. Invoice `line_items` use the label. The owner-facing views still *select* name and code so the AI can tell the owner which shop it means.
- **Per-shop time zone.** `agents.tz_offset` is `CHECK`-constrained to `[+-]HH:MM`; `settings.timezone_offset` is only the default for new shops (`+03:00` for EAT). `visits.scheduled_start` / `scheduled_end` are shop-local wall-clock strings (`YYYY-MM-DDTHH:MM:SS`, `CHECK`-constrained to have no offset) and `visits_upcoming` builds `start_iso` / `end_iso` as `scheduled_start || tz_offset`. `checkin_at` / `checkout_at` carry an explicit offset, and every comparison against the slot uses `julianday(scheduled_x || tz_offset)`, so late-check-in detection is correct for a Lagos shop scheduled by a Nairobi agency.
- **One event per agent per wave.** `programs.wave_start` / `wave_end` are the event dates; a `CHECK` rejects `wave_end` more than 59 days after `wave_start`, which forces long engagements into one program row per wave (the kit's answer to the 60-day event cap; there is no rolling `event_needs_roll` machinery because a wave never outlives its events). `program_agents` (`UNIQUE (program_id, agent_id)`) holds `zensched_event_id` and `event_valid_until`; `event_create(location_id, title="{program} - {zensched_label}", start_date=wave_start, end_date=wave_end, idempotency_key="event-pa-{program_agent_id}-{YYYYMMDD}")`, then `form_assign(form_id, event_id=...)`. `visits_upcoming.needs_event` flips when the row has no event or `event_valid_until` is before the visit date; `needs_location` when the shop was never geocoded.
- **One Audit Record form for the account**, id on `settings.audit_record_form_id` and copied onto `programs.zensched_form_id`, created with `form_create(title, fields_json, idempotency_key="form-audit-record")`. The exact `fields_json` is in `SKILL.md` and `example-workflow.md` (byte-identical) and was validated against ZenSched's `_validate_fields`. Five fields: section `sec_audit`, number `float_count`, select `branding_ok` (`Yes` / `No` / `Partial` → keys `yes`, `no`, `partial`), photo `kyc_poster` `max_images` 2, photo `shopfront` `max_images` 1. Every field, including the section, carries an explicit `identifier`. **No `signature` field**: on ZenSched a signature replaces the Submit button.
- **Visit lifecycle.** `visits.status` is `open | assigned | completed | no_show | rejected | cancelled`; `qa_status` is `pending | approved | rejected`; `branding_ok` is `Yes | No | Partial`; all `CHECK`-constrained. `zensched_shift_id` is `UNIQUE`, and the rule is never to reuse a row that has one: no-shows, rejections, and cancellations keep their row (for `auditor_reliability`) and the agent inserts a fresh `open` row. `program_progress` therefore counts approved visits against `SUM(program_agents.visits_required)`, not against row counts.
- **Fraud flags are a view, not a status.** `visits_flagged` returns completed visits with `checkin_late`, `checkin_early`, `no_checkin`, `short_visit`, `branding_issue` (`branding_ok` is No or Partial), and `minutes_after_slot_end`. A flag is information for QA; the owner decides.
- `duration_minutes` is filled by two triggers (`AFTER INSERT`, `AFTER UPDATE OF checkin_at, checkout_at`) as `round((julianday(out) − julianday(in)) × 1440)` whenever it is NULL and both stamps exist; an explicit value is never overwritten.
- **Money.** `visits_to_invoice` groups approved, uninvoiced visits per client with `SUM(client_fee)`; `auditor_pay_due` does the same per auditor with `SUM(auditor_fee)` and a JSON `visit_ids` array. Fees are read from the program at query time, not snapshotted. `invoices.invoice_number` is auto-assigned by trigger as `{prefix}-{YYYY}-{0001}`; `invoices_outstanding` adds `days_overdue` and an `aging_bucket` (`current | 1-30 | 31-60 | 61-90 | 90+`).
- `auditor_reliability` aggregates with `FILTER` clauses (SQLite ≥ 3.30): visits given, completed, approved, no-shows, rejected, upcoming, `on_time_pct` over completed and rejected visits with a punch, last completed date. Auditors with no visits get zeros and a NULL percentage.
- **Phone / desk audits share the account.** `remote_checkin` is policy-scoped. Keep policy 0 geofenced; `policy_create` → `brand_create(policy_id=…)` → `event_create(brand_id=…)` for the remote programs. Documented in `SKILL.md`.
- `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session; SQLite does not persist it. Deleting a client cascades to programs, agents, program-agent rows, visits, and invoices; deleting an auditor sets `visits.auditor_id` NULL and cascades payouts.

**Idempotency keys.** Deterministic, derived from local IDs so a retried or re-run agent turn cannot duplicate:

- location: `loc-agent-{agent_id}`
- event: `event-pa-{program_agent_id}-{YYYYMMDD wave start}`
- shift: `shift-visit-{visit_id}` (one shift per visit row; a redo is a new row)
- cancel: `cancel-shift-{shift_id}`
- worker: `worker-{email}`
- form: `form-audit-record`; assignment: `assign-audit-record-{event_id}`

ZenSched caches idempotent responses for 24 hours.

**Timestamps.** `shift_create` takes `start` and `end` in ISO 8601 with an explicit offset, never `Z`. The offset is the **shop's** (`agents.tz_offset`), which is why `visits_upcoming` builds the strings and the agent is told not to. `shift_list` takes `date_from` / `date_to` as `YYYY-MM-DD`; `form_export` / `form_submissions` take `since` / `until` as dates; `timesheet_export` takes `period="YYYY-MM-DD:YYYY-MM-DD"`.

**Metered reads.** `form_submissions` and `form_export` bill $0.05 per submission read ($0.15 with media; the KYC and shopfront photos make every visit a media read), once per submission ever; replays, including the CSV export for the telco after the JSON pull for QA, are free. `form_export(format="json")` for a wave is the intended pull; `form_submissions(form_id, event_id=...)` for one shop. `shift_list`, `shift_status`, `event_get`, and `timesheet_export(mode="hours"|"raw")` are free.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent. Any SQLite MCP server with read and write tools will work; adjust the tool names in `SKILL.md`.

**Schema test.** The schema was verified by splitting the file into its 47 statements with `sqlite3.complete_statement` and executing each individually (as the MCP server does) twice for idempotency (seed rows not duplicated), then exercising: all 9 tables, 9 views, and 8 triggers present; every view on an empty database; `UNIQUE (client_id, normalized_address)` (and the same address allowed for a different client), `UNIQUE (program_id, agent_id)`, `UNIQUE` on `zensched_shift_id`, `auditors.email`, `auditors.zensched_worker_id`; `visits_upcoming` building `start_iso` / `end_iso` from a `+03:00` and a `+01:00` shop, the `shift-visit-{id}` key, `needs_location`, and `needs_event` flipping on a stale `event_valid_until`; `visits_open` days-left math; `visits_overdue`; `visits_flagged` catching a 45-minute-late check-in, a short visit, an early check-in, a completed visit with no punch, and branding Partial/No while ignoring on-time branding-Yes visits and a 10-minute-early one; the duration trigger on insert and update, across mixed offsets, refilling after NULL, and never overwriting an explicit value; `program_progress` counts and percentage before and after QA; `visits_to_invoice`, `auditor_pay_due`, and `auditor_reliability` math including an auditor with no visits; invoice numbering with prefix and year and an explicit number kept; all five aging buckets and `days_overdue`; every `CHECK` (wave length both ways, window times, weekday mask length and characters, quota, program status, `tz_offset` format including rejecting `Z` and `EAT`, `scheduled_*` format rejecting an offset and a space separator, visit status, QA status, branding_ok labels not keys); the five `updated_at` triggers; foreign keys, cascade from client, and set-null from auditor. The Audit Record form in `SKILL.md` was run through ZenSched's `_validate_fields` and accepted (5 fields, no signature, SKILL.md byte-identical to example-workflow.md, option keys `yes`/`no`/`partial` ≤ 30 characters). Integer types on every ZenSched ID column. 115 checks, all passing.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.
