PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS accounts (
 id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE, password TEXT NOT NULL,
 verified INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS codes (
 account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 purpose TEXT NOT NULL, digest TEXT NOT NULL, expires_at INTEGER NOT NULL,
 attempts INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(account_id,purpose)
);
CREATE TABLE IF NOT EXISTS devices (
 id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 name TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE,
 created_at INTEGER NOT NULL, last_seen INTEGER NOT NULL, expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS device_owner ON devices(account_id);
CREATE TABLE IF NOT EXISTS saves (
 id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 name TEXT NOT NULL, kind TEXT NOT NULL, metadata TEXT NOT NULL,
 head TEXT, updated_at INTEGER NOT NULL, deleted_at INTEGER, client_id TEXT,
 UNIQUE(account_id,client_id)
);
CREATE INDEX IF NOT EXISTS save_owner ON saves(account_id);
CREATE TABLE IF NOT EXISTS versions (
 revision TEXT PRIMARY KEY, save_id TEXT NOT NULL REFERENCES saves(id) ON DELETE CASCADE,
 blob TEXT NOT NULL, size INTEGER NOT NULL, sha256 TEXT NOT NULL, metadata TEXT NOT NULL,
 device_name TEXT NOT NULL, created_at INTEGER NOT NULL, sequence INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS version_save ON versions(save_id,sequence);
CREATE TABLE IF NOT EXISTS uploads (
 id TEXT PRIMARY KEY, save_id TEXT NOT NULL REFERENCES saves(id) ON DELETE CASCADE,
 base_revision TEXT, size INTEGER NOT NULL, sha256 TEXT NOT NULL, metadata TEXT NOT NULL,
 device_name TEXT NOT NULL, expires_at INTEGER NOT NULL, committed TEXT
);
CREATE INDEX IF NOT EXISTS upload_save ON uploads(save_id);
CREATE TABLE IF NOT EXISTS chunks (
 upload_id TEXT NOT NULL REFERENCES uploads(id) ON DELETE CASCADE,
 idx INTEGER NOT NULL, size INTEGER NOT NULL, sha256 TEXT NOT NULL,
 PRIMARY KEY(upload_id,idx)
);
CREATE TABLE IF NOT EXISTS rate_limits (
 bucket TEXT PRIMARY KEY, count INTEGER NOT NULL, expires_at INTEGER NOT NULL
);
