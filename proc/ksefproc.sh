# ------------------------------------
# different funcs related to KSeF
# ------------------------------------
# 2023/09/24 - first commit

OK="OK"
ERROR="ERROR"

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

buildauthorizationchallengejson() {
    local -r IN=patterns/authorisationchallenge.json
    sed s"/__NIP__/$NIP/" $IN 
}

createatuhorizedtoken() {
    # assuming TIMES does not contain spaces
    local -r TIMES=$1
    # convert TIMES to epoch miliseconds
    local -r MSECS=`date -d $TIMES +%s%3N 2>>$LOGFILE`
    [[ ! -z "$MSECS" ]] || logfail "Failed while calculating mili epoch from challenge date"
    local -r PUBKEY="ksefkeys/$ENV/publicKey.pem"
    # very important: echo without -n is adding extra lf at the end which messes up the result
    #                 also  -w 0 parameters to base64, without that the string is broken into lines using lfs
    echo -n "$TOKEN|$MSECS" | openssl pkeyutl -encrypt -pubin -inkey $PUBKEY 2>>$LOGFILE | base64 -w 0
}

buildinittokenxml() {
    local -r AUTHCHALLENGE=$1
    local -r ATOKEN=`createatuhorizedtoken $2`
    [[ ! -z "$ATOKEN" ]] || logfail "Failed while creating authorization token with openssl"

    local -r IN=patterns/inittoken.xml
    # base64 can contain / but does not produce #
    # sed to replace TOKEN should be executed as eval because of spaces problem
    local -r CMD="sed \"s#__TOKEN__#$ATOKEN#\" $IN"
    eval  $CMD | sed s"/__NIP__/$NIP/" | sed s"/__CHALLENGE__/$AUTHCHALLENGE/"
    [ $? -eq 0 ] || logfail "Failed while building token with sed"
}

gettimestampfromchallenge() {
    echo `jq -r ".timestamp" $1`
}

getchallengefromchallenge() {
    echo `jq -r ".challenge" $1`
}

getsessiontoken() {
    echo `jq -r ".sessionToken.token" $1`
}


createinitxmlfromchallenge() {
    local -r TIMESTAMP=`gettimestampfromchallenge $1`
    local -r CHALLENGE=`getchallengefromchallenge $1`
    buildinittokenxml $CHALLENGE $TIMESTAMP
}

gethttpcode() {
    local -r HTTP=`grep "HTTP/1.1 " $1 | sed "s/.* \([0-9]*\) .*/\1/"`
    echo $HTTP
}

getstatusexceptioncode() {
    echo `jq -r .exception.exceptionDetailList[0].exceptionCode $1`
}

getprocessingcode() {
    echo `jq -r .processingCode $1`
}

getinvoicereference() {
    echo `jq -r .elementReferenceNumber $1`
}


