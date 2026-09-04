# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for the first wave of a program, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

IDs and responses are illustrative. ZenSched IDs are integers. Watch what does **not** cross to ZenSched: the client contact, the fees, the auditor's pay handle, QA notes, **agent names, till numbers**. ZenSched sees `Stop 1 - Ngong Rd`, a street address, an event title that may name the program, a form, and two auditor accounts. Watch also the Lagos shop: its shifts are created in `+01:00` while the agency runs on `+03:00`.

The agency is **Riftline Audits**, Nairobi, Kenya, East Africa time. Today is Tuesday, September 8, 2026.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My Agent Audit Co, timezone_offset = +03:00, invoice_due_days = 30,
    invoice_prefix = INV, default_visit_minutes = 20, default_checkin_radius_m = 75,
    audit_record_form_id = NULL
sqlite_query:   SELECT * FROM visits_overdue;                              → (none)
sqlite_query:   SELECT * FROM visits_flagged WHERE qa_status = 'pending';  → (none)
```

## "We're Riftline Audits in Nairobi, East Africa time. Set the check-in radius to 75 m, give auditors a 30-minute reminder, and create the Audit Record form."

```
sqlite_execute: UPDATE settings SET value = 'Riftline Audits' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '+03:00' WHERE key = 'timezone_offset';

policy_get: policy_id 0
  → settings: { geofence_enabled: true, require_on_site: true, remote_checkin: false, checkin_radius_m: 91, ... }

policy_update:
  policy_id: 0
  settings_json: "{\"checkin_radius_m\": 75, \"checkin_reminder_min_before\": 30}"
  → settings: { checkin_radius_m: 75, checkin_reminder_min_before: 30, geofence_enabled: true, require_on_site: true, ... }
    (with geofencing on, values under 100 m are raised to about 91 m / 300 ft)

sqlite_execute: UPDATE settings SET value = '75' WHERE key = 'default_checkin_radius_m';
```

> Saved. Auditors must check in within the policy radius of the shop pin (75 m requested; geofencing raises anything under 100 m to about 91 m / 300 ft — a kiosk-and-veranda circle) and get a reminder 30 minutes before each visit. GPS verification stays on for every in-shop program; that is the proof your telco pays for. If you also run phone audits later, we give those their own brand and policy instead of flipping `remote_checkin` on this one. East Africa time is the default for new shops, but each shop keeps its own time zone. You don't have an Audit Record form yet; it's free to create. Want me to set it up now?

Owner: *"yes"*

```
form_create:
  title: "Audit Record"
  idempotency_key: "form-audit-record"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Audit record", "identifier": "sec_audit",
   "text": "Count the visible cash float, photograph the KYC poster and the shopfront. Do not write the agent's name or till number on this form. This is not a telco or central-bank KYC/AML record."},
  {"type": "number", "label": "Float count", "identifier": "float_count", "required": true},
  {"type": "select", "label": "Branding OK", "identifier": "branding_ok", "required": true,
   "options": ["Yes", "No", "Partial"]},
  {"type": "photo", "label": "KYC poster", "identifier": "kyc_poster", "required": true, "max_images": 2},
  {"type": "photo", "label": "Shopfront", "identifier": "shopfront", "required": true, "max_images": 1}
]
```

```
  → form_id: 501, fields: [ ...5 fields echoed with identifiers... ]

