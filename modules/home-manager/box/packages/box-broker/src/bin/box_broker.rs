//! Unified in-box CLI for everything that goes through the host
//! approval-tui (box-approver). Subcommands are nested to mirror the
//! dotted op-id naming:
//!
//!   box-broker gh pr create  …   →  op gh.pr.create
//!   box-broker gh pr edit    …   →  op gh.pr.edit
//!   box-broker linear issue create … → op linear.issue.create
//!   box-broker git push      …   →  op git.push
//!   box-broker git batch-sign    →  op git.sign-range
//!   box-broker agent event   …   →  fire-and-forget bottom-pane event
//!   box-broker agent hook    …   →  Claude Code hook entry point
//!   box-broker request-approval … → low-level escape hatch
//!
//! `box-broker --help` and each level's `--help` enumerate everything.

use anyhow::{anyhow, bail, Context, Result};
use box_broker::broker_client::{
    broker_root_from_env, drop_agent_event, submit_and_wait, Outcome, DEFAULT_TIMEOUT,
};
use clap::{ArgAction, Args, Parser, Subcommand};
use serde_json::{json, Value};
use std::io::Read;
use std::path::PathBuf;
use std::time::Duration;
use tokio::process::Command;

#[derive(Parser)]
#[command(
    name = "box-broker",
    about = "Approval-gated host-side operations brokered by box-approver.",
    subcommand_required = true,
    arg_required_else_help = true
)]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// GitHub PR operations.
    Gh(GhCmd),
    /// Linear ticket operations.
    Linear(LinearCmd),
    /// Git operations (network ops via the broker; batch-sign).
    Git(GitCmd),
    /// Agent lifecycle (used by sandbox-init + Claude Code hooks).
    Agent(AgentCmd),
    /// Low-level: drop a generic envelope into the broker queue.
    RequestApproval(RequestApprovalArgs),
}

// ─── gh ────────────────────────────────────────────────────────────────

#[derive(Args)]
struct GhCmd {
    #[command(subcommand)]
    sub: GhSub,
}

#[derive(Subcommand)]
enum GhSub {
    /// Pull request operations.
    Pr(GhPrCmd),
}

#[derive(Args)]
struct GhPrCmd {
    #[command(subcommand)]
    sub: GhPrSub,
}

#[derive(Subcommand)]
enum GhPrSub {
    /// Open a new PR.
    Create(GhPrCreateArgs),
    /// Edit title/body/base/state/draft on an existing PR.
    Edit(GhPrEditArgs),
    /// Submit a PR review (event = COMMENT or REQUEST_CHANGES; APPROVE blocked).
    Review(GhPrReviewArgs),
    /// Add inline comments to the caller's pending review draft.
    ReviewAppend(GhPrReviewAppendArgs),
}

#[derive(Args)]
struct GhPrCreateArgs {
    #[arg(long)] repo: String,
    #[arg(long)] head: String,
    #[arg(long)] base: String,
    #[arg(long)] title: String,
    #[arg(long)] body: Option<String>,
    /// Read body from a file (mutually exclusive with --body).
    #[arg(long = "body-file", value_name = "FILE")] body_file: Option<PathBuf>,
    #[arg(long, action = ArgAction::SetTrue)] draft: bool,
}

#[derive(Args)]
struct GhPrEditArgs {
    #[arg(long)] repo: String,
    #[arg(long)] number: u64,
    #[arg(long)] title: Option<String>,
    #[arg(long)] body: Option<String>,
    #[arg(long = "body-file", value_name = "FILE")] body_file: Option<PathBuf>,
    #[arg(long)] base: Option<String>,
    #[arg(long, value_parser = ["open", "closed"])] state: Option<String>,
    #[arg(long, action = ArgAction::SetTrue, conflicts_with = "ready")] draft: bool,
    #[arg(long, action = ArgAction::SetTrue, conflicts_with = "draft")] ready: bool,
}

