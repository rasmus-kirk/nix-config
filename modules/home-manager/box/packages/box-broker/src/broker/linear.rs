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

    /// Resolve an issue's UUID from its identifier (e.g. "QMS-84" → UUID).
    /// `issueCreate`'s `parentId` needs the UUID, but humans work with the
    /// short identifier.
    async fn issue_uuid(&self, identifier: &str) -> Result<String> {
        let query = r#"
            query IssueUuid($id: String!) {
              issue(id: $id) { id }
            }
        "#;
        let data = self
            .graphql(query, json!({ "id": identifier }))
            .await
            .context("resolving Linear issue by identifier")?;
        data.pointer("/issue/id")
            .and_then(|v| v.as_str())
            .map(str::to_string)
            .ok_or_else(|| anyhow!("no Linear issue with identifier `{identifier}`"))
    }

    /// Resolve an assignee to a user UUID. `"me"` resolves to the token's
    /// viewer. A value containing `@` matches by email; otherwise it matches
    /// a user's name or displayName (exact first, then case-insensitive).
    async fn user_id(&self, who: &str) -> Result<String> {
        if who.eq_ignore_ascii_case("me") {
            let data = self
                .graphql("query { viewer { id } }", json!({}))
                .await
                .context("resolving viewer")?;
            return data
                .pointer("/viewer/id")
                .and_then(|v| v.as_str())
                .map(str::to_string)
                .ok_or_else(|| anyhow!("viewer response missing id"));
        }

        let filter = if who.contains('@') {
            json!({ "email": { "eq": who } })
        } else {
            Value::Null
        };
        let query = r#"
            query Users($filter: UserFilter) {
              users(filter: $filter) {
                nodes { id name displayName email }
              }
            }
        "#;
        let data = self
            .graphql(query, json!({ "filter": filter }))
            .await
            .context("looking up Linear users")?;
        let nodes = data
            .pointer("/users/nodes")
            .and_then(|v| v.as_array())
            .ok_or_else(|| anyhow!("users response missing nodes: {data}"))?;

        if who.contains('@') {
            return nodes
                .first()
                .and_then(|n| n.get("id"))
                .and_then(|v| v.as_str())
                .map(str::to_string)
                .ok_or_else(|| anyhow!("no Linear user with email `{who}`"));
        }

        let field = |n: &Value, k: &str| n.get(k).and_then(|v| v.as_str()).map(str::to_string);
        // Exact name / displayName match first.
        if let Some(id) = nodes.iter().find_map(|n| {
            (field(n, "name").as_deref() == Some(who) || field(n, "displayName").as_deref() == Some(who))
                .then(|| field(n, "id"))
                .flatten()
        }) {
            return Ok(id);
        }
        // Case-insensitive fallback.
        let want = who.to_ascii_lowercase();
        let matches: Vec<&Value> = nodes
            .iter()
            .filter(|n| {
                field(n, "name").map(|s| s.to_ascii_lowercase()) == Some(want.clone())
                    || field(n, "displayName").map(|s| s.to_ascii_lowercase()) == Some(want.clone())
            })
            .collect();
        match matches.as_slice() {
            [n] => field(n, "id").ok_or_else(|| anyhow!("matched user missing id")),
            [] => bail!("no Linear user matching `{who}` (try an email or \"me\")"),
            many => {
                let names: Vec<String> = many
                    .iter()
                    .filter_map(|n| field(n, "email"))
                    .collect();
                bail!("`{who}` is ambiguous ({} users). Use an email: {}", many.len(), names.join(", "))
            }
        }
    }

    /// Resolve a project's UUID from its name (exact first, then
    /// case-insensitive).
    async fn project_id(&self, name: &str) -> Result<String> {
        let query = r#"
            query Projects {
              projects { nodes { id name } }
            }
        "#;
        let data = self
            .graphql(query, json!({}))
            .await
            .context("looking up Linear projects")?;
        let nodes = data
            .pointer("/projects/nodes")
            .and_then(|v| v.as_array())
            .ok_or_else(|| anyhow!("projects response missing nodes: {data}"))?;
        resolve_named(nodes, name)
            .ok_or_else(|| anyhow!("no Linear project matching `{name}`"))
    }

    /// Resolve a milestone's UUID within a project (by project UUID), matching
    /// on name (exact first, then case-insensitive).
    async fn milestone_id(&self, project_uuid: &str, name: &str) -> Result<String> {
        let query = r#"
            query Milestones($id: String!) {
              project(id: $id) {
                projectMilestones { nodes { id name } }
              }
            }
        "#;
        let data = self
            .graphql(query, json!({ "id": project_uuid }))
            .await
            .context("looking up project milestones")?;
        let nodes = data
            .pointer("/project/projectMilestones/nodes")
            .and_then(|v| v.as_array())
            .ok_or_else(|| anyhow!("milestones response missing nodes: {data}"))?;
        resolve_named(nodes, name)
            .ok_or_else(|| anyhow!("no milestone matching `{name}` in that project"))
    }
}

/// Resolve `project` / `milestone` names to UUIDs and insert `projectId` /
/// `projectMilestoneId` into a mutation input. A milestone needs its project,
/// so `milestone` without `project` is an error.
async fn insert_project_milestone(
    client: &LinearClient,
    project: Option<&str>,
    milestone: Option<&str>,
    input: &mut serde_json::Map<String, Value>,
) -> Result<()> {
    let project_uuid = match project {
        Some(p) => {
            let id = client
                .project_id(p)
                .await
                .with_context(|| format!("resolving project {p}"))?;
            input.insert("projectId".into(), Value::String(id.clone()));
            Some(id)
        }
        None => None,
    };
    if let Some(m) = milestone {
        let puid = project_uuid.ok_or_else(|| anyhow!("--milestone requires --project"))?;
        let id = client
            .milestone_id(&puid, m)
            .await
            .with_context(|| format!("resolving milestone {m}"))?;
        input.insert("projectMilestoneId".into(), Value::String(id));
    }
    Ok(())
}

