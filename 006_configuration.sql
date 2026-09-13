-- ============================================================
-- CONFIGURATION COMPTA — types de mouvement, descriptions, listes
-- simples, fournisseurs, soldes initiaux.
-- ============================================================
-- SÉCURITÉ : toutes les fonctions d'écriture ci-dessous vérifient
-- désormais explicitement le rôle admin. Ce n'était PAS le cas dans la
-- version d'origine de ce fichier (écrite avant que l'authentification
-- Compta soit définie dans 015_auth_rls_compta.sql) : ces fonctions
-- "security definer" contournent le RLS par nature, donc sans ce
-- contrôle, n'importe qui connaissant la clé anon publique aurait pu
-- les appeler directement (créer un type de mouvement, changer un solde
-- initial...) sans être connecté. Toujours ajouter ce contrôle sur toute
-- nouvelle fonction d'écriture Compta.

-- ============================================================
-- TYPES DE MOUVEMENT (partagé Banque/Caisse/Chèques/Remises/Factures)
-- ============================================================
create or replace function ajouter_type_mouvement(p_valeur text, p_ordre integer default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    insert into types_mouvement (valeur, ordre) values (btrim(p_valeur), p_ordre)
    returning id into v_id;
    return v_id;
end;
$$;

create or replace function renommer_type_mouvement(p_id uuid, p_nouvelle_valeur text)
returns void language plpgsql security definer set search_path = public as $$
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    update types_mouvement set valeur = btrim(p_nouvelle_valeur) where id = p_id;
end;
$$;

-- Supprime le type ET ses descriptions (cascade déjà en place sur la FK).
-- N'affecte pas les mouvements/factures déjà saisis (type_mouvement y est
-- du texte libre, pas une FK) : seule la liste de choix future est réduite.
create or replace function supprimer_type_mouvement(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    delete from types_mouvement where id = p_id;
end;
$$;


-- ============================================================
-- DESCRIPTIONS (rattachées à un type de mouvement précis)
-- ============================================================
create or replace function ajouter_description(p_type_mouvement_id uuid, p_valeur text, p_ordre integer default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    insert into descriptions_mouvement (type_mouvement_id, valeur, ordre)
    values (p_type_mouvement_id, btrim(p_valeur), p_ordre)
    returning id into v_id;
    return v_id;
end;
$$;

create or replace function renommer_description(p_id uuid, p_nouvelle_valeur text)
returns void language plpgsql security definer set search_path = public as $$
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    update descriptions_mouvement set valeur = btrim(p_nouvelle_valeur) where id = p_id;
end;
$$;

create or replace function supprimer_description(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    delete from descriptions_mouvement where id = p_id;
end;
$$;


-- ============================================================
-- LISTES SIMPLES (modes de règlement, libellés complémentaires...) —
-- table config_listes. NE COUVRE PLUS LES PÉRIODES : voir plus bas,
-- unifiées sur config_compta pour rester cohérentes avec les pages
-- Caisse/Banque/Chèques/Remises/Factures/Caisse physique, qui lisent
-- toutes config_compta (cle='periodes') et non config_listes.
-- ============================================================
create or replace function ajouter_config_liste(p_categorie text, p_valeur text, p_ordre integer default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    if p_categorie = 'periodes' then raise exception 'Utiliser ajouter_periode() pour les périodes.'; end if;
    insert into config_listes (categorie, valeur, ordre) values (p_categorie, btrim(p_valeur), p_ordre)
    returning id into v_id;
    return v_id;
end;
$$;

create or replace function supprimer_config_liste(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    delete from config_listes where id = p_id;
end;
$$;


-- ============================================================
-- PÉRIODES — stockées dans config_compta (cle='periodes', valeur=jsonb
-- array de textes), lu directement par toutes les pages Compta.
-- ============================================================
create or replace function ajouter_periode(p_periode text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_actuelles jsonb;
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    if p_periode !~ '^\d{4} - \d{4}$' then
        raise exception 'Format invalide, attendu "2026 - 2027".';
    end if;
    select valeur into v_actuelles from config_compta where cle = 'periodes';
    v_actuelles := coalesce(v_actuelles, '[]'::jsonb);
    if v_actuelles ? p_periode then
        raise exception 'Cette période existe déjà.';
    end if;
    v_actuelles := v_actuelles || to_jsonb(p_periode);
    insert into config_compta (cle, valeur) values ('periodes', v_actuelles)
        on conflict (cle) do update set valeur = excluded.valeur, maj_le = now();
end;
$$;

create or replace function supprimer_periode(p_periode text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_actuelles jsonb;
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    select valeur into v_actuelles from config_compta where cle = 'periodes';
    if v_actuelles is null or jsonb_array_length(v_actuelles) <= 1 then
        raise exception 'Vous devez conserver au moins une période.';
    end if;
    select jsonb_agg(v) into v_actuelles from jsonb_array_elements(v_actuelles) v where v <> to_jsonb(p_periode);
    update config_compta set valeur = v_actuelles, maj_le = now() where cle = 'periodes';
end;
$$;


-- ============================================================
-- FOURNISSEURS — désactivation plutôt que suppression, pour ne pas
-- casser les factures/chèques/mouvements historiques qui les référencent
-- ============================================================
create or replace function ajouter_fournisseur(p_nom text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    insert into fournisseurs (nom, actif) values (btrim(p_nom), true)
    returning id into v_id;
    return v_id;
end;
$$;

create or replace function definir_actif_fournisseur(p_id uuid, p_actif boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    update fournisseurs set actif = p_actif where id = p_id;
end;
$$;


-- ============================================================
-- PARAMÈTRES (clé/valeur — ex: période courante)
-- ============================================================
create or replace function definir_parametre(p_cle text, p_valeur text)
returns void language plpgsql security definer set search_path = public as $$
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    insert into parametres (cle, valeur) values (p_cle, p_valeur)
    on conflict (cle) do update set valeur = excluded.valeur;
end;
$$;


-- ============================================================
-- SOLDES INITIAUX
-- ============================================================
create or replace function enregistrer_soldes_initiaux(
    p_periode text,
    p_solde_banque numeric,
    p_solde_caisse1 numeric,
    p_solde_caisse2 numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    insert into soldes (periode, compte, type_solde, montant) values (p_periode, 'banque', 'initial', p_solde_banque)
        on conflict (periode, compte, type_solde) do update set montant = excluded.montant;
    insert into soldes (periode, compte, type_solde, montant) values (p_periode, 'caisse1', 'initial', p_solde_caisse1)
        on conflict (periode, compte, type_solde) do update set montant = excluded.montant;
    insert into soldes (periode, compte, type_solde, montant) values (p_periode, 'caisse2', 'initial', p_solde_caisse2)
        on conflict (periode, compte, type_solde) do update set montant = excluded.montant;
end;
$$;

-- Solde final d'une période = solde initial + somme des mouvements de
-- cette période pour ce compte. Jamais stocké : toujours recalculé, pour
-- ne jamais diverger de la réalité des mouvements saisis.
-- p_compte : 'banque' -> banque_mouvements ; 'caisse1'/'caisse2' ->
-- caisse_mouvements (colonne caisse). Les deux tables réelles sont
-- créées dans 014_schema_compta.sql, exécuté après ce fichier — cette
-- fonction n'est donc utilisable qu'une fois 014 passé. Lecture seule :
-- pas de contrôle admin, accessible à tout compte Compta (lecteur inclus).
create or replace function obtenir_solde_final(p_periode text, p_compte text)
returns numeric
language plpgsql
security definer
set search_path = public
stable
as $$
declare
    v_initial numeric;
    v_mouvements numeric;
begin
    if role_compta_courant() is null then raise exception 'Accès refusé.'; end if;

    select montant into v_initial from soldes
        where periode = p_periode and compte = p_compte and type_solde = 'initial';
    v_initial := coalesce(v_initial, 0);

    if p_compte = 'banque' then
        select coalesce(sum(coalesce(credit,0) - coalesce(debit,0)), 0) into v_mouvements
            from banque_mouvements where periode = p_periode;
    elsif p_compte in ('caisse1', 'caisse2') then
        select coalesce(sum(coalesce(credit,0) - coalesce(debit,0)), 0) into v_mouvements
            from caisse_mouvements where periode = p_periode and caisse = p_compte;
    else
        raise exception 'Compte inconnu : % (attendu banque, caisse1 ou caisse2)', p_compte;
    end if;

    return v_initial + v_mouvements;
end;
$$;


-- ============================================================
-- GESTION DES COMPTES COMPTA (admin + lecteur)
-- ============================================================
-- Ajoute un accès Compta à un compte Supabase Auth DÉJÀ créé (Dashboard
-- Supabase > Authentication > Users > Add user). On ne peut pas créer le
-- compte de connexion lui-même depuis cette page (ça demande la clé
-- "service role", jamais exposée côté client) — seulement lui donner un
-- rôle une fois qu'il existe.
create or replace function ajouter_utilisateur_compta(p_email text, p_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid;
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    if p_role not in ('admin', 'lecteur') then raise exception 'Rôle invalide : % (attendu admin ou lecteur)', p_role; end if;

    select id into v_user_id from auth.users where email = p_email;
    if v_user_id is null then
        raise exception 'Aucun compte Supabase Auth trouvé pour %. Créez-le d''abord dans Supabase (Authentication > Users > Add user).', p_email;
    end if;

    insert into profils_compta (user_id, email, role) values (v_user_id, p_email, p_role)
        on conflict (user_id) do update set role = excluded.role, email = excluded.email;
end;
$$;

create or replace function modifier_role_utilisateur_compta(p_email text, p_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    if p_role not in ('admin', 'lecteur') then raise exception 'Rôle invalide : % (attendu admin ou lecteur)', p_role; end if;
    update profils_compta set role = p_role where email = p_email;
end;
$$;

create or replace function retirer_utilisateur_compta(p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then raise exception 'Accès refusé : réservé aux comptes admin.'; end if;
    if (select count(*) from profils_compta) <= 1 then
        raise exception 'Impossible de retirer le dernier compte Compta.';
    end if;
    delete from profils_compta where email = p_email;
end;
$$;