# create payload for invoice/send
# $1 - < invoice XML
# $2 - > invoice/send json
createinvoicesend() {
    local -r PATTERN=patterns/invoice.json
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
analizehttpcode() {
    local -r HTTP=`gethttpcode $1`
    local -r EXPECTED=$2
    logfile $1
    if [ "$HTTP" != "$EXPECTED" ]; then
        local -r END=`getdate`
        local -r MESS="Obtained HTTP code $HTTP  Expected HTTP code $EXPECTED"
        journallog "$3" "$4" "$END" $ERROR "$MESS"
        echo "xxxxxx $5 xxxx"
        [ ! -z "$5" ] && logfile $5
        logfail "$MESS"
    fi
}

# $1 - < exist code
# $2 - < file with command output
# $3 - < Fail message
# $4 - < OP
# $5 - < BEG
checkstatus() {
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

verifyresult() {
    checkstatus $1 $2 "$4" "$5" "$6"
    analizehttpcode $2 $3 "$5" "$6" $7
    local -r END=`getdate`
    [ ! -z "$7" ] && logfile $7
    journallognocomment "$5" "$6" "$END" $OK    
}

# -------------------------
# actions
# -------------------------

# /api/online/Session/AuthorisationChallenge
# $1 - result
requestchallenge() {
    local -r TEMP=`crtemp`
    buildauthorizationchallengejson >$TEMP
    local -r BEG=`getdate`
    log "Obtaining authorization challenge"
    local -r OP="Session/AuthorisationChallenge"
    curl $PREFIXURL/api/online/Session/AuthorisationChallenge -d @$TEMP -v -H "Content-Type: application/json" -o $1 >$CURLOUT 2>&1
    verifyresult $? $CURLOUT 201 "Failed to obtain authorization challenge" "$OP" "$BEG" $1
}

# /api/online/Session/InitToken 
# $1 - inittoken.json request file
# $2 - result 
requestinittoken() {
    log "Obtaining init token"
    local -r BEG=`getdate`
    local -r OP="Session/InitToken"
    curl $PREFIXURL/api/online/Session/InitToken -v  -H "Content-Type: application/octet-stream" -H "accept: application/json" -d@$1 -o $2 >$CURLOUT 2>&1
    verifyresult $? $CURLOUT 201 "Failed to obtain init token" "$OP" "$BEG" $2
}

# /api/online/Session/Status
# $1 - result of the InitToken file, sessiontoken.json
# $2 - result file
requestsessionstatus() {
    log "Checking session status"
    local -r BEG=`getdate`
    local -r OP="Session/Status"
    local -r SESSIONTOKEN=`getsessiontoken $1`
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot extract session token"    
    curl $PREFIXURL/api/online/Session/Status -v -H "SessionToken: $SESSIONTOKEN" -o $2  >$CURLOUT 2>&1
    checkstatus $? $CURLOUT "Failed to verify session status" "$OP" "$BEG"
    local -r END=`getdate`
    logfile $2
    logfile $CURLOUT
    local -r HTTPCODE=`gethttpcode $CURLOUT`
    case $HTTPCODE in
    200) 
      local -r PROCESSINGCODE=`getprocessingcode $2`
      [[ ! -z "$PROCESSINGCODE" ]] || logfail "Cannot extract processing code" 
      [ "$PROCESSINGCODE" == "315" ] && return 0
      [ "$PROCESSINGCODE" == "200" ] && return 1
      local -r MESS="Unrecognized processing code $PROCESSINGCODE  Expected 315 or 200"
      journallog "$OP" "$BEG" "$END" $ERROR "$MESS"
      logfail "$MESS"
      ;;
    400) 
        local -r ECODE=`getstatusexceptioncode $2`
        [ "$ECODE" == "21170" ] && return 1
        ;;
    esac
    local -r MESS="Obtained HTTP code $HTTPCODE, expected 200 or 400"
    journallog "$OP" "$BEG" "$END" $ERROR "$MESS"
    logfail "$MESS"
}

# /api/online/Session/Terminate
# $1 - result of the InitToken file, sessiontoken.json
requestsessionterminate() {
    log "Terminating session"
    local -r OP="Session/Terminate"
    local -r BEG=`getdate`
    local -r SESSIONTOKEN=`getsessiontoken $1`
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot extract session token"
    local -r TEMP=`crtemp`
    curl $PREFIXURL/api/online/Session/Terminate -v -H "SessionToken: $SESSIONTOKEN" -o $TEMP  >$CURLOUT 2>&1
    verifyresult $? $CURLOUT 200 "Failed to terminate session" "$OP" "$BEG" $TEMP
}

# api/online/Invoice/Send
# $1 - < result of the InitToken file, sessiontoken.json
# $2 - > request invoice/send 
# $3 - > invoice status
directrequestinvoicesend() {
    log "Sending invoice"
    local -r OP="Invoice/Send"
    local -r BEG=`getdate`
    local -r SESSIONTOKEN=`getsessiontoken $1`
    local -r OUT=$3
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot extract session token"
    # Important: PUT
    curl -X PUT $PREFIXURL/api/online/Invoice/Send -v  -H "Content-Type: application/json" -H "accept: application/json" -H "SessionToken: $SESSIONTOKEN" -d@$2 -o $OUT >$CURLOUT 2>&1
    verifyresult $? $CURLOUT 202 "Failed to send invoice" "$OP" "$BEG" $OUT
}


# api/online/Invoice/Send
# $1 - < result of the InitToken file, sessiontoken.json
# $2 - < invoice XML
# $3 - > request invoice/send
# $4 - > invoice status
requestinvoicesend() {
    createinvoicesend $2 $3
    directrequestinvoicesend $1 $3 $4
}


