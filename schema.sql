-- ZenSched Agent-Audit Local Database Schema
-- SQLite database for telco / MMO clients, audit programs (waves),
-- the agent-shop cache, the auditor pool, individual audit visits
-- and float/branding/KYC results, QA, client invoicing, and auditor
-- pay runs.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, the
-- original form submissions and KYC / shopfront photos).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my agent-audit database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 agent-audit.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- PRIVACY: agents.agent_name and agents.agent_code (till number, agent ID,
-- MSISDN, wallet ID) live ONLY in this file on your computer. The ONLY
-- string sent to ZenSched about a shop is agents.zensched_label
-- (e.g. 'Stop 12 - Ngong Rd'). Never send a till number, an agent name,
-- or a wallet ID in location_create name/notes, event_create title/notes,
-- a form field, or a shift_cancel reason. SKILL.md makes this a hard rule.
--
-- TIME CONVENTIONS
--   visits.scheduled_start / scheduled_end are SHOP-LOCAL wall-clock times
--   without an offset ('2026-09-10T09:00:00'). Views append the agent's
--   tz_offset to build the ISO strings shift_create needs, so a multi-country
--   program (Nairobi +03:00, Lagos +01:00, Dhaka +06:00) comes out right
--   without the agent doing timezone arithmetic.
--   visits.checkin_at / checkout_at are ISO 8601 WITH an explicit offset, as
--   recorded from ZenSched (any offset is fine; SQLite normalizes to UTC when
--   comparing).

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session.
-- timezone_offset is the DEFAULT for new agents; each agent carries its own
-- tz_offset because programs often span countries.
-- default_checkin_radius_m is informational: the radius ZenSched enforces is
-- the account POLICY's, set with policy_update(0, {"checkin_radius_m": N}).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My Agent Audit Co');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '+03:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '30');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_visit_minutes', '20');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_checkin_radius_m', '75');
INSERT OR IGNORE INTO settings (key, value) VALUES ('audit_record_form_id', NULL);

-- Clients: the telco, MMO, bank, or super-agent network that buys verified
-- shop visits. LOCAL ONLY. Nothing from this table is ever sent to ZenSched.
CREATE TABLE IF NOT EXISTS clients (
  client_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_name TEXT NOT NULL,
  contact_name TEXT,
  contact_email TEXT,
  contact_phone TEXT,
  billing_email TEXT,
  payment_terms_days INTEGER DEFAULT 30,
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Programs: one WAVE of shop audits for one client. A program says which
-- agents, when (wave dates, daily window, allowed weekdays), how many visits
-- per shop, and the money (client fee, auditor fee). A quarter-long
-- engagement is several program rows, one per wave, because a ZenSched event
-- is capped at 60 days and the kit creates one event per agent per wave
-- (the CHECK below enforces the split). allowed_weekdays is a 7-character
-- 0/1 mask, Monday first: '1111100' = weekdays only.
CREATE TABLE IF NOT EXISTS programs (
  program_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  program_name TEXT NOT NULL,                       -- 'M-Pesa Agent Audit - Sep'
  wave_start TEXT NOT NULL,                         -- ISO date
  wave_end TEXT NOT NULL                            -- ISO date, at most 59 days after wave_start
    CHECK (wave_end >= wave_start AND julianday(wave_end) - julianday(wave_start) <= 59),
  window_start_time TEXT NOT NULL DEFAULT '08:00'   -- earliest local time a visit may start
    CHECK (window_start_time GLOB '[0-2][0-9]:[0-5][0-9]'),
  window_end_time TEXT NOT NULL DEFAULT '18:00'     -- latest local time a visit may END
    CHECK (window_end_time GLOB '[0-2][0-9]:[0-5][0-9]'),
  allowed_weekdays TEXT NOT NULL DEFAULT '1111100'
    CHECK (length(allowed_weekdays) = 7 AND allowed_weekdays NOT GLOB '*[^01]*'),
  quota_per_agent INTEGER NOT NULL DEFAULT 1 CHECK (quota_per_agent >= 1),
  client_fee REAL NOT NULL,                         -- what the telco pays per approved visit
  auditor_fee REAL NOT NULL,                        -- what the auditor earns per approved visit
  min_minutes INTEGER DEFAULT 8,                    -- visits shorter than this are flagged
  zensched_form_id INTEGER,                         -- from form_create (shared Audit Record)
  auditor_brief TEXT,                               -- the ONLY text about this program an auditor may be told
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'active', 'closed')),
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE
);

