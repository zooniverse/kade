# Sloan Knowledge and Discovery Engine

Knowledge and Discovery Engine - KaDE

The Zooniverse API for supporting knoweldge extraction and discovery for machine learning systems.

## Requirements

KaDE uses Docker to manage its environment, the requirements listed below are also found in `docker-compose.yml`. The means by which a new instance is created with Docker is located in the `Dockerfile`. If you plan on using Docker to manage this application, skip ahead to Installation.

KaDE is primarily developed against stable MRI, currently 3.1. If you're running MRI Ruby you'll need to have the Postgresql client libraries installed as well as have [Postgresql](http://postgresql.org) version 13+ running.

Optionally, you can also run the following:

* [Redis](http://redis.io) version >= 6

## Installation

We only support running KaDE via Docker and Docker Compose. If you'd like to run it outside a container, see the above Requirements sections to get started.

## Usage

1. `docker-compose build`

2. `docker-compose up` to start the containers

    * If the above step reports a missing database error, kill the docker-compose process or open a new terminal window in the current directory and then run `docker-compose run --rm api bundle exec rake db:setup` to setup the database.

    * Alternatively use the following command to start a bash terminal session in the container `docker compose run --service-ports --rm api bash`

    * Run the tests in the container `docker compose run --service-ports --rm api RAILS_ENV=test bin/rspec`

## Documentation Site

The `docs/` directory is configured as a lightweight GitHub Pages site. The New Workflow Configuration runbook is available in the repo at `docs/configuring-new-workflow-active-learning-loop.md` and will publish as `/new-workflow-configuration/`.

Preview the site locally with:

```sh
cd docs
bundle config set path vendor/bundle
bundle install
bundle exec jekyll serve --host 127.0.0.1 --port 4000

```

Then open `http://127.0.0.1:4000/new-workflow-configuration/`.

To enable it on GitHub:

1. Open the repository `Settings` page.
2. Go to `Pages`.
3. Under `Build and deployment`, set `Source` to `Deploy from a branch`.
4. Select the default branch and `/docs` as the folder.
5. Save the settings.

For a normal project Pages site, the published runbook URL will be:

```text
https://<owner>.github.io/<repository>/new-workflow-configuration/
```

## Admin UI

KaDE includes a server-rendered Rails admin surface for internal operators. When running locally through Docker Compose, open `http://localhost:3001/admin`.

### Authentication

The admin UI is protected with HTTP basic auth. Configure dedicated admin credentials with:

* `ADMIN_BASIC_AUTH_USERNAME`
* `ADMIN_BASIC_AUTH_PASSWORD`

If these values are not set, the app falls back to `API_BASIC_AUTH_USERNAME` and `API_BASIC_AUTH_PASSWORD`. In development, those API credentials default to `kade-user` / `kade-password`. Production and staging deployments should set admin-specific credentials and keep them separate from service-to-service API credentials.

### Admin resources

The admin navigation exposes the following resources:

* `Contexts` (`/admin/contexts`) - list, create, view, edit, and delete context records. Context forms support workflow ID, project ID, active subject set ID, pool subject set ID, module name, extractor name, and metadata JSON. The admin flow uses the same validation as the JSON API for integer fields, metadata shape, `metadata.batch` runtime configuration, and known module/extractor pairs.
* `Label Extractors` (`/admin/label_extractor_definitions`) - list, create, edit, enable, disable, and delete DB-backed label extractor definitions. Definitions are keyed by `module_name` and `extractor_name`; config is edited as structured JSON and validated against the configurable extractor schema. Context detail pages show matching definitions for that context's module/extractor pair.
* `Subjects` (`/admin/subjects`) - list and view subjects, including their context, metadata, locations, and reductions. The list can be filtered with `?zooniverse_subject_id=...`.
* `Reductions` (`/admin/reductions`) - list and view reductions, including their linked subject, labels, and raw payload. The list can be filtered with `?zooniverse_subject_id=...`.
* `Training Exports` (`/admin/training_data_exports`) - list and view training data export records.
* `Prediction Jobs` (`/admin/prediction_jobs`) - list and view prediction job records, including state, messages, manifests, results, and subject set settings.
* `Training Jobs` (`/admin/training_jobs`) - list and view training job records, including state, messages, manifests, results, and workflow IDs.

Admin list pages support `?page=` and `?page_size=` query parameters. The default page size is 25 records and `page_size` is clamped between 1 and 100.

### Operational actions

Context detail pages include manual actions for:

* Triggering a prediction run, which enqueues `PredictionManifestExportJob` for the context.
* Triggering a training run, which enqueues `RetrainZoobotJob` for the context.
* Deleting the context. Deletion uses the model restrictions, so it fails while subjects still reference that context.

The admin UI is intended as an internal maintenance surface for inspection and controlled manual corrections. Use the JSON API for service-to-service integration.

## API

The KaDE service has a json API for the following resource

All `GET /$resource/` list end points allow the use of `?page_size=100` query param to change the default number of returned objects.

### Reductions Resource

#### List Reduction resources

`GET /reductions/` List all reductions
`GET /reductions/?zooniverse_subject_id=85095` Filter the list for reductions that match the zooniverse API ID

Returns a JSON payload listing the last 10 reductions resources by default

``` javascript
[
  {
    'id': 4,
    'reducible': {
      'id': 3,
      'type': 'Workflow'
    },
    'data': {
      '0' => 3,
      '1' => 9,
      '2' => 0
    },
    'subject': {
      'id': 999,
      'metadata': { '#name' => '8000_231121_468' },
      'created_at': '2021-08-06T11:08:53.918Z',
      'updated_at': '2021-08-06T11:08:53.918Z'
    },
    'created_at': '2021-08-06T11:08:54.000Z',
    'updated_at': '2021-08-06T11:08:54.000Z'
  }
]
```

#### Get the details of a Reduction resource

`GET /reductions/$id`

Returns a JSON payload describing the reduction resource

``` javascript
{
    'id': 4,
    'reducible': {
      'id': 3,
      'type': 'Workflow'
    },
    'data': {
      '0' => 3,
      '1' => 9,
      '2' => 0
    },
    'subject': {
      'id': 999,
      'metadata': { '#name' => '8000_231121_468' },
      'created_at': '2021-08-06T11:08:53.918Z',
      'updated_at': '2021-08-06T11:08:53.918Z'
    },
    'created_at': '2021-08-06T11:08:54.000Z',
    'updated_at': '2021-08-06T11:08:54.000Z'
  }
```

### Create a new Reductions resource

This resulting reduction resource represents the known aggregated state of a subject.

This end point is meant to be used by Caesar system to post aggregated subject reductions into this system.

`POST /reductions/`

Requires a JSON payload for creating a Reduction resource. The payload is static and derived from the Caesar system internals.

``` javascript
{
  'reduction': {
    'id': 4,
    'reducible': {
      'id': 3,
      'type': 'Workflow'
    },
    'data': {
      '0' => 3,
      '1' => 9,
      '2' => 0
    },
    'subject': {
      'id': 999,
      'metadata': { '#name' => '8000_231121_468' },
      'created_at': '2021-08-06T11:08:53.918Z',
      'updated_at': '2021-08-06T11:08:53.918Z'
    },
    'created_at': '2021-08-06T11:08:54.000Z',
    'updated_at': '2021-08-06T11:08:54.000Z'
  }
}
```

### Training Data Exports Resource

#### Create a new Training Data Export resource

This resulting export resource will link to a csv training data catalogue at a hosted storage location

`POST /training_data_exports/`

Requires a JSON payload for creating a training data export for a known workflow, e.g.

``` javascript
{ 'training_data_export': { 'workflow_id': 3 } }
```

Example using Curl to create an export against localhost

``` sh
curl -u kade-user:kade-password -H 'Content-Type: application/json' -X POST http://localhost:3001/training_data_exports -d '{ "training_data_export": { "workflow_id": 3 } }'
```

#### Get the details of a Training Data Export resource

`GET /training_data_exports/$id`

Returns a JSON payload describing the export resource

``` javascript
{
 'id': 1,
 'workflow_id': 3,
 'state' => 'started',
 'storage_path' => '/staging/training_catalogues/workflow-3.csv'
}
```

#### List Training Data Export resources

`GET /training_data_exports/`

Returns a JSON payload listing the last 10 export resources

``` javascript
[
  {
    'id': 1,
    'workflow_id': 3,
    'state' => 'started',
    'storage_path' => '/staging/training_catalogues/workflow-3.csv'
  }
]
```

### Subjects Resource

#### List Subject resources

`GET /subjects/` List all subjects
`GET /subjects/?zooniverse_subject_id=85095` Filter the list for subjects that match the zooniverse API ID

Returns a JSON payload listing the last 10 subject resources

``` javascript
[
  {
    'id': 1,
    'zooniverse_subject_id': 999,
    'metadata': { 'name': '#uniq-name!' },
    'context_id': 1,
    'locations': [
      {
        'image/jpeg': 'https://panoptes-uploads.zooniverse.org/subject_location/2f2490b4-65c1-4dca-ba25-c44128aa7a39.jpeg'
      }
    ]
  }
]
```

#### Get the details of a Subject resource

`GET /subjects/$id`

Returns a JSON payload describing the subject resource

``` javascript
{
  'id': 1,
  'zooniverse_subject_id': 999,
  'metadata': { 'name': '#uniq-name!' },
  'context_id': 1,
  'locations': [
    {
      'image/jpeg': 'https://panoptes-uploads.zooniverse.org/subject_location/2f2490b4-65c1-4dca-ba25-c44128aa7a39.jpeg'
    }
  ]
}
```

### Prediction Jobs Resource

#### List Prediction Jobs resources

`GET /prediction_jobs/` List all prediction jobs

Returns a JSON payload listing the last 10 prediciton jobs resources

``` javascript
[
  {
    'id': 10,
    'service_job_url': 'https://bajor.zooniverse.org/prediction/job/job-id',
    'manifest_url': 'https://container.blob.core.windows.net/predictions/catalogues/production/export-1.json',
    'state': 'completed',
    'message': '',
    'created_at': '2022-11-25T10:55:00.551Z',
    'updated_at': '2022-11-25T11:09:19.891Z',
    'results_url': 'https://container.blob.core.windows.net/predictions/jobs/job_id/results/predictions.csv',
    'subject_set_id': 110267,
    'probability_threshold': 0.8,
    'randomisation_factor': 0.2
  }
]
```

#### Get the details of a Prediction Job resource

`GET /prediction_job/$id`

Returns a JSON payload describing the prediction job resource

``` javascript
{
    'id': 10,
    'service_job_url': 'https://bajor.zooniverse.org/prediction/job/job-id',
    'manifest_url': 'https://container.blob.core.windows.net/predictions/catalogues/production/export-1.json',
    'state': 'completed',
    'message': '',
    'created_at': '2022-11-25T10:55:00.551Z',
    'updated_at': '2022-11-25T11:09:19.891Z',
    'results_url': 'https://container.blob.core.windows.net/predictions/jobs/job_id/results/predictions.csv',
    'subject_set_id': 110267,
    'probability_threshold': 0.8,
    'randomisation_factor': 0.2
  }
```

### Create a new Prediction Job resource

This resulting prediction job resource represents a submitted for processing prediction job.

This end point is meant to be used by authenticated clients that want to schedule prediction jobs.

`POST /prediction_jobs/`

Requires a JSON payload for creating a Prediction Job resource.

``` javascript
{
  'prediction_job': {
    'manifest_url': 'https://example.com/hosted-manifest.csv'
  }
}
```

### Training Jobs Resource

#### List Training Jobs resources

`GET /training_jobs/` List all training jobs

Returns a JSON payload listing the last 10 training jobs resources

``` javascript
[
  {
    'id': 10,
    'service_job_url': 'https://bajor.zooniverse.org/training/job/job-id',
    'manifest_url': 'https://container.blob.core.windows.net/training/catalogues/production/export-1.json',
    'state': 'completed',
    'message': '',
    'created_at': '2022-11-25T10:55:00.551Z',
    'updated_at': '2022-11-25T11:09:19.891Z',
    'results_url': 'https://container.blob.core.windows.net/training/jobs/job_id/results/',
    'workflow_id': 1
  }
]
```

#### Get the details of a Training Job resource

`GET /training_job/$id`

Returns a JSON payload describing the training job resource

``` javascript
{
    'id': 10,
    'service_job_url': 'https://bajor.zooniverse.org/training/job/job-id',
    'manifest_url': 'https://container.blob.core.windows.net/training/catalogues/production/export-1.json',
    'state': 'completed',
    'message': '',
    'created_at': '2022-11-25T10:55:00.551Z',
    'updated_at': '2022-11-25T11:09:19.891Z',
    'results_url': 'https://container.blob.core.windows.net/training/jobs/job_id/results/',
    'workflow_id': 1
}
```