# $1 - < result of the InitToken file, sessiontoken.json
# $2 - < invoice reference number
# $3 - > response
requestreferencestatus() {
    log "Checking invoice reference status $2"
    local -r OP="Invoice/Status"
    local -r BEG=`getdate`
    local -r SESSIONTOKEN=`getsessiontoken $1`
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot extract session token"    
    curl $PREFIXURL/api/online/Invoice/Status/$2 -v -H "SessionToken: $SESSIONTOKEN" -o $3  >$CURLOUT 2>&1
    verifyresult $? $CURLOUT 200 "Failed to verify invoice reference status" "$OP" "$BEG" $3
}

# /online/Invoice/Get/{KSeFReferenceNumber}
# $1 < sessiontoken.json
# $2 < ksief invoice reference number
# $3 - > response
requestinvoiceget() {
    log "Get invoice using ksef reference number $2"
    local -r SESSIONTOKEN=`getsessiontoken $1`
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot extract session token"    
    curl $PREFIXURL/api/online/Invoice/Get/$2 -v -H "SessionToken: $SESSIONTOKEN" -o $3  >$CURLOUT 2>&1
    checkstatus $? $CURLOUT "Failed to get invoice by reference number" 
    logfile $3
    logfile $CURLOUT
    analizehttpcode $CURLOUT 200
}

# /online/Query/Invoice/Sync
# $1 < sessiontoken.json
# $2 < queryjson
# $3 - > response
requestinvoicesync() {
    log "Running Query/Invoice/Sync"
    local -r SESSIONTOKEN=`getsessiontoken $1`
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot run query"    
    curl "$PREFIXURL/api/online/Query/Invoice/Sync/?PageSize=10&PageOffset=0" -H "Content-Type: application/vnd.v2+json" -H "SessionToken: $SESSIONTOKEN" -d @$2 -o $3  >$CURLOUT 2>&1
    logfile $3
    logfile $CURLOUT
    analizehttpcode $CURLOUT 200
}

# /online/Query/Invoice/Async/Init
# $1 < sessiontoken.json
# $2 < queryjson
# $3 > response
requestinvoiceasyncinit() {
    log "Running Query/Invoice/Sync"
    local -r SESSIONTOKEN=`getsessiontoken $1`
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot run query"    
    curl "$PREFIXURL/api/online/Query/Invoice/AsyncInit" -v -H "Content-Type: application/vnd.v2+json" -H "SessionToken: $SESSIONTOKEN" -d @$2 -o $3  >$CURLOUT 2>&1
    logfile $3
    logfile $CURLOUT
    analizehttpcode $CURLOUT 202
}

# ----------------------------------
# operation
# ----------------------------------

# invoice send and get ksef reference number
# $1 < sessiontoken.json
# $2 < invoice
# $3 > reference status

requestinvoicesendandreference() {
    local -r TEMP=`crtemp`
    local -r ITEMP=`crtemp`
    requestinvoicesend $1 $2 $TEMP $ITEMP
    REFERENCENUMBER=`getinvoicereference $ITEMP`
    local -r OP="Invoice/GetKsefReference"
    local -r BEG=`getdate`
    for i in {1..3} 
    do
        sleep 5
        requestreferencestatus $1 $REFERENCENUMBER $3
        local PCODE=`getprocessingcode $3`
        [ $PCODE -eq 200 ] && return 0
        [ $PCODE -ne 310 ] && break
        log "Invoice still preprocessing, wait 5 sec and retry"
    done
    local -r END=`getdate`
    journallog "$OP" "$BEG" "$END" $ERROR "Cannot extract reference number"
    logfail "Cannot extract reference number"
}

# -------------------------------------
# init
# -------------------------------------

recognizeenv() {
    case $ENV in
      test) PREFIXURL='https://ksef-test.mf.gov.pl';;
      *) logfail "$ENV environment not recognized";;
    esac

}

init () {
    usetemp
    touchlogfile
    required_listofcommands "openssl base64 jq curl sha256sum uuidgen xmllint"
    recognizeenv
    export CURLOUT=`crtemp`
}

init