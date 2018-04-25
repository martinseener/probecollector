#!/usr/bin/env python
# # -*- coding: utf-8 -*-

"""
check_probe_collector provides only the check_domain part
from Probe Collector for dependency-free deployments on
servers that don't have pip.
"""

from __future__ import print_function
import sys

try:
    import argparse
    import subprocess
    import time
    import re

except ImportError as e:
    print("Missing python module: {}".format(e.message))
    sys.exit(255)


__author__ = 'Martin Seener'
__copyright__ = 'Copyright 2018, Martin Seener'
__license__ = 'MIT'
__version__ = '2.1.2'
__maintainer__ = 'Martin Seener'
__email__ = 'martin@sysorchestra.com'
__status__ = 'Production'


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


def check_domain(domain, warning, critical):
    """
    Checks if the domain has been updated recently
    and outputs the result in a Nagios-compatible manner
    """
    current_timestamp = int(time.time())
    resp = subprocess.check_output(
        ['dig', 'TXT', domain, '+short']
    ).decode().strip().strip('"')
    if type(resp) == str or type(resp) == unicode:
        try:
            resp = int(resp)
        except Exception:
            print('UNKNOWN - Domain does not provide a valid TXT record.')
            sys.exit(3)
    if isinstance(warning, int) and isinstance(critical, int):
        if (current_timestamp - resp) >= critical:
            print('CRITICAL - Last update of {} was more than {}s ago!'.format(
                domain,
                critical
            ))
            sys.exit(2)
        elif (current_timestamp - resp) >= warning:
            print('WARNING - Last update of {} was more than {}s ago!'.format(
                domain,
                warning
            ))
            sys.exit(1)
        elif (current_timestamp - resp) < warning:
            print('OK - Last update of {} was less than {}s ago.'.format(
                domain,
                warning
            ))
            sys.exit()
        else:
            print('UNKNOWN - Unknown error occured!')
            sys.exit(3)
    else:
        print('UNKNOWN - warning or critical values are no integers!')
        sys.exit(3)


def main(args):
    parser = argparse.ArgumentParser(
        description='\
        check_probe_collector is a external dependency-free Nagios-compatible\
        check that fetches the TXT record of a Probe Collector domain and\
        compares it\'s UNIX timestamp to see if the domain\
        has been updated recently.',
    )

    parser.add_argument(
        '-q',
        '--query-domain',
        dest='check_domain',
        help='Enter a valid FQDN like "monitoringprobes.sysorchestra.com" to check\
        last update of the domain. The output is Nagios-compatible!',
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
    else:
        parser.print_help()


if __name__ == '__main__':
    main(sys.argv[1:])
