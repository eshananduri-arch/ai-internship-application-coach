"""Create ignored secrets once. Never overwrites an existing local environment."""
import secrets
from pathlib import Path
from cryptography.fernet import Fernet

root=Path(__file__).resolve().parents[1]
path=root/'.env'
if path.exists():
    raise SystemExit('Existing backend/.env preserved. Edit it intentionally; do not rotate encryption keys accidentally.')
data=(root/'.env.example').read_text(encoding='utf-8')
for name,value in {'SESSION_SIGNING_KEY':secrets.token_urlsafe(48),'RESUME_ENCRYPTION_KEY':Fernet.generate_key().decode(),'ADMIN_TOKEN':secrets.token_urlsafe(48)}.items():
    data=data.replace(name+'=\n',name+'='+value+'\n')
path.write_text(data,encoding='utf-8',newline='\n')
print('Created backend/.env with random local secrets. No values printed. Keep and back up this ignored file securely.')
