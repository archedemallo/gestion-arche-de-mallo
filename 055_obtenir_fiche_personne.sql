-- ============================================================
-- 055_obtenir_fiche_personne.sql
-- ============================================================
-- Crée obtenir_fiche_personne(), l'équivalent pour une personne de
-- obtenir_fiche_animal() (042) : retourne en un seul appel la fiche de
-- la personne et tout son historique avec l'association — adhésions,
-- dons, adoptions, réservations, dépôts, abandons, familles d'accueil,
-- attestations, prêts/retours de matériel, certificats d'engagement —
-- chacun avec l'animal concerné (si applicable), les chèques détaillés
-- (adhésions, dons, adoptions, réservations) et les PDF associés
-- (soumission_fichiers).
--
-- Utilisée par recherche_personne.html. Même contrôle d'accès que les
-- autres fonctions Suivi : compte Suivi requis (role_suivi_courant()).
-- ============================================================

create or replace function obtenir_fiche_personne(p_personne_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
    v_personne jsonb;
    v_adhesions jsonb;
    v_dons jsonb;
    v_adoptions jsonb;
    v_reservations jsonb;
    v_depots jsonb;
    v_abandons jsonb;
    v_familles_accueil jsonb;
    v_attestations jsonb;
    v_materiel jsonb;
    v_certificats jsonb;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;

    select to_jsonb(p) into v_personne from personnes p where p.id = p_personne_id;
    if v_personne is null then
        return null;
    end if;

    -- Adhésions
    select coalesce(jsonb_agg(
        to_jsonb(ad) || jsonb_build_object(
            'cheques', coalesce((
                select jsonb_agg(to_jsonb(c) order by c.numero_cheque)
                from adhesions_cheques c where c.adhesion_id = ad.id
            ), '[]'::jsonb),
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'adhesions' and f.enregistrement_id = ad.id
            ), '[]'::jsonb)
        )
        order by ad.date_adhesion desc nulls last
    ), '[]'::jsonb)
    into v_adhesions
    from adhesions ad
    where ad.personne_id = p_personne_id;

    -- Dons (inclut les reçus fiscaux : numero_recu_fiscal est une colonne de dons)
    select coalesce(jsonb_agg(
        to_jsonb(d) || jsonb_build_object(
            'cheques', coalesce((
                select jsonb_agg(to_jsonb(c) order by c.numero_cheque)
                from dons_cheques c where c.don_id = d.id
            ), '[]'::jsonb),
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'dons' and f.enregistrement_id = d.id
            ), '[]'::jsonb)
        )
        order by d.date_signature desc nulls last
    ), '[]'::jsonb)
    into v_dons
    from dons d
    where d.personne_id = p_personne_id;

    -- Adoptions (avec l'animal adopté)
    select coalesce(jsonb_agg(
        to_jsonb(ad) || jsonb_build_object(
            'animal', (select jsonb_build_object('id', a.id, 'nom_usuel', a.nom_usuel,
                                                'nom_adoption', a.nom_adoption,
                                                'numero_interne', a.numero_interne)
                       from animaux a where a.id = ad.animal_id),
            'cheques', coalesce((
                select jsonb_agg(to_jsonb(c) order by c.numero_cheque)
                from adoptions_cheques c where c.adoption_id = ad.id
            ), '[]'::jsonb),
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'adoptions' and f.enregistrement_id = ad.id
            ), '[]'::jsonb)
        )
        order by ad.date_adoption desc nulls last
    ), '[]'::jsonb)
    into v_adoptions
    from adoptions ad
    where ad.personne_id = p_personne_id;

    -- Réservations
    select coalesce(jsonb_agg(
        to_jsonb(r) || jsonb_build_object(
            'animal', (select jsonb_build_object('id', a.id, 'nom_usuel', a.nom_usuel,
                                                'numero_interne', a.numero_interne)
                       from animaux a where a.id = r.animal_id),
            'cheques', coalesce((
                select jsonb_agg(to_jsonb(c) order by c.numero_cheque)
                from reservations_cheques c where c.reservation_id = r.id
            ), '[]'::jsonb),
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'reservations' and f.enregistrement_id = r.id
            ), '[]'::jsonb)
        )
        order by r.date_reservation desc nulls last
    ), '[]'::jsonb)
    into v_reservations
    from reservations r
    where r.personne_id = p_personne_id;

    -- Dépôts de chats (avec les animaux déposés)
    select coalesce(jsonb_agg(
        to_jsonb(dc) || jsonb_build_object(
            'animaux', coalesce((
                select jsonb_agg(jsonb_build_object('id', a.id, 'nom_usuel', a.nom_usuel,
                                                    'numero_interne', a.numero_interne))
                from depot_chat_animaux dca
                join animaux a on a.id = dca.animal_id
                where dca.depot_id = dc.id
            ), '[]'::jsonb),
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'depots_chat' and f.enregistrement_id = dc.id
            ), '[]'::jsonb)
        )
        order by dc.date_depot desc nulls last
    ), '[]'::jsonb)
    into v_depots
    from depots_chat dc
    where dc.personne_id = p_personne_id;

    -- Abandons
    select coalesce(jsonb_agg(
        to_jsonb(ab) || jsonb_build_object(
            'animal', (select jsonb_build_object('id', a.id, 'nom_usuel', a.nom_usuel,
                                                'numero_interne', a.numero_interne)
                       from animaux a where a.id = ab.animal_id),
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'abandons' and f.enregistrement_id = ab.id
            ), '[]'::jsonb)
        )
        order by ab.date_fait desc nulls last
    ), '[]'::jsonb)
    into v_abandons
    from abandons ab
    where ab.personne_id = p_personne_id;

    -- Familles d'accueil
    select coalesce(jsonb_agg(
        to_jsonb(fa) || jsonb_build_object(
            'animal', (select jsonb_build_object('id', a.id, 'nom_usuel', a.nom_usuel,
                                                'numero_interne', a.numero_interne)
                       from animaux a where a.id = fa.animal_id),
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'familles_accueil' and f.enregistrement_id = fa.id
            ), '[]'::jsonb)
        )
        order by fa.date_debut desc nulls last
    ), '[]'::jsonb)
    into v_familles_accueil
    from familles_accueil fa
    where fa.personne_id = p_personne_id;

    -- Attestations (CBS absent, décharge vaccin)
    select coalesce(jsonb_agg(
        to_jsonb(att) || jsonb_build_object(
            'animal', (select jsonb_build_object('id', a.id, 'nom_usuel', a.nom_usuel,
                                                'numero_interne', a.numero_interne)
                       from animaux a where a.id = att.animal_id),
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'attestations' and f.enregistrement_id = att.id
            ), '[]'::jsonb)
        )
        order by att.date_fait desc nulls last
    ), '[]'::jsonb)
    into v_attestations
    from attestations att
    where att.personne_id = p_personne_id;

    -- Prêts / retours de matériel
    select coalesce(jsonb_agg(
        to_jsonb(m) || jsonb_build_object(
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'materiel_mouvements' and f.enregistrement_id = m.id
            ), '[]'::jsonb)
        )
        order by m.date_mouvement desc nulls last
    ), '[]'::jsonb)
    into v_materiel
    from materiel_mouvements m
    where m.personne_id = p_personne_id;

    -- Certificats d'engagement
    select coalesce(jsonb_agg(
        to_jsonb(ce) || jsonb_build_object(
            'fichiers', coalesce((
                select jsonb_agg(to_jsonb(f))
                from soumission_fichiers f
                where f.table_source = 'certificats_engagement' and f.enregistrement_id = ce.id
            ), '[]'::jsonb)
        )
        order by ce.date_fait desc nulls last
    ), '[]'::jsonb)
    into v_certificats
    from certificats_engagement ce
    where ce.personne_id = p_personne_id;

    return jsonb_build_object(
        'personne', v_personne,
        'adhesions', v_adhesions,
        'dons', v_dons,
        'adoptions', v_adoptions,
        'reservations', v_reservations,
        'depots', v_depots,
        'abandons', v_abandons,
        'familles_accueil', v_familles_accueil,
        'attestations', v_attestations,
        'materiel', v_materiel,
        'certificats', v_certificats
    );
