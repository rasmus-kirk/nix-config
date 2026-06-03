use super::{Broker, BrokerFuture};
use crate::types::RequestEnvelope;
use anyhow::{anyhow, bail, Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::path::PathBuf;
use std::time::Duration;
use tokio::fs;

const GH_API: &str = "https://api.github.com";
const GH_GRAPHQL: &str = "https://api.github.com/graphql";
const API_VERSION: &str = "2022-11-28";
const USER_AGENT: &str = "approval-tui/0.1";

/// Shared GitHub API client. Holds the PAT path; loads/strips the token
/// fresh on each request (kept in memory only for the duration of one call).
#[derive(Clone)]
pub struct GhClient {
    http: Client,
    token_file: PathBuf,
}

impl GhClient {
    pub fn new(token_file: PathBuf) -> Result<Self> {
        let http = Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .context("building reqwest client")?;
        Ok(Self { http, token_file })
    }

    async fn read_token(&self) -> Result<String> {
        let raw = fs::read_to_string(&self.token_file)
            .await
            .with_context(|| format!("reading PAT at {}", self.token_file.display()))?;
        let trimmed = raw.trim().to_string();
        if trimmed.is_empty() {
            bail!("PAT file {} is empty", self.token_file.display());
        }
        Ok(trimmed)
    }

    async fn rest_request(
        &self,
        method: reqwest::Method,
        url: &str,
        body: Option<Value>,
    ) -> Result<(reqwest::StatusCode, Value)> {
        let token = self.read_token().await?;
        let mut req = self
            .http
            .request(method.clone(), url)
            .header("Authorization", format!("Bearer {token}"))
            .header("Accept", "application/vnd.github+json")
            .header("X-GitHub-Api-Version", API_VERSION)
            .header("User-Agent", USER_AGENT);
        if let Some(b) = body {
            req = req.json(&b);
        }
        let resp = req
            .send()
            .await
            .with_context(|| format!("{method} {url}"))?;
        let status = resp.status();
        let value = resp
            .json::<Value>()
            .await
            .context("decoding GitHub response as JSON")?;
        Ok((status, value))
    }
}

// ─── create ────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct CreatePayload {
    repo: String,
    head: String,
    base: String,
    title: String,
    #[serde(default)]
    body: String,
    #[serde(default)]
    draft: bool,
}

#[derive(Debug, Serialize)]
struct CreatedPr {
    url: String,
    number: u64,
    op: &'static str,
}

pub struct GhPrCreate {
    pub client: GhClient,
}

impl Broker for GhPrCreate {
    fn op_id(&self) -> &'static str {
        "gh.pr.create"
    }

    fn fallback_summary(&self, env: &RequestEnvelope) -> String {
        let payload: CreatePayload =
            serde_json::from_value(env.payload.clone()).unwrap_or(CreatePayload {
                repo: "?".into(),
                head: "?".into(),
                base: "?".into(),
                title: "?".into(),
                body: String::new(),
                draft: false,
            });
        format!(
            "Create PR in {}: {} → {}{}\n{}",
            payload.repo,
            payload.head,
            payload.base,
            if payload.draft { "  [DRAFT]" } else { "" },
            payload.title
        )
    }

    fn dispatch<'a>(&'a self, env: &'a RequestEnvelope) -> BrokerFuture<'a> {
        Box::pin(async move {
            let p: CreatePayload =
                serde_json::from_value(env.payload.clone()).context("decoding create payload")?;
            let url = format!("{GH_API}/repos/{}/pulls", p.repo);
            let body = json!({
                "title": p.title,
                "body": p.body,
                "head": p.head,
                "base": p.base,
                "draft": p.draft,
            });
            let (status, value) = self
                .client
                .rest_request(reqwest::Method::POST, &url, Some(body))
                .await?;
            if status.as_u16() != 201 {
                bail!("GitHub create-PR returned HTTP {}: {}", status, value);
            }
            let html_url = value
                .get("html_url")
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow!("response missing html_url"))?
                .to_string();
            let number = value
                .get("number")
                .and_then(|v| v.as_u64())
                .ok_or_else(|| anyhow!("response missing number"))?;
            Ok(serde_json::to_value(CreatedPr {
                url: html_url,
                number,
                op: "create",
            })?)
        })
    }
}