sqlite_execute: UPDATE settings SET value = '501' WHERE key = 'audit_record_form_id';
```

> Audit Record form created. I'll attach it to every shop automatically. Float count, branding Yes/No/Partial, KYC poster (up to 2), shopfront (1). There is no signature step — this is not a telco or central-bank official KYC / AML record.

## "New program. Client is PesaNet, contact Wanjiku Mwangi, wanjiku@pesanet.example, billing ap@pesanet.example, net 30. Weekday shop audits, one per agent, 8 to 6, Sep 8 through Sep 30. $8 per visit to them, auditors get $3. Visits should take at least 8 minutes. Agents: Fatuma Hassan, till 884211, 14 Ngong Road, Nairobi / Joseph Otieno, till 552190, Tom Mboya Street, Nairobi / Chidi Okonkwo, till NG-44081, 22 Allen Avenue, Ikeja, Lagos. Brief: count the visible float, photograph the KYC poster and the shopfront, mark branding."

```
sqlite_query:   SELECT client_id FROM clients WHERE client_name = 'PesaNet';   → (none)
sqlite_execute:
  INSERT INTO clients (client_name, contact_name, contact_email, billing_email, payment_terms_days)
  VALUES ('PesaNet', 'Wanjiku Mwangi', 'wanjiku@pesanet.example', 'ap@pesanet.example', 30);
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO programs (client_id, program_name, wave_start, wave_end, window_start_time, window_end_time, allowed_weekdays,
                        quota_per_agent, client_fee, auditor_fee, min_minutes, zensched_form_id, auditor_brief, status)
  VALUES (1, 'PesaNet Agent Audit - Sep', '2026-09-08', '2026-09-30', '08:00', '18:00', '1111100',
          1, 8.00, 3.00, 8, 501,
          'Count the visible float. Photograph the KYC poster and the shopfront. Mark branding. Do not write the till number on the form.',
          'draft');
  → lastInsertRowid = 1
```

Shops: normalize, look up, insert. Lagos gets `+01:00`. Labels are de-identified.

```
sqlite_query: SELECT agent_id, zensched_location_id FROM agents WHERE client_id = 1 AND normalized_address = '14 ngong rd nairobi ke';   → (none)
sqlite_execute:
  INSERT INTO agents (client_id, agent_name, agent_code, address, city, region, country, postal, normalized_address, tz_offset, zensched_label)
  VALUES (1, 'Fatuma Hassan', '884211', '14 Ngong Road', 'Nairobi', 'Nairobi', 'KE', NULL,
          '14 ngong rd nairobi ke', '+03:00', 'Stop 1 - Ngong Rd');   → 1
sqlite_execute:
  INSERT INTO agents (client_id, agent_name, agent_code, address, city, region, country, postal, normalized_address, tz_offset, zensched_label)
  VALUES (1, 'Joseph Otieno', '552190', 'Tom Mboya Street', 'Nairobi', 'Nairobi', 'KE', NULL,
          'tom mboya st nairobi ke', '+03:00', 'Stop 2 - Tom Mboya');   → 2
sqlite_execute:
  INSERT INTO agents (client_id, agent_name, agent_code, address, city, region, country, postal, normalized_address, tz_offset, zensched_label)
  VALUES (1, 'Chidi Okonkwo', 'NG-44081', '22 Allen Avenue', 'Ikeja', 'Lagos', 'NG', NULL,
          '22 allen ave ikeja lagos ng', '+01:00', 'Stop 3 - Ikeja');   → 3

sqlite_execute: INSERT INTO program_agents (program_id, agent_id, visits_required) VALUES (1, 1, 1);   → 1
sqlite_execute: INSERT INTO program_agents (program_id, agent_id, visits_required) VALUES (1, 2, 1);   → 2
sqlite_execute: INSERT INTO program_agents (program_id, agent_id, visits_required) VALUES (1, 3, 1);   → 3
```

Agent (first metered call this session, rule 9):

> Three new shops cost $0.09 to geocode now. Each completed visit will cost about $0.35 on ZenSched (two GPS punches and one form read with the KYC / shopfront photos), so about $1.05 for the wave. If the account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
location_create:
  name: "Stop 1 - Ngong Rd"
  street_address: "14 Ngong Road, Nairobi, Nairobi"
  checkin_radius_m: 75
  idempotency_key: "loc-agent-1"
  → location_id: 9201, lat: -1.3006, lng: 36.7845, pin_quality: "street"
    billing: { meter: "geocode", units: 1, price: 0.03 }

location_create: name "Stop 2 - Tom Mboya", street_address "Tom Mboya Street, Nairobi, Nairobi", checkin_radius_m 75, idempotency_key "loc-agent-2"  → 9202
location_create: name "Stop 3 - Ikeja",     street_address "22 Allen Avenue, Ikeja, Lagos",     checkin_radius_m 75, idempotency_key "loc-agent-3"  → 9203

sqlite_execute: UPDATE agents SET zensched_location_id = 9201 WHERE agent_id = 1;
sqlite_execute: UPDATE agents SET zensched_location_id = 9202 WHERE agent_id = 2;
sqlite_execute: UPDATE agents SET zensched_location_id = 9203 WHERE agent_id = 3;
```

