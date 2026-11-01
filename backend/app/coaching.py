import hashlib
import json
import re
from datetime import datetime
from zoneinfo import ZoneInfo
import httpx
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from .errors import AppError, PipelineError

def normalize_letter(text):
    return text.replace('\r\n','\n').replace('\r','\n')

def validate_letter(text: str, candidate_name=None):
    text=normalize_letter(text)
    if not 80<=len(text)<=20000 or len(text.split())>250 or '\x00' in text:
        raise AppError('Use a complete letter of 250 words or fewer.',422,'letter_length')
    if re.search(r'\[(?:your|candidate|name|company|role|date|address|email|phone|insert)[^\]]*\]|<(?:EMAIL_ADDRESS|PHONE_NUMBER|NAME|PERSON)>|```',text,re.I):
        raise AppError('Replace placeholders and remove Markdown code fences before approval.',422,'letter_placeholders')
    if not re.match(r'^\s*(dear|to the)\b',text,re.I) or not re.search(r'\b(sincerely|regards|yours faithfully|yours truly)\b',text,re.I):
        raise AppError('The letter needs a greeting and professional closing.',422,'letter_structure')
    if candidate_name and candidate_name.casefold() not in text[-300:].casefold():
        raise AppError('Use the candidate name in the letter signature.',422,'letter_signature')
    return text

class ToolEvidence(BaseModel):
    model_config=ConfigDict(extra='forbid')
    tool: str
    role_id: str | None=None
    letter_sha256: str | None=None
    word_count: int | None=None
    source_version: int | None=None

class CoachingResult(BaseModel):
    model_config=ConfigDict(extra='forbid')
    analysis_id: str
    role_id: str
    final_letter: str
    match_report: dict
    critic_review: dict
    deadline_info: dict
    tool_evidence: list[ToolEvidence]
    usage: dict = Field(default_factory=dict)

class Coach:
    def __init__(self, settings, transport=None):
        self.settings,self.transport=settings,transport

    def generate(self, analysis, resume_text, attempt):
        if not self.settings.coaching_configured:
            raise PipelineError('coaching_unconfigured')
        payload={'analysis_id':str(analysis['id']),'request_id':analysis['request_id'],
            'attempt_id':str(analysis['id'])+':'+str(attempt),
            'company':analysis['role_snapshot']['company'],'role_id':analysis['role_id'],
            'role':analysis['role_snapshot'],'candidate_name':analysis['candidate_name'],
            'resume_text':resume_text,'today':datetime.now(ZoneInfo('Asia/Kolkata')).date().isoformat(),
            'max_words':250,'token_budget':12000}
        try:
            with httpx.Client(timeout=httpx.Timeout(self.settings.n8n_timeout_seconds,connect=10),
                    follow_redirects=False,transport=self.transport) as client:
                with client.stream('POST',self.settings.n8n_webhook_url,json=payload,
                    headers={'Authorization':'Bearer '+self.settings.n8n_webhook_token.get_secret_value(),
                             'Idempotency-Key':str(analysis['id'])}) as response:
                    if response.status_code==429:
                        try: delay=max(1,min(900,int(response.headers.get('retry-after','30'))))
                        except ValueError: delay=30
                        raise PipelineError('provider_throttled',retryable=True,retry_after=delay)
                    if response.status_code>=500:
                        # Keep only known error codes, never provider messages, resumes or letters.
                        error_body=bytearray()
                        for chunk in response.iter_bytes():
                            error_body.extend(chunk)
                            if len(error_body)>16384:
                                break
                        safe_codes={'model_incomplete_output','model_invalid_json','model_invalid_schema',
                            'model_unsupported_evidence','model_invalid_match','critic_requires_changes',
                            'letter_invalid_length','letter_missing_role','letter_placeholders',
                            'mcp_tool_failed','mcp_invalid_json','mcp_invalid_envelope',
                            'role_not_found','role_expired','usage_exceeds_budget','provider_http_failed',
                            'provider_connection_failed','missing_usage_metadata'}
                        try:
                            error=json.loads(error_body) if len(error_body)<=16384 else {}
                            code=error.get('error_code') if isinstance(error,dict) and error.get('status')=='failed' else None
                        except (ValueError,UnicodeDecodeError):
                            code=None
                        if code in safe_codes:
                            raise PipelineError(code,uncertain=True)
                        raise PipelineError('coaching_unavailable',retryable=self.settings.n8n_idempotent,uncertain=True)
                    if response.status_code!=200:
                        raise PipelineError('coaching_http_error')
                    raw=bytearray()
                    for chunk in response.iter_bytes():
                        raw.extend(chunk)
                        if len(raw)>131072:
                            raise PipelineError('coaching_response_too_large')
            try:
                return self.validate(json.loads(raw),analysis)
            except PipelineError as error:
                error.uncertain=True
                raise
        except PipelineError:
            raise
        except (httpx.TimeoutException,httpx.NetworkError):
            raise PipelineError('coaching_timeout',retryable=self.settings.n8n_idempotent,uncertain=True) from None
        except (ValueError,ValidationError,AppError):
            raise PipelineError('invalid_coaching_response',uncertain=True) from None

    def validate(self, data, analysis):
        result=CoachingResult.model_validate(data)
        if result.analysis_id!=str(analysis['id']) or result.role_id!=analysis['role_id']:
            raise PipelineError('coaching_identity_mismatch')
        if result.deadline_info.get('expired') is not False:
            raise PipelineError('role_deadline_invalid')
        result.final_letter=validate_letter(result.final_letter,analysis['candidate_name'])
        checksum=hashlib.sha256(result.final_letter.encode()).hexdigest()
        evidence=result.tool_evidence
        if not any(e.tool=='search_internship_roles' and e.role_id==analysis['role_id']
                   and e.source_version==analysis['role_snapshot'].get('catalog_version',1) for e in evidence):
            raise PipelineError('missing_role_evidence')
        counts=[e for e in evidence if e.tool=='word_count' and e.letter_sha256==checksum and e.word_count==len(result.final_letter.split())]
        if len(counts)!=1 or not any(e.tool=='days_until' and e.role_id==analysis['role_id'] for e in evidence):
            raise PipelineError('missing_final_letter_evidence')
        if result.critic_review.get('approved') is not True:
            raise PipelineError('critic_requires_changes')
        if not isinstance(result.critic_review.get('feedback'),list):
            raise PipelineError('invalid_critic_feedback')
        for key in ('input_tokens','output_tokens'):
            if type(result.usage.get(key)) is not int or not 0<=result.usage[key]<=12000:
                raise PipelineError('missing_usage_accounting')
        if result.usage['input_tokens']+result.usage['output_tokens']>12000:
            raise PipelineError('usage_exceeds_reservation')
        return result.model_dump()
