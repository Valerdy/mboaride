-- =====================================================================
-- MboaRide · Données d'exemple (fictives) pour la démonstration
-- Personnes, organisations et numéros sont inventés.
-- =====================================================================
SET search_path TO mboaride;

INSERT INTO organisation (nom, type_organisation, domaine_email, code_invitation, abonnement_actif, tarif_mensuel_fcfa) VALUES
  ('Entreprise A (Bonanjo)', 'entreprise',             'entreprise-a.cm', 'ENTA-2026', TRUE,  1500),
  ('Entreprise B (Akwa)',    'entreprise',             'entreprise-b.cm', 'ENTB-2026', TRUE,  1500),
  ('Collège B (Bonapriso)',  'etablissement_scolaire', NULL,              'COLB-2026', FALSE, 0),
  ('Campus C',               'campus',                 'campus-c.cm',     'CAMC-2026', TRUE,  0);

INSERT INTO partenariat (id_organisation_a, id_organisation_b) VALUES (1, 2);

INSERT INTO utilisateur (nom, prenom, telephone, email, mot_de_passe_hache, est_conducteur, statut_agrement, date_agrement,
                         mode_reservation, priorite, accepte_partenaires, accepte_public, souhaite_clim, consentement_position) VALUES
  ('Essomba', 'Armand',  '+237600000001', 'armand@entreprise-a.cm', '$2b$12$exemple', TRUE,  'actif',           '2026-10-01', 'autonome', 'heure', TRUE,  FALSE, TRUE,  TRUE),
  ('Mbarga',  'Grâce',   '+237600000002', 'grace@entreprise-a.cm',  '$2b$12$exemple', FALSE, 'non_demande',     NULL,         'manuel',   'heure', TRUE,  FALSE, TRUE,  TRUE),
  ('Fotso',   'Mireille','+237600000003', NULL,                     '$2b$12$exemple', FALSE, 'non_demande',     NULL,         'autonome', 'heure', TRUE,  TRUE,  FALSE, TRUE),
  ('Kamga',   'Serge',   '+237600000004', NULL,                     '$2b$12$exemple', TRUE,  'actif',           '2026-09-15', 'manuel',   'prix',  TRUE,  TRUE,  FALSE, TRUE),
  ('Tchinda', 'Nadège',  '+237600000005', 'nadege@campus-c.cm',     '$2b$12$exemple', FALSE, 'non_demande',     NULL,         'manuel',   'prix',  TRUE,  TRUE,  FALSE, TRUE),
  ('Ndjock',  'Junior',  '+237600000006', NULL,                     '$2b$12$exemple', FALSE, 'non_demande',     NULL,         'manuel',   'prix',  TRUE,  TRUE,  FALSE, TRUE),
  ('Ewane',   'Paul',    '+237600000007', NULL,                     '$2b$12$exemple', TRUE,  'en_verification', NULL,         'manuel',   'heure', TRUE,  TRUE,  FALSE, TRUE),
  ('Onana',   'Brice',   '+237600000008', NULL,                     '$2b$12$exemple', TRUE,  'actif',           '2026-10-10', 'autonome', 'heure', TRUE,  TRUE,  TRUE,  TRUE),
  ('Ekwalla', 'Hélène',  '+237600000009', 'rh@entreprise-a.cm',     '$2b$12$exemple', FALSE, 'non_demande',     NULL,         'manuel',   'heure', TRUE,  FALSE, FALSE, FALSE);

INSERT INTO appartenance (id_utilisateur, id_organisation, role) VALUES
  (1, 1, 'membre'), (2, 1, 'membre'), (9, 1, 'administrateur'), (5, 4, 'membre');

INSERT INTO document_agrement (id_utilisateur, type_document, statut, chemin_fichier, expire_le) VALUES
  (1, 'piece_identite',    'valide', 'agrement/1/cni.pdf',     '2031-05-01'),
  (1, 'permis',            'valide', 'agrement/1/permis.pdf',  '2030-02-01'),
  (1, 'casier_judiciaire', 'valide', 'agrement/1/casier.pdf',  '2027-01-15'),
  (1, 'assurance',         'valide', 'agrement/1/assur.pdf',   '2027-06-30'),
  (7, 'piece_identite',    'depose', 'agrement/7/cni.pdf',     NULL),
  (7, 'permis',            'depose', 'agrement/7/permis.pdf',  NULL);

INSERT INTO vehicule (id_proprietaire, marque_modele, immatriculation, places_passagers, conso_l_100km, climatise, non_fumeur, accepte_bagages) VALUES
  (1, 'Berline 2012',        'LT-001-AA', 3, 8.0, TRUE,  TRUE, FALSE),
  (4, 'SUV 2016',            'CE-002-BB', 4, 7.0, TRUE,  TRUE, TRUE),
  (8, 'Citadine 2018',       'LT-003-CC', 3, 6.5, TRUE,  TRUE, FALSE),
  (7, 'Berline 2010',        'LT-004-DD', 3, 8.5, FALSE, TRUE, FALSE);