Fatuma, Joseph, Chidi, 884211, 552190, and NG-44081 are **not** in `name` or `notes`. They live only in `agents.agent_name` / `agents.agent_code`. `checkin_radius_m` on the location is informational; the enforced radius is the policy.

One event per shop for the wave, the form attached to each:

```
event_create:
  location_id: 9201
  title: "PesaNet Agent Audit - Stop 1 - Ngong Rd"
  start_date: "2026-09-08"
  end_date:   "2026-09-30"          ← the wave (23 days; the cap is 60)
  idempotency_key: "event-pa-1-20260908"
  → event_id: 7301

form_assign:
  form_id: 501
  event_id: 7301
  idempotency_key: "assign-audit-record-7301"
  → status: "assigned", form_id: 501, event_id: 7301, policy_id: 0

sqlite_execute: UPDATE program_agents SET zensched_event_id = 7301, event_valid_until = '2026-09-30' WHERE program_agent_id = 1;

event_create: location_id 9202, title "PesaNet Agent Audit - Stop 2 - Tom Mboya", 2026-09-08..2026-09-30, key "event-pa-2-20260908"  → 7302;  form_assign 501 → 7302, key "assign-audit-record-7302"
event_create: location_id 9203, title "PesaNet Agent Audit - Stop 3 - Ikeja",     2026-09-08..2026-09-30, key "event-pa-3-20260908"  → 7303;  form_assign 501 → 7303, key "assign-audit-record-7303"
sqlite_execute: UPDATE program_agents SET zensched_event_id = 7302, event_valid_until = '2026-09-30' WHERE program_agent_id = 2;
sqlite_execute: UPDATE program_agents SET zensched_event_id = 7303, event_valid_until = '2026-09-30' WHERE program_agent_id = 3;

sqlite_execute: INSERT INTO visits (program_agent_id) VALUES (1);   → visit 1 (open)
sqlite_execute: INSERT INTO visits (program_agent_id) VALUES (2);   → visit 2
sqlite_execute: INSERT INTO visits (program_agent_id) VALUES (3);   → visit 3

sqlite_execute: UPDATE programs SET status = 'active' WHERE program_id = 1;
```

> PesaNet Agent Audit - Sep is live: 3 shops (2 Nairobi, 1 Lagos), 3 visits, weekdays 08:00–18:00 through Sep 30. $8 per visit to PesaNet; auditors earn $3. The Audit Record has 5 fields (float, branding, KYC poster max 2, shopfront max 1). Till numbers and agent names stay on your computer; ZenSched only has Stop 1 / Stop 2 / Stop 3. No auditors yet; who should I invite?

## "Invite Amina Yusuf, amina@example.com, Nairobi, M-Pesa 0712 555 014. And Tunde Balogun, tunde@example.com, Lagos, bank Transfer Tunde B."

> Inviting two auditors costs $0.50. OK?

Owner: *"yes"*

