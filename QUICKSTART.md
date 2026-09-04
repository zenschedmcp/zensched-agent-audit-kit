# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

Before you start, read the "What this kit is not" section of `README.md`. Short version: this is GPS-verified shop-visit proof plus a local extract of the Audit Record (float, branding, KYC poster, shopfront). It is **not** a telco or central-bank official KYC / AML / CICO record (not a CBK, BOT, Bangladesh Bank, SBP, or CBN filing), not a wallet-balance pull, and not a signed legal document. Agent names and till numbers stay on your computer.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\agent-audit` (Windows) or `/Users/yourname/agent-audit` (Mac). Note the full path. It will hold till numbers, agent names, and auditor pay details, so keep it backed up.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\agent-audit\\agent-audit.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "Riftline Audits". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my agent-audit database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> We're Riftline Audits in Nairobi, Kenya, East Africa time. Save that to settings, set the check-in radius to 75 m, give auditors a 30-minute reminder, and create the Audit Record form.

The AI saves your name and default time zone, sets the ZenSched check-in policy (free): auditors must be within 75 m of the shop pin (about 91 m / 300 ft once geofencing raises the floor), GPS verification stays on, and they get a reminder before each visit. It creates the Audit Record once (free): float count, branding Yes/No/Partial, KYC poster (max 2), shopfront (max 1). No signature. Till numbers stay local.

## 6. Set up your first program

Paste the client's agent list. For example:

> New program. Client is PesaNet, contact Wanjiku Mwangi, wanjiku@pesanet.example, billing ap@pesanet.example, net 30. Weekday shop audits, one per agent, 8 to 6, Sep 8 through Sep 30. $8 per visit to them, auditors get $3, visits at least 8 minutes. Agents: Fatuma Hassan, till 884211, 14 Ngong Road, Nairobi / Joseph Otieno, till 552190, Tom Mboya Street, Nairobi / Chidi Okonkwo, till NG-44081, 22 Allen Avenue, Ikeja, Lagos. Brief: count the visible float, photograph the KYC poster and the shopfront, mark branding.

Behind the scenes the AI saves the client and program locally, adds the three shops to its agent cache (the Lagos one in `+01:00`), labels them `Stop 1 - Ngong Rd`, `Stop 2 - Tom Mboya`, `Stop 3 - Ikeja` (never the till number), attaches the Audit Record (free), asks you before geocoding the three shops ($0.09, may trigger the $5 activation deposit the first time), creates one event per shop for the wave with the form attached, and creates three open visits. You just see a confirmation. Each completed visit will cost about $0.35 on ZenSched.

## 7. Invite your auditors

> Invite Amina Yusuf at amina@example.com, Nairobi, M-Pesa 0712 555 014. And Tunde Balogun, tunde@example.com, Lagos, bank Transfer Tunde B.

Each gets an email ($0.25), installs the app ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [iOS TestFlight](https://testflight.apple.com/join/Wp51m5Yq)), and activates. Send them the brief yourself; ZenSched shows them the shop **label**, the slot, and the form — not the till number.

## 8. Assign the visits

> Give Amina the two Nairobi shops next week, morning, and Tunde the Lagos one on Tuesday.

The AI picks weekdays inside the 8–6 window, creates one shift per visit on ZenSched in each shop's own time zone, and confirms by auditor and day. Amina gets a push notification per visit with the Audit Record attached. She checks in at the shop (GPS-verified), counts the float, photographs the KYC poster and shopfront, marks branding, and checks out.

Or say "fill the open visits" and the AI proposes who should take what, by home city and track record, and waits for your yes.

## 9. After the visits are done

> Pull this week's results.

The AI pulls the completed, GPS-verified shifts and their punch times from ZenSched (free), then the submissions (metered, so it tells you the cost first, about $0.15 per visit), records float and branding, and leads with anything suspicious: a check-in 40 minutes after the slot ended, branding Partial, a form with no check-in, a 4-minute visit. Missed shifts become no-shows and the visit is reopened.

> Approve Amina's two. Reject Tunde, he checked in after the slot. Reopen it.

Approved visits go on the telco invoice and the auditor pay sheet. Rejected ones are reopened for someone to redo.

> How's the PesaNet program doing?

Required, assigned, completed, approved, percent complete, days left. From the local database, free.

> Send PesaNet their results and invoice.

A CSV download of the wave's submissions (already-read submissions are not billed again) plus a plain-text invoice with one line per approved visit (shop **label**, not till number) and a note that every visit was GPS-verified with timestamped KYC-poster and shopfront photos. No auditor names.

> Run auditor pay.

A pay sheet per auditor (fee, with their pay handle). You pay them through M-Pesa or the bank and say "paid".

> PesaNet paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, the privacy boundary, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above
- `SKILL.md` if you also run phone or desk audits — it has the brand/policy recipe so you do not flip geofencing off for in-shop work
