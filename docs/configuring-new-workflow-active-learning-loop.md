---
layout: default
title: "Active Learning Loop: New Workflow Configuration"
permalink: /new-workflow-configuration/
---

# Active Learning Loop: New Workflow Configuration

This guide details the complete procedure for integrating a fresh Zooniverse workflow into the active learning loop.

The following areas are addressed:

- Components managed by KaDE.
- The runtime contract transmitted from KaDE to BaJoR.

## System Boundary

The active learning cycle is composed of four primary interconnected components:

- `Panoptes`: Functions as the primary owner of project data, including workflows, subject media, and subject sets.
- `Caesar`: Handles the aggregation of volunteer classifications and transmits the resulting reduced task data to KaDE.
- `KaDE`: Manages workflow context and reduction ingestion; it is responsible for exporting training catalogues, initiating training/prediction jobs, and performing subject set migrations.
- `BaJoR`: Operates as the scheduler for Azure Batch training and prediction tasks, executing them based on the specific configurations provided by KaDE.

Within the active learning ecosystem, KaDE serves as the authoritative repository for workflow-specific configuration data. BaJoR is designed to operate as a stateless scheduler, deriving all necessary runtime parameters directly from the job request; deployment defaults are utilized strictly as a fallback mechanism for workflows that have not yet undergone migration.

## Prerequisites

Prior to establishing the KaDE configuration, collect these identifiers and runtime assets:

- Zooniverse project and workflow IDs.
- The active subject set ID.
- The pool subject set ID, containing the candidate subjects targeted for prediction tasks.
- KaDE module and extractor names.
- Caesar task keys required for transmitting reductions into the KaDE ecosystem.
- Specific reduction answer mappings associated with each task key.
- A container image name compatible with the BaJoR scheduler.
- Pathways for training and prediction scripts.
- The best checkpoint file promotion script path - possibly not needed as we are working on uploading to Hugging Face.
- A pretrained checkpoint reference.
- Optional model runtime parameters, including `fixed_crop` and `n_blocks`.

## KaDE Label Extraction Methodology

The KaDE system is required to transform data payloads originating from Caesar into structured training columns within CSV catalogues.

For existing GZ workflows, we use a predefined code-backed extractor, as of 27 May 2026:

- `galaxy_zoo.cosmic_dawn`
- `galaxy_zoo.decals`
- `galaxy_zoo.euclid`
- `galaxy_zoo.jwst_cosmos`

We use a DB-backed `LabelExtractorDefinition` for simple new workflows where each task key maps directly to answer labels. This avoids a Ruby code change when the transformation is only structured mapping.

Database-backed configuration schema:

```json
{
  "data_release_suffix": "example",
  "task_key_label_prefixes": {
    "T0": "smooth-or-featured"
  },
  "task_key_data_labels": {
    "T0": {
      "0": "smooth",
      "1": "featured",
      "2": "artifact"
    }
  }
}
```

With the above schema, Caesar is required to transmit reductions to the following endpoint:

```text
POST /reductions/<module_name>_<extractor_name>_t0
```

KaDE resolves that lookup key into `module_name`, `extractor_name`, and task key `T0`.

## KaDE Extractor Registration and Initialization

For workflows utilizing database-backed extractors, it is necessary to instantiate an enabled `LabelExtractorDefinition`. This definition must include the corresponding `module_name`, `extractor_name`, and associated `config` parameters.

The following Rails console command illustrates the creation of this configuration:

```ruby
LabelExtractorDefinition.create!(
  module_name: 'example_project',
  extractor_name: 'main',
  enabled: true,
  config: {
    data_release_suffix: 'example',
    task_key_label_prefixes: {
      T0: 'smooth-or-featured'
    },
    task_key_data_labels: {
      T0: {
        '0': 'smooth',
        '1': 'featured',
        '2': 'artifact'
      }
    }
  }
)
```

Regarding workflows utilizing code-backed extractors, the corresponding extractor class must be implemented within `app/modules/label_extractors` and formally registered inside `LabelExtractors::Registry`. Furthermore, comprehensive test coverage must be established to validate reduction extraction logic and ensure the accuracy of training export headers.

## Establishing and Updating KaDE Workflow Context

The `Context` record provides the structural link between a Zooniverse workflow and its associated subject sets, extractors, and Azure Batch execution parameters.

The following configuration fields must be specified:

- `workflow_id`
- `project_id`
- `active_subject_set_id`
- `pool_subject_set_id`
- `module_name`
- `extractor_name`
- `metadata.batch`

The authenticated KaDE API enables the modification of existing context records through the following `PATCH` request.

