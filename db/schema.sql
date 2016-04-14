CREATE TABLE pages (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    created_at VARCHAR NOT NULL,
    updated_at VARCHAR NOT NULL,
    committed BOOLEAN NOT NULL DEFAULT 0,  -- This row becomes immutable
    obsolete BOOLEAN NOT NULL DEFAULT 0,    -- (except for this flag)
    prev_id INTEGER REFERENCES pages (id),
    path VARCHAR NOT NULL,
    title TEXT,
    html TEXT,
    originated_at VARCHAR  -- Of whatever this represents if not itself
);
CREATE TABLE links (
     -- Links inherit committed and obsolete from their from page
      -- Should we cache them here anyway?
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    from_id INTEGER NOT NULL REFERENCES pages (id),
    rel VARCHAR NOT NULL,
    to_path VARCHAR NOT NULL REFERENCES pages (path)
);
CREATE UNIQUE INDEX paths_committed ON pages (path) WHERE NOT obsolete AND committed;
CREATE UNIQUE INDEX paths_uncommitted ON pages (path) WHERE NOT obsolete AND NOT committed;
CREATE INDEX from_index ON links (from_id);
CREATE INDEX to_index ON links (to_path);
