-- ============================================================
-- LIER UNE REMISE DE CHÈQUES DEPUIS BANQUE (après création)
-- ============================================================
-- Comme pour lier_banque_cheque (035), le rattachement d'une remise de
-- chèques à un mouvement bancaire n'était possible qu'à la création
-- (creer_operation_banque(p_ref_remise)) — seul delier_banque_remise
-- existait pour le retirer. Ajoute le "lier" symétrique, utilisable
-- depuis le panneau Rapprochement à tout moment.

create or replace function lier_banque_remise(p_banque_mouvement_id uuid, p_remise_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_statut text;
    v_date   date;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select statut, date_mouvement into v_statut, v_date from banque_mouvements where id = p_banque_mouvement_id;
    if v_statut is null then raise exception 'Opération introuvable.'; end if;
    if v_statut = 'verifie' then raise exception 'Ligne verrouillée — décochez "Vérifié" pour modifier.'; end if;
    if exists (select 1 from banque_mouvements where id <> p_banque_mouvement_id and ref_remise = p_remise_id) then
        raise exception 'Cette remise est déjà rattachée à un autre mouvement.';
    end if;

    update banque_mouvements set ref_remise = p_remise_id where id = p_banque_mouvement_id;
    update remises_cheques set statut = 'encaisse', date_encaissement = v_date, ref_banque = p_banque_mouvement_id where id = p_remise_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'banque_mouvements', p_banque_mouvement_id::text, 'Remise de chèques liée');
end;
$$;
