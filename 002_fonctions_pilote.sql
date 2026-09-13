-- ============================================================
-- Fonctions métier appelées depuis les formulaires (RPC Supabase)
-- ============================================================
create or replace function creer_adhesion(
    p_nom text,
    p_prenom text,
    p_adresse text default null,
    p_code_postal text default null,
    p_ville text default null,
    p_email text default null,
    p_telephone text default null,
    p_date_naissance date default null,
    p_date_adhesion date default null,
    p_type_adhesion text default null,
    p_cotisation_adherent numeric default null,
    p_don_bienfaiteur numeric default null,
    p_don_sympathisant numeric default null,
    p_montant_total numeric default null,
    p_montant_virement numeric default null,
    p_montant_espece numeric default null,
    p_date_fait date default null,
    p_saisi_par_id uuid default null,
    p_cheques jsonb default '[]'::jsonb,
    p_adoption_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_personne_id uuid;
    v_utilisateur_id uuid;
    v_adhesion_id uuid;
    v_cheque jsonb;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;
    if p_nom is null or btrim(p_nom) = '' then
        raise exception 'Le nom est obligatoire';
    end if;

    select id into v_personne_id
    from personnes
    where upper(btrim(nom)) = upper(btrim(p_nom))
      and coalesce(upper(btrim(prenom)), '') = coalesce(upper(btrim(p_prenom)), '')
    limit 1;

    if v_personne_id is null then
        insert into personnes (type_personne, nom, prenom, adresse, code_postal,
            ville, email, telephone, date_naissance)
        values ('particulier', btrim(p_nom), btrim(p_prenom), p_adresse, p_code_postal,
            p_ville, p_email, p_telephone, p_date_naissance)
        returning id into v_personne_id;
    end if;

    if p_saisi_par_id is not null then
        if not exists (select 1 from utilisateurs where id = p_saisi_par_id and actif) then
            raise exception 'Personne non reconnue dans la liste des saisisseurs.';
        end if;
        v_utilisateur_id := p_saisi_par_id;
    end if;

    insert into adhesions (personne_id, date_adhesion, type_adhesion,
        cotisation_adherent, don_bienfaiteur, don_sympathisant, montant_total,
        montant_virement, montant_espece, saisi_par, date_fait, adoption_id)
    values (v_personne_id, p_date_adhesion, p_type_adhesion,
        p_cotisation_adherent, p_don_bienfaiteur, p_don_sympathisant, p_montant_total,
        p_montant_virement, p_montant_espece, v_utilisateur_id, p_date_fait, p_adoption_id)
    returning id into v_adhesion_id;

    for v_cheque in select * from jsonb_array_elements(coalesce(p_cheques, '[]'::jsonb))
    loop
        insert into adhesions_cheques (adhesion_id, numero_cheque, montant)
        values (
            v_adhesion_id,
            v_cheque->>'numero_cheque',
            nullif(v_cheque->>'montant', '')::numeric
        );
    end loop;

    return v_adhesion_id;
end;
$$;
