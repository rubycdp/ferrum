---
sidebar_position: 22
---

# Docker

There are two ways to use Chrome with Docker:

- **Our images**, `ghcr.io/rubycdp/chrome` and `ghcr.io/rubycdp/chromium`: Chrome runs in its own container and Ferrum
  connects to it. Use these unless you need Chrome inside your app's container. Process reaping, crashpad, fonts and
  flags are taken care of.
- **Chrome in your own container**, next to your Ruby process. Chrome runs a bit differently in a container, in ways
  that are not obvious and that surface as slow leaks rather than errors, and [Running Chrome yourself](#running-chrome-yourself)
  covers all of it.

## Our images (recommended)

Two images, both for amd64 and arm64: `chromium` ships Debian's Chromium, `chrome` ships Google Chrome. Each
connection gets its own Chrome with a fresh profile, which is stopped as soon as the connection closes. Nothing else
talks to your browser: the driver inside passes CDP through unchanged.

Tags are `latest`, the major version (`155`) and the full version (`155.0.8059.84`). New browser releases are picked up
daily. Older tags stay available, so you can pin a version.

### Quick start

```shell
docker run --rm -p 3000:3000 ghcr.io/rubycdp/chromium
```

```ruby
browser = Ferrum::Browser.new(url: "http://localhost:3000")
browser.go_to("https://example.com")
browser.quit
```

`ws_url: "ws://localhost:3000"` works too.

### Compose and Cuprite

```yaml
services:
  chrome:
    image: ghcr.io/rubycdp/chromium
    environment:
      CONCURRENT: 4
    volumes:
      - .:/app

  app:
    build: .
    volumes:
      - .:/app
    environment:
      CHROME_URL: http://chrome:3000
    depends_on:
      chrome:
        condition: service_healthy
```

```ruby
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, url: ENV.fetch("CHROME_URL"))
end

Capybara.server_host = "0.0.0.0"
Capybara.server_port = 3001
Capybara.app_host = "http://app:3001"
```

Chrome has to reach your app, so bind the server to `0.0.0.0` and point `app_host` at the app's name on the compose
network. When the app runs on your machine instead, use `host.docker.internal`, which needs
`extra_hosts: ["host.docker.internal:host-gateway"]` on Linux.

Cuprite keeps one connection per test process and calls `reset` between tests, so every parallel worker gets its own
Chrome. The image has a healthcheck on `/health`.

### Options per connection

Ferrum's `window_size:` and `browser_options:` only apply to a Chrome that Ferrum starts itself. For a remote one, put
them in the connection URL as `launch`, JSON or base64:

```ruby
launch = {
  defaultViewport: { width: 1920, height: 1080 },
  args: ["--accept-lang=de-DE"]
}
Ferrum::Browser.new(url: "http://localhost:3000?launch=#{CGI.escape(launch.to_json)}")
```

- `args`: extra Chrome flags. A flag with the same name as a default replaces it.
- `defaultViewport`: the window size, 1024x768 by default like Ferrum's.
- `ignoreDefaultArgs`: `true`, or a list of default flags to drop.
- `headless: false`: Chrome gets a window on its own virtual display.

`timeout=<ms>` in the same URL ends the session after that long. `docker run --rm ghcr.io/rubycdp/chromium --help`
lists everything, including the default flags, which are Ferrum's.

### Settings

- `CONCURRENT`: how many sessions run at once, the number of CPUs by default. Set it to at least your number of test
  workers.
- `QUEUED`: how many connections wait for a free slot, 10 by default. Past that they get `429`.
- `TIMEOUT`: a session timeout in milliseconds for every connection. There is none by default.
- `EXTERNAL`: the public URL when the container sits behind a proxy, so the WebSocket address it hands out is
  reachable.
- `PORT` and `HOST`: where it listens, `0.0.0.0:3000` by default.

### Files

Chrome resolves file paths inside its own container. Mount the directories that uploads come from and downloads go to
at the same absolute path in both containers, and `attach_file`, `select_file` and `save_path` work unchanged. Run the
container as your user so downloaded files belong to you:

```shell
docker run --rm -p 3000:3000 --user "$(id -u):$(id -g)" -v "$PWD:$PWD" ghcr.io/rubycdp/chromium
```

Screenshots and PDFs need no mount, they come back over CDP.

### Watching a test

Open [http://localhost:3000](http://localhost:3000) while tests run. The dashboard lists running sessions and their
pages, and each page links to DevTools with a live view of it. Pages go away when the test ends, so pause the test
(`binding.irb`, a breakpoint) to look at one.

### Security

:::warning
There is no authentication, and anyone who can connect can pass Chrome flags that run commands in the container. Never
publish the port beyond localhost or a private network.
:::

### Coming from browserless

Usually you swap the image and connect to `/`. The differences that matter:

- There's no session timeout by default, browserless kills sessions after 30 seconds.
- There are no `/chrome` or `/chromium` paths, no tokens, and no REST APIs (`/screenshot`, `/pdf`, `/function`).
  Ferrum does all of that over CDP.
- There's no `/workspace`, files go through mounts as described above.
- Nothing resets your viewport or download folder, and `reset` really isolates tests.

The full comparison and the reasons behind it are in the [design notes](https://github.com/rubycdp/ferrum/blob/main/docker/DESIGN.md).

## Running Chrome yourself

### In your app's container

:::note
When running in docker as root
:::

```ruby
Ferrum::Browser.new(dockerize: true)
```

Essentially it just sets CLI flags for a browser to make it start. On CI, you can just set `FERRUM_CHROME_DOCKERIZE=true`
environment variable, and it will be passed to all browser instances.

### An init is required

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

### Kubernetes

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

### What Ferrum cleans up, and what it does not

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

### Another remote browser service

Any service that speaks CDP works the same way, with `url:` or `ws_url:`. Ferrum did not spawn that browser and
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

### Diagnosing

Check whether the processes piling up are dead or alive:

```console
$ docker exec app ps -Ao pid=,ppid=,stat=,comm=
```

`STAT` of `Z`, or `<defunct>` in the command, means the process is finished and merely uncollected. That is the
missing-init problem above.

Live processes accumulating instead means browsers are never being shut down at all — usually a `#quit` that is not
called, or a remote browser service holding sessions open. An init will not help with those.
