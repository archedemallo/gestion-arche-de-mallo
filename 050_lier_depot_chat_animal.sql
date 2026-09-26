-- ============================================================
-- 050_lier_depot_chat_animal.sql
-- ============================================================
-- Bug signalé : les quantités saisies dans depot_chat.html
-- (nombre_chats/chatons/autres) ne sont jamais "reprises" ailleurs.
--
-- Cause : creer_depot_chat() enregistre bien la ligne dans depots_chat,
-- mais ne l'a jamais reliée à un animal individuel via la table de
-- liaison depot_chat_animaux — pourtant déjà prévue dans le schéma
-- (001) et déjà lue par obtenir_fiche_animal() (042) pour afficher
-- l'historique des dépôts sur la fiche d'un animal. Ce lien n'était
-- simplement jamais créé à l'écriture : la fiche animal n'affichait
-- donc jamais aucun dépôt, quelle que soit la quantité saisie.
--
-- Le formulaire depot_chat.html limite déjà la saisie à 1 seul animal
-- par dépôt ("Un seul animal maximum par formulaire de dépôt"), donc le
-- lien depot_id <-> animal_id est simple (0 ou 1 animal). L'animal_id
-- est transmis par arrivee_animal.html (paramètre ?animalId= à
-- l'ouverture de depot_chat.html) quand le dépôt suit la création d'une
-- arrivée ; il reste optionnel (un dépôt peut toujours être saisi seul,
-- sans arrivée préalable, comme avant).
create or replace function creer_depot_chat(
    p_nom text,
    p_prenom text default null,
    p_adresse text default null,
    p_code_postal text default null,
    p_ville text default null,
    p_telephone text default null,
    p_email text default null,
    p_commune text default null,
    p_date_depot date default null,
    p_nombre_chats integer default null,
    p_nombre_chatons integer default null,
    p_nombre_autres integer default null,
    p_preciser_autre text default null,
    p_date_fait date default null,
    p_saisi_par_id uuid default null,
    p_animal_id uuid default null
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
    v_personne_id uuid;
    v_utilisateur_id uuid;
    v_depot_id uuid;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;
    if p_nom is null or btrim(p_nom) = '' then
        raise exception 'Le nom est obligatoire';
    end if;

    select id into v_personne_id from personnes
    where upper(btrim(nom)) = upper(btrim(p_nom))
      and coalesce(upper(btrim(prenom)), '') = coalesce(upper(btrim(p_prenom)), '')
    limit 1;

    if v_personne_id is null then
        insert into personnes (type_personne, nom, prenom, adresse, code_postal, ville, telephone, email)
        values ('particulier', btrim(p_nom), btrim(p_prenom), p_adresse, p_code_postal, p_ville, p_telephone, p_email)
        returning id into v_personne_id;
    end if;

    if p_saisi_par_id is not null then
        if not exists (select 1 from utilisateurs where id = p_saisi_par_id and actif) then
            raise exception 'Personne non reconnue dans la liste des saisisseurs.';
        end if;
        v_utilisateur_id := p_saisi_par_id;
    end if;

    insert into depots_chat (personne_id, date_depot, commune, preciser_autre,
        nombre_chats_historique, nombre_chatons_historique, nombre_autres_historique, saisi_par)
    values (v_personne_id, p_date_depot, p_commune, p_preciser_autre,
        p_nombre_chats, p_nombre_chatons, p_nombre_autres, v_utilisateur_id)
    returning id into v_depot_id;

    if p_animal_id is not null then
        if not exists (select 1 from animaux where id = p_animal_id) then
            raise exception 'Animal introuvable pour le rattachement du dépôt.';
        end if;
        insert into depot_chat_animaux (depot_id, animal_id) values (v_depot_id, p_animal_id);
    end if;

    return v_depot_id;
end;
$$;
