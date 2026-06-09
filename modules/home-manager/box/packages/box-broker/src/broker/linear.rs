use super::{Broker, BrokerFuture, DetailView};
use crate::types::RequestEnvelope;
use anyhow::{anyhow, bail, Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::path::PathBuf;
use std::time::Duration;
use tokio::fs;

const LINEAR_GQL: &str = "https://api.linear.app/graphql";

/// Shared Linear GraphQL client. Loads the PAT fresh on each request
/// (kept in memory only for the duration of one call).
#[derive(Clone)]
pub struct LinearClient {
    http: Client,
    token_file: PathBuf,
}

impl LinearClient {
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
            .with_context(|| format!("reading Linear PAT at {}", self.token_file.display()))?;
        let trimmed = raw.trim().to_string();
        if trimmed.is_empty() {
            bail!("Linear PAT file {} is empty", self.token_file.display());
        }
        Ok(trimmed)
    }

    async fn graphql(&self, query: &str, variables: Value) -> Result<Value> {
        let token = self.read_token().await?;
        // Linear PATs go in `Authorization` *without* a Bearer prefix.
        let resp = self
            .http
            .post(LINEAR_GQL)
            .header("Authorization", token)
            .header("Content-Type", "application/json")
            .json(&json!({ "query": query, "variables": variables }))
            .send()
            .await
            .context("POST api.linear.app/graphql")?;
        let status = resp.status();
        let body: Value = resp
            .json()
            .await
            .context("decoding Linear response as JSON")?;
        if !status.is_success() {
            bail!("Linear returned HTTP {}: {}", status, body);
        }
        if let Some(errors) = body.get("errors") {
            bail!("Linear GraphQL errors: {errors}");
        }
        body.get("data")
            .cloned()
            .ok_or_else(|| anyhow!("Linear response missing data: {body}"))
    }

    /// Resolve a workflow-state UUID by name, scoped to the team owning
    /// the given issue. State names ("Todo", "In Progress", "Done", …)
    /// are per-team in Linear; we need the issue's team to disambiguate.
    /// Matches by exact name first, then case-insensitive fallback.
    async fn resolve_state_id(&self, issue_id: &str, state_name: &str) -> Result<String> {
        let query = r#"
            query IssueWithStates($id: String!) {
              issue(id: $id) {
                id
                team {
                  id
                  states {
                    nodes { id name }
                  }
                }
              }
            }
        "#;
        let data = self
            .graphql(query, json!({ "id": issue_id }))
            .await
            .context("looking up issue + team states")?;
        let nodes = data
            .pointer("/issue/team/states/nodes")
            .and_then(|v| v.as_array())
            .ok_or_else(|| anyhow!("issue {issue_id}: no states in response"))?;
        // Exact match first.
        let want = state_name;
        if let Some(id) = nodes.iter().find_map(|n| {
            (n.get("name").and_then(|v| v.as_str()) == Some(want))
                .then(|| n.get("id").and_then(|v| v.as_str()))
                .flatten()
        }) {
            return Ok(id.to_string());
        }
        // Case-insensitive fallback.
        let want_lc = state_name.to_ascii_lowercase();
        if let Some(id) = nodes.iter().find_map(|n| {
            let name = n.get("name").and_then(|v| v.as_str())?;
            (name.to_ascii_lowercase() == want_lc)
                .then(|| n.get("id").and_then(|v| v.as_str()))
                .flatten()
        }) {
            return Ok(id.to_string());
        }
        let available: Vec<&str> = nodes
            .iter()
            .filter_map(|n| n.get("name").and_then(|v| v.as_str()))
            .collect();
        bail!(
            "no workflow state matching `{state_name}` for issue {issue_id}. Available: {}",
            available.join(", ")
        )
    }

    /// Resolve a team's UUID from its key (e.g. "QMS" → UUID). Linear's
    /// `issueCreate` mutation needs the UUID, but humans/scripts work
    /// with the short key.
    async fn team_id_by_key(&self, key: &str) -> Result<String> {
        let query = r#"
            query TeamByKey($key: String!) {
              teams(filter: { key: { eq: $key } }) {
                nodes { id key }
              }
            }
        "#;
        let data = self
            .graphql(query, json!({ "key": key }))
            .await
            .context("resolving Linear team by key")?;
        let nodes = data
            .pointer("/teams/nodes")
            .and_then(|v| v.as_array())
            .ok_or_else(|| anyhow!("teams response missing nodes: {data}"))?;
        let id = nodes
            .first()
            .and_then(|n| n.get("id"))
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow!("no Linear team with key `{key}`"))?;
        Ok(id.to_string())
    }
}

