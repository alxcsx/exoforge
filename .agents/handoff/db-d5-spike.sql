-- Throwaway, run as a CREATEROLE non-superuser "exo_app" owning database exo2 on a scratch cluster. See db-d5-spike.md.
REVOKE CREATE ON DATABASE exo2 FROM PUBLIC;
CREATE ROLE ext_items LOGIN PASSWORD 'pi'; CREATE ROLE ext_store LOGIN PASSWORD 'ps'; CREATE ROLE ext_other LOGIN PASSWORD 'po';
GRANT ext_items TO exo_app WITH SET TRUE, INHERIT FALSE; GRANT ext_store TO exo_app WITH SET TRUE, INHERIT FALSE; GRANT ext_other TO exo_app WITH SET TRUE, INHERIT FALSE;
CREATE SCHEMA plugin_items AUTHORIZATION ext_items; CREATE SCHEMA plugin_store AUTHORIZATION ext_store; CREATE SCHEMA plugin_other AUTHORIZATION ext_other;
SET ROLE ext_items;
CREATE TABLE plugin_items.itens (id text primary key, data jsonb);
GRANT USAGE ON SCHEMA plugin_items TO ext_store;
GRANT SELECT ON ALL TABLES IN SCHEMA plugin_items TO ext_store;
ALTER DEFAULT PRIVILEGES FOR ROLE ext_items IN SCHEMA plugin_items GRANT SELECT ON TABLES TO ext_store;
RESET ROLE;
-- teardown of reader ext_store
SET ROLE ext_items;
REVOKE ALL ON ALL TABLES IN SCHEMA plugin_items FROM ext_store;
REVOKE USAGE ON SCHEMA plugin_items FROM ext_store;
ALTER DEFAULT PRIVILEGES FOR ROLE ext_items IN SCHEMA plugin_items REVOKE SELECT ON TABLES FROM ext_store;
RESET ROLE;
SET ROLE ext_store; DROP OWNED BY ext_store; RESET ROLE; DROP ROLE ext_store;