// ─── edit ──────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct EditPayload {
    repo: String,
    pr_number: u64,
    #[serde(default)]
    title: Option<String>,
    #[serde(default)]
    body: Option<String>,
    #[serde(default)]
    base: Option<String>,
    #[serde(default)]
    state: Option<String>,
    #[serde(default)]
    title_set: u8,
    #[serde(default)]
    body_set: u8,
    #[serde(default)]
    base_set: u8,
    #[serde(default)]
    state_set: u8,
    #[serde(default)]
    draft_target: Option<String>,
}

#[derive(Debug, Serialize)]
struct EditedPr {
    url: String,
    number: u64,
    op: &'static str,
}

pub struct GhPrEdit {
    pub client: GhClient,
}

impl Broker for GhPrEdit {
    fn op_id(&self) -> &'static str {
        "gh.pr.edit"
    }

    fn fallback_summary(&self, env: &RequestEnvelope) -> String {
        let p: EditPayload = match serde_json::from_value(env.payload.clone()) {
            Ok(v) => v,
            Err(_) => return "Edit PR (malformed payload)".into(),
        };
        let mut bits: Vec<String> = vec![];
        if p.title_set == 1 {
            bits.push("title".into());
        }
        if p.body_set == 1 {
            bits.push("body".into());
        }
        if p.base_set == 1 {
            bits.push("base".into());
        }
        if p.state_set == 1 {
            bits.push(format!("state→{}", p.state.unwrap_or_default()));
        }
        if let Some(d) = p.draft_target.as_deref() {
            bits.push(format!("draft→{d}"));
        }
        let summary = if bits.is_empty() {
            "nothing".to_string()
        } else {
            bits.join(", ")
        };
        format!("Edit PR {}/#{}: {}", p.repo, p.pr_number, summary)
    }

    fn dispatch<'a>(&'a self, env: &'a RequestEnvelope) -> BrokerFuture<'a> {
        Box::pin(async move {
            let p: EditPayload =
                serde_json::from_value(env.payload.clone()).context("decoding edit payload")?;
            let url = format!("{GH_API}/repos/{}/pulls/{}", p.repo, p.pr_number);

            let mut fields = Map::new();
            if p.title_set == 1 {
                fields.insert("title".into(), json!(p.title.clone().unwrap_or_default()));
            }
            if p.body_set == 1 {
                fields.insert("body".into(), json!(p.body.clone().unwrap_or_default()));
            }
            if p.base_set == 1 {
                fields.insert("base".into(), json!(p.base.clone().unwrap_or_default()));
            }
            if p.state_set == 1 {
                fields.insert("state".into(), json!(p.state.clone().unwrap_or_default()));
            }

            let has_fields = !fields.is_empty();
            let draft_target = p.draft_target.as_deref();
            if !has_fields && draft_target.is_none() {
                bail!("edit has no fields to update");
            }

            let mut node_id: Option<String> = None;
            let mut latest: Option<Value> = None;

            // Step 1: REST PATCH
            if has_fields {
                let (status, value) = self
                    .client
                    .rest_request(
                        reqwest::Method::PATCH,
                        &url,
                        Some(Value::Object(fields.clone())),
                    )
                    .await?;
                if status.as_u16() != 200 {
                    bail!("GitHub edit-PR returned HTTP {}: {}", status, value);
                }
                node_id = value
                    .get("node_id")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string());
                latest = Some(value);
            }

            // Step 2: GraphQL for draft toggle
            if let Some(target) = draft_target {
                if node_id.is_none() {
                    let (status, value) = self
                        .client
                        .rest_request(reqwest::Method::GET, &url, None)
                        .await?;
                    if status.as_u16() != 200 {
                        bail!(
                            "GitHub get-PR (for node_id) returned HTTP {}: {}",
                            status,
                            value
                        );
                    }
                    node_id = value
                        .get("node_id")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string());
                }
                let node = node_id
                    .as_deref()
                    .ok_or_else(|| anyhow!("missing node_id for draft toggle"))?;
                let mutation = match target {
                    "draft" => "convertPullRequestToDraft",
                    "ready" => "markPullRequestReadyForReview",
                    other => bail!("invalid draft_target: {other}"),
                };
                let query = format!(
                    "mutation {{ {mutation}(input: {{pullRequestId: \"{node}\"}}) \
                     {{ pullRequest {{ id url number isDraft }} }} }}"
                );
                let (status, value) = self
                    .client
                    .rest_request(
                        reqwest::Method::POST,
                        GH_GRAPHQL,
                        Some(json!({ "query": query })),
                    )
                    .await?;
                if status.as_u16() != 200 || value.get("errors").is_some() {
                    bail!("GraphQL draft toggle failed (HTTP {}): {}", status, value);
                }
                // Re-fetch via REST so we return a consistent shape
                let (status, value) = self
                    .client
                    .rest_request(reqwest::Method::GET, &url, None)
                    .await?;
                if status.as_u16() != 200 {
                    bail!(
                        "GitHub get-PR (post-graphql refresh) HTTP {}: {}",
                        status,
                        value
                    );
                }
                latest = Some(value);
            }

            let latest = latest.ok_or_else(|| anyhow!("no successful API call recorded"))?;
            let html_url = latest
                .get("html_url")
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow!("response missing html_url"))?
                .to_string();
            let number = latest
                .get("number")
                .and_then(|v| v.as_u64())
                .ok_or_else(|| anyhow!("response missing number"))?;
            Ok(serde_json::to_value(EditedPr {
                url: html_url,
                number,
                op: "edit",
            })?)
        })
    }
}

