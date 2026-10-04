-- ============================================================
-- 052 — Colonne fichier_sterilisation_url sur la table ICAD
--
-- suivi_icad.html lit/écrit le certificat de stérilisation dans
-- animaux_sterilisation_icad.fichier_sterilisation_url. Cette
-- colonne n'existait pas en base (migration 052 absente du dépôt).
-- Idempotent : peut être rejoué sans erreur. Gère aussi le cas où
-- la table porte encore son ancien nom (icad_suivi, avant 053).
-- ============================================================
do $$
begin
    if to_regclass('public.animaux_sterilisation_icad') is not null then
        alter table animaux_sterilisation_icad
            add column if not exists fichier_sterilisation_url text;
    elsif to_regclass('public.icad_suivi') is not null then
        alter table icad_suivi
            add column if not exists fichier_sterilisation_url text;
    end if;
end $$;

-- Recharge le cache de l'API REST (PostgREST) pour que la colonne
-- soit visible immédiatement.
notify pgrst, 'reload schema';
