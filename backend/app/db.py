from contextlib import contextmanager
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
import certifi
from .errors import AppError

class Database:
    def __init__(self, url: str, max_size=6, name='firstrole'):
        self.pool = None
        if url:
            self.pool = ConnectionPool(url, min_size=0, max_size=max_size, max_idle=30,
                timeout=8, max_waiting=24, open=False, name=name,
                kwargs={'row_factory': dict_row, 'connect_timeout': 6,
                        'prepare_threshold': None, 'application_name': name,
                        'sslmode': 'verify-full', 'sslrootcert': certifi.where()})

    def open(self):
        if self.pool:
            self.pool.open()

    def close(self):
        if self.pool:
            self.pool.close()

    @contextmanager
    def transaction(self, visitor_id=None):
        if self.pool is None:
            raise AppError('Database connection is not configured yet.', 503, 'database_unconfigured')
        with self.pool.connection() as connection:
            with connection.transaction():
                connection.execute("SELECT set_config('statement_timeout','8000',true)")
                connection.execute("SELECT set_config('lock_timeout','3000',true)")
                connection.execute("SELECT set_config('app.visitor_id',%s,true)", (str(visitor_id) if visitor_id else '',))
                yield connection

    def ready(self):
        with self.transaction() as c:
            row = c.execute("SELECT current_user, r.rolbypassrls FROM pg_roles r WHERE rolname=current_user").fetchone()
            if row['rolbypassrls'] or row['current_user'] == 'postgres':
                raise AppError('Use a restricted backend database login.', 503, 'unsafe_database_role')
            c.execute('SELECT role_id FROM public.internship_roles LIMIT 1').fetchone()
            c.execute('SELECT id FROM app.resumes LIMIT 0')
        return True
