create or replace function creer_reservation(
    p_type_reservation text,
    p_nom text,
    p_prenom text,
    p_date_naissance_personne date default null,
    p_adresse text default null,
    p_code_postal text default null,
    p_ville text default null,
    p_telephone text default null,
    p_email text default null,
    p_nom_chat text default null,
    p_date_naissance_animal date default null,
    p_couleur text default null,
    p_identification text default null,
    p_signes_particuliers text default null,
    p_nom_maman text default null,       -- chaton uniquement
    p_superficie numeric default null,   -- chaton uniquement
    p_espece_autre text default null,    -- autre_animal uniquement (chien/lapin/texte libre)
    p_numero_box text default null,
    p_date_reservation date default null,
    p_montant_virement numeric default null,
    p_montant_espece numeric default null,
    p_montant_cb numeric default null,
    p_saisi_par_id uuid default null,
    p_cheques jsonb default '[]'::jsonb,
    p_animal_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_personne_id uuid;
    v_animal_id uuid;
    v_utilisateur_id uuid;
    v_reservation_id uuid;
    v_cheque jsonb;
    v_montant numeric;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;
    if p_nom is null or btrim(p_nom) = '' then
        raise exception 'Le nom est obligatoire';
    end if;
    if p_type_reservation not in ('chat', 'chaton', 'autre_animal') then
        raise exception 'Type de réservation invalide : %', p_type_reservation;
    end if;

    select id into v_personne_id from personnes
    where upper(btrim(nom)) = upper(btrim(p_nom))
      and coalesce(upper(btrim(prenom)), '') = coalesce(upper(btrim(p_prenom)), '')
    limit 1;

    if v_personne_id is null then
        insert into personnes (type_personne, nom, prenom, date_naissance, adresse,
            code_postal, ville, telephone, email)
        values ('particulier', btrim(p_nom), btrim(p_prenom), p_date_naissance_personne,
            p_adresse, p_code_postal, p_ville, p_telephone, p_email)
        returning id into v_personne_id;
    end if;

    -- Animal : id du sélecteur en priorité (fiable), sinon repli par nom
    if p_animal_id is not null then
        v_animal_id := p_animal_id;
    else
        select id into v_animal_id from animaux
        where upper(btrim(nom_usuel)) = upper(btrim(p_nom_chat))
        limit 1;

        if v_animal_id is null then
            insert into animaux (nom_usuel, couleur, date_naissance, puce, nom_maman, signes_particuliers)
            values (btrim(p_nom_chat), p_couleur, p_date_naissance_animal, p_identification,
                p_nom_maman, p_signes_particuliers)
            returning id into v_animal_id;
        end if;
    end if;

    update animaux set
        couleur = coalesce(nullif(p_couleur, ''), couleur),
        puce = coalesce(nullif(p_identification, ''), puce),
        nom_maman = coalesce(nullif(p_nom_maman, ''), nom_maman),
        signes_particuliers = coalesce(nullif(p_signes_particuliers, ''), signes_particuliers)
    where id = v_animal_id;

    if p_saisi_par_id is not null then
        if not exists (select 1 from utilisateurs where id = p_saisi_par_id and actif) then
            raise exception 'Personne non reconnue dans la liste des saisisseurs.';
        end if;
        v_utilisateur_id := p_saisi_par_id;
    end if;

    v_montant := coalesce(p_montant_virement, 0) + coalesce(p_montant_espece, 0) + coalesce(p_montant_cb, 0);

    insert into reservations (type_reservation, animal_id, personne_id, numero_box,
        date_reservation, montant, montant_virement, montant_espece, montant_cb,
        signes_particuliers, superficie, saisi_par)
    values (p_type_reservation, v_animal_id, v_personne_id, p_numero_box,
        p_date_reservation, nullif(v_montant, 0), p_montant_virement, p_montant_espece, p_montant_cb,
        p_signes_particuliers, p_superficie, v_utilisateur_id)
    returning id into v_reservation_id;

    for v_cheque in select * from jsonb_array_elements(coalesce(p_cheques, '[]'::jsonb))
    loop
        insert into reservations_cheques (reservation_id, numero_cheque, montant)
        values (v_reservation_id, v_cheque->>'numero_cheque', nullif(v_cheque->>'montant', '')::numeric);
    end loop;

    -- Transition de statut : adoptable -> reserve (ferme la période en cours,
    -- en ouvre une nouvelle, comme pour l'adoption)
    update animaux_statuts_historique
    set date_fin = coalesce(p_date_reservation, current_date)
    where animal_id = v_animal_id and date_fin is null;

    insert into animaux_statuts_historique (animal_id, statut, date_debut, saisi_par)
    values (v_animal_id, 'reserve', coalesce(p_date_reservation, current_date), v_utilisateur_id);

    update animaux set statut_actuel = 'reserve' where id = v_animal_id;

    return v_reservation_id;
end;
$$;
