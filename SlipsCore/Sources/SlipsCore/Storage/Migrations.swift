import GRDB

/// Append-only schema history. Never edit a migration that has shipped; add `v2_…`, `v3_…`.
enum Migrations {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: v1Initial)
        }
        migrator.registerMigration("v2_fts") { db in
            try db.execute(sql: v2FTS)
        }
    }

    /// Plan §3. Ids are UUIDs (16-byte blobs, GRDB's default), dates are GRDB date strings (UTC),
    /// `txn_date` is a calendar day `YYYY-MM-DD`, amounts are integer minor units.
    static let v1Initial = """
        CREATE TABLE profiles (
            id BLOB PRIMARY KEY NOT NULL,
            name TEXT NOT NULL CHECK (length(trim(name)) > 0),
            mode TEXT NOT NULL DEFAULT 'local' CHECK (mode IN ('local', 'fin')),
            fin_base_url TEXT,
            fin_workspace_id TEXT,
            fin_device_id TEXT,
            fin_user_display TEXT,
            created_at TEXT NOT NULL
        );

        CREATE TABLE enterprises (
            id BLOB PRIMARY KEY NOT NULL,
            profile_id BLOB NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            name TEXT NOT NULL CHECK (length(trim(name)) > 0),
            remote_id TEXT,
            archived_at TEXT
        );
        CREATE INDEX enterprises_profile ON enterprises(profile_id);

        CREATE TABLE subcategories (
            id BLOB PRIMARY KEY NOT NULL,
            profile_id BLOB NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            kind TEXT NOT NULL CHECK (kind IN ('personal', 'family', 'enterprise', 'any')),
            name_key TEXT,
            custom_name TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            remote_id TEXT,
            archived_at TEXT,
            CHECK (name_key IS NOT NULL OR length(trim(custom_name)) > 0)
        );
        CREATE INDEX subcategories_profile ON subcategories(profile_id, kind, sort_order);
        CREATE UNIQUE INDEX subcategories_key ON subcategories(profile_id, name_key) WHERE name_key IS NOT NULL;

        CREATE TABLE payment_methods (
            id BLOB PRIMARY KEY NOT NULL,
            profile_id BLOB NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            name TEXT NOT NULL CHECK (length(trim(name)) > 0),
            type TEXT NOT NULL CHECK (type IN ('credit_card', 'debit', 'chequing', 'cash', 'other')),
            last4 TEXT CHECK (last4 IS NULL OR (length(last4) = 4 AND last4 NOT GLOB '*[^0-9]*')),
            currency TEXT NOT NULL CHECK (length(currency) = 3),
            default_kind TEXT CHECK (default_kind IS NULL OR default_kind IN ('personal', 'family', 'enterprise')),
            default_enterprise_id BLOB REFERENCES enterprises(id),
            remote_id TEXT,
            archived_at TEXT
        );
        CREATE INDEX payment_methods_profile ON payment_methods(profile_id);

        CREATE TABLE slips (
            id BLOB PRIMARY KEY NOT NULL,
            profile_id BLOB NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'ready', 'archived')),
            captured_at TEXT NOT NULL,
            pdf_path TEXT NOT NULL,
            pdf_sha256 TEXT NOT NULL CHECK (length(pdf_sha256) = 64),
            page_count INTEGER NOT NULL CHECK (page_count > 0),
            ocr_text TEXT,
            extracted TEXT,
            merchant TEXT,
            txn_date TEXT,
            currency TEXT NOT NULL DEFAULT 'CAD' CHECK (length(currency) = 3),
            subtotal INTEGER,
            gst INTEGER,
            qst INTEGER,
            hst INTEGER,
            tip INTEGER,
            total INTEGER,
            supplier_gst_no TEXT,
            supplier_qst_no TEXT,
            kind TEXT CHECK (kind IS NULL OR kind IN ('personal', 'family', 'enterprise')),
            enterprise_id BLOB REFERENCES enterprises(id),
            subcategory_id BLOB REFERENCES subcategories(id),
            payment_method_id BLOB REFERENCES payment_methods(id),
            notes TEXT,
            checks TEXT,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX slips_profile_date ON slips(profile_id, txn_date);

        CREATE TABLE merchant_memory (
            profile_id BLOB NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            merchant_norm TEXT NOT NULL CHECK (length(merchant_norm) > 0),
            kind TEXT CHECK (kind IS NULL OR kind IN ('personal', 'family', 'enterprise')),
            enterprise_id BLOB REFERENCES enterprises(id),
            subcategory_id BLOB REFERENCES subcategories(id),
            payment_method_id BLOB REFERENCES payment_methods(id),
            uses INTEGER NOT NULL DEFAULT 0 CHECK (uses >= 0),
            last_used_at TEXT NOT NULL,
            PRIMARY KEY (profile_id, merchant_norm)
        );
        CREATE INDEX merchant_memory_lookup ON merchant_memory(profile_id, merchant_norm);

        CREATE TABLE destinations (
            id BLOB PRIMARY KEY NOT NULL,
            profile_id BLOB NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            type TEXT NOT NULL CHECK (type IN ('library', 'icloud', 'folder', 'webdav', 'fin', 'dropbox', 'onedrive', 'gdrive')),
            name TEXT NOT NULL CHECK (length(trim(name)) > 0),
            config TEXT NOT NULL DEFAULT '{}',
            naming_rule TEXT NOT NULL,
            wifi_only INTEGER NOT NULL DEFAULT 0 CHECK (wifi_only IN (0, 1)),
            enabled INTEGER NOT NULL DEFAULT 0 CHECK (enabled IN (0, 1))
        );
        CREATE INDEX destinations_profile ON destinations(profile_id);

        CREATE TABLE deliveries (
            slip_id BLOB NOT NULL REFERENCES slips(id) ON DELETE CASCADE,
            destination_id BLOB NOT NULL REFERENCES destinations(id) ON DELETE CASCADE,
            status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_flight', 'done', 'failed', 'needs_auth')),
            attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
            next_attempt_at TEXT,
            last_error_code TEXT,
            remote_ref TEXT,
            delivered_sha256 TEXT,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (slip_id, destination_id)
        );
        CREATE INDEX deliveries_due ON deliveries(status, next_attempt_at);
        """

    /// Full-text search over merchant, notes and OCR text (plan P11). External content on `slips`,
    /// kept in step by triggers; accents ignored, so "epicerie" finds "Épicerie".
    static let v2FTS = """
        CREATE VIRTUAL TABLE slips_fts USING fts5(
            merchant, notes, ocr_text,
            content = 'slips', content_rowid = 'rowid',
            tokenize = 'unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER slips_fts_insert AFTER INSERT ON slips BEGIN
            INSERT INTO slips_fts(rowid, merchant, notes, ocr_text) VALUES (new.rowid, new.merchant, new.notes, new.ocr_text);
        END;
        CREATE TRIGGER slips_fts_delete AFTER DELETE ON slips BEGIN
            INSERT INTO slips_fts(slips_fts, rowid, merchant, notes, ocr_text) VALUES ('delete', old.rowid, old.merchant, old.notes, old.ocr_text);
        END;
        CREATE TRIGGER slips_fts_update AFTER UPDATE OF merchant, notes, ocr_text ON slips BEGIN
            INSERT INTO slips_fts(slips_fts, rowid, merchant, notes, ocr_text) VALUES ('delete', old.rowid, old.merchant, old.notes, old.ocr_text);
            INSERT INTO slips_fts(rowid, merchant, notes, ocr_text) VALUES (new.rowid, new.merchant, new.notes, new.ocr_text);
        END;
        INSERT INTO slips_fts(slips_fts) VALUES ('rebuild');
        """
}