// ─── issue.create ──────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct IssueCreatePayload {
    team_key: String,
    title: String,
    #[serde(default)]
    description: String,
    /// Linear priority: 0 (none) … 4 (low). Optional; omitted ⇒ no priority.
    #[serde(default)]
    priority: Option<u8>,
}

#[derive(Debug, Serialize)]
struct CreatedIssue {
    op: &'static str,
    identifier: String,
    url: String,
    title: String,
}

pub struct LinearIssueCreate {
    pub client: LinearClient,
}

impl Broker for LinearIssueCreate {
    fn op_id(&self) -> &'static str {
        "linear.issue.create"
    }

    fn fallback_summary(&self, env: &RequestEnvelope) -> String {
        let p: IssueCreatePayload = match serde_json::from_value(env.payload.clone()) {
            Ok(p) => p,
            Err(_) => return "Create Linear issue (malformed payload)".into(),
        };
        let prio = p
            .priority
            .map(|n| format!(", priority {n}"))
            .unwrap_or_default();
        let desc_preview = if p.description.is_empty() {
            String::new()
        } else {
            let one_line = p.description.lines().next().unwrap_or("");
            let trimmed: String = one_line.chars().take(140).collect();
            format!("\n{trimmed}")
        };
        format!(
            "Create Linear issue in team {}: {}{}{}",
            p.team_key, p.title, prio, desc_preview
        )
    }

    fn dispatch<'a>(&'a self, env: &'a RequestEnvelope) -> BrokerFuture<'a> {
        Box::pin(async move {
            let p: IssueCreatePayload = serde_json::from_value(env.payload.clone())
                .context("decoding linear.issue.create payload")?;
            if p.title.trim().is_empty() {
                bail!("linear.issue.create: title is required");
            }
            let team_id = self
                .client
                .team_id_by_key(&p.team_key)
                .await
                .with_context(|| format!("looking up team {}", p.team_key))?;

            let mut input = serde_json::Map::new();
            input.insert("teamId".into(), Value::String(team_id));
            input.insert("title".into(), Value::String(p.title));
            if !p.description.is_empty() {
                input.insert("description".into(), Value::String(p.description));
            }
            if let Some(n) = p.priority {
                input.insert("priority".into(), json!(n));
            }

            let mutation = r#"
                mutation IssueCreate($input: IssueCreateInput!) {
                  issueCreate(input: $input) {
                    success
                    issue { id identifier title url }
                  }
                }
            "#;
            let data = self
                .client
                .graphql(mutation, json!({ "input": Value::Object(input) }))
                .await
                .context("POST issueCreate")?;
            let success = data
                .pointer("/issueCreate/success")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            if !success {
                bail!("Linear issueCreate returned success=false: {data}");
            }
            let issue = data
                .pointer("/issueCreate/issue")
                .ok_or_else(|| anyhow!("issueCreate response missing issue: {data}"))?;
            let identifier = issue
                .get("identifier")
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow!("issue missing identifier"))?
                .to_string();
            let url = issue
                .get("url")
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow!("issue missing url"))?
                .to_string();
            let title = issue
                .get("title")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            Ok(serde_json::to_value(CreatedIssue {
                op: "linear.issue.create",
                identifier,
                url,
                title,
            })?)
        })
    }

    fn render_detail(&self, env: &RequestEnvelope) -> Option<DetailView> {
        let p: IssueCreatePayload = serde_json::from_value(env.payload.clone()).ok()?;
        let mut fields = vec![
            ("Team".into(), p.team_key.clone()),
            ("Title".into(), p.title.clone()),
        ];
        if let Some(n) = p.priority {
            fields.push(("Priority".into(), priority_label(n)));
        }
        let mut prose = vec![];
        if !p.description.is_empty() {
            prose.push(("Description".into(), p.description));
        }
        Some(DetailView {
            title: format!("Create Linear issue in {}", p.team_key),
            fields,
            flags: vec![],
            prose,
        })
    }
}

