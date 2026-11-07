-- ============================================================
-- 067a_vider_donnees_compta.sql  —  À N'UTILISER QUE SI la base contient déjà
-- des données de compta (test ou import partiel) que vous voulez REMPLACER.
-- ⚠️  EFFACE DÉFINITIVEMENT : banque, caisses, chèques, remises de chèques, factures,
--     leurs liens (Suivi / factures) et les écritures diverses.
-- ⚠️  Faites d'abord une sauvegarde (voir mode opératoire, étape 1).
-- Ne touche NI aux animaux, personnes, adoptions, dons, ICAD (Suivi), ni à la configuration.
-- ============================================================
begin;
delete from banque_mouvement_suivi_liens;
delete from banque_mouvement_facture_liens;
delete from caisse_mouvement_suivi_liens;
update caisse_mouvements set ref_banque = null;
update cheques set ref_banque = null;
update remises_cheques set ref_banque = null;
delete from caisse_mouvements;
delete from banque_mouvements;
delete from cheques;
delete from remise_cheques_details;
delete from remises_cheques;
delete from factures;
delete from ecritures_diverses;
select 'banque' as t, count(*) from banque_mouvements
union all select 'caisse', count(*) from caisse_mouvements
union all select 'cheques', count(*) from cheques
union all select 'remises', count(*) from remises_cheques
union all select 'factures', count(*) from factures;
commit;
