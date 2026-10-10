-- ============================================================
-- 065_suppression_statut_en_observation.sql
--
-- Dépend de 030, 032, 047 et 060.
--
-- Les utilisateurs ne veulent plus du statut « en_observation ».
-- Le statut de départ d'un nouveau chat devient 'adoptable'.
--
-- 1. Données : les chats / lignes d'historique 'en_observation'
--    passent à 'adoptable' (une ligne en_observation directement
--    suivie d'une ligne adoptable est fusionnée, pour ne pas avoir
--    deux lignes adoptable consécutives dans l'historique).
-- 2. Contrainte de statut sans 'en_observation'.
-- 3. Transitions : plus de départ/arrivée 'en_observation'. Ce que
--    permettait en_observation et que adoptable n'avait pas est
--    ajouté à adoptable : non_adoptable, famille_accueil, relache.
-- 4. obtenir_transitions_possibles / changer_statut_animal : un
--    animal sans statut ne peut passer qu'à 'adoptable'.
-- 5. creer_arrivee_animal : statut initial 'adoptable' (reste
--    identique à 047 par ailleurs).
-- 6. rechercher_animaux : 'en_observation' retiré des listes
--    (reste identique à 060 par ailleurs).
-- ============================================================


-- 1. Données ---------------------------------------------------

-- 1a. en_observation suivie directement d'adoptable : l'adoptable
--     reprend la date de début de l'observation, l'observation est supprimée.
update animaux_statuts_historique a
set date_debut = o.date_debut
from animaux_statuts_historique o
where o.statut = 'en_observation'
  and a.statut = 'adoptable'
  and a.animal_id = o.animal_id
  and o.date_fin is not null
  and a.date_debut = o.date_fin;

delete from animaux_statuts_historique o
where o.statut = 'en_observation'
  and o.date_fin is not null
  and exists (
      select 1 from animaux_statuts_historique a
      where a.animal_id = o.animal_id
        and a.statut = 'adoptable'
        and a.date_debut = o.date_debut
        and a.id <> o.id
  );

-- 1b. Le reste (observation en cours, ou suivie d'un autre statut) devient adoptable.
update animaux_statuts_historique set statut = 'adoptable' where statut = 'en_observation';
update animaux set statut_actuel = 'adoptable' where statut_actuel = 'en_observation';


-- 2. Contrainte de statut ---------------------------------------
alter table animaux_statuts_historique drop constraint if exists animaux_statut_check;
alter table animaux_statuts_historique add constraint animaux_statut_check
    check (statut in ('adoptable', 'non_adoptable', 'malade',
        'decede', 'relache', 'reservation_annulee', 'reserve', 'au_veto',
        'famille_accueil', 'adopte'));


-- 3. Transitions ------------------------------------------------
delete from transitions_statut_animal
where statut_depart = 'en_observation' or statut_arrivee = 'en_observation';

insert into transitions_statut_animal (statut_depart, statut_arrivee) values
    ('adoptable', 'non_adoptable'),
    ('adoptable', 'famille_accueil'),
    ('adoptable', 'relache')
on conflict do nothing;


-- 4. Transitions possibles + changement de statut ---------------
create or replace function obtenir_transitions_possibles(p_statut_actuel text)
returns table (statut_arrivee text)
language sql
security definer
set search_path = public
stable
as $$
    select case when p_statut_actuel is null then 'adoptable'
           else t.statut_arrivee end
    from (select 1) x
    left join transitions_statut_animal t on t.statut_depart = p_statut_actuel
    where p_statut_actuel is null or t.statut_arrivee is not null;
$$;

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
        if p_statut <> 'adoptable' then
            raise exception 'Un animal sans statut ne peut passer qu''en adoptable (demandé : %).', p_statut;
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


-- 5. creer_arrivee_animal : statut initial 'adoptable' ----------
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
    p_saisi_par_id uuid default null,
    p_sexe text default null,
    p_espece text default 'chat',
    p_sterilise boolean default false,
    p_vermifuge boolean default false,
    p_antipuce boolean default false,
    p_autre_info text default null,
    p_nom_maman text default null,
    p_chaton boolean default false
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
    if p_sexe is not null and p_sexe not in ('M', 'F') then
        raise exception 'Sexe invalide : %', p_sexe;
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
        origine_arrivee, date_arrivee, personne_origine_id, sexe, espece, signes_particuliers, nom_maman, est_chaton)
    values (btrim(p_nom_usuel), p_couleur, p_date_naissance, p_puce,
        p_origine_arrivee, p_date_arrivee, v_personne_id, p_sexe,
        coalesce(nullif(btrim(p_espece), ''), 'chat'), nullif(btrim(p_autre_info), ''), nullif(btrim(p_nom_maman), ''), p_chaton)
    returning id into v_animal_id;

    perform changer_statut_animal(v_animal_id, 'adoptable', p_date_arrivee,
        coalesce(p_motif, p_origine_arrivee), p_saisi_par_id);

    if p_sterilise then
        insert into animaux_sterilisation (animal_id, sterilise, date_sterilisation, saisi_par)
        values (v_animal_id, true, p_date_arrivee, p_saisi_par_id)
        on conflict (animal_id) do update
            set sterilise = true, date_sterilisation = excluded.date_sterilisation,
                derniere_maj = now();
    end if;
    if p_vermifuge then
        insert into animaux_soins_veto (animal_id, date_soin, type_soin)
        values (v_animal_id, p_date_arrivee, 'vermifuge');
    end if;
    if p_antipuce then
        insert into animaux_soins_veto (animal_id, date_soin, type_soin)
        values (v_animal_id, p_date_arrivee, 'antipuce');
    end if;

    return v_animal_id;
end;
$$;


-- 6. rechercher_animaux : sans 'en_observation' -----------------
create or replace function rechercher_animaux(
    p_recherche text,
    p_contexte text default 'adoption'
)
returns table (
    id uuid, numero_interne text, nom_usuel text, nom_adoption text,
    statut_actuel text, puce text, couleur text
)
language plpgsql security definer set search_path = public stable
as $$
declare
    v_statuts text[];
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;

    case p_contexte
        when 'reservation' then v_statuts := array['adoptable'];
        when 'adoption' then v_statuts := array['adoptable', 'reserve'];
        when 'recherche' then v_statuts := array['adoptable', 'non_adoptable',
            'malade', 'relache', 'reservation_annulee', 'reserve', 'au_veto', 'famille_accueil'];
        when 'statuts' then v_statuts := array['adoptable', 'non_adoptable',
            'malade', 'reservation_annulee', 'reserve', 'au_veto', 'famille_accueil'];
        when 'accueil' then v_statuts := array['adoptable', 'non_adoptable',
            'malade', 'reservation_annulee', 'reserve', 'au_veto', 'famille_accueil'];
        else raise exception 'Contexte de recherche invalide : %', p_contexte;
    end case;

    return query
    select a.id, a.numero_interne, a.nom_usuel, a.nom_adoption, a.statut_actuel, a.puce, a.couleur
    from animaux a
    where a.statut_actuel = any(v_statuts)
      and (p_recherche is null or btrim(p_recherche) = ''
           or a.nom_usuel ilike '%' || btrim(p_recherche) || '%'
           or a.numero_interne ilike '%' || btrim(p_recherche) || '%')
    order by a.nom_usuel
    limit case when p_contexte = 'statuts' then 500 else 20 end;
end;
$$;
