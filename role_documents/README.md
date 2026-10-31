# Educational role sources

These five Markdown files come from the supplied internship coach package. All vacancies, stipends and dates are simulated training data. Do not present them as current real job listings.

The 15 role IDs match the frontend catalog and seeded Supabase `public.internship_roles`. The source text is stored in `public.role_documents` version 1. Embeddings have not yet been generated.

During n8n indexing, split source sections by the explicit `Role ID`, retain the company/title/version, generate real embeddings with `models/gemini-embedding-001` at 3072 dimensions, and write `public.internship_role_chunks`. Each metadata object must include `dataset: internship_roles`, the exact `role_id`, `company`, `source_title` and `source_version`. Search must filter the user's exact selected role ID. Never index personal resumes into shared role knowledge.

Use the dedicated knowledge-writer credential. Validate retrieval for all 15 roles before setting a source document to `ready`. This directory contains source data only and does not perform indexing.
