use super::{Broker, BrokerFuture};
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
}
