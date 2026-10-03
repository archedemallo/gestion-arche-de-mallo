-- ============================================================
-- 058_import_suivi.sql
-- Onglet "Import Suivi" (import_rapprochement.html), inspiré de l'ancien
-- import-suivi.html : les dons / adoptions / adhésions / réservations
-- saisis dans Suivi sont proposés par catégorie, puis envoyés dans la
-- file de rapprochement (import_rapprochement, statut 'en_attente').
--
-- Une ligne = un enregistrement Suivi x un mode de règlement
-- (espèces -> caisse, virement / CB -> banque). Les chèques passent par
-- les remises de chèques (lier_remise_cheque_suivi), pas par ici.
--
-- Au transfert, le lien Suivi est créé automatiquement dans
-- caisse_mouvement_suivi_liens / banque_mouvement_suivi_liens : plus
-- besoin de "+ lier" à la main.
-- ============================================================

alter table import_rapprochement add column if not exists suivi_type text;
alter table import_rapprochement add column if not exists suivi_id   uuid;
alter table import_rapprochement add column if not exists suivi_mode text;
create index if not exists idx_import_rapprochement_suivi on import_rapprochement(suivi_type, suivi_id);

-- p_lignes : [{suivi_type, suivi_id, mode, destination, date, periode, libelle,
--              montant, type_mouvement, description, nom_chat, numero_recu}]
-- suivi_type : adhesion | don | adoption | reservation
-- Renvoie le nombre de lignes créées (les déjà importées sont ignorées).
create or replace function importer_suivi_vers_rapprochement(p_lignes jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_item  jsonb;
    v_count integer := 0;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;

    for v_item in select * from jsonb_array_elements(p_lignes) loop
        if (v_item->>'suivi_type') not in ('adhesion','don','adoption','reservation') then
            raise exception 'Type Suivi invalide : %', v_item->>'suivi_type';
        end if;
        if (v_item->>'destination') not in ('caisse1','caisse2','banque') then
            raise exception 'Destination invalide : %', v_item->>'destination';
        end if;
        if exists (
            select 1 from import_rapprochement
            where suivi_type = v_item->>'suivi_type'
              and suivi_id   = (v_item->>'suivi_id')::uuid
              and suivi_mode = v_item->>'mode'
              and statut <> 'ignoree'
        ) then
            continue;
        end if;

        insert into import_rapprochement (
            onglet, statut, destination, date_mouvement, periode, libelle, montant,
            type_mouvement, mode_reglement, nom_chat, numero_recu, description,
            date_import, suivi_type, suivi_id, suivi_mode
        ) values (
            'suivi', 'en_attente', v_item->>'destination', (v_item->>'date')::date,
            v_item->>'periode', v_item->>'libelle', (v_item->>'montant')::numeric,
            nullif(v_item->>'type_mouvement',''), v_item->>'mode', nullif(v_item->>'nom_chat',''),
            nullif(v_item->>'numero_recu',''), nullif(v_item->>'description',''),
            current_date, v_item->>'suivi_type', (v_item->>'suivi_id')::uuid, v_item->>'mode'
        );
        v_count := v_count + 1;
    end loop;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'AJOUT', 'import_rapprochement', null,
            format('%s ligne(s) Suivi envoyée(s) en attente de rapprochement', v_count));
    return v_count;
end;
$$;

-- Même signature qu'en 023 ; ajouts : reprise du mode/chat/reçu venant de
-- Suivi, et création automatique du lien Suivi sur le mouvement créé.
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
    v_chat text;
    v_recu text;
    v_desc text;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select * into v_ligne from import_rapprochement where id = p_id;
    if v_ligne.id is null then raise exception 'Ligne introuvable.'; end if;
    if v_ligne.statut <> 'en_attente' then raise exception 'Cette ligne a déjà été traitée.'; end if;
    if p_type_mouvement is null or p_type_mouvement = '' then raise exception 'Le type de mouvement est obligatoire.'; end if;

    v_chat := coalesce(nullif(p_nom_chat,''), v_ligne.nom_chat);
    v_recu := coalesce(nullif(p_numero_recu,''), v_ligne.numero_recu);
    v_desc := coalesce(nullif(p_description,''), v_ligne.description);
    perform valider_type_description(p_type_mouvement, v_desc);

    if v_ligne.destination = 'banque' then
        insert into banque_mouvements (
            date_mouvement, libelle, debit, credit, periode, type_mouvement, description,
            nom, nom_chat, numero_don_fiscal, fournisseur, mode_reglement
        ) values (
            v_ligne.date_mouvement, v_ligne.libelle,
            case when v_ligne.montant < 0 then abs(v_ligne.montant) else 0 end,
            case when v_ligne.montant > 0 then v_ligne.montant else 0 end,
            v_ligne.periode, p_type_mouvement, v_desc,
            v_ligne.libelle, v_chat, v_recu, p_fournisseur, v_ligne.mode_reglement
        ) returning id into v_id;

        if v_ligne.suivi_id is not null then
            insert into banque_mouvement_suivi_liens (banque_mouvement_id, adhesion_id, don_id, adoption_id, reservation_id, montant)
            values (v_id,
                case when v_ligne.suivi_type = 'adhesion'    then v_ligne.suivi_id end,
                case when v_ligne.suivi_type = 'don'         then v_ligne.suivi_id end,
                case when v_ligne.suivi_type = 'adoption'    then v_ligne.suivi_id end,
                case when v_ligne.suivi_type = 'reservation' then v_ligne.suivi_id end,
                abs(v_ligne.montant));
        end if;
    else
        insert into caisse_mouvements (
            caisse, date_mouvement, libelle, debit, credit, periode, type_mouvement, description,
            nom, nom_chat, numero_recu, fournisseur, reglement
        ) values (
            v_ligne.destination, v_ligne.date_mouvement, v_ligne.libelle,
            case when v_ligne.montant < 0 then abs(v_ligne.montant) else 0 end,
            case when v_ligne.montant > 0 then v_ligne.montant else 0 end,
            v_ligne.periode, p_type_mouvement, v_desc,
            v_ligne.libelle, v_chat, v_recu, p_fournisseur, v_ligne.mode_reglement
        ) returning id into v_id;

        if v_ligne.suivi_id is not null then
            insert into caisse_mouvement_suivi_liens (caisse_mouvement_id, adhesion_id, don_id, adoption_id, reservation_id, montant)
            values (v_id,
                case when v_ligne.suivi_type = 'adhesion'    then v_ligne.suivi_id end,
                case when v_ligne.suivi_type = 'don'         then v_ligne.suivi_id end,
                case when v_ligne.suivi_type = 'adoption'    then v_ligne.suivi_id end,
                case when v_ligne.suivi_type = 'reservation' then v_ligne.suivi_id end,
                abs(v_ligne.montant));
        end if;
    end if;

    update import_rapprochement set statut = 'rapprochee', date_rapprochement = current_date where id = p_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'import_rapprochement', p_id::text, 'Transférée vers ' || v_ligne.destination);

    return v_id;
end;
$$;
