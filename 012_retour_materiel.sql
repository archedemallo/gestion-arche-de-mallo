create or replace function creer_retour_materiel(
    p_nom text,
    p_prenom text default null,
    p_email text default null,
    p_materiel text default null,
    p_numero_cage text default null,
    p_date_retour_effectif date default null,
    p_etat text default null,
    p_anomalies text default null,
    p_statut_caution text default null,
    p_montant_conserve numeric default null,
    p_montant_restitue numeric default null,
    p_mode_restitution text default null,
    p_numero_cheque_restitution text default null,
    p_date_fait date default null,
    p_saisi_par_id uuid default null
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
    v_personne_id uuid;
    v_utilisateur_id uuid;
    v_id uuid;
    v_description text;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;
    if p_nom is null or btrim(p_nom) = '' then
        raise exception 'Le nom est obligatoire';
    end if;

    select id into v_personne_id from personnes
    where upper(btrim(nom)) = upper(btrim(p_nom))
      and coalesce(upper(btrim(prenom)), '') = coalesce(upper(btrim(p_prenom)), '')
    limit 1;
    if v_personne_id is null then
        insert into personnes (type_personne, nom, prenom, email)
        values ('particulier', btrim(p_nom), btrim(p_prenom), p_email)
        returning id into v_personne_id;
    end if;

    if p_saisi_par_id is not null then
        if not exists (select 1 from utilisateurs where id = p_saisi_par_id and actif) then
            raise exception 'Personne non reconnue dans la liste des saisisseurs.';
        end if;
        v_utilisateur_id := p_saisi_par_id;
    end if;

    -- Même limite que pour le prêt : pas de colonnes dédiées pour
    -- état/caution/montants sur materiel_mouvements aujourd'hui, tout est
    -- décrit dans le texte "materiel" pour ne rien perdre.
    v_description := coalesce(p_materiel, '')
        || case when p_numero_cage is not null and p_numero_cage <> '' then ' | Cage n°' || p_numero_cage else '' end
        || case when p_etat is not null then ' | État : ' || p_etat else '' end
        || case when p_anomalies is not null and p_anomalies <> '' then ' | Anomalies : ' || p_anomalies else '' end
        || case when p_statut_caution is not null then ' | Caution : ' || p_statut_caution else '' end
        || case when p_montant_conserve is not null then ' | Conservé ' || p_montant_conserve || '€' else '' end
        || case when p_montant_restitue is not null then ' | Restitué ' || p_montant_restitue || '€' else '' end
        || case when p_mode_restitution is not null then ' | Mode : ' || p_mode_restitution else '' end;

    insert into materiel_mouvements (type_mouvement, personne_id, materiel, date_mouvement, saisi_par)
    values ('retour', v_personne_id, trim(both ' | ' from v_description),
        coalesce(p_date_retour_effectif, p_date_fait), v_utilisateur_id)
    returning id into v_id;

    return v_id;
end;
$$;
