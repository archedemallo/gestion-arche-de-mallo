-- ============================================================
-- CORRECTIF SÉCURITÉ : vues sans SECURITY INVOKER
-- Le Security Advisor de Supabase signale ces 5 vues comme
-- SECURITY DEFINER par défaut (comportement standard de Postgres pour
-- une vue) : elles s'exécutent avec les droits du créateur de la vue
-- et non de l'utilisateur qui l'interroge, ce qui peut contourner le
-- RLS des tables sous-jacentes (dons, adhesions, adoptions,
-- reservations, soldes...).
--
-- Un correctif avait été communiqué précédemment mais n'avait jamais
-- été ajouté aux fichiers de migration du dépôt : 029 a même
-- recréé 4 de ces vues (create or replace) sans le correctif, ce qui
-- l'aurait de toute façon effacé s'il avait été appliqué à la main
-- dans Supabase. Cette migration corrige les 5 vues et doit être
-- exécutée dans Supabase.
-- ============================================================

alter view v_dons_non_rapproches           set (security_invoker = on);
alter view v_adhesions_non_rapprochees     set (security_invoker = on);
alter view v_adoptions_non_rapprochees     set (security_invoker = on);
alter view v_reservations_non_rapprochees  set (security_invoker = on);
alter view v_solde_cumule                  set (security_invoker = on);
