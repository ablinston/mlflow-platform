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

### If the arm64 build fails

If the arm64 half dies during the pip install with exit code 255, that's the emulator crashing, not a missing package. Docker Desktop puts its own older QEMU back every time it restarts (PC reboot, Docker Desktop update, `wsl --shutdown`), so after a restart run this once before building:

```
docker run --privileged --rm tonistiigi/binfmt --install arm64
```

The arm64 build takes around 40 minutes under emulation so don't assume it's hung. `docker stats` shows the `buildx_buildkit_multiarch0` container using CPU while it's still going.

requirements.txt is a full `pip freeze` of the image I tested with Compose, so every package is pinned and not just the three I actually use. Without that SQLAlchemy 2.1 got pulled in, which changed the default Postgres driver to psycopg and broke the connection. If I change anything, freeze it again from a working container:

```
docker compose exec -T mlflow python -m pip freeze | Out-File -Encoding ascii requirements.txt
```

Use `Out-File -Encoding ascii` rather than `>` in Windows PowerShell, `>` saves it as UTF-16.

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

## Adding a new MLflow instance

Each project gets its own MLflow instance, all running the same image in the `mlflow` namespace. They share the one Postgres but each has its own database, user, B2 prefix and key. `mlflow-sandbox` is the template. Below, `<name>` is the new instance, e.g. `projecta`.

1. In Backblaze, create a new application key for the `ab-mlflow-artifacts` bucket with read and write access and the file name prefix set to `mlflow-<name>/`. Copy the key straight away, it's only shown once.

2. Create a database and user for it. Open psql in the Postgres pod:

   ```
   kubectl exec -it postgres-0 -n mlflow -- psql -U mlflow -d postgres
   ```

   Then run this, with a new password (`openssl rand -hex 16`, letters and numbers only as it goes in a URL):

   ```
   CREATE USER mlflow_<name> WITH PASSWORD '<password>';
   CREATE DATABASE mlflow_<name> OWNER mlflow_<name>;
   REVOKE CONNECT ON DATABASE mlflow_<name> FROM PUBLIC;
   \q
   ```

   The REVOKE stops the other instances' users connecting to this database.

3. Create `secrets/mlflow-<name>.env` with the real values written out, there's no `${}` substitution:

   ```
   MLFLOW_BACKEND_STORE_URI=postgresql://mlflow_<name>:<password>@postgres:5432/mlflow_<name>
   AWS_ACCESS_KEY_ID=<keyID>
   AWS_SECRET_ACCESS_KEY=<applicationKey>
   ```

   Then turn it into a Secret:

   ```
   kubectl create secret generic mlflow-<name>-secrets -n mlflow --from-env-file=secrets/mlflow-<name>.env
   ```

4. Copy `k8s/mlflow-sandbox.yaml` to `k8s/mlflow-<name>.yaml` and change every `sandbox` to `<name>`. That covers the ConfigMap, Deployment and Service names, the `app` labels, the Secret and ConfigMap references and the prefix in `MLFLOW_ARTIFACTS_DESTINATION`. The labels matter most, if two instances share a label the Services will send traffic to both.

   Also give it its own `nodePort` (sandbox is 30500, so 30501, 30502 and so on).

5. Apply it and wait for the pod to show `1/1 Running`:

   ```
   kubectl apply -f k8s/mlflow-<name>.yaml
   kubectl get pods -n mlflow -w
   ```

6. On the Pi, open the new port to the home network only:

   ```
   sudo ufw allow from 192.168.1.0/24 to any port 30501 proto tcp
   ```

   Swap in the real network range and port.

7. Go to `http://<pi-ip>:30501` and check it loads, then log a test run and check the artifact turns up under `mlflow-<name>/` in the bucket.

To take an instance offline without deleting anything, scale it to 0. Set `replicas: 0` in its file and apply, otherwise the next apply brings it back.

```
kubectl scale deployment mlflow-<name> -n mlflow --replicas=0
```
