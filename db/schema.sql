-- =============================================================================
-- TMDB TV Shows Database – Complete Schema & Test Seed
-- RDBMS  : PostgreSQL 16
-- =============================================================================
-- Voer dit script uit met:
--   psql -U tmdb_admin -d tmdb -f db/schema.sql
-- of via Docker:
--   docker exec -i tmdb_postgres psql -U tmdb_admin -d tmdb < db/schema.sql
-- =============================================================================

-- Verwijder alles als het schema al bestaat (idempotent herstarten)
DROP TABLE IF EXISTS user_favorites            CASCADE;
DROP TABLE IF EXISTS show_creators             CASCADE;
DROP TABLE IF EXISTS show_production_countries CASCADE;
DROP TABLE IF EXISTS show_production_companies CASCADE;
DROP TABLE IF EXISTS show_networks             CASCADE;
DROP TABLE IF EXISTS show_genres               CASCADE;
DROP TABLE IF EXISTS show_languages            CASCADE;
DROP TABLE IF EXISTS shows                     CASCADE;

DROP TABLE IF EXISTS users                CASCADE;
DROP TABLE IF EXISTS creators             CASCADE;
DROP TABLE IF EXISTS production_countries CASCADE;
DROP TABLE IF EXISTS production_companies CASCADE;
DROP TABLE IF EXISTS networks             CASCADE;
DROP TABLE IF EXISTS genres               CASCADE;
DROP TABLE IF EXISTS languages            CASCADE;

DROP TYPE IF EXISTS show_status CASCADE;
DROP TYPE IF EXISTS show_type   CASCADE;


-- =============================================================================
-- ENUM TYPES
-- =============================================================================

CREATE TYPE show_status AS ENUM (
    'Ended',
    'Returning Series',
    'Canceled',
    'In Production',
    'Planned',
    'Pilot',
    'Unknown'
);

CREATE TYPE show_type AS ENUM (
    'Scripted',
    'Documentary',
    'Reality',
    'Talk Show',
    'Miniseries',
    'News',
    'Video'
);


-- =============================================================================
-- LOOKUP / DIMENSION TABLES  (met GENERATED ALWAYS AS IDENTITY)
-- =============================================================================

-- ----------------------------------------------------------------------------
-- languages
-- Bevat ISO-639-1 taalcodes (bijv. 'en', 'es', 'fr').
-- ----------------------------------------------------------------------------
CREATE TABLE languages (
    id   INT         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code VARCHAR(10) NOT NULL,
    CONSTRAINT uq_languages_code UNIQUE (code)
);

COMMENT ON TABLE  languages      IS 'ISO-639-1 taalcodes die voorkomen in de TMDB-dataset.';
COMMENT ON COLUMN languages.code IS 'Twee- of drieletter ISO-taalcode (bijv. ''en'', ''fr'').';


-- ----------------------------------------------------------------------------
-- genres
-- ----------------------------------------------------------------------------
CREATE TABLE genres (
    id   INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    CONSTRAINT uq_genres_name UNIQUE (name)
);

COMMENT ON TABLE genres IS 'Filmgenres zoals gedefinieerd door TMDB (bijv. ''Drama'', ''Action'').';


-- ----------------------------------------------------------------------------
-- networks
-- ----------------------------------------------------------------------------
CREATE TABLE networks (
    id   INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    CONSTRAINT uq_networks_name UNIQUE (name)
);

COMMENT ON TABLE networks IS 'Streamingplatforms die een show uitzenden (bijv. ''Netflix'', ''HBO'').';


-- ----------------------------------------------------------------------------
-- production_companies
-- ----------------------------------------------------------------------------
CREATE TABLE production_companies (
    id   INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    CONSTRAINT uq_production_companies_name UNIQUE (name)
);

COMMENT ON TABLE production_companies IS 'Productiemaatschappijen verantwoordelijk voor een show.';


-- ----------------------------------------------------------------------------
-- production_countries
-- ----------------------------------------------------------------------------
CREATE TABLE production_countries (
    id   INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    CONSTRAINT uq_production_countries_name UNIQUE (name)
);

COMMENT ON TABLE production_countries IS 'Landen waar een show geproduceerd is.';


