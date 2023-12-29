# ------------------------------------
# different funcs related to KSeF
# ------------------------------------
# 2023/09/24 - first commit
# 2023/11/25 - usuwanie faktury z bufora
# 2023/11/30 - czytanie faktur 
# 2023/12/28 - UPO

OK="OK"
ERROR="ERROR"
#CURLPARS="--no-progress-meter -v"
CURLPARS="--no-progress-meter -v"
# ----------------
# journal
# ----------------

OPERATIONLEN=30
TIMELEN=10
RESULTLEN=10
OPISLEN=50

# Adds entry to journal
# $2 : operation name
# $3 : starttime
# $4 : endtime
# $5 : result
# $6 : opis
function journallog() {
  printreportline $REPFILE "$1" $OPERATIONLEN "$2" $TIMELEN "$3" $TIMELEN "$4" $RESULTLEN "$5" $OPISLEN
}

function journallognocomment() {
    printreportline $REPFILE "$1" $OPERATIONLEN "$2" $TIMELEN "$3" $TIMELEN "$4" $RESULTLEN " " $OPISLEN
}

# ------------------
# helpers
# ------------------

function buildauthorizationchallengejson() {
    local -r NIP=$1
    local -r IN=$KSEFPROCDIR/patterns/authorisationchallenge.json
    sed s"/__NIP__/$NIP/" $IN 
}

function createatuhorizedtoken() {
    # assuming TIMES does not contain spaces
    local -r TOKEN=$1
    local -r TIMES=$2
    lognoecho "TIMES=$TIMES"
    # convert TIMES to epoch miliseconds
    local -r MSECS=`date -d $TIMES +%s%3N 2>>$LOGFILE`
    local -r ENV=`getksefenv`
    [[ ! -z "$MSECS" ]] || logfailnoecho "Failed while calculating mili epoch from challenge date"
    local -r PUBKEY="$KSEFPROCDIR/ksefkeys/$ENV/publicKey.pem"
    # very important: echo without -n is adding extra lf at the end which messes up the result
    #                 also  -w 0 parameters to base64, without that the string is broken into lines using lfs
    echo -n "$TOKEN|$MSECS" | openssl pkeyutl -encrypt -pubin -inkey $PUBKEY 2>>$LOGFILE | base64 -w 0
}

function buildinittokenxml() {
    local -r TOKEN=$1
    local -r AUTHCHALLENGE=$2
    local -r ATOKEN=`createatuhorizedtoken $TOKEN $3`
    [[ ! -z "$ATOKEN" ]] || logfail "Failed while creating authorization token with openssl"
    local -r IN=$KSEFPROCDIR/patterns/inittoken.xml
    # base64 can contain / but does not produce #
    # sed to replace TOKEN should be executed as eval because of spaces problem
    local -r CMD="sed \"s#__TOKEN__#$ATOKEN#\" $IN"
    eval  $CMD | sed s"/__NIP__/$NIP/" | sed s"/__CHALLENGE__/$AUTHCHALLENGE/"
    [ $? -eq 0 ] || logfail "Failed while building token with sed"
}

function gettimestampfromchallenge() {
    echo `jq -r ".timestamp" $1`
}

function getchallengefromchallenge() {
    echo `jq -r ".challenge" $1`
}

function getsessiontoken() {
    echo `jq -r ".sessionToken.token" $1`
}

function gettokenfornip() {
    echo `yq -r ".tokens.NIP$1" $TOKENSTORE`
}

function getksefenv() {
    local -r ENV=`yq -r ".env" $TOKENSTORE`
    if [ "$ENV" = "null" ] ; then echo "test"; else echo $ENV;
    fi
}    

function createinitxmlfromchallenge() {
    local -r NIP=$1
    local -r TOKEN=`gettokenfornip $NIP`    
    [ "$TOKEN" == "null" ] && logfail "Cannot get token for nip $NIP"
    local -r TIMESTAMP=`gettimestampfromchallenge $2`
    local -r CHALLENGE=`getchallengefromchallenge $2`
    buildinittokenxml $TOKEN $CHALLENGE $TIMESTAMP
}

function gethttpcode() {
    local -r HTTP=`grep "HTTP/1.1 " $1 | sed "s/.* \([0-9]*\) .*/\1/"`
    echo $HTTP
}

function getstatusexceptioncode() {
    echo `jq -r .exception.exceptionDetailList[0].exceptionCode $1`
}

function getprocessingcode() {
    echo `jq -r .processingCode $1`
}

function getinvoicereference() {
    echo `jq -r .elementReferenceNumber $1`
}

function getsessionreferencenumber() {
    echo `jq -r .referenceNumber $1`
}


