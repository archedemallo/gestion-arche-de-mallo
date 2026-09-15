do $$
declare
    t text;
begin
    foreach t in array array[
        'soldes', 'types_mouvement', 'descriptions_mouvement',
        'config_listes', 'parametres'
    ]
    loop
        execute format('alter table %I enable row level security;', t);

        execute format('drop policy if exists %I on %I;', t || '_lecture', t);
        execute format(
            'create policy %I on %I for select using (role_compta_courant() is not null);',
            t || '_lecture', t
        );
        execute format('drop policy if exists %I on %I;', t || '_ecriture_insert', t);
        execute format(
            'create policy %I on %I for insert with check (role_compta_courant() = ''admin'');',
            t || '_ecriture_insert', t
        );
        execute format('drop policy if exists %I on %I;', t || '_ecriture_update', t);
        execute format(
            'create policy %I on %I for update using (role_compta_courant() = ''admin'');',
            t || '_ecriture_update', t
        );
        execute format('drop policy if exists %I on %I;', t || '_ecriture_delete', t);
        execute format(
            'create policy %I on %I for delete using (role_compta_courant() = ''admin'');',
            t || '_ecriture_delete', t
        );
    end loop;
end $$;