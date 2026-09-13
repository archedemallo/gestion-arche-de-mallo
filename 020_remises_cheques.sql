-- ============================================================
-- REMISES DE CHÈQUES
-- ============================================================
-- Reprend remisecheques.html : une remise regroupe plusieurs chèques
-- reçus (donateurs) déposés ensemble en banque. p_cheques est un tableau
-- JSON de lignes ; la fonction remplace tout le détail à chaque
-- création/modification (plus simple et sûr qu'un diff ligne à ligne).
--
-- NON REPRIS pour l'instant (à construire avec la page Banque et/ou
-- Import-Rapprochement, absentes) : le panneau de rapprochement qui
-- recherche automatiquement le don/l'adhésion Suivi correspondant à
-- chaque chèque. En attendant, le rattachement à un formulaire Suivi se
-- fait via la table caisse_mouvement_suivi_liens / manuellement.
--
-- p_cheques : jsonb, ex.
--   '[{"donateur":"Mme X","montant":50,"numero_cheque":"1234567",
--      "type_mouvement":"Dons","description":"Dons","nom_chat":null,
--      "numero_recu":null}]'

create or replace function creer_remise_cheques(
    p_numero_bordereau text,
    p_date_remise      date,
    p_periode          text,
    p_cheques          jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id uuid;
    v_total numeric(10,2);
    v_nb integer;
    v_item jsonb;
    v_ordre integer := 1;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    if p_date_remise is null then raise exception 'La date est obligatoire.'; end if;
    if p_cheques is null or jsonb_array_length(p_cheques) = 0 then raise exception 'Ajoutez au moins un chèque.'; end if;

    select coalesce(sum((item->>'montant')::numeric), 0), jsonb_array_length(p_cheques)
        into v_total, v_nb
        from jsonb_array_elements(p_cheques) item;

    for v_item in select * from jsonb_array_elements(p_cheques) loop
        if coalesce((v_item->>'montant')::numeric, 0) <= 0 then
            raise exception 'Tous les montants sont obligatoires (chèque %).', v_ordre;
        end if;
        v_ordre := v_ordre + 1;
    end loop;

    insert into remises_cheques (numero_bordereau, date_remise, periode, nb_cheques, montant_total, statut)
    values (p_numero_bordereau, p_date_remise, p_periode, v_nb, v_total, 'en_attente')
    returning id into v_id;

    v_ordre := 1;
    for v_item in select * from jsonb_array_elements(p_cheques) loop
        perform valider_type_description(v_item->>'type_mouvement', v_item->>'description');
        insert into remise_cheques_details (
            remise_id, numero_ordre, donateur, montant, cheque_ref,
            type_mouvement, description, libelle_complementaire, nom_chat, numero_recu
        ) values (
            v_id, v_ordre, v_item->>'donateur', (v_item->>'montant')::numeric, v_item->>'numero_cheque',
            v_item->>'type_mouvement', v_item->>'description', v_item->>'libelle_complementaire',
            v_item->>'nom_chat', v_item->>'numero_recu'
        );
        v_ordre := v_ordre + 1;
    end loop;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'AJOUT', 'remises_cheques', v_id::text, format('%s chèque(s), %s€', v_nb, v_total));

    return v_id;
end;
$$;

create or replace function modifier_remise_cheques(
    p_id               uuid,
    p_numero_bordereau text,
    p_date_remise      date,
    p_periode          text,
    p_cheques          jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_verifie boolean;
    v_total numeric(10,2);
    v_nb integer;
    v_item jsonb;
    v_ordre integer := 1;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select verifie into v_verifie from remises_cheques where id = p_id;
    if v_verifie is null then raise exception 'Remise introuvable.'; end if;
    if v_verifie then raise exception 'Remise vérifiée — décochez pour modifier.'; end if;
    if p_cheques is null or jsonb_array_length(p_cheques) = 0 then raise exception 'Ajoutez au moins un chèque.'; end if;

    select coalesce(sum((item->>'montant')::numeric), 0), jsonb_array_length(p_cheques)
        into v_total, v_nb
        from jsonb_array_elements(p_cheques) item;

    update remises_cheques set
        numero_bordereau = p_numero_bordereau, date_remise = p_date_remise, periode = p_periode,
        nb_cheques = v_nb, montant_total = v_total
    where id = p_id;

    delete from remise_cheques_details where remise_id = p_id;
    for v_item in select * from jsonb_array_elements(p_cheques) loop
        perform valider_type_description(v_item->>'type_mouvement', v_item->>'description');
        insert into remise_cheques_details (
            remise_id, numero_ordre, donateur, montant, cheque_ref,
            type_mouvement, description, libelle_complementaire, nom_chat, numero_recu
        ) values (
            p_id, v_ordre, v_item->>'donateur', (v_item->>'montant')::numeric, v_item->>'numero_cheque',
            v_item->>'type_mouvement', v_item->>'description', v_item->>'libelle_complementaire',
            v_item->>'nom_chat', v_item->>'numero_recu'
        );
        v_ordre := v_ordre + 1;
    end loop;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'remises_cheques', p_id::text, format('%s chèque(s), %s€', v_nb, v_total));
end;
$$;

create or replace function verrouiller_remise_cheques(p_id uuid, p_verrouiller boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    update remises_cheques set verifie = p_verrouiller where id = p_id;
    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'remises_cheques', p_id::text, case when p_verrouiller then 'Verrouillée' else 'Déverrouillée' end);
end;
$$;

create or replace function supprimer_remise_cheques(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_verifie boolean;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select verifie into v_verifie from remises_cheques where id = p_id;
    if v_verifie then raise exception 'Remise vérifiée — décochez avant de supprimer.'; end if;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    select auth.jwt() ->> 'email', 'SUPPRESSION', 'remises_cheques', p_id::text, numero_bordereau from remises_cheques where id = p_id;

    delete from remises_cheques where id = p_id; -- remise_cheques_details supprimées en cascade
end;
$$;