#[derive(Args)]
struct GhPrReviewArgs {
    #[arg(long)] repo: String,
    #[arg(long)] number: u64,
    #[arg(long)] body: Option<String>,
    #[arg(long = "body-file", value_name = "FILE")] body_file: Option<PathBuf>,
    #[arg(long, default_value = "COMMENT", value_parser = ["COMMENT", "REQUEST_CHANGES"])]
    event: String,
    #[arg(long = "comments-file", value_name = "FILE")] comments_file: Option<PathBuf>,
}

#[derive(Args)]
struct GhPrReviewAppendArgs {
    #[arg(long)] repo: String,
    #[arg(long)] number: u64,
    #[arg(long = "comments-file", value_name = "FILE")] comments_file: PathBuf,
}

// ─── linear ────────────────────────────────────────────────────────────

#[derive(Args)]
struct LinearCmd {
    #[command(subcommand)]
    sub: LinearSub,
}

#[derive(Subcommand)]
enum LinearSub {
    /// Issue (ticket) operations.
    Issue(LinearIssueCmd),
}

#[derive(Args)]
struct LinearIssueCmd {
    #[command(subcommand)]
    sub: LinearIssueSub,
}

#[derive(Subcommand)]
enum LinearIssueSub {
    /// Create a new Linear issue.
    Create(LinearIssueCreateArgs),
}

#[derive(Args)]
struct LinearIssueCreateArgs {
    /// Team key, e.g. "QMS" (not the UUID — host resolves it).
    #[arg(long)] team: String,
    #[arg(long)] title: String,
    #[arg(long)] description: Option<String>,
    #[arg(long = "description-file", value_name = "FILE")] description_file: Option<PathBuf>,
    /// Linear priority 0–4 (0 = no priority, 1 = urgent, 4 = low).
    #[arg(long)] priority: Option<u8>,
}

// ─── git ───────────────────────────────────────────────────────────────

#[derive(Args)]
struct GitCmd {
    #[command(subcommand)]
    sub: GitSub,
}

#[derive(Subcommand)]
enum GitSub {
    /// Run `git push ARGS` on the host (broker-gated). Refuses
    /// unsigned commits in @{u}..HEAD.
    Push(GitNetArgs),
    /// Run `git pull ARGS` on the host (broker-gated).
    Pull(GitNetArgs),
    /// Run `git fetch ARGS` on the host (broker-gated).
    Fetch(GitNetArgs),
    /// Amend-sign every unsigned commit in BASE..HEAD via the host's
    /// `git-sign-range` script. One TUI approval gates the batch.
    BatchSign(GitBatchSignArgs),
}

#[derive(Args)]
struct GitNetArgs {
    /// Arguments to forward to git (everything after `--`, e.g. `origin main`).
    #[arg(trailing_var_arg = true)]
    args: Vec<String>,
}

#[derive(Args)]
struct GitBatchSignArgs {
    /// Base ref. Defaults to @{u}, falls back to `main` if no upstream.
    base: Option<String>,
}

// ─── agent ─────────────────────────────────────────────────────────────

#[derive(Args)]
struct AgentCmd {
    #[command(subcommand)]
    sub: AgentSub,
}

#[derive(Subcommand)]
enum AgentSub {
    /// Drop a working / ready / terminated event for the agents pane.
    Event(AgentEventArgs),
    /// Wrapper for Claude Code UserPromptSubmit/Stop hooks. Reads stdin JSON.
    Hook(AgentHookArgs),
}

#[derive(Args)]
struct AgentEventArgs {
    #[arg(value_parser = ["working", "ready", "terminated"])]
    event: String,
    #[arg(long = "claude-session", value_name = "UUID")] claude_session: Option<String>,
}

#[derive(Args)]
struct AgentHookArgs {
    #[arg(value_parser = ["working", "ready"])]
    event: String,
}

// ─── request-approval ──────────────────────────────────────────────────

