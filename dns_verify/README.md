# DNS Verification Script

```
Usage: dns_verify.sh [-s <file>] [-hqvV] [<file_or_domain>]...
  DNS Verification Script v0.1
    -s <file>  JSON file of take-down services and a string to check for
    -h         Display this help text and exit
    -q         Quiet
    -d         Debug mode (log the entire checking process)
    -v         Verbose mode (show passing domains)
    -V         Display version information and exit
```

This script allows you to check domains for dangling `CNAME` DNS records as well as services with vulnerable DNS Takeover services. It takes a series of arguments that are either a domain to check or a file with a list of many domains separated by a new line. It also has several flags documented above for changing the level of logging as well as supplying a JSON file containing known takedown services and search strings (See [`services.json`](services.json) for an example of this file).

Example: `./dns_verify.sh -s services.json -v balena.io`

Docker: `docker run -it -v $(pwd):/mnt --rm alpine:edge sh -uelic 'apk add bind-tools curl jq; /mnt/dns_verify.sh -s /mnt/services.json balena.io'`
