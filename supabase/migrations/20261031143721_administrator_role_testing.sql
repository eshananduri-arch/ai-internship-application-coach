-- Supabase's managed postgres role is not a superuser. Permit the migration
-- administrator to test the actual restricted roles without inheriting them.
-- No browser role or service login is made a member here.
GRANT internship_api,internship_worker,internship_mcp_reader,
  internship_knowledge_writer,internship_operator TO postgres WITH SET TRUE;
