-- ============================================================
-- 030_transitions_statut_animal.sql
--
-- Dépend de 027_gestion_statuts_animaux.sql. (029 est un correctif compta sans rapport, numéroté avant celui-ci.)
--
-- Remplace le schéma de statuts par la liste validée avec l'utilisateur
-- (tableau Chat.xlsx + ajustements) :
--   Origines (5)  : depot, abandon, saisie, ne_a_association, trappage
--                   (transfert_autre_association retiré : n'existe pas)
--   Statuts (11)  : en_observation (point de départ), adoptable,
--                   non_adoptable, malade, decede, relache,
--                   reservation_annulee, reserve, au_veto,
--                   famille_accueil, adopte
--   (arrive/retour/transfere retirés)
--
-- Ajoute une table de transitions autorisées et fait valider CHAQUE
-- changement de statut par changer_statut_animal() contre cette table
-- — y compris depuis creer_reservation et creer_adoption, qui posaient
-- jusqu'ici le statut directement sans passer par cette fonction (ce
-- qui permettait par ex. de "réserver" un animal déjà réservé).
--
-- Conséquence assumée : creer_reservation et creer_adoption exigent
-- désormais un p_animal_id non nul (animal déjà existant, choisi via
-- le sélecteur) — elles ne créent plus de fiche animal à la volée à
-- partir d'un simple nom tapé au clavier. Toute nouvelle fiche doit
-- passer par creer_arrivee_animal / creer_abandon / creer_famille_accueil
-- (page Statuts ou formulaires dédiés), qui posent le statut initial
-- 'en_observation'.
-- ============================================================


-- 1. Origines d'arrivée : retrait de transfert_autre_association
alter table animaux drop constraint if exists animaux_origine_check;
alter table animaux add constraint animaux_origine_check
    check (origine_arrivee is null or origine_arrivee in
        ('depot', 'abandon', 'saisie', 'ne_a_association', 'trappage'));


-- 2. Nouvelle liste de statuts
alter table animaux_statuts_historique drop constraint if exists animaux_statut_check;
alter table animaux_statuts_historique add constraint animaux_statut_check
    check (statut in ('en_observation', 'adoptable', 'non_adoptable', 'malade',
        'decede', 'relache', 'reservation_annulee', 'reserve', 'au_veto',
        'famille_accueil', 'adopte'));


-- 3. Table des transitions autorisées (le parcours du chat)
create table if not exists transitions_statut_animal (
    statut_depart text not null,
    statut_arrivee text not null,
    primary key (statut_depart, statut_arrivee)
);

truncate table transitions_statut_animal;

insert into transitions_statut_animal (statut_depart, statut_arrivee) values
    ('en_observation', 'adoptable'),
    ('en_observation', 'non_adoptable'),
    ('en_observation', 'malade'),
    ('en_observation', 'decede'),
    ('en_observation', 'au_veto'),
    ('en_observation', 'famille_accueil'),

    ('adoptable', 'reserve'),
    ('adoptable', 'adopte'),
    ('adoptable', 'malade'),
    ('adoptable', 'decede'),
    ('adoptable', 'au_veto'),

    ('au_veto', 'decede'),
    ('au_veto', 'adoptable'),
    ('au_veto', 'relache'),
    ('au_veto', 'reserve'),
    ('au_veto', 'non_adoptable'),
    ('au_veto', 'malade'),

    ('non_adoptable', 'au_veto'),
    ('non_adoptable', 'decede'),
    ('non_adoptable', 'relache'),
    ('non_adoptable', 'adoptable'),

    ('reserve', 'adopte'),
    ('reserve', 'malade'),
    ('reserve', 'decede'),
    ('reserve', 'reservation_annulee'),

    ('malade', 'au_veto'),
    ('malade', 'decede'),
    ('malade', 'non_adoptable'),
    ('malade', 'adoptable'),

    ('reservation_annulee', 'malade'),
    ('reservation_annulee', 'decede'),
    ('reservation_annulee', 'adoptable'),
    ('reservation_annulee', 'au_veto'),

    ('famille_accueil', 'adoptable'),
    ('famille_accueil', 'non_adoptable'),
    ('famille_accueil', 'malade'),
    ('famille_accueil', 'decede'),
    ('famille_accueil', 'relache'),
    ('famille_accueil', 'reserve'),
    ('famille_accueil', 'adopte');
    -- decede / relache / adopte : états finaux, aucune transition sortante


-- 4. obtenir_transitions_possibles() : pour peupler dynamiquement le
--    menu "nouveau statut" de la page Statuts selon le statut actuel.
create or replace function obtenir_transitions_possibles(p_statut_actuel text)
returns table (statut_arrivee text)
language sql
security definer
set search_path = public
stable
as $$
    select case when p_statut_actuel is null then 'en_observation'
           else t.statut_arrivee end
    from (select 1) x
    left join transitions_statut_animal t on t.statut_depart = p_statut_actuel
    where p_statut_actuel is null or t.statut_arrivee is not null;
$$;


-- 5. changer_statut_animal() : ajoute la validation de transition.
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
    v_statut_actuel text;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;

    select statut_actuel into v_statut_actuel from animaux where id = p_animal_id;
    if not found then
        raise exception 'Animal introuvable.';
    end if;

    if v_statut_actuel is null then
        if p_statut <> 'en_observation' then
            raise exception 'Un animal sans statut ne peut passer qu''en observation (demandé : %).', p_statut;
        end if;
    elsif v_statut_actuel = p_statut then
        raise exception 'L''animal est déjà au statut %.', p_statut;
    elsif not exists (
        select 1 from transitions_statut_animal
        where statut_depart = v_statut_actuel and statut_arrivee = p_statut
    ) then
        raise exception 'Transition non autorisée : % -> %.', v_statut_actuel, p_statut;
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


