#!/usr/bin/env python
# # -*- coding: utf-8 -*-

"""
Pingdomes Probes as a Service provides easy management of
Pingdom Probes (A/AAAA) on your Cloudflare Domain as a single
DNS Entry for easier usage for Whitelisting-purposes.
It also works as a Check-Tool with Nagios-compatible output.
"""


import sys
import argparse
import requests
import subprocess
import time
import re
import CloudFlare


__author__ = 'Martin Seener'
__copyright__ = 'Copyright 2018, Martin Seener'
__license__ = 'MIT'
__version__ = '2.0.0'
__maintainer__ = 'Martin Seener'
__email__ = 'martin@sysorchestra.com'
__status__ = 'Production'


def version():
    """Returns the current version, copyright and license"""
    return 'PPaaS ' + __version__ + ' - ' + __copyright__ + \
        ' - ' + 'License: ' + __license__


def validate_fqdn(fqdn):
    """Checks a given string if it's a valid FQDN"""
    fqdn_validation = re.match(
        '(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63}$)',
        fqdn,
    )
    if fqdn_validation is None:
        return False
    else:
        return True


def pingdom_fetch_probes(proto):
    """Fetches all Pingdom probes from the given protocol"""
    try:
        resp = requests.get('https://my.pingdom.com/probes/' + proto)
    except Exception as e:
        return 'Failed to get {} probes from Pingdom with error: {}'.format(
            proto,
            e,
        ), True
    # Get back a list of IP's and filter out empty lines
    iplist = filter(lambda x: x != '', resp.text.split("\n"))
    return iplist, False


def cf_get_zone_id(cf, domain):
    """Queries the Cloudflare Zone-ID from the given domain"""
    zone_name = domain.split('.', 1)[1]
    try:
        params = {'name': zone_name}
        raw_results = cf.zones.get(params=params)
    except CloudFlare.exceptions.CloudFlareAPIError as e:
        return '/zones {} {} - api call failed'.format(e, e), True
    except Exception as e:
        return '/zones.get - {} - api call failed'.format(e), True

    zones = raw_results['result']

    if len(zones) == 0:
        return '/zones.get - {} - zone not found'.format(
            zone_name,
        ), True

    if len(zones) != 1:
        return '/zones.get - {} - api call returned {} items'.format(
            zone_name,
            len(zones),
        ), True

    return zones[0]['id'], False


def cf_fetch_rr(cf, domain, zone_id, type):
    """Fetches all DNS Resource Records from the Cloudflare Domain"""
    page_number = 0
    cf_records = []
    while True:
        page_number += 1
        try:
            raw_results = cf.zones.dns_records.get(
                zone_id,
                params={
                    'name': domain,
                    'type': type,
                    'per_page': 100,
                    'page': page_number,
                },
            )
        except CloudFlare.exceptions.CloudFlareAPIError as e:
            return 'GET /zones/{}/dns_records {}'.format(zone_id, e), True

        cf_records += raw_results['result']

        total_pages = raw_results['result_info']['total_pages']
        if total_pages == 0:
            total_pages += 1
        if page_number == total_pages:
            break

    return cf_records, False


def cf_add_txt_rr(cf, domain, zone_id):
    """
    Adds a TXT Record with the current timestamp,
    so one can check if the update was running
    """
    current_timestamp = int(time.time())

    # Get the rr_id for the TXT record first, if there is one
    resp, e = cf_fetch_rr(cf, domain, zone_id, 'TXT')
    if e is False:
        cf_txt_records = resp
    else:
        print resp
        sys.exit(1)
    if len(cf_txt_records) >= 1:
        """
        If there is one or more records (should be one)
        we will delete them all and recreate a new one.
        """
        for cf_txt_dict in cf_txt_records:
            try:
                cf.zones.dns_records.delete(zone_id, cf_txt_dict['id'])
            except CloudFlare.exceptions.CloudFlareAPIError as e:
                return 'Failed: DELETE /zones/{}/dns_records/{} {} {}'.format(
                    zone_id,
                    cf_txt_dict['id'],
                    e,
                    e,
                )

    # Obviously there is none (anymore), so let us create a new one.
    txt_rr = {
        'name': domain.split('.', 1)[0],
        'type': 'TXT',
        'content': str(current_timestamp),
        'ttl': 120,
    }

    try:
        cf.zones.dns_records.post(zone_id, data=txt_rr)
    except CloudFlare.exceptions.CloudFlareAPIError as e:
        return 'Failed: POST /zones/{}/dns_records {} {}'.format(
            zone_id,
            e,
            e,
        )
    return True