-- ----------------------------------------------------------------------------
-- creators
-- Regisseurs / showrunners die een show hebben gemaakt.
-- ----------------------------------------------------------------------------
CREATE TABLE creators (
    id   INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    CONSTRAINT uq_creators_name UNIQUE (name)
);

COMMENT ON TABLE creators IS 'Personen die als creator vermeld staan voor een show (showrunners, schrijvers).';


-- ----------------------------------------------------------------------------
-- users
-- Applicatiegebruikers die favorieten kunnen bijhouden.
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    id            INT           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username      VARCHAR(100)  NOT NULL,
    password_hash VARCHAR(255)  NOT NULL,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_users_username UNIQUE (username),
    CONSTRAINT chk_users_username_length CHECK (LENGTH(username) >= 3)
);

COMMENT ON TABLE  users               IS 'Applicatiegebruikers (filmrecensenten, analisten, …).';
COMMENT ON COLUMN users.password_hash IS 'Bcrypt-hash van het wachtwoord; nooit plaintext opslaan!';


-- =============================================================================
-- CORE ENTITY: shows
-- =============================================================================

CREATE TABLE shows (
    -- Primaire sleutel overgenomen uit TMDB (niet gegenereerd)
    id                 BIGINT        PRIMARY KEY,

    -- Titels
    name               VARCHAR(500)  NOT NULL,
    original_name      VARCHAR(500),

    -- Aantallen
    number_of_seasons  INT           CHECK (number_of_seasons  >= 0),
    number_of_episodes INT           CHECK (number_of_episodes >= 0),

    -- Beoordelingen
    vote_count         INT           NOT NULL DEFAULT 0 CHECK (vote_count   >= 0),
    vote_average       NUMERIC(5,3)  NOT NULL DEFAULT 0 CHECK (vote_average BETWEEN 0 AND 10),

    -- Beschrijving
    overview           TEXT,
    tagline            VARCHAR(1000),

    -- Metadata
    adult              BOOLEAN       NOT NULL DEFAULT FALSE,
    backdrop_path      VARCHAR(500),
    poster_path        VARCHAR(500),
    homepage           VARCHAR(2000),

    -- Datums
    first_air_date     DATE,
    last_air_date      DATE,

    -- Productie
    in_production      BOOLEAN       NOT NULL DEFAULT FALSE,
    popularity         NUMERIC(12,3) CHECK (popularity >= 0),
    episode_run_time   INT           CHECK (episode_run_time >= 0),  -- minuten

    -- Enum-kolommen
    status             show_status,
    type               show_type,

    -- Audit
    created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    -- Logische datumvolgorde
    CONSTRAINT chk_shows_air_dates
        CHECK (last_air_date IS NULL OR first_air_date IS NULL OR last_air_date >= first_air_date)
);

COMMENT ON TABLE  shows                  IS 'Kerntabel: elke rij is één TV-show uit de TMDB-dataset.';
COMMENT ON COLUMN shows.id               IS 'TMDB show-id; overgenomen uit de bron, niet gegenereerd.';
COMMENT ON COLUMN shows.vote_average     IS 'Gemiddelde score 0–10 zoals berekend door TMDB.';
COMMENT ON COLUMN shows.popularity       IS 'TMDB-populariteitsindex (zwevend getal).';
COMMENT ON COLUMN shows.episode_run_time IS 'Typische afleveringsduur in minuten, 0 bij afwezigheid van gegevens.';


-- =============================================================================
-- KOPPELTABELLEN  (many-to-many)
-- =============================================================================

-- ----------------------------------------------------------------------------
-- show_languages
-- Alle talen (languages) geassocieerd met een show.
-- ----------------------------------------------------------------------------
CREATE TABLE show_languages (
    show_id     BIGINT NOT NULL,
    language_id INT    NOT NULL,
    CONSTRAINT pk_show_languages PRIMARY KEY (show_id, language_id),
    CONSTRAINT fk_show_languages_show
        FOREIGN KEY (show_id)     REFERENCES shows     (id) ON DELETE CASCADE,
    CONSTRAINT fk_show_languages_language
        FOREIGN KEY (language_id) REFERENCES languages (id) ON DELETE CASCADE
);

COMMENT ON TABLE show_languages IS 'Koppelt shows aan talen (languages in TMDB).';


