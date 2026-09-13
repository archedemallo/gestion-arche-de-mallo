-- ============================================================
-- COMPTES ET DROITS D'ACCÈS — COMPTA
-- ============================================================
-- Reprend le modèle actuel (auth.js / AUTH_CONFIG.authorizedUsers) :
--   - compta@archedemallo.fr : admin, accès complet (lecture + écriture)
--   - jonathan@archedemallo.fr : lecteur, lecture seule
--
-- Contrairement aux formulaires Suivi (ouverts au public, clé "anon"),
-- toutes les tables Compta sont ici protégées par RLS et ne sont
-- accessibles qu'aux 2 comptes ci-dessus, une fois connectés via
-- Supabase Auth (email + mot de passe).
--
-- ÉTAPE MANUELLE avant que ça fonctionne : créer les 2 comptes dans
-- Supabase (Authentication > Users > Add user) avec CES DEUX EMAILS
-- EXACTS, puis exécuter les 2 lignes "insert into profils_compta"
-- tout en bas de ce fichier en remplaçant <uuid-compta> et
-- <uuid-jonathan> par les UUID générés (visibles dans la liste des
-- utilisateurs Supabase juste après leur création).

create table if not exists profils_compta (
    user_id  uuid primary key references auth.users(id) on delete cascade,
    email    text not null unique,
    role     text not null check (role in ('admin', 'lecteur')),
    cree_le  timestamptz not null default now()
);

-- Fonction utilitaire : le rôle de la personne actuellement connectée
-- (null si elle n'est pas dans profils_compta, donc pas autorisée).
create or replace function role_compta_courant()
returns text
language sql
security definer
set search_path = public
stable
as $$
    select role from profils_compta where user_id = auth.uid();
$$;

-- ---- Activation RLS sur toutes les tables Compta ----
alter table config_compta enable row level security;
alter table journal_audit_compta enable row level security;
alter table caisse_mouvements enable row level security;
alter table cheques enable row level security;
alter table remises_cheques enable row level security;
alter table remise_cheques_details enable row level security;
alter table banque_mouvements enable row level security;
alter table factures enable row level security;
alter table caisse_physique_comptages enable row level security;
alter table import_rapprochement enable row level security;
alter table profils_compta enable row level security;

-- ---- Politiques génériques : lecture pour admin + lecteur, écriture pour admin seul ----
-- (répété par table car Postgres ne permet pas une policy "sur toutes les tables" en une fois)
do $$
declare
    t text;
begin
    foreach t in array array[
        'config_compta', 'journal_audit_compta', 'caisse_mouvements', 'cheques',
        'remises_cheques', 'remise_cheques_details', 'banque_mouvements',
        'factures', 'caisse_physique_comptages', 'import_rapprochement'
    ]
    loop
        -- "drop policy if exists" avant chaque création : Postgres n'a pas
        -- de "create policy if not exists", donc sans ça, relancer ce
        -- script après une première installation échoue avec
        -- "policy ... already exists".
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

-- profils_compta : chacun voit uniquement sa propre ligne (évite d'exposer
-- la liste des comptes à tout le monde) ; seul l'admin peut la modifier.
drop policy if exists profils_compta_lecture on profils_compta;
create policy profils_compta_lecture on profils_compta
    for select using (user_id = auth.uid() or role_compta_courant() = 'admin');
drop policy if exists profils_compta_ecriture on profils_compta;
create policy profils_compta_ecriture on profils_compta
    for all using (role_compta_courant() = 'admin');

-- ============================================================
-- À COMPLÉTER : une fois les 2 comptes créés dans Supabase Auth,
-- remplacer les UUID ci-dessous et exécuter ces 2 lignes.
-- ============================================================
-- insert into profils_compta (user_id, email, role) values
--     ('<uuid-compta>',   'compta@archedemallo.fr',   'admin'),
--     ('<uuid-jonathan>', 'jonathan@archedemallo.fr', 'lecteur');
