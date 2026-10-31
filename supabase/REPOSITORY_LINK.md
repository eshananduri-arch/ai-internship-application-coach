# Supabase repository association

The project schema and migration history are versioned in this repository. `project.json` identifies the existing Mumbai project; it contains no authentication credential. `config.toml` is the generated local CLI configuration, with PostgreSQL 17 and seed replay disabled because the educational catalog is already a versioned migration.

An actual authenticated CLI link and Supabase dashboard GitHub connection are **not completed**. CLI inspection returned `AccessTokenRequiredError`; the browser helper failed before the integration page could be operated. Recording a project reference does not authenticate the CLI, connect Python to the database or install a GitHub integration.

## Finish dashboard association

An authorized Supabase/GitHub account owner can open [this project's integration settings](https://supabase.com/dashboard/project/eztcigkqrhuyeyfgpaor/settings/integrations), connect the GitHub integration, and select `eshananduri-arch/ai-internship-application-coach`. The selected Supabase directory is `/supabase` and the main branch is `main`.

Keep **Deploy to production** disabled while integration/testing is unfinished. Do not create paid preview branches or enable automatic deployments as part of the version 1 source checkpoint. Review the generated local configuration before allowing it to modify any hosted project settings. Follow the [official GitHub integration guide](https://supabase.com/docs/guides/deployment/branching/github-integration) for the current UI and account permissions.

## Finish a developer's local CLI link

With a Supabase CLI installed and the appropriate account authorization, run from the repository root:

```sh
supabase login
supabase link --project-ref eztcigkqrhuyeyfgpaor
supabase migration list
```

Enter credentials only into the local authenticated CLI or private environment; never put access tokens/passwords into Git, screenshots or chat. The CLI's local `.temp` files are ignored. These commands link and inspect; do not run `db push`, `db reset`, `db pull` or enable deployment unless a specific schema operation is intended. The eight existing migrations are already applied, so do not create a duplicate baseline by importing them again.

A CLI link is separate from the API's `DATABASE_URL` and the worker/operator credentials. Those remain unconfigured in version 1. No database login accounts were created.
