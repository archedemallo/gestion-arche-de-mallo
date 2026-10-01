-- ============================================================
-- 054 — Photo de réservation reprise à l'adoption
--
-- animaux_photos existait (001) mais n'était alimentée par aucun code
-- et n'avait ni date ni origine. On ajoute :
--   - source   : d'où vient la photo ('reservation', ...)
--   - cree_le  : pour retrouver la plus récente si un animal est
--                réservé plusieurs fois
-- RLS déjà en place sur cette table (026_auth_rls_suivi.sql :
-- lecture Suivi/Compta, écriture Suivi).
-- ============================================================
alter table animaux_photos add column if not exists source text;
alter table animaux_photos add column if not exists cree_le timestamptz not null default now();

create index if not exists idx_animaux_photos_animal_source
    on animaux_photos (animal_id, source, cree_le desc);
