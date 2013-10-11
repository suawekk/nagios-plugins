#!/bin/bash

################################################################################
# Nagios outdated gems check
#
# Author: suawekk <suawekk+github@gmail.com>
#
# Synopsis:
# Checks for outdates gems
################################################################################


#OK exit code
EXIT_OK=0

#Warning exit code
EXIT_WARN=1

#Critical exit code
EXIT_CRIT=2

#Unknown exit code
EXIT_WTF=3

#Thresholds
THRESHOLD_WARNING=0
THRESHOLD_CRITICAL=0

#Verbosity
VERBOSE=0

help(){
    echo "Supported parameters:"
    echo "-h : shows help"
    echo "-w warning-threshold"
    echo "-c critical-threshold"
    echo "-v verbose mode"
}

out(){
    echo -e "CHECK_GEM $1"
    exit $2
}

GEM=$(which gem)

if [[ -z "$GEM" ]]
then
    out "No gem command found!" $EXIT_WTF
fi

WC=$(which wc)

if [[ -z "$WC" ]]
then
    out "No wc command found!" $EXIT_WTF
fi

while getopts ":hw:c:v" OPT
do
    case $OPT in
        h)
            help
            exit $EXIT_WTF
        ;;
        w)
            THRESHOLD_WARNING=$OPTARG
        ;;
        v)
            VERBOSE=1
        ;;
        c)
            THRESHOLD_CRITICAL=$OPTARG
        ;;
        \:)
            out "Option: -${OPTARG} requires an argument" $EXIT_WTF
        ;;

        \?)
            out "Unrecognized parameter: -${OPTARG}" $EXIT_WTF
        ;;
    esac
done

OUT=$($GEM outdated)
CODE=$?

if [[ $CODE -eq 0 ]]
then
    COUNT=$(echo "$OUT" | $WC -l) 

    if (( $VERBOSE == 1 )) 
    then
        ADDITIONAL_INFO=",gem path: $GEM"
        if (( $COUNT > 0 ))
        then
            ADDITIONAL_INFO+=",gems needing update:\n$OUT"
        fi
    fi

    if (( $THRESHOLD_CRITICAL > 0 && $COUNT >= $THRESHOLD_CRITICAL))
    then
        out "CRITICAL: $COUNT gems need updating $ADDITIONAL_INFO" $EXIT_CRIT
    elif (( $THRESHOLD_WARNING > 0 && $COUNT >= $THRESHOLD_WARNING))
    then
        out "WARNING: $COUNT gems need updating $ADDITIONAL_INFO" $EXIT_WARN
    else
        out "OK: $COUNT gems need updating $ADDITIONAL_INFO" $EXIT_OK
    fi
else
    out "$CMD exited with nonzero status: $CODE" $EXIT_WTF
fi

