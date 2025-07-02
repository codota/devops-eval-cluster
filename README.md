# devop-eval-cluster

A GKE cluster terraform definition, used to set up an evaluation for devops candidates.

It sets up a simple GKE cluster with a gateway, that can be used to expose public services.
It also defines a cloud sql postgres database, that can be used by these services.

## Setup

```
cd terraform/
terraform apply
```

This will take a few minutes to run.

After it is done:

```
export DB_URL=$(terraform output -raw database_url)
gcloud container clusters get-credentials devops-eval-cluster --project devops-eval-463110 --region us-central1
```

Then clone the [service repo](https://github.com/codota/devops-eval-service) and run

```
docker buildx build --platform linux/amd64 . -t us-central1-docker.pkg.dev/devops-eval-463110/docker-repository/tasks-service:1.0.5 --push
helm upgrade --install -n eval --create-namespace tasks helm/ --set "database.url=$DB_URL"
```

This should setup the service with a couple of issues that cause it to not work.

You will get an error if you run

```
curl devops-eval.tabnine.com/api/tasks
```