def cf_del_rr(cf, zone_id, rr):
    """Deletes a DNS Resource Record from Cloudflare"""
    try:
        cf.zones.dns_records.delete(zone_id, rr)
    except CloudFlare.exceptions.CloudFlareAPIError as e:
        return 'Failed: DELETE /zones/{}/dns_records/{} {} {}'.format(
            zone_id,
            rr,
            e,
            e,
        )
    return True


def cf_add_rr(cf, zone_id, domain, type, content, ttl=300, proxied=False):
    """Adds a DNS Resource Record to Cloudflare"""
    new_rr = {
        'name': domain.split('.', 1)[0],
        'type': type,
        'content': content,
        'ttl': ttl,
        'proxied': proxied,
    }
    try:
        cf.zones.dns_records.post(zone_id, data=new_rr)
    except CloudFlare.exceptions.CloudFlareAPIError as e:
        return 'POST /zones/{}/dns_records {} {} - api call failed'.format(
            zone_id,
            e,
            e,
        )
    return True


def check_domain(domain, warning, critical):
    """
    Checks if the domain has been updated recently
    and outputs the result in a Nagios-compatible manner
    """
    current_timestamp = int(time.time())
    resp = subprocess.check_output(
        ['dig', 'TXT', domain, '+short']
    ).rstrip("\n").strip('"')
    if isinstance(resp, str):
        try:
            resp = int(resp)
        except Exception:
            print 'UNKNOWN - Domain does not provide a valid TXT record.'
            sys.exit(3)
    if isinstance(warning, int) and isinstance(critical, int):
        if (current_timestamp - resp) >= critical:
            print 'CRITICAL - Last update of {} was more than {}s ago!'.format(
                domain,
                critical
            )
            sys.exit(2)
        elif (current_timestamp - resp) >= warning:
            print 'WARNING - Last update of {} was more than {}s ago!'.format(
                domain,
                warning
            )
            sys.exit(1)
        elif (current_timestamp - resp) < warning:
            print 'OK - Last update of {} was less than {}s ago.'.format(
                domain,
                warning
            )
            sys.exit()
        else:
            print 'UNKNOWN - Unknown error occured!'
            sys.exit(3)
    else:
        print 'UNKNOWN - warning or critical values are no integers!'
        sys.exit(3)


def update_domain(cf, domain):
    """
    Updates a domain and adds all Pingdom Probes there
    if they don't exist or updates it's status by comparing
    the Cloudflare list with the Pingdom probes list
    """
    resp, e = cf_get_zone_id(cf, domain)
    if e is False:
        zone_id = resp
    else:
        print resp
        sys.exit(1)

    # Get all current IPv4/6 RR's
    resp, e = cf_fetch_rr(cf, domain, zone_id, 'A')
    if e is False:
        cf_ipv4_records = resp
    else:
        print resp
        sys.exit(1)
    resp, e = cf_fetch_rr(cf, domain, zone_id, 'AAAA')
    if e is False:
        cf_ipv6_records = resp
    else:
        print resp
        sys.exit(1)

    # Fetch Pingdom Probes
    resp, e = pingdom_fetch_probes('ipv4')
    if e is False:
        pingdom_ipv4_probes = resp
    else:
        print resp
        sys.exit(1)
    resp, e = pingdom_fetch_probes('ipv6')
    if e is False:
        pingdom_ipv6_probes = resp
    else:
        print resp
        sys.exit(1)

    # Remove all IPv4/IPv6 Entries that are not in the Pingdom Probes list
    cf_ipv4_delcount = 0
    for cf_ipv4_dict in cf_ipv4_records:
        if cf_ipv4_dict['content'] not in pingdom_ipv4_probes:
            resp = cf_del_rr(cf, zone_id, cf_ipv4_dict['id'])
            if resp is not True:
                print resp
                sys.exit(1)
            cf_ipv4_delcount += 1

    cf_ipv6_delcount = 0
    for cf_ipv6_dict in cf_ipv6_records:
        if cf_ipv6_dict['content'] not in pingdom_ipv6_probes:
            resp = cf_del_rr(cf, zone_id, cf_ipv6_dict['id'])
            if resp is not True:
                print resp
                sys.exit(1)
            cf_ipv6_delcount += 1

    # Add all IPv4/6 entries from Pingdom that are missing in Cloudflare's list
    cf_ipv4_list = map(lambda x: x['content'], cf_ipv4_records)
    cf_ipv4_addcount = 0
    for pingdom_ipv4 in pingdom_ipv4_probes:
        if pingdom_ipv4 not in cf_ipv4_list:
            resp = cf_add_rr(
                cf=cf,
                zone_id=zone_id,
                type='A',
                domain=domain,
                content=pingdom_ipv4,
            )
            if resp is not True:
                print resp
                sys.exit(1)
            cf_ipv4_addcount += 1

    cf_ipv6_list = map(lambda x: x['content'], cf_ipv6_records)
    cf_ipv6_addcount = 0
    for pingdom_ipv6 in pingdom_ipv6_probes:
        if pingdom_ipv6 not in cf_ipv6_list:
            resp = cf_add_rr(
                cf=cf,
                zone_id=zone_id,
                type='AAAA',
                domain=domain,
                content=pingdom_ipv6,
            )
            if resp is not True:
                print resp
                sys.exit(1)
            cf_ipv6_addcount += 1

    # Renew TXT record on each run, even if nothing changed.
    cf_txt_resp = cf_add_txt_rr(cf, domain, zone_id)
    if cf_txt_resp is True:
        print 'Deleted IPv4/6: {}/{}. Added IPv4/6: {}/{}. TXT Renewal: OK'.\
            format(
                cf_ipv4_delcount,
                cf_ipv6_delcount,
                cf_ipv4_addcount,
                cf_ipv6_addcount,)
        sys.exit()
    else:
        print 'Deleted IPv4/6: {}/{}. Added IPv4/6: {}/{}. TXT Renewal: FAIL'.\
            format(
                cf_ipv4_delcount,
                cf_ipv6_delcount,
                cf_ipv4_addcount,
                cf_ipv6_addcount,)
        print cf_txt_resp
        sys.exit(1)


