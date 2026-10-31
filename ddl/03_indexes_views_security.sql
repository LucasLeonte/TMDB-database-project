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

    -- Concrete login-gebruikers
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'readonly_user') THEN
        CREATE ROLE readonly_user LOGIN PASSWORD 'readonly_secret';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'analyst_user') THEN
        CREATE ROLE analyst_user LOGIN PASSWORD 'analyst_secret';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user LOGIN PASSWORD 'app_secret';
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


-- =============================================================================
-- ROW-LEVEL SECURITY (RLS)  – users mogen enkel hun eigen favorieten zien/bewerken
-- =============================================================================

ALTER TABLE user_favorites ENABLE ROW LEVEL SECURITY;

-- Verwijder bestaande policies indien ze al bestaan
DROP POLICY IF EXISTS policy_user_favorites_self  ON user_favorites;
DROP POLICY IF EXISTS policy_user_favorites_admin ON user_favorites;

-- Eigenaarspolicy: een gebruiker ziet/bewerkt enkel rijen waar user_id = zijn eigen id.
-- current_setting('app.current_user_id') wordt door de applicatie ingesteld via
--   SET LOCAL app.current_user_id = '<id>';
-- vóór elke transactie.
CREATE POLICY policy_user_favorites_self
    ON user_favorites
    FOR ALL
    USING      (user_id IS NOT NULL AND user_id = NULLIF(current_setting('app.current_user_id', TRUE), '')::INT)
    WITH CHECK (user_id IS NOT NULL AND user_id = NULLIF(current_setting('app.current_user_id', TRUE), '')::INT);

-- =============================================================================
-- EINDE SCRIPT
-- =============================================================================
