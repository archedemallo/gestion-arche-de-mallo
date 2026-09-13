create or replace function creer_famille_accueil(
    p_type_accueil text,
    p_nom text,
    p_prenom text default null,
    p_adresse text default null,
    p_code_postal text default null,
    p_ville text default null,
    p_telephone text default null,
    p_email text default null,
    p_nom_animal text default null,
    p_couleur text default null,
    p_date_naissance_animal date default null,
    p_puce text default null,
    p_date_debut date default null,
    p_date_fin date default null,
    p_date_fait date default null,
    p_saisi_par_id uuid default null
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
    v_personne_id uuid;
    v_animal_id uuid;
    v_utilisateur_id uuid;
    v_fa_id uuid;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;
    if p_nom is null or btrim(p_nom) = '' then
        raise exception 'Le nom est obligatoire';
    end if;
    if p_type_accueil not in ('provisoire', 'chat_libre', 'adoption') then
        raise exception 'Type de famille d''accueil invalide : %', p_type_accueil;
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
            insert into animaux (nom_usuel, couleur, date_naissance, puce)
            values (btrim(p_nom_animal), p_couleur, p_date_naissance_animal, p_puce)
            returning id into v_animal_id;
        else
            update animaux set
                couleur = coalesce(nullif(p_couleur, ''), couleur),
                puce = coalesce(nullif(p_puce, ''), puce)
            where id = v_animal_id;
        end if;
    end if;

    if p_saisi_par_id is not null then
        if not exists (select 1 from utilisateurs where id = p_saisi_par_id and actif) then
            raise exception 'Personne non reconnue dans la liste des saisisseurs.';
        end if;
        v_utilisateur_id := p_saisi_par_id;
    end if;

    insert into familles_accueil (type_accueil, personne_id, animal_id, date_debut, date_fin, date_fait, saisi_par)
    values (p_type_accueil, v_personne_id, v_animal_id, p_date_debut, p_date_fin, p_date_fait, v_utilisateur_id)
    returning id into v_fa_id;

    return v_fa_id;
end;
$$;
