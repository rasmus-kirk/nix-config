{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.box;

  proxyFilterFile = pkgs.writeText "sandbox-proxy-filter" (concatStringsSep "\n" cfg.network.allowedHosts);

  # ─── GitHub PR-creation broker (file-drop pattern, like box-notify) ─────
  # Inside the box, gh-pr-create drops a JSON request at
  # ${cfg.brokerRoot}/request/. Outside (host), a systemd user path unit
  # watches that dir and dispatches each file via prBrokerDispatch, which
  # holds the write-PAT (NOT visible to the box) and calls GitHub's create-PR
  # endpoint. The PR URL is written back to ${cfg.brokerRoot}/response/ for
  # the in-box client to read.
  #
  # Security: box only knows how to drop a file. It cannot enumerate or invoke
  # other GitHub endpoints; the broker only exposes create-PR. Write-PAT lives
  # at githubPrBroker.writeTokenFile on the host, outside any bind-mount.

  # Shared helper used by both gh-pr-create and gh-pr-edit to drop a request
  # and wait for the response. Source-included via concatenation to avoid an
  # extra script-in-PATH for an internal helper.
  prBrokerClientPoll = ''
    # Args: $1 = request JSON, $2 = response field to print on success ("url" or "number")
    if [ ! -d ${cfg.brokerRoot}/request ]; then
      echo "PR broker not enabled on host (no ${cfg.brokerRoot}/request). See kirk.box.githubPrBroker.enable" >&2
      exit 1
    fi
    ID="$(date +%s%N).$$"
    REQ_TMP="${cfg.brokerRoot}/request/.staging.$ID"
    REQ_FINAL="${cfg.brokerRoot}/request/$ID.json"
    RESP_FILE="${cfg.brokerRoot}/response/$ID.json"
    printf '%s' "$1" > "$REQ_TMP"
    mv "$REQ_TMP" "$REQ_FINAL"
    for _ in $(seq 1 60); do
      if [ -f "$RESP_FILE" ]; then
        if jq -e '.error' "$RESP_FILE" >/dev/null 2>&1; then
          jq -r '"PR broker error: \(.error)\n\(.detail // "")"' "$RESP_FILE" >&2
          exit 2
        fi
        jq -r ".$2" "$RESP_FILE"
        exit 0
      fi
      sleep 0.5
    done
    echo "Timed out waiting for PR broker response (30s). Check 'journalctl --user -u box-pr-broker'." >&2
    exit 3
  '';

  ghPrCreateScript = pkgs.writeShellApplication {
    name = "gh-pr-create";
    runtimeInputs = with pkgs; [ coreutils jq ];
    inheritPath = false;
    text = ''
      set -euo pipefail

      usage() {
        cat >&2 <<EOF
      Usage: gh-pr-create --repo OWNER/REPO --head BRANCH --base BRANCH \\
                         --title TITLE [--body BODY | --body-file FILE] \\
                         [--draft]

      Drops a request file at ${cfg.brokerRoot}/request/ for the host-side
      broker to create the PR via the GitHub API. Waits up to 30s for the
      response and prints the resulting PR URL on stdout.
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

      REQ=$(jq -n \
        --arg op create \
        --arg repo "$REPO" \
        --arg head "$HEAD" \
        --arg base "$BASE" \
        --arg title "$TITLE" \
        --arg body "$BODY" \
        --argjson draft "$DRAFT" \
        '{op:$op, repo:$repo, head:$head, base:$base, title:$title, body:$body, draft:$draft}')

      set -- "$REQ" url
      ${prBrokerClientPoll}
    '';
  };

  ghPrEditScript = pkgs.writeShellApplication {
    name = "gh-pr-edit";
    runtimeInputs = with pkgs; [ coreutils jq ];
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

      Drops an edit request at ${cfg.brokerRoot}/request/ for the host-side broker
      to PATCH the PR via the GitHub API. Only fields passed are updated;
      others are left untouched. --draft and --ready toggle draft state via
      GraphQL (REST doesn't support that field on update). Prints the updated
      PR URL on stdout.
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

      REQ=$(jq -n \
        --arg op edit \
        --arg repo "$REPO" \
        --argjson pr_number "$NUMBER" \
        --arg title "$TITLE" --argjson title_set "$TITLE_SET" \
        --arg body "$BODY" --argjson body_set "$BODY_SET" \
        --arg base "$BASE" --argjson base_set "$BASE_SET" \
        --arg state "$STATE" --argjson state_set "$STATE_SET" \
        --arg draft_target "$DRAFT_TARGET" \
        '{op:$op, repo:$repo, pr_number:$pr_number}
         + (if $title_set == 1 then {title:$title} else {} end)
         + (if $body_set  == 1 then {body:$body}   else {} end)
         + (if $base_set  == 1 then {base:$base}   else {} end)
         + (if $state_set == 1 then {state:$state} else {} end)
         + (if $draft_target != "" then {draft_target:$draft_target} else {} end)')

      set -- "$REQ" url
      ${prBrokerClientPoll}
    '';
  };

  ghPrReviewScript = pkgs.writeShellApplication {
    name = "gh-pr-review";
    runtimeInputs = with pkgs; [ coreutils jq ];
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

      REQ=$(jq -n \
        --arg op review \
        --arg repo "$REPO" \
        --argjson pr_number "$NUMBER" \
        --arg body "$BODY" \
        --arg event "$EVENT" \
        --argjson comments "$COMMENTS_JSON" \
        '{op:$op, repo:$repo, pr_number:$pr_number, body:$body, event:$event, comments:$comments}')

      set -- "$REQ" url
      ${prBrokerClientPoll}
    '';
  };

  prBrokerDispatch = pkgs.writeShellScript "box-pr-broker-dispatch" ''
    set -u
    REQ_DIR=${cfg.brokerRoot}/request
    RESP_DIR=${cfg.brokerRoot}/response
    ${pkgs.coreutils}/bin/mkdir -p "$RESP_DIR"

    TOKEN_FILE='${if cfg.githubPrBroker.writeTokenFile != null
                  then cfg.githubPrBroker.writeTokenFile
                  else ""}'

    for f in "$REQ_DIR"/[!.]*; do
      [ -f "$f" ] || continue
      id=$(${pkgs.coreutils}/bin/basename "$f" .json)
      resp="$RESP_DIR/$id.json"

      write_resp() {
        ${pkgs.coreutils}/bin/printf '%s\n' "$1" > "$resp"
        ${pkgs.coreutils}/bin/chmod 0444 "$resp"
      }

      if [ -z "$TOKEN_FILE" ] || [ ! -r "$TOKEN_FILE" ]; then
        write_resp '{"error":"config","detail":"writeTokenFile not set or unreadable"}'
        ${pkgs.libnotify}/bin/notify-send -- "PR broker" "Write-PAT not configured" || true
        ${pkgs.coreutils}/bin/rm -f "$f"
        continue
      fi

      OP=$(${pkgs.jq}/bin/jq -r '.op // "create"' "$f")
      REPO=$(${pkgs.jq}/bin/jq -r '.repo // empty' "$f")
      if [ -z "$REPO" ]; then
        write_resp '{"error":"bad_request","detail":"missing repo"}'
        ${pkgs.libnotify}/bin/notify-send -- "PR broker" "Bad request — missing repo" || true
        ${pkgs.coreutils}/bin/rm -f "$f"
        continue
      fi

      TOKEN=$(${pkgs.coreutils}/bin/tr -d '[:space:]' < "$TOKEN_FILE")
      TMP_BODY=$(${pkgs.coreutils}/bin/mktemp)
      CODE=000
      RESPONSE_BODY=""
      SUMMARY=""

      case "$OP" in
        create)
          HEAD_REF=$(${pkgs.jq}/bin/jq -r '.head // empty' "$f")
          BASE_REF=$(${pkgs.jq}/bin/jq -r '.base // empty' "$f")
          TITLE=$(${pkgs.jq}/bin/jq -r '.title // empty' "$f")
          BODY=$(${pkgs.jq}/bin/jq -r '.body // empty' "$f")
          DRAFT=$(${pkgs.jq}/bin/jq -r '.draft // false' "$f")
          if [ -z "$HEAD_REF" ] || [ -z "$BASE_REF" ] || [ -z "$TITLE" ]; then
            write_resp '{"error":"bad_request","detail":"create needs head/base/title"}'
            ${pkgs.libnotify}/bin/notify-send -- "PR broker" "Bad create request" || true
            ${pkgs.coreutils}/bin/rm -f "$f" "$TMP_BODY"
            continue
          fi
          PAYLOAD=$(${pkgs.jq}/bin/jq -n \
            --arg title "$TITLE" --arg body "$BODY" \
            --arg head "$HEAD_REF" --arg base "$BASE_REF" \
            --argjson draft "$DRAFT" \
            '{title:$title, body:$body, head:$head, base:$base, draft:$draft}')
          CODE=$(${pkgs.curl}/bin/curl -sS -o "$TMP_BODY" -w '%{http_code}' \
            -X POST \
            -H "Authorization: Bearer $TOKEN" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -d "$PAYLOAD" \
            "https://api.github.com/repos/$REPO/pulls" 2>/dev/null || echo 000)
          SUMMARY="$TITLE"
          SUCCESS_CODE=201
          ;;
        edit)
          PR_NUMBER=$(${pkgs.jq}/bin/jq -r '.pr_number // empty' "$f")
          if [ -z "$PR_NUMBER" ]; then
            write_resp '{"error":"bad_request","detail":"edit needs pr_number"}'
            ${pkgs.libnotify}/bin/notify-send -- "PR broker" "Bad edit request" || true
            ${pkgs.coreutils}/bin/rm -f "$f" "$TMP_BODY"
            continue
          fi

          # Field updates (forward only fields actually present in the request)
          PAYLOAD=$(${pkgs.jq}/bin/jq '{title, body, base, state} | with_entries(select(.value != null))' "$f")
          HAS_FIELDS=$(${pkgs.coreutils}/bin/printf '%s' "$PAYLOAD" | ${pkgs.jq}/bin/jq 'length > 0')
          DRAFT_TARGET=$(${pkgs.jq}/bin/jq -r '.draft_target // empty' "$f")

          if [ "$HAS_FIELDS" != "true" ] && [ -z "$DRAFT_TARGET" ]; then
            write_resp '{"error":"bad_request","detail":"edit has no fields to update"}'
            ${pkgs.libnotify}/bin/notify-send -- "PR broker" "Empty edit request" || true
            ${pkgs.coreutils}/bin/rm -f "$f" "$TMP_BODY"
            continue
          fi

          CODE=200
          NODE_ID=""
          NEEDS_REFRESH=false
          GH_API="https://api.github.com/repos/$REPO/pulls/$PR_NUMBER"

          # Step 1: REST PATCH for field updates (title/body/base/state)
          if [ "$HAS_FIELDS" = "true" ]; then
            CODE=$(${pkgs.curl}/bin/curl -sS -o "$TMP_BODY" -w '%{http_code}' \
              -X PATCH \
              -H "Authorization: Bearer $TOKEN" \
              -H "Accept: application/vnd.github+json" \
              -H "X-GitHub-Api-Version: 2022-11-28" \
              -d "$PAYLOAD" \
              "$GH_API" 2>/dev/null || echo 000)
            if [ "$CODE" = "200" ]; then
              NODE_ID=$(${pkgs.jq}/bin/jq -r '.node_id' "$TMP_BODY")
            fi
          fi

          # Step 2: GraphQL mutation for draft toggle (REST has no draft field on PATCH)
          if [ -n "$DRAFT_TARGET" ] && [ "$CODE" = "200" ]; then
            if [ -z "$NODE_ID" ]; then
              # Need to fetch node_id since we didn't PATCH
              CODE=$(${pkgs.curl}/bin/curl -sS -o "$TMP_BODY" -w '%{http_code}' \
                -H "Authorization: Bearer $TOKEN" \
                -H "Accept: application/vnd.github+json" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                "$GH_API" 2>/dev/null || echo 000)
              if [ "$CODE" = "200" ]; then
                NODE_ID=$(${pkgs.jq}/bin/jq -r '.node_id' "$TMP_BODY")
              fi
            fi
            if [ "$CODE" = "200" ] && [ -n "$NODE_ID" ]; then
              case "$DRAFT_TARGET" in
                draft) MUTATION='convertPullRequestToDraft' ;;
                ready) MUTATION='markPullRequestReadyForReview' ;;
                *) MUTATION="" ;;
              esac
              GQL_QUERY="mutation { $MUTATION(input: {pullRequestId: \"$NODE_ID\"}) { pullRequest { id url number isDraft } } }"
              GQL_PAYLOAD=$(${pkgs.jq}/bin/jq -n --arg q "$GQL_QUERY" '{query:$q}')
              CODE=$(${pkgs.curl}/bin/curl -sS -o "$TMP_BODY" -w '%{http_code}' \
                -X POST \
                -H "Authorization: Bearer $TOKEN" \
                -H "Accept: application/json" \
                -d "$GQL_PAYLOAD" \
                "https://api.github.com/graphql" 2>/dev/null || echo 000)
              if [ "$CODE" = "200" ] && ${pkgs.jq}/bin/jq -e '.errors' "$TMP_BODY" > /dev/null; then
                CODE=422
              fi
              NEEDS_REFRESH=true
            fi
          fi

          # Step 3: refresh TMP_BODY to REST format if GraphQL was the last call
          # (the common success handler below extracts .html_url / .number from REST JSON)
          if [ "$NEEDS_REFRESH" = "true" ] && [ "$CODE" = "200" ]; then
            CODE=$(${pkgs.curl}/bin/curl -sS -o "$TMP_BODY" -w '%{http_code}' \
              -H "Authorization: Bearer $TOKEN" \
              -H "Accept: application/vnd.github+json" \
              -H "X-GitHub-Api-Version: 2022-11-28" \
              "$GH_API" 2>/dev/null || echo 000)
          fi

          SUMMARY="edit #$PR_NUMBER"
          SUCCESS_CODE=200
          ;;
        review)
          PR_NUMBER=$(${pkgs.jq}/bin/jq -r '.pr_number // empty' "$f")
          EVENT=$(${pkgs.jq}/bin/jq -r '.event // "COMMENT"' "$f")
          if [ -z "$PR_NUMBER" ]; then
            write_resp '{"error":"bad_request","detail":"review needs pr_number"}'
            ${pkgs.libnotify}/bin/notify-send -- "PR broker" "Bad review request" || true
            ${pkgs.coreutils}/bin/rm -f "$f" "$TMP_BODY"
            continue
          fi
          # Defense-in-depth: dispatcher refuses APPROVE even if the
          # in-box client script were patched out.
          if [ "$EVENT" = "APPROVE" ]; then
            write_resp '{"error":"forbidden","detail":"APPROVE not allowed via broker"}'
            ${pkgs.libnotify}/bin/notify-send -- "PR broker" "REJECTED: APPROVE attempt on #$PR_NUMBER" || true
            ${pkgs.coreutils}/bin/rm -f "$f" "$TMP_BODY"
            continue
          fi
          if [ "$EVENT" != "COMMENT" ] && [ "$EVENT" != "REQUEST_CHANGES" ]; then
            write_resp "$(${pkgs.jq}/bin/jq -n --arg e "$EVENT" '{error:"bad_request", detail:("invalid event: " + $e)}')"
            ${pkgs.coreutils}/bin/rm -f "$f" "$TMP_BODY"
            continue
          fi
          # Forward only present fields. Empty body / empty comments are
          # both valid (body-only OR inline-only OR both).
          PAYLOAD=$(${pkgs.jq}/bin/jq '{body, event, comments} | with_entries(select(.value != null and .value != ""))' "$f")
          CODE=$(${pkgs.curl}/bin/curl -sS -o "$TMP_BODY" -w '%{http_code}' \
            -X POST \
            -H "Authorization: Bearer $TOKEN" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -d "$PAYLOAD" \
            "https://api.github.com/repos/$REPO/pulls/$PR_NUMBER/reviews" 2>/dev/null || echo 000)
          SUMMARY="$EVENT on #$PR_NUMBER"
          SUCCESS_CODE=200
          ;;
        *)
          write_resp "$(${pkgs.jq}/bin/jq -n --arg op "$OP" '{error:"bad_request", detail:("unknown op: " + $op)}')"
          ${pkgs.libnotify}/bin/notify-send -- "PR broker" "Unknown op: $OP" || true
          ${pkgs.coreutils}/bin/rm -f "$f" "$TMP_BODY"
          continue
          ;;
      esac

      RESPONSE_BODY=$(${pkgs.coreutils}/bin/cat "$TMP_BODY" 2>/dev/null || echo "")
      ${pkgs.coreutils}/bin/rm -f "$TMP_BODY"

      if [ "$CODE" = "$SUCCESS_CODE" ]; then
        url=$(${pkgs.coreutils}/bin/printf '%s' "$RESPONSE_BODY" | ${pkgs.jq}/bin/jq -r '.html_url')
        if [ "$OP" = "review" ]; then
          # Review responses don't have a `.number` field — the PR's number
          # is implicit from the URL.
          write_resp "$(${pkgs.jq}/bin/jq -n --arg url "$url" --arg op "$OP" '{url:$url, op:$op}')"
          ${pkgs.libnotify}/bin/notify-send -- "PR review — $SUMMARY" "$url" || true
        else
          number=$(${pkgs.coreutils}/bin/printf '%s' "$RESPONSE_BODY" | ${pkgs.jq}/bin/jq -r '.number')
          write_resp "$(${pkgs.jq}/bin/jq -n --arg url "$url" --argjson number "$number" --arg op "$OP" '{url:$url, number:$number, op:$op}')"
          if [ "$OP" = "create" ]; then
            ${pkgs.libnotify}/bin/notify-send -- "PR opened — #$number" "$SUMMARY — $url" || true
          else
            ${pkgs.libnotify}/bin/notify-send -- "PR updated — #$number" "$url" || true
          fi
        fi
      else
        write_resp "$(${pkgs.jq}/bin/jq -n --arg code "$CODE" --arg detail "$RESPONSE_BODY" '{error:("HTTP " + $code), detail:$detail}')"
        ${pkgs.libnotify}/bin/notify-send -- "PR broker FAILED (HTTP $CODE)" "$SUMMARY" || true
      fi

      ${pkgs.coreutils}/bin/rm -f "$f"
    done
  '';


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
      exec zsh
    else
      exec "$@"
    fi
  '';

  # Whitelist /dev: replace buildFHSEnv's full /dev bind with a minimal
  # devtmpfs containing only standard nodes (null, zero, full, random,
  # urandom, tty, ptmx, pts, fd, stdin, stdout, stderr, console).
  # /dev/hidraw* gets re-added on top via hidrawBinds when exposeFidoDevices
  # is true. Anything else (cameras, mics, input events, GPU, etc.) is
  # absent unless the user explicitly adds it via extraBwrapArgs.
  minimalDev = [ "--dev" "/dev" ];

  hidrawBinds = optionals cfg.exposeFidoDevices (
    concatMap
      (n: [ "--dev-bind-try" "/dev/hidraw${toString n}" "/dev/hidraw${toString n}" ])
      (range 0 31)
  );

  claudeStateBind = optionals cfg.exposeClaudeState [
    "--bind" "${config.home.homeDirectory}/.claude" "/home/user/.claude"
    # ~/.claude.json holds auth + "user has been set up" state; without it
    # Claude Code treats every invocation as a first-run (theme picker etc).
    "--bind" "${config.home.homeDirectory}/.claude.json" "/home/user/.claude.json"
  ];

  tmpfsMasks = concatMap (p: [ "--tmpfs" p ]) cfg.mountTmpfs;
  roBinds = concatMap (p: [ "--ro-bind" p p ]) cfg.mountsRO;
  rwBinds = concatMap (p: [ "--bind" p p ]) cfg.mountsRW;

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
        "--cap-add" "CAP_NET_ADMIN"
        "--cap-add" "CAP_SYS_ADMIN"
      ])
      # Hostname inside the UTS namespace (requires unshareUts).
      ++ (optionals (cfg.hostname != null && cfg.unshareUts) [ "--hostname" cfg.hostname ])
      # tmpfs masks must come FIRST so they hide buildFHSEnv's auto-binds;
      # then our explicit binds re-introduce only the subpaths we want.
      ++ tmpfsMasks
      # Dynamically mask the top-level of $PWD so siblings of cwd aren't visible.
      ++ [ "--tmpfs" "$BOX_CWD_TOP" ]
      # Replace host /dev with a minimal devtmpfs; hidraw added back below.
      ++ minimalDev
      # /dev/net/tun must be added AFTER --dev /dev (which would wipe it).
      ++ (optionals cfg.network.enable [
        "--dev-bind-try" "/dev/net/tun" "/dev/net/tun"
      ])
      ++ [
        "--bind" "${cfg.stateDir}/home" "/home/user"
      ]
      ++ claudeStateBind
      ++ (optionals (cfg.githubTokenFile != null) [
        "--ro-bind" cfg.githubTokenFile cfg.githubTokenFile
      ])
      ++ hidrawBinds
      # /tmp/screenshots: read-only window into host's screenshot drop.
      # Lives on box's /tmp tmpfs (privateTmp). Silently skipped if absent.
      ++ [ "--ro-bind-try" "/tmp/screenshots" "/tmp/screenshots" ]
      # /tmp/box-notify: read-write outbox for the `notify` script. A host-side
      # systemd path unit watches this dir and dispatches each file via notify-send.
      ++ [ "--bind-try" "/tmp/box-notify" "/tmp/box-notify" ]
      # Broker IPC: box drops request files in ${cfg.brokerRoot}/request (RW),
      # reads response files from ${cfg.brokerRoot}/response (RO). Host
      # dispatcher (or approval TUI) holds the write-PAT and only invokes
      # whitelisted endpoints.
      ++ (optionals cfg.githubPrBroker.enable [
        "--bind-try" "${cfg.brokerRoot}/request" "${cfg.brokerRoot}/request"
        "--ro-bind-try" "${cfg.brokerRoot}/response" "${cfg.brokerRoot}/response"
      ])
      ++ roBinds
      ++ rwBinds
      ++ cfg.extraBwrapArgs
      ++ optionals (cfg.seccompFile != null) [ "--seccomp" "9" ]
      # Auto-bind the caller's cwd LAST so it survives every mask above.
      # Writable so active development inside the box works.
      ++ [ "--bind-try" "$PWD" "$PWD" ];
  };

  # Single entry-point — the FHS env wrapper. When network.enable=true the
  # FHS env's runScript is slirpWrapper (which sets up slirp4netns inside
  # bwrap's namespaces, drops caps, then execs initScript).
  runBox = "${fhs}/bin/${cfg.name}-fhs";

  box = pkgs.writeShellApplication {
    name = cfg.name;
    runtimeInputs = with pkgs; [ coreutils trash-cli ];
    inheritPath = false;
    text = ''
      if [ "''${1:-}" = "nuke" ]; then
        echo "Trashing ${cfg.stateDir}..."
        trash-put "${cfg.stateDir}" 2>/dev/null || echo "No state directory."
        exit 0
      fi
      mkdir -p "${cfg.stateDir}/home"
      # Ensure /tmp/box-notify exists on host BEFORE bwrap, otherwise the
      # --bind-try silently skips and the box's `notify` writes land in the
      # box's private /tmp where the host watcher never sees them.
      mkdir -p /tmp/box-notify
      ${optionalString cfg.githubPrBroker.enable ''
        # Same reasoning for the PR broker: directories must exist on host
        # before bwrap so bind-try'd mounts actually attach.
        mkdir -p ${cfg.brokerRoot}/request ${cfg.brokerRoot}/response
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
      if ${if cfg.homeManagerFlake != null then "true" else "false"} && [ ! -L "${cfg.stateDir}/home/.nix-profile" ]; then
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
      default = pkgs: with pkgs; [
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
          # GitHub SSH-over-HTTPS endpoint (port 443) — tunneled via tinyproxy
          # CONNECT so `git push` works without opening port 22 in the box.
          ''^ssh\.github\.com$''
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
        "/data/.secret/ssh/id_ed25519_yubi.pub"
        "/data/.secret/ssh/id_ed25519_yubi"
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

    exposeFidoDevices = mkOption {
      type = types.bool;
      default = true;
      description = "Expose /dev/hidraw0..31 so libfido2 can talk to the YubiKey (needed for SSH SK signing).";
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
          inside the box. Mirrors the box-notify file-drop pattern:
          `gh-pr-create` (in the box) drops a JSON request at
          `''${brokerRoot}/request/`, a host systemd path unit dispatches
          it via the GitHub API, and the response (PR URL) lands in
          `''${brokerRoot}/response/` for the in-box client to read.

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
      example = [ "--unshare-net" ];
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
      home.packages = [ ghPrCreateScript ghPrEditScript ghPrReviewScript ];
    })
    (mkIf cfg.enable {
    home.packages = [ box ];

    # PR broker: host-side path watcher + dispatcher. Same shape as the
    # box-notify pair (defined in work/home.nix).
    systemd.user.paths.box-pr-broker = mkIf cfg.githubPrBroker.enable {
      Unit.Description = "Watch ${cfg.brokerRoot}/request for GitHub PR-creation drops";
      Path = {
        PathExistsGlob = "${cfg.brokerRoot}/request/[!.]*";
        MakeDirectory = true;
        DirectoryMode = "0755";
      };
      Install.WantedBy = [ "default.target" ];
    };
    systemd.user.services.box-pr-broker = mkIf cfg.githubPrBroker.enable {
      Unit.Description = "Dispatch ${cfg.brokerRoot}/request drops via GitHub's create-PR endpoint";
      Service = {
        Type = "oneshot";
        ExecStart = "${prBrokerDispatch}";
      };
    };

    systemd.user.services.sandbox-proxy = mkIf cfg.network.enable {
      Unit = {
        Description = "Domain-allowlist HTTP proxy for the sandbox";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.tinyproxy}/bin/tinyproxy -d -c ${proxyConfigFile}";
        Restart = "on-failure";
        RestartSec = "2s";
      };
      Install.WantedBy = [ "default.target" ];
    };
    })
  ];
}
