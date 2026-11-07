-- ============================================================
-- 068_liens_suivi_historiques.sql
-- Conserve les ANCIENS liens « ligne de compta <-> enregistrement Suivi » du classeur Excel
-- (colonnes suivi_ref de Banque / Caisse / Remises de chèques) et fournit la fonction
-- reconstituer_liens_suivi() qui les REFAIT AUTOMATIQUEMENT quand le Suivi (adoptions,
-- dons, adhésions, réservations, prêts de matériel) a été importé dans la base.
--
-- ÉTAPE 1 (maintenant) : exécuter ce fichier une fois. Il n'écrit rien dans les tables de compta.
-- ÉTAPE 2 (après l'import du Suivi) : select * from reconstituer_liens_suivi();
--   -> relançable à volonté : seuls les liens pas encore faits sont retraités.
-- Les cas non résolus se consultent avec : select * from v_liens_suivi_a_verifier;
-- Dépend de : 014, 015, 017 (tables de liens), 039 (colonnes de lien des chèques de remise).
-- Généré automatiquement depuis « Arche_Compta_2025-2026.xlsx » (222 références).
-- ============================================================

create table if not exists liens_suivi_historiques (
    id            uuid primary key,
    source        text not null check (source in ('banque', 'caisse', 'remise_detail')),
    source_id     uuid not null,          -- id de la ligne de compta (banque_mouvements, caisse_mouvements, remise_cheques_details)
    ancien_ref    text not null,          -- référence d'origine, ex. « Adoption:25/09/2025|18:43:0 »
    suivi_type    text check (suivi_type in ('adhesion', 'don', 'adoption', 'reservation', 'materiel_mouvement')),
    sous_type     text,                   -- réservation : 'chat' ou 'chaton'
    date_suivi    date,                   -- date de l'enregistrement Suivi d'origine
    nom           text,
    prenom        text,
    animal        text,
    recu_fiscal   text,
    montant_lien  numeric(10,2),          -- part du mouvement correspondant à cet enregistrement (si connue)
    statut        text not null default 'a_traiter' check (statut in ('a_traiter', 'lie', 'introuvable', 'ambigu')),
    cible_id      uuid,                   -- enregistrement Suivi retrouvé
    note          text,
    traite_le     timestamptz
);
create index if not exists idx_lsh_source on liens_suivi_historiques(source, source_id);
alter table liens_suivi_historiques enable row level security;
drop policy if exists liens_suivi_historiques_admin on liens_suivi_historiques;
create policy liens_suivi_historiques_admin on liens_suivi_historiques for all
    using (role_compta_courant() = 'admin') with check (role_compta_courant() = 'admin');

-- ---------- Anciennes références ----------
insert into liens_suivi_historiques (id, source, source_id, ancien_ref, suivi_type, sous_type, date_suivi, nom, prenom, animal, recu_fiscal, montant_lien, statut) values
('09bfe56f-2012-59d5-bdce-e036057fd1b4', 'banque', 'd9f6ff14-6185-58e4-bc04-e50f8783289d', 'Adoption:25/09/2025|18:43:0', 'adoption', null, '2025-09-25', 'DEPARIS MAGAGNA', 'CORINNE', 'perle', null, null, 'a_traiter'),
('b6aa4940-ae4a-5e46-98c2-c721c857b77a', 'banque', '4bf71a6e-dec7-5d1e-9bcf-7df8132b5376', 'Reservation_Chaton:05/07/2026|19:57:0', 'reservation', 'chaton', '2025-12-30', 'MONNIER', 'COROLINE', 'ficelle', null, 50.00, 'a_traiter'),
('66edf536-bc75-5a00-969b-a2deb8a03787', 'banque', '45c091da-26db-5ce3-b100-a8f58c78d023', 'Contrat_reservation_chat:05/07/2026|18:01:0', 'reservation', 'chat', '2026-02-20', 'MONNIER', 'CAMILLE', 'nuts', null, 50.00, 'a_traiter'),
('edcd9597-f2f0-583d-9d42-8a03aa2c9691', 'banque', '5b3ad7a0-2a73-5183-8a34-d2cd52d4d189', 'Contrat_reservation_chat:05/07/2026|17:58:0', 'reservation', 'chat', '2026-02-20', 'MONNIER', 'CAMILLE', 'lilou', null, 50.00, 'a_traiter'),
('49dcd0b6-9f29-5660-b6fd-122f555335ba', 'banque', 'a4f3dc68-f7a4-50b5-ab1e-5a4110ce1527', 'Adoption:05/07/2026|18:10:1', 'adoption', null, '2026-02-20', 'MONNIER', 'CAMILLE', 'nuts', null, 170.00, 'a_traiter'),
('8ae15279-3edd-51de-917d-3cc585544a4e', 'banque', '754ee5b6-b4d4-5846-a9e5-554113fd98d5', 'Contrat_reservation_chat:05/07/2026|19:37:0', 'reservation', 'chat', '2026-03-13', 'BOUVROT', 'MADELINE', 'panthere', null, 50.00, 'a_traiter'),
('9d775670-d711-58e8-9303-0cc9644a0349', 'banque', 'be4ca441-9a59-5dbb-9efd-263d7d7b45e3', 'Reservation_Chaton:22/06/2026|19:07:0', 'reservation', 'chaton', '2026-06-22', 'VOLPINI', 'YANN', 'Ice', null, null, 'a_traiter'),
('57ea7e06-292e-532e-8869-8b74ec3df52f', 'banque', 'e58ffb45-e3a6-5fc2-bfc4-91892e8c6967', 'Reservation_Chaton:21/06/2026|17:50:0', 'reservation', 'chaton', '2026-06-21', 'GACEUS', 'ELISA', 'Minuit', null, null, 'a_traiter'),
('151495bc-a716-56d1-8125-f397bdfb5916', 'banque', '0f89d8ed-aed3-5e80-b288-24850776ba80', 'Reservation_Chaton:12/06/2026|19:23:0', 'reservation', 'chaton', '2026-06-12', 'ESTEVES', 'LUKAS', 'Idefix', null, null, 'a_traiter'),
('261c24f3-144d-59f2-8ffc-9ee97834b2da', 'banque', '9e5f1a35-434e-50ec-ac33-c7a285c44ef8', 'Adoption:10/06/2026|19:30:0', 'adoption', null, '2026-06-10', 'MARTIN', 'STÉPHANE', 'Balou', null, null, 'a_traiter'),
('6cb1ce27-88f4-5449-be45-39036f2462c3', 'banque', 'fdcd11da-882d-53ec-ab1a-f655c068af11', 'Reservation_Chaton:15/06/2026|19:00:0', 'reservation', 'chaton', '2026-06-15', 'PERREZ', 'CÉCILE', 'Fripon', null, null, 'a_traiter'),
('e68ccfea-5c2a-540d-821e-10f7d95f569d', 'banque', 'a3feda2b-0ee4-502f-90d5-e3b87a88c289', 'Reservation_Chaton:05/06/2026|18:50:0', 'reservation', 'chaton', '2026-06-05', 'FASCINA', 'AMELIA', 'Praline', null, null, 'a_traiter'),
('f7fdece6-9e47-5a7b-8238-45347bd2b8df', 'banque', '719c4c60-4613-5e5f-89b6-82865f3166f9', 'Reservation_Chaton:04/06/2026|18:29:0', 'reservation', 'chaton', '2026-06-04', 'VALENTIN', 'AARON', 'Jazz', null, null, 'a_traiter'),
('28a5f7a7-7ad3-5617-917d-4aeb53d91a83', 'banque', 'd3320c7d-3e08-5a42-a6aa-baef395f18de', 'Reservation_Chaton:20/07/2026|19:01:0', 'reservation', 'chaton', '2026-07-20', 'ALBERSAMMER', 'TIM', 'Liam', null, 50.00, 'a_traiter'),
('484348d2-6e98-5dbd-9403-a9afd572da6c', 'banque', '601b7901-207a-5b28-8d0e-c795c5dfc956', 'Adoption:10/07/2026|18:37:1', 'adoption', null, '2026-07-10', 'SAIRE', 'CORINNE', 'Yumi', null, 70.00, 'a_traiter'),
('927ca2c4-7220-5973-9dcb-54d1a6176298', 'banque', '33d1bb01-0ba9-5abf-8538-f7c4726a4118', 'Adoption:30/06/2026|18:05:1', 'adoption', null, '2026-06-30', 'VALENTIN', 'AARON', 'Jazz', null, null, 'a_traiter'),
('f0f5a399-6c86-52de-9253-649343dc9023', 'banque', '4e0b0039-51c7-5335-8b0f-a4725121bf67', 'Adoption:28/06/2026|16:45:1', 'adoption', null, '2026-06-28', 'MAURICE', 'ELISA', 'Pandora', null, null, 'a_traiter'),
('3edbefb5-64b1-5ce2-b69e-8101e03c9fe8', 'banque', '732f865d-9b1c-5932-95c1-6aca11014d8c', 'Reservation_Chaton:04/09/2026|19:02:0', 'reservation', 'chaton', '2026-09-04', 'TABET', 'FARES', 'Tuica', null, 50.00, 'a_traiter'),
('6599986e-62b3-5299-b3e2-04843ce29d44', 'banque', '732f865d-9b1c-5932-95c1-6aca11014d8c', 'Adoption:04/09/2026|18:33:0', 'adoption', null, '2026-09-04', 'DIETSCH', 'ALAIN', 'Saké', null, 120.00, 'a_traiter'),
('cb102667-a6ce-5191-80f0-bb2effd699e6', 'banque', '4161191b-8663-5053-8977-4b5fad15816d', 'Reservation_Chaton:05/09/2026|17:54:0', 'reservation', 'chaton', '2026-09-05', 'DUPARCHY', 'MATHIS', 'Bea', null, 50.00, 'a_traiter'),
('33508483-1da1-59f0-8de6-d7d13637edfa', 'banque', '885617b7-46f2-51a0-98ff-4898547b9ed7', 'Reservation_Chaton:31/08/2026|19:06:0', 'reservation', 'chaton', '2026-08-31', 'ROUVIER', 'MARIE-MICHELE', 'Tatouille', null, 50.00, 'a_traiter'),
('8e9ac189-5437-5021-8468-820c6950775d', 'banque', '11e03d71-4083-5075-a0a3-696471f3303c', 'Contrat_reservation_chat:30/08/2026|12:11:0', 'reservation', 'chat', '2026-08-30', 'PERRO-GUEFFIER', 'EMILIE', 'Biscotte', null, 100.00, 'a_traiter'),
('835dbc50-e7b5-5483-81dd-9955aafb9551', 'banque', '924fe6a1-ce77-5344-a72a-3e20753be65c', 'Dons:05/09/2026|17:05:0', 'don', null, null, 'BIZUARD', 'JUSTINE', null, null, 30.00, 'a_traiter'),
('664f27d7-5f4d-58bd-b8a6-cf4f90f0a91e', 'banque', 'cf383b2b-490d-554f-a19a-49cbbfc772e7', 'Dons:05/09/2026|17:08:0', 'don', null, null, 'SCHOEN', 'PASCALE', null, null, 50.00, 'a_traiter'),
('25f87c57-08d9-573a-95ba-7381ded7e27e', 'banque', 'd52949b7-75df-572c-81e3-85a11c540a69', 'Reservation_Chaton:22/08/2026|17:39:0', 'reservation', 'chaton', '2026-08-22', 'CANET', 'BILLY', 'Vodka', null, 50.00, 'a_traiter'),
('39dd4677-b749-5341-9c78-a73802602cc9', 'banque', 'd52949b7-75df-572c-81e3-85a11c540a69', 'Reservation_Chaton:22/08/2026|18:17:0', 'reservation', 'chaton', '2026-08-22', 'MOUGEOT', 'JADE', 'Eristoff', null, 50.00, 'a_traiter'),
('83ccc4c8-edf8-552f-bd98-a611ac03c674', 'banque', '8daf7174-76a8-548f-a1b8-fa01c5b59283', 'Reservation_Chaton:20/08/2026|18:42:0', 'reservation', 'chaton', '2026-08-20', 'DIETSCH', 'ALAIN', 'Saké', null, 50.00, 'a_traiter'),
('6393e036-0bf1-5ff9-bba1-a6d5d14cd83c', 'banque', 'ea52c2c6-759f-5e76-ba57-5d2222659591', 'Adoption:08/10/2026|18:22:0', 'adoption', null, '2026-10-08', 'TABAC', 'MARIE', 'Bianca', null, 90.00, 'a_traiter'),
('703dc563-a891-507c-99fa-878d39e0073d', 'banque', 'df373d44-6f94-54bd-aa82-3051a306aee8', 'Pret_Materiel:05/10/2026|18:28:0', 'materiel_mouvement', null, '2026-10-05', 'BUCHER', 'SONIA', null, null, 100.00, 'a_traiter'),
('a6ef9f31-1423-5e47-93d9-657a7ed520a0', 'banque', '995e05f2-c759-54eb-81c1-36c3a8d784d1', 'Adoption:03/10/2026|11:19:0', 'adoption', null, '2026-10-03', 'SCHMITT', 'DIDIER', 'Flamme', null, 50.00, 'a_traiter'),
('1b7abc10-04a3-5902-943e-70c1b885192f', 'banque', 'e92fcb30-a702-508e-951b-0527871c1dd9', 'Contrat_reservation_chat:03/10/2026|10:11:0', 'reservation', 'chat', '2026-10-03', 'RICHARD KERN', 'AMANDINE', 'Oreo', null, 50.00, 'a_traiter'),
('7a5883e8-7433-5b1c-a74d-d0eac9891f24', 'banque', '6dadbb59-8183-5730-a34a-1a23677d64ee', 'Reservation_Chaton:26/09/2026|18:42:0', 'reservation', 'chaton', '2026-09-26', 'SCHMITT', 'DIDIER', 'Flamme', null, 50.00, 'a_traiter'),
('6f57bce7-806a-5d14-bf5f-50f9f66e6d34', 'banque', '3173d49b-8cff-5f07-9883-3a3629c9f007', 'Contrat_reservation_chat:18/09/2026|18:29:0', 'reservation', 'chat', '2026-09-11', 'MAURAS', 'DAMIEN', 'Mirabelle', null, 50.00, 'a_traiter'),
('edb26018-c6de-5574-9064-6560b51d68ff', 'banque', '80c0e7a3-6a07-527c-9e03-a0952b23af59', 'Dons:12/09/2026|17:58:0', 'don', null, null, 'MEYSSONNIER', 'GWENDOLINE', null, null, 100.00, 'a_traiter'),
('a9b82dea-21a0-516d-8d8d-32c2fdf9b7b1', 'banque', '334f2f96-66e1-5285-9863-a12074c54002', 'Adoption:09/09/2026|18:19:0', 'adoption', null, '2026-09-11', 'TABET', 'FARES', 'Tuica', null, 120.00, 'a_traiter'),
('f3e0fa14-6059-568e-b959-27ca91252526', 'banque', 'c5b9beb9-c12d-5217-8bb6-7e44a769ada1', 'Dons:20/09/2026|22:51:0', 'don', null, null, 'Guillaume VUITTON', 'ECOSPHERE', null, null, 500.00, 'a_traiter'),
('aec66a9c-eba3-5486-91f8-6beef9eb4cbf', 'banque', '556634a3-18bb-5761-b846-1a3e6ce55c2f', 'Pret_Materiel:07/09/2026|18:03:0', 'materiel_mouvement', null, '2026-09-07', 'MARGUIER', 'FRANÇOIS', null, null, 100.00, 'a_traiter'),
('8c179cd8-14d5-5670-b4a2-04304f1a53bd', 'banque', 'c89a61fc-d54d-505f-8648-14cf7fff740e', 'Reservation_Chaton:06/09/2026|18:36:0', 'reservation', 'chaton', '2026-09-06', 'CHIAPPINI', 'ELISE', 'Bingo', null, 50.00, 'a_traiter'),
('9ec08eea-9c45-55c7-854d-860c5926c838', 'banque', '15c44b16-de79-5daf-917e-1a7d49be9606', 'Adoption:05/09/2026|16:49:0', 'adoption', null, '2026-09-05', 'ROUVIER', 'MARIE-MICHELE', 'Tatouille', null, 130.00, 'a_traiter'),
('99912cba-0108-518d-8045-41a7a82026dd', 'banque', 'ddca2ef9-8bb9-53f8-b985-de4ca30a7dbc', 'Adoption:05/09/2026|18:06:0', 'adoption', null, '2026-09-05', 'DUPARCHY', 'MATHIS', 'Bea', null, 70.00, 'a_traiter'),
('001362c6-9f6c-5fa0-bc5d-2fd045807885', 'banque', 'c4118c23-8c4e-568e-ad55-cec3cf5b9dfa', 'Reservation_Chaton:25/10/2026|18:58:0', 'reservation', 'chaton', '2026-10-25', 'TIZIANI', 'CORINNE', 'Yuchi', null, null, 'a_traiter'),
('0a702873-f361-57a7-a8fc-4365c2827465', 'banque', 'c4118c23-8c4e-568e-ad55-cec3cf5b9dfa', 'Adoption:25/10/2026|10:32:0', 'adoption', null, '2026-10-25', 'KHALFALLAH', 'KARIM', 'Duchesse', null, 150.00, 'a_traiter'),
('824d28a4-e248-5414-9a7e-ec1f0e8f8edc', 'banque', 'c4118c23-8c4e-568e-ad55-cec3cf5b9dfa', 'Adoption:25/10/2026|10:44:0', 'adoption', null, '2026-10-25', 'KHALFALLAH', 'KARIM', 'Franie', null, 150.00, 'a_traiter'),
('91ad1946-2b9a-5c3a-a52a-7f910dd5ea77', 'banque', '93996f6c-bcf1-5cde-b155-1554763f0025', 'Adoption:24/10/2026|10:17:0', 'adoption', null, '2026-10-24', 'GUARDIOLE', 'LOIC', 'Ziggie', null, 90.00, 'a_traiter'),
('45f00c56-a846-5ed0-9c0d-a922de073bec', 'banque', '93996f6c-bcf1-5cde-b155-1554763f0025', 'Adoption:24/10/2026|10:36:0', 'adoption', null, '2026-10-24', 'GUARDIOLE', 'LOIC', 'Filou', null, 90.00, 'a_traiter'),
('f91912f2-60bf-5c2d-be9e-a009796f2b9f', 'banque', '93996f6c-bcf1-5cde-b155-1554763f0025', 'Adoption:24/10/2026|11:17:0', 'adoption', null, '2026-10-24', 'REES', 'DIANA', 'Birk', null, 40.00, 'a_traiter'),
('140c6989-9003-5201-b93b-17bec47d5553', 'banque', '41d21bcd-f85b-5ace-b0fe-d115f63dfbdd', 'Adoption:23/10/2026|18:53:0', 'adoption', null, '2026-10-23', 'BAVARD', 'AMANDINE', 'Avanne', null, 90.00, 'a_traiter'),
('49957e27-6784-534b-8388-9fbd991e48ee', 'banque', '21f8d8ae-6ddb-53c4-b840-d99018623169', 'Reservation_Chaton:20/10/2026|20:01:0', 'reservation', 'chaton', '2026-10-20', 'WIRA', 'FRÉDÉRIC', 'Brooklyn', null, 50.00, 'a_traiter'),
('7b06d392-9e5d-5ac7-8566-180cf4dcc2a1', 'banque', 'fdbef2cb-4adf-596d-8466-6ecf47049539', 'Contrat_reservation_chat:18/10/2026|11:45:0', 'reservation', 'chat', '2026-10-18', 'KHALFALLAH', 'KARIM', 'Franie', null, 50.00, 'a_traiter'),
('7b374728-8b47-5989-94db-9bf212f95523', 'banque', 'fdbef2cb-4adf-596d-8466-6ecf47049539', 'Contrat_reservation_chat:18/10/2026|12:04:0', 'reservation', 'chat', '2026-10-18', 'KHALFALLAH', 'KARIM', 'Duchesse', null, 50.00, 'a_traiter'),
('42559c4c-f2a2-5227-8355-4ece433b03cd', 'banque', 'fdbef2cb-4adf-596d-8466-6ecf47049539', 'Reservation_Chaton:18/10/2026|10:49:0', 'reservation', 'chaton', '2026-10-18', 'GUARDIOLE', 'LOIC', 'Ziggie', null, 50.00, 'a_traiter'),
('956ad11d-b307-5961-99cf-fb474bd5468b', 'banque', 'd4b46567-9526-5dd1-86b2-48ee0fb0fe15', 'Reservation_Chaton:13/10/2026|19:31:0', 'reservation', 'chaton', '2026-10-13', 'BAVARD', 'AMANDINE', 'Avanne', null, 50.00, 'a_traiter'),
('b1d38dbf-c47a-582b-bbc1-5309cb476ff6', 'banque', '238af31e-ec71-5b12-8eb7-fe30d4619063', 'Reservation_Chaton:10/10/2026|18:49:0', 'reservation', 'chaton', '2026-10-10', 'PAILLARD', 'MANON', 'Aky', null, 50.00, 'a_traiter'),
('398cecd3-d87b-55bc-8c6b-ca92f05f02ca', 'banque', '238af31e-ec71-5b12-8eb7-fe30d4619063', 'Adoption:10/10/2026|10:27:0', 'adoption', null, '2026-10-10', 'RICHARD KERN', 'AMANDINE', 'Oréo', null, 220.00, 'a_traiter'),
('48cc9937-0dba-5f62-91b1-af642cf07b7b', 'banque', 'f884a57f-f63d-5c30-b29f-1c22066fd04b', 'Contrat_reservation_chat:29/10/2026|17:53:0', 'reservation', 'chat', '2026-10-29', 'VOINOT', 'ROMAIN', 'Panda', null, 50.00, 'a_traiter'),
('d7c6ce43-6b89-5a69-be3f-085e2957c4f8', 'banque', 'a12e9b28-e1c6-528e-ae8e-5250fdc2a923', 'Adoption:27/10/2026|18:30:0', 'adoption', null, '2026-10-27', 'WIRA', 'FRÉDÉRIC', 'Brooklyn', null, 100.00, 'a_traiter'),
('8680f033-f53d-53c9-a0b4-9dcca6f0b3af', 'banque', 'a12e9b28-e1c6-528e-ae8e-5250fdc2a923', 'Reservation_Chaton:27/10/2026|18:39:0', 'reservation', 'chaton', '2026-10-27', 'LAFFAY', 'ADELINE', 'Garfield', null, 50.00, 'a_traiter'),
('7e4da33a-7468-5522-9d98-668d0aa05994', 'caisse', '0bd8b1f1-9d80-5193-a53c-663e22909908', 'Adoption:08/07/2026|09:59:0', 'adoption', null, '2026-07-08', 'PEQUIGNOT', 'JEAN MARIE', 'Tenessee', null, 250.00, 'a_traiter'),
('0e3b4537-ba6e-5099-a37a-bf4a046dfab5', 'caisse', 'b0e1eeac-b4ab-5d95-8bbb-dd1e50e32677', 'Adoption:25/06/2026|18:57:1', 'adoption', null, '2026-06-25', 'GACEUS', 'ELISA', 'Minuit', null, null, 'a_traiter'),
('f1963099-8822-5932-863d-e23e324fcd88', 'caisse', '64b9308e-395f-5c9e-9f11-1518e08c17c2', 'Dons:01/07/2026|21:17:0', 'don', null, null, 'BENACHIR', 'LILOU', null, null, null, 'a_traiter'),
('ba382d97-95ee-5eb8-8b81-f595e4497750', 'caisse', '77d2acf3-7e43-57ff-bb6a-25bb9055b944', 'Dons:27/06/2026|19:19:0', 'don', null, null, 'BRUDER', 'MATHIEU', null, null, null, 'a_traiter'),
('ae219bf7-22bc-5d7d-b6a1-26584b3a6e4b', 'caisse', '5f52b870-f9fd-5b05-a02c-ed88a2405cc2', 'Dons:14/05/2026|21:47:0', 'don', null, null, 'ORTEGA', 'CATHERINE', null, null, null, 'a_traiter'),
('c0dac5a3-7ada-5870-894c-e2e512e64f3e', 'caisse', 'bb8c99b8-3ecf-5fcd-8378-6a0ad64d4e21', 'Dons:29/04/2026|19:00:0', 'don', null, null, 'MENIGOZ', 'Pascale', null, null, null, 'a_traiter'),
('214f7018-f1aa-5c58-bd63-4591d078a479', 'caisse', '60575d03-a74a-5a43-90a7-43c05299c357', 'Dons:05/07/2026|19:22:0', 'don', null, null, 'NOBLAT', 'GAELLE', null, null, 10.00, 'a_traiter'),
('93d0bab9-947b-5c29-8911-ba2a5e3c3038', 'caisse', 'ba9f713b-0821-5d1a-ac67-0dda117e99b4', 'Dons:05/02/2026|21:47:0', 'don', null, null, null, 'ASSOCIATION WELL''COM', null, null, null, 'a_traiter'),
('a267a8b8-f346-5938-a87b-e92f504c7fae', 'caisse', 'd7006de8-cf6d-5cc5-b0b4-b97f958f0645', 'Contrat_reservation_chat:02/07/2026|18:01:0', 'reservation', 'chat', '2026-07-02', 'PEQUIGNOT', 'JEAN-MARIE', 'Tenessee', null, null, 'a_traiter'),
('ceb92c8f-bf6a-5b44-ba97-dc085c5ee6e7', 'caisse', 'dc237458-8b61-5ec8-9f06-c41a72ce0e98', 'Reservation_Chaton:06/06/2026|17:30:0', 'reservation', 'chaton', '2026-06-06', 'ROGER', 'NOEMIE', 'Mojito', null, null, 'a_traiter'),
('c144c36d-4d38-5ed9-b0c0-842c1657ffaf', 'caisse', 'dc206d03-05fd-5605-bf1a-a05fdebbf61c', 'Reservation_Chaton:05/06/2026|17:24:0', 'reservation', 'chaton', '2026-06-05', 'MAURICE', 'ELISA', 'Pandora', null, null, 'a_traiter'),
('57945f87-d1f8-5e05-b786-a4f935097ada', 'caisse', '6010dfee-f6a6-5f7b-b718-5c259ecb226f', 'Adhesion:09/05/2026|20:18:2', 'adhesion', null, '2026-05-09', 'ZLIGA', 'Stephanie', null, null, null, 'a_traiter'),
('2750c434-e775-56e2-8db9-5b289e0fd8de', 'caisse', '0c806028-5e38-57ec-a69c-7c502910b464', 'Reservation_Chaton:05/07/2026|19:20:0', 'reservation', 'chaton', '2026-03-22', 'NOBLAT', 'GAELLE', 'spiderman', null, 50.00, 'a_traiter'),
('e35894cd-4f46-59e6-a63a-82cad13dbe2c', 'caisse', 'a34c4c61-17da-57a1-80e9-b5efed29c10f', 'Adhesion:30/04/2026|20:15:2', 'adhesion', null, '2026-04-30', 'PROTHAIN', 'Catherine', null, null, null, 'a_traiter'),
('8411fda8-124c-546d-b748-2dc0f6894614', 'caisse', '84691f8d-bd50-582a-8de3-736b67c15f8b', 'Adhesion:26/02/2026|20:16:2', 'adhesion', null, '2026-02-26', 'FESSARD', 'Aurélie', null, null, null, 'a_traiter'),
('dc230008-581e-5efa-a8ce-b03e2dcd8d05', 'caisse', '3bb05968-c35b-5433-b116-d1f93468434d', 'Contrat_reservation_chat:05/07/2026|18:23:0', 'reservation', 'chat', '2026-02-15', 'FROEHLY', 'AUDE', 'mistinguette', null, 50.00, 'a_traiter'),
('c30879c1-c923-5aa0-b34a-74ed23837e0d', 'caisse', '53c10902-fb8a-5a56-ac04-beb2f13e3f9d', 'Adhesion:09/02/2026|20:17:2', 'adhesion', null, '2026-02-09', 'HUGUEL', 'Alovia', null, null, null, 'a_traiter'),
('711466ed-0908-5d3b-b9ae-a55dd6465dcc', 'caisse', 'd2df40a4-329c-5089-a8c9-6c0d07e9986c', 'Adhesion:09/02/2026|20:18:2', 'adhesion', null, '2026-02-09', 'FENARD', 'Aurélie', null, null, null, 'a_traiter'),
('6d712f10-6d61-5900-bf57-564b61a28c27', 'caisse', '1af503b1-9e68-51f5-8071-18f344fe4840', 'Reservation_Chaton:05/07/2026|18:17:0', 'reservation', 'chaton', '2026-02-03', 'GERALDES', 'RAPHAEL', 'silver', null, 50.00, 'a_traiter'),
('a61636e3-4667-5947-9929-dd8de06e193e', 'caisse', '9de1496d-32dd-5ae4-a53c-0d782fbb4ab1', 'Reservation_Chaton:05/07/2026|20:02:0', 'reservation', 'chaton', '2026-01-04', 'PERNOT', 'CELINE', 'louna', null, 50.00, 'a_traiter'),
('b42265cf-3bd8-533c-96c3-7e99086b98a1', 'caisse', 'bf736b9f-4db5-5116-80d4-e662402023e2', 'Adoption:04/07/2026|18:07:1', 'adoption', null, '2026-07-04', 'ESTEVES', 'LUKAS', 'Idefix', null, 70.00, 'a_traiter'),
('e8f0de75-3f75-5005-b1fd-9a5a64746bcf', 'caisse', '873416ba-313d-54b8-b0a8-2c5cdf607b5f', 'Adoption:03/07/2026|18:14:1', 'adoption', null, '2026-07-03', 'PELLICORO', 'JEANNE', 'Crunch', null, null, 'a_traiter'),
('5a22a122-d043-59bf-aff8-3719f075162e', 'caisse', '2bfca0fe-c8f6-594a-995d-bbe686585223', 'Adoption:28/06/2026|11:11:1', 'adoption', null, '2026-06-28', 'DONNARD', 'ENORA', 'Berlioz', null, null, 'a_traiter'),
('51045bd8-dddb-5e72-ad0d-b3652aa0ae31', 'caisse', '91364ee2-df60-53aa-a853-b93ef6f60094', 'Adoption:24/06/2026|10:42:1', 'adoption', null, '2026-06-24', 'POLY', 'SANDRINE', 'Frimousse', null, null, 'a_traiter'),
('d04b2267-5110-58c9-b3f6-25da783cf652', 'caisse', '2075a525-6e31-551f-af55-a4693d144478', 'Adoption:18/06/2026|19:03:1', 'adoption', null, '2026-06-18', 'BLIN', 'CAROLE', 'Balthazar', null, null, 'a_traiter'),
('2506bc74-cf8f-5b50-8baa-b59b315f7785', 'caisse', 'f3b43e7e-a45e-56be-8694-3ba29fac2b24', 'Adoption:05/07/2026|18:41:1', 'adoption', null, '2026-04-06', 'ALLEMANN', 'GIULIA', 'alba', null, 180.00, 'a_traiter'),
('682d54a9-dc59-558a-b4b3-f7f3342e5aaa', 'caisse', '3d4a010d-baf0-5488-8940-6875853b69a1', 'Adoption:05/07/2026|18:15:1', 'adoption', null, '2026-02-27', 'GERALDES', 'RAPHAEL', 'silver', null, 20.00, 'a_traiter'),
('437a376a-c6c4-529a-b00f-03be4ad3f567', 'caisse', '34b08a0a-eb6d-59c4-8e87-31fc2555c2f9', 'Adoption:05/07/2026|20:01:1', 'adoption', null, '2026-01-16', 'PERNOT', 'CELINE', 'louna', null, 40.00, 'a_traiter'),
('4bd47dc3-3205-5c8e-bd28-129d034b66a0', 'caisse', 'b13b9613-6e59-5d62-8209-d77a264e9d15', 'Adoption:05/07/2026|17:33:1', 'adoption', null, '2026-01-07', 'MODAUX', 'MELISSA', 'perla', null, 50.00, 'a_traiter'),
('c39aa1dd-757a-5e73-8ae2-fe26e8f9afc0', 'caisse', '0c379bba-f452-59aa-98bb-88cc30dc405b', 'Adoption:17/12/2025|18:07:0', 'adoption', null, '2025-12-17', 'EL BAQQALI', 'MELISSA', 'Arya', null, null, 'a_traiter'),
('0a8986c5-8ca0-597a-b34b-c6fa9c8edafa', 'caisse', '11b710f4-9fee-594b-9a2e-40e2912c1f45', 'Adoption:26/11/2025|12:09:0', 'adoption', null, '2025-11-26', 'LUPFER', 'CAMILLE', 'FOX', null, null, 'a_traiter'),
('851e65cf-ac2e-5450-b05a-c36dab7f6442', 'caisse', '3da19e50-de2b-5525-a38a-15f15b776b3b', 'Adoption:17/08/2026|18:24:0', 'adoption', null, '2026-08-17', 'DEMIR', 'MUHAMET', 'Mirabelle', null, 50.00, 'a_traiter'),
('98f31790-3855-5e02-9432-f5569f499cc9', 'caisse', 'd85de110-2fda-5a2d-a412-399f9437c08a', 'Reservation_Chaton:15/08/2026|18:49:0', 'reservation', 'chaton', '2026-08-15', 'DUPOISOT', 'HELENE', 'Bobine', null, 50.00, 'a_traiter'),
('a7b28548-4259-509d-992c-68786b428112', 'caisse', '26110302-9e34-5b23-a399-427a145b48ed', 'Adhesion:01/11/2025|19:59:2', 'adhesion', null, '2025-11-01', 'LABRIET', 'ALAIN', null, null, null, 'a_traiter'),
('536e6aa7-43a7-5ce1-8121-5a24a37dd23c', 'caisse', 'e02244e5-5969-54fd-a536-457f279cf312', 'Adoption:25/07/2026|10:01:1', 'adoption', null, '2026-07-25', 'TESSIAU', 'LOU-ANNE', 'Mercure', null, 40.00, 'a_traiter'),
('a08e1cf1-2c75-5100-932b-c7db2c6d35c3', 'caisse', '62640a6a-2509-53f3-9722-33d08e732ba5', 'Adoption:25/07/2026|09:42:1', 'adoption', null, '2026-07-25', 'BERGEON', 'DAVID', 'Sphere', null, 40.00, 'a_traiter'),
('5fc79882-4a9d-54fb-8d28-dbfbd9b6906b', 'caisse', '7d3f6da3-ed74-5061-99e8-7e862f6e1a7f', 'Adoption:26/07/2026|18:49:1', 'adoption', null, '2026-07-26', 'ALBERSAMMER', 'TIM', 'Liam', null, 40.00, 'a_traiter'),
('aafce1ff-864e-5666-8b78-1b44cf11a9cd', 'caisse', '831de392-f821-5b2b-8010-387bbe02dca3', 'Reservation_Chaton:07/08/2026|18:33:0', 'reservation', 'chaton', '2026-08-07', 'HILDENBRAND', 'SANDY', 'Polochone', null, 50.00, 'a_traiter'),
('58e036ef-8c95-5542-9829-ee4dd2900133', 'caisse', '9bc2caca-cb77-574d-a35c-90e5db046434', 'Reservation_Chaton:20/07/2026|18:24:0', 'reservation', 'chaton', '2026-07-20', 'VILLA', 'ALLIANCE', 'Mellena', null, 50.00, 'a_traiter'),
('c983f46d-d076-5b81-8bf5-ebd6c6790f8c', 'caisse', 'd543460d-0c32-5f69-852b-7b66f6ba5aa4', 'Adoption:19/07/2026|12:11:1', 'adoption', null, '2026-07-19', 'RAHON', 'BENOIT', 'Chani', null, 150.00, 'a_traiter'),
('05ac66f3-0e1f-537c-8bf0-a0632724fc35', 'caisse', '9b775fe9-8fef-5dac-a13b-d0fb837c78e9', 'Adhesion:01/11/2025|19:51:2', 'adhesion', null, '2025-11-01', 'AMET', 'ARIANE', null, null, null, 'a_traiter'),
('cff9b64b-a2f7-59a9-a618-5d3635ae3746', 'caisse', '517692a7-e758-5cd7-be46-ea938d65f1e6', 'Adhesion:01/11/2025|19:52:2', 'adhesion', null, '2025-11-01', 'BOVEE', 'VINCENT - LAETITIA', null, null, null, 'a_traiter'),
('fc3da396-b69b-5c18-8e09-f070c6c4975a', 'caisse', '835f9451-b545-5c3f-92a5-48430db14e60', 'Adhesion:01/11/2025|19:53:2', 'adhesion', null, '2025-11-01', 'CROLUS', 'PHILIPPE', null, null, null, 'a_traiter')
on conflict (id) do nothing;

insert into liens_suivi_historiques (id, source, source_id, ancien_ref, suivi_type, sous_type, date_suivi, nom, prenom, animal, recu_fiscal, montant_lien, statut) values
('f9d641d1-66a5-5d83-b41f-4965f3343f7f', 'caisse', 'de890daa-0d9a-5a23-a400-03a6d788dc83', 'Adhesion:01/11/2025|19:54:2', 'adhesion', null, '2025-11-01', 'CROLUS', 'CLAUDIA', null, null, null, 'a_traiter'),
('e4ef94bb-fb4e-5ecf-9617-7f42f8e198d1', 'caisse', '0a29fd21-0536-5a60-9e81-719db4282f8c', 'Adhesion:01/11/2025|19:55:2', 'adhesion', null, '2025-11-01', 'DEBOULEY', 'Arnaud', null, null, null, 'a_traiter'),
('1fe55cee-1407-553f-bdfb-22801feb31b4', 'caisse', '4a4cd4f0-ace9-589e-8038-bcabf6864bcf', 'Adhesion:01/11/2025|19:57:2', 'adhesion', null, '2025-11-01', 'EINHORM', 'NADINE', null, null, null, 'a_traiter'),
('d99ebec2-6e0c-5ebd-8495-5c5389332df6', 'caisse', '33ef6371-fb5e-5ce6-a555-9ccf8ef7dcc6', 'Adhesion:01/11/2025|20:11:2', 'adhesion', null, '2025-11-01', 'TISSERAND', 'Yannick', null, null, null, 'a_traiter'),
('0c9cbf7b-c6d6-5e94-88d5-6d48517de495', 'caisse', '463ad5ce-77d0-5097-a947-da27da4a995f', 'Adhesion:01/11/2025|20:10:2', 'adhesion', null, '2025-11-01', 'TINNES', 'EMILIE', null, null, null, 'a_traiter'),
('d9d8455a-831d-5674-8ff5-d590cbefb5ed', 'caisse', '314c884a-3707-50fc-aa6f-ada098a8adaa', 'Adhesion:01/11/2025|20:09:2', 'adhesion', null, '2025-11-01', 'SCHNEIDER', 'VIVIANE', null, null, null, 'a_traiter'),
('9045a20b-039e-5f25-99b7-ab3d809c5055', 'caisse', 'd2f38fff-7d58-5f82-bb65-5f0994fcfbfc', 'Adhesion:01/11/2025|20:06:2', 'adhesion', null, '2025-11-01', 'ORTEGA', 'Jonathan', null, null, null, 'a_traiter'),
('64330619-fa8d-5856-b263-fbd36c39fe2d', 'caisse', '25db3519-321a-5f1b-981c-a2cc4ca9e010', 'Adhesion:01/11/2025|20:05:2', 'adhesion', null, '2025-11-01', 'ORTEGA', 'Mallory', null, null, null, 'a_traiter'),
('0971756f-471f-5202-b98a-d0ce37f069c9', 'caisse', '7079878b-a541-59da-93bf-ee97fd2dd051', 'Adhesion:01/11/2025|20:02:2', 'adhesion', null, '2025-11-01', 'MANARANCHE', 'OPHELIE', null, null, null, 'a_traiter'),
('c3b293a7-ffbf-5da7-a27d-16cbfad5f363', 'caisse', '74233639-1b4b-56da-9685-25a8e8cbc409', 'Adhesion:01/11/2025|20:04:2', 'adhesion', null, '2025-11-01', 'NGUYEN', 'MARIE', null, null, null, 'a_traiter'),
('a2947598-78aa-5cba-b921-ff34740e17f3', 'caisse', '9907e965-e97e-5fe2-ab96-6f5089508581', 'Adhesion:01/11/2025|20:11:2', 'adhesion', null, '2025-11-01', 'TISSERAND', 'Yannick', null, null, null, 'a_traiter'),
('29427189-da91-5bbe-ac53-d8fafcb10fbb', 'caisse', '2e5da171-d5a7-5ff0-ba56-3a33e49a152a', 'Adhesion:01/11/2025|20:00:2', 'adhesion', null, '2025-11-01', 'LESAGE', 'LOANE', null, null, null, 'a_traiter'),
('0798d748-191e-5cef-a641-8816dc061298', 'caisse', '177e6670-97d9-501f-89dc-5965557e8252', 'Adhesion:01/11/2025|20:01:2', 'adhesion', null, '2025-11-01', 'LESAGE', 'COLEEN', null, null, null, 'a_traiter'),
('16960e7d-c8af-5e32-b54d-91862c265792', 'caisse', 'f7e34438-47d6-5f6a-a5bf-32e5fa909731', 'Adhesion:01/11/2025|19:59:2', 'adhesion', null, '2025-11-01', 'LABRIET', 'ALAIN', null, null, null, 'a_traiter'),
('7d4ea82d-4a16-5c1e-bcaf-fb19019336bf', 'caisse', 'a047bd18-6d38-5b99-b9a3-3304e815732d', 'Adhesion:01/11/2025|20:19:2', 'adhesion', null, '2025-11-01', 'GLADINIE', 'Julie', null, null, null, 'a_traiter'),
('a5c5d2ca-e853-5616-9554-3d0c6fe57830', 'caisse', '046c991a-51e7-5c6e-aa63-dd76f269d858', 'Dons:29/08/2026|11:18:0', 'don', null, null, null, null, null, null, 20.00, 'a_traiter'),
('701433c7-bd67-5ba1-958f-6958a620abb0', 'caisse', '66d685a6-eb44-5177-b185-065da13fc78e', 'Reservation_Chaton:29/08/2026|10:01:0', 'reservation', 'chaton', '2026-08-29', 'LASSABE', 'FREDERIC', 'Meteore', null, 50.00, 'a_traiter'),
('263560e8-f67e-5ccb-ba42-458df66c0e3a', 'caisse', '548f098e-e306-5b9d-b3ad-3d1aaf4a46ba', 'Adoption:26/08/2026|19:34:0', 'adoption', null, '2026-08-26', 'MAADINI', 'ABDALLAH', 'Bonnie', null, null, 'a_traiter'),
('2bacb6b1-7c01-5f69-b3ab-6d0e4680853a', 'caisse', 'f7240bda-0d83-5b09-8b03-cc4d2e44bada', 'Adoption:25/08/2026|18:05:1', 'adoption', null, '2026-08-25', 'DUPOISOT', 'HELENE', 'Bobine', null, null, 'a_traiter'),
('9e8b17ce-d251-55f1-a248-3dbcb976deb5', 'caisse', 'fc47d802-6cd2-5acb-b8f0-ecdd71ed8c37', 'Dons:05/09/2026|14:22:0', 'don', null, null, null, null, null, null, 50.00, 'a_traiter'),
('0c7cafd3-baf4-5bb5-924b-43e813358e3d', 'caisse', '5cd85973-80ea-57f8-ba2e-643a0bad1092', 'Dons:05/09/2026|14:29:0', 'don', null, null, null, null, null, null, 50.00, 'a_traiter'),
('38f6c898-229e-53c5-a541-1790dcede955', 'caisse', 'cd2c3de5-0c6d-5fe4-9dc1-840acae5b00d', 'Dons:05/09/2026|14:30:0', 'don', null, null, null, null, null, null, 50.00, 'a_traiter'),
('54334adc-ce9b-54cf-9ed4-9f912949cd2a', 'caisse', '8ab55ada-6265-5b5f-b893-9974e38a3b41', 'Dons:05/09/2026|14:35:0', 'don', null, null, null, null, null, null, null, 'a_traiter'),
('1cb3a321-ddfa-5b3c-971a-3dc18a20ff9e', 'caisse', '65e0491d-3132-5de0-9ade-93759fcf7745', 'Dons:05/09/2026|14:48:0', 'don', null, null, 'STRADY', 'ORIANNE', null, null, 150.00, 'a_traiter'),
('d710d0fa-7fc0-5a66-b586-9ce46b1660ee', 'caisse', '6279debc-b004-5c09-bd14-205d726d5061', 'Dons:05/09/2026|14:51:0', 'don', null, null, 'AMET', 'MARINE', null, null, 150.00, 'a_traiter'),
('9132ebff-9732-5ecc-8947-0edab6861640', 'caisse', 'e4305799-7b40-5e86-9a63-11ba100e32e9', 'Dons:05/09/2026|15:29:0', 'don', null, null, 'MERIAUX', 'JULIE', null, null, 50.00, 'a_traiter'),
('f588c644-51b2-5aaf-a7c7-7b455b88a9df', 'caisse', '9c1252f6-ba61-5249-af0e-78cfeb8a6296', 'Dons:05/09/2026|15:37:0', 'don', null, null, null, null, null, null, 30.00, 'a_traiter'),
('97250e8e-5f43-5fa7-979c-87895a3d90b2', 'caisse', 'a9be5b70-5483-5a6f-9326-667a577a9db3', 'Adoption:06/09/2026|11:58:0', 'adoption', null, '2026-09-06', 'PERRO-GUEFFIER', 'EMILIE', 'Biscotte', null, null, 'a_traiter'),
('544d63fe-a026-53ec-ad0c-c2f2e3872402', 'caisse', '0820096e-4cc7-5868-8959-9082518a9666', 'Dons:05/09/2026|16:27:0', 'don', null, null, null, null, null, null, null, 'a_traiter'),
('2a59e1dc-3af2-5967-8da1-7f6e59ee64e7', 'caisse', '92d62182-9af8-5fd5-9c29-3c339a6de945', 'Adoption:05/09/2026|19:00:0', 'adoption', null, '2026-09-05', 'VILLA', 'ALLIANCE', 'Mellena', null, null, 'a_traiter'),
('b4fdf3a2-0c7e-5dba-ab02-8d32d9ebd30f', 'caisse', '3bb20620-2ad2-57ac-92dd-3aa3ccfad6db', 'Adoption:06/10/2026|18:36:0', 'adoption', null, '2026-10-06', 'LE CAM', 'ALAIN', 'Eclipse', null, null, 'a_traiter'),
('407165ef-de62-5761-84a8-e3ea4c0b16ea', 'caisse', 'ff5f6591-513c-59ac-831e-788bbc33f8c1', 'Reservation_Chaton:03/10/2026|09:04:0', 'reservation', 'chaton', '2026-10-03', 'SEILLER', 'JUSTINE', 'Reglisse', null, 50.00, 'a_traiter'),
('e51ddc62-0dc2-5c1f-8553-07361f4d75ef', 'caisse', '35d2c26b-700a-54e5-ac15-e2449979cfc7', 'Adoption:01/10/2026|17:37:0', 'adoption', null, '2026-10-01', 'BUCHER', 'SONIA', 'Violette', null, null, 'a_traiter'),
('f7cff99a-b415-56e1-ad4c-392b4d1b2264', 'caisse', 'f4d70b67-c695-5431-9fa2-3193bd4039b4', 'Contrat_reservation_chat:24/09/2026|18:53:0', 'reservation', 'chat', '2026-09-24', 'BUCHER', 'SONIA', 'Violette', null, 50.00, 'a_traiter'),
('8d3eda2a-fb78-591c-9d80-9cf34ef13e40', 'caisse', '4c7d6d84-4a82-530d-abad-093cd728e8ef', 'Reservation_Chaton:24/09/2026|19:03:0', 'reservation', 'chaton', '2026-09-24', 'LE CAM', 'ALAIN', 'Eclipse', null, 50.00, 'a_traiter'),
('0abbbc1d-6640-5777-a2d4-c12e81c1c92d', 'caisse', '6079e43b-7b69-5d60-9232-af42ee01f591', 'Adoption:18/09/2026|18:46:0', 'adoption', null, '2026-09-18', 'MAURAS', 'DAMIEN', 'Mirabelle(Baya)', null, null, 'a_traiter'),
('795faeed-d081-5b1c-8abf-6fc11a2567b9', 'caisse', '88795ef4-1759-5d4c-922f-bd9a84f9db28', 'Pret_Materiel:21/07/2026|18:39:2', 'materiel_mouvement', null, '2026-07-21', 'SIGRIST', 'RITA', null, null, 100.00, 'a_traiter'),
('3cb8a286-3621-5d4f-9dc8-88d5949a9d0f', 'caisse', '2ce4fcd1-415f-5205-970a-b0e29ab9f090', 'Adoption:17/10/2026|18:13:0', 'adoption', null, '2026-10-17', 'PAILLARD', 'MANON', 'Aky', null, null, 'a_traiter'),
('8aa6a999-ce5b-54f3-ae51-96911985385e', 'caisse', '67e3f8a4-08d7-5fa5-9666-3591f6ebbe98', 'Reservation_Chaton:16/10/2026|18:47:0', 'reservation', 'chaton', '2026-10-16', 'JEUDY', 'AURORE', 'Bolt', null, 50.00, 'a_traiter'),
('a4fef88e-e595-506a-9641-862a820782b2', 'caisse', 'dff7f2c5-99ad-55bd-a6fc-64c18fcc5901', 'Reservation_Chaton:17/10/2026|13:57:0', 'reservation', 'chaton', '2026-10-17', 'REES', 'DIANA', 'Birk', null, 50.00, 'a_traiter'),
('5b3951f6-ba94-5e99-9b93-a62a937b4af9', 'caisse', 'eda0d214-125b-5c1d-ba7e-22cdbf2a0305', 'Reservation_Chaton:27/10/2026|20:16:0', 'reservation', 'chaton', '2026-10-27', 'MEYER', 'LUDIVINE', '250269101629971', null, 50.00, 'a_traiter'),
('86feab68-e67c-5f60-80b2-cf00c9873551', 'caisse', 'cf77858f-2426-598b-9634-d4a68c702bfd', 'Reservation_Chaton:25/10/2026|10:56:0', 'reservation', 'chaton', '2026-10-25', 'OZTEKE', 'ALPER', 'Bao', null, 50.00, 'a_traiter'),
('65447a3f-bf69-5b1e-9622-3eda283bb2f8', 'caisse', 'f20e4fea-5a8a-55dc-80d2-beda309c033d', 'Dons:23/10/2026|18:39:0', 'don', null, null, 'JEUDY', 'AURORE', null, null, 10.00, 'a_traiter'),
('3d035a61-fd0c-5829-8bc9-7d2cf4a70fb4', 'caisse', '3e79504d-6333-597a-8633-220e184b57f9', 'Dons:25/10/2026|11:29:0', 'don', null, null, null, null, null, null, 50.00, 'a_traiter'),
('cc8d70fa-a11f-50b4-b8ea-69470c772d48', 'caisse', '526a03c1-4359-56f5-9c4c-4cd858441631', 'Adoption:23/10/2026|18:27:0', 'adoption', null, '2026-10-23', 'JEUDY', 'AURORE', 'Bolt', null, null, 'a_traiter'),
('1bfca930-fbad-57d3-8529-c72e6ea3fef5', 'caisse', '2a1e31e8-3e94-5e6b-b25f-70ab93a76df3', 'Dons:03/10/2026|11:41:0', 'don', null, null, 'SCHMITT', 'DIDIER', null, null, null, 'a_traiter'),
('27f5aba4-39e4-5a18-afc5-430927506f0b', 'caisse', 'e8caeaef-b3d8-5493-a321-a4147183c6c9', 'Dons:02/09/2026|17:10:0', 'don', null, null, null, null, null, null, 50.00, 'a_traiter'),
('e85904a3-32e0-5fcd-8273-4fb792046aaf', 'remise_detail', 'b7a7180a-233e-517c-832b-2f5247f0f4c1', 'Adhesion:01/11/2025|20:08:2', 'adhesion', null, '2025-11-01', 'ROSSE', 'Carole', null, null, null, 'a_traiter'),
('ae4c00c6-c318-5584-a3f8-5f62e23fcfd6', 'remise_detail', '9318a1d1-9895-5e59-885b-a0551a19e05a', 'Adhesion:01/11/2025|20:03:2', 'adhesion', null, '2025-11-01', 'MOREL', 'ADELINE', null, null, null, 'a_traiter'),
('7b701181-47eb-5a30-9c94-cb3fe58dc9f6', 'remise_detail', '51b693bd-661c-5ba3-a767-5bf5f01f7dee', 'Adhesion:01/11/2025|19:58:1', 'adhesion', null, '2025-11-01', 'JEANNINGROS', 'FREDERIQUE', null, null, null, 'a_traiter'),
('0d1f1e14-d660-5917-bce9-01b04af39a28', 'remise_detail', '479d7a2a-5fde-58cd-b61d-2ac2b3777835', 'Dons:row_22:0', 'don', null, null, 'JEANNINGROS', 'FREDERIQUE', null, null, null, 'a_traiter'),
('3c5f2011-c0ad-59c0-8e6a-f9441f5308d0', 'remise_detail', '11f2bfab-cb23-5509-8ac0-8b5d2ec3c5a5', 'Adhesion:01/11/2025|20:07:2', 'adhesion', null, '2025-11-01', 'RONDOT ENEE', 'AUDREY', null, null, null, 'a_traiter'),
('3c7df48d-0ab7-540f-a2a6-36fe2eb5b155', 'remise_detail', 'c4d0119a-d0c0-563f-96d6-3fe5ff52af01', 'Adoption:05/07/2026|17:42:1', 'adoption', null, '2025-10-03', 'RAUZIER', 'BENEDICTE', 'wandara', null, null, 'a_traiter'),
('d936bdf5-b91f-55f8-a170-c608b584aacf', 'remise_detail', '74277dc0-ce27-50e1-bc7e-e61f73e0a17b', 'Dons:09/01/2026|21:47:0', 'don', null, null, 'BOUVIER', 'FRANCOISE', null, null, null, 'a_traiter'),
('358c5522-eaea-5e04-9069-ef3f150621c6', 'remise_detail', '09fa2200-ab72-571e-8439-7d2849cf73c8', 'Dons:12/01/2026|21:47:0', 'don', null, null, 'KIEFFER', 'DAVID', null, null, null, 'a_traiter'),
('29cdf95c-3cad-54c6-a9c8-1a09770786e3', 'remise_detail', 'd542f6fe-f9b9-5374-8e53-31892ca81705', 'Contrat_reservation_chat:05/07/2026|19:30:0', 'reservation', 'chat', '2026-02-20', 'THIRIET', 'JEAN YVES', 'bounty', null, null, 'a_traiter'),
('9777e12d-5a42-5a9c-be50-0f99ae1f8809', 'remise_detail', '1ba17860-338f-5e0d-836b-a3b570398213', 'Dons:21/02/2026|21:47:0', 'don', null, null, 'MUCK', 'SOLANGE', null, null, null, 'a_traiter'),
('6456ccd6-50b3-5358-821e-ff66ca0363d9', 'remise_detail', 'd4f19938-533c-50c0-b1b6-47b652c14998', 'Adoption:05/07/2026|18:21:1', 'adoption', null, '2026-02-22', 'FROEHLY', 'AUDE', 'mistinguette', null, null, 'a_traiter'),
('58830947-3da0-5f75-94d6-7dab3bcddd5e', 'remise_detail', 'ba502c54-3abc-517a-92a7-dbfd8b572884', 'Dons:02/03/2026|21:47:0', 'don', null, null, 'MARTINET', 'SYLVIE', null, null, null, 'a_traiter'),
('822e85f8-ce82-575b-bdd2-f68f53475717', 'remise_detail', 'c97c1c2a-c78a-5efd-8834-7fa354875baa', 'Adoption:05/07/2026|20:07:1', 'adoption', null, '2026-03-06', 'THIRIET', 'JEAN YVES', 'bounty', null, null, 'a_traiter'),
('3551b45f-4f55-5f21-87ce-5c2876c57e60', 'remise_detail', '35c25d99-9ba8-58b5-bf47-e253f2465bf6', 'Reservation_Chaton:05/07/2026|19:48:0', 'reservation', 'chaton', '2026-03-01', 'PONTIGGA', 'CECILE', 'o maley', null, null, 'a_traiter'),
('21deb37d-5e59-5d6f-ae1e-11c901fedf82', 'remise_detail', 'cb147360-94d8-5662-bd70-fa473036ce01', 'Adoption:08/07/2026|17:24:1', 'adoption', null, '2026-03-29', 'COFIELD', 'HAYLEE', 'STELLA', null, null, 'a_traiter'),
('914eaf71-6c6e-5090-878e-a1917d681ed3', 'remise_detail', '7eb5274a-5abc-5403-9dd7-902b96e4e408', 'Adoption:05/07/2026|19:16:1', 'adoption', null, '2026-03-29', 'NOBLAT', 'GAELLE', 'spiderman', null, null, 'a_traiter'),
('5304f46f-06eb-5ca8-addc-bfbc2adde29a', 'remise_detail', '2b8ff27e-c6d7-5f25-aab7-08e665abc46f', 'Dons:05/07/2026|19:18:0', 'don', null, null, 'NOBLAT', 'GAELLE', null, null, null, 'a_traiter'),
('405bb947-d738-5d14-ab2b-ae11f7807b50', 'remise_detail', 'f606feb2-dce1-59c7-9c47-742f24caf184', 'Adoption:05/07/2026|19:26:1', 'adoption', null, '2026-03-26', 'WENDRELY', 'JEAN FRANCOIS', 'pixel', null, null, 'a_traiter'),
('d1262e72-7d74-5640-ba62-5d1f3f169983', 'remise_detail', '8bb0bbff-6be3-5325-abce-531d1fdf4ecd', 'Adoption:05/07/2026|19:42:1', 'adoption', null, '2026-03-25', 'PONTIGGA', 'CECILE', 'o maley', null, null, 'a_traiter'),
('19bc42f9-bade-5838-8850-c60788a14576', 'remise_detail', '44f24074-5240-5a55-97e2-f781dac084af', 'Dons:05/07/2026|19:43:0', 'don', null, null, 'PONTIGGA', 'CECILE', null, null, null, 'a_traiter'),
('d4a2e13d-1f4f-5f75-ad7f-378c32ad7822', 'remise_detail', 'a539048f-1efd-5d7d-9bea-7e23df501ea5', 'Dons:02/05/2026|21:47:0', 'don', null, null, 'MUCK', 'SOLANGE', null, null, null, 'a_traiter'),
('23503987-dd6b-591c-b548-75fbb33a14b0', 'remise_detail', '53813786-9561-5ccd-93e0-5fdc7b01e9b2', 'Dons:03/05/2026|21:47:0', 'don', null, null, 'AMET', 'ARIANE', null, null, null, 'a_traiter'),
('96e44db9-ae88-5736-bbba-b8b6548f3a29', 'remise_detail', '670efe51-49d7-5909-9189-1d72f9c98c06', 'Dons:16/05/2026|21:47:0', 'don', null, null, 'VILMINOT', 'MARIE DELLE', null, null, null, 'a_traiter'),
('3c0229d0-de52-5a65-9a1d-ec963afda682', 'remise_detail', '5b3af72e-3406-55e8-8174-0f22a98c20a0', 'Reservation_Chaton:13/06/2026|19:18:0', 'reservation', 'chaton', '2026-06-13', 'JARDOT', 'PATRICIA', 'Starlett', null, null, 'a_traiter'),
('cbd2b545-0814-58d6-966e-771672f49f54', 'remise_detail', '3e42d33a-1fe8-5159-8992-a94758ccf0ca', 'Reservation_Chaton:13/06/2026|19:13:0', 'reservation', 'chaton', '2026-06-13', 'PERROT', 'RENÉ', 'Maya', null, null, 'a_traiter'),
('3b84ad16-6274-5014-9790-7ac9e6f5d3f7', 'remise_detail', '1dee74aa-e479-56af-ab70-00e6aa6ec7a1', 'Dons:08/04/2026|21:47:0', 'don', null, null, 'CAUX', 'LAURENCE', null, null, null, 'a_traiter'),
('5278657d-9759-53d8-9236-53c2821ec83a', 'remise_detail', 'e6302983-89ca-57b5-8221-84a3aebab2cb', 'Adoption:23/06/2026|10:35:1', 'adoption', null, '2026-06-23', 'PROTHIN', 'CATHERINE', 'Mozarella', null, null, 'a_traiter'),
('e0e364eb-a493-5d67-9ac8-1cb72d94b2a1', 'remise_detail', '2db8cc91-675b-5a4a-b7f8-0f712889fe3a', 'Reservation_Chaton:13/06/2026|17:16:0', 'reservation', 'chaton', '2026-06-13', 'BAR', 'ANNABELLE', 'Moon', null, null, 'a_traiter'),
('8f6ba184-8572-5d6a-85cc-901977a3de9c', 'remise_detail', 'cf1c3aec-68f0-5956-abf0-982c16202d4c', 'Reservation_Chaton:11/06/2026|17:51:0', 'reservation', 'chaton', '2026-06-11', 'SAIRE', 'CORINNE', 'Yumi', null, null, 'a_traiter'),
('32695b93-4514-5219-ba8c-757cc1e3e663', 'remise_detail', '02161b6f-da4d-5e16-9514-9b413bee1702', 'Reservation_Chaton:09/06/2026|18:22:0', 'reservation', 'chaton', '2026-06-09', 'PELLICORO', 'JEANNE', 'Sushi', null, null, 'a_traiter'),
('8016df3e-21e7-525a-ad21-d6b8d6cbd649', 'remise_detail', '36f3c07c-33e2-598b-a1e0-4355f029aa23', 'Reservation_Chaton:06/06/2026|18:30:0', 'reservation', 'chaton', '2026-06-06', 'CARREYVE', 'ESTELLE', 'Nougat', null, null, 'a_traiter'),
('ec724e26-91e7-5114-a40c-d9cfc92970ce', 'remise_detail', '3a5ff6dc-e91d-555e-8102-ab6c9a6c1e26', 'Reservation_Chaton:05/06/2026|17:58:0', 'reservation', 'chaton', '2026-06-05', 'TAILLARD', 'KARINE', 'Fendi', null, null, 'a_traiter'),
('e9b400a6-257f-5ac5-b2f9-7fe4e90316c4', 'remise_detail', '75342aea-f652-50dc-abb8-7a1d0203d4b3', 'Reservation_Chaton:05/06/2026|17:41:0', 'reservation', 'chaton', '2026-06-05', 'ZIMMERMANN', 'LEA', 'Gris foncé poils long', null, null, 'a_traiter'),
('baed8996-8970-5f1d-9412-95c40e4b6dc8', 'remise_detail', '5442e145-1c64-5dcb-9401-22cc0608e1de', 'Adoption:27/06/2026|10:16:1', 'adoption', null, '2026-06-27', 'JANVIER', 'ANAÏS', 'Noodle', null, null, 'a_traiter'),
('9e98f6ff-3c80-5345-b89d-40aaab621508', 'remise_detail', '13013224-cbe1-5870-9617-68acfacad5ac', 'Adoption:26/06/2026|12:16:1', 'adoption', null, '2026-06-26', 'HUGUEL', 'OLIVIA', 'Minimiss', null, null, 'a_traiter'),
('3d53d404-135b-5fe0-b745-5ccac9c0747d', 'remise_detail', 'fe8820c8-ccfc-5550-a415-ac56c1096c86', 'Reservation_Chaton:13/06/2026|18:41:0', 'reservation', 'chaton', '2026-06-13', 'ORTEGA', 'NADEGE', 'Noir et blanc', null, null, 'a_traiter'),
('f2be3502-eb8e-5cff-9624-2d0f24059b44', 'remise_detail', '44966e2f-11a5-5f15-b484-fe4c6300242b', 'Adoption:09/07/2026|18:27:0', 'adoption', null, '2026-07-09', 'BOUILLON', 'SARAH', 'Praline', null, null, 'a_traiter'),
('0f351d1f-45a9-5da0-ba99-4b92f92e52a6', 'remise_detail', 'e9cc3d6e-6232-5ee5-879e-49dfded162cd', 'Adoption:29/06/2026|17:48:0', 'adoption', null, '2026-06-29', 'PEDRETTI', 'ALEXANDRE', 'Joy', null, null, 'a_traiter'),
('0c38fd4a-e5c8-5a77-9474-3f625851e4cf', 'remise_detail', '0117dfac-cd96-5aa2-972b-8f8524879bf5', 'Adoption:09/07/2026|20:16:1', 'adoption', null, '2026-07-09', 'TAILLARD', 'KARINE', 'Fendi', null, null, 'a_traiter'),
('bd9e75bc-f6b1-5f33-9179-b95bb87f1252', 'remise_detail', '85ec28cc-28b4-549d-b777-ac2543cd58fc', 'Adoption:03/07/2026|19:05:1', 'adoption', null, '2026-07-03', 'PERREZ', 'CÉCILE', 'Fripon', null, null, 'a_traiter'),
('580c0920-51bd-599b-b00f-d05c4e9d1b08', 'remise_detail', '40a1d367-ddb7-533b-8fd9-42f4decdabfa', 'Adoption:28/06/2026|18:50:1', 'adoption', null, '2026-06-28', 'CARREYVE', 'ESTELLE', 'Mikado', null, null, 'a_traiter'),
('b6f3606b-b89c-5a66-895d-cba42dae18a8', 'remise_detail', 'ae603559-1241-5670-a990-51507b61268f', 'Adoption:30/06/2026|20:35:1', 'adoption', null, '2026-06-30', 'JARDOT', 'PATRICIA', 'Scarlett', null, null, 'a_traiter'),
('f0a7c21e-1dc0-56ba-964d-dfd7f7213f73', 'remise_detail', '8bf27a31-6913-5157-a836-2cce1c3c1e57', 'Adoption:05/07/2026|18:26:1', 'adoption', null, '2026-07-05', 'JACOULOT', 'CANDICE', 'Curly', null, null, 'a_traiter'),
('f42ddcbd-e936-5473-b4e2-908e97516279', 'remise_detail', '1ffeede2-f204-5b62-813a-039dd31f65a0', 'Dons:05/07/2026|12:00:0', 'don', null, null, 'JACOULOT', 'CANDICE', null, null, null, 'a_traiter'),
('8d5068cd-b0ae-54b6-a8b3-4b733c57aadb', 'remise_detail', 'd30fb01e-c9fb-5ce0-9ce3-790f23923578', 'Adoption:07/07/2026|18:48:1', 'adoption', null, '2026-07-07', 'ZIMMERMANN', 'LEA', 'Barnabé', null, null, 'a_traiter'),
('aa376a75-d6f8-56a6-94bf-73ed6ff5c798', 'remise_detail', 'd4da7208-f74a-5005-a1b0-49525e4080a2', 'Adoption:15/07/2026|18:14:1', 'adoption', null, '2026-07-15', 'BAR', 'ANNABELLE', 'Moon', null, null, 'a_traiter'),
('305ecf42-c50c-57a6-af82-e749838a42aa', 'remise_detail', 'bdd1df3d-2e47-59a0-989d-6e50477b888e', 'Dons:15/08/2026|14:36:0', 'don', null, null, 'AMET', 'ARIANE', null, null, null, 'a_traiter'),
('e27c128b-0487-593c-9b8b-f834ca364f41', 'remise_detail', '370bc849-85e9-5f98-a663-3cede67f42c6', 'Adoption:17/07/2026|21:09:1', 'adoption', null, '2026-07-17', 'ROGER', 'NOÉMIE', 'Mojito', null, null, 'a_traiter'),
('8270e2e4-cf7f-5258-b41d-b63b90c18a13', 'remise_detail', '49b5a201-a6ae-52f2-9190-60bfb8a5c2e2', 'Reservation_Chaton:23/06/2026|10:14:0', 'reservation', 'chaton', '2026-06-23', 'PROTHIN', 'CATHERINE', 'Mozarella', null, null, 'a_traiter'),
('19672983-66e5-5262-a15d-d6f3d6641b76', 'remise_detail', 'b8aa7103-a780-5918-ac6d-ecea4a7a0b4f', 'Reservation_Chaton:24/06/2026|17:49:0', 'reservation', 'chaton', '2026-06-24', 'JOHANNA', 'FURLING', 'Filou', null, null, 'a_traiter'),
('7f27c507-e9ee-5059-92d4-7b0744030258', 'remise_detail', 'dceb48f2-3c29-5b42-a6f6-9bb11a4e4844', 'Reservation_Chaton:16/06/2026|19:35:0', 'reservation', 'chaton', '2026-06-16', 'BERGEON', 'DAVID', 'Bagheraa', null, null, 'a_traiter'),
('8fa1b24f-06c1-5d89-942a-23f2799a5233', 'remise_detail', '9528a42d-fbad-58dd-bf12-de9c80572d1b', 'Reservation_Chaton:28/05/2026|19:08:0', 'reservation', 'chaton', '2026-05-28', 'BLIN', 'CAROLE', 'Perle', null, null, 'a_traiter'),
('cbcb5d74-b991-553f-b38f-3a9e3c71bef6', 'remise_detail', '4ca988f9-1b3b-5639-ba68-e63a23089b7e', 'Adoption:03/09/2026|17:50:0', 'adoption', null, '2026-09-03', 'DREZET', 'AURÉLIE', 'Bounti', null, null, 'a_traiter')
on conflict (id) do nothing;

insert into liens_suivi_historiques (id, source, source_id, ancien_ref, suivi_type, sous_type, date_suivi, nom, prenom, animal, recu_fiscal, montant_lien, statut) values
('520e9d09-13e5-57f2-bab4-7b0aa9851103', 'remise_detail', '3c3f5708-cd38-500a-85f9-859d6f82d582', 'Reservation_Chaton:07/08/2026|17:57:0', 'reservation', 'chaton', '2026-08-07', 'DREZET', 'JADE', 'Bounti', null, null, 'a_traiter'),
('00f235d3-3d92-521e-8462-efa2a75fc8ac', 'remise_detail', 'e3f006bd-06c1-5f88-ba78-93afd565fe7b', 'Reservation_Chaton:09/07/2026|18:56:0', 'reservation', 'chaton', '2026-07-09', 'VERNIER', 'JUSTINE', 'Gray', null, null, 'a_traiter'),
('e1e14c05-2491-56e4-b894-350e1a5844d9', 'remise_detail', '40ac5790-587b-5aa7-b568-f4843ba7b8e6', 'Adoption:27/08/2026|09:58:0', 'adoption', null, '2026-08-27', 'LEOPOLD', 'CATHERINE', 'Azrael', null, null, 'a_traiter'),
('b15f18f1-9ec9-5f8a-9d69-6c291b5cecf5', 'remise_detail', '670b2f10-d716-5d1b-9718-d22d3231ec72', 'Contrat_reservation_chat:20/08/2026|10:25:0', 'reservation', 'chat', '2026-08-20', 'LEOPOLD', 'CATHERINE', 'Azrael', null, null, 'a_traiter'),
('cf3d938a-1d1c-5f97-8e6c-b0008fba1640', 'remise_detail', '7e7fac03-30fd-5c9a-b65b-a1c6de6a24d3', 'Contrat_reservation_chat:14/08/2026|18:14:0', 'reservation', 'chat', '2026-08-14', 'MAHOUACHI', 'NESRINE', 'Figaro', null, null, 'a_traiter'),
('c75486ea-6ec3-5833-9056-21170bf466bd', 'remise_detail', '24322e07-c5f1-578d-9238-bdad75bf27b5', 'Dons:24/08/2026|17:37:0', 'don', null, null, 'HILDENBRAND', 'SANDY', null, null, null, 'a_traiter'),
('b1f3f5a6-0e70-5237-8871-5e44ebebffa0', 'remise_detail', 'cab92812-c571-5be9-94ff-5d780040a09f', 'Reservation_Chaton:19/07/2026|19:15:0', 'reservation', 'chaton', '2026-07-19', 'KIMMICH', 'RONAN', 'Styx', null, null, 'a_traiter'),
('652eec48-2e0c-5aba-9ce7-6357368b5003', 'remise_detail', '32a51b83-69a6-537d-b351-d79cf6faf850', 'Dons:05/09/2026|15:36:0', 'don', null, null, 'KALBE', 'J.LUC', null, null, null, 'a_traiter'),
('9f42716d-21a1-55e2-83d5-403cdc3a6eea', 'remise_detail', '6aece432-e75a-56fa-b905-8065e5ef3f5a', 'Dons:05/09/2026|15:34:0', 'don', null, null, 'FRELIN', 'LAETITIA', null, null, null, 'a_traiter'),
('6522972d-52d6-5ef7-b52f-093f59aae224', 'remise_detail', 'ea63af87-0e60-5a94-9a1d-7816e73b63d2', 'Dons:24/08/2026|13:15:0', 'don', null, null, 'BOUQUET', 'PATRICK', null, null, null, 'a_traiter'),
('53419dbc-95af-5941-98a7-4e37c60d7d1a', 'remise_detail', '8509918a-5583-5b0f-84e7-54e6261ece9b', 'Dons:05/09/2026|14:46:0', 'don', null, null, 'GRANDVOINET', 'MARYLENE', null, null, null, 'a_traiter'),
('98a62d93-a2f5-59a7-9267-bfa156b9172b', 'remise_detail', '3b2690cc-3db6-535a-9df6-9d7fd29357e6', 'Dons:05/09/2026|14:55:0', 'don', null, null, 'MUCK', 'SOLANGE', null, null, null, 'a_traiter'),
('64e125a4-cc4a-5350-b8aa-064422951c28', 'remise_detail', 'fc8652d7-5265-5f68-9179-0855e54a5e7c', 'Adoption:10/10/2026|09:33:0', 'adoption', null, '2026-10-10', 'CHIAPPINI', 'SANDRINE', 'Juju', null, null, 'a_traiter'),
('80a2ca92-61ca-5ba6-a762-3166a074f6a2', 'remise_detail', '99e37eef-e7fd-56d0-9a4b-5188830a7571', 'Reservation_Chaton:03/10/2026|18:32:0', 'reservation', 'chaton', '2026-10-03', 'LAMBERT', 'ALINE', 'Lupine', null, null, 'a_traiter'),
('efdfc8b1-04c2-5018-aa54-945169aa6091', 'remise_detail', '94d23001-6b6f-59c7-8bda-5675cdad284f', 'Dons:10/10/2026|19:27:0', 'don', null, null, 'MARTINET', 'SYLVIE', null, null, null, 'a_traiter'),
('af2d3b5b-17a0-562f-96d1-e5233f9288c1', 'remise_detail', '08c511bd-1de5-5db2-adda-4ddbd5ed1d77', 'Dons:12/09/2026|18:08:0', 'don', null, null, 'CLOG', 'DAVID', null, null, null, 'a_traiter'),
('75efd2e0-386c-5d9e-96d5-05d6886d2d31', 'remise_detail', 'e997382b-c430-5664-8b85-7a8b642b0b68', 'Dons:10/10/2026|20:03:0', 'don', null, null, null, 'ASSOCIATION DÉFI BONHEUR', null, null, null, 'a_traiter'),
('e9e6edff-d996-54ad-91a7-0398f5fbc62e', 'remise_detail', 'e0719dc8-a402-58cc-ab79-d777934c5bf7', 'Adoption:10/10/2026|09:44:0', 'adoption', null, '2026-10-10', 'CHIAPPINI', 'SANDRINE', 'Simba', null, null, 'a_traiter'),
('fc782e13-682c-595e-8c1d-c4ac4d452657', 'remise_detail', '2156e20a-31a9-507d-8f08-5f419853d20c', 'Dons:22/10/2026|21:51:0', 'don', null, null, 'VERITTI', 'MARYLENE', null, null, null, 'a_traiter'),
('2a90a176-7006-5d11-bc7e-118c6c679fef', 'remise_detail', 'f221b639-19b5-51c3-b419-2d832496d6d8', 'Reservation_Chaton:15/10/2026|19:46:0', 'reservation', 'chaton', '2026-10-15', 'BURRIER', 'CLAIRE', 'Sonic', null, null, 'a_traiter'),
('b8274543-d667-5ced-96f3-07f6657d42d6', 'remise_detail', 'dbe5af51-5e84-5863-9792-b0d72cc4a94b', 'Dons:20/10/2026|18:19:0', 'don', null, null, 'VILMINOT', 'MARIE DELLE', null, null, null, 'a_traiter'),
('004df9c4-9df7-54a0-87a4-f596d5412ed7', 'remise_detail', '5825b727-8d7b-5b83-8117-5201e00df927', 'Adoption:10/10/2026|17:52:0', 'adoption', null, '2026-10-10', 'LAMBERT', 'ALINE', 'Lupine', null, null, 'a_traiter')
on conflict (id) do nothing;


-- ---------- Normalisation des noms (sans accents, minuscules, lettres/chiffres seulement) ----------
create or replace function norm_txt(t text) returns text
language sql immutable as $$
    select regexp_replace(lower(translate(coalesce(t, ''), 'àâäãçéèêëîïôöõùûüÿñÀÂÄÃÇÉÈÊËÎÏÔÖÕÙÛÜŸÑ', 'aaaaceeeeiiooouuuynaaaaceeeeiiooouuuyn')), '[^a-z0-9]', '', 'g')
$$;

-- ---------- Recherche des enregistrements Suivi correspondant à une ancienne référence ----------
-- p_passe : 0 = n° de reçu fiscal (dons) ; 1 = date + nom + prénom ; 2 = date + nom ;
--           3 = date à +/- 3 jours + nom + prénom ; 4 = sans date : nom + prénom + nom de l'animal (adoption / réservation).
create or replace function candidats_suivi(
    p_type text, p_sous text, p_date date, p_nom text, p_prenom text, p_animal text, p_recu text, p_passe int)
returns uuid[]
language plpgsql stable set search_path = public as $$
declare
    v_ids   uuid[];
    v_nom   text := norm_txt(p_nom);
    v_pre   text := norm_txt(p_prenom);
    v_ani   text := norm_txt(p_animal);
    v_d1    date;
    v_d2    date;
    v_aff   uuid[];
begin
    if p_passe = 0 then
        if p_type = 'don' and p_recu is not null then
            select array_agg(id) into v_ids from dons where numero_recu_fiscal = p_recu;
        end if;
        return coalesce(v_ids, '{}');
    end if;
    if v_nom = '' or (p_date is null and p_passe <> 4) then return '{}'; end if;
    if p_passe = 4 then
        if p_type not in ('adoption', 'reservation') or v_ani = '' then return '{}'; end if;
        v_d1 := date '1900-01-01'; v_d2 := date '2999-12-31';
    elsif p_passe = 3 then v_d1 := p_date - 3; v_d2 := p_date + 3;
    else v_d1 := p_date; v_d2 := p_date; end if;

    if p_type = 'adoption' then
        select array_agg(a.id) into v_ids from adoptions a join personnes p on p.id = a.personne_id
        where a.date_adoption between v_d1 and v_d2 and norm_txt(p.nom) = v_nom
          and (p_passe = 2 or v_pre = '' or norm_txt(p.prenom) = v_pre or norm_txt(p.prenom) like v_pre || '%' or v_pre like norm_txt(p.prenom) || '%');
        if (array_length(v_ids, 1) > 1 or p_passe = 4) and v_ani <> '' then
            select array_agg(a.id) into v_aff from adoptions a join animaux an on an.id = a.animal_id
            where a.id = any(v_ids) and (norm_txt(an.nom_usuel) = v_ani or norm_txt(an.nom_adoption) = v_ani);
            if array_length(v_aff, 1) = 1 or p_passe = 4 then v_ids := v_aff; end if;
        end if;
    elsif p_type = 'reservation' then
        select array_agg(r.id) into v_ids from reservations r join personnes p on p.id = r.personne_id
        where r.date_reservation between v_d1 and v_d2 and norm_txt(p.nom) = v_nom
          and (p_sous is null or r.type_reservation = p_sous)
          and (p_passe = 2 or v_pre = '' or norm_txt(p.prenom) = v_pre or norm_txt(p.prenom) like v_pre || '%' or v_pre like norm_txt(p.prenom) || '%');
        if (array_length(v_ids, 1) > 1 or p_passe = 4) and v_ani <> '' then
            select array_agg(r.id) into v_aff from reservations r join animaux an on an.id = r.animal_id
            where r.id = any(v_ids) and (norm_txt(an.nom_usuel) = v_ani or norm_txt(an.nom_adoption) = v_ani);
            if array_length(v_aff, 1) = 1 or p_passe = 4 then v_ids := v_aff; end if;
        end if;
    elsif p_type = 'adhesion' then
        select array_agg(a.id) into v_ids from adhesions a join personnes p on p.id = a.personne_id
        where a.date_adhesion between v_d1 and v_d2 and norm_txt(p.nom) = v_nom
          and (p_passe = 2 or v_pre = '' or norm_txt(p.prenom) = v_pre or norm_txt(p.prenom) like v_pre || '%' or v_pre like norm_txt(p.prenom) || '%');
    elsif p_type = 'don' then
        select array_agg(d.id) into v_ids from dons d join personnes p on p.id = d.personne_id
        where d.date_signature between v_d1 and v_d2 and (norm_txt(p.nom) = v_nom or norm_txt(p.raison_sociale) = v_nom)
          and (p_passe = 2 or v_pre = '' or norm_txt(p.prenom) = v_pre or norm_txt(p.prenom) like v_pre || '%' or v_pre like norm_txt(p.prenom) || '%' or norm_txt(p.raison_sociale) = v_nom);
    elsif p_type = 'materiel_mouvement' then
        select array_agg(m.id) into v_ids from materiel_mouvements m join personnes p on p.id = m.personne_id
        where m.type_mouvement = 'pret' and m.date_mouvement between v_d1 and v_d2 and norm_txt(p.nom) = v_nom
          and (p_passe = 2 or v_pre = '' or norm_txt(p.prenom) = v_pre or norm_txt(p.prenom) like v_pre || '%' or v_pre like norm_txt(p.prenom) || '%');
    end if;
    return coalesce(v_ids, '{}');
end;
$$;

-- ---------- Reconstitution des liens ----------
create or replace function reconstituer_liens_suivi()
returns table (resultat text, nombre bigint)
language plpgsql security definer set search_path = public as $$
declare
    r        record;
    v_ids    uuid[];
    v_cible  uuid;
    v_col    text;
    v_tbl    text;
    v_mvtcol text;
    v_mvttbl text;
    v_mvt    numeric;
    v_nb     int;
    v_passe  int;
    v_mont   numeric;
begin
    if auth.uid() is not null and role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;

    for r in select * from liens_suivi_historiques where liens_suivi_historiques.statut <> 'lie' order by liens_suivi_historiques.id loop
        v_col := case r.suivi_type when 'adhesion' then 'adhesion_id' when 'don' then 'don_id' when 'adoption' then 'adoption_id'
                                   when 'reservation' then 'reservation_id' when 'materiel_mouvement' then 'materiel_mouvement_id' end;
        if v_col is null then
            update liens_suivi_historiques set statut = 'introuvable', note = 'référence d''origine non identifiée', traite_le = now() where id = r.id;
            continue;
        end if;

        v_ids := '{}';
        for v_passe in 0..4 loop
            v_ids := candidats_suivi(r.suivi_type, r.sous_type, r.date_suivi, r.nom, r.prenom, r.animal, r.recu_fiscal, v_passe);
            exit when coalesce(array_length(v_ids, 1), 0) > 0;
        end loop;

        if coalesce(array_length(v_ids, 1), 0) = 0 then
            update liens_suivi_historiques set statut = 'introuvable', traite_le = now(),
                   note = 'aucun enregistrement Suivi correspondant (Suivi pas encore importé ?)' where id = r.id;
            continue;
        elsif array_length(v_ids, 1) > 1 then
            update liens_suivi_historiques set statut = 'ambigu', traite_le = now(),
                   note = array_length(v_ids, 1) || ' enregistrements possibles : à lier à la main' where id = r.id;
            continue;
        end if;
        v_cible := v_ids[1];

        if r.source in ('banque', 'caisse') then
            v_mvttbl := r.source || '_mouvements';
            v_tbl    := r.source || '_mouvement_suivi_liens';
            v_mvtcol := r.source || '_mouvement_id';
            execute format('select coalesce(nullif(credit, 0), debit) from %I where id = $1', v_mvttbl) into v_mvt using r.source_id;
            get diagnostics v_nb = row_count;
            if v_nb = 0 then
                update liens_suivi_historiques set statut = 'introuvable', traite_le = now(), note = 'ligne de compta introuvable' where id = r.id;
                continue;
            end if;
            select count(*) into v_nb from liens_suivi_historiques h where h.source = r.source and h.source_id = r.source_id;
            v_mont := coalesce(r.montant_lien, round(v_mvt / greatest(v_nb, 1), 2));
            execute format('insert into %I (%I, %I, montant) select $1, $2, $3 where not exists (select 1 from %I where %I = $1 and %I = $2)',
                           v_tbl, v_mvtcol, v_col, v_tbl, v_mvtcol, v_col) using r.source_id, v_cible, v_mont;
            execute format('update %I set suivi_ref = ''oui'' where id = $1', v_mvttbl) using r.source_id;
        else
            execute format('update remise_cheques_details set %I = $1 where id = $2', v_col) using v_cible, r.source_id;
            get diagnostics v_nb = row_count;
            if v_nb = 0 then
                update liens_suivi_historiques set statut = 'introuvable', traite_le = now(), note = 'chèque de remise introuvable' where id = r.id;
                continue;
            end if;
        end if;

        update liens_suivi_historiques set statut = 'lie', cible_id = v_cible, note = null, traite_le = now() where id = r.id;
    end loop;

    return query select h.statut, count(*) from liens_suivi_historiques h group by h.statut order by h.statut;
end;
$$;

-- ---------- Cas restants à traiter à la main ----------
create or replace view v_liens_suivi_a_verifier with (security_invoker = true) as
select h.statut, h.source, h.ancien_ref, h.suivi_type, h.date_suivi, h.nom, h.prenom, h.animal, h.montant_lien, h.note, h.id
from liens_suivi_historiques h
where h.statut <> 'lie'
order by h.statut, h.date_suivi, h.nom;

-- ---------- Contrôle : 57 lignes de banque, 90 de caisse, 75 chèques de remise (222 références) ----------
select source, count(*) as references_conservees from liens_suivi_historiques group by source order by source;