-- Agents: the cache of physical shops / kiosks / dukas, one ZenSched
-- LOCATION each, created once and kept forever (geocoding is metered).
-- Keyed by client + normalized address so the same shop pasted in two
-- CSVs is one row and one geocode.
-- tz_offset is PER AGENT: a regional program has shops in several zones.
-- agent_name and agent_code are LOCAL ONLY. zensched_label is the only
-- name that crosses to ZenSched ('Stop 12 - Ngong Rd').
CREATE TABLE IF NOT EXISTS agents (
  agent_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  agent_name TEXT NOT NULL,                         -- LOCAL ONLY: the person / shop trade name
  agent_code TEXT,                                  -- LOCAL ONLY: till number, agent ID, wallet ID
  address TEXT NOT NULL,                            -- as the client wrote it
  city TEXT,
  region TEXT,                                      -- county / state / division
  country TEXT DEFAULT 'KE',
  postal TEXT,
  normalized_address TEXT NOT NULL,                 -- see SKILL.md "Normalize an address"
  tz_offset TEXT NOT NULL                           -- '+03:00'; defaults to settings.timezone_offset unless the agent knows better
    CHECK (tz_offset GLOB '[+-][0-1][0-9]:[0-5][0-9]'),
  zensched_label TEXT,                              -- de-identified name used on ZenSched
  zensched_location_id INTEGER,                     -- from location_create (permanent)
  is_active INTEGER DEFAULT 1,
  notes TEXT,                                       -- LOCAL ONLY: 'blue container, second from the corner'
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE,
  UNIQUE (client_id, normalized_address)
);

-- Program x agent: which shops are in this wave, how many visits each needs,
-- and the ZenSched EVENT for that shop for this wave (start_date = wave_start,
-- end_date = wave_end, never more than 60 days). The Audit Record form is
-- assigned to the event so it installs on the auditor's phone at shift_create.
CREATE TABLE IF NOT EXISTS program_agents (
  program_agent_id INTEGER PRIMARY KEY AUTOINCREMENT,
  program_id INTEGER NOT NULL,
  agent_id INTEGER NOT NULL,
  visits_required INTEGER NOT NULL DEFAULT 1 CHECK (visits_required >= 0),
  zensched_event_id INTEGER,                        -- from event_create
  event_valid_until TEXT,                           -- ISO date: last day the event covers (= wave_end)
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (program_id) REFERENCES programs(program_id) ON DELETE CASCADE,
  FOREIGN KEY (agent_id) REFERENCES agents(agent_id) ON DELETE CASCADE,
  UNIQUE (program_id, agent_id)
);

