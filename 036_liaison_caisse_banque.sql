-- ============================================================
-- RATTACHEMENT CAISSE (DÉPÔT D'ESPÈCES) DEPUIS BANQUE
-- ============================================================
-- Ajoute, dans le même panneau Rapprochement de banque.html, une
-- section "Lier à une sortie de caisse" équivalente à celle de l'ancien
-- système ("Lier à une sortie de caisse (dépôt espèces en banque)") :
-- une sortie de Caisse1 ou Caisse2 (le débit constaté quand des espèces
-- quittent la caisse pour être déposées en banque) se rattache au
-- mouvement bancaire de crédit correspondant.
--
-- Un même dépôt en banque peut regrouper la sortie de Caisse1 ET celle
-- de Caisse2 (vidées ensemble avant d'aller à la banque) — plusieurs
-- lignes caisse peuvent donc pointer vers le même mouvement banque.
-- D'où une colonne ref_banque sur caisse_mouvements, sur le modèle de
-- cheques.ref_banque / remises_cheques.ref_banque, plutôt qu'une table
-- de liaison séparée (pas besoin ici : une sortie de caisse ne se
-- rattache jamais qu'à un seul dépôt bancaire).

alter table caisse_mouvements add column if not exists ref_banque uuid references banque_mouvements(id);
create index if not exists idx_caisse_mouvements_ref_banque on caisse_mouvements(ref_banque);

create or replace function lier_banque_caisse(p_banque_mouvement_id uuid, p_caisse_mouvement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_statut_banque text;
    v_statut_caisse text;
    v_deja_liee     uuid;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;

    select statut into v_statut_banque from banque_mouvements where id = p_banque_mouvement_id;
    if v_statut_banque is null then raise exception 'Opération bancaire introuvable.'; end if;
    if v_statut_banque = 'verifie' then raise exception 'Ligne bancaire verrouillée — décochez "Vérifié" pour modifier.'; end if;

    select flag_statut, ref_banque into v_statut_caisse, v_deja_liee from caisse_mouvements where id = p_caisse_mouvement_id;
    if v_statut_caisse is null then raise exception 'Mouvement de caisse introuvable.'; end if;
    if v_statut_caisse = 'verifie' then raise exception 'Ligne de caisse verrouillée — décochez "Vérifié" pour modifier.'; end if;
    if v_deja_liee is not null then raise exception 'Cette sortie de caisse est déjà rattachée à un mouvement bancaire.'; end if;

    update caisse_mouvements set ref_banque = p_banque_mouvement_id where id = p_caisse_mouvement_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'banque_mouvements', p_banque_mouvement_id::text, 'Sortie de caisse liée');
end;
$$;

create or replace function delier_banque_caisse(p_banque_mouvement_id uuid, p_caisse_mouvement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_statut_banque text;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select statut into v_statut_banque from banque_mouvements where id = p_banque_mouvement_id;
    if v_statut_banque = 'verifie' then raise exception 'Ligne bancaire verrouillée — décochez "Vérifié" pour modifier.'; end if;

    update caisse_mouvements set ref_banque = null
        where id = p_caisse_mouvement_id and ref_banque = p_banque_mouvement_id;
end;
$$;

-- supprimer_operation_banque doit aussi libérer les sorties de caisse
-- liées (comme c'est déjà fait pour chèque/remise/facture depuis
-- 035_liaison_cheque_facture_banque.sql).
create or replace function supprimer_operation_banque(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_statut text;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select statut into v_statut from banque_mouvements where id = p_id;
    if v_statut = 'verifie' then raise exception 'Ligne verrouillée — décochez "Vérifié" avant de supprimer.'; end if;

    update cheques set statut = 'en_attente', date_encaissement = null, ref_banque = null where ref_banque = p_id;
    update remises_cheques set statut = 'en_attente', date_encaissement = null, ref_banque = null where ref_banque = p_id;
    update factures set statut = null, date_reglement = null
        where id in (select facture_id from banque_mouvement_facture_liens where banque_mouvement_id = p_id);
    delete from banque_mouvement_facture_liens where banque_mouvement_id = p_id;
    update caisse_mouvements set ref_banque = null where ref_banque = p_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    select auth.jwt() ->> 'email', 'SUPPRESSION', 'banque_mouvements', p_id::text, libelle from banque_mouvements where id = p_id;

    delete from banque_mouvements where id = p_id;
end;
$$;
