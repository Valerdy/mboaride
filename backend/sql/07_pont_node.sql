-- ---------------------------------------------------------------------
-- Pont avec l'API Node, qui porte l'authentification (US01)
-- ---------------------------------------------------------------------
-- Les deux services partagent la même base PostgreSQL : l'API Node y tient sa table
-- `users`, l'API Python sa table `utilisateur`. Cette table dit quel compte Node
-- correspond à quel utilisateur métier, pour qu'un jeton émis par Node désigne sans
-- ambiguïté la bonne personne ici. Le rapprochement se fait sur l'e-mail ou le
-- téléphone à la première requête authentifiée, puis il est gardé.

SET search_path TO mboaride;

CREATE TABLE IF NOT EXISTS compte_node (
    id_compte_node  INTEGER      PRIMARY KEY,                -- users.id de l'API Node
    id_utilisateur  INTEGER      NOT NULL UNIQUE REFERENCES utilisateur ON DELETE CASCADE,
    lie_le          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    lie_par         VARCHAR(16)  NOT NULL DEFAULT 'email'
        CHECK (lie_par IN ('email', 'telephone', 'creation', 'manuel'))
);

COMMENT ON TABLE compte_node IS
    'Correspondance entre un compte de l''API Node (authentification) et un utilisateur métier.';