#[derive(Args)]
struct RequestApprovalArgs {
    /// Dotted op-id, e.g. gh.pr.create, git.push, linear.issue.create.
    #[arg(long)] op: String,
    #[arg(long = "payload-file", value_name = "FILE")] payload_file: PathBuf,
    #[arg(long)] summary: Option<String>,
    #[arg(long, default_value_t = 1800)] timeout: u64,
}

// ───────────────────────────────────────────────────────────────────────

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let cli = Cli::parse();
    let outcome = match dispatch(cli.cmd).await {
        Ok(o) => o,
        Err(e) => {
            eprintln!("box-broker: {e:#}");
            std::process::exit(1);
        }
    };
    outcome.finish_and_exit();
}

async fn dispatch(cmd: Cmd) -> Result<Outcome> {
    match cmd {
        Cmd::Gh(c) => match c.sub {
            GhSub::Pr(p) => match p.sub {
                GhPrSub::Create(a) => cmd_gh_pr_create(a).await,
                GhPrSub::Edit(a) => cmd_gh_pr_edit(a).await,
                GhPrSub::Review(a) => cmd_gh_pr_review(a).await,
                GhPrSub::ReviewAppend(a) => cmd_gh_pr_review_append(a).await,
            },
        },
        Cmd::Linear(c) => match c.sub {
            LinearSub::Issue(i) => match i.sub {
                LinearIssueSub::Create(a) => cmd_linear_issue_create(a).await,
            },
        },
        Cmd::Git(c) => match c.sub {
            GitSub::Push(a) => cmd_git_net("push", a).await,
            GitSub::Pull(a) => cmd_git_net("pull", a).await,
            GitSub::Fetch(a) => cmd_git_net("fetch", a).await,
            GitSub::BatchSign(a) => cmd_git_batch_sign(a).await,
        },
        Cmd::Agent(c) => match c.sub {
            AgentSub::Event(a) => cmd_agent_event(a).await,
            AgentSub::Hook(a) => cmd_agent_hook(a).await,
        },
        Cmd::RequestApproval(a) => cmd_request_approval(a).await,
    }
}

// ─── gh pr create ──────────────────────────────────────────────────────

async fn cmd_gh_pr_create(args: GhPrCreateArgs) -> Result<Outcome> {
    let body = resolve_body(args.body, args.body_file).await?.unwrap_or_default();
    let summary = format!(
        "Create PR in {}: {} → {}{}: {}",
        args.repo, args.head, args.base,
        if args.draft { " [DRAFT]" } else { "" },
        args.title,
    );
    let payload = json!({
        "repo": args.repo, "head": args.head, "base": args.base,
        "title": args.title, "body": body, "draft": args.draft,
    });
    submit(payload, "gh.pr.create", summary, DEFAULT_TIMEOUT)
        .await
        .map(|o| project_field(o, "url"))
}

// ─── gh pr edit ────────────────────────────────────────────────────────

async fn cmd_gh_pr_edit(args: GhPrEditArgs) -> Result<Outcome> {
    let body = resolve_body(args.body, args.body_file).await?;
    let title_set = u8::from(args.title.is_some());
    let body_set = u8::from(body.is_some());
    let base_set = u8::from(args.base.is_some());
    let state_set = u8::from(args.state.is_some());
    if title_set + body_set + base_set + state_set == 0 && !args.draft && !args.ready {
        bail!(
            "edit needs at least one of --title / --body / --base / --state / --draft / --ready"
        );
    }
    let draft_target = if args.draft { "draft" } else if args.ready { "ready" } else { "" };
    let mut bits: Vec<String> = vec![];
    if title_set == 1 { bits.push("title".into()); }
    if body_set == 1 { bits.push("body".into()); }
    if base_set == 1 { bits.push("base".into()); }
    if state_set == 1 { bits.push(format!("state→{}", args.state.clone().unwrap_or_default())); }
    if !draft_target.is_empty() { bits.push(format!("draft→{draft_target}")); }
    let summary = format!("Edit PR {}/#{}: {}", args.repo, args.number, bits.join(", "));
    let payload = json!({
        "repo": args.repo, "pr_number": args.number,
        "title": args.title.unwrap_or_default(), "title_set": title_set,
        "body": body.unwrap_or_default(), "body_set": body_set,
        "base": args.base.unwrap_or_default(), "base_set": base_set,
        "state": args.state.unwrap_or_default(), "state_set": state_set,
        "draft_target": draft_target,
    });
    submit(payload, "gh.pr.edit", summary, DEFAULT_TIMEOUT)
        .await
        .map(|o| project_field(o, "url"))
}