```
worker_invite:
  email: "amina@example.com"
  first_name: "Amina"
  last_name: "Yusuf"
  idempotency_key: "worker-amina@example.com"
  → worker_id: 601, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

worker_invite: email "tunde@example.com", first_name "Tunde", last_name "Balogun", idempotency_key "worker-tunde@example.com"  → worker_id 602

sqlite_execute: INSERT INTO auditors (auditor_name, email, home_city, home_region, zensched_worker_id, pay_handle) VALUES ('Amina Yusuf', 'amina@example.com', 'Nairobi', 'Nairobi', 601, 'mpesa:0712555014');   → 1
sqlite_execute: INSERT INTO auditors (auditor_name, email, home_city, home_region, zensched_worker_id, pay_handle) VALUES ('Tunde Balogun', 'tunde@example.com', 'Lagos', 'Lagos', 602, 'bank:Transfer Tunde B');   → 2
```

> Invited Amina and Tunde. Each gets an email with the app link and an activation code. They'll see the shop label, their time slot, and the form — not the till number. The brief you send them yourself.

Optional, if a market stall keeps missing punches:

```
policy_get: policy_id 0
policy_update:
  policy_id: 0
  settings_json: '{"geofence_enabled": true, "require_on_site": true, "checkin_radius_m": 150}'
```

The radius is on the **policy**, not on any shop.

## "Give Amina the two Nairobi shops next week, morning, and Tunde the Lagos one on Tuesday."

```
sqlite_query: SELECT * FROM visits_open;
  → visit 1 | Stop 1 - Ngong Rd   | Nairobi | +03:00 | evt 7301 | 08:00–18:00 | 1111100 | 22 days left | Fatuma Hassan | 884211
    visit 2 | Stop 2 - Tom Mboya  | Nairobi | +03:00 | evt 7302 | ...
    visit 3 | Stop 3 - Ikeja      | Ikeja   | +01:00 | evt 7303 | ...
sqlite_query: SELECT auditor_id, zensched_worker_id FROM auditors WHERE is_active = 1;   → (1, 601), (2, 602)
```

Next week is Sep 14–18, all weekdays. Amina's two visits go on Mon and Tue as a Nairobi route; 20-minute slots inside 08:00–18:00.

```
sqlite_execute: UPDATE visits SET auditor_id = 1, scheduled_start = '2026-09-14T09:00:00', scheduled_end = '2026-09-14T09:20:00', status = 'assigned' WHERE visit_id = 1;
sqlite_execute: UPDATE visits SET auditor_id = 1, scheduled_start = '2026-09-15T09:00:00', scheduled_end = '2026-09-15T09:20:00', status = 'assigned' WHERE visit_id = 2;
sqlite_execute: UPDATE visits SET auditor_id = 2, scheduled_start = '2026-09-15T09:00:00', scheduled_end = '2026-09-15T09:20:00', status = 'assigned' WHERE visit_id = 3;

sqlite_query: SELECT * FROM visits_upcoming WHERE zensched_shift_id IS NULL;
  → visit 1 | Stop 1 - Ngong Rd  | worker 601 | start_iso 2026-09-14T09:00:00+03:00 | end_iso 2026-09-14T09:20:00+03:00 | shift-visit-1 | needs_location 0 | needs_event 0 | evt 7301
    visit 2 | Stop 2 - Tom Mboya | worker 601 | start_iso 2026-09-15T09:00:00+03:00 | end_iso 2026-09-15T09:20:00+03:00 | shift-visit-2 | needs_location 0 | needs_event 0 | evt 7302
    visit 3 | Stop 3 - Ikeja     | worker 602 | start_iso 2026-09-15T09:00:00+01:00 | end_iso 2026-09-15T09:20:00+01:00 | shift-visit-3 | needs_location 0 | needs_event 0 | evt 7303

shift_create:
  event_id: 7301
  worker_id: 601
  start: "2026-09-14T09:00:00+03:00"
  end:   "2026-09-14T09:20:00+03:00"
  idempotency_key: "shift-visit-1"
  → shift_id: 89011, status: "scheduled", forms_installed: [501]

shift_create: event_id 7302, worker_id 601, start "2026-09-15T09:00:00+03:00", end "2026-09-15T09:20:00+03:00", idempotency_key "shift-visit-2"  → 89012
shift_create:
  event_id: 7303
  worker_id: 602
  start: "2026-09-15T09:00:00+01:00"        ← Lagos offset, not the agency's
  end:   "2026-09-15T09:20:00+01:00"
  idempotency_key: "shift-visit-3"
  → shift_id: 89013, status: "scheduled", forms_installed: [501]

sqlite_execute: UPDATE visits SET zensched_shift_id = 89011 WHERE visit_id = 1;
sqlite_execute: UPDATE visits SET zensched_shift_id = 89012 WHERE visit_id = 2;
sqlite_execute: UPDATE visits SET zensched_shift_id = 89013 WHERE visit_id = 3;
```

