-- ============================================================
-- AUTHENTIFICATION SUIVI — comptes individuels (comme Compta), suite à
-- la revue de code : les formulaires Suivi étaient jusqu'ici en accès
-- public, et leurs fonctions SECURITY DEFINER (creer_adhesion,
-- creer_don, etc.) étaient donc appelables directement par n'importe
-- qui connaissant la clé anon publique — inévitablement visible dans le
-- code source d'une page web. Toute personne qui saisit un formulaire
-- doit désormais avoir un compte Supabase Auth.
--
-- Contrairement à Compta, un seul niveau d'accès ici pour SAISIR : pas
-- de distinction admin/lecteur, tout compte Suivi peut lire et écrire
-- les formulaires (association de taille modeste, tous les bénévoles
-- habilités font la même chose).
--
-- En revanche, GÉRER qui a un compte (profils_suivi) et gérer la liste
-- des "saisi par" (utilisateurs) est réservé à l'admin Compta — sur
-- demande explicite, pour que ça ne soit pas ouvert à tout compte Suivi.
-- C'est fait depuis une carte dédiée dans configuration.html (Compta),
-- pas depuis une page Suivi.
--
-- ÉTAPE MANUELLE avant que ça fonctionne : créer un compte par bénévole
-- habilité dans Supabase (Authentication > Users > Add user), puis
-- l'ajouter à profils_suivi depuis la carte "Comptes Suivi" de
-- configuration.html (ou, pour le tout premier compte, via
-- ajouter_utilisateur_suivi() dans l'éditeur SQL Supabase).

create table if not exists profils_suivi (
    user_id  uuid primary key references auth.users(id) on delete cascade,
    email    text not null unique,
    nom      text,
    cree_le  timestamptz not null default now()
);

create or replace function role_suivi_courant()
returns text
language sql
security definer
set search_path = public
stable
as $$
    select email from profils_suivi where user_id = auth.uid();
$$;

-- Lecture ouverte à tout compte Suivi (chacun peut voir la liste des
-- comptes) ou à l'admin Compta. Écriture réservée à l'admin Compta.
alter table profils_suivi enable row level security;
drop policy if exists profils_suivi_lecture on profils_suivi;
create policy profils_suivi_lecture on profils_suivi
    for select using (role_suivi_courant() is not null or role_compta_courant() = 'admin');
drop policy if exists profils_suivi_ecriture on profils_suivi;
create policy profils_suivi_ecriture on profils_suivi
    for all using (role_compta_courant() = 'admin');

create or replace function ajouter_utilisateur_suivi(p_email text, p_nom text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé à l''admin Compta.';
    end if;
    select id into v_user_id from auth.users where email = p_email;
    if v_user_id is null then
        raise exception 'Aucun compte Supabase Auth trouvé pour %. Créez-le d''abord dans Supabase (Authentication > Users > Add user).', p_email;
    end if;
    insert into profils_suivi (user_id, email, nom) values (v_user_id, p_email, p_nom)
        on conflict (user_id) do update set email = excluded.email, nom = excluded.nom;
end;
$$;

create or replace function retirer_utilisateur_suivi(p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé à l''admin Compta.';
    end if;
    if (select count(*) from profils_suivi) <= 1 then
        raise exception 'Impossible de retirer le dernier compte Suivi.';
    end if;
    delete from profils_suivi where email = p_email;
end;
$$;

-- ============================================================
-- RLS sur toutes les tables Suivi (données des formulaires). Lecture :
-- un compte Suivi OU Compta (Compta a besoin de lire les
-- dons/adhésions/etc. pour le rapprochement bancaire, voir
-- 017_liens_mouvement_suivi.sql). Écriture : réservée aux comptes
-- Suivi — Compta ne modifie jamais ces tables. NE COUVRE PAS
-- "utilisateurs" : traitée séparément plus bas (droits différents).
-- ============================================================
do $$
declare
    t text;
begin
    foreach t in array array[
        'personnes', 'animaux', 'animaux_sterilisation',
        'animaux_statuts_historique', 'animaux_soins_veto', 'animaux_photos',
        'icad_suivi', 'adhesions', 'adhesions_cheques', 'dons', 'dons_cheques',
        'adoptions', 'adoptions_cheques', 'reservations', 'reservations_cheques',
        'depots_chat', 'depot_chat_animaux', 'abandons', 'familles_accueil',
        'attestations', 'materiel_mouvements', 'certificats_engagement',
        'soumission_fichiers'
    ]
    loop
        execute format('alter table %I enable row level security;', t);
        execute format('drop policy if exists %I on %I;', t || '_lecture', t);
        execute format(
            'create policy %I on %I for select using (role_suivi_courant() is not null or role_compta_courant() is not null);',
            t || '_lecture', t
        );
        execute format('drop policy if exists %I on %I;', t || '_ecriture', t);
        execute format(
            'create policy %I on %I for all using (role_suivi_courant() is not null);',
            t || '_ecriture', t
        );
    end loop;
end $$;

-- fournisseurs : table partagée Suivi/Compta (utilisée par les soins
-- vétérinaires côté Suivi ET les factures/chèques côté Compta) — lecture
-- pour l'un ou l'autre, écriture pour un compte Suivi OU un admin Compta.
alter table fournisseurs enable row level security;
drop policy if exists fournisseurs_lecture on fournisseurs;
create policy fournisseurs_lecture on fournisseurs
    for select using (role_suivi_courant() is not null or role_compta_courant() is not null);
drop policy if exists fournisseurs_ecriture on fournisseurs;
create policy fournisseurs_ecriture on fournisseurs
    for all using (role_suivi_courant() is not null or role_compta_courant() = 'admin');

-- ============================================================
-- LISTE DES "SAISI PAR" (table utilisateurs) — suite à la revue de
-- code : ce champ était un texte libre sur chaque formulaire, et
-- créait automatiquement un nouvel "utilisateur" à la moindre variante
-- de saisie ("Christophe" vs "Christophe Dupont" par exemple). C'est
-- maintenant une vraie liste fermée. Sur demande explicite, seul
-- l'admin Compta peut l'ajouter/la modifier (depuis configuration.html)
-- — un compte Suivi peut la LIRE (pour peupler le menu déroulant du
-- formulaire) mais pas la modifier.
--
-- Distinct de profils_suivi (les comptes de connexion) : une personne
-- peut apparaître dans la liste des saisisseurs sans avoir de compte de
-- connexion elle-même (ex: quelqu'un qui saisit occasionnellement sur
-- le poste d'un autre bénévole déjà connecté).
alter table utilisateurs enable row level security;
drop policy if exists utilisateurs_lecture on utilisateurs;
create policy utilisateurs_lecture on utilisateurs
    for select using (role_suivi_courant() is not null or role_compta_courant() is not null);
drop policy if exists utilisateurs_ecriture on utilisateurs;
create policy utilisateurs_ecriture on utilisateurs
    for all using (role_compta_courant() = 'admin');

create or replace function ajouter_saisisseur(p_nom text, p_email text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id uuid;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé à l''admin Compta.';
    end if;
    insert into utilisateurs (nom, email, actif)
    values (
        btrim(p_nom),
        coalesce(p_email, lower(regexp_replace(btrim(p_nom), '[^a-zA-Z0-9]+', '.', 'g')) || '@arche-import.local'),
        true
    )
    returning id into v_id;
    return v_id;
end;
$$;

create or replace function definir_actif_saisisseur(p_id uuid, p_actif boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé à l''admin Compta.';
    end if;
    update utilisateurs set actif = p_actif where id = p_id;
end;
$$;
