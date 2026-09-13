-- ============================================================
-- CAISSE PHYSIQUE — comptage de billets/pièces
-- ============================================================
-- Reprend caisse-physique1.html / caisse-physique2.html (quasi
-- identiques dans compta-main, fusionnés en une seule page côté front
-- avec un sélecteur de caisse — même principe que reservation.html
-- côté Suivi).
--
-- Le total est toujours recalculé côté serveur à partir des quantités
-- de billets/pièces (jamais celui envoyé par le formulaire) : ça évite
-- qu'un total incohérent avec le détail ne soit enregistré, même par
-- erreur de calcul côté client.

create or replace function creer_comptage_caisse_physique(
    p_caisse       text,
    p_date         date,
    p_periode      text default null,
    p_mois         date default null,
    p_b500 integer default 0, p_b200 integer default 0, p_b100 integer default 0,
    p_b50  integer default 0, p_b20  integer default 0, p_b10  integer default 0,
    p_b5   integer default 0,
    p_p200 integer default 0, p_p100 integer default 0, p_p050 integer default 0,
    p_p020 integer default 0, p_p010 integer default 0, p_p005 integer default 0,
    p_p002 integer default 0, p_p001 integer default 0,
    p_commentaire  text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id uuid;
    v_total numeric(10,2);
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;

    if p_caisse not in ('caisse1', 'caisse2') then
        raise exception 'Caisse invalide : % (attendu caisse1 ou caisse2)', p_caisse;
    end if;

    v_total := round((
          p_b500*500 + p_b200*200 + p_b100*100 + p_b50*50 + p_b20*20 + p_b10*10 + p_b5*5
        + p_p200*2   + p_p100*1   + p_p050*0.5  + p_p020*0.2 + p_p010*0.1 + p_p005*0.05
        + p_p002*0.02 + p_p001*0.01
    )::numeric, 2);

    insert into caisse_physique_comptages (
        caisse, date_comptage, periode, mois,
        b500, b200, b100, b50, b20, b10, b5,
        p200, p100, p050, p020, p010, p005, p002, p001,
        total, commentaire
    ) values (
        p_caisse, p_date, p_periode, coalesce(p_mois, p_date),
        p_b500, p_b200, p_b100, p_b50, p_b20, p_b10, p_b5,
        p_p200, p_p100, p_p050, p_p020, p_p010, p_p005, p_p002, p_p001,
        v_total, p_commentaire
    )
    returning id into v_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'AJOUT', 'caisse_physique_comptages', v_id::text, format('Comptage %s : %s€', p_caisse, v_total));

    return v_id;
end;
$$;

create or replace function supprimer_comptage_caisse_physique(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    select auth.jwt() ->> 'email', 'SUPPRESSION', 'caisse_physique_comptages', p_id::text,
           format('Comptage %s du %s supprimé', caisse, date_comptage)
    from caisse_physique_comptages where id = p_id;

    delete from caisse_physique_comptages where id = p_id;
end;
$$;
