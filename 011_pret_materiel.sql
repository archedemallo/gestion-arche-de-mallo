create or replace function creer_pret_materiel(
    p_nom text,
    p_prenom text default null,
    p_adresse text default null,
    p_code_postal text default null,
    p_ville text default null,
    p_telephone text default null,
    p_email text default null,
    p_materiel text default null,
    p_numero_cage text default null,
    p_date_prise_en_charge date default null,
    p_date_retour_prevue date default null,
    p_montant_caution numeric default null,
    p_date_fait date default null,
    p_saisi_par_id uuid default null
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
    v_personne_id uuid;
    v_utilisateur_id uuid;
    v_id uuid;
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
        insert into personnes (type_personne, nom, prenom, adresse, code_postal, ville, telephone, email)
        values ('particulier', btrim(p_nom), btrim(p_prenom), p_adresse, p_code_postal, p_ville, p_telephone, p_email)
        returning id into v_personne_id;
    end if;

    if p_saisi_par_id is not null then
        if not exists (select 1 from utilisateurs where id = p_saisi_par_id and actif) then
            raise exception 'Personne non reconnue dans la liste des saisisseurs.';
        end if;
        v_utilisateur_id := p_saisi_par_id;
    end if;

    -- p_numero_cage / p_date_retour_prevue / p_montant_caution : pas de
    -- colonne dédiée sur materiel_mouvements aujourd'hui, ajoutées dans le
    -- texte "materiel" pour ne rien perdre — à revoir si vous voulez ces
    -- infos structurées séparément.
    insert into materiel_mouvements (type_mouvement, personne_id, materiel, date_mouvement, saisi_par)
    values ('pret', v_personne_id,
        trim(both ' | ' from p_materiel
             || case when p_numero_cage is not null and p_numero_cage <> '' then ' | Cage n°' || p_numero_cage else '' end
             || case when p_montant_caution is not null then ' | Caution ' || p_montant_caution || '€' else '' end
             || case when p_date_retour_prevue is not null then ' | Retour prévu le ' || p_date_retour_prevue else '' end),
        coalesce(p_date_prise_en_charge, p_date_fait), v_utilisateur_id)
    returning id into v_id;

    return v_id;
end;
$$;
