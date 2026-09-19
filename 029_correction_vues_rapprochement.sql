-- ============================================================
-- 029_correction_vues_rapprochement.sql
--
-- Corrige un bug bloquant : les 4 vues ci-dessous (dans
-- 001_schema_arche_de_mallo.sql) référençaient encore
-- 'mouvement_suivi_liens', une table de l'ébauche remplacée depuis par
-- deux tables séparées (caisse_mouvement_suivi_liens /
-- banque_mouvement_suivi_liens, voir 017_liens_mouvement_suivi.sql) —
-- d'où l'erreur "relation mouvement_suivi_liens does not exist" à la
-- création de ces vues.
--
-- Ce fichier est exécutable seul (CREATE OR REPLACE VIEW), pour
-- corriger la base déjà déployée. 001_schema_arche_de_mallo.sql a été
-- mis à jour en parallèle pour qu'un futur déploiement neuf ne
-- reproduise pas le problème.
-- ============================================================

create or replace view v_dons_non_rapproches as
select d.*
from dons d
where not exists (select 1 from caisse_mouvement_suivi_liens l where l.don_id = d.id)
  and not exists (select 1 from banque_mouvement_suivi_liens l where l.don_id = d.id);

create or replace view v_adhesions_non_rapprochees as
select a.*
from adhesions a
where not exists (select 1 from caisse_mouvement_suivi_liens l where l.adhesion_id = a.id)
  and not exists (select 1 from banque_mouvement_suivi_liens l where l.adhesion_id = a.id);

create or replace view v_adoptions_non_rapprochees as
select a.*
from adoptions a
where not exists (select 1 from caisse_mouvement_suivi_liens l where l.adoption_id = a.id)
  and not exists (select 1 from banque_mouvement_suivi_liens l where l.adoption_id = a.id);

create or replace view v_reservations_non_rapprochees as
select r.*
from reservations r
where not exists (select 1 from caisse_mouvement_suivi_liens l where l.reservation_id = r.id)
  and not exists (select 1 from banque_mouvement_suivi_liens l where l.reservation_id = r.id);
