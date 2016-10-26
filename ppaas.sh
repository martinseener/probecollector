#!/usr/bin/env bash

# Pingdom Probes as a Service
# (c) 2016 by Martin Seener (martin@sysorchestra.com)

# Configuration

## Your Cloudflare Login E-Mail address
CFEMAIL="user@example.com"
## Your Cloudflare API Key (can be found in "My Settings" -> "Global API Key")
CFAPIKEY="6822e6be06bfea43cf3cc303154f86"
## Your Zone/Domain you want to manage
CFZONE="example.com"
## The desired record/subdomain for the pingdomprobes entries
CFPPDOMAIN="pingdomprobes.example.com"
## Default RR-TTL (for A and AAAA Records). Pingdoms default TTL is 300s, so we will adapt this here
RRTTL=300
## Enable Syslog logging?
DOLOG=true
## Also output log to STDOUT (useful when run first to quickly see any problems)
INTERACTIVELOG=true

# Configuration End

VERSION="1.0.0"

# Prints help
print_help() {
    echo "PPaaS"
    echo "$VERSION - (c)2016 by Martin Seener"
    echo ""
    echo -e "\e[00;31mUsage: $0\e[00m"
    echo ""
    echo "Description: PPaaS (Pingdom Probes as a Service) gets all IPv4 and IPv6 Probe Server IP's from Pingdom and creates a single DNS Name with multiple A/AAAA-RR's"
    echo "out of them, so you can use just a single DNS Name for whitelisting purposes without ever have to manually add/remove"
    echo "them anymore. This is helpful for example when using IP-Whitelisting with the Sophos UTM. You just have to use a DNS Group"
    echo "and you're done."
    echo ""
}

# Logging method
log() {
    if ${DOLOG}; then
        logger -t "PPaaS[$$]" "$1"
        if ${INTERACTIVELOG}; then
            echo "PPaaS[$$]: $1"
        fi
    fi
}

