-- ============================================================
-- creer_adoption() a été DÉPLACÉE vers 004_selecteur_animal.sql — plus
-- aucune définition ici. Avant, cette fonction était définie une
-- première fois ici (signature courte) PUIS redéfinie dans 004
-- (signature étendue avec p_animal_id) avec un DROP FUNCTION pour
-- éviter que les deux coexistent. Ça fonctionnait, mais rendait l'ordre
-- d'exécution des scripts obligatoire (003 avant 004, jamais l'inverse,
-- jamais 003 seul après coup) — repéré en revue de code. Une seule
-- définition, à un seul endroit, supprime le risque.


-- ============================================================
-- creer_don()
-- ============================================================
create or replace function creer_don(
    p_nom text default null,
    p_prenom text default null,
    p_raison_sociale text default null,
    p_representant text default null,
    p_adresse text default null,
    p_code_postal text default null,
    p_ville text default null,
    p_email text default null,
    p_telephone text default null,
    p_montant numeric default null,
    p_montant_virement numeric default null,
    p_montant_espece numeric default null,
    p_montant_cb numeric default null,
    p_date_signature date default null,
    p_don_anonyme boolean default false,
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
    v_don_id uuid;
    v_cheque jsonb;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;
    if not p_don_anonyme and (p_nom is null or btrim(p_nom) = '') and (p_raison_sociale is null or btrim(p_raison_sociale) = '') then
        raise exception 'Le nom (ou la raison sociale) est obligatoire pour un don non anonyme';
    end if;

    if not p_don_anonyme then
        select id into v_personne_id from personnes
        where upper(btrim(coalesce(nom, raison_sociale))) = upper(btrim(coalesce(p_nom, p_raison_sociale)))
          and coalesce(upper(btrim(prenom)), '') = coalesce(upper(btrim(p_prenom)), '')
        limit 1;

        if v_personne_id is null then
            insert into personnes (type_personne, nom, prenom, raison_sociale, representant,
                adresse, code_postal, ville, email, telephone)
            values (
                case when p_raison_sociale is not null and btrim(p_raison_sociale) <> '' then 'entreprise' else 'particulier' end,
                btrim(p_nom), btrim(p_prenom), p_raison_sociale, p_representant,
                p_adresse, p_code_postal, p_ville, p_email, p_telephone)
            returning id into v_personne_id;
        end if;
    end if;

    if p_saisi_par_id is not null then
        if not exists (select 1 from utilisateurs where id = p_saisi_par_id and actif) then
            raise exception 'Personne non reconnue dans la liste des saisisseurs.';
        end if;
        v_utilisateur_id := p_saisi_par_id;
    end if;

    insert into dons (personne_id, don_anonyme, date_signature, montant,
        montant_virement, montant_espece, montant_cb, saisi_par, adoption_id)
    values (v_personne_id, p_don_anonyme, p_date_signature, p_montant,
        p_montant_virement, p_montant_espece, p_montant_cb, v_utilisateur_id, p_adoption_id)
    returning id into v_don_id;

    for v_cheque in select * from jsonb_array_elements(coalesce(p_cheques, '[]'::jsonb))
    loop
        insert into dons_cheques (don_id, numero_cheque, montant)
        values (v_don_id, v_cheque->>'numero_cheque', nullif(v_cheque->>'montant', '')::numeric);
    end loop;

    return v_don_id;
end;
$$;
