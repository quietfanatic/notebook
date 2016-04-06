CREATE TABLE pages (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    committed BOOLEAN NOT NULL DEFAULT 0,  -- This row becomes immutable
    deleted BOOLEAN NOT NULL DEFAULT 0,
    prev_id INTEGER REFERENCES pages (id),
    path VARCHAR NOT NULL,
    title VARCHAR,
    html VARCHAR,
    originated_at TEXT  -- Of whatever this represents if not itself
);
CREATE TABLE links (  -- Links are committed when their from page is committed
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    deleted BOOLEAN NOT NULL DEFAULT 0,
    prev_id INTEGER REFERENCES links (id),
    rel VARCHAR NOT NULL,
    from_id INTEGER NOT NULL REFERENCES pages (id),
    to_path VARCHAR NOT NULL REFERENCES pages (path)
);
CREATE INDEX path_index ON pages (path, id DESC);
CREATE INDEX from_index ON links (from_id);
CREATE INDEX to_index ON links (to_id);
