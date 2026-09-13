-- ============================================================
-- LIENS MOUVEMENT ↔ SUIVI (reconstruits proprement)
-- ============================================================
-- Relie un mouvement de caisse ou de banque à son (ou ses) formulaire(s)
-- Suivi d'origine — utile par exemple quand une remise en banque
-- regroupe plusieurs dons distincts en un seul virement.
--
-- Une table de liaison par table de mouvement (caisse_mouvements et
-- banque_mouvements sont deux tables distinctes, donc deux jeux de FK :
-- pas de FK "polymorphe" propre en Postgres).

create table if not exists caisse_mouvement_suivi_liens (
    id                 uuid primary key default gen_random_uuid(),
    caisse_mouvement_id uuid not null references caisse_mouvements(id) on delete cascade,
    adhesion_id        uuid references adhesions(id) on delete cascade,
    don_id             uuid references dons(id) on delete cascade,
    adoption_id        uuid references adoptions(id) on delete cascade,
    reservation_id     uuid references reservations(id) on delete cascade,
    materiel_mouvement_id uuid references materiel_mouvements(id) on delete cascade,
    montant            numeric(10,2),
    constraint ccsl_une_seule_cible check (
        (case when adhesion_id is not null then 1 else 0 end
       + case when don_id is not null then 1 else 0 end
       + case when adoption_id is not null then 1 else 0 end
       + case when reservation_id is not null then 1 else 0 end
       + case when materiel_mouvement_id is not null then 1 else 0 end) = 1
    )
);
create index if not exists idx_ccsl_caisse_mouvement_id on caisse_mouvement_suivi_liens(caisse_mouvement_id);
create index if not exists idx_ccsl_adhesion_id on caisse_mouvement_suivi_liens(adhesion_id);
create index if not exists idx_ccsl_don_id on caisse_mouvement_suivi_liens(don_id);
create index if not exists idx_ccsl_adoption_id on caisse_mouvement_suivi_liens(adoption_id);
create index if not exists idx_ccsl_reservation_id on caisse_mouvement_suivi_liens(reservation_id);
create index if not exists idx_ccsl_materiel_mouvement_id on caisse_mouvement_suivi_liens(materiel_mouvement_id);

create table if not exists banque_mouvement_suivi_liens (
    id                  uuid primary key default gen_random_uuid(),
    banque_mouvement_id uuid not null references banque_mouvements(id) on delete cascade,
    adhesion_id         uuid references adhesions(id) on delete cascade,
    don_id              uuid references dons(id) on delete cascade,
    adoption_id         uuid references adoptions(id) on delete cascade,
    reservation_id      uuid references reservations(id) on delete cascade,
    materiel_mouvement_id uuid references materiel_mouvements(id) on delete cascade,
    montant             numeric(10,2),
    constraint bmsl_une_seule_cible check (
        (case when adhesion_id is not null then 1 else 0 end
       + case when don_id is not null then 1 else 0 end
       + case when adoption_id is not null then 1 else 0 end
       + case when reservation_id is not null then 1 else 0 end
       + case when materiel_mouvement_id is not null then 1 else 0 end) = 1
    )
);
create index if not exists idx_bmsl_banque_mouvement_id on banque_mouvement_suivi_liens(banque_mouvement_id);
create index if not exists idx_bmsl_adhesion_id on banque_mouvement_suivi_liens(adhesion_id);
create index if not exists idx_bmsl_don_id on banque_mouvement_suivi_liens(don_id);
create index if not exists idx_bmsl_adoption_id on banque_mouvement_suivi_liens(adoption_id);
create index if not exists idx_bmsl_reservation_id on banque_mouvement_suivi_liens(reservation_id);
create index if not exists idx_bmsl_materiel_mouvement_id on banque_mouvement_suivi_liens(materiel_mouvement_id);

alter table caisse_mouvement_suivi_liens enable row level security;
alter table banque_mouvement_suivi_liens enable row level security;

drop policy if exists caisse_mouvement_suivi_liens_lecture on caisse_mouvement_suivi_liens;
create policy caisse_mouvement_suivi_liens_lecture on caisse_mouvement_suivi_liens
    for select using (role_compta_courant() is not null);
drop policy if exists caisse_mouvement_suivi_liens_ecriture on caisse_mouvement_suivi_liens;
create policy caisse_mouvement_suivi_liens_ecriture on caisse_mouvement_suivi_liens
    for all using (role_compta_courant() = 'admin');
drop policy if exists banque_mouvement_suivi_liens_lecture on banque_mouvement_suivi_liens;
create policy banque_mouvement_suivi_liens_lecture on banque_mouvement_suivi_liens
    for select using (role_compta_courant() is not null);
drop policy if exists banque_mouvement_suivi_liens_ecriture on banque_mouvement_suivi_liens;
create policy banque_mouvement_suivi_liens_ecriture on banque_mouvement_suivi_liens
    for all using (role_compta_courant() = 'admin');