-- ----------------------------------------------------------------------------
-- show_genres
-- ----------------------------------------------------------------------------
CREATE TABLE show_genres (
    show_id  BIGINT NOT NULL,
    genre_id INT    NOT NULL,
    CONSTRAINT pk_show_genres PRIMARY KEY (show_id, genre_id),
    CONSTRAINT fk_show_genres_show
        FOREIGN KEY (show_id)  REFERENCES shows  (id) ON DELETE CASCADE,
    CONSTRAINT fk_show_genres_genre
        FOREIGN KEY (genre_id) REFERENCES genres (id) ON DELETE CASCADE
);

COMMENT ON TABLE show_genres IS 'Koppelt shows aan genres.';


-- ----------------------------------------------------------------------------
-- show_networks
-- ----------------------------------------------------------------------------
CREATE TABLE show_networks (
    show_id    BIGINT NOT NULL,
    network_id INT    NOT NULL,
    CONSTRAINT pk_show_networks PRIMARY KEY (show_id, network_id),
    CONSTRAINT fk_show_networks_show
        FOREIGN KEY (show_id)    REFERENCES shows    (id) ON DELETE CASCADE,
    CONSTRAINT fk_show_networks_network
        FOREIGN KEY (network_id) REFERENCES networks (id) ON DELETE CASCADE
);

COMMENT ON TABLE show_networks IS 'Koppelt shows aan streamingplatforms.';


-- ----------------------------------------------------------------------------
-- show_production_companies
-- ----------------------------------------------------------------------------
CREATE TABLE show_production_companies (
    show_id    BIGINT NOT NULL,
    company_id INT    NOT NULL,
    CONSTRAINT pk_show_production_companies PRIMARY KEY (show_id, company_id),
    CONSTRAINT fk_show_prod_companies_show
        FOREIGN KEY (show_id)    REFERENCES shows                (id) ON DELETE CASCADE,
    CONSTRAINT fk_show_prod_companies_company
        FOREIGN KEY (company_id) REFERENCES production_companies (id) ON DELETE CASCADE
);

COMMENT ON TABLE show_production_companies IS 'Koppelt shows aan productiemaatschappijen.';


-- ----------------------------------------------------------------------------
-- show_production_countries
-- ----------------------------------------------------------------------------
CREATE TABLE show_production_countries (
    show_id    BIGINT NOT NULL,
    country_id INT    NOT NULL,
    CONSTRAINT pk_show_production_countries PRIMARY KEY (show_id, country_id),
    CONSTRAINT fk_show_prod_countries_show
        FOREIGN KEY (show_id)    REFERENCES shows                 (id) ON DELETE CASCADE,
    CONSTRAINT fk_show_prod_countries_country
        FOREIGN KEY (country_id) REFERENCES production_countries  (id) ON DELETE CASCADE
);

COMMENT ON TABLE show_production_countries IS 'Koppelt shows aan productielanden.';


-- ----------------------------------------------------------------------------
-- show_creators
-- ----------------------------------------------------------------------------
CREATE TABLE show_creators (
    show_id    BIGINT NOT NULL,
    creator_id INT    NOT NULL,
    CONSTRAINT pk_show_creators PRIMARY KEY (show_id, creator_id),
    CONSTRAINT fk_show_creators_show
        FOREIGN KEY (show_id)    REFERENCES shows    (id) ON DELETE CASCADE,
    CONSTRAINT fk_show_creators_creator
        FOREIGN KEY (creator_id) REFERENCES creators (id) ON DELETE CASCADE
);

COMMENT ON TABLE show_creators IS 'Koppelt shows aan hun creators (created_by in TMDB).';


-- ----------------------------------------------------------------------------
-- user_favorites
-- Een gebruiker kan een show aan zijn favorieten toevoegen.
-- ----------------------------------------------------------------------------
CREATE TABLE user_favorites (
    user_id  INT         NOT NULL,
    show_id  BIGINT      NOT NULL,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT pk_user_favorites PRIMARY KEY (user_id, show_id),
    CONSTRAINT fk_user_favorites_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_user_favorites_show
        FOREIGN KEY (show_id) REFERENCES shows (id) ON DELETE CASCADE
);

