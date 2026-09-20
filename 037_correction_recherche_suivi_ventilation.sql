-- ============================================================
-- CORRECTION : recherche Suivi (ventilation Caisse/Banque) muette
-- ============================================================
-- Bug réel, reproduit et confirmé (rejoué en local avec un vrai
-- Postgres) : rechercher_suivi_pour_ventilation() faisait un
-- `union all` suivi d'un `order by date_operation`, mais aucune des
-- colonnes du UNION n'était explicitement nommée dans le SELECT — or
-- Postgres n'accepte dans le ORDER BY d'un UNION que les noms de
-- colonnes réels du premier SELECT, pas ceux déclarés dans RETURNS
-- TABLE. Résultat : la fonction levait une erreur SQL
-- ("invalid UNION/INTERSECT/EXCEPT ORDER BY clause") à CHAQUE appel,
-- pour toute recherche (caisse.html et banque.html, qui appellent
-- toutes les deux cette même fonction depuis leur panneau
-- "Ventilation"). Le JS, lui, avalait l'erreur en console sans rien
-- afficher (catch(e){console.error(e)}), d'où l'impression trompeuse
-- d'une recherche qui "ne renvoie jamais de résultat".
--
-- Correctif : on nomme explicitement les colonnes du premier SELECT du
-- UNION (seul celui-ci compte pour nommer les colonnes du résultat).

create or replace function rechercher_suivi_pour_ventilation(p_recherche text)
returns table (
    type            text,
    id              uuid,
    nom_affiche     text,
    montant_suggere numeric,
    date_operation  date
)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
    if role_compta_courant() is null then
        raise exception 'Accès refusé : réservé aux comptes Compta.';
    end if;

    return query
    select
        'adhesion'::text as type,
        a.id as id,
        coalesce(p.prenom || ' ' || p.nom, p.raison_sociale, 'Anonyme') as nom_affiche,
        a.montant_total as montant_suggere,
        a.date_adhesion as date_operation
    from adhesions a join personnes p on p.id = a.personne_id
    where p_recherche is null or btrim(p_recherche) = ''
       or p.nom ilike '%'||p_recherche||'%' or p.prenom ilike '%'||p_recherche||'%' or p.raison_sociale ilike '%'||p_recherche||'%'
    union all
    select 'don'::text, d.id, coalesce(p.prenom || ' ' || p.nom, p.raison_sociale, 'Anonyme'), d.montant, d.date_signature
    from dons d left join personnes p on p.id = d.personne_id
    where p_recherche is null or btrim(p_recherche) = ''
       or p.nom ilike '%'||p_recherche||'%' or p.prenom ilike '%'||p_recherche||'%' or p.raison_sociale ilike '%'||p_recherche||'%'
    union all
    select 'adoption'::text, ad.id, coalesce(p.prenom || ' ' || p.nom, p.raison_sociale, 'Anonyme'), ad.tarif_particulier, ad.date_adoption
    from adoptions ad join personnes p on p.id = ad.personne_id
    where p_recherche is null or btrim(p_recherche) = ''
       or p.nom ilike '%'||p_recherche||'%' or p.prenom ilike '%'||p_recherche||'%' or p.raison_sociale ilike '%'||p_recherche||'%'
    union all
    select 'reservation'::text, r.id, coalesce(p.prenom || ' ' || p.nom, p.raison_sociale, 'Anonyme'), r.montant, r.date_reservation
    from reservations r join personnes p on p.id = r.personne_id
    where p_recherche is null or btrim(p_recherche) = ''
       or p.nom ilike '%'||p_recherche||'%' or p.prenom ilike '%'||p_recherche||'%' or p.raison_sociale ilike '%'||p_recherche||'%'
    union all
    -- Prêt de matériel : une caution est versée à l'Arche mais
    -- materiel_mouvements ne stocke pas de montant (juste le
    -- type/la personne/le matériel) — pas de montant suggéré ici,
    -- l'admin le saisit à la main dans la ventilation.
    select 'materiel_mouvement'::text, m.id, coalesce(p.prenom || ' ' || p.nom, p.raison_sociale, 'Anonyme') || ' — ' || coalesce(m.materiel, ''), null::numeric, m.date_mouvement
    from materiel_mouvements m join personnes p on p.id = m.personne_id
    where m.type_mouvement = 'pret'
      and (p_recherche is null or btrim(p_recherche) = ''
       or p.nom ilike '%'||p_recherche||'%' or p.prenom ilike '%'||p_recherche||'%' or p.raison_sociale ilike '%'||p_recherche||'%'
       or m.materiel ilike '%'||p_recherche||'%')
    order by date_operation desc nulls last
    limit 30;
end;
$$;