INSERT INTO compte_eleve (id_parent, id_etablissement, prenom, age_declare) VALUES
  (3, 3, 'Ange', 12),
  (3, 3, 'Marc', 15);

-- Trajets : régulier domicile-travail, voyage Douala-Yaoundé, trajet du matin vers Bonapriso
INSERT INTO trajet (id_conducteur, id_vehicule, type_trajet, depart_libelle, depart_lat, depart_lon, arrivee_libelle, arrivee_lat, arrivee_lon,
                    heure_depart, date_unique, jours_semaine, places_offertes, detour_max_km, peage_fcfa, ouvert_partenaires, ouvert_public) VALUES
  (1, 1, 'urbain',      'Logpom', 4.088000, 9.765000, 'Bonanjo',   4.042000, 9.689000, '06:50', NULL,         '1111100', 3, 2.0, 0,    TRUE, FALSE),
  (4, 2, 'interurbain', 'Akwa',   4.050000, 9.698000, 'Yaoundé',   3.866700, 11.516700, '14:00', '2026-11-20', NULL,     4, 8.0, 1000, TRUE, TRUE),
  (8, 3, 'urbain',      'Makepe', 4.081000, 9.752000, 'Bonapriso', 4.033000, 9.695000, '06:35', NULL,         '1111100', 2, 3.0, 0,    TRUE, TRUE);

INSERT INTO point_depart (id_trajet, ordre_passage, libelle, lat, lon, heure_passage) VALUES
  (2, 1, 'Akwa',    4.050000, 9.698000, '14:00'),
  (2, 2, 'Ndokoti', 4.044000, 9.737000, '14:20');

INSERT INTO demande (id_demandeur, id_eleve, id_organisation, type_trajet, depart_libelle, depart_lat, depart_lon, arrivee_libelle, arrivee_lat, arrivee_lon,
                     arrivee_au_plus_tot, arrivee_au_plus_tard, date_unique, jours_semaine, prix_max_fcfa, mode_reservation, cercle_max, statut) VALUES
  (2, NULL, 1,    'urbain',      'Kotto',  4.072000, 9.766000, 'Bonanjo',   4.042000, 9.689000, '07:30', '07:50', NULL,         '1111100', 400,  'manuel',   'partenaires', 'satisfaite'),
  (3, 1,    3,    'urbain',      'Makepe', 4.081000, 9.752000, 'Bonapriso', 4.033000, 9.695000, '06:55', '07:15', NULL,         '1111100', 400,  'autonome', 'public',      'satisfaite'),
  (3, 2,    3,    'urbain',      'Makepe', 4.081000, 9.752000, 'Bonapriso', 4.033000, 9.695000, '06:55', '07:15', NULL,         '1111100', 400,  'autonome', 'public',      'satisfaite'),
  (5, NULL, 4,    'urbain',      'Bonabéri', 4.073000, 9.657000, 'Campus C', 4.060000, 9.735000, '07:15', '07:30', NULL,       '1111100', 300,  'manuel',   'public',      'sans_equipage'),
  (6, NULL, NULL, 'interurbain', 'Ndokoti', 4.044000, 9.737000, 'Yaoundé', 3.866700, 11.516700, '17:30', '19:30', '2026-11-20', NULL,      3500, 'manuel',   'public',      'satisfaite');

INSERT INTO reservation (id_demande, id_trajet, date_trajet, heure_prise_en_charge, heure_arrivee_estimee, prix_fcfa, detour_km, niveau_cercle, score, statut) VALUES
  (1, 1, '2026-11-16', '07:02', '07:38', 175,  1.20, 'organisation', 0.8120, 'terminee'),
  (1, 1, '2026-11-17', '07:02', '07:40', 175,  1.20, 'organisation', 0.8050, 'confirmee'),
  (2, 3, '2026-11-17', '06:36', '07:05', 125,  0.30, 'public',       0.7400, 'confirmee'),
  (3, 3, '2026-11-17', '06:36', '07:05', 125,  0.30, 'public',       0.7400, 'confirmee'),
  (5, 2, '2026-11-20', '14:20', '18:40', 3200, 0.00, 'public',       0.7710, 'confirmee');

INSERT INTO paiement (id_reservation, montant_fcfa, commission_fcfa, moyen, operateur, reference_transaction, statut, paye_le) VALUES
  (1, 175,  0,   'mobile_money', 'Opérateur 1', 'MM-0001', 'reussi',     '2026-11-16 07:40+01'),
  (5, 3200, 290, 'mobile_money', 'Opérateur 2', 'MM-0002', 'en_attente', NULL);

INSERT INTO evaluation (id_reservation, id_auteur, id_evalue, note, commentaire) VALUES
  (1, 2, 1, 5, 'Ponctuel, voiture climatisée.'),
  (1, 1, 2, 5, NULL);