-- 6. creer_arrivee_animal() : statut initial 'en_observation' (plus 'arrive')
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
    if p_origine_arrivee not in ('depot', 'abandon', 'saisie', 'ne_a_association', 'trappage') then
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

    perform changer_statut_animal(v_animal_id, 'en_observation', p_date_arrivee,
        coalesce(p_motif, p_origine_arrivee), p_saisi_par_id);

    return v_animal_id;
end;
$$;


-- 7. creer_abandon() : statut initial 'en_observation' (au lieu de 'arrive')
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
        perform changer_statut_animal(v_animal_id, 'en_observation', coalesce(p_date_fait, current_date), null, p_saisi_par_id);
    end if;

    return v_abandon_id;
end;
$$;


-- 8. creer_famille_accueil() : passe par 'en_observation' si la fiche
--    vient d'être créée (le statut ne peut pas démarrer directement à
--    'famille_accueil'), puis transition vers 'famille_accueil'.
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
    v_animal_nouveau boolean := false;
    v_utilisateur_id uuid;
    v_fa_id uuid;
    v_date date;
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
            v_animal_nouveau := true;
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
        v_date := coalesce(p_date_debut, p_date_fait, current_date);
        if v_animal_nouveau then
            perform changer_statut_animal(v_animal_id, 'en_observation', v_date, null, p_saisi_par_id);
        end if;
        perform changer_statut_animal(v_animal_id, 'famille_accueil', v_date, p_type_accueil, p_saisi_par_id);
    end if;

    return v_fa_id;
end;
$$;


-- 9. creer_reservation() : passe par changer_statut_animal (validé) et
--    exige désormais un animal déjà existant (p_animal_id obligatoire) —
--    ne crée plus de fiche à la volée à partir d'un nom tapé au clavier.
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
    p_nom_maman text default null,
    p_superficie numeric default null,
    p_espece_autre text default null,
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
    if p_animal_id is null then
        raise exception 'Sélectionnez un animal existant (via son numéro interne) avant de réserver.';
    end if;
    v_animal_id := p_animal_id;

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

    perform changer_statut_animal(v_animal_id, 'reserve', coalesce(p_date_reservation, current_date), null, p_saisi_par_id);

    return v_reservation_id;
end;
$$;


-- 10. creer_adoption() : passe par changer_statut_animal (validé) et
--     exige désormais un animal déjà existant (p_animal_id obligatoire).
--     NB : la version en base contient déjà p_autres_motif/p_autres_montant
--     (ajoutés en direct sur Supabase) — repris ici en fin de liste pour
--     ne pas casser la signature existante.
create or replace function creer_adoption(p_nom text, p_prenom text, p_civilite text DEFAULT NULL::text, p_adresse text DEFAULT NULL::text, p_code_postal text DEFAULT NULL::text, p_ville text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_telephone text DEFAULT NULL::text, p_nom_usuel text DEFAULT NULL::text, p_nom_adoption text DEFAULT NULL::text, p_couleur text DEFAULT NULL::text, p_date_naissance_animal date DEFAULT NULL::date, p_puce text DEFAULT NULL::text, p_numero_carnet_sante text DEFAULT NULL::text, p_nom_attestation text DEFAULT NULL::text, p_tarif_particulier numeric DEFAULT NULL::numeric, p_total_participation numeric DEFAULT NULL::numeric, p_montant_virement numeric DEFAULT NULL::numeric, p_montant_espece numeric DEFAULT NULL::numeric, p_montant_cb numeric DEFAULT NULL::numeric, p_date_fait date DEFAULT NULL::date, p_saisi_par_id uuid DEFAULT NULL::uuid, p_cheques jsonb DEFAULT '[]'::jsonb, p_date_vaccin date DEFAULT NULL::date, p_date_rappel_vaccin date DEFAULT NULL::date, p_type_vaccin text DEFAULT NULL::text, p_date_vermifuge date DEFAULT NULL::date, p_produit_vermifuge text DEFAULT NULL::text, p_prochain_vermifuge date DEFAULT NULL::date, p_date_antipuces date DEFAULT NULL::date, p_produit_antipuces text DEFAULT NULL::text, p_prochain_antipuces date DEFAULT NULL::date, p_date_certificat_veto date DEFAULT NULL::date, p_sterilisation_cas1 boolean DEFAULT false, p_date_sterilisation_cas1 date DEFAULT NULL::date, p_animal_id uuid DEFAULT NULL::uuid, p_autres_motif text DEFAULT NULL::text, p_autres_montant numeric DEFAULT NULL::numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    if p_animal_id is null then
        raise exception 'Sélectionnez un animal existant (via son numéro interne) avant d''adopter.';
    end if;
    v_animal_id := p_animal_id;

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
        montant_cb, date_fait, saisi_par, autres_motif, autres_montant)
    values (v_animal_id, v_personne_id, p_date_fait, p_nom_attestation,
        p_tarif_particulier, p_total_participation, p_montant_virement, p_montant_espece,
        p_montant_cb, p_date_fait, v_utilisateur_id, p_autres_motif, p_autres_montant)
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

    v_date_transition := coalesce(p_date_fait, current_date);
    perform changer_statut_animal(v_animal_id, 'adopte', v_date_transition, null, p_saisi_par_id);

    return v_adoption_id;
end;
$function$;
