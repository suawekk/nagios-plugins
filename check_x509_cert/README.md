### Nagios multiple x509 Certificate checker ###

#### Usage ####
this script should help with checking validity of multiple x509
certificates at once. It uses glob patterns to build certificate list
and then checks each of them whether they expired.

If you call it like this:

```
/path/to/check_certs.rb -g 'path/to/certs/*.crt' -w 360 -c 72
```

then script will check for all files matching pattern
'path/to/certs/*.crt' and  issue error when any of them will expire in
less than 72 hours or issue warning if any of them will expire in less
than 360 hours 
