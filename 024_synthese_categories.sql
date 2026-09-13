-- ============================================================
-- SYNTHÈSE PAR CATÉGORIE (ex "AG" / "Analyse" fusionnées côté front)
-- ============================================================
-- La configuration des catégories (quelles sources/types/descriptions/
-- fournisseurs composent "Dons", "Frais vétérinaires", etc.) est stockée
-- dans config_compta (cle='ag_categories'), même mécanisme que
-- 'periodes'. Structure d'un élément :
--   {"cat":"Dons","sens":"recette","sources":["banque","caisse"],
--    "types":["Dons","Don libre"],"descriptions":[],"fournisseurs":[]}
--
-- ATTENTION vérifiée en reprenant l'ancien système : si une même
-- catégorie coche à la fois "banque" (ou "caisse") ET "cheques"/"remises"
-- comme sources, un chèque/une remise encaissé(e) est compté deux fois
-- (une fois comme chèque/remise, une fois comme mouvement bancaire une
-- fois encaissé). Par défaut, aucune catégorie ne mélange les deux — la
-- page ci-jointe avertit visuellement si on active cette combinaison.

create or replace function enregistrer_ag_categories(p_categories jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    insert into config_compta (cle, valeur) values ('ag_categories', p_categories)
        on conflict (cle) do update set valeur = excluded.valeur, maj_le = now();
end;
$$;