> Assigned:
> - Amina: Mon 9/14 09:00–09:20 Stop 1 - Ngong Rd (Fatuma Hassan); Tue 9/15 09:00–09:20 Stop 2 - Tom Mboya (Joseph Otieno)
> - Tunde: Tue 9/15 09:00–09:20 Stop 3 - Ikeja (Chidi Okonkwo, West Africa time)
>
> Both notified in the app with the Audit Record attached and a reminder 30 minutes before. Send them the brief; remind them the KYC poster (up to 2) and shopfront (1) are required. Till numbers stay off ZenSched.

Nothing but the shift IDs is written locally. Asking again for the same visits returns the same three shifts because of `shift-visit-{visit_id}`.

## The auditors do the work

Monday 09:03, Amina at 14 Ngong Road: **Check in** (GPS: 22 m from the pin, verified, $0.10). Counts 18400 visible float. Opens **Audit Record**: Float count 18400; Branding OK = Yes; two KYC-poster photos; one shopfront. Submits (no signature). **Check out** 09:18 ($0.10).

Tuesday 09:02, Amina at Tom Mboya: in, float 9250, branding Yes, two KYC + shopfront, out 09:17.

Tuesday, Tunde in Ikeja runs late. Slot was 09:00–09:20 West Africa; he checks in at 10:05 (GPS verified, 41 m), float 6200, branding Partial (faded fascia, poster up), one KYC + shopfront, checks out 10:19.

## "Pull this week's results." (Saturday, Sep 19)

```
shift_list:
  date_from: "2026-09-14"
  date_to:   "2026-09-18"
  status:    "checked_out"
  → shifts: [
      { shift_id: 89011, event_id: 7301, worker_id: 601, date: "2026-09-14", start: "09:00", end: "09:20", status: "checked_out" },
      { shift_id: 89012, event_id: 7302, worker_id: 601, date: "2026-09-15", start: "09:00", end: "09:20", status: "checked_out" },
      { shift_id: 89013, event_id: 7303, worker_id: 602, date: "2026-09-15", start: "09:00", end: "09:20", status: "checked_out" }
    ], count: 3

sqlite_query: SELECT visit_id, program_agent_id, auditor_id FROM visits WHERE zensched_shift_id IN (89011, 89012, 89013) AND status = 'assigned';
  → (1, 1, 1), (2, 2, 1), (3, 3, 2)
```

Agent (metered read, rule 9):

> There are 3 Audit Records to pull, all with photos, so about $0.45 ($0.15 each). I'll read them once and keep the summaries locally. That's the last piece of the ~$0.35/visit meter (punches already billed when they checked in and out). OK?

Owner: *"go"*

