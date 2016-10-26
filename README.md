# Pingdom Probes as a Service (PPaaS)
This little script will automate the hassle of adding or removing single pingdom probes manually from your IP-Whitelisting or Firewall.
It will do this by getting all IPv4 and IPv6 Probes and add them to a single Subdomain of your own domain. It will add all probes as separate A/AAAA
Records for that subdomain so by resolving the subdomain you get all probes.

### Example
In the Sophos UTM you can either do it manually and add single DNS Hosts or Hosts with IP's manually or you can now add a single DNS Group which
points to your new subdomain. The UTM will automatically resolve to all A/AAAA Records (AAAA only when IPv6 is activated) and updates the Filterrules
which uses this DNS Group, so an update to the listed RR's on the Subdomain results in an automatically updated Whitelisting.

## How to use
Just download the ppaas.sh script and make it executeable with `chmod +x ppaas.sh`. Then configure the parameters within that script at the top.

* **CFEMAIL** means your login e-mail address for your Cloudflare account
* **CFAPIKEY** is your *Global API Key* which you can find in [your Account](https://www.cloudflare.com/a/account/my-account) by clicking *View API Key*
* **CFZONE** is your Domain where your Pingdom Probe Subdomain will be created like `example.com`
* **CFPPDOMAIN** is the desired Pingdom Probes Subdomain like `pingdomprobes.example.com`
* **RRTTL** is the TTL (Time-to-live) of the created A/AAAA Resource Records (this is the default for Pingdoms Probe Server DNS Entries)
* **DOLOG** enables the logging of what PPaaS does. By default it logs into syslog using `logger` with the programname `ppaas`
* **INTERACTIVELOG** outputs all log also to `STDOUT` besides syslog, so you can see what `ppass` does.

### Embedded 3rd party tools
While PPaaS needs to process JSON Output coming from the Cloudflare API, [JSON.sh](https://github.com/dominictarr/JSON.sh) has been embedded into ppaas.sh, so it does not rely on external 3rd party tools and can run everywhere where a bash is available (Linux, macOS, *BSD, maybe Windows with cygwin or WSL)

## Contributing and License
This script has been quickly written to just do what it does. It fetches all probes available, erases all current Resource Records from the owned subdomain and readds all probes again. This is not very intelligent but it works just fine. I thought about checking which A/AAAA Records are already there and just adding/removing those who are/are not in the Probes list. If you want to help me out making this tool better, you're very welcome.

I even appreciate ports to Go, Ruby or other Languages.

### How to contribute?
1. Check for open issues or open a new issue to start a discussion around a feature idea or a bug.
2. Fork the repository on Github and make your changes on your own **development** branch (just branch off of master).
3. Send a pull request (with the **master** branch as the target).

## Changelog
See [CHANGELOG.md](CHANGELOG.md)

### License
PPaaS is available under the MIT license. See the [LICENSE](LICENSE) file for more info.