# create payload for invoice/send
# $1 - < invoice XML
# $2 - > invoice/send json
function createinvoicesend() {
    local -r PATTERN=$KSEFPROCDIR/patterns/invoice.json
    local -r FILESIZE=`cat $1 | wc -c`
    local -r BODY=`cat $1 | base64 -w 0`

    #local -r HASH=`md5sum $1 | cut -d " " -f 1 | base64 -w 0`
    local -r HASH=`cat $1 | openssl sha256 -binary | base64 -w 0`

    local -r CMD="sed \"s#__HASH__#$HASH#\" $PATTERN"
    local -r CMD1="sed \"s#__INVOICE__#$BODY#\""
    eval $CMD | eval $CMD1 | sed "s/9999999999/$FILESIZE/" >$2
}

# error handling

# $1 - < file with command output
# $2 - < expected HTTP code
# $3 - < OP
# $4 - < BEG
# $5 - < (optional) additional file to log
function analizehttpcode() {
    local -r HTTP=`gethttpcode $1`
    local -r EXPECTED=$2
    logfile $1
    if [ "$HTTP" != "$EXPECTED" ]; then
        local -r END=`getdate`
        local -r MESS="Obtained HTTP code $HTTP  Expected HTTP code $EXPECTED"
        journallog "$3" "$4" "$END" $ERROR "$MESS"
        [ ! -z "$5" ] && logfile $5
        logfail "$MESS"
    fi
}

# $1 - < exist code
# $2 - < file with command output
# $3 - < Fail message
# $4 - < OP
# $5 - < BEG
function checkstatus() {
    if [ $1 -ne 0 ]; then
        local -r END=`getdate`
        journallog "$4" "$5" "$END" $ERROR "$3"
        logfile $2
        logfail "$3"
    fi
}

# $1 - < $?
# $2 - < file with output
# $3 - < Expected HTTP code
# $4 - < Fail message
# $5 - < OP
# $6 - < BEG
# $7 - < (optional) additional file to log

function verifyresult() {
    checkstatus $1 $2 "$4" "$5" "$6"
    analizehttpcode $2 $3 "$5" "$6" $7
    local -r END=`getdate`
    [ ! -z "$7" ] && logfile $7
    journallognocomment "$5" "$6" "$END" $OK    
}

# -------------------------
# actions
# -------------------------

# /online/Session/AuthorisationChallenge
# $1 - < NIP
# $2 - > result
function requestchallenge() {
    local -r NIP=$1
    local -r ROUT=$2
    local -r TEMP=`crtemp`
    buildauthorizationchallengejson $NIP >$TEMP
    logfile $TEMP
    local -r BEG=`getdate`
    log "Obtaining authorization challenge"
    local -r OP="Session/AuthorisationChallenge"
    curl $PREFIXURL/api/online/Session/AuthorisationChallenge -d @$TEMP $CURLPARS -H "Content-Type: application/json" -o $ROUT >$CURLOUT 2>&1
    verifyresult $? $CURLOUT 201 "Failed to obtain authorization challenge" "$OP" "$BEG" $ROUT
}

# /online/Session/InitToken 
# $1 - < inittoken.json request file
# $2 - > result 
function requestinittoken() {
    log "Obtaining init token"
    local -r BEG=`getdate`
    local -r OP="Session/InitToken"
    echo $1
    logfile $1
    curl $PREFIXURL/api/online/Session/InitToken $CURLPARS  -H "Content-Type: application/octet-stream" -H "accept: application/json" -d@$1 -o $2 >$CURLOUT 2>&1
    verifyresult $? $CURLOUT 201 "Failed to obtain init token" "$OP" "$BEG" $2
}

