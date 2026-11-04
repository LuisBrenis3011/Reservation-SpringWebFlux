DROP TABLE IF EXISTS customer_role;
DROP TABLE IF EXISTS customer;
DROP TABLE IF EXISTS role;

CREATE TABLE role (
                      name VARCHAR(50) PRIMARY KEY,
                      description TEXT
);


CREATE TABLE customer (
                          id SERIAL PRIMARY KEY,
                          firstname VARCHAR(100) NOT NULL,
                          enabled BOOLEAN DEFAULT TRUE,
                          account_non_expired BOOLEAN DEFAULT TRUE,
                          credentials_non_expired BOOLEAN DEFAULT TRUE,
                          lastname VARCHAR(100) NOT NULL,
                          email VARCHAR(255) UNIQUE NOT NULL,
                          user_password VARCHAR(256) NOT NULL,
                          age INT CHECK (age >= 0),
                          birthdate DATE,
                          alternative_id UUID UNIQUE
);


CREATE TABLE customer_role (
                               customer_id INT REFERENCES customer(id) ON DELETE CASCADE,
                               role_name VARCHAR(50) REFERENCES role(name) ON DELETE CASCADE,
                               PRIMARY KEY (customer_id, role_name)
);
