
-- create user
CREATE USER :username WITH ENCRYPTED PASSWORD :'password';

-- allow basic CRUD access to data + sequences
REVOKE ALL PRIVILEGES ON DATABASE :database_name FROM :username;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :username;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO :username;

-- verify that the user got created
SELECT rolname FROM pg_roles;
