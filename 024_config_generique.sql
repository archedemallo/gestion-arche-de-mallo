-- ============================================================
-- CONFIGURATION GÉNÉRIQUE (clé/valeur) — utilisée par la page Analyse
-- pour ag_categories, moy_cout_types, moy_adopt_statuts. Même table que
-- 'periodes' (config_compta), mais périodes garde sa fonction dédiée
-- (ajouter_periode/supprimer_periode) car elle a une validation propre.
create or replace function definir_config_compta(p_cle text, p_valeur jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    if p_cle = 'periodes' then
        raise exception 'Utiliser ajouter_periode()/supprimer_periode() pour les périodes.';
    end if;
    insert into config_compta (cle, valeur) values (p_cle, p_valeur)
        on conflict (cle) do update set valeur = excluded.valeur, maj_le = now();
end;
$$;