COMMENT ON TABLE  user_favorites          IS 'Houd bij welke shows een gebruiker als favoriet heeft gemarkeerd (RLS actief).';
COMMENT ON COLUMN user_favorites.added_at IS 'Tijdstip waarop favoriet werd toegevoegd (UTC).';


-- =============================================================================
-- EXTENSIES
-- =============================================================================

-- pg_trgm extensie activeren voor trigram-matching & GIN indexering
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- =============================================================================
-- INDEXEN
-- =============================================================================

-- Verwijder bestaande indexen indien ze al bestaan
DROP INDEX IF EXISTS idx_shows_name;
DROP INDEX IF EXISTS idx_shows_original_name;
DROP INDEX IF EXISTS idx_shows_first_air_date;
DROP INDEX IF EXISTS idx_shows_last_air_date;
DROP INDEX IF EXISTS idx_shows_popularity;
DROP INDEX IF EXISTS idx_shows_vote_average;
DROP INDEX IF EXISTS idx_show_languages_language_id;
DROP INDEX IF EXISTS idx_show_genres_genre_id;
DROP INDEX IF EXISTS idx_show_networks_network_id;
DROP INDEX IF EXISTS idx_show_prod_companies_comp_id;
DROP INDEX IF EXISTS idx_show_prod_countries_coun_id;
DROP INDEX IF EXISTS idx_show_creators_creator_id;
DROP INDEX IF EXISTS idx_user_favorites_user_id;

-- Zoeken op naam / titels: GIN indexen met pg_trgm
-- Maakt snelle ILIKE '%...%' (substring), regex en trigram fuzzy searches mogelijk
CREATE INDEX idx_shows_name           ON shows USING gin (name gin_trgm_ops);
CREATE INDEX idx_shows_original_name  ON shows USING gin (original_name gin_trgm_ops);

-- Sorteren / filteren op datum (B-Tree)
CREATE INDEX idx_shows_first_air_date ON shows (first_air_date);
CREATE INDEX idx_shows_last_air_date  ON shows (last_air_date);

-- Rangschikking op populariteit / score (B-Tree)
CREATE INDEX idx_shows_popularity     ON shows (popularity DESC);
CREATE INDEX idx_shows_vote_average   ON shows (vote_average DESC);

-- Koppeltabellen: snel opzoeken per show (FK-kant al gedekt door PK;
-- extra index op de andere kant voor reverse-lookup)
CREATE INDEX idx_show_languages_language_id   ON show_languages            (language_id);
CREATE INDEX idx_show_genres_genre_id         ON show_genres               (genre_id);
CREATE INDEX idx_show_networks_network_id     ON show_networks             (network_id);
CREATE INDEX idx_show_prod_companies_comp_id  ON show_production_companies (company_id);
CREATE INDEX idx_show_prod_countries_coun_id  ON show_production_countries (country_id);
CREATE INDEX idx_show_creators_creator_id     ON show_creators             (creator_id);

-- Favorietenlijst per gebruiker
CREATE INDEX idx_user_favorites_user_id ON user_favorites (user_id);


-- =============================================================================
-- VIEWS
-- =============================================================================

-- ----------------------------------------------------------------------------
-- vw_show_overview
-- Overzicht voor snelle rapportage.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_show_overview AS
SELECT
    s.id,
    s.name,
    s.original_name,
    s.status,
    s.type,
    s.first_air_date,
    s.last_air_date,
    s.number_of_seasons,
    s.number_of_episodes,
    s.vote_average,
    s.vote_count,
    s.popularity,
    s.in_production,
    s.adult
FROM shows s;

COMMENT ON VIEW vw_show_overview IS
    'Overzicht van elke show. Handig voor rapportage.';


-- ----------------------------------------------------------------------------
-- vw_network_stats
-- Statistieken per netwerk.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_network_stats AS
SELECT
    n.name                          AS network,
    COUNT(sn.show_id)               AS total_shows,
    ROUND(AVG(s.vote_average), 2)   AS avg_vote_average,
    ROUND(AVG(s.popularity),   2)   AS avg_popularity
FROM networks n
JOIN show_networks sn ON sn.network_id = n.id
JOIN shows        s  ON s.id          = sn.show_id
GROUP BY n.name
ORDER BY total_shows DESC;

COMMENT ON VIEW vw_network_stats IS
    'Statistieken per streamingplatform.';


