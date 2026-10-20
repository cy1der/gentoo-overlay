# Personal Gentoo overlay

## Adding the repository

### With `eselect repository`

```sh
emerge --ask app-eselect/eselect-repository dev-vcs/git
eselect repository add cy1der git https://github.com/cy1der/gentoo-overlay.git
emaint sync --repo cy1der
```

### Manually

Create `/etc/portage/repos.conf/cy1der.conf`:

```ini
[cy1der]
location = /var/db/repos/cy1der
sync-type = git
sync-uri = https://github.com/cy1der/gentoo-overlay.git
auto-sync = yes
```

Then sync it:

```sh
emaint sync --repo cy1der
```
