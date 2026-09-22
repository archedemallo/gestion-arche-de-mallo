-- ============================================================
-- 042_obtenir_fiche_animal.sql
-- ============================================================
-- Crée la fonction obtenir_fiche_animal(), appelée par
-- recherche_chat.html mais absente de toutes les migrations
-- précédentes du dépôt (repéré en 027 et signalé, jamais traité) —
-- la page était cassée depuis le début, indépendamment de tout le
-- reste. Reprend le même principe qu'obtenir_animal_avec_statuts()
-- (voir 027 / 041) en l'étendant à toutes les informations que la
-- page affiche : stérilisation, historique de statut, soins
-- vétérinaires, et l'historique complet (adoptions, réservations,
-- dépôts, abandons, familles d'accueil, attestations), chacun avec
-- la personne concernée et les fichiers associés (soumission_fichiers,
-- table pas encore utilisée par l'appli — retournera '[]' pour
-- l'instant, prêt pour quand l'upload de documents sera branché).
-- ============================================================

create or replace function obtenir_fiche_animal(p_animal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_animal jsonb;
    v_sterilisation jsonb;
    v_statuts jsonb;
    v_soins jsonb;
    v_adoptions jsonb;
    v_reservations jsonb;
    v_depots jsonb;
    v_abandons jsonb;
    v_familles_accueil jsonb;
    v_attestations jsonb;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;

    select to_jsonb(a) into v_animal from animaux a where a.id = p_animal_id;
    if v_animal is null then
        return null;
    end if;

    select to_jsonb(s) into v_sterilisation
    from animaux_sterilisation s
    where s.animal_id = p_animal_id;

    select coalesce(jsonb_agg(to_jsonb(h) order by h.date_debut desc), '[]'::jsonb)
    into v_statuts
    from animaux_statuts_historique h
    where h.animal_id = p_animal_id;

    select coalesce(jsonb_agg(to_jsonb(sv) order by sv.date_soin desc), '[]'::jsonb)
    into v_soins
    from animaux_soins_veto sv
    where sv.animal_id = p_animal_id;

    select coalesce(jsonb_agg(
        to_jsonb(ad) || jsonb_build_object(
            'personne', to_jsonb(p),
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'adoptions' and f.enregistrement_id = ad.id
            ), '[]'::jsonb)
        )
        order by ad.date_adoption desc
    ), '[]'::jsonb)
    into v_adoptions
    from adoptions ad
    left join personnes p on p.id = ad.personne_id
    where ad.animal_id = p_animal_id;

    select coalesce(jsonb_agg(
        to_jsonb(r) || jsonb_build_object(
            'personne', to_jsonb(p),
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'reservations' and f.enregistrement_id = r.id
            ), '[]'::jsonb)
        )
        order by r.date_reservation desc
    ), '[]'::jsonb)
    into v_reservations
    from reservations r
    left join personnes p on p.id = r.personne_id
    where r.animal_id = p_animal_id;

    select coalesce(jsonb_agg(
        to_jsonb(dc) || jsonb_build_object(
            'personne', to_jsonb(p),
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'depots_chat' and f.enregistrement_id = dc.id
            ), '[]'::jsonb)
        )
        order by dc.date_depot desc
    ), '[]'::jsonb)
    into v_depots
    from depot_chat_animaux dca
    join depots_chat dc on dc.id = dca.depot_id
    left join personnes p on p.id = dc.personne_id
    where dca.animal_id = p_animal_id;

    select coalesce(jsonb_agg(
        to_jsonb(ab) || jsonb_build_object(
            'personne', to_jsonb(p),
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'abandons' and f.enregistrement_id = ab.id
            ), '[]'::jsonb)
        )
        order by ab.date_fait desc
    ), '[]'::jsonb)
    into v_abandons
    from abandons ab
    left join personnes p on p.id = ab.personne_id
    where ab.animal_id = p_animal_id;

    select coalesce(jsonb_agg(
        to_jsonb(fa) || jsonb_build_object(
            'personne', to_jsonb(p),
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'familles_accueil' and f.enregistrement_id = fa.id
            ), '[]'::jsonb)
        )
        order by fa.date_debut desc
    ), '[]'::jsonb)
    into v_familles_accueil
    from familles_accueil fa
    left join personnes p on p.id = fa.personne_id
    where fa.animal_id = p_animal_id;

    select coalesce(jsonb_agg(
        to_jsonb(at) || jsonb_build_object(
            'personne', to_jsonb(p),
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'attestations' and f.enregistrement_id = at.id
            ), '[]'::jsonb)
        )
        order by at.date_fait desc
    ), '[]'::jsonb)
    into v_attestations
    from attestations at
    left join personnes p on p.id = at.personne_id
    where at.animal_id = p_animal_id;

    return jsonb_build_object(
        'animal', v_animal,
        'sterilisation', v_sterilisation,
        'statuts', v_statuts,
        'soins', v_soins,
        'adoptions', v_adoptions,
        'reservations', v_reservations,
        'depots', v_depots,
        'abandons', v_abandons,
        'familles_accueil', v_familles_accueil,
        'attestations', v_attestations
    );
end;
$$;
