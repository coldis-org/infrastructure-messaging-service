#!/bin/sh

DEBUG=true
INPUT_FILE="/local/messaging-services"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Missing file"
    exit 1
fi

while IFS= read -r LINE || [ -n "$LINE" ]; do
    LINE=$(echo "$LINE" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$LINE" ] && continue

    CREDENTIALS=""
    ADDR=""

    for FIELD in $LINE; do
        case "$FIELD" in
        credentials=*)
            CREDENTIALS="${FIELD#credentials=}"
            ;;
        addr=*)
            ADDR="${FIELD#addr=}"
            ;;
        esac
    done

    USER=$(echo "$CREDENTIALS" | sed 's/:.*//')
    PWD=$(echo "$CREDENTIALS" | sed 's/.*://')

    ${DEBUG} && echo "USER=$USER"
    ${DEBUG} && echo "PWD=$PWD"
    ${DEBUG} && echo "ADDR=$ADDR"

    artemis_add_router \
        -u ${USER} -p ${PWD} \
        -c ${USER} -a ${ADDR} \
        -r ${USER} \
        
done < "$INPUT_FILE"
