#!/usr/bin/env bash

# PPaaS Configuration File

## Your Cloudflare Login E-Mail address
CFEMAIL="user@example.com"
## Your Cloudflare API Key (can be found in "My Settings" -> "Global API Key")
CFAPIKEY="6822e6be06bfea43cf3cc303154f86"
## Your Zone/Domain you want to manage
CFZONE="example.com"
## The desired record/subdomain for the pingdomprobes entries
CFPPDOMAIN="pingdomprobes.example.com"
## Default RR-TTL (for A and AAAA Records). Pingdoms default TTL is 300s, so we will adapt this here
RRTTL=3600
## Enable Syslog logging?
DOLOG=true
## Also output log to STDOUT (useful when run first to quickly see any problems)
INTERACTIVELOG=true
## On successful execution write the unix timestamp into a status file
STATUSFILE=/tmp/ppaas.status
