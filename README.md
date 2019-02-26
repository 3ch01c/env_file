# What is this?

Environment variables with `docker-compose` are confusing AF for me. So I sat down and unit tested this insanity...

# The Setup

My host environment:

``` sh
$ docker --version
Docker version 18.09.2, build 6247962
$ docker-compose --version
docker-compose version 1.24.0-rc1, build 0f3d4dda
$ export FOO="defined in host environment"
$ echo $FOO
defined in host environment
```

My `.env`:

``` sh
$ cat .env
FOO="defined in .env"
```

My `foo.env`:

``` sh
$ cat foo.env
FOO="defined in foo.env"
```

My `Dockerfile`:

``` Dockerfile
FROM alpine
ARG FOO="defined in Dockerfile ARG"
RUN env
ENTRYPOINT ["sh", "-c", "env"]
```

My `docker-compose.yml`:

``` yaml
version: "3"
services:
  env_test:
    image: env_test
    build:
      context: .
      args:
        - FOO=defined in docker-compose.yml build args block
    env_file:
      - ./foo.env
    environment:
      - FOO=defined in docker-compose.yml environment block
```

# The Tests

## Build time variable precedence

### `docker-compose build --build-arg FOO`

Variables declared with `--build-arg` in `docker-compose build` command line take highest precedence at build time. If undefined, host environment then `.env` then `Dockerfile ARG` will be used to define the variable at build time.

``` sh
$ docker-compose build --build-arg FOO="defined in docker-compose build command line"
Building env_test
Step 1/4 : FROM alpine
 ---> caf27325b298
Step 2/4 : ARG FOO="defined in Dockerfile ARG"
 ---> Using cache
 ---> be35bdaa7e80
Step 3/4 : RUN env
 ---> Running in 042352f8d005
HOSTNAME=042352f8d005
SHLVL=1
HOME=/root
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
FOO=defined in docker-compose build command line
PWD=/
...
```

So `--build-arg` -> host environment -> `.env` -> `Dockerfile`. Even if the build variable is only defined in `build args` block of `docker-compose.yml`, it **will not be used** if declared in `--build-arg` in `docker-compose build` command line.

``` sh
$ grep -A3 "build:" docker-compose.yml
    build:
      context: .
      args:
        - FOO=defined in docker-compose.yml build args block
$ echo $FOO

$ grep FOO .env
$ grep "ARG FOO" Dockerfile
ARG FOO
$ docker-compose build --build-arg FOO
Building env_test
Step 1/4 : FROM alpine
latest: Pulling from library/alpine
6c40cc604d8e: Already exists
Digest: sha256:b3dbf31b77fd99d9c08f780ce6f5282aba076d70a513a8be859d8d3a4d0c92b8
Status: Downloaded newer image for alpine:latest
 ---> caf27325b298
Step 2/4 : ARG FOO
 ---> Running in e6528c72f752
Removing intermediate container e6528c72f752
 ---> 4f7b9d737f2f
Step 3/4 : RUN env
 ---> Running in 3672c36ebbd5
HOSTNAME=3672c36ebbd5
SHLVL=1
HOME=/root
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
PWD=/
...
```

### `docker-compose.yml build args`

If not declared in `--build-arg` of `docker-compose build` command line, `build args` block in `docker-compose.yml` takes highest precedence at build time. If undefined, host environment then `.env`  will be used to define the variable at build time.

``` sh
james@luna:~/projects/env_file$ docker-compose build
Building env_test
Step 1/4 : FROM alpine
 ---> caf27325b298
Step 2/4 : ARG FOO="defined in Dockerfile ARG"
 ---> Running in bf110d0379be
Removing intermediate container bf110d0379be
 ---> be35bdaa7e80
Step 3/4 : RUN env
 ---> Running in 162f3f961b8c
HOSTNAME=162f3f961b8c
SHLVL=1
HOME=/root
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
FOO=defined in docker-compose.yml build args block
PWD=/
...
```

So `docker-compose.yml` -> host environment -> `.env`. Even if the build variable is only defined in `ARG` statement of `Dockerfile`, it **will not be used** if declared in `build args` of `docker-compose.yml`.

``` sh
$ grep -A3 "build:" docker-compose.yml
    build:
      context: .
    env_file:
      - ./foo.env
$ docker-compose build
Building env_test
Step 1/4 : FROM alpine
latest: Pulling from library/alpine
6c40cc604d8e: Already exists
Digest: sha256:b3dbf31b77fd99d9c08f780ce6f5282aba076d70a513a8be859d8d3a4d0c92b8
Status: Downloaded newer image for alpine:latest
 ---> caf27325b298
Step 2/4 : ARG FOO="defined in Dockerfile ARG"
 ---> Running in 8f9533787554
Removing intermediate container 8f9533787554
 ---> ba2e9f003f29
Step 3/4 : RUN env
 ---> Running in 2ff4c4af8499
HOSTNAME=2ff4c4af8499
SHLVL=1
HOME=/root
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
FOO=
PWD=/
...
```