```
form_export:
  form_id: 501
  since: "2026-09-08"
  until: "2026-09-19"
  format: "json"
  → row_count: 3, rows: [
      { submission_id: 5501, worker_id: 601, event_id: 7301, submitted_at: "2026-09-14 09:16:40",
        data: { float_count: 18400, branding_ok: "yes" },
        media: [ { field_id: 4, cdn_url: "https://cdn.zensched.com/m/.../k1.jpg",
                   thumbnail_url: "https://cdn.zensched.com/m/.../k1_thumb.jpg", original_filename: "k1.jpg" },
                 { field_id: 4, cdn_url: "https://cdn.zensched.com/m/.../k2.jpg",
                   thumbnail_url: "https://cdn.zensched.com/m/.../k2_thumb.jpg", original_filename: "k2.jpg" },
                 { field_id: 5, cdn_url: "https://cdn.zensched.com/m/.../s1.jpg",
                   thumbnail_url: "https://cdn.zensched.com/m/.../s1_thumb.jpg", original_filename: "s1.jpg" } ] },
      { submission_id: 5502, worker_id: 601, event_id: 7302, submitted_at: "2026-09-15 09:15:12",
        data: { float_count: 9250, branding_ok: "yes" },
        media: [ { field_id: 4, cdn_url: "https://cdn.zensched.com/m/.../k3.jpg",
                   thumbnail_url: "https://cdn.zensched.com/m/.../k3_thumb.jpg", original_filename: "k3.jpg" },
                 { field_id: 4, cdn_url: "https://cdn.zensched.com/m/.../k4.jpg",
                   thumbnail_url: "https://cdn.zensched.com/m/.../k4_thumb.jpg", original_filename: "k4.jpg" },
                 { field_id: 5, cdn_url: "https://cdn.zensched.com/m/.../s2.jpg",
                   thumbnail_url: "https://cdn.zensched.com/m/.../s2_thumb.jpg", original_filename: "s2.jpg" } ] },
      { submission_id: 5503, worker_id: 602, event_id: 7303, submitted_at: "2026-09-15 10:17:05",
        data: { float_count: 6200, branding_ok: "partial" },
        media: [ { field_id: 4, cdn_url: "https://cdn.zensched.com/m/.../k5.jpg",
                   thumbnail_url: "https://cdn.zensched.com/m/.../k5_thumb.jpg", original_filename: "k5.jpg" },
                 { field_id: 5, cdn_url: "https://cdn.zensched.com/m/.../s3.jpg",
                   thumbnail_url: "https://cdn.zensched.com/m/.../s3_thumb.jpg", original_filename: "s3.jpg" } ] }
    ]
    billing: { meter: "form_media", units: 3, price: 0.45 }

shift_status: shift_id 89011
  → status "checked_out", actual_in "2026-09-14T09:03:10+03:00", actual_out "2026-09-14T09:18:05+03:00",
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 22 },
               { type: "out", gps_verified: true, distance_from_site_m: 18 } ]
(free)

sqlite_execute:
  UPDATE visits SET status = 'completed', submission_dc_id = 5501,
    checkin_at = '2026-09-14T09:03:10+03:00', checkout_at = '2026-09-14T09:18:05+03:00',
    float_count = 18400, branding_ok = 'Yes',
    kyc_photo_urls = '["https://cdn.zensched.com/m/.../k1.jpg","https://cdn.zensched.com/m/.../k2.jpg"]',
    shopfront_photo_urls = '["https://cdn.zensched.com/m/.../s1.jpg"]',
    qa_status = 'pending'
  WHERE visit_id = 1;
  -- trigger: duration_minutes → 15

sqlite_execute:
  UPDATE visits SET status = 'completed', submission_dc_id = 5502,
    checkin_at = '2026-09-15T09:02:08+03:00', checkout_at = '2026-09-15T09:17:22+03:00',
    float_count = 9250, branding_ok = 'Yes',
    kyc_photo_urls = '["https://cdn.zensched.com/m/.../k3.jpg","https://cdn.zensched.com/m/.../k4.jpg"]',
    shopfront_photo_urls = '["https://cdn.zensched.com/m/.../s2.jpg"]',
    qa_status = 'pending'
  WHERE visit_id = 2;

sqlite_execute:
  UPDATE visits SET status = 'completed', submission_dc_id = 5503,
    checkin_at = '2026-09-15T10:05:00+01:00', checkout_at = '2026-09-15T10:19:00+01:00',
    float_count = 6200, branding_ok = 'Partial',
    kyc_photo_urls = '["https://cdn.zensched.com/m/.../k5.jpg"]',
    shopfront_photo_urls = '["https://cdn.zensched.com/m/.../s3.jpg"]',
    qa_status = 'pending'
  WHERE visit_id = 3;

sqlite_query: SELECT * FROM visits_flagged WHERE qa_status = 'pending';
  → visit 3 | Stop 3 - Ikeja | Tunde | checkin_late 1 | branding_issue 1 | minutes_after_slot_end 45
```