-- Auditors: the independent-contractor pool. zensched_worker_id comes
-- from worker_invite. pay_handle (M-Pesa, bKash, JazzCash, bank nickname)
-- is LOCAL ONLY. Reliability is derived from visits (see auditor_reliability).
CREATE TABLE IF NOT EXISTS auditors (
  auditor_id INTEGER PRIMARY KEY AUTOINCREMENT,
  auditor_name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  phone TEXT,
  home_city TEXT,
  home_region TEXT,
  zensched_worker_id INTEGER UNIQUE,                -- from worker_invite
  pay_handle TEXT,                                  -- LOCAL ONLY: how you pay them
  is_active INTEGER DEFAULT 1,
  notes TEXT,                                       -- 'has motorbike', 'speaks Swahili and English'
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Visits: one row per shop audit the program requires. Created 'open' from
-- the quota, becomes 'assigned' when an auditor and a date/time slot are
-- chosen (one ZenSched shift), then 'completed' / 'no_show' / 'rejected' /
-- 'cancelled'. scheduled_* are shop-local wall-clock ('YYYY-MM-DDTHH:MM:SS',
-- no offset); checkin_at / checkout_at are ISO with offset as recorded from
-- ZenSched. duration_minutes is filled by trigger from the punches when left
-- NULL. float_count / branding_ok / photo URL columns are a local summary of
-- the Audit Record so later questions do not re-read submissions.
CREATE TABLE IF NOT EXISTS visits (
  visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
  program_agent_id INTEGER NOT NULL,
  auditor_id INTEGER,                               -- NULL until assigned
  scheduled_start TEXT                              -- shop-local, no offset
    CHECK (scheduled_start IS NULL OR scheduled_start GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]'),
  scheduled_end TEXT
    CHECK (scheduled_end IS NULL OR scheduled_end GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]'),
  zensched_shift_id INTEGER UNIQUE,                 -- from shift_create
  status TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'assigned', 'completed', 'no_show', 'rejected', 'cancelled')),
  submission_dc_id INTEGER,                         -- form submission_id
  checkin_at TEXT,                                  -- ISO with offset, from shift_status
  checkout_at TEXT,
  duration_minutes INTEGER,                         -- trigger fills from punches if NULL
  float_count REAL,                                 -- from Audit Record number field
  branding_ok TEXT                                  -- from Audit Record select; store the label
    CHECK (branding_ok IS NULL OR branding_ok IN ('Yes', 'No', 'Partial')),
  kyc_photo_urls TEXT,                              -- JSON array of KYC-poster media URLs
  shopfront_photo_urls TEXT,                        -- JSON array of shopfront media URLs
  qa_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (qa_status IN ('pending', 'approved', 'rejected')),
  qa_notes TEXT,                                    -- LOCAL ONLY
  client_invoiced INTEGER DEFAULT 0,
  auditor_paid INTEGER DEFAULT 0,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (program_agent_id) REFERENCES program_agents(program_agent_id) ON DELETE CASCADE,
  FOREIGN KEY (auditor_id) REFERENCES auditors(auditor_id) ON DELETE SET NULL
);

-- Invoices to clients. invoice_number is filled by trigger if left NULL.
-- line_items is a JSON array with one object per visit. Line items use
-- zensched_label, never agent_name or agent_code.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  program_id INTEGER,                               -- NULL when one invoice spans programs
  invoice_number TEXT UNIQUE,                       -- 'INV-2026-0001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  visit_count INTEGER,
  fees_amount REAL,                                 -- SUM(client_fee)
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  sent_date TEXT,
  line_items TEXT,                                  -- JSON array: one object per visit
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE,
  FOREIGN KEY (program_id) REFERENCES programs(program_id) ON DELETE SET NULL
);

