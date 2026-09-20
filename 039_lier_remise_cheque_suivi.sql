-- ============================================================
-- LIER UN CHÈQUE (REMISE) À UN ENREGISTREMENT SUIVI
-- ============================================================
-- Confirmé absent du projet Fusion : le fichier 020_remises_cheques.sql
-- documentait lui-même ce manque ("NON REPRIS pour l'instant... le
-- panneau de rapprochement qui recherche automatiquement le don/
-- l'adhésion Suivi correspondant à chaque chèque").
--
-- Contrairement à caisse_mouvements/banque_mouvements (un mouvement
-- peut être ventilé sur PLUSIEURS enregistrements Suivi, d'où les
-- tables de liaison caisse_mouvement_suivi_liens /
-- banque_mouvement_suivi_liens), un chèque de remise correspond à
-- exactement UN don/une adhésion/etc. — une relation 1:1 suffit, donc
-- de simples colonnes nullables directement sur remise_cheques_details
-- plutôt qu'une table de liaison séparée.

alter table remise_cheques_details add column if not exists adhesion_id           uuid references adhesions(id) on delete set null;
alter table remise_cheques_details add column if not exists don_id                uuid references dons(id) on delete set null;
alter table remise_cheques_details add column if not exists adoption_id           uuid references adoptions(id) on delete set null;
alter table remise_cheques_details add column if not exists reservation_id        uuid references reservations(id) on delete set null;
alter table remise_cheques_details add column if not exists materiel_mouvement_id uuid references materiel_mouvements(id) on delete set null;

create or replace function lier_remise_cheque_suivi(p_detail_id uuid, p_type text, p_cible_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_remise_id uuid;
    v_verifie   boolean;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    if p_type not in ('adhesion','don','adoption','reservation','materiel_mouvement') then
        raise exception 'Type Suivi invalide : %', p_type;
    end if;

    select remise_id into v_remise_id from remise_cheques_details where id = p_detail_id;
    if v_remise_id is null then raise exception 'Chèque introuvable.'; end if;
    select verifie into v_verifie from remises_cheques where id = v_remise_id;
    if v_verifie then raise exception 'Remise vérifiée — décochez pour modifier.'; end if;

    update remise_cheques_details set
        adhesion_id           = case when p_type = 'adhesion' then p_cible_id else null end,
        don_id                = case when p_type = 'don' then p_cible_id else null end,
        adoption_id           = case when p_type = 'adoption' then p_cible_id else null end,
        reservation_id        = case when p_type = 'reservation' then p_cible_id else null end,
        materiel_mouvement_id = case when p_type = 'materiel_mouvement' then p_cible_id else null end
    where id = p_detail_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'remise_cheques_details', p_detail_id::text, 'Lié à Suivi : ' || p_type);
end;
$$;

create or replace function delier_remise_cheque_suivi(p_detail_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_remise_id uuid;
    v_verifie   boolean;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select remise_id into v_remise_id from remise_cheques_details where id = p_detail_id;
    if v_remise_id is null then raise exception 'Chèque introuvable.'; end if;
    select verifie into v_verifie from remises_cheques where id = v_remise_id;
    if v_verifie then raise exception 'Remise vérifiée — décochez pour modifier.'; end if;

    update remise_cheques_details set
        adhesion_id = null, don_id = null, adoption_id = null, reservation_id = null, materiel_mouvement_id = null
    where id = p_detail_id;
end;
$$;