# Embedded Dependency: JSON.sh from https://github.com/dominictarr/JSON.sh
json_sh() {
    throw() {
        echo "$*" >&2
        exit 1
    }

    BRIEF=0
    LEAFONLY=0
    PRUNE=0
    NO_HEAD=0
    NORMALIZE_SOLIDUS=0

    usage() {
        echo
        echo "Usage: JSON.sh [-b] [-l] [-p] [-s] [-h]"
        echo
        echo "-p - Prune empty. Exclude fields with empty values."
        echo "-l - Leaf only. Only show leaf nodes, which stops data duplication."
        echo "-b - Brief. Combines 'Leaf only' and 'Prune empty' options."
        echo "-n - No-head. Do not show nodes that have no path (lines that start with [])."
        echo "-s - Remove escaping of the solidus symbol (straight slash)."
        echo "-h - This help text."
        echo
    }

    parse_options() {
        set -- "$@"
        local ARGN=$#
        while [ "$ARGN" -ne 0 ]
        do
            case $1 in
                -h) usage
                    exit 0
                    ;;
                -b) BRIEF=1
                    LEAFONLY=1
                    PRUNE=1
                    ;;
                -l) LEAFONLY=1
                    ;;
                -p) PRUNE=1
                    ;;
                -n) NO_HEAD=1
                    ;;
                -s) NORMALIZE_SOLIDUS=1
                    ;;
                ?*) echo "ERROR: Unknown option."
                    usage
                    exit 0
                    ;;
            esac
            shift 1
            ARGN=$((ARGN-1))
        done
    }

    awk_egrep () {
        local pattern_string=$1

        gawk '{
            while ($0) {
                start=match($0, pattern);
                token=substr($0, start, RLENGTH);
                print token;
                $0=substr($0, start+RLENGTH);
            }
        }' pattern="$pattern_string"
    }

    tokenize () {
        local GREP
        local ESCAPE
        local CHAR

        if echo "test string" | egrep -ao --color=never "test" >/dev/null 2>&1
        then
            GREP='egrep -ao --color=never'
        else
            GREP='egrep -ao'
        fi

        if echo "test string" | egrep -o "test" >/dev/null 2>&1
        then
            ESCAPE='(\\[^u[:cntrl:]]|\\u[0-9a-fA-F]{4})'
            CHAR='[^[:cntrl:]"\\]'
        else
            GREP=awk_egrep
            ESCAPE='(\\\\[^u[:cntrl:]]|\\u[0-9a-fA-F]{4})'
            CHAR='[^[:cntrl:]"\\\\]'
        fi

        local STRING="\"$CHAR*($ESCAPE$CHAR*)*\""
        local NUMBER='-?(0|[1-9][0-9]*)([.][0-9]*)?([eE][+-]?[0-9]*)?'
        local KEYWORD='null|false|true'
        local SPACE='[[:space:]]+'

        # Force zsh to expand $A into multiple words
        local is_wordsplit_disabled=$(unsetopt 2>/dev/null | grep -c '^shwordsplit$')
        if [ $is_wordsplit_disabled != 0 ]; then setopt shwordsplit; fi
        $GREP "$STRING|$NUMBER|$KEYWORD|$SPACE|." | egrep -v "^$SPACE$"
        if [ $is_wordsplit_disabled != 0 ]; then unsetopt shwordsplit; fi
    }

    parse_array () {
        local index=0
        local ary=''
        read -r token
        case "$token" in
            ']') ;;
            *)
                while :
                do
                    parse_value "$1" "$index"
                    index=$((index+1))
                    ary="$ary""$value"
                    read -r token
                    case "$token" in
                        ']') break ;;
                        ',') ary="$ary," ;;
                        *) throw "EXPECTED , or ] GOT ${token:-EOF}" ;;
                    esac
                read -r token
            done
            ;;
        esac
        [ "$BRIEF" -eq 0 ] && value=$(printf '[%s]' "$ary") || value=
        :
    }

    parse_object () {
        local key
        local obj=''
        read -r token
        case "$token" in
            '}') ;;
            *)
            while :
            do
                case "$token" in
                    '"'*'"') key=$token ;;
                    *) throw "EXPECTED string GOT ${token:-EOF}" ;;
                    esac
                    read -r token
                    case "$token" in
                        ':') ;;
                        *) throw "EXPECTED : GOT ${token:-EOF}" ;;
                    esac
                    read -r token
                    parse_value "$1" "$key"
                    obj="$obj$key:$value"
                    read -r token
                    case "$token" in
                        '}') break ;;
                        ',') obj="$obj," ;;
                        *) throw "EXPECTED , or } GOT ${token:-EOF}" ;;
                    esac
                    read -r token
            done
            ;;
        esac
        [ "$BRIEF" -eq 0 ] && value=$(printf '{%s}' "$obj") || value=
        :
    }

    parse_value () {
        local jpath="${1:+$1,}$2" isleaf=0 isempty=0 print=0
        case "$token" in
            '{') parse_object "$jpath" ;;
            '[') parse_array  "$jpath" ;;
            # At this point, the only valid single-character tokens are digits.
            ''|[!0-9]) throw "EXPECTED value GOT ${token:-EOF}" ;;
            *) value=$token
            # if asked, replace solidus ("\/") in json strings with normalized value: "/"
            [ "$NORMALIZE_SOLIDUS" -eq 1 ] && value=$(echo "$value" | sed 's#\\/#/#g')
            isleaf=1
            [ "$value" = '""' ] && isempty=1
            ;;
        esac
        [ "$value" = '' ] && return
        [ "$NO_HEAD" -eq 1 ] && [ -z "$jpath" ] && return

        [ "$LEAFONLY" -eq 0 ] && [ "$PRUNE" -eq 0 ] && print=1
        [ "$LEAFONLY" -eq 1 ] && [ "$isleaf" -eq 1 ] && [ $PRUNE -eq 0 ] && print=1
        [ "$LEAFONLY" -eq 0 ] && [ "$PRUNE" -eq 1 ] && [ "$isempty" -eq 0 ] && print=1
        [ "$LEAFONLY" -eq 1 ] && [ "$isleaf" -eq 1 ] && \
            [ $PRUNE -eq 1 ] && [ $isempty -eq 0 ] && print=1
        [ "$print" -eq 1 ] && printf "[%s]\t%s\n" "$jpath" "$value"
        :
    }

    parse () {
        read -r token
        parse_value
        read -r token
        case "$token" in
            '') ;;
            *) throw "EXPECTED EOF GOT $token" ;;
        esac
    }

    if ([ "$0" = "$BASH_SOURCE" ] || ! [ -n "$BASH_SOURCE" ]);
    then
        parse_options "$@"
        tokenize | parse
    fi
}

