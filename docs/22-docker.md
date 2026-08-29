---
sidebar_position: 22
---

# Docker

Chrome runs a bit differently in a container, in ways that are not obvious and that surface as
slow leaks rather than errors. This page collects everything Ferrum-specific about it.

:::note
When running in docker as root
:::

```ruby
Ferrum::Browser.new(dockerize: true)
```

Essentially it just sets CLI flags for a browser to make it start. On CI, you can just set `FERRUM_CHROME_DOCKERIZE=true`
environment variable, and it will be passed to all browser instances.

## An init is required

:::warning
If your Ruby process is pid 1, run the container with an init: `docker run --init`, `init: true` in Compose, or
`ENTRYPOINT ["/sbin/tini", "--"]` in the image. This is a requirement, not a nicety.
:::

Chrome is a process tree — a browser process plus renderer, GPU, zygote and utility processes — and it delegates the
last step of its own cleanup to the operating system.

When Chrome shuts down it tells its children to go and then exits about 10ms later. Its children take another
20-30ms to finish, whilst their parent is gone, so there's no one to collect them. This is not avoidable
and not specific to Ferrum: it happens whether the browser is asked to quit politely or killed outright, and whether
the signal goes to the browser alone or to its whole process group. Measured on Chrome 151, roughly eight to eleven
processes per browser finish after the browser itself has exited.

Unix answers this by handing orphans to pid 1, whose job is to collect them. On a normal machine that is systemd or
launchd and it happens instantly. In a container started as `CMD ["bundle", "exec", "..."]` there is no init at
all: *your* process is pid 1, it never inherited that job, and it collects nothing.

Two things then go wrong, both measured on the same image with and without `--init`:

|  | no init | with an init |
|---|---|---|
| processes left after each `#quit` | 9 `<defunct>`, never reclaimed | 0 |
| time `#quit` takes | 2.02s | 0.06s |

The leak is the obvious cost. Each `<defunct>` entry holds a pid and a process-table slot forever, so eventually
`fork` starts failing, new browsers will not start, and page loads time out for no visible reason:

```console
$ docker exec app ps -A
  PID TTY          TIME CMD
   41 ?        00:00:00 [chrome] <defunct>
   42 ?        00:00:00 [chrome] <defunct>
   62 ?        00:00:01 [chrome] <defunct>
   ...
```

The two seconds are less obvious. Ferrum waits for Chrome's process group to empty before returning, and a zombie
still answers `kill(0, ...)` — so with nothing reaping them the group never looks empty and every `#quit` waits out
its full kill timeout.

An init fixes both, and is worth having regardless: every other process your image spawns has the same problem.

## Kubernetes

There is no `init: true` in a pod spec, so you have two options.

**Bake an init into the image.** `ENTRYPOINT ["/sbin/tini", "--"]`. Scoped to your container, behaves the same
everywhere, and is the better default.

**Or set `shareProcessNamespace: true` on the pod.** Kubernetes then makes the `pause` container pid 1 for the whole
pod, and `pause` is an init — its `SIGCHLD` handler loops on `waitpid(-1, WNOHANG)`, which is exactly the job that
is otherwise missing. Note this is not mentioned on the Kubernetes documentation page for the feature; it is
visible in `pause.c`.

It has real trade-offs beyond reaping, though: every container in the pod can see the other processes, their
environment variables through `/proc/$pid/environ`, and their filesystems through `/proc/$pid/root`. Your process
also stops being pid 1, so anyone doing `kill -HUP 1` now signals `pause`.

:::note
`initContainers` are not an init system.
:::

## What Ferrum cleans up, and what it does not

Ferrum spawns exactly one process: the browser. On `#quit` it signals the browser's process group, escalating from
`TERM` to `KILL`, and waits on the browser itself — the one process it is the parent of, and therefore the only one
nobody else can collect.

Chrome's renderer, GPU and utility processes are Ferrum's *grand*children. When they outlive the browser the kernel
reparents them to pid 1, and collecting them is PID 1 job by definition. Ferrum deliberately does not do it:
`waitpid(-1)` would also collect child processes your own application spawned, stealing their exit statuses. A
library cannot take that liberty, which is why the answer here is an init rather than something Ferrum can fix.

`chrome_crashpad_handler` is a whole new story — Chrome double-forks it into its own session before any of this
happens, so it is not even in the process group Ferrum signals. See [the crashpad handler](/docs/ferrum/customization#the-crashpad-handler),
including why the flag that appears to disable it must not be used.

## Running Chrome in a separate container

If Chrome lives in its own container and Ferrum connects over a websocket, Ferrum did not spawn that browser and
couldn't kill it:

```ruby
browser = Ferrum::Browser.new(ws_url: "ws://chrome:3000/")
```

`#quit` closes the connection and nothing more. Whether the remote browser then shuts down is up to that service —
most reclaim a session when its connection drops, and most have a timeout for when they do not. To ask the browser
itself to exit rather than relying on that, use `#close`, which sends the CDP `Browser.close` command:

```ruby
browser.close
browser.quit
```

## Diagnosing

Check whether the processes piling up are dead or alive:

```console
$ docker exec app ps -Ao pid=,ppid=,stat=,comm=
```

`STAT` of `Z`, or `<defunct>` in the command, means the process is finished and merely uncollected. That is the
missing-init problem above.

Live processes accumulating instead means browsers are never being shut down at all — usually a `#quit` that is not
called, or a remote browser service holding sessions open. An init will not help with those.
