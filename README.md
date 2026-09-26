# mlflow-platform
Self-hosted MLflow on Kubernetes, with Postgres for tracking and Backblaze B2 for artifacts. Runs on a Raspberry Pi 5.

This repo contains the deployment for an MLFlow server with multiple instances of MLflow for different projects. They used a shared Postgres pod, and each MLflow instance will run on its own pod from a central image.

## Building the image

The image gets built for both my PC (amd64) and the Pi (arm64) and pushed to GHCR in one go. amd64 covers Intel and AMD chips so the i5 is fine.

One-off setup, only needed again if the token expires or the builder gets removed:

```
docker login ghcr.io -u ablinston
docker buildx create --name multiarch --driver docker-container --use
```

The login password is a classic personal access token with `write:packages`, not the GitHub password.

To build and push, bump the version tag each time:

```
docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/ablinston/mlflow-platform:0.1.0 --push .
```

`--push` sends it straight to GHCR so it won't show up in `docker images`. To run that version locally, pull it first:

```
docker pull ghcr.io/ablinston/mlflow-platform:0.1.0
```

compose.yaml still builds from the Dockerfile, so local dev doesn't need any of this.

## Stopping cluster on the Pi

`systemctl stop k3s` only stops k3s itself. Pods that are already running carry on, so use the killall script to stop everything:

```
sudo systemctl stop k3s
sudo k3s-killall.sh
```

It starts again on the next boot. To stop that as well, and to turn it back on later:

```
sudo systemctl disable k3s
sudo systemctl enable --now k3s
```