/// Match a `{id, name}` node list by name: exact first, then
/// case-insensitive. Returns the matched node's `id`.
fn resolve_named(nodes: &[Value], name: &str) -> Option<String> {
    let id_of = |n: &Value| n.get("id").and_then(|v| v.as_str()).map(str::to_string);
    if let Some(id) = nodes
        .iter()
        .find(|n| n.get("name").and_then(|v| v.as_str()) == Some(name))
        .and_then(id_of)
    {
        return Some(id);
    }
    let want = name.to_ascii_lowercase();
    nodes
        .iter()
        .find(|n| {
            n.get("name")
                .and_then(|v| v.as_str())
                .map(|s| s.to_ascii_lowercase())
                == Some(want.clone())
        })
        .and_then(id_of)
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
    /// Parent issue identifier (e.g. "QMS-84"). Set ⇒ created as a subtask.
    #[serde(default)]
    parent_id: Option<String>,
    /// Assignee: "me", an email, or a user name/displayName.
    #[serde(default)]
    assignee: Option<String>,
    /// Project name.
    #[serde(default)]
    project: Option<String>,
    /// Milestone name (requires `project`).
    #[serde(default)]
    milestone: Option<String>,
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
        let parent = p
            .parent_id
            .map(|id| format!(" (subtask of {id})"))
            .unwrap_or_default();
        let assignee = p
            .assignee
            .map(|a| format!(", assignee {a}"))
            .unwrap_or_default();
        let project = match (p.project, p.milestone) {
            (Some(pr), Some(m)) => format!(", project {pr}/{m}"),
            (Some(pr), None) => format!(", project {pr}"),
            _ => String::new(),
        };
        format!(
            "Create Linear issue in team {}{}: {}{}{}{}{}",
            p.team_key, parent, p.title, prio, assignee, project, desc_preview
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
            if let Some(parent) = p.parent_id.as_deref() {
                let parent_uuid = self
                    .client
                    .issue_uuid(parent)
                    .await
                    .with_context(|| format!("resolving parent issue {parent}"))?;
                input.insert("parentId".into(), Value::String(parent_uuid));
            }
            if let Some(who) = p.assignee.as_deref() {
                let assignee_id = self
                    .client
                    .user_id(who)
                    .await
                    .with_context(|| format!("resolving assignee {who}"))?;
                input.insert("assigneeId".into(), Value::String(assignee_id));
            }
            insert_project_milestone(
                &self.client,
                p.project.as_deref(),
                p.milestone.as_deref(),
                &mut input,
            )
            .await?;

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
        if let Some(parent) = &p.parent_id {
            fields.push(("Parent".into(), parent.clone()));
        }
        if let Some(a) = &p.assignee {
            fields.push(("Assignee".into(), a.clone()));
        }
        if let Some(pr) = &p.project {
            fields.push(("Project".into(), pr.clone()));
        }
        if let Some(m) = &p.milestone {
            fields.push(("Milestone".into(), m.clone()));
        }
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
    /// New parent issue identifier (e.g. "QMS-79"). Set ⇒ reparent as a subtask.
    #[serde(default)]
    parent_id: Option<String>,
    /// New assignee: "me", an email, or a user name/displayName.
    #[serde(default)]
    assignee: Option<String>,
    /// New project name.
    #[serde(default)]
    project: Option<String>,
    /// New milestone name (requires `project`).
    #[serde(default)]
    milestone: Option<String>,
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
        if let Some(parent) = &p.parent_id {
            bits.push(format!("parent→{parent}"));
        }
        if let Some(a) = &p.assignee {
            bits.push(format!("assignee→{a}"));
        }
        if let Some(pr) = &p.project {
            bits.push(format!("project→{pr}"));
        }
        if let Some(m) = &p.milestone {
            bits.push(format!("milestone→{m}"));
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
                && p.parent_id.is_none()
                && p.assignee.is_none()
                && p.project.is_none()
                && p.milestone.is_none()
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
            if let Some(parent) = p.parent_id.as_deref() {
                let parent_uuid = self
                    .client
                    .issue_uuid(parent)
                    .await
                    .with_context(|| format!("resolving parent issue {parent}"))?;
                input.insert("parentId".into(), Value::String(parent_uuid));
            }
            if let Some(who) = p.assignee.as_deref() {
                let assignee_id = self
                    .client
                    .user_id(who)
                    .await
                    .with_context(|| format!("resolving assignee {who}"))?;
                input.insert("assigneeId".into(), Value::String(assignee_id));
            }
            insert_project_milestone(
                &self.client,
                p.project.as_deref(),
                p.milestone.as_deref(),
                &mut input,
            )
            .await?;

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
        if let Some(parent) = &p.parent_id {
            fields.push(("New parent".into(), parent.clone()));
        }
        if let Some(a) = &p.assignee {
            fields.push(("New assignee".into(), a.clone()));
        }
        if let Some(pr) = &p.project {
            fields.push(("New project".into(), pr.clone()));
        }
        if let Some(m) = &p.milestone {
            fields.push(("New milestone".into(), m.clone()));
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
