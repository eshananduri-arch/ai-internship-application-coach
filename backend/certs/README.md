# Supabase database CA

`supabase-root-2021.crt` is a public CA certificate, not a private key. Source: https://supabase-downloads.s3-ap-southeast-1.amazonaws.com/prod/ssl/prod-ca-2021.crt (linked by the official Supabase Studio SSL settings).

Set `DB_SSLROOTCERT=certs/supabase-root-2021.crt` in backend environment configuration. Relative paths resolve from `backend/`; absolute paths are also supported. All API, worker and operator pools use `verify-full` to check both the certificate chain and hostname. If the variable is unset, the normal certifi trust bundle is used. Do not disable certificate verification.
