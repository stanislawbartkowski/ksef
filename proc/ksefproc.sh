# ------------------------------------
# different funcs related to KSeF
# ------------------------------------

CURLOUT=curl.out

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

analizehttpcode() {
    local -r HTTP=`gethttpcode $1`
    local -r EXPECTED=$2
    logfile $1
    echo $HTTP
    [ "$HTTP" == "$EXPECTED" ] || logfail "Obtained HTTP code $HTTP  Expected HTTP code $EXPECTED"
}

getstatusexceptioncode() {
    echo `jq -r .exception.exceptionDetailList[0].exceptionCode $1`
}

getprocessingcode() {
    echo `jq -r .processingCode $1`
}

checkstatus() {
    [ $1 -eq 0 ] && return
    logfile $2
    logfail "$3"
}

# -------------------------
# actions
# -------------------------

# /api/online/Session/AuthorisationChallenge
# $1 - result
requestchallenge() {
    local -r TEMP="/tmp/c.json" 
    buildauthorizationchallengejson >$TEMP
    log "Obtaining authorization challenge"
    curl $PREFIXURL/api/online/Session/AuthorisationChallenge -d @$TEMP -v -H "Content-Type: application/json" -o $1 >$CURLOUT 2>&1
    [ $? -eq 0 ] || logfail "Failed to obtain authorization challenge"
    logfile $1
    analizehttpcode $CURLOUT 201
}

# /api/online/Session/InitToken 
# $1 - inittoken.json request file
# $2 - result 
requestinittoken() {
    log "Obtaining init token"
    curl $PREFIXURL/api/online/Session/InitToken -v  -H "Content-Type: application/octet-stream" -H "accept: application/json" -d@$1 -o $2 >$CURLOUT 2>&1
    [ $? -eq 0 ] || logfail "Failed to obtain init token"
    logfile $2
    analizehttpcode $CURLOUT 201
}

# /api/online/Session/Status
# $1 - result of the InitToken file, sessiontoken.json
# $2 - result file
requestsessionstatus() {
    log "Checking session status"
    local -r SESSIONTOKEN=`getsessiontoken $1`
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot extract session token"    
    curl $PREFIXURL/api/online/Session/Status -v -H "SessionToken: $SESSIONTOKEN" -o $2  >$CURLOUT 2>&1
    checkstatus $? $CURLOUT "Failed to verify session status" 
    logfile $2
    logfile $CURLOUT
    local -r HTTPCODE=`gethttpcode $CURLOUT`
    case $HTTPCODE in
    200) 
      local -r PROCESSINGCODE=`getprocessingcode $2`
      [[ ! -z "$PROCESSINGCODE" ]] || logfail "Cannot extract processing code" 
      [ "$PROCESSINGCODE" == "315" ] && return 0
      [ "$PROCESSINGCODE" == "200" ] && return 1
      logfail "Unrecognized processing code $PROCESSINGCODE  Expected 315 or 200"
      ;;
    400) 
        local -r ECODE=`getstatusexceptioncode $2`
        [ "$ECODE" == "21170" ] && return 1
        ;;
    esac
    logfail "Obtained HTTP code $HTTPCODE, expected 200 or 400"
}

# /api/online/Session/Terminate
# $1 - result of the InitToken file, sessiontoken.json
requestsessionterminate() {
    log "Terminating session"
    local -r SESSIONTOKEN=`getsessiontoken $1`
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot extract session token"
    local -r TEMP=`crtemp`
    curl $PREFIXURL/api/online/Session/Terminate -v -H "SessionToken: $SESSIONTOKEN" -o $TEMP  >$CURLOUT 2>&1
    checkstatus $? $CURLOUT "Failed to terminate session" 
    logfile $TEMP
    analizehttpcode $CURLOUT 200
}

# api/online/Invoice/Send
# $1 - result of the InitToken file, sessiontoken.json
# $2 - invoice XML
# $3 - result
requestinvoicesend() {
    log "Sending invoice"
    local -r SESSIONTOKEN=`getsessiontoken $1`
    [[ ! -z "$SESSIONTOKEN" ]] || logfail "Cannot extract session token"
    local -r PATTERN=patterns/invoice.json
    local -r BODY=`cat $2 | base64 -w 0`
    local -r HASH=`echo -n $BODY | openssl sha256 | base64 -w 0`
    local -r CMD="sed \"s#__HASH__#$HASH#\" $PATTERN"
    local -r CMD1="sed \"s#__INVOICE__#$BODY#\""
    eval $CMD | eval $CMD1 >3
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
    touchlogfile
    usetemp
    required_listofcommands "openssl base64 jq curl sha245sum"
    recognizeenv
}

init