KaDE API context update:

```sh
curl -u "$KADE_BASIC_AUTH_USERNAME:$KADE_BASIC_AUTH_PASSWORD" \
  -H 'Content-Type: application/json' \
  -X PATCH https://kade-staging.zooniverse.org/contexts/CONTEXT_ID \
  -d '{
    "workflow_id": 12345,
    "project_id": 6789,
    "active_subject_set_id": 111,
    "pool_subject_set_id": 222,
    "module_name": "example_project",
    "extractor_name": "main",
    "metadata": {
      "batch": {
        "container_image_name": "zoobot.azurecr.io/pytorch:example",
        "training_script_path": "example/train_model_finetune_on_catalog.py",
        "prediction_script_path": "example/predict_catalog_with_model.py",
        "promote_script_path": "example/promote_best_checkpoint_to_model.sh",
        "pretrained_checkpoint_url": "example/pretrained.ckpt",
        "n_blocks": 3,
        "fixed_crop": {
          "lower_left_x": 0,
          "lower_left_y": 0,
          "upper_right_x": 224,
          "upper_right_y": 224
        }
      }
    }
  }'
```

Note that KaDE performs a deep-merge on the metadata object; consequently, specific `metadata.batch` attributes may be updated in subsequent patches without overwriting the entire batch configuration.

## KaDE Context Contract Validation

To ensure the established configuration resolves successfully, verify the context via the following authenticated request:

```sh
curl -u "$KADE_BASIC_AUTH_USERNAME:$KADE_BASIC_AUTH_PASSWORD" \
  https://kade-staging.zooniverse.org/contexts/CONTEXT_ID
```

Upon receipt of the payload, validate the following technical requirements:

- The `workflow_id`, `project_id`, `active_subject_set_id`, and `pool_subject_set_id` align with Zooniverse records.
- The `module_name` and `extractor_name` reference a valid code-backed extractor or enabled `LabelExtractorDefinition`.
- The `metadata.batch` object utilizes only supported runtime keys.
- Script paths are defined as relative paths using forward slashes.
- Execution scripts for training and prediction utilize the `.py` extension.
- Promotion logic for checkpoints utilizes the `.sh` extension.
- The `pretrained_checkpoint_url` provides either a direct HTTP(S) URI or a valid relative asset path.
- The `n_blocks` attribute is instantiated as a positive integer.
- The `fixed_crop` schema contains numeric values for all coordinate boundaries.

KaDE is configured to return a `422 Unprocessable Entity` response if batch metadata fails these validation criteria.

## Caesar Integration and Reduction Transmission

The target workflow must be instantiated within Caesar prior to configuration. The provided setup utility is designed to provision extractors, reducers, and subject rules for existing workflows rather than creating them from scratch.

The following Caesar helper script serves as the baseline for initialization:

```sh
python caesar/setup_caesar_workflow.py \
  --env staging \
  --workflow-id WORKFLOW_ID \
  --kade-api-username "$KADE_BASIC_AUTH_USERNAME" \
  --kade-api-password "$KADE_BASIC_AUTH_PASSWORD"
```

When establishing a new workflow, the script logic should be audited and customized to address the following requirements:

- Define all applicable workflow task keys.
- Provision question extractors for the specified task keys.
- Implement count reducers to govern classification thresholds.
- Configure stats reducers to generate the answer data required by KaDE.
- Assign a value to `NUM_CLASSIFICATIONS_BEFORE_SEND_TO_KADE`.
- Map each rule effect URL to the appropriate KaDE reduction lookup key:

```text
https://kade-staging.zooniverse.org/reductions/<module_name>_<extractor_name>_<task_key_lowercase>
```

Refer to the following example for the lookup key structure:

```text
https://kade-staging.zooniverse.org/reductions/example_project_main_t0
```

Ensure the rule effect is configured with `external_with_basic_auth` and includes the requisite KaDE API credentials.

## Validating Ingestion via Smoke Testing

After Caesar is configured, let a small number of test classifications flow through, or post a representative reduction payload to the KaDE reduction endpoint in staging.

Verify the following:

- The `POST /reductions/<lookup_key>` operation concludes with a successful response code.
- The ingested data is visible upon executing a `GET /reductions?zooniverse_subject_id=SUBJECT_ID` request.
- The persisted record correctly maps the `workflow_id`, `subject_id`, `task_key`, and all associated extracted labels.
- Unknown task keys or answer keys fail during testing, not during production training export.

## Training Data Generation and Verification

The following procedure outlines the generation of a training data catalogue for the specified workflow via the KaDE API.

