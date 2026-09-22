-- ============================================================
-- 041_fiche_animal_sterilisation_soins.sql
-- ============================================================
-- Étend obtenir_animal_avec_statuts() (utilisée par statuts_animaux.html)
-- pour inclure aussi la stérilisation (table animaux_sterilisation) et les
-- soins vétérinaires de type vermifuge/antipuce (table animaux_soins_veto),
-- qui vivent dans des tables séparées et n'étaient pas repris jusqu'ici.
-- Le type d'animal, le sexe et la date de naissance étaient déjà transmis
-- via to_jsonb(a) (table animaux) — rien à changer côté base pour eux,
-- seul l'affichage dans statuts_animaux.html manquait.
-- ============================================================

create or replace function obtenir_animal_avec_statuts(p_animal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_animal jsonb;
    v_statuts jsonb;
    v_sterilisation jsonb;
    v_derniere_vermifuge date;
    v_derniere_antipuce date;
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

    select to_jsonb(s) into v_sterilisation
    from animaux_sterilisation s
    where s.animal_id = p_animal_id;

    select max(date_soin) into v_derniere_vermifuge
    from animaux_soins_veto
    where animal_id = p_animal_id and type_soin = 'vermifuge';

    select max(date_soin) into v_derniere_antipuce
    from animaux_soins_veto
    where animal_id = p_animal_id and type_soin = 'antipuce';

    return jsonb_build_object(
        'animal', v_animal,
        'statuts', v_statuts,
        'sterilisation', v_sterilisation,
        'derniere_vermifuge', v_derniere_vermifuge,
        'derniere_antipuce', v_derniere_antipuce
    );
end;
$$;