-- ----------------------------------------------------------------------------
-- vw_genre_stats
-- Gemiddelde score en totaal aantal shows per genre.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_genre_stats AS
SELECT
    g.name                          AS genre,
    COUNT(sg.show_id)               AS total_shows,
    ROUND(AVG(s.vote_average), 2)   AS avg_vote_average,
    ROUND(AVG(s.popularity),   2)   AS avg_popularity,
    SUM(s.vote_count)               AS total_votes
FROM genres g
JOIN show_genres sg ON sg.genre_id = g.id
JOIN shows      s  ON s.id        = sg.show_id
GROUP BY g.name
ORDER BY avg_vote_average DESC;

COMMENT ON VIEW vw_genre_stats IS
    'Geaggregeerde statistieken (gemiddelde score, populariteit, votes) per genre.';


-- ----------------------------------------------------------------------------
-- vw_top_shows_by_genre
-- Top 20 shows per genre op basis van vote_average.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_top_shows_by_genre AS
SELECT *
FROM (
    SELECT
        g.name AS genre,
        s.name AS show_name,
        s.vote_average,
        s.vote_count,
        s.popularity,
        RANK() OVER (PARTITION BY g.id ORDER BY s.vote_average DESC, s.vote_count DESC) AS rank_in_genre
    FROM genres g
    JOIN show_genres sg ON sg.genre_id = g.id
    JOIN shows      s  ON s.id        = sg.show_id
    WHERE s.vote_count >= 100   -- minimale drempel om betrouwbaar te zijn
) ranked
WHERE rank_in_genre <= 20;

COMMENT ON VIEW vw_top_shows_by_genre IS
    'Top 20 best beoordeelde shows per genre (minimaal 100 stemmen).';


-- =============================================================================
-- ROLLEN & RECHTEN  (Database Security)
-- =============================================================================

-- Verwijder eventueel bestaande rollen (mag falen als ze niet bestaan)
DO $$
BEGIN
    -- readonly_role: data-analisten, mogen alleen lezen
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'readonly_role') THEN
        CREATE ROLE readonly_role NOLOGIN;
    END IF;

    -- analyst_role: mag ook views aanmaken, maar geen DML op kerntabellen
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'analyst_role') THEN
        CREATE ROLE analyst_role NOLOGIN;
    END IF;

    -- app_role: back-end applicatie (INSERT/UPDATE/DELETE op user_favorites)
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_role') THEN
        CREATE ROLE app_role NOLOGIN;
    END IF;

    -- admin_role: volledige toegang (DBA)
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_role') THEN
        CREATE ROLE admin_role NOLOGIN;
    END IF;

    -- Concrete login-gebruikers (wachtwoorden zijn dummy-credentials)
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'readonly_user') THEN
        CREATE ROLE readonly_user LOGIN PASSWORD 'readonly_secret';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'analyst_user') THEN
        CREATE ROLE analyst_user LOGIN PASSWORD 'analyst_secret';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user LOGIN PASSWORD 'app_secret';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_user') THEN
        CREATE ROLE admin_user LOGIN PASSWORD 'admin_secret';
    END IF;
END $$;

-- Rol-hiërarchie koppelen
GRANT readonly_role TO analyst_role;   -- analisten erven leesrechten
GRANT readonly_role TO app_role;       -- app-gebruiker erft leesrechten

-- Rechten readonly_role: lees alle tabellen en views
GRANT USAGE  ON SCHEMA public                     TO readonly_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public       TO readonly_role;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public    TO readonly_role;

-- Rechten analyst_role: mag ook tijdelijke tabellen aanmaken
GRANT TEMPORARY ON DATABASE tmdb TO analyst_role;

-- Rechten app_role: mag user-gerelateerde tabellen bewerken
GRANT INSERT, UPDATE, DELETE ON TABLE users          TO app_role;
GRANT INSERT, UPDATE, DELETE ON TABLE user_favorites TO app_role;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public        TO app_role;

-- admin_role: supersets (in productie toewijzen aan de DBA-loginrol)
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO admin_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO admin_role;

-- Koppel loginrollen aan hun rolgroep
GRANT readonly_role TO readonly_user;
GRANT analyst_role  TO analyst_user;
GRANT app_role      TO app_user;
GRANT admin_role    TO admin_user;


