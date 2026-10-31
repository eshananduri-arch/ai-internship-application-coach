-- Database v1. Apply with the migration administrator, never a browser key.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;
CREATE SCHEMA app;
REVOKE ALL ON SCHEMA app FROM PUBLIC, anon, authenticated;

DO $roles$
BEGIN
  CREATE ROLE internship_api NOLOGIN NOBYPASSRLS;
  CREATE ROLE internship_worker NOLOGIN NOBYPASSRLS;
  CREATE ROLE internship_mcp_reader NOLOGIN NOBYPASSRLS;
  CREATE ROLE internship_knowledge_writer NOLOGIN NOBYPASSRLS;
  CREATE ROLE internship_operator NOLOGIN NOBYPASSRLS;
END
$roles$;

ALTER ROLE internship_mcp_reader SET search_path = public, extensions;
ALTER ROLE internship_knowledge_writer SET search_path = public, extensions;

CREATE FUNCTION app.normalize_letter(value text) RETURNS text
LANGUAGE sql IMMUTABLE STRICT SET search_path = ''
AS $$ SELECT replace(replace(value, E'\r\n', E'\n'), E'\r', E'\n') $$;

CREATE FUNCTION app.letter_sha256(value text) RETURNS text
LANGUAGE sql IMMUTABLE STRICT SET search_path = ''
AS $$ SELECT encode(sha256(convert_to(app.normalize_letter(value), 'UTF8')), 'hex') $$;

CREATE FUNCTION app.text_sha256(value text) RETURNS text
LANGUAGE sql IMMUTABLE STRICT SET search_path = ''
AS $$ SELECT encode(sha256(convert_to(value, 'UTF8')), 'hex') $$;

CREATE FUNCTION app.current_visitor_id() RETURNS uuid
LANGUAGE sql STABLE SET search_path = ''
AS $$ SELECT nullif(current_setting('app.visitor_id', true), '')::uuid $$;

CREATE TABLE public.companies (
  company_id text PRIMARY KEY CHECK (company_id ~ '^[a-z][a-z0-9_]{1,39}$'),
  name text NOT NULL UNIQUE CHECK (char_length(name) BETWEEN 1 AND 100),
  is_fictional boolean NOT NULL DEFAULT true CHECK (is_fictional),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.internship_roles (
  role_id text PRIMARY KEY CHECK (role_id ~ '^[A-Z]+-[0-9]{2}$'),
  company_id text NOT NULL REFERENCES public.companies(company_id),
  role_title text NOT NULL,
  location text NOT NULL,
  stipend_inr_month integer NOT NULL CHECK (stipend_inr_month >= 0),
  deadline date NOT NULL,
  required_skills text[] NOT NULL,
  preferred_skills text[] NOT NULL DEFAULT '{}',
  catalog_version integer NOT NULL DEFAULT 1 CHECK (catalog_version >= 1),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (role_id, company_id)
);
CREATE INDEX internship_roles_company_idx ON public.internship_roles(company_id);

CREATE TABLE public.role_documents (
  document_key text NOT NULL,
  source_version integer NOT NULL CHECK (source_version >= 1),
  company_id text NOT NULL REFERENCES public.companies(company_id),
  source_title text NOT NULL,
  content text NOT NULL CHECK (char_length(content) BETWEEN 1 AND 200000),
  content_sha256 text GENERATED ALWAYS AS (app.text_sha256(content)) STORED,
  index_status text NOT NULL DEFAULT 'pending' CHECK (index_status IN ('pending','indexing','ready','failed','retired')),
  embedding_model text NOT NULL DEFAULT 'models/gemini-embedding-001',
  embedding_dimensions integer NOT NULL DEFAULT 3072 CHECK (embedding_dimensions = 3072),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (document_key, source_version)
);
CREATE INDEX role_documents_company_idx ON public.role_documents(company_id);

-- Names match the exported MCP PGVector node. No synthetic embeddings are inserted.
CREATE TABLE public.internship_role_chunks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  text text NOT NULL CHECK (char_length(text) BETWEEN 1 AND 30000),
  metadata jsonb NOT NULL,
  embedding extensions.vector(3072) NOT NULL,
  role_id text GENERATED ALWAYS AS (metadata->>'role_id') STORED
    REFERENCES public.internship_roles(role_id),
  CHECK (jsonb_typeof(metadata) = 'object'),
  CHECK (metadata ?& ARRAY['dataset','role_id','company','source_title','source_version']),
  CHECK (metadata->>'dataset' = 'internship_roles')
);
CREATE INDEX internship_role_chunks_metadata_idx ON public.internship_role_chunks USING gin(metadata);
CREATE INDEX internship_role_chunks_role_idx ON public.internship_role_chunks(role_id);

COMMENT ON TABLE public.companies IS 'Fictional educational catalog; not verified live vacancies.';
COMMENT ON TABLE public.internship_role_chunks IS 'Shared role knowledge only. Never store resumes or private letters.';

-- All knowledge access is server-side; publishing an API key does not expose rows.
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.internship_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.internship_role_chunks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.companies, public.internship_roles, public.role_documents,
  public.internship_role_chunks FROM PUBLIC, anon, authenticated;

GRANT USAGE ON SCHEMA public, extensions TO internship_api, internship_worker,
  internship_mcp_reader, internship_knowledge_writer;
GRANT SELECT ON public.companies, public.internship_roles TO internship_api, internship_worker;
GRANT SELECT ON public.internship_role_chunks TO internship_mcp_reader;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.companies, public.internship_roles,
  public.role_documents, public.internship_role_chunks TO internship_knowledge_writer;

CREATE POLICY companies_read ON public.companies FOR SELECT
  TO internship_api, internship_worker, internship_knowledge_writer USING (true);
CREATE POLICY roles_read ON public.internship_roles FOR SELECT
  TO internship_api, internship_worker, internship_knowledge_writer USING (true);
CREATE POLICY documents_writer ON public.role_documents
  TO internship_knowledge_writer USING (true) WITH CHECK (true);
CREATE POLICY chunks_reader ON public.internship_role_chunks FOR SELECT
  TO internship_mcp_reader USING (true);
CREATE POLICY chunks_writer ON public.internship_role_chunks
  TO internship_knowledge_writer USING (true) WITH CHECK (true);
CREATE POLICY companies_writer ON public.companies FOR ALL
  TO internship_knowledge_writer USING (true) WITH CHECK (true);
CREATE POLICY roles_writer ON public.internship_roles FOR ALL
  TO internship_knowledge_writer USING (true) WITH CHECK (true);

REVOKE ALL ON FUNCTION app.normalize_letter(text), app.letter_sha256(text),
  app.text_sha256(text), app.current_visitor_id() FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA app TO internship_api, internship_worker, internship_operator;
GRANT EXECUTE ON FUNCTION app.normalize_letter(text), app.letter_sha256(text),
  app.current_visitor_id() TO internship_api, internship_worker;
GRANT USAGE ON SCHEMA app TO internship_knowledge_writer;
GRANT EXECUTE ON FUNCTION app.text_sha256(text) TO internship_knowledge_writer;