# Fetch Probes and record entries
fetch_probes() {
    if curl -s -X GET "https://my.pingdom.com/probes/ipv4" | grep 200 >/dev/null 2>&1; then
        PINGDOMIPV4PROBES=( $(curl -s -X GET "https://my.pingdom.com/probes/ipv4") )
    else
        log "ERROR: Unable to reach https://my.pingdom.com/probes/ipv4!"
        exit 1
    fi
    if curl -s -X GET "https://my.pingdom.com/probes/ipv6" | grep 200 >/dev/null 2>&1; then
        PINGDOMIPV6PROBES=( $(curl -s -X GET "https://my.pingdom.com/probes/ipv6") )
    else
        log "ERROR: Unable to reach https://my.pingdom.com/probes/ipv6!"
        exit 1
    fi
}

update_records() {
    # TODO: Add Logging and error handling!
    # Now we will remove all fetched RR's (A and AAAA) if there are any
    if [ "${ALLRRS}" == '' ]; then
        log "INFO: No RR's found. We will continue adding them."
    else
        for CURRENTRR in "${ALLRRS[@]}"; do
            DELRUN=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${CFZONEID}/dns_records/${CURRENTRR}" -H "X-Auth-Email: ${CFEMAIL}" -H "X-Auth-Key: ${CFAPIKEY}" -H "Content-Type: application/json")
            if [[ "${DELRUN}" == *"\"success\":false"* ]]; then
                log "ERROR: Deleting ${CURRENTRR} failed. Stopping."
                exit 1
            else
                log "INFO: Deleting ${CURRENTRR} succeeded."
            fi
        done
    fi

    # We will add all A-Probes now, followed by AAAA-Probes
    for APROBE in "${PINGDOMIPV4PROBES[@]}"; do
        AUPDATE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CFZONEID}/dns_records" -H "X-Auth-Email: ${CFEMAIL}" -H "X-Auth-Key: ${CFAPIKEY}" -H "Content-Type: application/json" --data "{\"type\":\"A\",\"name\":\"${CFPPDOMAIN}\",\"content\":\"${APROBE}\",\"ttl\":${RRTTL}}")
        if [[ "${AUPDATE}" == *"\"success\":false"* ]]; then
            log "ERROR: Adding ${AUPDATE} failed. Stopping."
            exit 1
        else
            log "INFO: Adding ${AUPDATE} succeeded."
        fi
    done
    for QAPROBE in "${PINGDOMIPV6PROBES[@]}"; do
        QAUPDATE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CFZONEID}/dns_records" -H "X-Auth-Email: ${CFEMAIL}" -H "X-Auth-Key: ${CFAPIKEY}" -H "Content-Type: application/json" --data "{\"type\":\"AAAA\",\"name\":\"${CFPPDOMAIN}\",\"content\":\"${QAPROBE}\",\"ttl\":${RRTTL}}")
        if [[ "${QAUPDATE}" == *"\"success\":false"* ]]; then
            log "ERROR: Adding ${QAUPDATE} failed. Stopping."
            exit 1
        else
            log "INFO: Adding ${QAUPDATE} succeeded."
        fi
    done
}

case "$1" in
    --help|-h)
        print_help
        exit 0;;
    *)
        CFZONEID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${CFZONE}" -H "X-Auth-Email: ${CFEMAIL}" -H "X-Auth-Key: ${CFAPIKEY}" -H "Content-Type: application/json" | json_sh -b | grep '0,"id"' | cut -d'"' -f6 )
        ALLRRS=( $(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CFZONEID}/dns_records?name=${CFPPDOMAIN}&page=1&per_page=1000&order=type&direction=desc&match=all" -H "X-Auth-Email: ${CFEMAIL}" -H "X-Auth-Key: ${CFAPIKEY}" -H "Content-Type: application/json" | json_sh -b | grep "\"id" | cut -d'"' -f6) )
        fetch_probes
        update_records
        exit 0;;
esac
