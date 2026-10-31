import hashlib
import hmac
import secrets
import base64
from dataclasses import dataclass
from uuid import UUID
from cryptography.fernet import Fernet, InvalidToken
from .errors import AppError

COOKIE = 'firstrole_session'

def digest(value: str | bytes):
    return hashlib.sha256(value.encode() if isinstance(value, str) else value).hexdigest()

def csrf_for(secret: str, signing_key: str):
    return hmac.new(signing_key.encode(), ('csrf:' + secret).encode(), hashlib.sha256).hexdigest()

def opaque_key(signing_key: str, scope: str, value: str):
    return hmac.new(signing_key.encode(), (scope + ':' + value).encode(), hashlib.sha256).hexdigest()

@dataclass(frozen=True)
class Visitor:
    id: UUID
    session_id: UUID

class Sessions:
    def __init__(self, db, settings):
        self.db, self.settings = db, settings

    def _require_key(self):
        if not self.settings.session_signing_key.get_secret_value():
            raise AppError('Private session configuration is missing.',503,'session_unconfigured')

    def get(self, raw):
        self._require_key()
        if not raw or len(raw) > 128:
            return None
        with self.db.transaction() as c:
            row = c.execute('SELECT id,visitor_id FROM app.sessions WHERE secret_hash=%s AND revoked_at IS NULL AND expires_at>now()', (digest(raw),)).fetchone()
        return Visitor(row['visitor_id'], row['id']) if row else None

    def establish(self, raw):
        self._require_key()
        visitor = self.get(raw)
        if visitor:
            return visitor, raw
        raw = secrets.token_urlsafe(48)
        csrf = csrf_for(raw, self.settings.session_signing_key.get_secret_value())
        with self.db.transaction() as c:
            owner = c.execute('INSERT INTO app.visitors DEFAULT VALUES RETURNING id').fetchone()['id']
            row = c.execute("INSERT INTO app.sessions(visitor_id,secret_hash,csrf_hash,expires_at) VALUES(%s,%s,%s,now()+make_interval(days=>%s)) RETURNING id", (owner,digest(raw),digest(csrf),self.settings.session_days)).fetchone()
        return Visitor(owner,row['id']), raw

    def require(self, raw):
        visitor = self.get(raw)
        if not visitor:
            raise AppError('Your private session expired. Reload this page.',401,'session_expired')
        return visitor

    def validate_mutation(self, request, raw):
        visitor = self.require(raw)
        expected = csrf_for(raw,self.settings.session_signing_key.get_secret_value())
        supplied = request.headers.get('x-csrf-token','')
        if request.headers.get('origin') != self.settings.app_origin or not hmac.compare_digest(supplied.encode(),expected.encode()):
            raise AppError('This request could not be verified. Reload the page.',403,'csrf_failed')
        return visitor

class Encryption:
    def __init__(self, settings):
        key = settings.resume_encryption_key.get_secret_value()
        self.cipher = Fernet(key.encode()) if key else None

    def encrypt(self, content: bytes):
        if not self.cipher:
            raise AppError('Resume encryption is not configured.',503,'encryption_unconfigured')
        # BYTEA stores binary, so omit the token's transport-only Base64 layer.
        # This keeps a 5 MB upload within the database's 6 MB ciphertext limit.
        return base64.urlsafe_b64decode(self.cipher.encrypt(content))

    def decrypt(self, content: bytes):
        if not self.cipher:
            raise AppError('Resume encryption is not configured.',503,'encryption_unconfigured')
        try:
            return self.cipher.decrypt(base64.urlsafe_b64encode(bytes(content)))
        except InvalidToken:
            raise AppError('The saved resume cannot be decrypted with this key.',503,'decryption_failed') from None
