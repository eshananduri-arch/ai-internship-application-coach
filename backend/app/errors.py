class AppError(Exception):
    def __init__(self, message: str, status: int = 400, code: str = 'invalid_request'):
        self.message, self.status, self.code = message, status, code
        super().__init__(code)

class PipelineError(Exception):
    def __init__(self, code: str, *, retryable=False, retry_after=30, uncertain=False):
        self.code, self.retryable = code, retryable
        self.retry_after, self.uncertain = retry_after, uncertain
        super().__init__(code)
