# INWK6312 VM Installation Steps, Extracted from install.cast

This document was reconstructed from an asciinema recording of the VM setup, by replaying the recording through a terminal emulator and extracting the commands and key output. It is a first draft, not a polished lab document, review it against the actual VM before treating it as authoritative, and see the Gaps and Things Worth Double-Checking section at the end for the handful of spots the recording did not fully resolve.

## Phase 1, System Update and Prerequisites

```bash
sudo apt update -y
sudo apt install ca-certificates curl
```

`ca-certificates` and `curl` were already present on this VM image, so this step confirmed rather than newly installed them.

## Phase 2, Install Docker Engine, Official apt Repository Method

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Verify the daemon is running and the engine works.

```bash
sudo systemctl status docker
sudo docker run hello-world
```

## Phase 3, Post-Install Docker Group Setup

By default only root can talk to the Docker daemon. This adds the current user to the `docker` group so `sudo` is no longer required for Docker commands.

```bash
sudo groupadd docker
sudo usermod -aG docker $USER
```

The group membership does not take effect in the current shell session. Running `docker version` immediately after this fails with `permission denied while trying to connect to the docker API`, which is expected. Exit and log back in, or `newgrp docker`, for the new group to apply.

```bash
exit
```

After logging back in, confirm Docker works without `sudo`:

```bash
docker version
```

## Phase 4, Install Containerlab

```bash
curl -sL https://containerlab.dev/setup | sudo -E bash -s "all"
```

This installed containerlab 0.77.0. The installer's own output recommends one more step that was not run in this recording, worth doing:

```bash
sudo usermod -aG clab_admins $USER && newgrp clab_admins
```

Confirm the install:

```bash
clab version
```

## Phase 5, Network OS Images, cEOS and SR Linux

The Arista cEOS image was pulled from an internal file server rather than a public registry, this step is specific to this course's infrastructure and will need a different distribution path for anyone outside it.

```bash
scp automan@192.168.2.181:cEOS/cEOS-lab-4.36.1F.tar .
ls
docker import cEOS-lab-4.36.1F.tar ceos:v4.36
```

Nokia SR Linux was pulled directly from its public registry:

```bash
docker pull ghcr.io/nokia/srlinux:26.7.1-554-amd64
```

## Phase 6, Docker Image Cleanup

Housekeeping, removing the `hello-world` test image and its stopped container from Phase 2.

```bash
docker image ls
docker ps
docker ps -a
docker stop 06277dfd9d85
docker rm 06277dfd9d85
docker rmi hello-world:latest
```

The container ID will differ on a different run, use `docker ps -a` to find the actual ID for the `hello-world` container before stopping and removing it.

## Phase 7, Python Virtual Environment Support and Utilities

```bash
sudo apt install python3-venv
sudo apt install tree
```

`python3-venv` was installed twice in this recording, the second attempt confirmed it was already present, this is not an error, just a repeated step.

One installation attempt in this phase failed and is worth knowing about rather than repeating:

```bash
sudo apt install pyang
```

This failed with `Unable to locate package pyang`, pyang is not available as an Ubuntu apt package. It is a Python package, if it is needed later in the course it should be installed with `pip install pyang` inside the relevant virtual environment instead.

## Phase 8, NetBox via netbox-docker

```bash
cd
git clone -b release https://github.com/netbox-community/netbox-docker.git
cd netbox-docker
cp docker-compose.override.yml.example docker-compose.override.yml
nano docker-compose.override.yml
```

The override file was edited to set at least the following, visible in the recording:

```yaml
services:
  netbox:
    ports:
      - "8000:8080"
    environment:
      SKIP_SUPERUSER: "false"
      SUPERUSER_EMAIL: "admin@example.com"
      SUPERUSER_NAME: "admin"
      SUPERUSER_PASSWORD: "admin"
      TZ: America/Halifax
```

See the Gaps section below, this file was edited more than once during troubleshooting later in the session, so this snapshot may not exactly match the final working version. Treat the actual file on the VM as the source of truth for exact contents.

Pull and bring up the stack:

```bash
docker compose pull
docker compose up -d
```

In this recording, `docker compose up -d` needed several attempts before NetBox came up healthy, including one interrupted attempt (Ctrl+C) and a step where the override file was backed up and removed entirely partway through troubleshooting:

```bash
cp docker-compose.override.yml docker-compose.override.yml.bk
rm docker-compose.override.yml
docker compose up -d
```

The exact cause of the slow or failed startups is not resolvable from the recording alone, but the end state was healthy. Confirm success with:

```bash
docker compose ps
sudo systemctl status netbox netbox-rq nginx
```

A superuser account may already exist from the `SUPERUSER_` environment variables above. If one is needed manually:

```bash
docker compose exec netbox /opt/netbox/netbox/manage.py createsuperuser
```

This command appears in the recording's shell history but was not clearly executed in this particular session, include it only if a superuser account does not already exist.

## Phase 9, gNMIc CLI Tool

```bash
sudo bash -c "$(curl -sL https://get-gnmic.openconfig.net)"
```

This installed gnmic 0.47.0 into `/usr/local/bin`.

## Phase 10, Batfish Image

```bash
docker pull batfish/allinone
```

## Gaps and Things Worth Double-Checking

A few spots in the recording could not be fully or confidently reconstructed. None of these are guesses, each is called out specifically rather than silently papered over.

The `docker-compose.override.yml` content shown in Phase 8 is the first version of the file as seen early in the editing session. The recording shows eight separate full-screen editing sessions in that same troubleshooting window, and a full-screen program clearing the terminal does not leave its intermediate states in the recording, only whatever was last drawn on screen survives. The file was also backed up to `docker-compose.override.yml.bk` and briefly deleted entirely partway through troubleshooting. The safest source of truth for the exact final settings is the live file on the VM, or the `.bk` backup if it still exists, rather than this document.

The `clab_admins` group step suggested by the containerlab installer's own output does not appear to have actually been run in this recording. Worth confirming whether containerlab commands on this VM currently require `sudo` as a result, and adding that step if so.

The `pyang` install failure in Phase 7 was left unresolved in the recording, nothing later in the session installed it another way. If a later phase of the install (not captured in this recording) needs it, it will need to be added via pip.

The exact container ID used in the Phase 6 cleanup step is specific to this one run and will differ every time, that step is written above as a pattern to follow rather than a literal command to copy.
