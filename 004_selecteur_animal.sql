-- ============================================================
-- rechercher_animaux()
-- Recherche par nom, filtrée par statut. AVANT : le navigateur passait
-- directement p_statuts (ex: ['adoptable','reserve']) — comme la
-- fonction est security definer, elle ignore le RLS, donc rien
-- n'empêchait un appel RPC direct de demander n'importe quel statut,
-- y compris des statuts internes non destinés à un formulaire public
-- (ex: en_soins, décédé...). Corrigé : c'est desormais le serveur qui
-- décide des statuts autorisés, à partir d'un p_contexte nommé — le
-- navigateur ne peut plus choisir les statuts lui-même.
-- ============================================================
create or replace function rechercher_animaux(
    p_recherche text,
    p_contexte text default 'adoption'
)
returns table (
    id uuid,
    nom_usuel text,
    nom_adoption text,
    statut_actuel text,
    puce text,
    couleur text
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
    v_statuts text[];
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;
    v_statuts := case p_contexte
        when 'reservation' then array['adoptable']
        when 'adoption'    then array['adoptable', 'reserve']
        else null
    end;
    if v_statuts is null then
        raise exception 'Contexte de recherche invalide : %', p_contexte;
    end if;

    return query
    select a.id, a.nom_usuel, a.nom_adoption, a.statut_actuel, a.puce, a.couleur
    from animaux a
    where a.statut_actuel = any(v_statuts)
      and (p_recherche is null or btrim(p_recherche) = '' or a.nom_usuel ilike '%' || btrim(p_recherche) || '%')
    order by a.nom_usuel
    limit 20;
end;
$$;


-- ============================================================
-- obtenir_animal_pour_formulaire()
-- Toutes les infos d'un animal + (s'il est actuellement 'reserve') les
-- coordonnées de la personne qui l'a réservé, pour préremplir un
-- formulaire d'adoption sans tout retaper.
-- ============================================================
create or replace function obtenir_animal_pour_formulaire(p_animal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_animal jsonb;
    v_personne jsonb;
    v_reservation_id uuid;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;
    select to_jsonb(a) into v_animal
    from animaux a where a.id = p_animal_id;

    if v_animal is null then
        return null;
    end if;

    -- La table reservations n'a pas de colonne "statut" — une réservation
    -- annulée ne laisse pas de trace différente d'une réservation active.
    -- Le seul signal fiable est le statut ACTUEL de l'animal : on ne va
    -- chercher une personne que si l'animal est bien "reserve" en ce
    -- moment. Avant ce correctif, la fonction remontait systématiquement
    -- la réservation la plus récente même pour un animal redevenu
    -- adoptable — risque de préremplir un formulaire avec les
    -- coordonnées d'une personne qui n'a plus rien à voir avec l'animal.
    if (v_animal->>'statut_actuel') = 'reserve' then
        select r.id, to_jsonb(p) into v_reservation_id, v_personne
        from reservations r
        join personnes p on p.id = r.personne_id
        where r.animal_id = p_animal_id
        order by r.date_reservation desc nulls last
        limit 1;
    end if;

    return jsonb_build_object(
        'animal', v_animal,
        'personne', v_personne,
        'reservation_id', v_reservation_id
    );
end;
$$;


-- ============================================================
-- creer_adoption() — mise à jour :
--   - accepte un animal_id déjà connu (depuis le sélecteur) : évite le
--     rapprochement par nom, plus fiable
--   - fait progresser le statut de l'animal vers 'adopte' (ferme la
--     période de statut précédente dans animaux_statuts_historique,
--     en ouvre une nouvelle) — sinon un chat resterait "réservé" ou
--     "adoptable" indéfiniment, et continuerait à apparaître dans le
--     sélecteur alors qu'il est déjà adopté.
-- ============================================================
-- L'ancienne signature courte (sans p_animal_id) n'est plus définie dans
-- 003_fonctions_adoption_don.sql (retirée — une seule définition
-- désormais, ici). Ce DROP reste utile uniquement en migration, pour un
-- déploiement qui aurait exécuté l'ancienne version de 003 avant ce
-- correctif ; sur une installation neuve, il ne trouve rien à supprimer
-- et ne fait rien.
drop function if exists creer_adoption(
    text, text, text, text, text, text, text, text, text, text, text, date,
    text, text, text, numeric, numeric, numeric, numeric, numeric, date,
    text, jsonb, date, date, text, date, text, date, date, text, date,
    boolean, date
);

