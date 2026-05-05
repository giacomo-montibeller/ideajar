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
  @ci_yml_path Path.expand("../../.github/workflows/ci.yml", __DIR__)
  @deploy_md_path Path.expand("../../docs/deploy.md", __DIR__)

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

    test "deploy job gate matches the canonical if expression on a single line" do
      canonical =
        "(github.event_name == 'workflow_dispatch') || " <>
          "(github.event.workflow_run.conclusion == 'success' && " <>
          "github.event.workflow_run.head_branch == 'main')"

      content = read_deploy_yml!()

      assert content =~ canonical,
             "deploy.yml must contain the canonical if expression verbatim — see plan W4"

      # Guard against a YAML reflow that breaks the expression across lines:
      # the canonical form must live on a single physical line so the
      # exact-substring check above is not silently bypassed by an editor
      # rewrapping it (which would change the test's meaning, not the
      # workflow's behavior).
      assert Enum.any?(String.split(content, "\n"), &String.contains?(&1, canonical)),
             "the canonical if expression must stay on a single line"
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

    test "authenticates by writing the secrets to a chmod-0600 ~/.netrc" do
      content = read_deploy_yml!()
      assert content =~ "secrets.GIGALIXIR_EMAIL"
      assert content =~ "secrets.GIGALIXIR_API_KEY"
      # ~/.netrc is the credentials store gigalixir reads at runtime — same
      # store `gigalixir login` uses internally, but bypasses the interactive
      # password prompt that even `-y` cannot suppress on a TTY-less CI runner.
      assert content =~ "~/.netrc"
      assert content =~ "chmod 0600"
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

  describe "push + migrate + ordering (Step 3)" do
    test "push step runs the documented git command" do
      assert read_deploy_yml!() =~ "git push gigalixir HEAD:refs/heads/main"
    end

    test "migrate step runs Ideajar.Release.migrate via gigalixir run" do
      assert read_deploy_yml!() =~
               ~s(gigalixir run -- bin/ideajar eval "Ideajar.Release.migrate")
    end

    test "no step suppresses failure with continue-on-error: true" do
      refute read_deploy_yml!() =~ "continue-on-error: true",
             "fail-fast must remain the default — push, migrate, and smoke test must each block the next step on failure"
    end

    test "Push precedes Migrate in the file" do
      content = read_deploy_yml!()
      push_offset = step_offset!(content, "Push")
      migrate_offset = step_offset!(content, "Migrate")

      assert push_offset < migrate_offset,
             "Push must appear before Migrate so a push failure prevents the migrator from running"
    end
  end

  describe "smoke test (Step 4)" do
    test "curls /health on PHX_HOST" do
      assert read_deploy_yml!() =~ ~s(curl -fsS "https://$PHX_HOST/health")
    end

    test "retries 10 times at 15-second intervals" do
      content = read_deploy_yml!()
      assert content =~ "for i in $(seq 1 10)"
      assert content =~ "sleep 15"
    end

    test "asserts status ok in the response body" do
      assert read_deploy_yml!() =~ ~s("status":"ok")
    end

    test "exit 0 fires inside the conditional after grep -q, before the first sleep" do
      content = read_deploy_yml!()
      grep_offset = offset!(content, "grep -q")
      then_offset = offset!(content, "; then")
      exit_zero_offset = offset!(content, "exit 0")
      first_sleep_offset = offset!(content, "sleep 15")

      assert grep_offset < then_offset,
             "the `; then` opener must follow the grep test"

      assert then_offset < exit_zero_offset,
             "exit 0 must live inside the then-branch (after the `; then` opener), not before"

      assert exit_zero_offset < first_sleep_offset,
             "exit 0 must come before sleep 15 — inside the then branch, not after"
    end

    test "exit 1 fires only after the retry loop is exhausted" do
      content = read_deploy_yml!()
      last_sleep_offset = last_offset!(content, "sleep 15")
      exit_one_offset = offset!(content, "exit 1")

      assert last_sleep_offset < exit_one_offset,
             "exit 1 must come after the loop's last sleep — only when retries are exhausted"
    end

    test "failure prints recovery hints (previous release, gigalixir logs, releases:rollback)" do
      content = read_deploy_yml!()
      assert content =~ "previous release"
      assert content =~ "gigalixir logs"
      assert content =~ "gigalixir releases:rollback"
    end

    test "Migrate precedes Smoke test in the file" do
      content = read_deploy_yml!()

      assert step_offset!(content, "Migrate") < step_offset!(content, "Smoke test"),
             "Smoke test must run after Migrate so a migrate failure short-circuits the pipeline"
    end
  end

  describe "documentation (Step 6)" do
    test "D1 — Routine deploys opens with the no-manual-action framing" do
      section = md_section!("Routine deploys")
      assert section =~ "no manual action is needed"
      assert section =~ "previous release"
      assert section =~ "still serving"
    end

    test "D1 — preamble does not claim there is no CI auto-push" do
      refute read_deploy_md!() =~ "there is no CI auto-push",
             "the slice 11b preamble said this; slice 13 made it false — the line cannot drift back"
    end

    test "D1 — Routine deploys has both Automatic and Manual fallback sub-headings" do
      content = read_deploy_md!()
      assert content =~ ~r/^#+\s+Automatic/m
      assert content =~ ~r/^#+\s+Manual fallback/m
    end

    test "D1 — manual fallback parity preserved (`git push gigalixir main`)" do
      assert read_deploy_md!() =~ "git push gigalixir main",
             "the manual fallback path must remain documented even after CD becomes the default"
    end

    test "D2 — Common failure modes carries a CD-specific caption" do
      assert read_deploy_md!() =~ "**CD-specific failures**"
    end

    test "D2 — CD-specific failure rows cover the four canonical symptoms" do
      content = read_deploy_md!()
      assert content =~ "workflow_run"
      assert content =~ "Authenticate"
      assert content =~ "smoke test"
      assert content =~ "lock"
    end

    test "D2 — smoke-test failure interpretation calls out the 150s budget" do
      section = md_section!("Common failure modes")
      assert section =~ "previous release"
      assert section =~ "still serving"
      assert section =~ "150"
    end

    test "D3 — GitHub Actions secrets section lists all four secrets and the UI path" do
      content = read_deploy_md!()
      assert content =~ "GIGALIXIR_EMAIL"
      assert content =~ "GIGALIXIR_API_KEY"
      assert content =~ "GIGALIXIR_APP_NAME"
      assert content =~ "PHX_HOST"
      assert content =~ "Settings → Secrets and variables → Actions"
    end

    test "D3 — secrets ordering constraint pins the before-first-deploy timing" do
      assert read_deploy_md!() =~ ~r/before (merging|the first deploy)/i,
             "the secrets section must spell out the timing constraint without tying it to a one-off slice event"
    end

    test "D4 — First-time activation section explains the workflow_dispatch bootstrap" do
      content = read_deploy_md!()
      assert content =~ ~r/^#+\s+First-time activation/m
      assert content =~ "workflow_dispatch"
      assert content =~ ~r/(bootstrap|first deploy)/i
    end

    test "D5 — migration safety distinguishes additive from breaking schema changes" do
      content = read_deploy_md!()
      assert content =~ ~r/additive/i
      assert content =~ ~r/(breaking|drop colonna|rename)/i
    end
  end

  describe "out-of-scope guards (Step 5)" do
    test "OS1a — ci.yml does not push to gigalixir" do
      refute read_ci_yml!() =~ "gigalixir",
             "ci.yml must stay test-only; gigalixir touchpoints belong in deploy.yml"
    end

    test "OS1b — ci.yml does not reference GIGALIXIR_* secrets" do
      refute read_ci_yml!() =~ "GIGALIXIR_",
             "ci.yml must not need any deploy secret"
    end

    test "OS1c — ci.yml workflow name is exactly `CI`" do
      assert read_ci_yml!() =~ ~r/^name: CI$/m,
             "deploy.yml's workflow_run trigger keys on `workflows: [\"CI\"]` — renaming silently breaks CD"
    end

    test "OS2 — deploy.yml does not invoke `gigalixir releases:rollback` as a bare command" do
      refute read_deploy_yml!() =~ ~r/^\s*gigalixir releases:rollback\b/m,
             "the rollback string is allowed only inside echo (smoke-test recovery hint), not as a run-line command"
    end

    test "OS3a — deploy.yml does not contain webhook domain literals" do
      content = read_deploy_yml!()
      refute content =~ "hooks.slack.com"
      refute content =~ "discord.com/api/webhooks"
      refute content =~ "events.pagerduty.com"
    end

    test "OS3b — deploy.yml does not POST to outbound webhooks via curl" do
      content = read_deploy_yml!()
      refute content =~ "curl -X POST"
      refute content =~ "curl --data"
      refute content =~ ~r/curl[^|]*-d "/
    end

    test "OS3c — deploy.yml does not pull in third-party notification actions" do
      refute read_deploy_yml!() =~ ~r/uses: .*(notify|slack|discord|pagerduty)/i,
             "no third-party notification action — failure email is the GH default channel"
    end

    test "OS4 — deploy.yml does not use path filters in its triggers" do
      content = read_deploy_yml!()
      refute content =~ ~r/^\s*paths:/m
      refute content =~ ~r/^\s*paths-ignore:/m
    end
  end

  defp read_deploy_yml! do
    File.read!(@deploy_yml_path)
  end

  defp read_ci_yml! do
    File.read!(@ci_yml_path)
  end

  defp read_deploy_md! do
    File.read!(@deploy_md_path)
  end

  # Extract the body of a top-level section in docs/deploy.md, from `## <name>`
  # up to (but not including) the next `## ` heading. Lets section-scoped tests
  # assert against the right block instead of accidentally satisfying an
  # assertion via tokens that live in a different section.
  defp md_section!(heading) do
    content = read_deploy_md!()
    pattern = ~r/^## #{Regex.escape(heading)}\b.*?(?=^## |\z)/ms

    case Regex.run(pattern, content) do
      [section] -> section
      _ -> flunk("section `## #{heading}` not found in docs/deploy.md")
    end
  end

  defp step_offset!(content, step_name) do
    case :binary.match(content, "name: #{step_name}") do
      {offset, _} -> offset
      :nomatch -> flunk("step `name: #{step_name}` not found in deploy.yml")
    end
  end

  defp offset!(content, needle) do
    case :binary.match(content, needle) do
      {offset, _} -> offset
      :nomatch -> flunk("substring `#{needle}` not found in deploy.yml")
    end
  end

  defp last_offset!(content, needle) do
    case :binary.matches(content, needle) do
      [] -> flunk("substring `#{needle}` not found in deploy.yml")
      matches -> matches |> List.last() |> elem(0)
    end
  end
end