// ─── review ────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct ReviewPayload {
    repo: String,
    pr_number: u64,
    #[serde(default)]
    body: String,
    #[serde(default = "default_event")]
    event: String,
    #[serde(default)]
    comments: Vec<Value>,
}

fn default_event() -> String {
    "COMMENT".into()
}

#[derive(Debug, Serialize)]
struct ReviewedPr {
    url: String,
    op: &'static str,
}

pub struct GhPrReview {
    pub client: GhClient,
}

impl Broker for GhPrReview {
    fn op_id(&self) -> &'static str {
        "gh.pr.review"
    }

    fn fallback_summary(&self, env: &RequestEnvelope) -> String {
        let p: ReviewPayload = match serde_json::from_value(env.payload.clone()) {
            Ok(v) => v,
            Err(_) => return "Review PR (malformed payload)".into(),
        };
        format!(
            "Review {} #{}: event={}, {} inline comment(s)",
            p.repo,
            p.pr_number,
            p.event,
            p.comments.len()
        )
    }

    fn dispatch<'a>(&'a self, env: &'a RequestEnvelope) -> BrokerFuture<'a> {
        Box::pin(async move {
            let p: ReviewPayload =
                serde_json::from_value(env.payload.clone()).context("decoding review payload")?;
            // Defense-in-depth — the in-box client also blocks this.
            if p.event == "APPROVE" {
                bail!("APPROVE not allowed via broker");
            }
            if p.event != "COMMENT" && p.event != "REQUEST_CHANGES" {
                bail!("invalid event: {}", p.event);
            }
            let mut body = Map::new();
            if !p.body.is_empty() {
                body.insert("body".into(), Value::String(p.body.clone()));
            }
            body.insert("event".into(), Value::String(p.event.clone()));
            if !p.comments.is_empty() {
                body.insert("comments".into(), Value::Array(p.comments.clone()));
            }
            let url = format!("{GH_API}/repos/{}/pulls/{}/reviews", p.repo, p.pr_number);
            let (status, value) = self
                .client
                .rest_request(reqwest::Method::POST, &url, Some(Value::Object(body)))
                .await?;
            if status.as_u16() != 200 {
                bail!("GitHub review submit returned HTTP {}: {}", status, value);
            }
            let html_url = value
                .get("html_url")
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow!("response missing html_url"))?
                .to_string();
            Ok(serde_json::to_value(ReviewedPr {
                url: html_url,
                op: "review",
            })?)
        })
    }
}

// ─── review-append ─────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct ReviewAppendPayload {
    repo: String,
    pr_number: u64,
    comments: Vec<Value>,
}

#[derive(Debug, Serialize)]
struct AppendedComments {
    op: &'static str,
    url: String,
    appended: usize,
}

