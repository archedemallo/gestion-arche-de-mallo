-- ============================================================
-- Renomme icad_suivi -> animaux_sterilisation_icad
-- La table porte désormais deux suivis par animal : le transfert ICAD
-- (date_transfert, fichier_icad_url) et le certificat de stérilisation
-- (fichier_sterilisation_url, ajouté par 052). Le nom d'origine ne
-- reflétait plus son contenu.
-- Les politiques RLS, contraintes et clés étrangères suivent la table
-- automatiquement ; on renomme seulement les 2 politiques par cohérence.
-- Idempotent : peut être rejoué sans erreur.
-- ============================================================
do $$
begin
    if to_regclass('public.icad_suivi') is not null
       and to_regclass('public.animaux_sterilisation_icad') is null then
        alter table icad_suivi rename to animaux_sterilisation_icad;
    end if;

    if exists (select 1 from pg_policies where tablename = 'animaux_sterilisation_icad' and policyname = 'icad_suivi_lecture') then
        alter policy icad_suivi_lecture on animaux_sterilisation_icad rename to animaux_sterilisation_icad_lecture;
    end if;
    if exists (select 1 from pg_policies where tablename = 'animaux_sterilisation_icad' and policyname = 'icad_suivi_ecriture') then
        alter policy icad_suivi_ecriture on animaux_sterilisation_icad rename to animaux_sterilisation_icad_ecriture;
    end if;
end $$;
