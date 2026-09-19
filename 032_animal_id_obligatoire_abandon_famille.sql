-- ============================================================
-- 032_animal_id_obligatoire_abandon_famille.sql
--
-- Dépend de 030_transitions_statut_animal.sql (changer_statut_animal
-- avec validation des transitions).
--
-- Suite logique de 030 : creer_reservation et creer_adoption exigent
-- déjà un animal existant (p_animal_id). Ce fichier applique la même
-- règle à creer_abandon et creer_famille_accueil : elles n'acceptent
-- plus qu'un animal soit créé à la volée à partir d'un nom tapé au
-- clavier — l'animal doit déjà exister (créé au préalable via la page
-- Statuts / creer_arrivee_animal), choisi par p_animal_id.
-- ============================================================


-- creer_abandon() : p_animal_id obligatoire, plus de création inline.
-- L'abandon ne fait plus lui-même transitionner le statut (l'arrivée et
-- son statut initial 'en_observation' sont désormais du ressort exclusif
-- de la page Statuts) : il se contente d'enregistrer les informations
-- propres à l'abandon (cause, état de santé, etc.) pour un animal déjà
-- suivi.
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
    p_saisi_par_id uuid default null,
    p_animal_id uuid default null
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
    if p_animal_id is null then
        raise exception 'Sélectionnez un animal existant (via son numéro interne) avant d''enregistrer l''abandon.';
    end if;
    v_animal_id := p_animal_id;

    select id into v_personne_id from personnes
    where upper(btrim(nom)) = upper(btrim(p_nom))
      and coalesce(upper(btrim(prenom)), '') = coalesce(upper(btrim(p_prenom)), '')
    limit 1;
    if v_personne_id is null then
        insert into personnes (type_personne, nom, prenom, adresse, code_postal, ville, telephone, email)
        values ('particulier', btrim(p_nom), btrim(p_prenom), p_adresse, p_code_postal, p_ville, p_telephone, p_email)
        returning id into v_personne_id;
    end if;

    update animaux set
        date_naissance = coalesce(date_naissance, p_date_naissance_animal),
        puce = coalesce(nullif(p_identification, ''), puce)
    where id = v_animal_id;

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


-- creer_famille_accueil() : p_animal_id obligatoire, plus de création
-- inline. Continue de transitionner le statut vers 'famille_accueil'
-- (c'est bien le rôle de ce formulaire), via changer_statut_animal —
-- donc validé contre le parcours autorisé comme tout le reste.
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
    p_saisi_par_id uuid default null,
    p_animal_id uuid default null
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
    if p_animal_id is null then
        raise exception 'Sélectionnez un animal existant (via son numéro interne) avant d''enregistrer le placement.';
    end if;
    v_animal_id := p_animal_id;

    select id into v_personne_id from personnes
    where upper(btrim(nom)) = upper(btrim(p_nom))
      and coalesce(upper(btrim(prenom)), '') = coalesce(upper(btrim(p_prenom)), '')
    limit 1;
    if v_personne_id is null then
        insert into personnes (type_personne, nom, prenom, adresse, code_postal, ville, telephone, email)
        values ('particulier', btrim(p_nom), btrim(p_prenom), p_adresse, p_code_postal, p_ville, p_telephone, p_email)
        returning id into v_personne_id;
    end if;

    update animaux set
        couleur = coalesce(nullif(p_couleur, ''), couleur),
        puce = coalesce(nullif(p_puce, ''), puce)
    where id = v_animal_id;

    if p_saisi_par_id is not null then
        if not exists (select 1 from utilisateurs where id = p_saisi_par_id and actif) then
            raise exception 'Personne non reconnue dans la liste des saisisseurs.';
        end if;
        v_utilisateur_id := p_saisi_par_id;
    end if;

    insert into familles_accueil (type_accueil, personne_id, animal_id, date_debut, date_fin, date_fait, saisi_par)
    values (p_type_accueil, v_personne_id, v_animal_id, p_date_debut, p_date_fin, p_date_fait, v_utilisateur_id)
    returning id into v_fa_id;

    perform changer_statut_animal(v_animal_id, 'famille_accueil',
        coalesce(p_date_debut, p_date_fait, current_date), p_type_accueil, p_saisi_par_id);

    return v_fa_id;
end;
$$;
