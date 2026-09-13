-- ============================================================
-- IMPORT / RAPPROCHEMENT
-- ============================================================
-- Reprend import.html + import-rapprochement.html. NON REPRIS : tout le
-- système "import-suivi" (import-suivi.html / -refresh / -archive) qui
-- copiait les données du tableur Suivi vers le tableur Compta — ce
-- mécanisme n'a plus de raison d'être : Suivi et Compta vivent
-- maintenant dans la même base Supabase, donc caisse_mouvement_suivi_liens
-- et banque_mouvement_suivi_liens (017_liens_mouvement_suivi.sql) relient
-- directement les enregistrements par clé étrangère, sans copie.
--
-- p_lignes (import en masse) : jsonb, ex.
--   '[{"date":"2026-03-05","libelle":"VIR SEPA...","montant":100.00,
--      "periode":"2025 - 2026"}]'
-- montant signé : positif = crédit (entrée), négatif = débit (sortie).

create or replace function importer_lignes_rapprochement(p_destination text, p_lignes jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_item jsonb;
    v_count integer := 0;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    if p_destination not in ('caisse1', 'caisse2', 'banque') then
        raise exception 'Destination invalide : % (attendu caisse1, caisse2 ou banque)', p_destination;
    end if;

    for v_item in select * from jsonb_array_elements(p_lignes) loop
        insert into import_rapprochement (
            destination, statut, date_mouvement, periode, libelle, montant, date_import
        ) values (
            p_destination, 'en_attente', (v_item->>'date')::date, v_item->>'periode',
            v_item->>'libelle', (v_item->>'montant')::numeric, current_date
        );
        v_count := v_count + 1;
    end loop;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'AJOUT', 'import_rapprochement', null, format('%s ligne(s) importée(s) vers %s', v_count, p_destination));

    return v_count;
end;
$$;

-- Transfère une ligne en attente vers caisse_mouvements ou
-- banque_mouvements (selon sa destination) et la marque "rapprochée".
-- p_type_mouvement/p_description sont saisis au moment du transfert (pas
-- à l'import) car le CSV bancaire ne les connaît pas.
create or replace function transferer_import_rapprochement(
    p_id             uuid,
    p_type_mouvement text,
    p_description    text default null,
    p_nom_chat       text default null,
    p_numero_recu    text default null,
    p_fournisseur    text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_ligne import_rapprochement%rowtype;
    v_id uuid;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select * into v_ligne from import_rapprochement where id = p_id;
    if v_ligne.id is null then raise exception 'Ligne introuvable.'; end if;
    if v_ligne.statut <> 'en_attente' then raise exception 'Cette ligne a déjà été traitée.'; end if;
    if p_type_mouvement is null or p_type_mouvement = '' then raise exception 'Le type de mouvement est obligatoire.'; end if;
    perform valider_type_description(p_type_mouvement, p_description);

    if v_ligne.destination = 'banque' then
        insert into banque_mouvements (
            date_mouvement, libelle, debit, credit, periode, type_mouvement, description,
            nom, nom_chat, numero_don_fiscal, fournisseur
        ) values (
            v_ligne.date_mouvement, v_ligne.libelle,
            case when v_ligne.montant < 0 then abs(v_ligne.montant) else 0 end,
            case when v_ligne.montant > 0 then v_ligne.montant else 0 end,
            v_ligne.periode, p_type_mouvement, p_description,
            v_ligne.libelle, p_nom_chat, p_numero_recu, p_fournisseur
        )
        returning id into v_id;
    else
        insert into caisse_mouvements (
            caisse, date_mouvement, libelle, debit, credit, periode, type_mouvement, description,
            nom, nom_chat, numero_recu, fournisseur
        ) values (
            v_ligne.destination, v_ligne.date_mouvement, v_ligne.libelle,
            case when v_ligne.montant < 0 then abs(v_ligne.montant) else 0 end,
            case when v_ligne.montant > 0 then v_ligne.montant else 0 end,
            v_ligne.periode, p_type_mouvement, p_description,
            v_ligne.libelle, p_nom_chat, p_numero_recu, p_fournisseur
        )
        returning id into v_id;
    end if;

    update import_rapprochement set statut = 'rapprochee', date_rapprochement = current_date where id = p_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'import_rapprochement', p_id::text, 'Transférée vers ' || v_ligne.destination);

    return v_id;
end;
$$;

create or replace function ignorer_import_rapprochement(p_id uuid, p_motif text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    update import_rapprochement set statut = 'ignoree', motif_ignore = p_motif where id = p_id and statut = 'en_attente';
end;
$$;

-- Remet une ligne ignorée ou déjà rapprochée en attente (ne supprime
-- jamais le mouvement déjà créé en caisse/banque si elle était
-- rapprochée — à faire manuellement si besoin, pour éviter de perdre la
-- trace d'une double saisie).
create or replace function rouvrir_import_rapprochement(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    update import_rapprochement set statut = 'en_attente', motif_ignore = null where id = p_id;
end;
$$;

create or replace function supprimer_import_rapprochement(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    delete from import_rapprochement where id = p_id;
end;
$$;
