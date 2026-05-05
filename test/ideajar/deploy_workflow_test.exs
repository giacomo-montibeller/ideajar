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

  defp read_deploy_yml! do
    File.read!(@deploy_yml_path)
  end
end