# /online/Session/Status
# $1 - result of the InitToken file, sessiontoken.json
# $2 - result file
# Returns
#  0 - sesja aktywna
#  1 - sesja nieaktywna
function requestsessionstatus() {
    log "Checking session status"
    local -r BEG=`getdate`
    local -r OP="Session/Status"
    local -r SESSIONTOKEN=`getsessiontoken $1`
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot extract session token"    
    local -r END=`getdate`
    for i in {1..7} 
    do
        curl $PREFIXURL/api/online/Session/Status $CURLPARS -H "SessionToken: $SESSIONTOKEN" -o $2  >$CURLOUT 2>&1
        checkstatus $? $CURLOUT "Failed to verify session status" "$OP" "$BEG"
        logfile $2
        logfile $CURLOUT
        local HTTPCODE=`gethttpcode $CURLOUT`
        case $HTTPCODE in
        200) 
            local PROCESSINGCODE=`getprocessingcode $2`
            [[ ! -z "$PROCESSINGCODE" ]] || logfail "Cannot extract processing code" 
            if [ "$PROCESSINGCODE" == "315" ]; then 
                journallog "$OP" "$BEG" "$END" $OK "Sesja aktywna (315) po $i próbach"
                return 0
            fi
            if [ "$PROCESSINGCODE" == "200" ]; then 
                journallog "$OP" "$BEG" "$END" $OK "Sesja nieaktywna (200) "
               return 1
            fi
            if  [ "$PROCESSINGCODE" == "310" ]; then
               log "Code 310, wait $i sec and try again"
               sleep $i
               continue;
            fi
            local -r MESS="Unrecognized processing code $PROCESSINGCODE  Expected 315 or 200"
            journallog "$OP" "$BEG" "$END" $ERROR "$MESS"
            logfail "$MESS"
            ;;
        400) 
            local -r ECODE=`getstatusexceptioncode $2`
            if [ "$ECODE" == "21170" ]; then 
               journallog "$OP" "$BEG" "$END" $OK "Sesja nieaktywna (21170) "               
               return 1
            fi
            ;;
        esac
    done
    local -r MESS="Nie mozna ustalić statusu sesji"
    journallog "$OP" "$BEG" "$END" $ERROR "$MESS"
    logfail "$MESS"
}

# /online/Session/Terminate
# $1 - result of the InitToken file, sessiontoken.json
function requestsessionterminate() {
    log "Terminating session"
    local -r OP="Session/Terminate"
    local -r BEG=`getdate`
    local -r SESSIONTOKEN=`getsessiontoken $1`
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot extract session token"
    local -r TEMP=`crtemp`
    curl $PREFIXURL/api/online/Session/Terminate $CURLPARS -H "SessionToken: $SESSIONTOKEN" -o $TEMP  >$CURLOUT 2>&1
    verifyresult $? $CURLOUT 200 "Failed to terminate session" "$OP" "$BEG" $TEMP
}

# /online/Invoice/Send
# $1 - < result of the InitToken file, sessiontoken.json
# $2 - > request invoice/send 
# $3 - > invoice status
function directrequestinvoicesend() {
    log "Sending invoice"
    local -r OP="Invoice/Send"
    local -r BEG=`getdate`
    local -r SESSIONTOKEN=`getsessiontoken $1`
    local -r OUT=$3
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot extract session token"
    # Important: PUT
    curl -X PUT $PREFIXURL/api/online/Invoice/Send $CURLPARS -H "Content-Type: application/json" -H "accept: application/json" -H "SessionToken: $SESSIONTOKEN" -d@$2 -o $OUT >$CURLOUT 2>&1
    verifyresult $? $CURLOUT 202 "Failed to send invoice" "$OP" "$BEG" $OUT
}


# /online/Invoice/Send
# $1 - < result of the InitToken file, sessiontoken.json
# $2 - < invoice XML
# $3 - > request invoice/send
# $4 - > invoice status
function requestinvoicesend() {
    createinvoicesend $2 $3
    directrequestinvoicesend $1 $3 $4
}

# api/online/Invoice/Status
# $1 - < result of the InitToken file, sessiontoken.json
# $2 - < invoice reference number
# $3 - > response
function requestreferencestatus() {
    log "Checking invoice reference status $2"
    local -r OP="Invoice/Status"
    local -r BEG=`getdate`
    local -r SESSIONTOKEN=`getsessiontoken $1`
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot extract session token"    
    curl $PREFIXURL/api/online/Invoice/Status/$2 $CURLPARS -H "SessionToken: $SESSIONTOKEN" -o $3  >$CURLOUT 2>&1
    verifyresult $? $CURLOUT 200 "Failed to verify invoice reference status" "$OP" "$BEG" $3
}

# TODO: remove

# /online/Invoice/Get/{KSeFReferenceNumber}
# $1 < sessiontoken.json
# $2 < ksief invoice reference number
# $3 - > response
function requestinvoiceget() {
    log "Get invoice using ksef reference number $2"
    local -r SESSIONTOKEN=`getsessiontoken $1`
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot extract session token"    
    curl $PREFIXURL/api/online/Invoice/Get/$2 $CURLPARS -H "SessionToken: $SESSIONTOKEN" -o $3  >$CURLOUT 2>&1
    checkstatus $? $CURLOUT "Failed to get invoice by reference number" 
    logfile $3
    logfile $CURLOUT
    analizehttpcode $CURLOUT 200
}

