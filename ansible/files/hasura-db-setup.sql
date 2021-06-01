CREATE SCHEMA IF NOT EXISTS postgis;
CREATE SCHEMA IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA pgcrypto;
CREATE SCHEMA IF NOT EXISTS infrastructure_network;

-- hasura needs pgcrypto in search_path https://hasura.io/docs/latest/graphql/core/deployment/postgres-requirements.html#pgcrypto-in-pg-search-path
-- add also postgis on search_path so that we can use it directly in migrations (`gen_random_uuid()` vs. `pgcrypto.gen_random_uuid()`)
-- this doesn't seem to affect current session
DO $$
BEGIN
  EXECUTE 'ALTER ROLE dbhasuraplayg SET search_path = postgis, pgcrypto';
END
$$;

-- update search path also for current session
SELECT set_config('search_path', 'postgis, pgcrypto,' || current_setting('search_path'), false);

-- create the schemas required by the hasura system
-- NOTE: If you are starting from scratch: drop the below schemas first, if they exist.
CREATE SCHEMA IF NOT EXISTS hdb_catalog;

-- making sure that the current admin user will still have ownership transitively to the hdb_catalog
-- even after the owner change
GRANT dbhasuraplayg TO dbadminplayg;

-- grant hasura access to pgcrypto and postgis extensions
GRANT USAGE ON SCHEMA postgis TO dbhasuraplayg;
GRANT USAGE ON SCHEMA pgcrypto TO dbhasuraplayg;

-- make the user an owner of system schemas
ALTER SCHEMA hdb_catalog OWNER TO dbhasuraplayg;