-- Auditor payouts: one row per auditor per pay run. The agency pays
-- outside the kit (M-Pesa, bKash, bank); this is the record.
-- visit_ids is a JSON array.
CREATE TABLE IF NOT EXISTS auditor_payouts (
  payout_id INTEGER PRIMARY KEY AUTOINCREMENT,
  auditor_id INTEGER NOT NULL,
  period_start TEXT,
  period_end TEXT,
  visit_count INTEGER,
  fees_amount REAL,                                 -- SUM(auditor_fee)
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  visit_ids TEXT,                                   -- JSON array of visit_id
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (auditor_id) REFERENCES auditors(auditor_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_programs_client ON programs(client_id, status);
CREATE INDEX IF NOT EXISTS idx_agents_client ON agents(client_id);
CREATE INDEX IF NOT EXISTS idx_agents_zensched_location ON agents(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_agents_code ON agents(client_id, agent_code);
CREATE INDEX IF NOT EXISTS idx_program_agents_program ON program_agents(program_id);
CREATE INDEX IF NOT EXISTS idx_program_agents_agent ON program_agents(agent_id);
CREATE INDEX IF NOT EXISTS idx_program_agents_event ON program_agents(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_visits_program_agent ON visits(program_agent_id, status);
CREATE INDEX IF NOT EXISTS idx_visits_auditor ON visits(auditor_id, status);
CREATE INDEX IF NOT EXISTS idx_visits_scheduled ON visits(scheduled_start);
CREATE INDEX IF NOT EXISTS idx_visits_qa ON visits(qa_status, client_invoiced, auditor_paid);
CREATE INDEX IF NOT EXISTS idx_invoices_client ON invoices(client_id, paid);
CREATE INDEX IF NOT EXISTS idx_payouts_auditor ON auditor_payouts(auditor_id, paid);

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_client_timestamp
AFTER UPDATE ON clients
BEGIN
  UPDATE clients SET updated_at = datetime('now') WHERE client_id = NEW.client_id;
END;

CREATE TRIGGER IF NOT EXISTS update_program_timestamp
AFTER UPDATE ON programs
BEGIN
  UPDATE programs SET updated_at = datetime('now') WHERE program_id = NEW.program_id;
END;

CREATE TRIGGER IF NOT EXISTS update_agent_timestamp
AFTER UPDATE ON agents
BEGIN
  UPDATE agents SET updated_at = datetime('now') WHERE agent_id = NEW.agent_id;
END;

CREATE TRIGGER IF NOT EXISTS update_auditor_timestamp
AFTER UPDATE ON auditors
BEGIN
  UPDATE auditors SET updated_at = datetime('now') WHERE auditor_id = NEW.auditor_id;
END;

CREATE TRIGGER IF NOT EXISTS update_visit_timestamp
AFTER UPDATE ON visits
BEGIN
  UPDATE visits SET updated_at = datetime('now') WHERE visit_id = NEW.visit_id;
END;

-- Fill duration_minutes from the punches when the agent leaves it NULL, on
-- insert and whenever the punch columns change. Both stamps carry an offset,
-- so julianday arithmetic is exact even across midnight or time zones.
CREATE TRIGGER IF NOT EXISTS fill_visit_duration_insert
AFTER INSERT ON visits
WHEN NEW.duration_minutes IS NULL AND NEW.checkin_at IS NOT NULL AND NEW.checkout_at IS NOT NULL
BEGIN
  UPDATE visits
  SET duration_minutes = CAST(round((julianday(NEW.checkout_at) - julianday(NEW.checkin_at)) * 1440.0) AS INTEGER)
  WHERE visit_id = NEW.visit_id;
END;

CREATE TRIGGER IF NOT EXISTS fill_visit_duration_update
AFTER UPDATE OF checkin_at, checkout_at ON visits
WHEN NEW.duration_minutes IS NULL AND NEW.checkin_at IS NOT NULL AND NEW.checkout_at IS NOT NULL
BEGIN
  UPDATE visits
  SET duration_minutes = CAST(round((julianday(NEW.checkout_at) - julianday(NEW.checkin_at)) * 1440.0) AS INTEGER)
  WHERE visit_id = NEW.visit_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Unassigned visits in active programs, with everything the agent needs to
-- propose an assignment: shop label (not the real name), city, tz, the
-- daily window, allowed weekdays, and how many days remain in the wave.
-- agent_name / agent_code are included so the OWNER can identify the shop;
-- they must never go into a ZenSched field.
CREATE VIEW IF NOT EXISTS visits_open AS
SELECT
  v.visit_id,
  p.program_id,
  p.program_name,
  c.client_name,
  a.agent_id,
  a.agent_name,
  a.agent_code,
  a.address,
  a.city,
  a.region,
  a.tz_offset,
  a.zensched_label,
  a.zensched_location_id,
  pa.program_agent_id,
  pa.zensched_event_id,
  p.wave_start,
  p.wave_end,
  p.window_start_time,
  p.window_end_time,
  p.allowed_weekdays,
  p.min_minutes,
  p.auditor_fee,
  p.auditor_brief,
  CAST(julianday(p.wave_end) - julianday(date('now')) AS INTEGER) AS days_until_wave_end
FROM visits v
JOIN program_agents pa ON pa.program_agent_id = v.program_agent_id
JOIN programs p        ON p.program_id = pa.program_id
JOIN agents a          ON a.agent_id = pa.agent_id
JOIN clients c         ON c.client_id = p.client_id
WHERE v.status = 'open'
  AND p.status = 'active'
  AND pa.is_active = 1
ORDER BY p.wave_end, a.city, a.zensched_label;

-- Assigned visits in the next 7 days (today + 6, by shop-local date). One
-- row = one shift_create call (if zensched_shift_id is NULL) or one shift to
-- watch. start_iso / end_iso use the AGENT's tz_offset. needs_location /
-- needs_event mean the shop or the program-agent row has not been set up on
-- ZenSched yet.
CREATE VIEW IF NOT EXISTS visits_upcoming AS
SELECT
  v.visit_id,
  v.status,
  p.program_id,
  p.program_name,
  c.client_name,
  a.agent_id,
  a.agent_name,
  a.agent_code,
  a.address,
  a.city,
  a.tz_offset,
  a.zensched_label,
  a.zensched_location_id,
  pa.program_agent_id,
  pa.zensched_event_id,
  pa.event_valid_until,
  au.auditor_id,
  au.auditor_name,
  au.zensched_worker_id                              AS worker_id,
  v.scheduled_start,
  v.scheduled_end,
  v.scheduled_start || a.tz_offset                   AS start_iso,
  v.scheduled_end   || a.tz_offset                   AS end_iso,
  'shift-visit-' || v.visit_id                       AS idempotency_key,
  v.zensched_shift_id,
  CASE WHEN a.zensched_location_id IS NULL THEN 1 ELSE 0 END AS needs_location,
  CASE WHEN pa.zensched_event_id IS NULL
         OR pa.event_valid_until IS NULL
         OR pa.event_valid_until < date(v.scheduled_start) THEN 1 ELSE 0 END AS needs_event,
  p.auditor_brief
FROM visits v
JOIN program_agents pa ON pa.program_agent_id = v.program_agent_id
JOIN programs p        ON p.program_id = pa.program_id
JOIN agents a          ON a.agent_id = pa.agent_id
JOIN clients c         ON c.client_id = p.client_id
LEFT JOIN auditors au  ON au.auditor_id = v.auditor_id
WHERE v.status = 'assigned'
  AND date(v.scheduled_start) BETWEEN date('now') AND date('now', '+6 days')
ORDER BY v.scheduled_start, a.city;

-- Assigned visits whose slot has already ended (shop-local, compared in UTC)
-- with no result recorded. Either the auditor did it and results have
-- not been pulled, or it is a no-show.
CREATE VIEW IF NOT EXISTS visits_overdue AS
SELECT
  v.visit_id,
  p.program_id,
  p.program_name,
  c.client_name,
  a.zensched_label,
  a.agent_name,
  a.agent_code,
  a.address,
  a.city,
  a.tz_offset,
  pa.zensched_event_id,
  au.auditor_id,
  au.auditor_name,
  au.zensched_worker_id                              AS worker_id,
  v.scheduled_start,
  v.scheduled_end,
  v.zensched_shift_id,
  CAST((julianday('now') - julianday(v.scheduled_end || a.tz_offset)) * 24 AS INTEGER) AS hours_overdue
FROM visits v
JOIN program_agents pa ON pa.program_agent_id = v.program_agent_id
JOIN programs p        ON p.program_id = pa.program_id
JOIN agents a          ON a.agent_id = pa.agent_id
JOIN clients c         ON c.client_id = p.client_id
LEFT JOIN auditors au  ON au.auditor_id = v.auditor_id
WHERE v.status = 'assigned'
  AND v.scheduled_end IS NOT NULL
  AND julianday(v.scheduled_end || a.tz_offset) < julianday('now')
ORDER BY v.scheduled_end;

-- Completed visits with a quality signal, for QA to look at first:
--   checkin_late     check-in after the assigned slot ended
--   checkin_early    check-in more than 15 minutes before the slot started
--   no_checkin       completed (form in) but no GPS check-in recorded
--   short_visit      duration below the program's min_minutes
--   branding_issue   branding_ok is No or Partial
-- On-time visits with a normal duration and branding Yes do not appear here.
CREATE VIEW IF NOT EXISTS visits_flagged AS
SELECT
  v.visit_id,
  p.program_id,
  p.program_name,
  c.client_name,
  a.zensched_label,
  a.agent_name,
  a.agent_code,
  a.address,
  a.city,
  a.tz_offset,
  au.auditor_id,
  au.auditor_name,
  v.scheduled_start,
  v.scheduled_end,
  v.checkin_at,
  v.checkout_at,
  v.duration_minutes,
  p.min_minutes,
  v.float_count,
  v.branding_ok,
  v.submission_dc_id,
  v.zensched_shift_id,
  v.qa_status,
  CASE WHEN v.checkin_at IS NOT NULL
        AND julianday(v.checkin_at) > julianday(v.scheduled_end || a.tz_offset) THEN 1 ELSE 0 END AS checkin_late,
  CASE WHEN v.checkin_at IS NOT NULL
        AND julianday(v.checkin_at) < julianday(v.scheduled_start || a.tz_offset, '-15 minutes') THEN 1 ELSE 0 END AS checkin_early,
  CASE WHEN v.checkin_at IS NULL THEN 1 ELSE 0 END AS no_checkin,
  CASE WHEN v.duration_minutes IS NOT NULL AND v.duration_minutes < COALESCE(p.min_minutes, 0) THEN 1 ELSE 0 END AS short_visit,
  CASE WHEN v.branding_ok IN ('No', 'Partial') THEN 1 ELSE 0 END AS branding_issue,
  CAST(round((julianday(v.checkin_at) - julianday(v.scheduled_end || a.tz_offset)) * 1440.0) AS INTEGER) AS minutes_after_slot_end
FROM visits v
JOIN program_agents pa ON pa.program_agent_id = v.program_agent_id
JOIN programs p        ON p.program_id = pa.program_id
JOIN agents a          ON a.agent_id = pa.agent_id
JOIN clients c         ON c.client_id = p.client_id
LEFT JOIN auditors au  ON au.auditor_id = v.auditor_id
WHERE v.status = 'completed'
  AND (
       v.checkin_at IS NULL
    OR julianday(v.checkin_at) > julianday(v.scheduled_end || a.tz_offset)
    OR julianday(v.checkin_at) < julianday(v.scheduled_start || a.tz_offset, '-15 minutes')
    OR (v.duration_minutes IS NOT NULL AND v.duration_minutes < COALESCE(p.min_minutes, 0))
    OR v.branding_ok IN ('No', 'Partial')
  )
ORDER BY CASE v.qa_status WHEN 'pending' THEN 0 ELSE 1 END, v.scheduled_start;

-- One row per program: how many visits are required, assigned, completed,
-- approved, percent complete (approved / required), and days left in the wave.
CREATE VIEW IF NOT EXISTS program_progress AS
SELECT
  p.program_id,
  p.program_name,
  c.client_name,
  p.status,
  p.wave_start,
  p.wave_end,
  CAST(julianday(p.wave_end) - julianday(date('now')) AS INTEGER)            AS days_left,
  (SELECT COUNT(*) FROM program_agents pa WHERE pa.program_id = p.program_id AND pa.is_active = 1) AS agent_count,
  (SELECT COALESCE(SUM(pa.visits_required), 0) FROM program_agents pa WHERE pa.program_id = p.program_id AND pa.is_active = 1) AS visits_required,
  (SELECT COUNT(*) FROM visits v JOIN program_agents pa ON pa.program_agent_id = v.program_agent_id
     WHERE pa.program_id = p.program_id AND v.status = 'open')               AS visits_open,
  (SELECT COUNT(*) FROM visits v JOIN program_agents pa ON pa.program_agent_id = v.program_agent_id
     WHERE pa.program_id = p.program_id AND v.status = 'assigned')           AS visits_assigned,
  (SELECT COUNT(*) FROM visits v JOIN program_agents pa ON pa.program_agent_id = v.program_agent_id
     WHERE pa.program_id = p.program_id AND v.status = 'completed')          AS visits_completed,
  (SELECT COUNT(*) FROM visits v JOIN program_agents pa ON pa.program_agent_id = v.program_agent_id
     WHERE pa.program_id = p.program_id AND v.status = 'completed' AND v.qa_status = 'approved') AS visits_approved,
  (SELECT COUNT(*) FROM visits v JOIN program_agents pa ON pa.program_agent_id = v.program_agent_id
     WHERE pa.program_id = p.program_id AND v.status = 'no_show')            AS visits_no_show,
  (SELECT COUNT(*) FROM visits v JOIN program_agents pa ON pa.program_agent_id = v.program_agent_id
     WHERE pa.program_id = p.program_id AND v.status = 'completed' AND v.qa_status = 'pending') AS visits_qa_pending,
  CASE WHEN (SELECT COALESCE(SUM(pa.visits_required), 0) FROM program_agents pa WHERE pa.program_id = p.program_id AND pa.is_active = 1) = 0 THEN 0
       ELSE round(100.0 *
            (SELECT COUNT(*) FROM visits v JOIN program_agents pa ON pa.program_agent_id = v.program_agent_id
               WHERE pa.program_id = p.program_id AND v.status = 'completed' AND v.qa_status = 'approved')
            / (SELECT SUM(pa.visits_required) FROM program_agents pa WHERE pa.program_id = p.program_id AND pa.is_active = 1), 1)
  END AS pct_complete
FROM programs p
JOIN clients c ON c.client_id = p.client_id
ORDER BY p.status = 'active' DESC, p.wave_end;

-- Approved visits not yet invoiced, grouped by client.
CREATE VIEW IF NOT EXISTS visits_to_invoice AS
SELECT
  c.client_id,
  c.client_name,
  c.billing_email,
  c.payment_terms_days,
  COUNT(v.visit_id)                                   AS visit_count,
  COUNT(DISTINCT p.program_id)                        AS program_count,
  SUM(p.client_fee)                                   AS fees_amount,
  SUM(p.client_fee)                                   AS total_amount,
  MIN(date(v.scheduled_start))                        AS first_visit_date,
  MAX(date(v.scheduled_start))                        AS last_visit_date
FROM visits v
JOIN program_agents pa ON pa.program_agent_id = v.program_agent_id
JOIN programs p        ON p.program_id = pa.program_id
JOIN clients c         ON c.client_id = p.client_id
WHERE v.status = 'completed'
  AND v.qa_status = 'approved'
  AND v.client_invoiced = 0
GROUP BY c.client_id
ORDER BY c.client_name;

-- Approved visits not yet paid to the auditor, grouped by auditor.
CREATE VIEW IF NOT EXISTS auditor_pay_due AS
SELECT
  au.auditor_id,
  au.auditor_name,
  au.email,
  au.pay_handle,
  COUNT(v.visit_id)                                   AS visit_count,
  SUM(p.auditor_fee)                                  AS fees_amount,
  SUM(p.auditor_fee)                                  AS total_due,
  MIN(date(v.scheduled_start))                        AS first_visit_date,
  MAX(date(v.scheduled_start))                        AS last_visit_date,
  json_group_array(v.visit_id)                        AS visit_ids
FROM visits v
JOIN program_agents pa ON pa.program_agent_id = v.program_agent_id
JOIN programs p        ON p.program_id = pa.program_id
JOIN auditors au       ON au.auditor_id = v.auditor_id
WHERE v.status = 'completed'
  AND v.qa_status = 'approved'
  AND v.auditor_paid = 0
GROUP BY au.auditor_id
ORDER BY au.auditor_name;

-- Per auditor: how many visits they were given, completed, no-showed,
-- had rejected, and what share of their visits (completed or rejected) had
-- an on-time check-in (within 15 minutes before the slot start and before
-- the slot end). Use this when deciding who gets the next assignment.
CREATE VIEW IF NOT EXISTS auditor_reliability AS
SELECT
  au.auditor_id,
  au.auditor_name,
  au.home_city,
  au.is_active,
  COUNT(v.visit_id) FILTER (WHERE v.status IN ('assigned', 'completed', 'no_show', 'rejected')) AS visits_given,
  COUNT(v.visit_id) FILTER (WHERE v.status = 'completed')                                        AS completed,
  COUNT(v.visit_id) FILTER (WHERE v.status = 'completed' AND v.qa_status = 'approved')           AS approved,
  COUNT(v.visit_id) FILTER (WHERE v.status = 'no_show')                                          AS no_shows,
  COUNT(v.visit_id) FILTER (WHERE v.status = 'rejected' OR (v.status = 'completed' AND v.qa_status = 'rejected')) AS rejected,
  COUNT(v.visit_id) FILTER (WHERE v.status = 'assigned')                                         AS upcoming,
  CASE WHEN COUNT(v.visit_id) FILTER (WHERE v.status IN ('completed', 'rejected') AND v.checkin_at IS NOT NULL) = 0 THEN NULL
       ELSE round(100.0 *
            COUNT(v.visit_id) FILTER (WHERE v.status IN ('completed', 'rejected') AND v.checkin_at IS NOT NULL
                                        AND julianday(v.checkin_at) >= julianday(v.scheduled_start || a.tz_offset, '-15 minutes')
                                        AND julianday(v.checkin_at) <= julianday(v.scheduled_end || a.tz_offset))
            / COUNT(v.visit_id) FILTER (WHERE v.status IN ('completed', 'rejected') AND v.checkin_at IS NOT NULL), 1)
  END AS on_time_pct,
  MAX(date(v.scheduled_start)) FILTER (WHERE v.status = 'completed')                             AS last_completed_date
FROM auditors au
LEFT JOIN visits v          ON v.auditor_id = au.auditor_id
LEFT JOIN program_agents pa ON pa.program_agent_id = v.program_agent_id
LEFT JOIN agents a          ON a.agent_id = pa.agent_id
GROUP BY au.auditor_id
ORDER BY au.is_active DESC, no_shows, au.auditor_name;

-- Unpaid client invoices with aging.
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  i.invoice_id,
  i.invoice_number,
  c.client_name,
  c.billing_email,
  i.invoice_date,
  i.due_date,
  i.visit_count,
  i.total_amount,
  i.sent_date,
  CASE WHEN i.due_date < date('now') THEN 1 ELSE 0 END AS overdue,
  CASE WHEN i.due_date >= date('now') THEN 0
       ELSE CAST(julianday(date('now')) - julianday(i.due_date) AS INTEGER) END AS days_overdue,
  CASE WHEN i.due_date >= date('now') THEN 'current'
       WHEN julianday(date('now')) - julianday(i.due_date) <= 30 THEN '1-30'
       WHEN julianday(date('now')) - julianday(i.due_date) <= 60 THEN '31-60'
       WHEN julianday(date('now')) - julianday(i.due_date) <= 90 THEN '61-90'
       ELSE '90+' END AS aging_bucket
FROM invoices i
JOIN clients c ON c.client_id = i.client_id
WHERE i.paid = 0
ORDER BY i.due_date;
