# Run a crawl in Google Cloud Platform

Documentation and scripts to launch an OpenWPM crawl on a Kubernetes cluster on GCP GKE.

For more detailed explanations about what is going on here, see [./openwpm-crawler/deployment/gcp/README.md](./openwpm-crawler/deployment/gcp/README.md).

## Prerequisites

- Access to GCP and the ability to provision resources in a GCP project
- [Google SDK](https://cloud.google.com/sdk/) installed locally
    - This will allow us to provision resources from CLI
- [Docker](https://hub.docker.com/search/?type=edition&offering=community)
    - We will use this to build the OpenWPM docker container

For the remainder of these instructions, you are assumed to be in the `crawl-engineering/gcp/` folder (the same folder as this readme), and you should have the following env var set:

```
export PROJECT="srg-team-sandbox"
```

Also, make sure that all git submodules are checked out properly.

## (One time) Provision GCP Resources

```
gcloud auth login --no-launch-browser
gcloud config set project $PROJECT
gcloud config set compute/zone us-central1-f
gcloud components install kubectl
../openwpm-crawler/deployment/gcp/start_gke_cluster.sh crawl
gcloud container clusters get-credentials crawl
gcloud redis instances create crawlredis --size=1 --region=us-central1 --redis-version=redis_4_0
```

## (Optional) Configure sentry credentials

Adapt `foo` to match the Sentry DSN:
```
kubectl create secret generic sentry-config \
--from-literal=sentry_dsn=foo
```

To run crawls without Sentry, remove the following from the crawl config after it has been generated below:
```
        - name: SENTRY_DSN
          valueFrom:
            secretKeyRef:
              name: sentry-config
              key: sentry_dsn
```

## (One time) Allow the cluster to access AWS S3

Makes the AWS credentials stored in `~/.aws/credentials` available to kubectl:
```
../openwpm-crawler/deployment/gcp/aws_credentials_as_kubectl_secrets.sh
```

## Run the crawl

Follow either `Pre-crawl` or `Main crawl` based on what kind of crawl you are about to run.

### Pre-crawl

#### Build and push Docker images to GCR

Build and push the pre-crawl image:
```
cd ../../crawl-prep; docker build -t gcr.io/$PROJECT/crawl-prep .; cd -
gcloud auth configure-docker
docker push gcr.io/$PROJECT/crawl-prep
```

#### Configure the pre-crawl

This will set you up with a new pre-crawl config that you can customize before running the crawl. Change `foo` to reflect the purpose of the crawl. It will be prefixed automatically by today's date.
```
../new-pre-crawl-directory.sh gcp pre_crawl_X
```
After running this, set the `$CRAWL_CONFIG_YAML` as per the output from the above script.

### Main crawl

#### (Optional) Build and push Docker images to GCR

If none of [the pre-built OpenWPM Docker images](https://hub.docker.com/r/openwpm/openwpm/tags) are sufficient:
```
cd ../OpenWPM; docker build -t gcr.io/$PROJECT/openwpm .; cd -
gcloud auth configure-docker
docker push gcr.io/$PROJECT/openwpm
```
Remember to change the `crawl.yaml` to point to `image: gcr.io/$PROJECT/openwpm`.

#### Prepare the stack and load the site list for the crawl

Launch a temporary redis-box pod deployed to the cluster which we use to interact with the above Redis instance:
```
kubectl apply -f ../openwpm-crawler/deployment/gcp/redis-box.yaml
```

Use the following output:
```
gcloud redis instances describe crawlredis --region=us-central1
```
... to set the corresponding env var:

```
export REDIS_HOST=10.0.0.3
```

Then load the site into redis:
```
../openwpm-crawler/deployment/load_site_list_into_redis.sh crawl-queue-a ../../lists/tranco_20190814_top5000.ranked.csv
../openwpm-crawler/deployment/load_site_list_into_redis.sh crawl-queue-b ../../lists/tranco_20190814_top5000.ranked.csv
../openwpm-crawler/deployment/load_site_list_into_redis.sh crawl-queue-c ../../lists/tranco_20190814_top5000.ranked.csv
```

#### Configure the crawl

This will set you up with a new crawl config that you can customize before running the crawl. Change `foo` to reflect the purpose of the crawl. It will be prefixed automatically by today's date.
```
../new-crawl-directory.sh gcp webcompat_test_crawls_2/a_control
../new-crawl-directory.sh gcp webcompat_test_crawls_2/b_chrome_ua
../new-crawl-directory.sh gcp webcompat_test_crawls_2/c_blocking_addons
```
After running this, set the `$CRAWL_CONFIG_YAML` as per the output from the above script.

### Scale up the cluster before running the crawl

Some nodes including the master node can become temporarily unavailable  during cluster auto-scaling operations. When larger new crawls are started, this can cause disruptions for a couple of minutes after the crawl has started.

To avoid this, set the amount of nodes before starting the crawl:

```
gcloud container clusters resize crawl --num-nodes=15
```

Another useful practice is to [manually upgrade the cluster master if necessary](https://cloud.google.com/kubernetes-engine/docs/how-to/upgrading-a-cluster#upgrade_master) before running a crawl, since otherwise this may be performed automatically right after executing your crawls, causing downtime:

```
gcloud container clusters upgrade crawl --master
```

## Start the crawl

```
kubectl create -f "$CRAWL_CONFIG_YAML"
```

### Monitor the crawl

#### Queue status (only relevant for the Main crawl)

Launch redis-cli:
```
kubectl exec -it redis-box -- sh -c "redis-cli -h $REDIS_HOST"
```

Current length of the queue:
```
llen crawl-queue-a
llen crawl-queue-b
llen crawl-queue-c
```

Amount of queue items marked as processing:
```
llen crawl-queue-a:processing
llen crawl-queue-b:processing
llen crawl-queue-c:processing
```

Contents of the queue:
```
lrange crawl-queue-a 0 -1
lrange crawl-queue-b 0 -1
lrange crawl-queue-c 0 -1
```

#### Crawl progress and logs

Check out the [GCP GKE Console](https://console.cloud.google.com/kubernetes/workload)

Also:
```
watch kubectl top nodes
watch kubectl top pods --selector=job-name=crawl
watch kubectl get pods --selector=job-name=crawl
watch kubectl top pods --selector=job-name=pre-crawl
watch kubectl get pods --selector=job-name=pre-crawl
```

#### View Job logs via GCP Stackdriver Logging Interface

- Visit [GCP Logging Console](https://console.cloud.google.com/logs/viewer)
- Select `GKE Container`

### Inspecting crawl results

The crawl data will end up in Parquet format in the S3 bucket that you configured.

### Clean up created pods, services and local artifacts

```
kubectl delete -f "$CRAWL_CONFIG_YAML"
gcloud redis instances delete crawlredis --region=us-central1
kubectl delete -f ../openwpm-crawler/deployment/gcp/redis-box.yaml
```

### Decrease the size of the cluster while it is not in use

While the cluster has auto-scaling activated, and thus should scale down when not in use, it can sometimes be slow to do this or fail to do this adequately. In these instances, it is a good idea to set the number of nodes to 0 or 1 manually:

```
gcloud container clusters resize crawl --num-nodes=1
```

It will still auto-scale up when the next crawl is executed.

### Deleting the GKE Cluster

If crawls are not to be run and the cluster need not to be accessed within the next hours or days, it is safest to delete the cluster:
```
gcloud container clusters delete crawl
```

### Troubleshooting

In case of any unexpected issues, rinse (clean up) and repeat. If the problems remain, file an issue against https://github.com/mozilla/openwpm-crawler.
