-- ============================================================
-- 062_pieces_adoption.sql
-- ============================================================
-- Suivi des pièces justificatives d'un dossier d'adoption.
-- Une adoption a 5 pièces attendues : CNI recto, CNI verso, justificatif
-- de domicile, certificat de bonne santé, carnet de santé. Elles peuvent
-- être transmises plus tard : chaque pièce est suivie par adoption.
--
--  * table adoption_pieces (une ligne par adoption et par pièce)
--  * dossiers_adoption_incomplets() : liste des dossiers à compléter
--  * obtenir_fiche_personne() : ajoute la clé 'pieces_adoption'
--    (chaîne : 055 -> 061 -> 062, chaque version appelle la précédente)
--
-- Les adoptions antérieures n'ont aucune ligne : elles sont signalées
-- « à vérifier » (statut calculé, rien n'est inventé).
-- ============================================================

create table if not exists adoption_pieces (
    id uuid primary key default gen_random_uuid(),
    adoption_id uuid not null references adoptions(id) on delete cascade,
    type_piece text not null,
    recue boolean not null default false,
    mode_reception text,
    date_reception date,
    cree_le timestamptz not null default now(),
    constraint adoption_pieces_type_check
        check (type_piece in ('cni_recto','cni_verso','domicile','cbs','carnet_sante')),
    constraint adoption_pieces_mode_check
        check (mode_reception is null or mode_reception in ('fichier','papier')),
    constraint adoption_pieces_unique unique (adoption_id, type_piece)
);

create index if not exists idx_adoption_pieces_adoption on adoption_pieces(adoption_id);

alter table adoption_pieces enable row level security;
drop policy if exists adoption_pieces_lecture on adoption_pieces;
create policy adoption_pieces_lecture on adoption_pieces
    for select using (role_suivi_courant() is not null or role_compta_courant() is not null);
drop policy if exists adoption_pieces_ecriture on adoption_pieces;
create policy adoption_pieces_ecriture on adoption_pieces
    for all using (role_suivi_courant() is not null);

-- ------------------------------------------------------------
-- Dossiers d'adoption incomplets
-- statut : 'incomplet' (suivi commencé, il manque des pièces)
--          'a_verifier' (aucune ligne : adoption antérieure au suivi)
-- ------------------------------------------------------------
create or replace function dossiers_adoption_incomplets()
returns table (
    adoption_id uuid,
    personne_id uuid,
    personne_nom text,
    animal_nom text,
    date_adoption date,
    statut text,
    manquantes text[]
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

    return query
    with calc as (
        select a.id as adoption_id, a.personne_id, a.animal_id, a.date_adoption,
               exists (select 1 from adoption_pieces x where x.adoption_id = a.id) as suivi,
               array(
                   select t
                   from unnest(array['cni_recto','cni_verso','domicile','cbs','carnet_sante']) as t
                   where not exists (
                       select 1 from adoption_pieces x
                       where x.adoption_id = a.id and x.type_piece = t and x.recue
                   )
               ) as manq
        from adoptions a
    )
    select c.adoption_id, c.personne_id,
           case when p.type_personne = 'entreprise' then coalesce(p.raison_sociale, '—')
                else coalesce(nullif(btrim(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,'')), ''), '—') end,
           an.nom_usuel,
           c.date_adoption,
           case when c.suivi then 'incomplet' else 'a_verifier' end,
           c.manq
    from calc c
    left join personnes p on p.id = c.personne_id
    left join animaux an on an.id = c.animal_id
    where cardinality(c.manq) > 0
    order by c.date_adoption asc nulls last;
end;
$$;

-- ------------------------------------------------------------
-- Fiche personne : ajoute 'pieces_adoption'
-- ------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_proc where proname = 'obtenir_fiche_personne')
       and not exists (select 1 from pg_proc where proname = 'obtenir_fiche_personne_v061') then
        alter function obtenir_fiche_personne(uuid) rename to obtenir_fiche_personne_v061;
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
    v_pieces jsonb;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;

    v_fiche := obtenir_fiche_personne_v061(p_personne_id);
    if v_fiche is null then
        return null;
    end if;

    select coalesce(jsonb_agg(jsonb_build_object(
        'adoption_id', ap.adoption_id,
        'type_piece', ap.type_piece,
        'recue', ap.recue,
        'mode_reception', ap.mode_reception,
        'date_reception', ap.date_reception
    )), '[]'::jsonb)
    into v_pieces
    from adoption_pieces ap
    join adoptions ad on ad.id = ap.adoption_id
    where ad.personne_id = p_personne_id;

    return v_fiche || jsonb_build_object('pieces_adoption', v_pieces);
end;
$$;