end;
$$;

-- ============================================================
-- rechercher_personnes() : recherche multi-mots.
-- Avant (043), la saisie entière était cherchée telle quelle dans
-- chaque champ séparément : "Guy Dupont" ne trouvait personne car ni
-- le nom ni le prénom ne contient les deux mots. Désormais chaque mot
-- doit se retrouver dans au moins un des champs (nom, prénom, raison
-- sociale, email, téléphone). Même signature et mêmes colonnes qu'en
-- 043 : selecteur-personne.js (13 formulaires) n'a rien à changer, et
-- une saisie d'un seul mot se comporte exactement comme avant.
-- ============================================================

create or replace function rechercher_personnes(p_recherche text)
returns table (
    id uuid,
    type_personne text,
    civilite text,
    nom text,
    prenom text,
    raison_sociale text,
    adresse text,
    code_postal text,
    ville text,
    email text,
    telephone text
)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;

    if p_recherche is null or btrim(p_recherche) = '' then
        return;
    end if;

    return query
    select p.id, p.type_personne, p.civilite, p.nom, p.prenom, p.raison_sociale,
           p.adresse, p.code_postal, p.ville, p.email, p.telephone
    from personnes p
    where not exists (
        select 1
        from unnest(regexp_split_to_array(btrim(p_recherche), '\s+')) as mot
        where not (
               p.nom            ilike '%' || mot || '%'
            or p.prenom         ilike '%' || mot || '%'
            or p.raison_sociale ilike '%' || mot || '%'
            or p.email          ilike '%' || mot || '%'
            or p.telephone      ilike '%' || mot || '%'
        )
    )
    order by coalesce(p.nom, p.raison_sociale), p.prenom
    limit 20;
end;
$$;
