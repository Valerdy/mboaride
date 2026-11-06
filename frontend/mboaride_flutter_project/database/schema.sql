-- Création du schéma de la base de données PostgreSQL / MySQL pour MBOARIDE

CREATE TABLE IF NOT EXISTS companies (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email_domain VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(50) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    role VARCHAR(50) DEFAULT 'passager', -- 'passager', 'conducteur', 'les_deux'
    is_verified BOOLEAN DEFAULT FALSE,
    avatar_url TEXT,
    company_id INT REFERENCES companies(id) ON DELETE SET NULL,
    vehicle_brand_model VARCHAR(255),
    vehicle_plate VARCHAR(50),
    available_seats INT DEFAULT 0,
    position_sharing_accepted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS otp_codes (
    id SERIAL PRIMARY KEY,
    identifier VARCHAR(255) NOT NULL,
    code VARCHAR(10) NOT NULL,
    attempts INT DEFAULT 0,
    expires_at BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(512) UNIQUE NOT NULL,
    is_revoked BOOLEAN DEFAULT FALSE,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insertion de données de test (Entreprises partenaires)
INSERT INTO companies (name, email_domain) 
VALUES ('Entreprise Test', 'entreprise.cm')
ON CONFLICT (email_domain) DO NOTHING;