// ─── gh pr review ──────────────────────────────────────────────────────

async fn cmd_gh_pr_review(args: GhPrReviewArgs) -> Result<Outcome> {
    if args.event == "APPROVE" {
        bail!("APPROVE not allowed via broker (intentional).");
    }
    let body = resolve_body(args.body, args.body_file).await?.unwrap_or_default();
    let comments = load_comments(args.comments_file.as_deref()).await?;
    if !comments.is_array() {
        bail!("--comments-file must contain a JSON array");
    }
    let n = comments.as_array().map(|a| a.len()).unwrap_or(0);
    let summary = format!("Review {}/#{}: event={}, {n} inline comment(s)", args.repo, args.number, args.event);
    let payload = json!({
        "repo": args.repo, "pr_number": args.number,
        "body": body, "event": args.event, "comments": comments,
    });
    submit(payload, "gh.pr.review", summary, DEFAULT_TIMEOUT)
        .await
        .map(|o| project_field(o, "url"))
}

// ─── gh pr review-append ───────────────────────────────────────────────

async fn cmd_gh_pr_review_append(args: GhPrReviewAppendArgs) -> Result<Outcome> {
    let comments = load_comments(Some(&args.comments_file)).await?;
    let Some(arr) = comments.as_array() else { bail!("--comments-file must contain a JSON array"); };
    if arr.is_empty() { bail!("--comments-file: empty array — nothing to append"); }
    for (i, c) in arr.iter().enumerate() {
        if c.get("path").and_then(Value::as_str).is_none()
            || c.get("line").and_then(Value::as_i64).is_none()
            || c.get("body").and_then(Value::as_str).is_none()
        {
            bail!("comment[{i}] is missing required path/line/body");
        }
    }
    let summary = format!("Append {} inline comment(s) to PR {}/#{}", arr.len(), args.repo, args.number);
    let payload = json!({ "repo": args.repo, "pr_number": args.number, "comments": comments });
    submit(payload, "gh.pr.review-append", summary, DEFAULT_TIMEOUT)
        .await
        .map(|o| project_field(o, "url"))
}

// ─── linear issue create ───────────────────────────────────────────────

async fn cmd_linear_issue_create(args: LinearIssueCreateArgs) -> Result<Outcome> {
    let description = resolve_body(args.description, args.description_file)
        .await?
        .unwrap_or_default();
    let preview = description.lines().next().unwrap_or("").chars().take(140).collect::<String>();
    let summary = format!(
        "Create Linear issue in team {}: {}{}\n{preview}",
        args.team, args.title,
        args.priority.map(|p| format!(", priority {p}")).unwrap_or_default(),
    );
    let mut payload = json!({
        "team_key": args.team, "title": args.title, "description": description,
    });
    if let Some(p) = args.priority { payload["priority"] = json!(p); }
    submit(payload, "linear.issue.create", summary, DEFAULT_TIMEOUT)
        .await
        .map(|o| project_field(o, "url"))
}

// ─── git push / pull / fetch ───────────────────────────────────────────

