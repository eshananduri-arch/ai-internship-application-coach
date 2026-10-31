-- Run once as the administrator of the intended development PostgreSQL database.
-- Requires the pgvector extension to be available on the database host.
-- This script creates knowledge storage only. It does not create private user tables,
-- insert sample documents, create passwords, drop tables, or delete existing data.

BEGIN;
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS public.internship_role_chunks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    text text NOT NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    embedding vector(3072) NOT NULL
);

CREATE INDEX IF NOT EXISTS internship_role_chunks_metadata_idx
    ON public.internship_role_chunks USING gin (metadata);

COMMENT ON TABLE public.internship_role_chunks IS
    'Shared internship role knowledge only. Never store resumes or private letters here.';
COMMIT;

-- The future loader must write one role per chunk with metadata such as:
-- {"dataset":"internship_roles","role_id":"NVIDIA-01","company":"NVIDIA",
--  "source_title":"NVIDIA Internship Roles","source_version":"1"}
-- It must embed text with models/gemini-embedding-001 at the same 3072 dimensions.
-- Do not mix embedding models, dimensions, or obsolete versions in this table.
-- The small initial catalog does not require an approximate vector index.

-- Have the administrator create a dedicated credential through the provider's
-- secure UI. Do not put its password in this file or Git.
-- Suggested permissions for an EXISTING runtime role named internship_mcp_reader:
-- GRANT CONNECT ON DATABASE your_database TO internship_mcp_reader;
-- GRANT USAGE ON SCHEMA public TO internship_mcp_reader;
-- GRANT SELECT ON public.internship_role_chunks TO internship_mcp_reader;
-- Do not grant that credential access to private application tables.
-- The future knowledge loader requires a separate narrowly scoped write credential.
-- Validate the reader credential with the actual n8n PGVector initialization;
-- provision the extension/table as administrator rather than using an admin runtime key.

-- Inspect setup (no real documents are added by this script):
SELECT extname FROM pg_extension WHERE extname = 'vector';
SELECT count(*) AS indexed_chunks FROM public.internship_role_chunks;
