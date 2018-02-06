#!/usr/bin/env bash

# Pingdom Probes as a Service
# (c) 2016 - 2017 by Martin Seener (martin@sysorchestra.com)

# Load Config and Libraries
source "$(dirname "$0")/config/*"
source "$(dirname "$0")/lib/*"

VERSION="1.1.0"

# Prints help
print_help() {
    echo "PPaaS"
    echo "${VERSION} - (c) 2016 - 2017 by Martin Seener (martin@sysorchestra.com)"
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

# Check Cloudflare API availablility
cloudflare_check_api_availability() {
    if curl -s -X GET "https://api.cloudflare.com/client/v4/ips" | grep "success\":true" >/dev/null 2>&1; then
        log "INFO: Cloudflare API v4 reachable."
    else
        log "ERROR: Cloudflare API v4 unreachable. Aborting."
    fi
}

# Get Cloudflare Zone-ID
cloudflare_get_zone_id() {
    export CFZONEID
    CFZONEID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${CFZONE}" -H "X-Auth-Email: ${CFEMAIL}" -H "X-Auth-Key: ${CFAPIKEY}" -H "Content-Type: application/json" | json_sh -b | grep '0,"id"' | cut -d'"' -f6 )
}

# Get all RR's from Cloudflare
cloudflare_get_all_rr() {
    export ALLRRS
    ALLRRS=( $(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CFZONEID}/dns_records?name=${CFPPDOMAIN}&page=1&per_page=1000&order=type&direction=desc&match=all" -H "X-Auth-Email: ${CFEMAIL}" -H "X-Auth-Key: ${CFAPIKEY}" -H "Content-Type: application/json" | json_sh -b | grep "\"id" | cut -d'"' -f6) )
}

# Fetch Probes and record entries
fetch_probes() {
    if curl -s -I "https://my.pingdom.com/probes/ipv4" | grep "200 OK" >/dev/null 2>&1; then
        PINGDOMIPV4PROBES=( $(curl -s -X GET "https://my.pingdom.com/probes/ipv4") )
    else
        log "ERROR: Unable to reach https://my.pingdom.com/probes/ipv4!"
        exit 1
    fi
    if curl -s -I "https://my.pingdom.com/probes/ipv6" | grep "200 OK" >/dev/null 2>&1; then
        PINGDOMIPV6PROBES=( $(curl -s -X GET "https://my.pingdom.com/probes/ipv6") )
    else
        log "ERROR: Unable to reach https://my.pingdom.com/probes/ipv6!"
        exit 1
    fi
}

update_records() {
    # Now we will remove all fetched RR's (A and AAAA) if there are any
    if [[ "${ALLRRS[@]}" == '' ]]; then
        log "INFO: No RR's found. We will continue adding them."
    else
        # Remove any RR
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
            log "ERROR: Adding ${APROBE} failed. Stopping."
            exit 1
        else
            log "INFO: Adding ${APROBE} succeeded."
        fi
    done
    for QAPROBE in "${PINGDOMIPV6PROBES[@]}"; do
        QAUPDATE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CFZONEID}/dns_records" -H "X-Auth-Email: ${CFEMAIL}" -H "X-Auth-Key: ${CFAPIKEY}" -H "Content-Type: application/json" --data "{\"type\":\"AAAA\",\"name\":\"${CFPPDOMAIN}\",\"content\":\"${QAPROBE}\",\"ttl\":${RRTTL}}")
        if [[ "${QAUPDATE}" == *"\"success\":false"* ]]; then
            log "ERROR: Adding ${QAPROBE} failed. Stopping."
            exit 1
        else
            log "INFO: Adding ${QAPROBE} succeeded."
        fi
    done

    # When we got here without exiting, the script obviously succeeded, so we can write a status update
    {
        date +%s
    } > "${STATUSFILE}"
}

case "$1" in
    --help|-h)
        print_help
        exit 0;;
    *)
        cloudflare_check_api_availability
        fetch_probes
        update_records
        exit 0;;
esac
