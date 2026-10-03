-- ============================================================
-- 057_fiche_animal_origine_photo.sql
-- ============================================================
-- Étend obtenir_animal_avec_statuts() (041), utilisée par
-- statuts_animaux.html, avec :
--   - personne_origine : la personne qui a amené l'animal
--     (animaux.personne_origine_id -> personnes), pour afficher
--     "Dépôt — NOM Prénom" ;
--   - derniere_photo   : la photo la plus récente de l'animal
--     (animaux_photos, toutes origines confondues).
-- Le reste de la fonction est identique à 041.
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
    v_personne_origine jsonb;
    v_derniere_photo jsonb;
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

    select jsonb_build_object(
        'id', p.id, 'type_personne', p.type_personne, 'nom', p.nom,
        'prenom', p.prenom, 'raison_sociale', p.raison_sociale,
        'ville', p.ville, 'telephone', p.telephone, 'email', p.email)
    into v_personne_origine
    from personnes p
    where p.id = (v_animal->>'personne_origine_id')::uuid;

    select jsonb_build_object('url', ph.url, 'source', ph.source, 'cree_le', ph.cree_le)
    into v_derniere_photo
    from animaux_photos ph
    where ph.animal_id = p_animal_id
    order by ph.cree_le desc
    limit 1;

    return jsonb_build_object(
        'animal', v_animal,
        'statuts', v_statuts,
        'sterilisation', v_sterilisation,
        'derniere_vermifuge', v_derniere_vermifuge,
        'derniere_antipuce', v_derniere_antipuce,
        'personne_origine', v_personne_origine,
        'derniere_photo', v_derniere_photo
    );
end;
$$;
