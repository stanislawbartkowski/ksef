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

QUERYPATTERN=patterns/initquery.json
#QUERYPATTERN=patterns/initq.json
QUERYOUTPUT=work/queryoutput.json


initsession() {
  requestchallenge $NIP $RECHALLENGE
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

#if requestsessionstatus $SESSIONTOKEN $SESSIONSTATUS; then echo "Sesja aktywna"; else echo "Sesja wygasła"; fi

#QUERY=patterns/initquery.json
#requestinvoicesync $SESSIONTOKEN $QUERY $REFERENCESTATUS
#requestinvoiceasyncinit  $SESSIONTOKEN $QUERY $REFERENCESTATUS

# --- scenariusz nr 1, wysłanie faktury
# sesja, wyślij poprawną fakturę, weź nr ksef i zakończ sesje

# initsession
#requestinvoicesendandreference $SESSIONTOKEN $INVOICE1 $REFERENCESTATUS
#terminatesession

# --- scenariusz nr 2, wysłaenie niepoprawej faktury
# sesja, wyślij niepoprawną fakturę

#initsession
#requestinvoicesendandreference $SESSIONTOKEN $INVOICE1 $REFERENCESTATUS
#terminatesession

# query

function fun() {
  initsession
  if requestsessionstatus $SESSIONTOKEN $SESSIONSTATUS; then echo "Sesja aktywna"; else echo "Sesja wygasła"; fi
  requestinvoicesync $SESSIONTOKEN $QUERYPATTERN "2023-10-01" "2023-10-11" $QUERYOUTPUT
  #requestinvoiceasyncinit  $SESSIONTOKEN $QUERYPATTERN $QUERYOUTPUT
  terminatesession
}

function count() {
  n=1
  while [ $n -le 5 ]
  do
    sleep 1
    echo  "$n"
    (( n+=2 ))
  done
}

RES=work/res.json

function read_invoices() {
  local -r page_size=10
  initsession
  if requestsessionstatus $SESSIONTOKEN $SESSIONSTATUS; then echo "Sesja aktywna"; else echo "Sesja wygasła"; fi
  echo '{ "res" : [] }' >$RES
  page_offset=0
  while true; do
    requestinvoicesync $SESSIONTOKEN "2023-10-01" "2023-10-11" $page_offset $page_size $QUERYOUTPUT
    R=`jq -r '.invoiceHeaderList' $QUERYOUTPUT`
    echo $R
    if [ "$R" == "[]" ]; then break; fi
    jq -n --slurpfile doc1  $RES --slurpfile doc2 $QUERYOUTPUT  '{ res: ($doc1[0].res + $doc2[0].invoiceHeaderList) }' >$RES
    (( page_offset+=$page_size))
    echo $page_offset
    if [ $page_offset -gt 30 ]; then break; fi
  done
  terminatesession
}

read_invoices
