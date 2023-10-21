export TEMPDIR=/tmp/ksef
export LOGFILE=$TEMPDIR/ksef.log
export REPFILE=$TEMPDIR/report.txt

. ./env.rc
. proc/commonproc.sh
. proc/ksefproc.sh

NIP="5328617307"

test() {
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
}

test1() {
  echo "test1"
  #requestchallenge $RECHALLENGE
  #createinitxmlfromchallenge $RECHALLENGE >$INITTOKEN
  #requestinittoken $INITTOKEN $SESSIONTOKEN
}


# -----
RECHALLENGE=work/rchallenge.json
INITTOKEN=work/inittoken.xml
SESSIONTOKEN=work/sessiontoken.json
REQUESTINVOICE=work/invoice.json
INVOICESTATUS=work/invoicestatus.json
SESSIONSTATUS=work/sessionstatus.json
INVOICE=example/Faktura_KSeF.xml
INVOICE1=example/faktura.xml
REFERENCESTATUS=work/referencestatus.json


initsession() {
  requestchallenge $RECHALLENGE
  createinitxmlfromchallenge $NIP $RECHALLENGE >$INITTOKEN
  requestinittoken $INITTOKEN $SESSIONTOKEN
}

terminatesession() {
  requestsessionterminate $SESSIONTOKEN    
}

getksefnumber() {
  REFERENCENUMBER=`getinvoicereference $INVOICESTATUS`
  echo $REFERENCENUMBER  
  requestreferencestatus $SESSIONTOKEN $REFERENCENUMBER $REFERENCESTATUS
}

#TOKEN=`gettokenfornip $NIP`
#echo $TOKEN

# if requestsessionstatus $SESSIONTOKEN $SESSIONSTATUS; then echo "Sesja aktywna"; else echo "Sesja wygasła"; fi

#QUERY=patterns/initquery.json
#requestinvoicesync $SESSIONTOKEN $QUERY $REFERENCESTATUS
#requestinvoiceasyncinit  $SESSIONTOKEN $QUERY $REFERENCESTATUS

# --- scenariusz nr 1, wysłanie faktury
# sesja, wyślij poprawną fakturę, weź nr ksef i zakończ sesje

#initsession
#requestinvoicesendandreference $SESSIONTOKEN $INVOICE1 $REFERENCESTATUS
terminatesession

# --- scenariusz nr 2, wysłaenie niepoprawej faktury
# sesja, wyślij niepoprawną fakturę

#initsession
#requestinvoicesendandreference $SESSIONTOKEN $INVOICE1 $REFERENCESTATUS
#terminatesession


