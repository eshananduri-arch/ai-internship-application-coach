import asyncio
from starlette.responses import JSONResponse

class BodyLimitMiddleware:
    """Bound multipart bytes before parsing/spooling, including chunked requests."""
    def __init__(self,app,maximum):
        self.app,self.maximum=app,maximum

    async def __call__(self,scope,receive,send):
        if scope['type']!='http' or scope.get('method') not in ('POST','PUT','PATCH') or not scope.get('path','').startswith('/api/'):
            return await self.app(scope,receive,send)
        headers=dict(scope.get('headers',[]))
        length=headers.get(b'content-length',b'0')
        chunks=[]; total=0
        try:
            if not length.isdigit() or int(length)>self.maximum:
                raise OverflowError
            async with asyncio.timeout(30):
                while True:
                    message=await receive()
                    if message['type']=='http.disconnect': return
                    chunk=message.get('body',b''); total+=len(chunk)
                    if total>self.maximum: raise OverflowError
                    chunks.append(chunk)
                    if not message.get('more_body',False): break
        except (OverflowError,TimeoutError) as error:
            response=JSONResponse({'message':'Request exceeds the upload limit.' if isinstance(error,OverflowError) else 'Upload timed out.'},
                status_code=413 if isinstance(error,OverflowError) else 408,headers={'Cache-Control':'no-store'})
            return await response(scope,receive,send)
        body=b''.join(chunks)
        delivered=False
        async def buffered_receive():
            nonlocal delivered
            if not delivered:
                delivered=True
                return {'type':'http.request','body':body,'more_body':False}
            return await receive()
        await self.app(scope,buffered_receive,send)
