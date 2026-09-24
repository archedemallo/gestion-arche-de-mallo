-- ============================================================
-- 044_numero_recu_fiscal_transactionnel.sql
-- ============================================================
-- Bug 5 (audit) : numero_recu_fiscal_suivant() et
-- enregistrer_numero_recu_fiscal() (013_recu_fiscal.sql) étaient deux
-- appels séparés depuis le JS. Si le réseau coupe entre les deux, un
-- numéro (soumis à obligation légale de continuité) est consommé sans
-- jamais être rattaché à un don — exactement le trou que 013 cherchait
-- à éviter.
--
-- Cette fonction fait les deux dans UN seul appel, donc dans UNE seule
-- transaction Postgres : soit tout réussit, soit rien n'est consommé.
-- Idempotente comme l'était enregistrer_numero_recu_fiscal() : si le
-- don a déjà un numéro (rechargement de page, double clic), on le
-- renvoie tel quel sans en consommer un nouveau.
--
-- p_don_id est optionnel : un reçu fiscal généré sans don rattaché
-- (cas existant dans recu_fiscal_particulier/entreprise.html) obtient
-- juste un numéro, sans rien mettre à jour dans dons.
--
-- Les deux anciennes fonctions restent en place (rien d'autre ne les
-- appelle, mais on ne casse rien qui s'y fierait encore) ; seuls les
-- deux formulaires reçu fiscal sont mis à jour pour utiliser celle-ci.
-- ============================================================

create or replace function obtenir_numero_recu_fiscal(p_type text, p_don_id uuid default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    v_annee integer := extract(year from now())::integer;
    v_numero integer;
    v_prefixe text;
    v_numero_txt text;
    v_numero_existant text;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;
    if p_type not in ('particulier', 'entreprise') then
        raise exception 'Type de reçu fiscal invalide : %', p_type;
    end if;

    if p_don_id is not null then
        select numero_recu_fiscal into v_numero_existant from dons where id = p_don_id;
        if v_numero_existant is not null then
            return v_numero_existant;
        end if;
    end if;

    insert into compteurs_recus_fiscaux (type, annee, dernier_numero)
    values (p_type, v_annee, 1)
    on conflict (type, annee) do update
        set dernier_numero = compteurs_recus_fiscaux.dernier_numero + 1
    returning dernier_numero into v_numero;

    v_prefixe := case p_type when 'particulier' then 'P' else 'E' end;
    v_numero_txt := v_prefixe || '-' || v_annee || '-' || lpad(v_numero::text, 4, '0');

    if p_don_id is not null then
        update dons set numero_recu_fiscal = v_numero_txt where id = p_don_id;
    end if;

    return v_numero_txt;
end;
$$;
