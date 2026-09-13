create or replace function creer_depot_chat(
    p_nom text,
    p_prenom text default null,
    p_adresse text default null,
    p_code_postal text default null,
    p_ville text default null,
    p_telephone text default null,
    p_email text default null,
    p_commune text default null,
    p_date_depot date default null,
    p_nombre_chats integer default null,
    p_nombre_chatons integer default null,
    p_nombre_autres integer default null,
    p_preciser_autre text default null,
    p_date_fait date default null,
    p_saisi_par_id uuid default null
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
    v_personne_id uuid;
    v_utilisateur_id uuid;
    v_depot_id uuid;
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

    -- Le formulaire ne recense les animaux que par compteur global (pas
    -- d'identité individuelle) : nombre_chats/chatons/autres_historique
    -- sont donc utilisés ici aussi, pas seulement pour les données migrées
    -- — voir la conversation, point à reconsidérer si vous ajoutez un jour
    -- un choix d'animaux individuels sur ce formulaire.
    insert into depots_chat (personne_id, date_depot, commune, preciser_autre,
        nombre_chats_historique, nombre_chatons_historique, nombre_autres_historique, saisi_par)
    values (v_personne_id, p_date_depot, p_commune, p_preciser_autre,
        p_nombre_chats, p_nombre_chatons, p_nombre_autres, v_utilisateur_id)
    returning id into v_depot_id;

    return v_depot_id;
end;
$$;


create or replace function creer_abandon(
    p_nom text,
    p_prenom text default null,
    p_adresse text default null,
    p_code_postal text default null,
    p_ville text default null,
    p_telephone text default null,
    p_email text default null,
    p_nom_animal text default null,
    p_date_naissance_animal date default null,
    p_identification text default null,
    p_cause_abandon text default null,
    p_qualites text default null,
    p_defauts text default null,
    p_probleme_sante text default null,
    p_vaccins text default null,
    p_nom_attestation text default null,
    p_date_fait date default null,
    p_saisi_par_id uuid default null
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
    v_personne_id uuid;
    v_animal_id uuid;
    v_utilisateur_id uuid;
    v_abandon_id uuid;
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

    if p_nom_animal is not null and btrim(p_nom_animal) <> '' then
        select id into v_animal_id from animaux where upper(btrim(nom_usuel)) = upper(btrim(p_nom_animal)) limit 1;
        if v_animal_id is null then
            insert into animaux (nom_usuel, date_naissance, puce)
            values (btrim(p_nom_animal), p_date_naissance_animal, p_identification)
            returning id into v_animal_id;
        end if;
    end if;

    if p_saisi_par_id is not null then
        if not exists (select 1 from utilisateurs where id = p_saisi_par_id and actif) then
            raise exception 'Personne non reconnue dans la liste des saisisseurs.';
        end if;
        v_utilisateur_id := p_saisi_par_id;
    end if;

    insert into abandons (animal_id, personne_id, cause_abandon, problemes_sante, qualites,
        defauts, vaccins, date_fait, saisi_par)
    values (v_animal_id, v_personne_id, p_cause_abandon, p_probleme_sante, p_qualites,
        p_defauts, p_vaccins, p_date_fait, v_utilisateur_id)
    returning id into v_abandon_id;

    return v_abandon_id;
end;
$$;
