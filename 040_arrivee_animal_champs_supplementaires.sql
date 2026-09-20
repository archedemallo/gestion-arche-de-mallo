-- ============================================================
-- 035_arrivee_animal_champs_supplementaires.sql
-- ============================================================
-- Étend creer_arrivee_animal() : le sexe et la date de naissance
-- existaient déjà côté base (table animaux) mais n'étaient pas
-- proposés dans le formulaire de déclaration d'arrivée. Ajoute en
-- plus : l'espèce (chat par défaut), stérilisé/vermifugé/antipuce
-- (posés à la date d'arrivée), et des notes libres.
-- ============================================================

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
    p_autre_info text default null
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
        origine_arrivee, date_arrivee, personne_origine_id, sexe, espece, signes_particuliers)
    values (btrim(p_nom_usuel), p_couleur, p_date_naissance, p_puce,
        p_origine_arrivee, p_date_arrivee, v_personne_id, p_sexe,
        coalesce(nullif(btrim(p_espece), ''), 'chat'), nullif(btrim(p_autre_info), ''))
    returning id into v_animal_id;

    perform changer_statut_animal(v_animal_id, 'en_observation', p_date_arrivee,
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
