# POC: user-installable applications, and the distribution question

Two questions were asked: can the desktop run something other than Ubuntu, and
can users install their own applications. The answers pull in opposite
directions, so they are separate below.

## Changing the distribution: not worth it

`oc.user`'s `Dockerfile.ubuntu` is 381 lines, 41 `RUN` layers. It carries:

- a **custom tigervnc `.deb`**, built and patched by abcdesktopio and fetched
  from their own repo. Fedora ships no equivalent package for the version used.
- nodejs from nodesource, plus a builder stage producing `/composer`
  (the spawner, wait-port, the whole abcdesktop plumbing)
- ~40 `apt-get install` blocks to translate to `dnf`

`ARG BASE_IMAGE` exists, but every layer below it is Debian-flavoured, so it
only buys you Debian or a Ubuntu derivative for free. A Fedora port is a
multi-day rewrite to re-do at every abcdesktop release (5.0 is already out).

## Letting users install their own applications: measured working

flatpak makes the base distribution mostly irrelevant, which answers the
original need without the port. `flatpak --user` installs into
`~/.local/share/flatpak`, and the home is a persistent PVC, so what a user
installs survives their session.

Verified on this cluster, in a throwaway pod, uid 4096 with an empty effective
capability set (the same conditions as a desktop container):

| Step | Result |
|---|---|
| `flatpak --user remote-add flathub` | works |
| `flatpak --user install org.freedesktop.Platform//24.08` | works, 2.0 GB in the home |
| `flatpak run` (bubblewrap) | works, `--command=echo` returned its argument |

Five conditions have to hold, and they were each found the hard way:

1. `user.max_user_namespaces > 0` — `mocha/patches/user-namespaces.yml`, done.
2. seccomp allowing `clone`/`unshare` — `mocha/patches/seccomp-userns.yml`, done.
   `mount` must stay allowed too: bubblewrap mounts inside its own namespace.
3. **`hostUsers: false`** on the pod. Not optional, and not a security
   downgrade: it maps the pod onto unprivileged host uids.
4. **`procMount: Unmasked`** on the container. Kubernetes masks paths under
   `/proc`, and the kernel then refuses to mount a fresh `proc` in a nested
   namespace, which is what bubblewrap does first. `Unmasked` requires
   `hostUsers: false`, the API rejects it otherwise.
5. A D-Bus **system** bus. `flatpak run` fails with
   `Could not connect: No such file or directory` without one — that message
   names no socket and sends you looking at the session bus, which is not it.
   The desktop already has `/var/run/dbus/system_bus_socket`.
6. `org.freedesktop.Accounts.service` **removed from the image**, see the
   Dockerfile. flatpak asks accountsservice for the user's locales; the daemon
   needs root and cannot start as uid 4096, and flatpak treats the resulting
   dbus error as fatal.
7. `XDG_RUNTIME_DIR` must exist and be `0700`, or flatpak stops on
   `Unable to allocate instance id`. abcdesktop sets it to `/tmp/runtime`
   through `desktop.envlocal` — check it is actually created.

The final run, in the POC image, uid 4096, empty effective capabilities, under
the cluster's own seccomp profile:

```
$ flatpak run --command=echo org.freedesktop.Platform//24.08 FLATPAK_RUNS_IN_ABCDESKTOP_IMAGE
FLATPAK_RUNS_IN_ABCDESKTOP_IMAGE
```

## What is left to wire up

Nothing is enabled: `od.config` still points at the upstream image. To switch:

```python
# desktop.pod.graphical.image
'image': { 'default': 'ghcr.io/qjoly/oc.user.flatpak:4.4' },

# desktop.pod.graphical.securityContext, and the same for
# ephemeral_container and pod_application
'procMount': 'Unmasked',

# executeclasses.default — pyos merges anything left in an execute class
# straight into the pod spec, which is the only way in for hostUsers
'hostUsers': False,
```

Then, per user, once: `flatpak --user remote-add --if-not-exists flathub
https://dl.flathub.org/repo/flathub.flatpakrepo`. Worth adding to the session
init container next to the mise install if this graduates out of POC.

## Costs to weigh first

- **Disk.** One runtime is 2 GB. The home PVC is 10 GB and the node's volume
  group had 70 GB free. Two users with a couple of runtimes each and it is
  gone. Size the home up, or point flatpak at a shared installation.
- **`procMount: Unmasked`** un-masks `/proc/kcore`, `/proc/keys`,
  `/proc/timer_list` and the rest inside the container. `hostUsers: false`
  offsets much of it, but the two go together, they are not independent knobs.
- **A custom image to maintain**, rebuilt on each abcdesktop release. Two lines
  of Dockerfile, but it is one more thing that can lag behind upstream.
- Only the desktop image is derived. The application containers
  (`vscode.d`, `firefox.d`) are untouched and keep working as they do now.
