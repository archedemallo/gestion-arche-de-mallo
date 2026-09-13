-- ============================================================
-- NOTES PARTAGÉES — seule donnée Compta modifiable par un compte
-- lecteur (les notes sont collaboratives, contrairement au reste qui
-- reste strictement réservé à l'admin).
-- ============================================================
create or replace function enregistrer_notes_partagees(p_notes jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() is null then
        raise exception 'Accès refusé.';
    end if;
    insert into config_compta (cle, valeur) values ('notes_partagees', p_notes)
        on conflict (cle) do update set valeur = excluded.valeur, maj_le = now();
end;
$$;
