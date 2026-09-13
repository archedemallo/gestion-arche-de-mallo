-- ============================================================
-- FACTURES
-- ============================================================
-- Reprend factures.html. Le statut ('payee' / null = en attente) suit
-- automatiquement la présence d'une date de règlement, comme dans
-- l'ancien système — on ne le fixe jamais directement depuis le
-- formulaire.
--
-- "categorie" (nom du champ dans les sheets) utilise la même liste que
-- "type de mouvement" ailleurs (Caisse/Banque/Chèques) — la cascade
-- catégorie → description demandée s'applique donc ici aussi.
--
-- Non repris : le sélecteur Google Drive pour joindre le PDF (nécessite
-- l'auth Google, qu'on quitte). Le champ lien_pdf reste un simple champ
-- texte où coller un lien.

create or replace function creer_facture(
    p_numero_facture text,
    p_fournisseur    text,
    p_date_facture   date,
    p_montant_ttc    numeric,
    p_categorie      text,
    p_description    text default null,
    p_date_reglement date default null,
    p_mode_reglement text default null,
    p_lien_pdf       text default null,
    p_commentaire    text default null,
    p_nom_chat       text default null,
    p_periode        text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id uuid;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    if p_fournisseur is null or p_fournisseur = '' then raise exception 'Le fournisseur est obligatoire.'; end if;
    if coalesce(p_montant_ttc,0) <= 0 then raise exception 'Le montant est obligatoire.'; end if;
    if p_date_facture is null then raise exception 'La date de facture est obligatoire.'; end if;
    perform valider_type_description(p_categorie, p_description);

    insert into factures (
        numero_facture, fournisseur, date_facture, montant_ttc, categorie, description,
        date_reglement, mode_reglement, lien_pdf, commentaire, nom_chat, periode, statut
    ) values (
        p_numero_facture, p_fournisseur, p_date_facture, p_montant_ttc, p_categorie, p_description,
        p_date_reglement, p_mode_reglement, p_lien_pdf, p_commentaire, p_nom_chat, p_periode,
        case when p_date_reglement is not null then 'payee' else null end
    )
    returning id into v_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'AJOUT', 'factures', v_id::text, p_fournisseur || ' — ' || p_montant_ttc);

    return v_id;
end;
$$;

create or replace function modifier_facture(
    p_id             uuid,
    p_numero_facture text,
    p_fournisseur    text,
    p_date_facture   date,
    p_montant_ttc    numeric,
    p_categorie      text,
    p_description    text default null,
    p_date_reglement date default null,
    p_mode_reglement text default null,
    p_lien_pdf       text default null,
    p_commentaire    text default null,
    p_nom_chat       text default null,
    p_periode        text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    if not exists (select 1 from factures where id = p_id) then raise exception 'Facture introuvable.'; end if;
    if coalesce(p_montant_ttc,0) <= 0 then raise exception 'Le montant est obligatoire.'; end if;
    perform valider_type_description(p_categorie, p_description);

    update factures set
        numero_facture = p_numero_facture, fournisseur = p_fournisseur, date_facture = p_date_facture,
        montant_ttc = p_montant_ttc, categorie = p_categorie, description = p_description,
        date_reglement = p_date_reglement, mode_reglement = p_mode_reglement, lien_pdf = p_lien_pdf,
        commentaire = p_commentaire, nom_chat = p_nom_chat, periode = p_periode,
        statut = case when p_date_reglement is not null then 'payee' else null end
    where id = p_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'factures', p_id::text, p_fournisseur);
end;
$$;

-- Bascule rapide payée / en attente, sans passer par le formulaire
-- complet (comme le bouton dédié de l'ancien système).
create or replace function basculer_facture_payee(p_id uuid)
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
    select statut into v_statut from factures where id = p_id;
    if v_statut is null then raise exception 'Facture introuvable.'; end if;

    if v_statut = 'payee' then
        update factures set statut = null, date_reglement = null where id = p_id;
    else
        update factures set statut = 'payee', date_reglement = current_date where id = p_id;
    end if;
end;
$$;

create or replace function supprimer_facture(p_id uuid)
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
    select auth.jwt() ->> 'email', 'SUPPRESSION', 'factures', p_id::text, fournisseur from factures where id = p_id;
    delete from factures where id = p_id;
end;
$$;