-- =============================================================================
-- ROW-LEVEL SECURITY (RLS)  – users mogen enkel hun eigen favorieten zien/bewerken
-- =============================================================================

ALTER TABLE user_favorites ENABLE ROW LEVEL SECURITY;

-- Verwijder bestaande policies indien ze al bestaan
DROP POLICY IF EXISTS policy_user_favorites  ON user_favorites;

-- Eigenaarspolicy: een gebruiker ziet/bewerkt enkel rijen waar user_id = zijn eigen id.
-- current_setting('app.current_user_id') wordt door de applicatie ingesteld via
--   SET LOCAL app.current_user_id = '<id>';
-- vóór elke transactie.
CREATE POLICY policy_user_favorites
    ON user_favorites
    FOR ALL
    USING      (user_id IS NOT NULL AND user_id = NULLIF(current_setting('app.current_user_id', TRUE), '')::INT)
    WITH CHECK (user_id IS NOT NULL AND user_id = NULLIF(current_setting('app.current_user_id', TRUE), '')::INT);


-- =============================================================================
-- TMDB Test Data Seed
-- =============================================================================
-- Doel:
--   1. Aanmaken van test-applicatiegebruikers in de tabel 'users'
--   2. Toevoegen van 20 shows uit TMDB_tv_dataset_v3.csv in 'shows'
--   3. Toevoegen van voorbeeld-favorieten in 'user_favorites'
-- =============================================================================

BEGIN;

-- =============================================================================
-- STAP 1: Testgebruikers toevoegen aan tabel 'users'
-- =============================================================================
-- Wachtwoorden zijn mock bcrypt-hashes van 'password123'
INSERT INTO users (username, password_hash)
VALUES
    ('alice',   '$2b$12$e8YmE1g9z9p1QfJ3xZ9uqeM3r8Zt1u9e8y7w6v5u4t3s2r1q0p9o.'),
    ('bob',     '$2b$12$k9ZnF2h0a0q2RgK4yA0vrfN4s9Au2v0f9z8x7w6v5u4t3s2r1q0p9o.'),
    ('charlie', '$2b$12$m0AoG3i1b1r3ShL5zB1wsgO5t0Bv3w1g0a9y8x7w6v5u4t3s2r1q0p9o.')
ON CONFLICT (username) DO NOTHING;


