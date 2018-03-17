# Change Log
All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [2.1.0] - 2018-03-17
- Made Probe Collector compatible with Python 2 and 3. Tested with Python 2.7.10 and 3.6.4
- Added support for UptimeRobot (Pingdom remains default for backwards-compatibility)

## [2.0.1] - 2018-02-06
- PPaaS has been renamed to Probe Collector to prepare support for multiple probe-based monitoring services

## [2.0.0] - 2018-02-06
- PPaaS has been completely rewritten in Python (2.7) starting with v2.x branch
- Updating a domain now does not purge and rewrites all probes but it intelligently deleting/writing only changed probes from Pingdom's lists
- Added functionality to add/update a TXT record with the current UNIX-timestamp when the last PPaaS run updated the domain
- Added functionality to completely purge a probes domain
- Added Nagios-compatible check if a domain has been updated recently using the added TXT record functionality
- Bash-Version (v1.x branch) has been archived/deprecated in favor of v2.x

## [1.1.0] - 2017-01-27
- Made the dependencies (json_sh) and configuration modular
- Added writing a status file upon last successful execution
- Made some smaller enhancements to ppaas.sh

## [1.0.1] - 2016-10-27
- Added Cloudflare API v4 Availability check
- Fixed the Pingdom Probes Availability check
- Fixed the Log output when new A/AAAA Records are being added (we accidentially logged the JSON response instead of the IP)

## [1.0.0] - 2016-10-26
- Initial release