### `ARG`

If not declared in `--build-arg` of `docker-compose build` command line or `build args` of `docker-compose.yml`, the default value in the `ARG` statement in `Dockerfile` will be used. If there is no default value, it will be undeclared in the image in this case. It will not fall back to host environment or `.env`.

``` sh
$ echo $FOO
defined in host environment
$ cat .env
FOO="defined in .env"
$ grep "ARG FOO" Dockerfile
ARG FOO
$ docker-compose build
Building env_test
Step 1/4 : FROM alpine
latest: Pulling from library/alpine
6c40cc604d8e: Already exists
Digest: sha256:b3dbf31b77fd99d9c08f780ce6f5282aba076d70a513a8be859d8d3a4d0c92b8
Status: Downloaded newer image for alpine:latest
 ---> caf27325b298
Step 2/4 : ARG FOO
 ---> Running in 783c66b516ee
Removing intermediate container 783c66b516ee
 ---> d83eeee58bbf
Step 3/4 : RUN env
 ---> Running in 702cedb02087
HOSTNAME=702cedb02087
SHLVL=1
HOME=/root
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
PWD=/
...
```

If the variable is not declared in an `ARG` statement, **it will not be used** at build time regardless of how you pass it.

## Run time variables

### `docker-compose run -e FOO`

Variables declared in the `docker-compose run` command line take precedence at run time.

``` sh
$ docker-compose run -e FOO="defined in docker-compose run command line" env_test
HOSTNAME=987ed2f2dc9f
SHLVL=1
HOME=/root
TERM=xterm
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
FOO=defined in docker-compose run command line
PWD=/
```

If undefined, it inherits from host environment. It does not inherit from `.env`, `foo.env`, or `docker-compose.yml`.

``` sh
$ docker-compose run -e FOO env_test
HOSTNAME=ded490f8dda1
SHLVL=1
HOME=/root
TERM=xterm
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
FOO=defined in host environment
PWD=/
```

### `docker-compose.yml environment`

Variables declared in the `environment` block of `docker-compose` take precedence after `docker-compose run` command line variables at run time.

``` sh
$ docker-compose run env_test
HOSTNAME=fffa21ffe5d3
SHLVL=1
HOME=/root
TERM=xterm
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
FOO=defined in docker-compose.yml environment block
PWD=/
```

If undefined, host environment then `.env` is used.

### `docker-compose.yml env_file`

If a variable is not declared in `environment`, `env_file` takes next precedence.

``` sh
$ grep -A3 env_file docker-compose.yml
    env_file:
      - ./foo.env
    environment:
      - BAR
$ docker-compose run env_test
HOSTNAME=80e9c7dfea7d
SHLVL=1
HOME=/root
TERM=xterm
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
FOO="defined in foo.env"
PWD=/
```

If undefined, host environment then `.env` is used.

## docker-compose variable expansion

You can also use variables in `docker-compose.yml`.

``` sh
$ grep -a1 FOO docker-compose.yml
      args:
        - FOO=$FOO
    env_file:
--
--
    environment:
      - FOO=$FOO
```

At build time, these variables are defined by host environment then `.env` then fall back to a blank string. They do not use `--build-arg` variables.

``` sh
$ docker-compose build --build-arg FOO="defined in docker-compose build command line"
Building env_test
Step 1/4 : FROM alpine
latest: Pulling from library/alpine
6c40cc604d8e: Already exists
Digest: sha256:b3dbf31b77fd99d9c08f780ce6f5282aba076d70a513a8be859d8d3a4d0c92b8
Status: Downloaded newer image for alpine:latest
 ---> caf27325b298
Step 2/4 : ARG FOO="defined in Dockerfile"
 ---> Running in c08a451cdc12
Removing intermediate container c08a451cdc12
 ---> bb7302860503
Step 3/4 : RUN env
 ---> Running in 0a57658d252e
HOSTNAME=0a57658d252e
SHLVL=1
HOME=/root
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
FOO=defined in host environment
PWD=/
```

At run time, these variables are defined by `-e` command line variables then host environment then `.env` then fall back to a blank string.

``` sh
$ docker-compose run env_test
HOSTNAME=3e92af457f7e
SHLVL=1
HOME=/root
TERM=xterm
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
FOO=defined in host environment
PWD=/
```

# Reserved for future use
Something about making a script for all this...