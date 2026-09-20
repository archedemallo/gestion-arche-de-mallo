-- ============================================================
-- 034_rls_tables_manquantes.sql
--
-- Trouvé lors d'un audit du projet : deux tables sans RLS activé,
-- passées entre les mailles des correctifs 015/026/028.
--
--   - compteurs_recus_fiscaux (dernier numéro attribué par type/année) :
--     sans RLS, si les droits par défaut de l'API REST Supabase n'ont
--     pas été révoqués, n'importe quel compte connecté pourrait modifier
--     directement "dernier_numero" sans passer par la fonction sécurisée
--     qui l'incrémente — risque de doublon ou de trou dans la
--     numérotation officielle des reçus fiscaux.
--   - transitions_statut_animal (table de référence des transitions de
--     statut autorisées) : pas de donnée sensible, mais incohérent avec
--     le reste du projet où quasi toutes les tables sont protégées.
-- ============================================================

alter table compteurs_recus_fiscaux enable row level security;
drop policy if exists compteurs_recus_fiscaux_lecture on compteurs_recus_fiscaux;
create policy compteurs_recus_fiscaux_lecture on compteurs_recus_fiscaux
    for select using (role_compta_courant() is not null);
-- Écriture réservée à la fonction sécurisée (SECURITY DEFINER) qui
-- attribue les numéros — aucun accès direct en insert/update/delete,
-- même pour un admin, pour qu'il n'existe qu'un seul chemin possible.

alter table transitions_statut_animal enable row level security;
drop policy if exists transitions_statut_animal_lecture on transitions_statut_animal;
create policy transitions_statut_animal_lecture on transitions_statut_animal
    for select using (role_suivi_courant() is not null or role_compta_courant() is not null);
-- Table de référence, modifiée uniquement par migration SQL — pas de
-- policy d'écriture pour l'API.
