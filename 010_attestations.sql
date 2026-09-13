create or replace function creer_attestation_cbs(
    p_nom text,
    p_prenom text default null,
    p_email text default null,
    p_nom_chat text default null,
    p_motif text default null,
    p_date_rdv_veto date default null,
    p_date_fait date default null,
    p_saisi_par_id uuid default null
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
    v_personne_id uuid;
    v_animal_id uuid;
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
        insert into personnes (type_personne, nom, prenom, email)
        values ('particulier', btrim(p_nom), btrim(p_prenom), p_email)
        returning id into v_personne_id;
    end if;

    if p_nom_chat is not null and btrim(p_nom_chat) <> '' then
        select id into v_animal_id from animaux where upper(btrim(nom_usuel)) = upper(btrim(p_nom_chat)) limit 1;
        if v_animal_id is null then
            insert into animaux (nom_usuel) values (btrim(p_nom_chat)) returning id into v_animal_id;
        end if;
    end if;

    if p_saisi_par_id is not null then
        if not exists (select 1 from utilisateurs where id = p_saisi_par_id and actif) then
            raise exception 'Personne non reconnue dans la liste des saisisseurs.';
        end if;
        v_utilisateur_id := p_saisi_par_id;
    end if;

    insert into attestations (type_attestation, animal_id, personne_id, motif, date_rdv_veto, date_fait, saisi_par)
    values ('cbs_absent', v_animal_id, v_personne_id, p_motif, p_date_rdv_veto, p_date_fait, v_utilisateur_id)
    returning id into v_id;

    return v_id;
end;
$$;


create or replace function creer_decharge_vaccin(
    p_nom text,
    p_prenom text default null,
    p_adresse text default null,
    p_code_postal text default null,
    p_ville text default null,
    p_telephone text default null,
    p_email text default null,
    p_nom_chat text default null,
    p_date_naissance_animal date default null,
    p_date_primo_vaccin date default null,
    p_date_limite_rappel date default null,
    p_date_fait date default null,
    p_saisi_par_id uuid default null
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
    v_personne_id uuid;
    v_animal_id uuid;
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

    if p_nom_chat is not null and btrim(p_nom_chat) <> '' then
        select id into v_animal_id from animaux where upper(btrim(nom_usuel)) = upper(btrim(p_nom_chat)) limit 1;
        if v_animal_id is null then
            insert into animaux (nom_usuel, date_naissance) values (btrim(p_nom_chat), p_date_naissance_animal)
            returning id into v_animal_id;
        end if;
    end if;

    if p_saisi_par_id is not null then
        if not exists (select 1 from utilisateurs where id = p_saisi_par_id and actif) then
            raise exception 'Personne non reconnue dans la liste des saisisseurs.';
        end if;
        v_utilisateur_id := p_saisi_par_id;
    end if;

    insert into attestations (type_attestation, animal_id, personne_id, date_naissance_animal,
        date_primo_vaccin, date_limite_rappel, date_fait, saisi_par)
    values ('decharge_vaccin', v_animal_id, v_personne_id, p_date_naissance_animal,
        p_date_primo_vaccin, p_date_limite_rappel, p_date_fait, v_utilisateur_id)
    returning id into v_id;

    return v_id;
end;
$$;
