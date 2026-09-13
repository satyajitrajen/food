-- Extra database for running the server locally; integration tests use the
-- POSTGRES_DB (foodpos_test) created automatically from the compose env.
CREATE DATABASE foodpos OWNER foodpos;