/// Linear priority enum: 0 = no priority, 1 = urgent, 2 = high, 3 = medium, 4 = low.
fn priority_label(n: u8) -> String {
    match n {
        0 => "No priority (0)".into(),
        1 => "Urgent (1)".into(),
        2 => "High (2)".into(),
        3 => "Medium (3)".into(),
        4 => "Low (4)".into(),
        other => format!("{other} (?)"),
    }
}

// ─── issue.update ──────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct IssueUpdatePayload {
    issue_id: String,
    #[serde(default)]
    status: Option<String>,
    #[serde(default)]
    title: Option<String>,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    priority: Option<u8>,
}

#[derive(Debug, Serialize)]
struct UpdatedIssue {
    op: &'static str,
    identifier: String,
    url: String,
    title: String,
}

pub struct LinearIssueUpdate {
    pub client: LinearClient,
}

impl Broker for LinearIssueUpdate {
    fn op_id(&self) -> &'static str {
        "linear.issue.update"
    }

    fn fallback_summary(&self, env: &RequestEnvelope) -> String {
        let p: IssueUpdatePayload = match serde_json::from_value(env.payload.clone()) {
            Ok(p) => p,
            Err(_) => return "Update Linear issue (malformed payload)".into(),
        };
        let mut bits = vec![];
        if let Some(s) = &p.status {
            bits.push(format!("status→{s}"));
        }
        if p.title.is_some() {
            bits.push("title".into());
        }
        if p.description.is_some() {
            bits.push("description".into());
        }
        if let Some(n) = p.priority {
            bits.push(format!("priority→{n}"));
        }
        format!("Update {}: {}", p.issue_id, bits.join(", "))
    }

    fn dispatch<'a>(&'a self, env: &'a RequestEnvelope) -> BrokerFuture<'a> {
        Box::pin(async move {
            let p: IssueUpdatePayload = serde_json::from_value(env.payload.clone())
                .context("decoding linear.issue.update payload")?;
            if p.status.is_none()
                && p.title.is_none()
                && p.description.is_none()
                && p.priority.is_none()
            {
                bail!("linear.issue.update: nothing to update");
            }

            let mut input = serde_json::Map::new();
            if let Some(state_name) = p.status.as_deref() {
                let state_id = self
                    .client
                    .resolve_state_id(&p.issue_id, state_name)
                    .await
                    .with_context(|| format!("resolving status `{state_name}`"))?;
                input.insert("stateId".into(), Value::String(state_id));
            }
            if let Some(t) = p.title {
                input.insert("title".into(), Value::String(t));
            }
            if let Some(d) = p.description {
                input.insert("description".into(), Value::String(d));
            }
            if let Some(n) = p.priority {
                input.insert("priority".into(), json!(n));
            }

            let mutation = r#"
                mutation IssueUpdate($id: String!, $input: IssueUpdateInput!) {
                  issueUpdate(id: $id, input: $input) {
                    success
                    issue { id identifier title url }
                  }
                }
            "#;
            let data = self
                .client
                .graphql(
                    mutation,
                    json!({ "id": p.issue_id, "input": Value::Object(input) }),
                )
                .await
                .context("POST issueUpdate")?;
            let success = data
                .pointer("/issueUpdate/success")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            if !success {
                bail!("Linear issueUpdate returned success=false: {data}");
            }
            let issue = data
                .pointer("/issueUpdate/issue")
                .ok_or_else(|| anyhow!("issueUpdate response missing issue: {data}"))?;
            let identifier = issue
                .get("identifier")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let url = issue
                .get("url")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let title = issue
                .get("title")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            Ok(serde_json::to_value(UpdatedIssue {
                op: "linear.issue.update",
                identifier,
                url,
                title,
            })?)
        })
    }

    fn render_detail(&self, env: &RequestEnvelope) -> Option<DetailView> {
        let p: IssueUpdatePayload = serde_json::from_value(env.payload.clone()).ok()?;
        let mut fields = vec![("Issue".into(), p.issue_id.clone())];
        if let Some(s) = &p.status {
            fields.push(("New status".into(), s.clone()));
        }
        if let Some(t) = &p.title {
            fields.push(("New title".into(), t.clone()));
        }
        if let Some(n) = p.priority {
            fields.push(("New priority".into(), priority_label(n)));
        }
        let mut prose = vec![];
        if let Some(d) = p.description {
            if !d.is_empty() {
                prose.push(("New description".into(), d));
            }
        }
        Some(DetailView {
            title: format!("Update Linear issue {}", p.issue_id),
            fields,
            flags: vec![],
            prose,
        })
    }
}

