-- =============================================================================
-- TMDB TV Shows – Import Script
-- RDBMS  : PostgreSQL 16
-- Strategie: Staging tabel → COPY (bulk) → normalisatie naar eindtabellen
-- =============================================================================
-- Gebruik:
--   1. Kopieer de CSV naar de container:
--        docker cp TMDB_tv_dataset_v3.csv tmdb_postgres:/tmp/TMDB_tv_dataset_v3.csv
--   2. Voer dit script uit:
--        docker exec -i tmdb_postgres psql -U tmdb_admin -d tmdb < db/import_full_dataset.sql
-- =============================================================================

BEGIN;

-- =============================================================================
-- STAP 1: Staging-tabel aanmaken
-- Alle kolommen zijn TEXT zodat COPY nooit faalt op type-mismatch.
-- Lege strings ("") worden later door NULLIF omgezet naar NULL.
-- =============================================================================

DROP TABLE IF EXISTS staging_shows;

CREATE UNLOGGED TABLE staging_shows (
    id                   TEXT,
    name                 TEXT,
    number_of_seasons    TEXT,
    number_of_episodes   TEXT,
    original_language    TEXT,   -- genegeerd (verwijderd uit schema)
    vote_count           TEXT,
    vote_average         TEXT,
    overview             TEXT,
    adult                TEXT,
    backdrop_path        TEXT,
    first_air_date       TEXT,
    last_air_date        TEXT,
    homepage             TEXT,
    in_production        TEXT,
    original_name        TEXT,
    popularity           TEXT,
    poster_path          TEXT,
    type                 TEXT,
    status               TEXT,
    tagline              TEXT,
    genres               TEXT,   -- komma-gescheiden: "Drama, Crime"
    created_by           TEXT,   -- komma-gescheiden: "David Benioff, D.B. Weiss"
    languages            TEXT,   -- komma-gescheiden ISO-codes: "en, ko"
    networks             TEXT,   -- komma-gescheiden: "HBO, Netflix"
    origin_country       TEXT,   -- genegeerd (niet in schema)
    spoken_languages     TEXT,   -- genegeerd (niet in schema)
    production_companies TEXT,   -- komma-gescheiden
    production_countries TEXT,   -- komma-gescheiden
    episode_run_time     TEXT
);

-- =============================================================================
-- STAP 2: COPY – laad de ruwe CSV in één keer in de staging-tabel
-- =============================================================================

COPY staging_shows (
    id, name, number_of_seasons, number_of_episodes, original_language,
    vote_count, vote_average, overview, adult, backdrop_path,
    first_air_date, last_air_date, homepage, in_production, original_name,
    popularity, poster_path, type, status, tagline,
    genres, created_by, languages, networks, origin_country,
    spoken_languages, production_companies, production_countries, episode_run_time
)
FROM '/tmp/TMDB_tv_dataset_v3.csv'
WITH (
    FORMAT CSV,
    HEADER TRUE,
    QUOTE '"',
    DELIMITER ',',
    ENCODING 'UTF8',
    NULL ''
);


