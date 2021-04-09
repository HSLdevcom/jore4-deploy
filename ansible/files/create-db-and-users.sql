-- database setup
CREATE DATABASE :database_name;
SELECT datname FROM pg_database;

-- HASURA: allow basic CRUD access to data + sequences
CREATE USER :hasura_username WITH ENCRYPTED PASSWORD :'hasura_password';

REVOKE ALL PRIVILEGES ON DATABASE :database_name FROM :hasura_username;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :hasura_username;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO :hasura_username;

-- JORE3 IMPORTER: allow basic CRUD access to data + sequences
CREATE USER :jore3importer_username WITH ENCRYPTED PASSWORD :'jore3importer_password';

REVOKE ALL PRIVILEGES ON DATABASE :database_name FROM :jore3importer_username;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :jore3importer_username;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO :jore3importer_username;

SELECT rolname FROM pg_roles;
