#!/bin/bash

################################################################################
# Nagios SVN authz validation check
#
# Author: suawekk <suawekk+github@gmail.com>
#
# Synopsis:
# Wraps svnauthz-validate command so Nagios can now determine whether 
# specific svn repository authz file is valid so users can (hopefully) login,
# commit etc.
################################################################################


#OK exit code
EXIT_OK=0

#Warning exit code
EXIT_WARN=1

#Critical exit code
EXIT_CRIT=2

#Unknown exit code
EXIT_WTF=3

help(){
    echo "Supported parameters:"
    echo "-h : shows help"
    echo "-f FILE : file to validate"
}

SVNAUTHZ_VALIDATE=svnauthz-validate

while getopts ":hf:" OPT
do
    case $OPT in
        h)
            help
            exit $EXIT_WTF
        ;;
        f)
            FILE=$OPTARG
        ;;
        :)
            echo "Option: -${OPTARG} requires an argument"
            exit $EXIT_WTF
        ;;

        \?)
            echo "Unrecognized parameter: -${OPTARG}"
            exit $EXIT_WTF
        ;;
    esac
done


if [[ ! -f "$FILE" ]]
then
    echo "File $FILE is not readable!"
    exit $EXIT_CRIT
fi

OUT=$($SVNAUTHZ_VALIDATE $FILE 2>&1)
CODE=$?

if [[ $CODE -eq 0 ]]
then
    echo "CHECK_SVNAUTHZ_VALIDATE OK: File $FILE is valid"
    exit $EXIT_OK
else
    echo "CHECK_SVNAUTHZ_VALIDATE CRITICAL: File $FILE is not valid svnauthz, $CMD code: $CODE, output: $OUT"
    exit $EXIT_CRIT
fi