-- =============================================================================
-- STAP 3: Verwijder duplicaten uit staging
-- (CSV bevat soms dubbele id's bij hernummerde seizoenen)
-- Behoud de rij met het hoogste vote_count per id.
-- =============================================================================

DELETE FROM staging_shows s
USING (
    SELECT ctid,
           ROW_NUMBER() OVER (
               PARTITION BY id
               ORDER BY CAST(NULLIF(vote_count, '') AS INT) DESC NULLS LAST, ctid
           ) AS row_number
    FROM staging_shows
) duplicate_rows
WHERE s.ctid = duplicate_rows.ctid
  AND duplicate_rows.row_number > 1;


-- =============================================================================
-- STAP 4: Normalisatie – vul de dimensie-tabellen
-- =============================================================================

-- ── languages ────────────────────────────────────────────────────────────────
-- Veld: "en, ko, ur"  →  split op ", "  →  INSERT IGNORE via ON CONFLICT
INSERT INTO languages (code)
SELECT DISTINCT TRIM(lang)
FROM staging_shows,
     LATERAL unnest(string_to_array(languages, ',')) AS t(lang)
WHERE NULLIF(TRIM(lang), '') IS NOT NULL
ON CONFLICT (code) DO NOTHING;

-- ── genres ───────────────────────────────────────────────────────────────────
INSERT INTO genres (name)
SELECT DISTINCT TRIM(g)
FROM staging_shows,
     LATERAL unnest(string_to_array(genres, ',')) AS t(g)
WHERE NULLIF(TRIM(g), '') IS NOT NULL
ON CONFLICT (name) DO NOTHING;

-- ── networks ─────────────────────────────────────────────────────────────────
INSERT INTO networks (name)
SELECT DISTINCT TRIM(n)
FROM staging_shows,
     LATERAL unnest(string_to_array(networks, ',')) AS t(n)
WHERE NULLIF(TRIM(n), '') IS NOT NULL
ON CONFLICT (name) DO NOTHING;

-- ── production_companies ──────────────────────────────────────────────────────
INSERT INTO production_companies (name)
SELECT DISTINCT TRIM(pc)
FROM staging_shows,
     LATERAL unnest(string_to_array(production_companies, ',')) AS t(pc)
WHERE NULLIF(TRIM(pc), '') IS NOT NULL
ON CONFLICT (name) DO NOTHING;

-- ── production_countries ──────────────────────────────────────────────────────
INSERT INTO production_countries (name)
SELECT DISTINCT TRIM(c)
FROM staging_shows,
     LATERAL unnest(string_to_array(production_countries, ',')) AS t(c)
WHERE NULLIF(TRIM(c), '') IS NOT NULL
ON CONFLICT (name) DO NOTHING;

-- ── creators ─────────────────────────────────────────────────────────────────
INSERT INTO creators (name)
SELECT DISTINCT TRIM(cr)
FROM staging_shows,
     LATERAL unnest(string_to_array(created_by, ',')) AS t(cr)
WHERE NULLIF(TRIM(cr), '') IS NOT NULL
ON CONFLICT (name) DO NOTHING;


-- =============================================================================
-- STAP 5: Vul de kern-tabel shows
-- =============================================================================

INSERT INTO shows (
    id,
    name,
    original_name,
    number_of_seasons,
    number_of_episodes,
    vote_count,
    vote_average,
    overview,
    tagline,
    adult,
    backdrop_path,
    poster_path,
    homepage,
    first_air_date,
    last_air_date,
    in_production,
    popularity,
    episode_run_time,
    status,
    type
)
SELECT DISTINCT ON (id::BIGINT)
    id::BIGINT,
    name,
    NULLIF(TRIM(original_name), ''),
    NULLIF(number_of_seasons, '')::INT,
    NULLIF(number_of_episodes, '')::INT,
    COALESCE(NULLIF(vote_count, '')::INT, 0),
    LEAST(COALESCE(NULLIF(vote_average, '')::NUMERIC, 0), 10),
    NULLIF(TRIM(overview), ''),
    NULLIF(TRIM(tagline),  ''),
    -- Python/pandas schrijft 'True'/'False'; normaliseren naar boolean
    CASE UPPER(TRIM(adult))
        WHEN 'TRUE'  THEN TRUE
        WHEN '1'     THEN TRUE
        ELSE FALSE
    END,
    NULLIF(TRIM(backdrop_path), ''),
    NULLIF(TRIM(poster_path),   ''),
    NULLIF(TRIM(homepage),      ''),
    -- Lege datumstrings → NULL.
    -- Zet last_air_date op NULL als het vóór first_air_date valt (dirty data).
    NULLIF(TRIM(first_air_date), '')::DATE,
    CASE
        WHEN NULLIF(TRIM(last_air_date), '') IS NULL THEN NULL
        WHEN NULLIF(TRIM(first_air_date), '') IS NULL THEN NULLIF(TRIM(last_air_date), '')::DATE
        WHEN NULLIF(TRIM(last_air_date), '')::DATE >= NULLIF(TRIM(first_air_date), '')::DATE
             THEN NULLIF(TRIM(last_air_date), '')::DATE
        ELSE NULL   -- last < first → ongeldige datum, negeer
    END,
    CASE UPPER(TRIM(in_production))
        WHEN 'TRUE' THEN TRUE
        WHEN '1'    THEN TRUE
        ELSE FALSE
    END,
    NULLIF(popularity, '')::NUMERIC(12,3),
    -- episode_run_time 0 → bewaar als 0 (schema CHECK >= 0 staat dit toe)
    NULLIF(episode_run_time, '')::INT,
    -- ENUM: cast alleen als de waarde niet leeg is
    NULLIF(TRIM(status), '')::show_status,
    NULLIF(TRIM(type),   '')::show_type
FROM staging_shows
ORDER BY id::BIGINT, NULLIF(vote_count, '')::INT DESC NULLS LAST
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    original_name = EXCLUDED.original_name,
    number_of_seasons = EXCLUDED.number_of_seasons,
    number_of_episodes = EXCLUDED.number_of_episodes,
    vote_count = EXCLUDED.vote_count,
    vote_average = EXCLUDED.vote_average,
    overview = EXCLUDED.overview,
    tagline = EXCLUDED.tagline,
    adult = EXCLUDED.adult,
    backdrop_path = EXCLUDED.backdrop_path,
    poster_path = EXCLUDED.poster_path,
    homepage = EXCLUDED.homepage,
    first_air_date = EXCLUDED.first_air_date,
    last_air_date = EXCLUDED.last_air_date,
    in_production = EXCLUDED.in_production,
    popularity = EXCLUDED.popularity,
    episode_run_time = EXCLUDED.episode_run_time,
    status = EXCLUDED.status,
    type = EXCLUDED.type;


-- =============================================================================
-- STAP 6: Vul de koppeltabellen
-- =============================================================================

-- ── show_languages ────────────────────────────────────────────────────────────
INSERT INTO show_languages (show_id, language_id)
SELECT DISTINCT
    s.id::BIGINT,
    l.id
FROM staging_shows s,
     LATERAL unnest(string_to_array(s.languages, ',')) AS t(lang)
JOIN languages l ON l.code = TRIM(lang)
WHERE NULLIF(TRIM(lang), '') IS NOT NULL
  AND s.id::BIGINT IN (SELECT id FROM shows)
ON CONFLICT DO NOTHING;

-- ── show_genres ───────────────────────────────────────────────────────────────
INSERT INTO show_genres (show_id, genre_id)
SELECT DISTINCT
    s.id::BIGINT,
    g.id
FROM staging_shows s,
     LATERAL unnest(string_to_array(s.genres, ',')) AS t(gname)
JOIN genres g ON g.name = TRIM(gname)
WHERE NULLIF(TRIM(gname), '') IS NOT NULL
  AND s.id::BIGINT IN (SELECT id FROM shows)
ON CONFLICT DO NOTHING;

-- ── show_networks ─────────────────────────────────────────────────────────────
INSERT INTO show_networks (show_id, network_id)
SELECT DISTINCT
    s.id::BIGINT,
    n.id
FROM staging_shows s,
     LATERAL unnest(string_to_array(s.networks, ',')) AS t(nname)
JOIN networks n ON n.name = TRIM(nname)
WHERE NULLIF(TRIM(nname), '') IS NOT NULL
  AND s.id::BIGINT IN (SELECT id FROM shows)
ON CONFLICT DO NOTHING;

-- ── show_production_companies ─────────────────────────────────────────────────
INSERT INTO show_production_companies (show_id, company_id)
SELECT DISTINCT
    s.id::BIGINT,
    pc.id
FROM staging_shows s,
     LATERAL unnest(string_to_array(s.production_companies, ',')) AS t(pcname)
JOIN production_companies pc ON pc.name = TRIM(pcname)
WHERE NULLIF(TRIM(pcname), '') IS NOT NULL
  AND s.id::BIGINT IN (SELECT id FROM shows)
ON CONFLICT DO NOTHING;

-- ── show_production_countries ─────────────────────────────────────────────────
INSERT INTO show_production_countries (show_id, country_id)
SELECT DISTINCT
    s.id::BIGINT,
    c.id
FROM staging_shows s,
     LATERAL unnest(string_to_array(s.production_countries, ',')) AS t(cname)
JOIN production_countries c ON c.name = TRIM(cname)
WHERE NULLIF(TRIM(cname), '') IS NOT NULL
  AND s.id::BIGINT IN (SELECT id FROM shows)
ON CONFLICT DO NOTHING;

-- ── show_creators ─────────────────────────────────────────────────────────────
INSERT INTO show_creators (show_id, creator_id)
SELECT DISTINCT
    s.id::BIGINT,
    cr.id
FROM staging_shows s,
     LATERAL unnest(string_to_array(s.created_by, ',')) AS t(crname)
JOIN creators cr ON cr.name = TRIM(crname)
WHERE NULLIF(TRIM(crname), '') IS NOT NULL
  AND s.id::BIGINT IN (SELECT id FROM shows)
ON CONFLICT DO NOTHING;


-- =============================================================================
-- STAP 7: Post-import validatie
-- =============================================================================

DO $$
DECLARE
    v_staging_rows BIGINT;
    v_duplicate_ids BIGINT;
    v_missing_shows BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_staging_rows
    FROM staging_shows;

    IF v_staging_rows = 0 THEN
        RAISE EXCEPTION 'Import validation failed: staging_shows is empty';
    END IF;

    SELECT COUNT(*) INTO v_duplicate_ids
    FROM (
        SELECT id
        FROM staging_shows
        GROUP BY id
        HAVING COUNT(*) > 1
    ) duplicates;

    IF v_duplicate_ids > 0 THEN
        RAISE EXCEPTION 'Import validation failed: % duplicate show IDs remain', v_duplicate_ids;
    END IF;

    SELECT COUNT(*) INTO v_missing_shows
    FROM staging_shows s
    LEFT JOIN shows sh ON sh.id = s.id::BIGINT
    WHERE sh.id IS NULL;

    IF v_missing_shows > 0 THEN
        RAISE EXCEPTION 'Import validation failed: % staged shows are missing from shows', v_missing_shows;
    END IF;
END $$;


-- =============================================================================
-- STAP 8: Opruimen – verwijder de staging-tabel
-- =============================================================================

DROP TABLE IF EXISTS staging_shows;


-- Refresh planner statistics after the bulk load.
ANALYZE
    shows,
    languages,
    genres,
    networks,
    production_companies,
    production_countries,
    creators,
    show_languages,
    show_genres,
    show_networks,
    show_production_companies,
    show_production_countries,
    show_creators;


-- =============================================================================
-- STAP 9: Snelle validatie – tel rijen per tabel
-- =============================================================================

DO $$
DECLARE
    v_shows      BIGINT;
    v_langs      BIGINT;
    v_genres     BIGINT;
    v_networks   BIGINT;
    v_companies  BIGINT;
    v_countries  BIGINT;
    v_creators   BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_shows     FROM shows;
    SELECT COUNT(*) INTO v_langs     FROM languages;
    SELECT COUNT(*) INTO v_genres    FROM genres;
    SELECT COUNT(*) INTO v_networks  FROM networks;
    SELECT COUNT(*) INTO v_companies FROM production_companies;
    SELECT COUNT(*) INTO v_countries FROM production_countries;
    SELECT COUNT(*) INTO v_creators  FROM creators;

    RAISE NOTICE '=== Import voltooid ===';
    RAISE NOTICE 'shows               : %', v_shows;
    RAISE NOTICE 'languages           : %', v_langs;
    RAISE NOTICE 'genres              : %', v_genres;
    RAISE NOTICE 'networks            : %', v_networks;
    RAISE NOTICE 'production_companies: %', v_companies;
    RAISE NOTICE 'production_countries: %', v_countries;
    RAISE NOTICE 'creators            : %', v_creators;
END $$;

COMMIT;

-- =============================================================================
-- EINDE SCRIPT
-- =============================================================================