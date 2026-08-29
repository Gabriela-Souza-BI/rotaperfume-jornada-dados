# rotaperfume-jornada-dados

📚 **About this project:** This is a course-guided project, built to apply Databricks concepts in practice — business views, metadata auditing, Genie Space — while also exploring Claude Code as a daily development tool.   It's my first hands-on project in this area; the content follows course instructions and is not fully solo-authored. Future projects will be developed independently.

## What this project does
This is a data pipeline built on Databricks that simulates the data journey of a perfume e-commerce business — ingesting raw sales data, transforming it into clean, reliable tables, and modeling it into business-facing views. Along the way it also covers metadata auditing (tracking where data comes from and how it changes) and a Genie Space setup for natural-language querying over the data.
The goal wasn't just to move data from point A to B, but to go through the full journey a real analytics engineering project involves: raw ingestion, transformation, validation, documentation, and finally making the data usable for business questions.

## Project structure
* `src/`: Python source code for this project.
* `resources/`:  Resource configurations (jobs, pipelines, etc.)
* `tests/`: Unit tests for the shared Python code.
* `fixtures/`: Fixtures for data sets (primarily used for testing).


## Getting started

Choose how you want to work on this project:

(a) Directly in your Databricks workspace, see
    https://docs.databricks.com/dev-tools/bundles/workspace.

(b) Locally with an IDE like Cursor or VS Code, see
    https://docs.databricks.com/dev-tools/vscode-ext.html.

(c) With command line tools, see https://docs.databricks.com/dev-tools/cli/databricks-cli.html

If you're developing with an IDE, dependencies for this project should be installed using uv:

*  Make sure you have the UV package manager installed.
   It's an alternative to tools like pip: https://docs.astral.sh/uv/getting-started/installation/.
*  Run `uv sync --dev` to install the project's dependencies.


# Using this project using the CLI

The Databricks workspace and IDE extensions provide a graphical interface for working
with this project. It's also possible to interact with it directly using the CLI:

1. Authenticate to your Databricks workspace, if you have not done so already:
    ```
    $ databricks configure
    ```

2. To deploy a development copy of this project, type:
    ```
    $ databricks bundle deploy --target dev
    ```
    (Note that "dev" is the default target, so the `--target` parameter
    is optional here.)

    This deploys everything that's defined for this project.

3. Similarly, to deploy a production copy, type:
   ```
   $ databricks bundle deploy --target prod
   ```

4. To run a job or pipeline, use the "run" command:
   ```
   $ databricks bundle run
   ```

5. Finally, to run tests locally, use `pytest`:
   ```
   $ uv run pytest
   ```