pub struct GhPrReviewAppend {
    pub client: GhClient,
}

/// Whitelist of comment fields forwarded to GitHub. We only pass through
/// what the in-box CLI documents, never the raw JSON object.
const COMMENT_FIELDS: &[&str] = &[
    "path",
    "line",
    "body",
    "side",
    "start_line",
    "start_side",
    "in_reply_to",
];

fn comment_to_post_body(commit_id: &str, raw: &Value) -> Result<Value> {
    let obj = raw
        .as_object()
        .ok_or_else(|| anyhow!("comment entry is not an object"))?;
    // Required: path, line, body.
    for required in ["path", "line", "body"] {
        if !obj.contains_key(required) {
            bail!("comment entry missing required field `{required}`");
        }
    }
    let mut out = Map::new();
    out.insert("commit_id".into(), Value::String(commit_id.to_string()));
    for &field in COMMENT_FIELDS {
        if let Some(v) = obj.get(field) {
            out.insert(field.into(), v.clone());
        }
    }
    Ok(Value::Object(out))
}

impl Broker for GhPrReviewAppend {
    fn op_id(&self) -> &'static str {
        "gh.pr.review-append"
    }

    fn fallback_summary(&self, env: &RequestEnvelope) -> String {
        let p: ReviewAppendPayload = match serde_json::from_value(env.payload.clone()) {
            Ok(v) => v,
            Err(_) => return "Append review comments (malformed payload)".into(),
        };
        format!(
            "Append {} inline comment(s) to PR {}/#{}",
            p.comments.len(),
            p.repo,
            p.pr_number,
        )
    }

    fn dispatch<'a>(&'a self, env: &'a RequestEnvelope) -> BrokerFuture<'a> {
        Box::pin(async move {
            let p: ReviewAppendPayload = serde_json::from_value(env.payload.clone())
                .context("decoding review-append payload")?;
            if p.comments.is_empty() {
                bail!("review-append: comments array is empty");
            }
            // Pre-validate every entry before any POST so we don't half-post.
            for (i, c) in p.comments.iter().enumerate() {
                let obj = c
                    .as_object()
                    .ok_or_else(|| anyhow!("comment[{i}] is not an object"))?;
                if !obj.get("path").is_some_and(|v| v.is_string()) {
                    bail!("comment[{i}] missing string field `path`");
                }
                if !obj.get("line").is_some_and(|v| v.is_number()) {
                    bail!("comment[{i}] missing numeric field `line`");
                }
                if !obj.get("body").is_some_and(|v| v.is_string()) {
                    bail!("comment[{i}] missing string field `body`");
                }
            }

            // Look up the PR's head SHA — every comment POST needs commit_id.
            let pr_url = format!("{GH_API}/repos/{}/pulls/{}", p.repo, p.pr_number);
            let (status, pr_value) = self
                .client
                .rest_request(reqwest::Method::GET, &pr_url, None)
                .await?;
            if status.as_u16() != 200 {
                bail!("GitHub get-PR returned HTTP {}: {}", status, pr_value);
            }
            let head_sha = pr_value
                .pointer("/head/sha")
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow!("PR response missing .head.sha"))?
                .to_string();
            let html_url = pr_value
                .get("html_url")
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow!("PR response missing .html_url"))?
                .to_string();

            // Post each comment. Stop on first failure.
            let post_url = format!("{GH_API}/repos/{}/pulls/{}/comments", p.repo, p.pr_number);
            let mut appended: usize = 0;
            for (i, c) in p.comments.iter().enumerate() {
                let body = comment_to_post_body(&head_sha, c)?;
                let (status, value) = self
                    .client
                    .rest_request(reqwest::Method::POST, &post_url, Some(body))
                    .await?;
                // Both 200 and 201 are observed for this endpoint.
                if status.as_u16() != 200 && status.as_u16() != 201 {
                    bail!(
                        "appended {appended} comment(s); HTTP {} on comment {i}: {}",
                        status,
                        value
                    );
                }
                appended += 1;
            }

            Ok(serde_json::to_value(AppendedComments {
                op: "review-append",
                url: html_url,
                appended,
            })?)
        })
    }
}
