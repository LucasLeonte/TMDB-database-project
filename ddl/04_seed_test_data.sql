-- =============================================================================
-- TMDB TV Shows – Test Data & RLS Demonstratie
-- =============================================================================
-- Doel:
--   1. Aanmaken van test-applicatiegebruikers in de tabel 'users'
--   2. Toevoegen van voorbeeld-favorieten in 'user_favorites'
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
-- STAP 2: Favoriete shows toevoegen aan 'user_favorites'
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