async fn cmd_git_net(sub: &str, args: GitNetArgs) -> Result<Outcome> {
    let cwd = std::env::current_dir().context("cwd")?;
    let argv_for_payload = std::iter::once(sub.to_string())
        .chain(args.args.iter().cloned())
        .collect::<Vec<_>>();
    let branch = run_git_capture(&["symbolic-ref", "--quiet", "--short", "HEAD"]).await;
    let head_sha = run_git_capture(&["rev-parse", "--short", "HEAD"]).await;
    let (upstream_state, signing_status) = if sub == "push" {
        (
            run_git_capture(&["log", "--oneline", "@{u}..HEAD"]).await,
            run_git_capture(&["log", "@{u}..HEAD", "--format=%h %G?"]).await,
        )
    } else {
        (String::new(), String::new())
    };
    let summary = format!(
        "git {} (in {}, branch {})",
        argv_for_payload.join(" "),
        cwd.display(),
        if branch.is_empty() { "?" } else { branch.as_str() },
    );
    let payload = json!({
        "cwd": cwd.to_string_lossy(),
        "argv": argv_for_payload,
        "current_branch": branch,
        "head_sha": head_sha,
        "upstream_state": upstream_state,
        "signing_status": signing_status,
    });
    let op = format!("git.{sub}");
    let result = submit(payload, &op, summary, DEFAULT_TIMEOUT).await?;
    // For network git ops the result is {stdout, stderr, argv}; surface
    // stdout and stderr through to the caller, drop the rest.
    if let Outcome::Ok(value) = &result {
        if let Some(s) = value.get("stdout").and_then(Value::as_str) {
            print!("{s}");
        }
        if let Some(s) = value.get("stderr").and_then(Value::as_str) {
            eprint!("{s}");
        }
        return Ok(Outcome::Ok(Value::Null));
    }
    Ok(result)
}

// ─── git batch-sign ────────────────────────────────────────────────────

async fn cmd_git_batch_sign(args: GitBatchSignArgs) -> Result<Outcome> {
    let base = match args.base {
        Some(b) => b,
        None => resolve_default_base().await?,
    };
    let count = git_rev_list_count(&base).await?;
    if count == 0 {
        return Ok(Outcome::Ok(json!({
            "appended": 0,
            "message": format!("No unsigned commits between {base} and HEAD"),
        })));
    }
    let head_sha = run_git_capture(&["rev-parse", "--short", "HEAD"]).await;
    let commit_list = git_log_format(&base, "%h %G? %s").await?;
    let cwd = std::env::current_dir().context("cwd")?;
    let summary = format!("Sign {count} commit(s) in {} from {base} to HEAD", cwd.display());
    let payload = json!({
        "cwd": cwd.to_string_lossy(),
        "base": base,
        "head_sha": head_sha,
        "commit_list": commit_list,
    });
    let result = submit(payload, "git.sign-range", summary, Duration::from_secs(3600)).await?;
    if let Outcome::Ok(value) = &result {
        if let Some(s) = value.get("stdout").and_then(Value::as_str) { print!("{s}"); }
        if let Some(s) = value.get("stderr").and_then(Value::as_str) { eprint!("{s}"); }
        return Ok(Outcome::Ok(Value::Null));
    }
    Ok(result)
}

// ─── agent event ───────────────────────────────────────────────────────

async fn cmd_agent_event(args: AgentEventArgs) -> Result<Outcome> {
    drop_agent_event(&broker_root_from_env(), &args.event, args.claude_session.as_deref())
        .await
        .context("dropping agent-event")?;
    Ok(Outcome::Ok(Value::Null))
}

// ─── agent hook ────────────────────────────────────────────────────────

async fn cmd_agent_hook(args: AgentHookArgs) -> Result<Outcome> {
    let mut buf = String::new();
    let _ = std::io::stdin().read_to_string(&mut buf);
    let claude_session = if buf.trim().is_empty() {
        None
    } else {
        serde_json::from_str::<Value>(&buf)
            .ok()
            .and_then(|v| v.get("session_id").and_then(Value::as_str).map(str::to_string))
    };
    drop_agent_event(&broker_root_from_env(), &args.event, claude_session.as_deref())
        .await
        .context("dropping agent-event from hook")?;
    Ok(Outcome::Ok(Value::Null))
}

