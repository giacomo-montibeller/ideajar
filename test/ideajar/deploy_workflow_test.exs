defmodule Ideajar.DeployWorkflowTest do
  @moduledoc """
  Slice 13 — pin the structural contract of `.github/workflows/deploy.yml`.

  The CD pipeline is mostly declarative YAML, so behavioral correctness
  is validated end-to-end by the first real `workflow_dispatch`
  post-merge (O4a). These tests are regression guards: they assert the
  lexical properties that a refactor could silently break — trigger
  surface, job gate, concurrency policy, secrets handling, step
  ordering, smoke-test logic — and they prevent OS guards (no rollback,
  no webhooks, no ci.yml drift) from quietly leaking back in.
  """
  use ExUnit.Case, async: true

  @deploy_yml_path Path.expand("../../.github/workflows/deploy.yml", __DIR__)

  describe "trigger + concurrency (Step 1)" do
    test "deploy.yml exists" do
      assert File.exists?(@deploy_yml_path),
             "expected #{@deploy_yml_path} to exist"
    end

    test "workflow_run targets ci.yml on completion" do
      assert read_deploy_yml!() =~
               """
                 workflow_run:
                   workflows: ["CI"]
                   types: [completed]
               """,
             "the three workflow_run keys must appear together as one trigger block"
    end

    test "workflow_dispatch is enabled for manual redeploy" do
      assert read_deploy_yml!() =~ "workflow_dispatch:"
    end

    test "deploy job gate matches the canonical if expression" do
      canonical =
        "(github.event_name == 'workflow_dispatch') || " <>
          "(github.event.workflow_run.conclusion == 'success' && " <>
          "github.event.workflow_run.head_branch == 'main')"

      assert read_deploy_yml!() =~ canonical,
             "deploy.yml must contain the canonical if expression verbatim — see plan W4"
    end

    test "deploy job gate does NOT use OR between conclusion and head_branch" do
      refute read_deploy_yml!() =~
               "conclusion == 'success' || github.event.workflow_run.head_branch",
             "OR-form would deploy on failed CI for main, or success for any branch"
    end

    test "concurrency serializes deploys without dropping queue" do
      content = read_deploy_yml!()
      assert content =~ "group: deploy-prod"
      assert content =~ "cancel-in-progress: false"
    end
  end

  describe "checkout + auth (Step 2)" do
    test "checkout uses fetch-depth 0" do
      content = read_deploy_yml!()
      assert content =~ "actions/checkout@v4"
      assert content =~ "fetch-depth: 0"
    end

    test "checkout ref pulls the validated SHA on workflow_run" do
      assert read_deploy_yml!() =~ "github.event.workflow_run.head_sha",
             "workflow_run trigger must check out the SHA that CI validated"
    end

    test "checkout ref falls back to main tip on workflow_dispatch" do
      assert read_deploy_yml!() =~ "refs/heads/main",
             "workflow_dispatch must check out refs/heads/main, not the workflow file SHA"
    end

    test "checkout ref does NOT use github.sha (typo trap or unsafe form)" do
      content = read_deploy_yml!()

      refute content =~ ~r/ref:\s*\$\{\{\s*github\.sha\s*\|\|/,
             "github.sha is always truthy on workflow_run, the fallback would never fire"

      refute content =~ "ref: ${{ github.sha }}",
             "github.sha for workflow_dispatch points to the workflow file SHA, not main tip"
    end

    test "installs gigalixir CLI via pipx" do
      assert read_deploy_yml!() =~ "pipx install gigalixir"
    end

    test "authenticates via GIGALIXIR_EMAIL + GIGALIXIR_API_KEY secrets" do
      content = read_deploy_yml!()
      assert content =~ "secrets.GIGALIXIR_EMAIL"
      assert content =~ "secrets.GIGALIXIR_API_KEY"
      assert content =~ "gigalixir login"
    end

    test "no echo or printf of GIGALIXIR_* secrets" do
      refute read_deploy_yml!() =~ ~r/(echo|printf).*GIGALIXIR_/,
             "secrets must never reach stdout"
    end

    test "adds the gigalixir remote with the app-name secret" do
      content = read_deploy_yml!()
      assert content =~ "secrets.GIGALIXIR_APP_NAME"
      assert content =~ ~s(gigalixir git:remote "$GIGALIXIR_APP_NAME")
    end
  end

  defp read_deploy_yml! do
    File.read!(@deploy_yml_path)
  end
end