// ─── issue.comment ─────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct IssueCommentPayload {
    issue_id: String,
    body: String,
}

#[derive(Debug, Serialize)]
struct CreatedComment {
    op: &'static str,
    issue_identifier: String,
    url: String,
}

pub struct LinearIssueComment {
    pub client: LinearClient,
}

impl Broker for LinearIssueComment {
    fn op_id(&self) -> &'static str {
        "linear.issue.comment"
    }

    fn fallback_summary(&self, env: &RequestEnvelope) -> String {
        let p: IssueCommentPayload = match serde_json::from_value(env.payload.clone()) {
            Ok(p) => p,
            Err(_) => return "Comment on Linear issue (malformed payload)".into(),
        };
        let preview = p
            .body
            .lines()
            .next()
            .unwrap_or("")
            .chars()
            .take(80)
            .collect::<String>();
        format!("Comment on {}: {preview}", p.issue_id)
    }

    fn dispatch<'a>(&'a self, env: &'a RequestEnvelope) -> BrokerFuture<'a> {
        Box::pin(async move {
            let p: IssueCommentPayload = serde_json::from_value(env.payload.clone())
                .context("decoding linear.issue.comment payload")?;
            if p.body.trim().is_empty() {
                bail!("linear.issue.comment: body is required");
            }
            let mutation = r#"
                mutation CommentCreate($input: CommentCreateInput!) {
                  commentCreate(input: $input) {
                    success
                    comment {
                      id
                      url
                      issue { identifier }
                    }
                  }
                }
            "#;
            let data = self
                .client
                .graphql(
                    mutation,
                    json!({ "input": { "issueId": p.issue_id, "body": p.body } }),
                )
                .await
                .context("POST commentCreate")?;
            let success = data
                .pointer("/commentCreate/success")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            if !success {
                bail!("Linear commentCreate returned success=false: {data}");
            }
            let comment = data
                .pointer("/commentCreate/comment")
                .ok_or_else(|| anyhow!("commentCreate response missing comment: {data}"))?;
            let url = comment
                .get("url")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let issue_identifier = comment
                .pointer("/issue/identifier")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            Ok(serde_json::to_value(CreatedComment {
                op: "linear.issue.comment",
                issue_identifier,
                url,
            })?)
        })
    }

    fn render_detail(&self, env: &RequestEnvelope) -> Option<DetailView> {
        let p: IssueCommentPayload = serde_json::from_value(env.payload.clone()).ok()?;
        Some(DetailView {
            title: format!("Comment on Linear issue {}", p.issue_id),
            fields: vec![("Issue".into(), p.issue_id.clone())],
            flags: vec![],
            prose: if p.body.is_empty() {
                vec![]
            } else {
                vec![("Comment".into(), p.body)]
            },
        })
    }
}
