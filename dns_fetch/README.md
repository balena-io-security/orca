# DNS Fetch Script

```
Usage: dns_fetch.sh [-s <service>] [-d <domain>] [-o <field>] [-hqvV] [record type]...
  DNS Record Fetch Script v0.1
    -s <service>   Service to use, default to all configured
    -d <domain>    Domain to retrieve, default to all available
    -o <field>     Output specific field (name, content, or type), default to json of all fields
    -h             Display this help text and exit
    -q             Quiet
    -v             Verbose mode
    -V             Display version information and exit
```

This script allows you to fetch DNS records from various services and filter them by type.

## Examples

```sh
# Fetch all the balena.io domains from Cloudflare that are of CNAME or A type.
./dns_fetch.sh -s cloudflare -d balena.io CNAME A

# Fetch all the balena.io CNAME DNS record names from Cloudflare
# and use dns_verify.sh to validate them against DNS hijacking attacks
./dns_fetch.sh -s cloudflare -d balena.io -o name CNAME | ../dns_verify/dns_verify.sh -v -s ../dns_verify/services.json
```

## Supported Services

We currently support the following checked services while the unchecked services are on the roadmap to be added in the future. Configuration for authentication is currently done through environment variables which are specified in the list as well.

- [x] `cloudflare` ([Cloudflare](https://www.cloudflare.com/dns/))
  - _Preferred:_ API Token Authentication with `DNS:Read` permissions (set `CLOUDFLARE_TOKEN`)
  - Email and Global API Key Authentication (set `CLOUDFLARE_EMAIL` and `CLOUDFLARE_KEY`)
- [ ] `aws` ([AWS Route53](https://aws.amazon.com/route53/))
- [ ] `gcp` ([Google Cloud DNS](https://cloud.google.com/dns))
- [ ] `azure` ([Azure DNS](https://azure.microsoft.com/en-us/services/dns/))
