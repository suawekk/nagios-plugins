## Subpage indexing check

### What does it do?

It takes list of URLs from file
and perform two checks for each of them
* checks whether robots.txt on URL's domain forbid/allow it to be indexed
* checks whether page contains

```html
<meta name="robots">
```
HTML tag.

### Usage
call script with "-h" argument to see what options are supported
