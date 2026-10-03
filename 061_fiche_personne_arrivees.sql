-- ============================================================
-- 061_fiche_personne_arrivees.sql
-- ============================================================
-- Problème : la fiche personne ne montrait un dépôt ou un abandon que
-- si le formulaire (depot_chat / abandon) avait été rempli. Or une
-- arrivée enregistrée dans "Nouvelle arrivée" (origine dépôt, abandon,
-- saisie…) rattache seulement la personne à l'animal
-- (animaux.personne_origine_id) : sans formulaire, rien n'apparaissait.
--
-- Ajoute à obtenir_fiche_personne() une clé 'arrivees' : les animaux
-- arrivés par cette personne, avec l'origine, le statut, et pour les
-- dépôts/abandons si le formulaire a été complété.
-- Méthode : l'ancienne fonction (055) est conservée sous le nom
-- obtenir_fiche_personne_base et la nouvelle la complète.
-- ============================================================

do $$
begin
    if exists (select 1 from pg_proc where proname = 'obtenir_fiche_personne')
       and not exists (select 1 from pg_proc where proname = 'obtenir_fiche_personne_base') then
        alter function obtenir_fiche_personne(uuid) rename to obtenir_fiche_personne_base;
    end if;
end $$;

create or replace function obtenir_fiche_personne(p_personne_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
    v_fiche jsonb;
    v_arrivees jsonb;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;

    v_fiche := obtenir_fiche_personne_base(p_personne_id);
    if v_fiche is null then
        return null;
    end if;

    select coalesce(jsonb_agg(jsonb_build_object(
        'id', a.id,
        'nom_usuel', a.nom_usuel,
        'nom_adoption', a.nom_adoption,
        'numero_interne', a.numero_interne,
        'date_arrivee', a.date_arrivee,
        'origine_arrivee', a.origine_arrivee,
        'statut_actuel', a.statut_actuel,
        'formulaire_requis', a.origine_arrivee in ('depot', 'abandon'),
        'formulaire_fait', case a.origine_arrivee
            when 'depot' then exists (
                select 1 from depot_chat_animaux dca
                join depots_chat dc on dc.id = dca.depot_id
                where dca.animal_id = a.id and dc.personne_id = p_personne_id)
            when 'abandon' then exists (
                select 1 from abandons ab
                where ab.animal_id = a.id and ab.personne_id = p_personne_id)
            else null end
    ) order by a.date_arrivee desc nulls last), '[]'::jsonb)
    into v_arrivees
    from animaux a
    where a.personne_origine_id = p_personne_id;

    return v_fiche || jsonb_build_object('arrivees', v_arrivees);
end;
$$;
