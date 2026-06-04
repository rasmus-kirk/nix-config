{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.box;

  proxyFilterFile = pkgs.writeText "sandbox-proxy-filter" (concatStringsSep "\n" cfg.network.allowedHosts);

  # ─── GitHub PR brokers (envelope-based, via request-approval) ──────────
  # Inside the box, gh-pr-{create,edit,review} build a JSON payload and
  # delegate to `request-approval`, which wraps it in an envelope at
  # ${cfg.brokerRoot}/request/ and waits for the host-side approval TUI
  # (running on the user's host home-manager profile) to gate + dispatch.
  #
  # Security: box only knows how to drop a file. The host TUI verifies
  # ssh-keygen -Y signature on each approval (binding the YubiKey touch
  # to the exact request bytes) and calls GitHub with the write-PAT,
  # which lives at githubPrBroker.writeTokenFile and is never visible
  # to the box.

  ghPrCreateScript = pkgs.writeShellApplication {
    name = "gh-pr-create";
    runtimeInputs = (with pkgs; [coreutils jq]) ++ [requestApprovalScript];
    inheritPath = false;
    text = ''
      set -euo pipefail

      usage() {
        cat >&2 <<EOF
      Usage: gh-pr-create --repo OWNER/REPO --head BRANCH --base BRANCH \\
                         --title TITLE [--body BODY | --body-file FILE] \\
                         [--draft]

      Builds the create-PR payload and submits it to the host approval TUI
      via request-approval (op gh.pr.create). On approval, prints the new
      PR URL on stdout.
      EOF
        exit 1
      }

      REPO="" HEAD="" BASE="" TITLE="" BODY="" DRAFT=false
      while [ $# -gt 0 ]; do
        case "$1" in
          --repo) REPO="$2"; shift 2 ;;
          --head) HEAD="$2"; shift 2 ;;
          --base) BASE="$2"; shift 2 ;;
          --title) TITLE="$2"; shift 2 ;;
          --body) BODY="$2"; shift 2 ;;
          --body-file) BODY=$(cat "$2"); shift 2 ;;
          --draft) DRAFT=true; shift ;;
          -h|--help) usage ;;
          *) echo "Unknown arg: $1" >&2; usage ;;
        esac
      done

      if [ -z "$REPO" ] || [ -z "$HEAD" ] || [ -z "$BASE" ] || [ -z "$TITLE" ]; then
        usage
      fi

      PAYLOAD_TMP=$(mktemp)
      trap 'rm -f "$PAYLOAD_TMP"' EXIT
      jq -n \
        --arg repo "$REPO" --arg head "$HEAD" --arg base "$BASE" \
        --arg title "$TITLE" --arg body "$BODY" \
        --argjson draft "$DRAFT" \
        '{repo:$repo, head:$head, base:$base, title:$title, body:$body, draft:$draft}' \
        > "$PAYLOAD_TMP"

      DRAFT_LABEL=""
      if [ "$DRAFT" = "true" ]; then DRAFT_LABEL=" [DRAFT]"; fi
      SUMMARY="Create PR in $REPO: $HEAD → $BASE$DRAFT_LABEL: $TITLE"

      RESULT=$(request-approval --op gh.pr.create \
        --payload-file "$PAYLOAD_TMP" --summary "$SUMMARY")
      printf '%s\n' "$RESULT" | jq -r '.url'
    '';
  };

  ghPrEditScript = pkgs.writeShellApplication {
    name = "gh-pr-edit";
    runtimeInputs = (with pkgs; [coreutils jq]) ++ [requestApprovalScript];
    inheritPath = false;
    text = ''
      set -euo pipefail

      usage() {
        cat >&2 <<EOF
      Usage: gh-pr-edit --repo OWNER/REPO --number N \\
                       [--title TITLE] \\
                       [--body BODY | --body-file FILE] \\
                       [--base BRANCH] \\
                       [--state open|closed] \\
                       [--draft | --ready]

      Builds the edit-PR payload and submits it to the host approval TUI
      via request-approval (op gh.pr.edit). Only fields passed are updated;
      others are left untouched. --draft and --ready toggle draft state via
      GraphQL. Prints the updated PR URL on stdout.
      EOF
        exit 1
      }

      REPO="" NUMBER="" TITLE="" BODY="" BASE="" STATE="" DRAFT_TARGET=""
      TITLE_SET=0 BODY_SET=0 BASE_SET=0 STATE_SET=0
      while [ $# -gt 0 ]; do
        case "$1" in
          --repo) REPO="$2"; shift 2 ;;
          --number) NUMBER="$2"; shift 2 ;;
          --title) TITLE="$2"; TITLE_SET=1; shift 2 ;;
          --body) BODY="$2"; BODY_SET=1; shift 2 ;;
          --body-file) BODY=$(cat "$2"); BODY_SET=1; shift 2 ;;
          --base) BASE="$2"; BASE_SET=1; shift 2 ;;
          --state) STATE="$2"; STATE_SET=1; shift 2 ;;
          --draft) DRAFT_TARGET="draft"; shift ;;
          --ready) DRAFT_TARGET="ready"; shift ;;
          -h|--help) usage ;;
          *) echo "Unknown arg: $1" >&2; usage ;;
        esac
      done

      if [ -z "$REPO" ] || [ -z "$NUMBER" ]; then
        usage
      fi
      if [ "$TITLE_SET" = 0 ] && [ "$BODY_SET" = 0 ] && [ "$BASE_SET" = 0 ] \
         && [ "$STATE_SET" = 0 ] && [ -z "$DRAFT_TARGET" ]; then
        echo "Nothing to update (pass at least one of --title/--body/--base/--state/--draft/--ready)" >&2
        exit 1
      fi
      if [ "$STATE_SET" = 1 ] && [ "$STATE" != "open" ] && [ "$STATE" != "closed" ]; then
        echo "--state must be 'open' or 'closed', got: $STATE" >&2
        exit 1
      fi

      PAYLOAD_TMP=$(mktemp)
      trap 'rm -f "$PAYLOAD_TMP"' EXIT
      jq -n \
        --arg repo "$REPO" \
        --argjson pr_number "$NUMBER" \
        --arg title "$TITLE" --argjson title_set "$TITLE_SET" \
        --arg body "$BODY" --argjson body_set "$BODY_SET" \
        --arg base "$BASE" --argjson base_set "$BASE_SET" \
        --arg state "$STATE" --argjson state_set "$STATE_SET" \
        --arg draft_target "$DRAFT_TARGET" \
        '{repo:$repo, pr_number:$pr_number,
          title:$title, title_set:$title_set,
          body:$body, body_set:$body_set,
          base:$base, base_set:$base_set,
          state:$state, state_set:$state_set,
          draft_target:$draft_target}' \
        > "$PAYLOAD_TMP"

      BITS=""
      [ "$TITLE_SET" = 1 ] && BITS="$BITS title"
      [ "$BODY_SET"  = 1 ] && BITS="$BITS body"
      [ "$BASE_SET"  = 1 ] && BITS="$BITS base"
      [ "$STATE_SET" = 1 ] && BITS="$BITS state→$STATE"
      [ -n "$DRAFT_TARGET" ] && BITS="$BITS draft→$DRAFT_TARGET"
      SUMMARY="Edit PR $REPO/#$NUMBER:''${BITS}"

      RESULT=$(request-approval --op gh.pr.edit \
        --payload-file "$PAYLOAD_TMP" --summary "$SUMMARY")
      printf '%s\n' "$RESULT" | jq -r '.url'
    '';
  };

  ghPrReviewScript = pkgs.writeShellApplication {
    name = "gh-pr-review";
    runtimeInputs = (with pkgs; [coreutils jq]) ++ [requestApprovalScript];
    inheritPath = false;
    text = ''
      set -euo pipefail
      usage() {
        cat >&2 <<EOF
      Usage: gh-pr-review --repo OWNER/REPO --number N \\
                         [--body BODY | --body-file FILE] \\
                         [--event COMMENT|REQUEST_CHANGES] \\
                         [--comments-file FILE]

      Submits a PR review via the host-side broker. Default event is COMMENT.
      APPROVE is intentionally not reachable from inside the box.

      --comments-file: JSON array of inline review comments, e.g.:
        [
          {"path": "src/foo.rs", "line": 42, "body": "issue"},
          {"path": "src/bar.rs", "start_line": 5, "line": 10, "body": "block"}
        ]
      Each entry needs path + line + body. Optional: side (LEFT|RIGHT,
      default RIGHT), start_side, start_line for multi-line.
      EOF
        exit 1
      }

      REPO="" NUMBER="" BODY="" EVENT="COMMENT" COMMENTS_JSON="[]"
      while [ $# -gt 0 ]; do
        case "$1" in
          --repo) REPO="$2"; shift 2 ;;
          --number) NUMBER="$2"; shift 2 ;;
          --body) BODY="$2"; shift 2 ;;
          --body-file) BODY=$(cat "$2"); shift 2 ;;
          --event) EVENT="$2"; shift 2 ;;
          --comments-file) COMMENTS_JSON=$(cat "$2"); shift 2 ;;
          -h|--help) usage ;;
          *) echo "Unknown arg: $1" >&2; usage ;;
        esac
      done

      if [ -z "$REPO" ] || [ -z "$NUMBER" ]; then
        usage
      fi
      case "$EVENT" in
        COMMENT|REQUEST_CHANGES) ;;
        APPROVE)
          echo "APPROVE is not allowed from inside the box (intentional)." >&2
          exit 1 ;;
        *)
          echo "--event must be COMMENT or REQUEST_CHANGES, got: $EVENT" >&2
          exit 1 ;;
      esac
      if ! printf '%s' "$COMMENTS_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
        echo "--comments-file must contain a JSON array" >&2
        exit 1
      fi

      PAYLOAD_TMP=$(mktemp)
      trap 'rm -f "$PAYLOAD_TMP"' EXIT
      jq -n \
        --arg repo "$REPO" \
        --argjson pr_number "$NUMBER" \
        --arg body "$BODY" \
        --arg event "$EVENT" \
        --argjson comments "$COMMENTS_JSON" \
        '{repo:$repo, pr_number:$pr_number, body:$body, event:$event, comments:$comments}' \
        > "$PAYLOAD_TMP"

      COMMENT_COUNT=$(printf '%s' "$COMMENTS_JSON" | jq 'length')
      SUMMARY="Review $REPO/#$NUMBER: event=$EVENT, $COMMENT_COUNT inline comment(s)"

      RESULT=$(request-approval --op gh.pr.review \
        --payload-file "$PAYLOAD_TMP" --summary "$SUMMARY")
      printf '%s\n' "$RESULT" | jq -r '.url'
    '';
  };

  ghPrReviewAppendScript = pkgs.writeShellApplication {
    name = "gh-pr-review-append";
    runtimeInputs = (with pkgs; [coreutils jq]) ++ [requestApprovalScript];
    inheritPath = false;
    text = ''
      set -euo pipefail
      usage() {
        cat >&2 <<EOF
      Usage: gh-pr-review-append --repo OWNER/REPO --number N --comments-file FILE

      Appends inline comments to the caller's pending review on a PR.
      Use this for multi-step review work: leave a few comments, do more
      reading, leave more — all into the same pending draft. Submitting
      the review (event=COMMENT or REQUEST_CHANGES) is gh-pr-review's job.

      If no pending review exists for this PR, the first comment creates
      one as a side-effect and subsequent comments attach to that draft.

      --comments-file: JSON array of inline review comments, e.g.:
        [
          {"path": "src/foo.rs", "line": 42, "body": "issue"},
          {"path": "src/bar.rs", "start_line": 5, "line": 10, "body": "block"}
        ]
      Each entry needs path + line + body. Optional: side (LEFT|RIGHT,
      default RIGHT), start_line + start_side (multi-line), in_reply_to
      (thread under an existing comment).

      Posts each comment via a separate API call (GitHub has no batch
      endpoint). On any individual failure, stops and reports how many
      succeeded plus the index of the failed one.
      EOF
        exit 1
      }

      REPO="" NUMBER="" COMMENTS_JSON=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --repo) REPO="$2"; shift 2 ;;
          --number) NUMBER="$2"; shift 2 ;;
          --comments-file) COMMENTS_JSON=$(cat "$2"); shift 2 ;;
          -h|--help) usage ;;
          *) echo "Unknown arg: $1" >&2; usage ;;
        esac
      done

      if [ -z "$REPO" ] || [ -z "$NUMBER" ] || [ -z "$COMMENTS_JSON" ]; then
        usage
      fi
      if ! printf '%s' "$COMMENTS_JSON" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
        echo "--comments-file must contain a non-empty JSON array" >&2
        exit 1
      fi
      if ! printf '%s' "$COMMENTS_JSON" | jq -e 'all(.[]; (.path | type == "string") and (.line | type == "number") and (.body | type == "string"))' >/dev/null 2>&1; then
        echo "every comment entry needs path (string), line (number), and body (string)" >&2
        exit 1
      fi

      PAYLOAD_TMP=$(mktemp)
      trap 'rm -f "$PAYLOAD_TMP"' EXIT
      jq -n \
        --arg repo "$REPO" \
        --argjson pr_number "$NUMBER" \
        --argjson comments "$COMMENTS_JSON" \
        '{repo:$repo, pr_number:$pr_number, comments:$comments}' \
        > "$PAYLOAD_TMP"

      COMMENT_COUNT=$(printf '%s' "$COMMENTS_JSON" | jq 'length')
      SUMMARY="Append $COMMENT_COUNT inline comment(s) to PR $REPO/#$NUMBER"

      RESULT=$(request-approval --op gh.pr.review-append \
        --payload-file "$PAYLOAD_TMP" --summary "$SUMMARY")
      printf '%s\n' "$RESULT" | jq -r '.url'
    '';
  };

  # Generic in-box client for the approval TUI. Wraps a payload in the
  # request-envelope shape, drops it at ${cfg.brokerRoot}/request/, waits for
  # the TUI to ack (5s), then polls for the final response. Exit codes:
  #   0  ok     — stdout is the broker's JSON result
  #  10  user rejected via TUI
  #  11  sign_failed or dispatch_failed (stderr has detail)
  #  12  TUI not running (no ack within 5s)
  #  13  abandoned (TUI restarted mid-request)
  #  14  timeout (no decision within --timeout)
  requestApprovalScript = pkgs.writeShellApplication {
    name = "request-approval";
    runtimeInputs = with pkgs; [coreutils jq];
    inheritPath = false;
    text = ''
      set -euo pipefail
      usage() {
        cat >&2 <<EOF
      Usage: request-approval --op <dotted.id> --payload-file <path>
                              [--summary <one-liner>] [--timeout <secs>]

      Examples of --op:  gh.pr.create, gh.pr.edit, gh.pr.review,
                         git.push, git.pull, git.fetch, git.sign-range.

      On status=ok, the broker's JSON result is printed to stdout.
      Exit codes: 0 ok / 10 rejected / 11 sign|dispatch failed /
                  12 TUI not running / 13 abandoned / 14 timeout.
      EOF
        exit 1
      }

      OP="" PAYLOAD_FILE="" SUMMARY="" TIMEOUT=1800
      while [ $# -gt 0 ]; do
        case "$1" in
          --op) OP="$2"; shift 2 ;;
          --payload-file) PAYLOAD_FILE="$2"; shift 2 ;;
          --summary) SUMMARY="$2"; shift 2 ;;
          --timeout) TIMEOUT="$2"; shift 2 ;;
          -h|--help) usage ;;
          *) echo "Unknown arg: $1" >&2; usage ;;
        esac
      done
      if [ -z "$OP" ] || [ -z "$PAYLOAD_FILE" ]; then usage; fi
      if [ ! -r "$PAYLOAD_FILE" ]; then
        echo "request-approval: payload file not readable: $PAYLOAD_FILE" >&2
        exit 1
      fi
      if [ ! -d ${cfg.brokerRoot}/request ]; then
        echo "request-approval: broker dir not mounted (${cfg.brokerRoot}/request)." >&2
        echo "Box may not have been launched with the broker bind-mounts." >&2
        exit 12
      fi

      ID="$(date +%s%N).$$"
      NOW="$(date -Iseconds)"
      SESSION_ID="''${BOX_SESSION_ID:-unknown}"
      ENVELOPE=$(jq -n \
        --arg id "$ID" --arg requested_at "$NOW" \
        --arg op "$OP" --arg summary "$SUMMARY" \
        --arg cwd "$PWD" --arg started_at "$NOW" \
        --arg session_id "$SESSION_ID" \
        --argjson agent_pid "$$" \
        --slurpfile payload "$PAYLOAD_FILE" \
        '{v:1, request_id:$id, requested_at:$requested_at, op:$op,
          payload:$payload[0], summary:$summary,
          client_context:{cwd:$cwd, agent_pid:$agent_pid,
                          session_id:$session_id, started_at:$started_at}}')

      REQ_TMP="${cfg.brokerRoot}/request/.staging.$ID"
      REQ_FINAL="${cfg.brokerRoot}/request/$ID.json"
      ACK_FILE="${cfg.brokerRoot}/response/$ID.ack"
      RESP_FILE="${cfg.brokerRoot}/response/$ID.json"

      printf '%s' "$ENVELOPE" > "$REQ_TMP"
      mv "$REQ_TMP" "$REQ_FINAL"

      # Wait up to ~5s for TUI to ack the request. No ack → TUI not running.
      for _ in $(seq 1 10); do
        [ -f "$ACK_FILE" ] && break
        sleep 0.5
      done
      if [ ! -f "$ACK_FILE" ]; then
        echo "request-approval: TUI not running on host (no ack within 5s)." >&2
        echo "Start 'approval-tui' on the host and retry." >&2
        exit 12
      fi

      # Poll for final response until --timeout. Sleep 0.5s between checks.
      DEADLINE=$(( $(date +%s) + TIMEOUT ))
      while [ "$(date +%s)" -lt "$DEADLINE" ]; do
        if [ -f "$RESP_FILE" ]; then
          STATUS=$(jq -r '.status' "$RESP_FILE")
          case "$STATUS" in
            ok)
              jq -c '.result' "$RESP_FILE"
              exit 0
              ;;
            rejected)
              jq -r '.detail // "rejected"' "$RESP_FILE" >&2
              exit 10
              ;;
            sign_failed|dispatch_failed)
              jq -r '.detail // "broker failure"' "$RESP_FILE" >&2
              exit 11
              ;;
            abandoned)
              jq -r '.detail // "abandoned"' "$RESP_FILE" >&2
              exit 13
              ;;
            *)
              echo "request-approval: unknown status: $STATUS" >&2
              exit 11
              ;;
          esac
        fi
        sleep 0.5
      done
      echo "request-approval: timed out after ''${TIMEOUT}s waiting for decision." >&2
      exit 14
    '';
  };

  # Fire-and-forget signal to the host approval TUI's agent registry.
  # Invoked from Claude Code's UserPromptSubmit (working) and Stop
  # (ready) hooks via ~/.claude/settings.json. Drops a small JSON file
  # at ${cfg.brokerRoot}/agent-events/<nanos>.json that the TUI reads
  # to update the bottom pane.
  agentEventScript = pkgs.writeShellApplication {
    name = "agent-event";
    runtimeInputs = with pkgs; [coreutils jq];
    inheritPath = false;
    text = ''
      set -euo pipefail
      EVENT="''${1:-}"
      case "$EVENT" in
        working|ready|terminated) ;;
        *) echo "agent-event: usage: agent-event {working|ready|terminated} [--claude-session UUID]" >&2; exit 1 ;;
      esac
      shift
      CLAUDE_SESSION=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --claude-session) CLAUDE_SESSION="$2"; shift 2 ;;
          *) echo "agent-event: unknown arg: $1" >&2; exit 1 ;;
        esac
      done
      DIR=${cfg.brokerRoot}/agent-events
      [ -d "$DIR" ] || exit 0  # broker not mounted — silent no-op
      ID="$(date +%s%N).$$"
      SESSION_ID="''${BOX_SESSION_ID:-unknown}"
      NOW="$(date -Iseconds)"
      STAGE="$DIR/.staging.$ID"
      FINAL="$DIR/$ID.json"
      jq -n \
        --arg event "$EVENT" --arg session_id "$SESSION_ID" \
        --arg claude_session_id "$CLAUDE_SESSION" \
        --arg cwd "$PWD" --arg ts "$NOW" \
        '{event:$event, session_id:$session_id,
          claude_session_id:$claude_session_id, cwd:$cwd, ts:$ts}' \
        > "$STAGE"
      mv "$STAGE" "$FINAL"
    '';
  };

  # Wrapper invoked by Claude Code's UserPromptSubmit / Stop hooks.
  # Reads the hook context JSON from stdin to extract Claude's
  # session UUID (different from BOX_SESSION_ID) and forwards the
  # event type + UUID to agent-event. The TUI uses the UUID to
  # cross-reference transcript files in ~/.claude/projects/ and
  # picks up agent-name updates directly from there (so /rename
  # reflects immediately, not just on the next hook).
  agentHookScript = pkgs.writeShellApplication {
    name = "agent-hook";
    runtimeInputs = with pkgs; [coreutils jq agentEventScript];
    inheritPath = false;
    text = ''
      set -euo pipefail
      EVENT="''${1:-}"
      case "$EVENT" in
        working|ready) ;;
        *) echo "agent-hook: usage: agent-hook {working|ready}" >&2; exit 1 ;;
      esac
      CONTEXT=""
      if [ ! -t 0 ]; then
        CONTEXT=$(cat || true)
      fi
      CLAUDE_SESSION=""
      if [ -n "$CONTEXT" ]; then
        CLAUDE_SESSION=$(printf '%s' "$CONTEXT" | jq -r '.session_id // empty')
      fi
      if [ -n "$CLAUDE_SESSION" ]; then
        agent-event "$EVENT" --claude-session "$CLAUDE_SESSION"
      else
        agent-event "$EVENT"
      fi
    '';
  };

  # In-box git wrapper. Intercepts push / pull / fetch and routes them
  # through the approval TUI on the host (which runs the actual git op
  # with the host's YubiKey-bound SSH key). Other subcommands — including
  # `commit` (intentionally unsigned in the box for fast checkpointing)
  # — pass through to the real git binary.
  gitWrapperScript = pkgs.writeShellApplication {
    name = "git";
    runtimeInputs = (with pkgs; [coreutils jq]) ++ [requestApprovalScript];
    inheritPath = false;
    text = ''
      set -euo pipefail
      REAL_GIT=${pkgs.git}/bin/git

      if [ $# -lt 1 ]; then
        exec "$REAL_GIT"
      fi
      SUB="$1"
      case "$SUB" in
        push|pull|fetch) ;;
        *) exec "$REAL_GIT" "$@" ;;
      esac

      # Capture context for the TUI summary. All best-effort — the actual
      # git invocation happens on the host, against the same working tree.
      shift  # drop the subcommand from the array we forward as argv
      ARGS=("$@")
      BRANCH=$("$REAL_GIT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
      HEAD_SHA=$("$REAL_GIT" rev-parse --short HEAD 2>/dev/null || true)
      UPSTREAM_STATE=""
      SIGNING_STATUS=""
      if [ "$SUB" = "push" ]; then
        UPSTREAM_STATE=$("$REAL_GIT" log --oneline '@{u}..HEAD' 2>/dev/null || true)
        SIGNING_STATUS=$("$REAL_GIT" log '@{u}..HEAD' --format='%h %G?' 2>/dev/null || true)
      fi

      PAYLOAD_TMP=$(mktemp)
      trap 'rm -f "$PAYLOAD_TMP"' EXIT
      # Filter program MUST precede --args (otherwise jq treats the
      # filter as a positional and uses ARGS[0] as the filter, e.g.
      # "origin/0 is not defined").
      jq -n \
        --arg cwd "$PWD" \
        --arg branch "$BRANCH" \
        --arg head_sha "$HEAD_SHA" \
        --arg upstream_state "$UPSTREAM_STATE" \
        --arg signing_status "$SIGNING_STATUS" \
        --arg sub "$SUB" \
        '
        # The wrapper drops the subcommand; the broker dispatcher runs
        # `git <sub> <args>` on host, so we put $sub first in argv.
        {cwd:$cwd, argv:([$sub] + $ARGS.positional),
         current_branch:$branch, head_sha:$head_sha,
         upstream_state:$upstream_state, signing_status:$signing_status}' \
        --args -- "''${ARGS[@]}" \
        > "$PAYLOAD_TMP"

      ARGS_JOINED=$(printf '%s ' "''${ARGS[@]}")
      SUMMARY="git $SUB ''${ARGS_JOINED}(in $PWD, branch ''${BRANCH:-?})"

      RESULT=$(request-approval --op "git.$SUB" \
        --payload-file "$PAYLOAD_TMP" --summary "$SUMMARY")
      # On success, surface the broker's stdout/stderr to the caller so the
      # agent sees what git printed on the host.
      printf '%s' "$RESULT" | jq -r '.stdout // ""'
      printf '%s' "$RESULT" | jq -r '.stderr // ""' >&2
    '';
  };

  # git-batch-sign: amend-sign every unsigned commit between <base> and
  # HEAD via the existing git-sign-range on the host. Single approval
  # request gates the whole batch; the rebase loop still touches the
  # YubiKey once per commit.
  gitBatchSignScript = pkgs.writeShellApplication {
    name = "git-batch-sign";
    runtimeInputs = (with pkgs; [coreutils jq git]) ++ [requestApprovalScript];
    inheritPath = false;
    text = ''
      set -euo pipefail
      BASE="''${1:-}"

      if [ -z "$BASE" ]; then
        if git rev-parse --verify --quiet '@{u}' >/dev/null; then
          BASE='@{u}'
        elif git rev-parse --verify --quiet main >/dev/null; then
          BASE='main'
        else
          echo "git-batch-sign: no upstream and no 'main' — pass a base ref" >&2
          exit 1
        fi
      fi

      COUNT=$(git rev-list --count "$BASE..HEAD")
      if [ "$COUNT" -eq 0 ]; then
        echo "git-batch-sign: nothing to sign ($BASE..HEAD is empty)."
        exit 0
      fi

      HEAD_SHA=$(git rev-parse --short HEAD)
      COMMIT_LIST=$(git log "$BASE..HEAD" --format='%h %G? %s' --no-color)

      PAYLOAD_TMP=$(mktemp)
      trap 'rm -f "$PAYLOAD_TMP"' EXIT
      jq -n \
        --arg cwd "$PWD" --arg base "$BASE" \
        --arg head_sha "$HEAD_SHA" --arg commit_list "$COMMIT_LIST" \
        '{cwd:$cwd, base:$base, head_sha:$head_sha, commit_list:$commit_list}' \
        > "$PAYLOAD_TMP"

      SUMMARY="Sign $COUNT commit(s) in $PWD from $BASE to HEAD"

      RESULT=$(request-approval --op git.sign-range \
        --payload-file "$PAYLOAD_TMP" --summary "$SUMMARY" --timeout 3600)
      printf '%s' "$RESULT" | jq -r '.stdout // ""'
      printf '%s' "$RESULT" | jq -r '.stderr // ""' >&2
    '';
  };

  proxyConfigFile = pkgs.writeText "sandbox-proxy.conf" ''
    Port ${toString cfg.network.proxyPort}
    Listen 127.0.0.1
    Timeout 600
    DefaultErrorFile "${pkgs.tinyproxy}/share/tinyproxy/default.html"
    StatFile "${pkgs.tinyproxy}/share/tinyproxy/stats.html"
    LogLevel Warning
    MaxClients 100
    Allow 127.0.0.1
    Filter "${proxyFilterFile}"
    FilterDefaultDeny Yes
    FilterType ere
    FilterURLs Off
    ConnectPort 443
    ConnectPort 563
  '';

  # The box runs inside an unshared net ns; slirp4netns NATs out via tap0.
  # Host's 127.0.0.1 is reachable as 10.0.2.2 (slirp4netns default gateway).
  proxyEnv = optionalString cfg.network.enable ''
    export HTTP_PROXY=http://10.0.2.2:${toString cfg.network.proxyPort}
    export HTTPS_PROXY=http://10.0.2.2:${toString cfg.network.proxyPort}
    export http_proxy=http://10.0.2.2:${toString cfg.network.proxyPort}
    export https_proxy=http://10.0.2.2:${toString cfg.network.proxyPort}
    export NO_PROXY=127.0.0.1,localhost,::1
    export no_proxy=127.0.0.1,localhost,::1
  '';

  # When network.enable=true, bwrap's runScript points HERE instead of
  # directly to initScript. We're running inside bwrap's user+net namespaces
  # with CAP_NET_ADMIN/CAP_SYS_ADMIN (via --cap-add). Spawn slirp4netns to
  # set up the tap device, then drop caps and exec the real init.
  # nftables ruleset applied inside the box's netns. Drops all outbound
  # except to the proxy address; drops all inbound except related/established
  # (so proxy responses return). Effectively forces ALL outbound traffic —
  # including raw sockets — through tinyproxy's domain allowlist.
  nftRuleset = pkgs.writeText "box-nftables.rules" ''
    table inet filter {
      chain output {
        type filter hook output priority 0; policy drop;
        ct state established,related accept
        oifname "lo" accept
        # The ONLY permitted destination is tinyproxy on host loopback. Every
        # outbound flow — HTTPS, SSH tunneled through CONNECT, DNS done on the
        # host side — must go through here, where the domain allowlist applies.
        ip daddr 10.0.2.2 tcp dport ${toString cfg.network.proxyPort} accept
      }
      chain input {
        type filter hook input priority 0; policy drop;
        ct state established,related accept
        iifname "lo" accept
      }
    }
  '';

  # Runs INSIDE the new netns (via nsenter). Applies nftables filter, drops
  # caps, then execs init. No marker waiting — slirp4netns is already up.
  innerChild = pkgs.writeShellScript "box-net-inner" ''
    ${pkgs.nftables}/bin/nft -f ${nftRuleset} || {
      echo "WARNING: nftables filter failed; raw-socket bypass not blocked." >&2
    }
    exec ${pkgs.util-linux}/bin/setpriv --inh-caps=-all --ambient-caps=-all -- ${initScript} "$@"
  '';

  # 1. Spawn a backgrounded `sleep` in a new netns to act as a netns holder
  #    (gives us a stable /proc/PID/ns/net for slirp4netns to attach to).
  # 2. Start slirp4netns in OUR (parent's) netns, attached to the holder's netns.
  # 3. exec into nsenter foreground — the user command (zsh) keeps the
  #    terminal because we're not in a backgrounded process group.
  slirpWrapper = pkgs.writeShellScript "box-slirp-wrapper" ''
    ${pkgs.util-linux}/bin/unshare --net ${pkgs.coreutils}/bin/sleep infinity &
    HOLDER_PID=$!

    for _ in $(seq 1 20); do
      [ -e "/proc/$HOLDER_PID/ns/net" ] && break
      sleep 0.05
    done

    ${pkgs.slirp4netns}/bin/slirp4netns --configure --mtu=65520 "$HOLDER_PID" tap0 2>/dev/null &
    SLIRP_PID=$!
    sleep 0.3

    # die-with-parent on bwrap reaps the holder + slirp4netns when zsh exits.
    exec ${pkgs.util-linux}/bin/nsenter --net=/proc/$HOLDER_PID/ns/net -- ${innerChild} "$@"
  '';

  initScript = pkgs.writeShellScript "sandbox-init" ''
    # Box uses its own home-manager profile, not the host's /etc/profiles
    # (which would leak host-installed tools — most notably `box` itself).
    export PATH="/home/user/.nix-profile/bin:$PATH"
    export NIX_REMOTE=daemon
    export NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
    export SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
    # Stable identifier for this box session. Propagated into every
    # request-approval envelope so the approval TUI can group requests
    # by agent and render an "active agents" pane.
    export BOX_SESSION_ID="$(date +%s%N).$$"
    # Fire a `terminated` agent-event when this init script exits so the
    # TUI removes the agent row from the bottom pane. The trap fires on
    # normal exit, EOF on the controlling tty, SIGHUP from a closing
    # terminal — anything that lets the shell unwind cleanly. SIGKILL
    # is uncatchable; in that rare case the agent row will linger.
    trap 'agent-event terminated || true' EXIT
    ${proxyEnv}
    ${optionalString (cfg.githubTokenFile != null) ''
      if [ -r ${cfg.githubTokenFile} ]; then
        GITHUB_PERSONAL_ACCESS_TOKEN=$(${pkgs.coreutils}/bin/tr -d '[:space:]' < ${cfg.githubTokenFile})
        export GITHUB_PERSONAL_ACCESS_TOKEN
      fi
    ''}
    # Stay at caller's cwd (auto-bound). Fall back to /home/user if it's gone.
    [ -d "$PWD" ] || cd /home/user
    # Apply direnv for the cwd before exec'ing the user command, so non-shell
    # invocations like `box claude --resume` still inherit the project's
    # .envrc / flake devshell env vars. zsh users get this automatically via
    # the direnv hook; this branch covers the direct-exec case.
    if [ -x /home/user/.nix-profile/bin/direnv ]; then
      eval "$(/home/user/.nix-profile/bin/direnv export bash 2>/dev/null)" || true
    fi
    if [ $# -eq 0 ]; then
      zsh
    else
      "$@"
    fi
    exit $?
  '';

  # Whitelist /dev: replace buildFHSEnv's full /dev bind with a minimal
  # devtmpfs containing only standard nodes (null, zero, full, random,
  # urandom, tty, ptmx, pts, fd, stdin, stdout, stderr, console).
  # Anything else (cameras, mics, input events, GPU, hidraw etc.) is
  # absent unless the user explicitly adds it via extraBwrapArgs.
  minimalDev = ["--dev" "/dev"];

  claudeStateBind = optionals cfg.exposeClaudeState [
    "--bind"
    "${config.home.homeDirectory}/.claude"
    "/home/user/.claude"
    # ~/.claude.json holds auth + "user has been set up" state; without it
    # Claude Code treats every invocation as a first-run (theme picker etc).
    "--bind"
    "${config.home.homeDirectory}/.claude.json"
    "/home/user/.claude.json"
  ];

  tmpfsMasks = concatMap (p: ["--tmpfs" p]) cfg.mountTmpfs;
  roBinds = concatMap (p: ["--ro-bind" p p]) cfg.mountsRO;
  rwBinds = concatMap (p: ["--bind" p p]) cfg.mountsRW;

  fhs = pkgs.buildFHSEnv {
    name = "${cfg.name}-fhs";
    targetPkgs = cfg.targetPkgs;
    multiPkgs = pkgs: cfg.multiPkgs pkgs;
    # When network filtering is on, runScript points at the slirpWrapper.
    runScript =
      if cfg.network.enable
      then "${slirpWrapper}"
      else "${initScript}";
    # Namespace unshares passed straight to bwrap flags.
    # network.enable: we let bwrap unshare USER (so --cap-add can grant caps),
    # but we unshare NET ourselves inside the wrapper so the new netns is
    # cleanly owned by our user-ns (avoiding the nested-userns issue that
    # caused setns EPERM when bwrap did it).
    inherit (cfg) unshareIpc unsharePid unshareUts unshareCgroup privateTmp dieWithParent;
    unshareNet = cfg.unshareNet && !cfg.network.enable;
    unshareUser = cfg.network.enable;
    # Compute the caller's cwd top-level dir so we can mask it (hiding cwd's
    # siblings) before re-binding just $PWD itself. Runs in the same shell
    # as extraBwrapArgs, which can reference these variables.
    extraPreBwrapCmds = ''
      if [ -n "''${PWD-}" ] && [ "$PWD" != "/" ]; then
        _stripped="''${PWD#/}"
        BOX_CWD_TOP="/''${_stripped%%/*}"
      else
        BOX_CWD_TOP="/tmp"
      fi
      ${optionalString (cfg.seccompFile != null) ''
        # Open the seccomp BPF program on FD 9; bwrap reads it via --seccomp 9.
        exec 9< ${cfg.seccompFile}
      ''}
    '';
    extraBwrapArgs =
      # When network filtering is on, grant slirp4netns the caps it needs.
      # setpriv drops these before running user code.
      (optionals cfg.network.enable [
        "--cap-add"
        "CAP_NET_ADMIN"
        "--cap-add"
        "CAP_SYS_ADMIN"
      ])
      # Hostname inside the UTS namespace (requires unshareUts).
      ++ (optionals (cfg.hostname != null && cfg.unshareUts) ["--hostname" cfg.hostname])
      # tmpfs masks must come FIRST so they hide buildFHSEnv's auto-binds;
      # then our explicit binds re-introduce only the subpaths we want.
      ++ tmpfsMasks
      # Dynamically mask the top-level of $PWD so siblings of cwd aren't visible.
      ++ ["--tmpfs" "$BOX_CWD_TOP"]
      # Replace host /dev with a minimal devtmpfs. No hidraw — YubiKey
      # operations (git push/pull/fetch, commit signing) all flow through
      # the host approval TUI, which owns the YubiKey itself.
      ++ minimalDev
      # /dev/net/tun must be added AFTER --dev /dev (which would wipe it).
      ++ (optionals cfg.network.enable [
        "--dev-bind-try"
        "/dev/net/tun"
        "/dev/net/tun"
      ])
      ++ [
        "--bind"
        "${cfg.stateDir}/home"
        "/home/user"
      ]
      ++ claudeStateBind
      ++ (optionals (cfg.githubTokenFile != null) [
        "--ro-bind"
        cfg.githubTokenFile
        cfg.githubTokenFile
      ])
      # /tmp/screenshots: read-only window into host's screenshot drop.
      # Lives on box's /tmp tmpfs (privateTmp). Silently skipped if absent.
      ++ ["--ro-bind-try" "/tmp/screenshots" "/tmp/screenshots"]
      # Broker IPC: box drops request files in ${cfg.brokerRoot}/request (RW),
      # reads response files from ${cfg.brokerRoot}/response (RO). Host
      # dispatcher (or approval TUI) holds the write-PAT and only invokes
      # whitelisted endpoints. agent-events/ is a separate stream of
      # fire-and-forget state notifications (working/ready), consumed by
      # the TUI's bottom pane + ready-notification.
      ++ (optionals cfg.githubPrBroker.enable [
        "--bind-try"
        "${cfg.brokerRoot}/request"
        "${cfg.brokerRoot}/request"
        "--ro-bind-try"
        "${cfg.brokerRoot}/response"
        "${cfg.brokerRoot}/response"
        "--bind-try"
        "${cfg.brokerRoot}/agent-events"
        "${cfg.brokerRoot}/agent-events"
      ])
      ++ roBinds
      ++ rwBinds
      ++ cfg.extraBwrapArgs
      ++ optionals (cfg.seccompFile != null) ["--seccomp" "9"]
      # Auto-bind the caller's cwd LAST so it survives every mask above.
      # Writable so active development inside the box works.
      ++ ["--bind-try" "$PWD" "$PWD"];
  };

  # Single entry-point — the FHS env wrapper. When network.enable=true the
  # FHS env's runScript is slirpWrapper (which sets up slirp4netns inside
  # bwrap's namespaces, drops caps, then execs initScript).
  runBox = "${fhs}/bin/${cfg.name}-fhs";

  box = pkgs.writeShellApplication {
    name = cfg.name;
    runtimeInputs = with pkgs; [coreutils trash-cli];
    inheritPath = false;
    text = ''
      if [ "''${1:-}" = "nuke" ]; then
        echo "Trashing ${cfg.stateDir}..."
        trash-put "${cfg.stateDir}" 2>/dev/null || echo "No state directory."
        exit 0
      fi
      mkdir -p "${cfg.stateDir}/home"
      ${optionalString cfg.githubPrBroker.enable ''
        # PR broker dirs: must exist on host before bwrap so bind-try'd
        # mounts actually attach.
        mkdir -p ${cfg.brokerRoot}/request ${cfg.brokerRoot}/response \
                 ${cfg.brokerRoot}/agent-events
      ''}

      # Auto-allow any .envrc in the launching cwd so direnv loads the
      # project devshell inside the box (initScript runs `direnv export
      # bash`, which only emits env when .envrc is trusted). Safe in this
      # context because the box itself is the sandbox — if someone cd's
      # into a malicious repo and runs `box`, the .envrc's code runs inside
      # the bwrap+nft jail, not on the host.
      if [ -f "$PWD/.envrc" ]; then
        ${pkgs.direnv}/bin/direnv allow "$PWD" 2>/dev/null || true
      fi

      # Auto-bootstrap on first run.
      if ${
        if cfg.homeManagerFlake != null
        then "true"
        else "false"
      } && [ ! -L "${cfg.stateDir}/home/.nix-profile" ]; then
        echo "First run — bootstrapping box home-manager (${cfg.homeManagerFlake})..."
        ${runBox} bash -lc 'home-manager switch --flake ${cfg.homeManagerFlake} -b backup --impure' || {
          echo "Bootstrap failed. Run '${cfg.name} hm-switch' manually."
          exit 1
        }
      fi

      exec ${runBox} "$@"
    '';
  };
in {
  options.kirk.box = {
    enable = mkEnableOption "bubblewrap + FHS sandbox (replaces ubuntuContainer)";

    name = mkOption {
      type = types.str;
      default = "box";
      description = "Command name for the sandbox launcher.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/data/.state/sandbox";
      description = "Writable state directory (the sandbox's home lives at <stateDir>/home).";
    };

    brokerRoot = mkOption {
      type = types.str;
      default = "/tmp/box-broker";
      description = ''
        Root directory for the host↔box broker IPC. Contains `request/`
        (box→host, RW in box) and `response/` (host→box, RO in box)
        subdirectories. The host-side approval TUI (or dispatcher,
        depending on broker) watches `request/` and writes back to
        `response/`. Must be the SAME path inside and outside the
        sandbox — the directories are bind-mounted.
      '';
    };

    targetPkgs = mkOption {
      type = types.functionTo (types.listOf types.package);
      default = pkgs:
        with pkgs; [
          glibc
          coreutils
          bashInteractive
          zsh
          git
          openssh
          curl
          wget
          cacert
          gnumake
          gcc
          python3
          nodejs
          sudo
          less
          vim
          util-linux
          file
          which
          gnused
          gnugrep
          gawk
          findutils
          nix
          home-manager
          claude-code
          socat
        ];
      description = "Function returning the packages exposed inside the FHS (available in /usr/bin etc.).";
    };

    multiPkgs = mkOption {
      type = types.functionTo (types.listOf types.package);
      default = _: [];
      description = "Function returning packages provided for both x86_64 and i686 inside the FHS.";
    };

    mountTmpfs = mkOption {
      type = with types; listOf str;
      default = [
        "/data"
        "/home"
        "/var"
        "/opt"
        "/root"
        "/srv"
        "/mnt"
        "/media"
        "/boot"
        # Hide host's dbus/pulseaudio/ssh-agent/etc. user sockets.
        "/run/user"
      ];
      description = ''
        Host top-level directories to mask with a tmpfs inside the sandbox.
        buildFHSEnv auto-mounts every directory under / from the host;
        masking forces the sandbox to see only what is explicitly bound via
        mountsRO/mountsRW/extraBwrapArgs.
      '';
    };

    unshareIpc = mkOption {
      type = types.bool;
      default = true;
      description = "Unshare SysV IPC and POSIX message queues from the host.";
    };

    unsharePid = mkOption {
      type = types.bool;
      default = true;
      description = "Give the box its own PID namespace — host PIDs are invisible, and box processes can't signal host processes.";
    };

    unshareUts = mkOption {
      type = types.bool;
      default = true;
      description = "Unshare UTS (hostname/domainname) namespace.";
    };

    unshareCgroup = mkOption {
      type = types.bool;
      default = true;
      description = "Unshare cgroup namespace.";
    };

    unshareNet = mkOption {
      type = types.bool;
      default = false;
      description = "Unshare the network namespace — fully blocks network from the box. Off by default since most workflows need network.";
    };

    privateTmp = mkOption {
      type = types.bool;
      default = true;
      description = "Use a private tmpfs at /tmp instead of sharing host /tmp.";
    };

    dieWithParent = mkOption {
      type = types.bool;
      default = true;
      description = "Kill all box processes when the launcher exits (clean lifecycle).";
    };

    network = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Route the box's HTTP/HTTPS traffic through a local domain-allowlist proxy
          (tinyproxy). Loopback (127.0.0.1, localhost) bypasses the proxy via NO_PROXY.
          Disabling this gives the box full host network access — convenient but
          undoes a primary security goal.
        '';
      };

      proxyPort = mkOption {
        type = types.port;
        default = 8888;
        description = "TCP port the proxy listens on (loopback only).";
      };

      allowedHosts = mkOption {
        type = with types; listOf str;
        default = [
          # Anthropic / Claude
          ''^api\.anthropic\.com$''
          ''^platform\.claude\.com$''
          # GitHub
          ''^github\.com$''
          ''^api\.github\.com$''
          ''^codeload\.github\.com$''
          ''^.*\.githubusercontent\.com$''
          # GitHub MCP server (hosted on GitHub Copilot infra by Microsoft)
          ''^api\.githubcopilot\.com$''
          # Azure storage / Microsoft cloud: GitHub Actions log/artifact
          # downloads redirect here (productionresultssa5.blob.core.windows.net
          # and similar). Broad on purpose so future Azure-hosted GitHub
          # endpoints don't need allowlist updates.
          ''^.*\.windows\.net$''
          # Nix
          ''^cache\.nixos\.org$''
          ''^channels\.nixos\.org$''
          ''^.*\.cachix\.org$''
          # npm
          ''^registry\.npmjs\.org$''
          # cargo
          ''^crates\.io$''
          ''^index\.crates\.io$''
          ''^static\.crates\.io$''
          # Linear (MCP server + OAuth)
          ''^linear\.app$''
          ''^.*\.linear\.app$''
        ];
        description = ''
          Regex patterns (extended POSIX) matching allowed destination hostnames.
          tinyproxy applies these as a Filter with FilterDefaultDeny=Yes, so anything
          not matching is blocked. Loopback bypasses this list entirely via NO_PROXY.
        '';
      };
    };

    mountsRO = mkOption {
      type = with types; listOf str;
      default = [
        "/data/.system-configuration"
        # YubiKey PUBLIC key only — the box uses this to verify commit
        # signatures in the shared working tree (kirk.git builds
        # allowed_signers from it). The matching SK private blob lives
        # only on host; signing happens via the approval TUI.
        "/data/.secret/ssh/id_ed25519_yubi.pub"
      ];
      description = "Host paths bind-mounted read-only inside the sandbox (same path inside and out).";
    };

    mountsRW = mkOption {
      type = with types; listOf str;
      default = [];
      description = "Host paths bind-mounted read-write inside the sandbox (same path inside and out).";
    };

    homeManagerFlake = mkOption {
      type = with types; nullOr str;
      default = "/data/.system-configuration#sandbox";
      example = "/data/.system-configuration#sandbox";
      description = ''
        Flake reference for the box's home-manager config. When non-null,
        running `box` for the first time will auto-bootstrap home-manager.
        Use `box hm-switch` to re-apply after changes.
      '';
    };

    exposeClaudeState = mkOption {
      type = types.bool;
      default = true;
      description = "Bind-mount host ~/.claude into the sandbox so Claude Code's state persists.";
    };

    githubTokenFile = mkOption {
      type = with types; nullOr str;
      default = null;
      example = "/data/.secret/github/pat";
      description = ''
        Host path to a file containing a GitHub PAT. When set, the file is
        bind-mounted read-only into the box and its contents (with surrounding
        whitespace stripped) are exported as GITHUB_PERSONAL_ACCESS_TOKEN.
        The official github MCP plugin reads this env var for its Bearer header.
      '';
    };

    brokerClient = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Install the in-box client scripts (`gh-pr-create`, `gh-pr-edit`)
          into this profile's `home.packages` so they end up in
          `~/.nix-profile/bin/` — which is reliably on PATH including
          through direnv/devenv shells. Enable this in the BOX's
          home-manager config (not the host's); the host doesn't need them.
        '';
      };
    };

    githubPrBroker = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Host-side capability broker for opening GitHub pull requests from
          inside the box. File-drop pattern: `gh-pr-create` (in the box)
          drops a JSON request at `''${brokerRoot}/request/`, the host
          approval TUI dispatches it via the GitHub API, and the response
          (PR URL) lands in `''${brokerRoot}/response/` for the in-box
          client to read.

          The write-scoped PAT lives at `writeTokenFile` on the host and is
          never bind-mounted into the box. The broker only ever invokes
          GitHub's create-PR endpoint — approve/close/comment/merge are not
          reachable from inside the box.
        '';
      };

      writeTokenFile = mkOption {
        type = with types; nullOr str;
        default = null;
        example = "/data/.secret/github/pat-write";
        description = ''
          Host path to a file containing a GitHub PAT with
          `Pull requests: Read and Write` permission. Read by the dispatcher
          at request time. MUST NOT be inside any path that's bind-mounted
          into the box (don't put it under `mountsRO`/`mountsRW`).
        '';
      };
    };

    hostname = mkOption {
      type = with types; nullOr str;
      default = "box";
      example = "box";
      description = ''
        Hostname the box reports inside its UTS namespace. Visible in shell
        prompts (`%m` in zsh, `\h` in bash) and via `hostname`/`uname -n`.
        Requires `unshareUts = true` (default). Set to `null` to inherit
        the host's hostname.
      '';
    };

    extraBwrapArgs = mkOption {
      type = with types; listOf str;
      default = [];
      example = ["--unshare-net"];
      description = "Additional raw bwrap arguments appended to the invocation.";
    };

    seccompFile = mkOption {
      type = with types; nullOr path;
      default = null;
      example = literalExpression "./box-seccomp.bpf";
      description = ''
        Path to a compiled seccomp BPF program. When set, the box uses
        `--seccomp` to apply syscall filtering. Generating the BPF requires
        a separate libseccomp-based tool; this option is intentionally manual
        for now. If null, no seccomp filter is applied (bwrap's defaults still
        drop most capabilities via the user namespace).
      '';
    };
  };

  config = mkMerge [
    # Box's in-box client scripts. Independent of cfg.enable so the BOX's
    # home-manager (which never sets box.enable) can still install them.
    (mkIf cfg.brokerClient.enable {
      home.packages = [
        requestApprovalScript
        agentEventScript
        agentHookScript
        ghPrCreateScript
        ghPrEditScript
        ghPrReviewScript
        ghPrReviewAppendScript
        # Git wrapper shadows pkgs.git's bin/git for push/pull/fetch only;
        # other subcommands fall through to the real git binary. hiPrio
        # resolves the bin/git symlink collision in favour of the wrapper.
        (lib.hiPrio gitWrapperScript)
        gitBatchSignScript
      ];
    })
    (mkIf cfg.enable {
      home.packages = [box];

      # The PR broker dispatcher (bash + systemd path-unit) is retired: all
      # broker requests now go through the host-side approval-tui binary,
      # which watches ${cfg.brokerRoot}/request directly. The user launches
      # approval-tui in a terminal of their choice; bind-mounts + brokerRoot
      # remain available for it.

      systemd.user.services.sandbox-proxy = mkIf cfg.network.enable {
        Unit = {
          Description = "Domain-allowlist HTTP proxy for the sandbox";
          After = ["network-online.target"];
          Wants = ["network-online.target"];
        };
        Service = {
          Type = "simple";
          ExecStart = "${pkgs.tinyproxy}/bin/tinyproxy -d -c ${proxyConfigFile}";
          Restart = "on-failure";
          RestartSec = "2s";
        };
        Install.WantedBy = ["default.target"];
      };
    })
  ];
}
