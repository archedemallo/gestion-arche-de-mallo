-- ============================================================
-- IMPORT DIRECT AVEC TYPE DE MOUVEMENT (onglet "Import banque")
-- ============================================================
-- Jusqu'ici, l'onglet Import banque ne faisait qu'insérer les lignes
-- dans import_rapprochement (statut 'en_attente') ; il fallait ensuite
-- aller dans l'onglet Rapprochement pour affecter un type de mouvement,
-- ligne par ligne ou en masse.
--
-- Cette fonction permet de sauter cette étape quand toutes les lignes
-- sélectionnées relèvent du même type de mouvement (ex. un relevé qui ne
-- contient que des dons, ou que des frais vétérinaires) : chaque ligne est
-- à la fois tracée dans import_rapprochement (déjà "rapprochée", pour
-- garder l'historique et la détection de doublons) et créée directement
-- dans caisse_mouvements / banque_mouvements.
--
-- Les lignes qui ne rentrent pas dans un type unique continuent de passer
-- par importer_lignes_rapprochement (import "en attente") puis par le
-- rapprochement individuel ou en masse, comme avant.
create or replace function importer_et_transferer_lignes(
    p_destination    text,
    p_lignes         jsonb,
    p_type_mouvement text,
    p_description    text default null,
    p_fournisseur    text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_item     jsonb;
    v_count    integer := 0;
    v_date     date;
    v_libelle  text;
    v_montant  numeric;
    v_periode  text;
    v_ligne_id uuid;
    v_mvt_id   uuid;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    if p_destination not in ('caisse1', 'caisse2', 'banque') then
        raise exception 'Destination invalide : % (attendu caisse1, caisse2 ou banque)', p_destination;
    end if;
    if p_type_mouvement is null or p_type_mouvement = '' then
        raise exception 'Le type de mouvement est obligatoire.';
    end if;
    perform valider_type_description(p_type_mouvement, p_description);

    for v_item in select * from jsonb_array_elements(p_lignes) loop
        v_date    := (v_item->>'date')::date;
        v_libelle := v_item->>'libelle';
        v_montant := (v_item->>'montant')::numeric;
        v_periode := v_item->>'periode';

        -- Trace de l'import, directement marquée "rapprochée" puisqu'on
        -- lui affecte tout de suite un type de mouvement.
        insert into import_rapprochement (
            destination, statut, date_mouvement, periode, libelle, montant,
            type_mouvement, description, date_import, date_rapprochement
        ) values (
            p_destination, 'rapprochee', v_date, v_periode, v_libelle, v_montant,
            p_type_mouvement, p_description, current_date, current_date
        )
        returning id into v_ligne_id;

        if p_destination = 'banque' then
            insert into banque_mouvements (
                date_mouvement, libelle, debit, credit, periode, type_mouvement, description,
                nom, fournisseur
            ) values (
                v_date, v_libelle,
                case when v_montant < 0 then abs(v_montant) else 0 end,
                case when v_montant > 0 then v_montant else 0 end,
                v_periode, p_type_mouvement, p_description,
                v_libelle, p_fournisseur
            )
            returning id into v_mvt_id;
        else
            insert into caisse_mouvements (
                caisse, date_mouvement, libelle, debit, credit, periode, type_mouvement, description,
                nom, fournisseur
            ) values (
                p_destination, v_date, v_libelle,
                case when v_montant < 0 then abs(v_montant) else 0 end,
                case when v_montant > 0 then v_montant else 0 end,
                v_periode, p_type_mouvement, p_description,
                v_libelle, p_fournisseur
            )
            returning id into v_mvt_id;
        end if;

        v_count := v_count + 1;
    end loop;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (
        auth.jwt() ->> 'email', 'AJOUT', 'import_rapprochement', null,
        format('%s ligne(s) importée(s) et affectée(s) directement au type "%s" vers %s', v_count, p_type_mouvement, p_destination)
    );

    return v_count;
end;
$$;
