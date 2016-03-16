CREATE TABLE items (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    created_at INTEGER NOT NULL,
    originated_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    path VARCHAR NOT NULL,
    title VARCHAR,
    html VARCHAR,
    deleted BOOLEAN NOT NULL DEFAULT 0,
    prev_id INTEGER REFERENCES items (id)
);
CREATE TABLE links (
    id INTEGER PRIMARY KEY NOT NULL,
    rel VARCHAR NOT NULL,
    from_id INTEGER NOT NULL REFERENCES items (id),
    to_id INTEGER NOT NULL REFERENCES items (id),
    obsolete BOOLEAN NOT NULL DEFAULT 0
);
CREATE INDEX path_index ON items (path, updated_at);