create or replace function creer_adoption(
    p_nom text,
    p_prenom text,
    p_civilite text default null,
    p_adresse text default null,
    p_code_postal text default null,
    p_ville text default null,
    p_email text default null,
    p_telephone text default null,
    p_nom_usuel text default null,
    p_nom_adoption text default null,
    p_couleur text default null,
    p_date_naissance_animal date default null,
    p_puce text default null,
    p_numero_carnet_sante text default null,
    p_nom_attestation text default null,
    p_tarif_particulier numeric default null,
    p_total_participation numeric default null,
    p_montant_virement numeric default null,
    p_montant_espece numeric default null,
    p_montant_cb numeric default null,
    p_date_fait date default null,
    p_saisi_par_id uuid default null,
    p_cheques jsonb default '[]'::jsonb,
    p_date_vaccin date default null,
    p_date_rappel_vaccin date default null,
    p_type_vaccin text default null,
    p_date_vermifuge date default null,
    p_produit_vermifuge text default null,
    p_prochain_vermifuge date default null,
    p_date_antipuces date default null,
    p_produit_antipuces text default null,
    p_prochain_antipuces date default null,
    p_date_certificat_veto date default null,
    p_sterilisation_cas1 boolean default false,
    p_date_sterilisation_cas1 date default null,
    p_animal_id uuid default null   -- <-- nouveau : animal déjà choisi via le sélecteur
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
    v_adoption_id uuid;
    v_cheque jsonb;
    v_date_transition date;
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
        insert into personnes (type_personne, civilite, nom, prenom, adresse,
            code_postal, ville, email, telephone)
        values ('particulier', p_civilite, btrim(p_nom), btrim(p_prenom), p_adresse,
            p_code_postal, p_ville, p_email, p_telephone)
        returning id into v_personne_id;
    end if;

    -- Animal : utilise l'id transmis par le sélecteur s'il existe (fiable),
    -- sinon repli sur le rapprochement par nom (saisie manuelle sans
    -- sélecteur, ex. formulaire pas encore branché dessus).
    if p_animal_id is not null then
        v_animal_id := p_animal_id;
    else
        select id into v_animal_id from animaux
        where upper(btrim(nom_usuel)) = upper(btrim(p_nom_usuel))
        limit 1;

        if v_animal_id is null then
            insert into animaux (nom_usuel, nom_adoption, couleur, date_naissance, puce)
            values (btrim(p_nom_usuel), p_nom_adoption, p_couleur, p_date_naissance_animal, p_puce)
            returning id into v_animal_id;
        end if;
    end if;

    update animaux set
        nom_adoption = coalesce(p_nom_adoption, nom_adoption),
        puce = coalesce(nullif(p_puce, ''), puce),
        numero_carnet_sante = coalesce(nullif(p_numero_carnet_sante, ''), numero_carnet_sante)
    where id = v_animal_id;

    if p_saisi_par_id is not null then
        if not exists (select 1 from utilisateurs where id = p_saisi_par_id and actif) then
            raise exception 'Personne non reconnue dans la liste des saisisseurs.';
        end if;
        v_utilisateur_id := p_saisi_par_id;
    end if;

    insert into adoptions (animal_id, personne_id, date_adoption, nom_attestation,
        tarif_particulier, total_participation, montant_virement, montant_espece,
        montant_cb, date_fait, saisi_par)
    values (v_animal_id, v_personne_id, p_date_fait, p_nom_attestation,
        p_tarif_particulier, p_total_participation, p_montant_virement, p_montant_espece,
        p_montant_cb, p_date_fait, v_utilisateur_id)
    returning id into v_adoption_id;

    for v_cheque in select * from jsonb_array_elements(coalesce(p_cheques, '[]'::jsonb))
    loop
        insert into adoptions_cheques (adoption_id, numero_cheque, montant)
        values (v_adoption_id, v_cheque->>'numero_cheque', nullif(v_cheque->>'montant', '')::numeric);
    end loop;

    if p_date_vaccin is not null then
        insert into animaux_soins_veto (animal_id, date_soin, type_soin, description, prochain_rappel)
        values (v_animal_id, p_date_vaccin, 'vaccination', p_type_vaccin, p_date_rappel_vaccin);
    end if;
    if p_date_vermifuge is not null then
        insert into animaux_soins_veto (animal_id, date_soin, type_soin, description, prochain_rappel)
        values (v_animal_id, p_date_vermifuge, 'vermifuge', p_produit_vermifuge, p_prochain_vermifuge);
    end if;
    if p_date_antipuces is not null then
        insert into animaux_soins_veto (animal_id, date_soin, type_soin, description, prochain_rappel)
        values (v_animal_id, p_date_antipuces, 'antipuce', p_produit_antipuces, p_prochain_antipuces);
    end if;
    if p_date_certificat_veto is not null then
        insert into animaux_soins_veto (animal_id, date_soin, type_soin)
        values (v_animal_id, p_date_certificat_veto, 'consultation');
    end if;

    if p_sterilisation_cas1 then
        insert into animaux_sterilisation (animal_id, sterilise, date_sterilisation)
        values (v_animal_id, true, p_date_sterilisation_cas1)
        on conflict (animal_id) do update
            set sterilise = true, date_sterilisation = excluded.date_sterilisation,
                derniere_maj = now();
    end if;

    -- Transition de statut : l'animal devient "adopte". On ferme la période
    -- de statut en cours (date_fin) et on en ouvre une nouvelle, pour ne
    -- pas perdre l'historique (ex: était "reserve" depuis telle date).
    v_date_transition := coalesce(p_date_fait, current_date);

    update animaux_statuts_historique
    set date_fin = v_date_transition
    where animal_id = v_animal_id and date_fin is null;

    insert into animaux_statuts_historique (animal_id, statut, date_debut, saisi_par)
    values (v_animal_id, 'adopte', v_date_transition, v_utilisateur_id);

    update animaux set statut_actuel = 'adopte' where id = v_animal_id;

    return v_adoption_id;
end;
$$;
