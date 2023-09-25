import sys
import base64
from hashlib import md5

PATTERN="patterns/invoice.json"

def _createjson(invoice: str, requestjson: str):
    with open(invoice, "r") as f:
        lines = f.read()
        blines = lines.encode('UTF-8')
        
        contentbase64 = base64.b64encode(blines)
        
        digest = md5(blines).hexdigest().encode("ascii")
        digestbase64 = base64.b64encode(digest)
        
        filelen = len(lines)
        
    with open(PATTERN,"r") as p:
        lines = p.read()
        lines1 = lines.replace("__INVOICE__", contentbase64.decode("ascii"))
        lines2 = lines1.replace("__HASH__", digestbase64.decode("ascii"))
        lines3 = lines2.replace("9999999999",str(filelen))
        
    with open(requestjson,"w") as w:
        w.write(lines3)

if __name__ == '__main__':
    # invoice = sys.argv[1]
    # requestjson = sys.argv[2]
    invoice = 'example/Faktura_KSeF.xml'
    requestjson = 'work/invoice1.json'
    _createjson(invoice, requestjson)