KaDE training export request:

```sh
curl -u "$KADE_BASIC_AUTH_USERNAME:$KADE_BASIC_AUTH_PASSWORD" \
  -H 'Content-Type: application/json' \
  -X POST https://kade-staging.zooniverse.org/training_data_exports \
  -d '{ "training_data_export": { "workflow_id": 12345 } }'
```

To monitor the progression and details of the generated asset, execute the following retrieval command:

```sh
curl -u "$KADE_BASIC_AUTH_USERNAME:$KADE_BASIC_AUTH_PASSWORD" \
  https://kade-staging.zooniverse.org/training_data_exports/EXPORT_ID
```

Validation of export integrity:

- Confirm the job status transitions to `finished`.
- Ensure the CSV file is accessible at the specified `storage_path`.
- Verify that CSV column headers align with the registered extractor schema.
- Validate that subject media locations and classification label data are correctly instantiated.

## Executing Training Operations via KaDE

The training lifecycle utilizes the most recent successful training export associated with the specific workflow. Within the active learning loop, the retraining worker identifies the relevant `Context` record by resolving the `workflow_id`, constructs the necessary BaJoR execution parameters from the `Context.metadata.batch` object, and initiates the request to the BaJoR scheduler.

The structured payload for the BaJoR training request is formatted as follows:

```json
{
  "manifest_path": "/training/catalogues/staging/workflow-12345-2026-05-27T10:00:00Z.csv",
  "opts": {
    "workflow_name": "main",
    "fixed_crop": {
      "lower_left_x": 0,
      "lower_left_y": 0,
      "upper_right_x": 224,
      "upper_right_y": 224
    },
    "n_blocks": 3,
    "container_image_name": "zoobot.azurecr.io/pytorch:example",
    "training_script_path": "example/train_model_finetune_on_catalog.py",
    "promote_script_path": "example/promote_best_checkpoint_to_model.sh",
    "pretrained_checkpoint_url": "example/pretrained.ckpt"
  }
}
```

While KaDE provides the `workflow_name` attribute for compatibility with legacy schemas, workflows that have completed migration must derive all model-specific runtime parameters directly from the `metadata.batch` configuration.

## Training Supervision and Model Promotion Audit

Utilize the KaDE training metadata and the associated BaJoR job URI to oversee the execution progress.

Technical validation requirements:

- The BaJoR execution lifecycle reaches a successful termination state.
- KaDE formally registers the training job status as completed.
- Output results are instantiated within the reported training results directory.
- The promotion script successfully migrates the targeted checkpoint to the prediction-ready path.
- The promoted checkpoint name/path matches the workflow's prediction `pretrained_checkpoint_url` defined in the workflow context.

## Initiating Prediction Cycles via KaDE

Prediction jobs resolve their context by `active_subject_set_id`. It is critical to ensure the prediction `subject_set_id` matches the established `active_subject_set_id` within the record.

The resulting BaJoR prediction payload structure is as follows:

```json
{
  "manifest_url": "https://kadeactivelearning.blob.core.windows.net/predictions/catalogues/staging/export-1.json",
  "opts": {
    "workflow_name": "main",
    "fixed_crop": {
      "lower_left_x": 0,
      "lower_left_y": 0,
      "upper_right_x": 224,
      "upper_right_y": 224
    },
    "container_image_name": "zoobot.azurecr.io/pytorch:example",
    "prediction_script_path": "example/predict_catalog_with_model.py",
    "pretrained_checkpoint_url": "example/pretrained.ckpt"
  }
}
```

Note that KaDE systematically excludes training-specific parameters when constructing the prediction options object.

## Assessing BaJoR Prediction Runtime Compatibility

The integrity of the prediction selection process must be confirmed by validating the following technical requirements:

- The prediction script exists under the mounted prediction code directory.
- The prediction script architecture supports the following BaJoR-supplied arguments:
  - `--checkpoint-path`
  - `--catalog-url`
  - `--save-path`
  - Optional `--fixed-crop`
- The specified checkpoint target resolves to the appropriate model asset.
- Output results are formally written to `predictions.json`.
- The generated prediction schema is compatible with the KaDE result processor.

## Auditing Subject Selection and Panoptes Integration

Following the processing of prediction results, verify the accuracy of the subject migration lifecycle:

- KaDE creates `Prediction` records for all scored subjects.
- Targeted subjects are migrated to the defined active subject set.
- Subject removal from the candidate pool occurs according to defined parameters.
- The prediction threshold and randomisation logic yield the projected subject count.
- Panoptes reflects the new subject distribution within the active workflow.
