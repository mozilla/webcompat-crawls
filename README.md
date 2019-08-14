# Webcompat Crawls

Configuration and instructions used to crawls top sites using a specially instrumented version of Firefox gathering information about 

## Generate the seed list via a series of pre-crawls

See [./crawl-prep/README.md](./crawl-prep/README.md).

## Run an OpenWPM crawl in Google Cloud Platform

See [./crawl-engineering/gcp/README.md](./crawl-engineering/gcp/README.md).

## Developer notes

To update the OpenWPM Crawler and crawl-prep submodules to the latest commits in the remotely tracked branches:

```
git submodule update --remote
```