> Pulled 3 visits.
>
> **Flag:** Stop 3 - Ikeja, Tunde — checked in at 10:05, 45 minutes after his 09:00–09:20 slot ended. Branding Partial, float 6,200. 1 KYC photo + shopfront.
>
> Stop 1 - Ngong Rd (Amina): on time, 15 min, branding Yes, float 18,400. Stop 2 - Tom Mboya (Amina): on time, branding Yes, float 9,250.

## "Approve Amina's two. Reject Tunde, he checked in after the slot. Reopen it."

```
sqlite_execute: UPDATE visits SET qa_status = 'approved', qa_notes = 'On time, branding Yes' WHERE visit_id IN (1, 2);
sqlite_execute: UPDATE visits SET qa_status = 'rejected', status = 'rejected', qa_notes = 'Checked in 45 min after slot; telco will not accept' WHERE visit_id = 3;
sqlite_execute: INSERT INTO visits (program_agent_id) VALUES (3);   → visit 4 (open, replaces the rejected Ikeja visit)
```

> Approved Amina's two Nairobi visits. Rejected Tunde's Ikeja visit and reopened it — it is back on `visits_open` for someone else. Tunde is not paid for that one unless you say otherwise.

## "How's the PesaNet program doing?"

```
sqlite_query: SELECT * FROM program_progress WHERE program_id = 1;
  → 3 agents, 3 required, 0 open, 0 assigned, 2 completed, 2 approved, 0 no-show, 0 QA pending, 1 rejected (not in those counts), pct_complete 66.7, days_left 11
```

> PesaNet Agent Audit - Sep: 3 shops, 3 visits required; 2 approved, 1 open (Ikeja redo), 11 days left (66.7% complete).

## "Send PesaNet their results and invoice."

```
form_export:
  form_id: 501
  since: "2026-09-08"
  until: "2026-09-30"
  format: "csv"
  → download_url: "https://cdn.zensched.com/exports/..."   (already-read submissions not billed again)

sqlite_query: SELECT * FROM visits_to_invoice;
  → PesaNet | 2 visits | 16.00 | 2026-09-14 .. 2026-09-15

sqlite_execute:
  INSERT INTO invoices (client_id, program_id, invoice_date, due_date, visit_count, fees_amount, total_amount, line_items)
  SELECT p.client_id, CASE WHEN COUNT(DISTINCT p.program_id) = 1 THEN MIN(p.program_id) END,
         date('now'),
         date('now', '+' || COALESCE(MAX(c.payment_terms_days), 30) || ' days'),
         COUNT(*), SUM(p.client_fee), SUM(p.client_fee),
         json_group_array(json_object('visit_id', v.visit_id, 'date', date(v.scheduled_start),
                                      'label', a.zensched_label, 'program', p.program_name,
                                      'fee', p.client_fee, 'float_count', v.float_count, 'branding_ok', v.branding_ok))
  FROM visits v
  JOIN program_agents pa ON pa.program_agent_id = v.program_agent_id
  JOIN programs p ON p.program_id = pa.program_id
  JOIN agents a ON a.agent_id = pa.agent_id
  JOIN clients c ON c.client_id = p.client_id
  WHERE v.status = 'completed' AND v.qa_status = 'approved' AND v.client_invoiced = 0 AND p.client_id = 1
  GROUP BY p.client_id;

sqlite_execute: UPDATE visits SET client_invoiced = 1 WHERE visit_id IN (1, 2);
sqlite_query:   SELECT invoice_number, due_date, visit_count, total_amount FROM invoices WHERE invoice_id = last_insert_rowid();
  → INV-2026-0001 | 2026-10-19 | 2 | 16.00
```