def purge_domain(cf, domain):
    """
    Completely purges a domain so there are
    no traces of any pingdom probes or TXT records anymore
    """
    resp, e = cf_get_zone_id(cf, domain)
    if e is False:
        zone_id = resp
    else:
        print resp
        sys.exit(1)

    # Get all current RR's
    resp, e = cf_fetch_rr(cf, domain, zone_id, None)
    if e is False:
        cf_domain_records = resp
    else:
        print resp
        sys.exit(1)

    # Remove all Records from that domain (effectly the domain itself)
    cf_domain_delcount = 0
    for cf_domain_dict in cf_domain_records:
        resp = cf_del_rr(cf, zone_id, cf_domain_dict['id'])
        if resp is not True:
            print resp
            sys.exit(1)
        cf_domain_delcount += 1

    print 'Successfully deleted {} records from {}'.format(
        cf_domain_delcount,
        domain,
    )
    sys.exit()


def main(args):
    parser = argparse.ArgumentParser(
        description='\
        PPaaS (Pingdom Probes as a Service) gets all IPv4 and\
        IPv6 Probe Server IP\'s from Pingdom and creates a single\
        DNS Name with multiple A/AAAA-RR\'s out of them, so you can use\
        just a single DNS Name for whitelisting purposes without ever\
        have to manually add/remove them anymore. This is helpful\
        for example when using IP-Whitelisting with the Sophos UTM.\
        You now have to use a DNS Group and you\'re done.',
        version=version()
    )

    exclusive_group = parser.add_mutually_exclusive_group()
    exclusive_group.add_argument(
        '-q',
        '--query-domain',
        dest='check_domain',
        help='Enter a valid FQDN like "pingdomprobes.sysorchestra.com" to check last update\
        of the domain. The output is Nagios-compatible!',
    )
    exclusive_group.add_argument(
        '-u',
        '--update-domain',
        dest='update_domain',
        help='Enter a valid FQDN like "pingdomprobes.sysorchestra.com" to update\
        the Pingdom probes on that domain.',
    )
    exclusive_group.add_argument(
        '-p',
        '--purge-domain',
        dest='purge_domain',
        help='Enter a valid FQDN like "pingdomprobes.sysorchestra.com" to purge\
        the Pingdom probes on that domain as well as the TXT record.',
    )

    parser.add_argument(
        '-w',
        '--warning',
        default=86400,
        type=int,
        help='Enter the WARNING threshold in seconds.',
    )
    parser.add_argument(
        '-c',
        '--critical',
        default=172800,
        type=int,
        help='Enter the CRITICAL threshold in seconds.',
    )

    args = parser.parse_args()
    if args.check_domain and validate_fqdn(args.check_domain):
        check_domain(args.check_domain, args.warning, args.critical)
    elif args.update_domain and validate_fqdn(args.update_domain):
        cf = CloudFlare.CloudFlare(raw=True)
        update_domain(cf, args.update_domain)
    elif args.purge_domain and validate_fqdn(args.purge_domain):
        cf = CloudFlare.CloudFlare(raw=True)
        purge_domain(cf, args.purge_domain)
    else:
        parser.print_help()


if __name__ == '__main__':
    main(sys.argv[1:])
