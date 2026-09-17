-- ============================================================
-- 027_gestion_statuts_animaux.sql
--
-- Contexte : le parcours d'un chat (arrivée -> statuts internes ->
-- départ) était prévu dans le schéma (animaux_origine_check,
-- animaux_statut_check) mais très peu câblé côté formulaires :
--   - creer_depot_chat ne crée pas de fiche animal individuelle
--     (comptage global uniquement) — non traité ici, hors périmètre.
--   - creer_abandon créait bien une fiche animal mais ne renseignait
--     jamais origine_arrivee / date_arrivee / personne_origine_id, ni
--     statut_actuel / animaux_statuts_historique.
--   - creer_famille_accueil ne posait jamais le statut 'famille_accueil'.
--   - Aucune fonction ne permettait de poser les statuts sans
--     formulaire dédié : trappage (nouvelle origine), retour, décès,
--     relâche, transfert, au véto, en observation, non adoptable.
--   - rechercher_animaux() n'avait pas de contexte "sans filtre de
--     statut", alors que recherche_chat.html l'appelle déjà avec
--     p_contexte='recherche' (jusqu'ici en échec systématique : la
--     fonction levait "Contexte de recherche invalide").
--
-- Ce fichier :
--   1. Ajoute 'trappage' aux origines d'arrivée valides.
--   2. Ajoute le contexte 'recherche' (aucun filtre de statut) à
--      rechercher_animaux() — corrige au passage recherche_chat.html.
--   3. Ajoute changer_statut_animal(), fonction générique réutilisée
--      par la nouvelle page "Statuts" pour tout ce qui n'a pas de
--      formulaire dédié.
--   4. Ajoute creer_arrivee_animal(), pour déclarer l'arrivée d'un
--      animal sans passer par un dépôt/abandon (trappage, saisie,
--      né à l'association, transfert autre association).
--   5. Corrige creer_abandon() et creer_famille_accueil() pour qu'ils
--      posent réellement un statut/une origine à l'arrivée.
-- ============================================================


-- 1. 'trappage' ajouté aux origines d'arrivée valides.
alter table animaux drop constraint if exists animaux_origine_check;
alter table animaux add constraint animaux_origine_check
    check (origine_arrivee is null or origine_arrivee in
        ('depot', 'abandon', 'saisie', 'ne_a_association',
         'transfert_autre_association', 'trappage'));


-- 2. rechercher_animaux() : nouveau contexte 'recherche' = tous statuts.
--    Signature inchangée (CREATE OR REPLACE valide sans DROP).
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
    v_sans_filtre boolean := false;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;

    case p_contexte
        when 'reservation' then v_statuts := array['adoptable'];
        when 'adoption'    then v_statuts := array['adoptable', 'reserve'];
        when 'recherche'   then v_sans_filtre := true;
        else raise exception 'Contexte de recherche invalide : %', p_contexte;
    end case;

    return query
    select a.id, a.nom_usuel, a.nom_adoption, a.statut_actuel, a.puce, a.couleur
    from animaux a
    where (v_sans_filtre or a.statut_actuel = any(v_statuts))
      and (p_recherche is null or btrim(p_recherche) = '' or a.nom_usuel ilike '%' || btrim(p_recherche) || '%')
    order by a.nom_usuel
    limit 20;
end;
$$;


-- 3. Fonction générique de transition de statut — même logique que
--    celle déjà utilisée dans creer_reservation/creer_adoption (ferme
--    la période en cours, en ouvre une nouvelle, met à jour
--    statut_actuel), mais réutilisable pour n'importe quel statut.
create or replace function changer_statut_animal(
    p_animal_id uuid,
    p_statut text,
    p_date date default current_date,
    p_motif text default null,
    p_saisi_par_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_utilisateur_id uuid;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;
    if not exists (select 1 from animaux where id = p_animal_id) then
        raise exception 'Animal introuvable.';
    end if;
    if p_saisi_par_id is not null then
        if not exists (select 1 from utilisateurs where id = p_saisi_par_id and actif) then
            raise exception 'Personne non reconnue dans la liste des saisisseurs.';
        end if;
        v_utilisateur_id := p_saisi_par_id;
    end if;

    update animaux_statuts_historique
    set date_fin = p_date
    where animal_id = p_animal_id and date_fin is null;

    insert into animaux_statuts_historique (animal_id, statut, date_debut, motif, saisi_par)
    values (p_animal_id, p_statut, p_date, p_motif, v_utilisateur_id);

    update animaux set statut_actuel = p_statut where id = p_animal_id;
end;
$$;


-- 4. Déclarer l'arrivée d'un animal sans formulaire dédié (trappage,
--    saisie, né à l'association, transfert autre association — et
--    dépôt/abandon si besoin d'une saisie individuelle rapide).
create or replace function creer_arrivee_animal(
    p_nom_usuel text,
    p_origine_arrivee text,
    p_date_arrivee date default current_date,
    p_couleur text default null,
    p_date_naissance date default null,
    p_puce text default null,
    p_nom_personne text default null,
    p_prenom_personne text default null,
    p_motif text default null,
    p_saisi_par_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_animal_id uuid;
    v_personne_id uuid;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;
    if p_nom_usuel is null or btrim(p_nom_usuel) = '' then
        raise exception 'Le nom de l''animal est obligatoire';
    end if;
    if p_origine_arrivee not in ('depot', 'abandon', 'saisie', 'ne_a_association',
        'transfert_autre_association', 'trappage') then
        raise exception 'Origine d''arrivée invalide : %', p_origine_arrivee;
    end if;

    if p_nom_personne is not null and btrim(p_nom_personne) <> '' then
        select id into v_personne_id from personnes
        where upper(btrim(nom)) = upper(btrim(p_nom_personne))
          and coalesce(upper(btrim(prenom)), '') = coalesce(upper(btrim(p_prenom_personne)), '')
        limit 1;
        if v_personne_id is null then
            insert into personnes (type_personne, nom, prenom)
            values ('particulier', btrim(p_nom_personne), btrim(p_prenom_personne))
            returning id into v_personne_id;
        end if;
    end if;

    insert into animaux (nom_usuel, couleur, date_naissance, puce,
        origine_arrivee, date_arrivee, personne_origine_id)
    values (btrim(p_nom_usuel), p_couleur, p_date_naissance, p_puce,
        p_origine_arrivee, p_date_arrivee, v_personne_id)
    returning id into v_animal_id;

    perform changer_statut_animal(v_animal_id, 'arrive', p_date_arrivee,
        coalesce(p_motif, p_origine_arrivee), p_saisi_par_id);

    return v_animal_id;
end;
$$;


-- 4b. Fiche minimale (animal + historique de statut) pour la nouvelle
--     page Statuts. NB : recherche_chat.html appelle de son côté une
--     fonction 'obtenir_fiche_animal' qui n'existe dans AUCUNE
--     migration du dépôt — cette page est cassée depuis le début,
--     indépendamment de ce correctif. Pas traité ici (hors périmètre
--     demandé), à reprendre séparément si besoin.
create or replace function obtenir_animal_avec_statuts(p_animal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_animal jsonb;
    v_statuts jsonb;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;

    select to_jsonb(a) into v_animal from animaux a where a.id = p_animal_id;
    if v_animal is null then
        return null;
    end if;

    select coalesce(jsonb_agg(to_jsonb(h) order by h.date_debut desc), '[]'::jsonb)
    into v_statuts
    from animaux_statuts_historique h
    where h.animal_id = p_animal_id;

    return jsonb_build_object('animal', v_animal, 'statuts', v_statuts);
end;
$$;


-- 5a. creer_abandon() : pose désormais origine_arrivee/date_arrivee/
--     personne_origine_id + statut initial 'arrive' — uniquement quand
--     la fiche animal vient d'être créée (ne touche pas un animal déjà
--     suivi, pour ne pas écraser son historique).
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
    v_animal_nouveau boolean := false;
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
            insert into animaux (nom_usuel, date_naissance, puce,
                origine_arrivee, date_arrivee, personne_origine_id)
            values (btrim(p_nom_animal), p_date_naissance_animal, p_identification,
                'abandon', coalesce(p_date_fait, current_date), v_personne_id)
            returning id into v_animal_id;
            v_animal_nouveau := true;
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

    if v_animal_nouveau then
        perform changer_statut_animal(v_animal_id, 'arrive', coalesce(p_date_fait, current_date), null, p_saisi_par_id);
    end if;

    return v_abandon_id;
end;
$$;


-- 5b. creer_famille_accueil() : pose désormais le statut
--     'famille_accueil' à chaque placement (que la fiche animal soit
--     nouvelle ou déjà existante — le placement est bien l'événement).
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

    if v_animal_id is not null then
        perform changer_statut_animal(v_animal_id, 'famille_accueil',
            coalesce(p_date_debut, p_date_fait, current_date), p_type_accueil, p_saisi_par_id);
    end if;

    return v_fa_id;
end;
$$;
