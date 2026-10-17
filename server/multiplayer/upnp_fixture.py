"""Loopback SOAP router fixture, never changes a real router."""
from aiohttp import web
import xml.etree.ElementTree as ET


def install(app):
    mappings = {}
    async def control(request):
        root = ET.fromstring(await request.text())
        values = {e.tag.split('}')[-1]: e.text or '' for e in root.iter()}
        port = int(values['NewExternalPort'])
        action = request.headers.get('SOAPAction', '')
        status = 200
        if 'GetSpecificPortMappingEntry' in action:
            if port in mappings:
                body = ''.join(f'<{k}>{v}</{k}>' for k,v in mappings[port].items())
            else:
                status, body = 500, '<errorCode>714</errorCode>'
        elif 'AddPortMapping' in action:
            assert values['NewProtocol'] == 'TCP'
            assert values['NewLeaseDuration'] == '3600'
            mappings[port] = {k:values[k] for k in ['NewInternalClient','NewInternalPort','NewPortMappingDescription']}
            body = ''
        elif 'DeletePortMapping' in action:
            mappings.pop(port, None)
            body = ''
        else:
            raise web.HTTPBadRequest()
        return web.Response(status=status, content_type='text/xml', text='<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'+body+'</s:Body></s:Envelope>')
    app.router.add_post('/upnp/control', control)
