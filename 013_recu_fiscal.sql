-- ============================================================
-- REÇUS FISCAUX (Cerfa 11580*05 particuliers / 16216*03 entreprises)
-- ============================================================
-- La table compteurs_recus_fiscaux (type, annee, dernier_numero) existe
-- déjà dans 001_schema_arche_de_mallo.sql, prête pour ça.
--
-- ATTENTION avant mise en production : le compteur démarre à 0 pour
-- chaque (type, année). Si des reçus ont déjà été émis cette année
-- (papier ou PDF, hors Supabase), positionnez le dernier numéro réel
-- AVANT le premier reçu généré depuis ce nouveau système, sinon vous
-- aurez deux reçus différents portant le même numéro :
--
--   select initialiser_compteur_recu_fiscal('particulier', 2026, 42);
--   select initialiser_compteur_recu_fiscal('entreprise', 2026, 3);
--
-- (42 = dernier numéro particulier déjà émis en 2026, le prochain sera 43)

create or replace function initialiser_compteur_recu_fiscal(p_type text, p_annee integer, p_dernier_numero integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;
    insert into compteurs_recus_fiscaux (type, annee, dernier_numero)
    values (p_type, p_annee, p_dernier_numero)
    on conflict (type, annee) do update set dernier_numero = excluded.dernier_numero;
end;
$$;

-- Alloue et renvoie le prochain numéro, de façon atomique : si deux
-- bénévoles génèrent un reçu au même moment, ils n'obtiennent jamais le
-- même numéro (contrainte unique (type, annee) + upsert).
--
-- Format par défaut : {P|E}-{ANNÉE}-{NUMÉRO sur 4 chiffres}, ex.
-- P-2026-0001. C'est un choix arbitraire de notre part — si vous avez
-- déjà une convention de numérotation (ex. suite de l'ancien système),
-- dites-le-moi et j'adapte cette fonction.
--
-- Différence volontaire avec l'ancien système : côté Apps Script, le
-- numéro était tiré à l'OUVERTURE du formulaire (donc un numéro était
-- perdu si le formulaire était ouvert puis abandonné sans sauvegarder).
-- Ici, le numéro n'est tiré qu'à la SAUVEGARDE (voir les formulaires),
-- ce qui évite ces trous inutiles dans la numérotation. Dites-le-moi si
-- vous préférez qu'on revienne au comportement identique à l'existant.
create or replace function numero_recu_fiscal_suivant(p_type text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    v_annee integer := extract(year from now())::integer;
    v_numero integer;
    v_prefixe text;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;
    if p_type not in ('particulier', 'entreprise') then
        raise exception 'Type de reçu fiscal invalide : %', p_type;
    end if;

    insert into compteurs_recus_fiscaux (type, annee, dernier_numero)
    values (p_type, v_annee, 1)
    on conflict (type, annee) do update
        set dernier_numero = compteurs_recus_fiscaux.dernier_numero + 1
    returning dernier_numero into v_numero;

    v_prefixe := case p_type when 'particulier' then 'P' else 'E' end;
    return v_prefixe || '-' || v_annee || '-' || lpad(v_numero::text, 4, '0');
end;
$$;

-- Rattache un numéro déjà généré au don d'origine (colonne
-- dons.numero_recu_fiscal, contrainte unique). Idempotent : si le don a
-- déjà un numéro, on ne l'écrase pas silencieusement — ça protège contre
-- un double-clic ou un rechargement de page qui rappellerait la fonction
-- avec un numéro différent.
create or replace function enregistrer_numero_recu_fiscal(p_don_id uuid, p_numero text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;
    update dons set numero_recu_fiscal = p_numero
    where id = p_don_id and numero_recu_fiscal is null;
end;
$$;