// ─── request-approval (low-level) ──────────────────────────────────────

async fn cmd_request_approval(args: RequestApprovalArgs) -> Result<Outcome> {
    let bytes = tokio::fs::read(&args.payload_file)
        .await
        .with_context(|| format!("reading {}", args.payload_file.display()))?;
    let payload: Value = serde_json::from_slice(&bytes).context("payload-file isn't valid JSON")?;
    submit(payload, &args.op, args.summary.unwrap_or_default(), Duration::from_secs(args.timeout)).await
}

// ─── helpers ───────────────────────────────────────────────────────────

async fn submit(payload: Value, op: &str, summary: String, timeout: Duration) -> Result<Outcome> {
    let root = broker_root_from_env();
    let summary_opt = (!summary.is_empty()).then_some(summary);
    submit_and_wait(op, payload, summary_opt, timeout, &root).await
}

fn project_field(outcome: Outcome, field: &str) -> Outcome {
    if let Outcome::Ok(value) = &outcome {
        if let Some(s) = value.get(field).and_then(Value::as_str) {
            return Outcome::Ok(Value::String(s.to_string()));
        }
    }
    outcome
}

async fn resolve_body(body: Option<String>, file: Option<PathBuf>) -> Result<Option<String>> {
    match (body, file) {
        (Some(_), Some(_)) => Err(anyhow!("pass either --body or --body-file, not both")),
        (Some(b), None) => Ok(Some(b)),
        (None, Some(p)) => {
            let s = tokio::fs::read_to_string(&p)
                .await
                .with_context(|| format!("reading {}", p.display()))?;
            Ok(Some(s))
        }
        (None, None) => Ok(None),
    }
}

async fn load_comments(path: Option<&std::path::Path>) -> Result<Value> {
    match path {
        None => Ok(Value::Array(vec![])),
        Some(p) => {
            let bytes = tokio::fs::read(p)
                .await
                .with_context(|| format!("reading {}", p.display()))?;
            serde_json::from_slice(&bytes)
                .with_context(|| format!("parsing {} as JSON", p.display()))
        }
    }
}

async fn resolve_default_base() -> Result<String> {
    if git_has_ref("@{u}").await {
        Ok("@{u}".into())
    } else if git_has_ref("main").await {
        Ok("main".into())
    } else {
        Err(anyhow!("no upstream and no 'main' branch; pass a base ref explicitly"))
    }
}

async fn git_has_ref(r: &str) -> bool {
    Command::new("git")
        .args(["rev-parse", "--verify", "--quiet", r])
        .output().await.map(|o| o.status.success()).unwrap_or(false)
}

async fn run_git_capture(args: &[&str]) -> String {
    let Ok(out) = Command::new("git").args(args).output().await else { return String::new() };
    if !out.status.success() { return String::new() }
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

async fn git_rev_list_count(base: &str) -> Result<u32> {
    let out = Command::new("git")
        .args(["rev-list", "--count", &format!("{base}..HEAD")])
        .output().await.context("git rev-list --count")?;
    if !out.status.success() {
        bail!("git rev-list --count {base}..HEAD failed: {}", String::from_utf8_lossy(&out.stderr).trim());
    }
    let s = String::from_utf8_lossy(&out.stdout);
    s.trim().parse::<u32>().with_context(|| format!("parsing rev-list count: {s:?}"))
}

async fn git_log_format(base: &str, format: &str) -> Result<String> {
    let out = Command::new("git")
        .args(["log", &format!("{base}..HEAD"), &format!("--format={format}"), "--no-color"])
        .output().await.context("git log")?;
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}
