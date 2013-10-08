#!/bin/bash

HOST=
PORT=6379
MASTER_HOST=
MASTER_PORT=6379
SERVICESTATE=
SERVICESTATETYPE=
SERVICEATTEMPT=

SCRIPT=redis-replication-changer.rb
TIMEOUT=10
HAS_SCRIPT=0

MAIL=0
MAIL_CMD=$(which mail)
MAIL_TO=root
MAIL_FROM=redis-handler
MAIL_SUBJECT="Redis slave failure event handler"

EXIT_OK=0
EXIT_WARNING=1
EXIT_CRITICAL=2
EXIT_UNKNOWN=3

while getopts ":h:p:s:t:a:mf:r:M:P:S:" OPT
do
    case $OPT in
        h)
            HOST=$OPTARG
        ;;
        p)
            PORT=$OPTARG
        ;;
        M)
            MASTER_HOST=$OPTARG
        ;;
        P)
            MASTER_PORT=$OPTARG
        ;;
        s)
            SERVICESTATE=$OPTARG
        ;;
        t)
            SERVICESTATETYPE=$OPTARG
        ;;
        a)
            SERVICEATTEMPT=$OPTARG
        ;;
        m)
            MAIL=1
        ;;
        f)
            MAIL_FROM=$OPTARG
        ;;
        r)
            MAIL_TO=$OPTARG
        ;;
        S)
            SCRIPT=$OPTARG
        ;;
        \?)
            echo "Option: -$OPT requires an argument !"
        ;;
        *)
            echo "Unknown option: -$OPTARG !"
        ;;
    esac
done

function quit {
    echo $1

    if [[ $MAIL == 1 ]]
    then
        if [[ $HAS_SCRIPT  == 1 ]]
        then
           ADDITIONAL_INFO=$($SCRIPT -c info -h $HOST -p $PORT -t $TIMEOUT)
        else
           ADDITIONAL_INFO="N/A"
        fi

        echo -e "$1\r\nAdditional info:\r\n$ADDITIONAL_INFO" | $MAIL_CMD -s "encoding=utf8" -r $MAIL_FROM -s "$MAIL_SUBJECT" $MAIL_TO
    fi
    exit $2
}

if [[ ! -f $SCRIPT ]]
then
    quit "$SCRIPT is not a file!" $EXIT_UNKNOWN
elif [[ ! -x  $SCRIPT ]]
then
    quit "$SCRIPT is not executable" $EXIT_UNKNOWN
else
    HAS_SCRIPT=1
fi

if [[ "$SERVICESTATETYPE" == "HARD" && "$SERVICESTATE" == "CRITICAL" ]]
then
    OUT=$($SCRIPT -c set -h $HOST -p $PORT -r slave -m "$MASTER_HOST:$MASTER_PORT" -t $TIMEOUT)

    if [[ $? == 0 ]]
    then
        quit "All OK, handler output: $OUT" $EXIT_OK
    else
        quit "Failed, handler output: $OUT" $EXIT_CRITICAL
    fi
fi

exit 0