-- =============================================================================
-- STAP 2: Eerste 20 shows uit TMDB_tv_dataset_v3.csv toevoegen
-- =============================================================================
-- Dit is een kleine seed voor lokaal testen. De volledige dataset kan worden
-- geladen met import_full_dataset.sql.
INSERT INTO shows (
    id,
    name,
    original_name,
    number_of_seasons,
    number_of_episodes,
    vote_count,
    vote_average,
    first_air_date,
    last_air_date,
    in_production,
    popularity,
    episode_run_time,
    status,
    type
)
VALUES
    (1399,  'Game of Thrones',       'Game of Thrones',       8,  73, 21857, 8.442, '2011-04-17', '2019-05-19', FALSE, 1083.917, 0,   'Ended',          'Scripted'),
    (71446, 'Money Heist',            'La Casa de Papel',      3,  41, 17836, 8.257, '2017-05-02', '2021-12-03', FALSE, 96.354,   70,  'Ended',          'Scripted'),
    (66732, 'Stranger Things',        'Stranger Things',        4,  34, 16161, 8.624, '2016-07-15', '2022-07-01', TRUE,  185.711,  0,   'Returning Series','Scripted'),
    (1402,  'The Walking Dead',       'The Walking Dead',      11, 177, 15432, 8.121, '2010-10-31', '2022-11-20', FALSE, 489.746,  42,  'Ended',          'Scripted'),
    (63174, 'Lucifer',                'Lucifer',                6,  93, 13870, 8.486, '2016-01-25', '2021-09-10', FALSE, 416.668,  45,  'Ended',          'Scripted'),
    (69050, 'Riverdale',              'Riverdale',              7, 137, 13180, 8.479, '2017-01-26', '2023-08-23', FALSE, 143.750,  45,  'Ended',          'Scripted'),
    (93405, 'Squid Game',             '오징어 게임',             2,   9, 13053, 7.831, '2021-09-17', '2021-09-17', TRUE,  115.587,   0,  'Returning Series','Scripted'),
    (1396,  'Breaking Bad',           'Breaking Bad',           5,  62, 12398, 8.890, '2008-01-20', '2013-09-29', FALSE, 247.632,   0,  'Ended',          'Scripted'),
    (71712, 'The Good Doctor',        'The Good Doctor',        6, 116, 11768, 8.503, '2017-09-25', '2023-05-01', TRUE,  681.614,  43,  'Returning Series','Scripted'),
    (85271, 'WandaVision',            'WandaVision',             1,   9, 11308, 8.300, '2021-01-15', '2021-03-05', FALSE, 62.893,    0,  'Ended',          'Miniseries'),
    (60735, 'The Flash',              'The Flash',               9, 184, 10642, 7.797, '2014-10-07', '2023-05-24', FALSE, 319.767,  44,  'Ended',          'Scripted'),
    (1418,  'The Big Bang Theory',    'The Big Bang Theory',    12, 279, 10322, 7.879, '2007-09-24', '2019-05-16', FALSE, 344.121,  22,  'Ended',          'Scripted'),
    (84958, 'Loki',                   'Loki',                    2,  12, 10136, 8.200, '2021-06-09', '2021-07-14', TRUE,  276.759,  52,  'Returning Series','Scripted'),
    (1416,  'Grey''s Anatomy',        'Grey''s Anatomy',        19, 419,  9512, 8.253, '2005-03-27', '2023-05-18', TRUE,  1647.218, 43,  'Returning Series','Scripted'),
    (82856, 'The Mandalorian',        'The Mandalorian',         3,  24,  9353, 8.500, '2019-11-12', '2023-04-19', TRUE,  154.480,  0,  'Returning Series','Scripted'),
    (456,   'The Simpsons',           'The Simpsons',           35, 762,  9136, 7.999, '1989-12-17', '2023-10-01', TRUE,  439.488, 22,  'Returning Series','Scripted'),
    (85552, 'Euphoria',               'Euphoria',                2,  16,  9008, 8.353, '2019-06-16', '2022-02-27', TRUE,  197.456, 60,  'Returning Series','Scripted'),
    (75006, 'The Umbrella Academy',   'The Umbrella Academy',    4,  32,  8891, 8.604, '2019-02-15', '2022-06-22', TRUE,  51.859,    0,  'Returning Series','Scripted'),
    (60574, 'Peaky Blinders',         'Peaky Blinders',          6,  36,  8836, 8.546, '2013-09-12', '2022-04-03', FALSE, 344.477,  58,  'Ended',          'Scripted'),
    (76669, 'Elite',                  'Élite',                   7,  49,  8817, 8.071, '2018-10-05', '2022-11-18', TRUE,  100.711,  50,  'Returning Series','Scripted')
ON CONFLICT (id) DO NOTHING;


-- =============================================================================
-- STAP 3: Favoriete shows toevoegen aan 'user_favorites'
-- =============================================================================
-- Koppel bekende shows op basis van hun TMDB ID:
--   1399  : Game of Thrones
--   66732 : Stranger Things
--   63174 : Lucifer
--   71446 : Money Heist (La Casa de Papel)
--   1402  : The Walking Dead
--   93405 : Squid Game

-- Favorieten voor Alice:
INSERT INTO user_favorites (user_id, show_id)
SELECT u.id, s.id
FROM users u, shows s
WHERE u.username = 'alice'
  AND s.id IN (1399, 66732, 63174)
ON CONFLICT (user_id, show_id) DO NOTHING;

-- Favorieten voor Bob:
INSERT INTO user_favorites (user_id, show_id)
SELECT u.id, s.id
FROM users u, shows s
WHERE u.username = 'bob'
  AND s.id IN (71446, 1402)
ON CONFLICT (user_id, show_id) DO NOTHING;

-- Favorieten voor Charlie:
INSERT INTO user_favorites (user_id, show_id)
SELECT u.id, s.id
FROM users u, shows s
WHERE u.username = 'charlie'
  AND s.id IN (93405)
ON CONFLICT (user_id, show_id) DO NOTHING;

COMMIT;

-- =============================================================================
-- EINDE SCRIPT
-- =============================================================================