> CSV download for the wave (strip the `worker_name` column before it goes to PesaNet). Invoice you can paste:
>
> ```
> Riftline Audits
> Invoice INV-2026-0001
> To: PesaNet (ap@pesanet.example)
> Program: PesaNet Agent Audit - Sep
> Date: Sep 19, 2026    Due: Oct 19, 2026
>
>   Sep 14    Stop 1 - Ngong Rd     float 18400   branding Yes       $8.00
>   Sep 15    Stop 2 - Tom Mboya    float  9250   branding Yes       $8.00
>
> Total due: $16.00
> Every visit GPS-verified at the shop with timestamped KYC-poster and shopfront photos.
> ```
>
> No auditor names. No till numbers. Say "sent" when it's out. Want me to add till numbers from your local file for this invoice only?

## "Run auditor pay."

```
sqlite_query: SELECT * FROM auditor_pay_due;
  → Amina Yusuf | mpesa:0712555014 | 2 visits | 6.00 | [1, 2]

sqlite_execute:
  INSERT INTO auditor_payouts (auditor_id, period_start, period_end, visit_count, fees_amount, total_amount, visit_ids)
  SELECT auditor_id, '2026-09-08', '2026-09-19', visit_count, fees_amount, total_due, visit_ids
  FROM auditor_pay_due WHERE auditor_id = 1;

sqlite_execute: UPDATE visits SET auditor_paid = 1 WHERE auditor_id = 1 AND status = 'completed' AND qa_status = 'approved' AND auditor_paid = 0;
```

> Amina Yusuf — M-Pesa 0712 555 014 — 2 visits × $3 = $6.00 (Stop 1 Sep 14, Stop 2 Sep 15). Tunde has nothing approved. Pay her outside the kit and say "paid".

## "PesaNet paid INV-2026-0001."

```
sqlite_execute: UPDATE invoices SET paid = 1, paid_date = date('now'), sent_date = COALESCE(sent_date, date('now')) WHERE invoice_number = 'INV-2026-0001';
```

> Marked INV-2026-0001 paid. Ikeja is still open if you want it covered before Sep 30.

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| PesaNet contact, $8 / $3 fees, wave dates | SQLite | CRM; ZenSched does not model rates or waves |
| Fatuma / Joseph / Chidi names, tills 884211 / 552190 / NG-44081 | SQLite **only** | Privacy; never sent to ZenSched |
| Each shop's GPS location under `Stop N - street` | ZenSched (integer ID in `agents`) | Needed for geofenced check-in |
| Each shop's current ≤60-day event and its end date | ZenSched (integer ID + `event_valid_until` in `program_agents`) | Shifts hang off events; one event per shop per wave |
| The Audit Record form | ZenSched (ID in `settings`) | Installed on the auditor's phone per shift |
| Amina and Tunde, their invites, their app | ZenSched (integer ID in `auditors`) | Workforce and notifications |
| The week's three shifts | ZenSched only | Live schedule; never copied |
| GPS punches, actual times | ZenSched only | Verified record; queried via `shift_status` |
| Three Audit Records with photos | ZenSched (originals); summary + photo URLs in `visits` | Read once (metered), then QA / invoices from SQLite |
| Two approved `visits` rows + one rejected + one reopened | SQLite | Billing + auditor reliability |
| One invoice, paid | SQLite | Billing |
