export TEMPDIR=/tmp/ksef
export LOGFILE=$TEMPDIR/ksef.log

. ./env.rc
. proc/commonproc.sh
. proc/ksefproc.sh

TIMES=2023-09-22T21:27:52.300Z
CHALLENGE=20230922-CR-B434B8BBDB-872A019ADD-E1

#createatuhorizedtoken $TIMES

#buildinittokenxml $CHALLENGE $TIMES

#TEST=test/testchallenge.json
#gettimestampfromchallenge $TEST
#getchallengefromchallenge $TEST

#INITTOKEN=test/testinittoken.json
#getsessiontoken $INITTOKEN

#SESSIONSTATUS=status.json
#if requestsessionstatus $INITTOKEN $SESSIONSTATUS; then echo "Sesja aktywna"; else echo "Sesja wygasła"; fi


#getstatusexceptioncode test/status.json

#directrequestinvoicesend $SESSIONTOKEN $REQUESTINVOICE
#createinvoicesend $SESSIONTOKEN $REQUESTINVOICE

# -----
RECHALLENGE=work/rchallenge.json
INITTOKEN=work/inittoken.xml
SESSIONTOKEN=work/sessiontoken.json


initsession() {
  requestchallenge $RECHALLENGE
  createinitxmlfromchallenge $RECHALLENGE >$INITTOKEN
  requestinittoken $INITTOKEN $SESSIONTOKEN
}

terminatesession() {
  requestsessionterminate $SESSIONTOKEN    
}

#initsession

SESSIONSTATUS=work/sessionstatus.json
#if requestsessionstatus $SESSIONTOKEN $SESSIONSTATUS; then echo "Sesja aktywna"; else echo "Sesja wygasła"; fi

#requestsessionterminate $SESSIONTOKEN

INVOICE=example/Faktura_KSeF.xml
INVOICE1=example/faktura.xml
#INVOICE=example/faktura.xml
REQUESTINVOICE=work/invoice.json
# requestinvoicesend $SESSIONTOKEN $INVOICE $REQUESTINVOICE


#directrequestinvoicesend $SESSIONTOKEN $REQUESTINVOICE

# createinvoicesend $INVOICE $REQUESTINVOICE

INVOICESTATUS=work/invoicestatus.json

REFERENCENUMBER=`getinvoicereference $INVOICESTATUS`

REFERENCESTATUS=work/referencestatus.json
#requestreferencestatus $SESSIONTOKEN $REFERENCENUMBER $REFERENCESTATUS

#requestinvoiceget $SESSIONTOKEN $REFERENCENUMBER $REFERENCESTATUS

QUERY=patterns/initquery.json
#requestinvoicesync $SESSIONTOKEN $QUERY $REFERENCESTATUS
#requestinvoiceasyncinit  $SESSIONTOKEN $QUERY $REFERENCESTATUS

# --- scenariusz nr 1, wysłanie faktury
# sesja, wyślij poprawną fakturę, weź nr ksef i zakończ sesje

#initsession
#requestinvoicesend $SESSIONTOKEN $INVOICE $REQUESTINVOICE
#requestreferencestatus $SESSIONTOKEN $REFERENCENUMBER $REFERENCESTATUS
#terminatesession

# --- scenariusz nr 2, wysłaenie niepoprawej faktury
# sesja, wyślij nie poprawną fakturę

#initsession
#requestinvoicesend $SESSIONTOKEN $INVOICE1 $REQUESTINVOICE
#requestreferencestatus $SESSIONTOKEN $REFERENCENUMBER $REFERENCESTATUS
#terminatesession


