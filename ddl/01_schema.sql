-- =============================================================================
-- TMDB TV Shows Database – DDL Script
-- RDBMS  : PostgreSQL 16
-- =============================================================================
-- Voer dit script uit met:
--   psql -U tmdb_admin -d tmdb -f 01_schema.sql
-- of via Docker:
--   docker exec -i tmdb_postgres psql -U tmdb_admin -d tmdb < ddl/01_schema.sql
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
    vote_average       NUMERIC(4,3)  NOT NULL DEFAULT 0 CHECK (vote_average BETWEEN 0 AND 10),

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