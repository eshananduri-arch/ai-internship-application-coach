"""Verify configured service logins without printing secrets or private records."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app.config import Settings
from app.db import Database

def main():
    settings=Settings()
    for name,value,group in [('api',settings.database_url,'internship_api'),('worker',settings.worker_database_url,'internship_worker'),('operator',settings.operator_database_url,'internship_operator')]:
        if not value.get_secret_value():
            raise SystemExit(name+': connection is not configured')
        db=Database(value.get_secret_value(),2,'firstrole-check-'+name,sslrootcert=settings.db_sslrootcert)
        db.open()
        try:
            with db.transaction() as connection:
                role=connection.execute("SELECT rolname,rolsuper,rolbypassrls,pg_has_role(current_user,%s,'MEMBER') member FROM pg_roles WHERE rolname=current_user",(group,)).fetchone()
                if role['rolsuper'] or role['rolbypassrls'] or not role['member']:
                    raise SystemExit(name+': incorrect database permission group')
                if name=='operator':
                    connection.execute('SELECT app.operations_snapshot()').fetchone()
                else:
                    connection.execute('SELECT role_id FROM public.internship_roles LIMIT 1').fetchone()
            print(name+': connected with verified SSL and restricted permissions')
        finally:
            db.close()
    print('coaching: '+('configured' if settings.coaching_configured else 'not configured'))

if __name__=='__main__':
    main()