# /online/Query/Invoice/Sync
# $1 < sessiontoken.json
# $2 < date_from
# $3 < date_to
# $4 < page offset
# $5 < page size
# $6 - > response
function requestinvoicesync() {
    log "Running Query/Invoice/Sync"
    local -r SESSIONTOKEN=`getsessiontoken $1`
    local -r DATE_FROM=$2
    local -r DATE_TO=$3
    local -r PAGE_OFFSET=$4
    local -r PAGE_SIZE=$5
    local -r TEMP=`crtemp`
    local -r QUERYPATTERN=$KSEFPROCDIR/patterns/initquery.json
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot run query"    
    log "Read invoices $DATE_FROM to $DATE_TO"
    log "Read invoice from $PAGE_OFFSET with size: $PAGE_SIZE"
    sed "s/__DATE_FROM__/$DATE_FROM/" $QUERYPATTERN | sed "s/__DATE_TO__/$DATE_TO/" >$TEMP
    logfile $TEMP
    curl "$PREFIXURL/api/online/Query/Invoice/Sync?PageSize=$PAGE_SIZE&PageOffset=$PAGE_OFFSET" $CURLPARS -H "Content-Type: application/vnd.v2+json" -H "SessionToken: $SESSIONTOKEN" -d @$TEMP -o $6  >$CURLOUT 2>&1
    checkstatus $? $CURLOUT "Failed to read invoices" 
    logfile $6
    logfile $CURLOUT
    analizehttpcode $CURLOUT 200
}

# /online/Query/Invoice/Async/Init
# $1 < sessiontoken.json
# $2 < queryjson
# $3 > response
function requestinvoiceasyncinit() {
    log "Running Query/Invoice/Async/Init"
    local -r SESSIONTOKEN=`getsessiontoken $1`
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot run query"    
    curl $PREFIXURL/api/online/Query/Invoice/Async/Init $CURLPARS -H "Content-Type: application/vnd.v2+json" -H "SessionToken: $SESSIONTOKEN" -d @$2 -o $3  >$CURLOUT 2>&1
    checkstatus $? $CURLOUT "Failed run AyncInit" 
    logfile $3
    logfile $CURLOUT
    analizehttpcode $CURLOUT 202
}

# /common/Status
# $1 < session reference number
# $2 > status, response
function requestcommonsessionstatus() {
    local -r STATUSREFERENCENUMBER=$1
    local -r OP="common/Status"
    local -r BEG=`getdate`

    log "Running $OP session reference number: $STATUSREFERENCENUMBER"
    curl $PREFIXURL/api/common/Status/$STATUSREFERENCENUMBER $CURLPARS -H "Content-Type: application/vnd.v2+json" -o $2  >$CURLOUT 2>&1
    verifyresult $? $CURLOUT 200 "Failed to get session status" "$OP" "$BEG" $2
}

# ----------------------------------
# operation
# ----------------------------------

# invoice send and get ksef reference number
# $1 < sessiontoken.json
# $2 < invoice
# $3 > reference status

function requestinvoicesendandreference() {
    local -r TEMP=`crtemp`
    local -r ITEMP=`crtemp`
    requestinvoicesend $1 $2 $TEMP $ITEMP
    REFERENCENUMBER=`getinvoicereference $ITEMP`
    local -r OP="Invoice/GetKsefReference"
    local -r BEG=`getdate`
    for i in {1..3} 
    do
        sleep $i
        requestreferencestatus $1 $REFERENCENUMBER $3
        local PCODE=`getprocessingcode $3`
        [ $PCODE -eq 336 ] && return 0
        [ $PCODE -eq 200 ] && return 0
        [ $PCODE -eq 430 ] && return 0
        [ $PCODE -ne 310 ] && break
        log "Invoice still preprocessing, wait $i sec and retry"
    done
    local -r END=`getdate`
    journallog "$OP" "$BEG" "$END" $ERROR "Cannot extract reference number"
    logfail "Cannot extract reference number"
}

# -------------------------------------
# init
# -------------------------------------

function recognizeenv() {
    local -r ENV=`getksefenv`
    case $ENV in
      test) PREFIXURL='https://ksef-test.mf.gov.pl';;
      demo) PREFIXURL='https://ksef-demo.mf.gov.pl';;
      prod) PREFIXURL='https://ksef.mf.gov.pl';;
      *) logfail "$ENV environment not recognized";;
    esac
}

function init() {
    usetemp
    touchlogfile
    required_listofcommands "openssl base64 jq curl sha256sum uuidgen xmllint yq"
    recognizeenv
    export CURLOUT=`crtemp`
    #export CURLOUT=work/c.out
    required_listofvars TOKENSTORE ENV
    existfile $TOKENSTORE
}

init