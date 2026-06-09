use crate::agents::AgentRegistry;
use crate::broker::{DetailView, Registry};
use crate::queue::Queue;
use box_broker::markdown::markdown_to_text;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Wrap};
use ratatui::Frame;

pub struct UiState {
    pub help_visible: bool,
    pub message: Option<String>,
}

impl UiState {
    pub fn new() -> Self {
        Self {
            help_visible: false,
            message: None,
        }
    }
}

impl Default for UiState {
    fn default() -> Self {
        Self::new()
    }
}

pub fn draw(
    frame: &mut Frame,
    queue: &Queue,
    agents: &AgentRegistry,
    registry: &Registry,
    state: &UiState,
) {
    // Vertical: top = queue+detail, middle = agents (up to ~6 rows),
    // bottom = status bar.
    let agents_height = (agents.len().min(5) as u16).saturating_add(2); // +2 for borders
    let agents_height = if agents.len() == 0 { 3 } else { agents_height };
    let outer = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Min(0),
            Constraint::Length(agents_height),
            Constraint::Length(1),
        ])
        .split(frame.area());

    let main = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Length(32), Constraint::Min(0)])
        .split(outer[0]);

    draw_queue(frame, main[0], queue);
    draw_detail(frame, main[1], queue, registry);
    draw_agents(frame, outer[1], agents);
    draw_status(frame, outer[2], queue, state);

    if state.help_visible {
        draw_help_overlay(frame, frame.area());
    }
}

fn draw_agents(frame: &mut Frame, area: Rect, agents: &AgentRegistry) {
    let items: Vec<ListItem> = agents
        .recent(5)
        .iter()
        .map(|a| {
            let status_style = match a.state {
                crate::agents::AgentState::Working => {
                    Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)
                }
                crate::agents::AgentState::Ready => {
                    Style::default().fg(Color::Green).add_modifier(Modifier::BOLD)
                }
                crate::agents::AgentState::Unknown => Style::default().fg(Color::DarkGray),
            };
            let in_flight_extra = if a.in_flight > 0 {
                format!("  in-flight {}", a.in_flight)
            } else {
                String::new()
            };
            let line = Line::from(vec![
                Span::styled(format!("{:>8} ", a.state.label()), status_style),
                Span::raw(format!("{:<24} ", truncate(a.label(), 24))),
                Span::styled(
                    format!("seen {}{}", a.total_seen, in_flight_extra),
                    Style::default().fg(Color::DarkGray),
                ),
            ]);
            ListItem::new(line)
        })
        .collect();
    let title = if agents.len() == 0 {
        "Agents (none yet)".to_string()
    } else {
        format!("Agents ({})", agents.len())
    };
    let list = List::new(items).block(Block::default().borders(Borders::ALL).title(title));
    frame.render_widget(list, area);
}

fn truncate(s: &str, n: usize) -> String {
    if s.chars().count() <= n {
        s.to_string()
    } else {
        let mut t: String = s.chars().take(n.saturating_sub(1)).collect();
        t.push('…');
        t
    }
}

fn draw_queue(frame: &mut Frame, area: Rect, queue: &Queue) {
    let items: Vec<ListItem> = queue
        .iter()
        .map(|(_id, r)| {
            let state_style = match r.state {
                crate::types::RequestState::Pending => Style::default().fg(Color::Yellow),
                crate::types::RequestState::Dispatching => Style::default().fg(Color::Cyan),
                crate::types::RequestState::DispatchFailed => Style::default().fg(Color::Red),
            };
            let line = Line::from(vec![
                Span::styled(format!("{:>11} ", r.state.label()), state_style),
                Span::raw(r.envelope.op.clone()),
            ]);
            ListItem::new(line)
        })
        .collect();

    let mut state = ListState::default();
    if !queue.is_empty() {
        state.select(Some(queue.selected_index()));
    }

    let list = List::new(items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(format!("Queue ({})", queue.len())),
        )
        .highlight_style(
            Style::default()
                .add_modifier(Modifier::BOLD)
                .bg(Color::DarkGray),
        )
        .highlight_symbol("▸ ");

    frame.render_stateful_widget(list, area, &mut state);
}

fn draw_detail(frame: &mut Frame, area: Rect, queue: &Queue, registry: &Registry) {
    let Some(req) = queue.selected() else {
        let p = Paragraph::new("Queue empty. Waiting for requests...")
            .block(Block::default().borders(Borders::ALL).title("Detail"));
        frame.render_widget(p, area);
        return;
    };
    let env = &req.envelope;
    match registry.render_detail(env) {
        Some(view) => draw_detail_structured(frame, area, req, &view),
        None => draw_detail_generic(frame, area, req),
    }
}

fn draw_detail_structured(
    frame: &mut Frame,
    area: Rect,
    req: &crate::types::PendingRequest,
    view: &DetailView,
) {
    // Header (title + flag badges).
    let mut header_spans: Vec<Span> = vec![Span::styled(view.title.clone(), bold())];
    for flag in &view.flags {
        header_spans.push(Span::raw(" "));
        header_spans.push(Span::styled(
            format!(" {flag} "),
            Style::default()
                .fg(Color::Black)
                .bg(badge_color(flag))
                .add_modifier(Modifier::BOLD),
        ));
    }
    // Fields block — one line per field; field name dimmed, value plain.
    let mut field_lines: Vec<Line> = Vec::with_capacity(view.fields.len());
    let max_label = view
        .fields
        .iter()
        .map(|(k, _)| k.chars().count())
        .max()
        .unwrap_or(0);
    for (k, v) in &view.fields {
        let pad = max_label - k.chars().count();
        field_lines.push(Line::from(vec![
            Span::styled(format!("{k}:{}", " ".repeat(pad + 1)), bold()),
            Span::raw(v.clone()),
        ]));
    }

    // Footer (state + optional error).
    let mut footer_spans: Vec<Span> = vec![
        Span::styled("state: ", bold()),
        Span::raw(req.state.label()),
    ];
    if let Some(err) = req.last_error.as_ref() {
        footer_spans.push(Span::raw("  "));
        footer_spans.push(Span::styled(
            format!("error: {err}"),
            Style::default().fg(Color::Red).add_modifier(Modifier::BOLD),
        ));
    }

    let prose_count = view.prose.len().max(1);
    let fields_height = (field_lines.len() as u16).saturating_add(2); // +2 borders

    // Layout: header (1) + fields box + prose sections (split evenly) + footer (1).
    let mut constraints: Vec<Constraint> = vec![Constraint::Length(1)]; // header
    if !view.fields.is_empty() {
        constraints.push(Constraint::Length(fields_height));
    }
    for _ in 0..prose_count.max(1) {
        constraints.push(Constraint::Min(3));
    }
    constraints.push(Constraint::Length(1)); // footer
    let inner = Layout::default()
        .direction(Direction::Vertical)
        .constraints(constraints)
        .split(area);

    let mut idx = 0;
    frame.render_widget(Paragraph::new(Line::from(header_spans)), inner[idx]);
    idx += 1;
    if !view.fields.is_empty() {
        frame.render_widget(
            Paragraph::new(field_lines)
                .block(Block::default().borders(Borders::ALL).title("Fields")),
            inner[idx],
        );
        idx += 1;
    }
    if view.prose.is_empty() {
        // Nothing to render in the prose slot — fill with a marker so
        // the layout doesn't look broken when there's no body.
        frame.render_widget(
            Paragraph::new("(no prose fields)")
                .style(Style::default().fg(Color::DarkGray))
                .block(Block::default().borders(Borders::ALL)),
            inner[idx],
        );
        idx += 1;
    } else {
        for (label, md) in &view.prose {
            let text: Text = if md.is_empty() {
                Text::styled("(empty)", Style::default().fg(Color::DarkGray))
            } else {
                markdown_to_text(md)
            };
            frame.render_widget(
                Paragraph::new(text)
                    .wrap(Wrap { trim: false })
                    .block(
                        Block::default()
                            .borders(Borders::ALL)
                            .title(label.clone()),
                    ),
                inner[idx],
            );
            idx += 1;
        }
    }
    frame.render_widget(Paragraph::new(Line::from(footer_spans)), inner[idx]);
}

fn draw_detail_generic(frame: &mut Frame, area: Rect, req: &crate::types::PendingRequest) {
    let inner = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(6),
            Constraint::Length(6),
            Constraint::Min(0),
        ])
        .split(area);
    let env = &req.envelope;
    let head_lines = vec![
        Line::from(vec![Span::styled("op:        ", bold()), Span::raw(env.op.clone())]),
        Line::from(vec![
            Span::styled("id:        ", bold()),
            Span::raw(env.request_id.clone()),
        ]),
        Line::from(vec![
            Span::styled("requested: ", bold()),
            Span::raw(env.requested_at.clone()),
        ]),
        Line::from(vec![
            Span::styled("state:     ", bold()),
            Span::raw(req.state.label()),
        ]),
    ];
    let head = Paragraph::new(head_lines)
        .block(Block::default().borders(Borders::ALL).title("Request"));
    frame.render_widget(head, inner[0]);

    let summary_text = env
        .summary
        .clone()
        .unwrap_or_else(|| "(no summary)".into());
    let summary = Paragraph::new(summary_text)
        .wrap(Wrap { trim: false })
        .block(Block::default().borders(Borders::ALL).title("Summary"));
    frame.render_widget(summary, inner[1]);

    let payload_pretty = serde_json::to_string_pretty(&env.payload).unwrap_or_default();
    let mut body_lines: Vec<Line> = payload_pretty.lines().map(Line::raw).collect();
    if let Some(err) = req.last_error.as_ref() {
        body_lines.push(Line::raw(""));
        body_lines.push(Line::from(vec![
            Span::styled(
                "error: ",
                Style::default().fg(Color::Red).add_modifier(Modifier::BOLD),
            ),
            Span::raw(err.clone()),
        ]));
    }
    let payload =
        Paragraph::new(body_lines).block(Block::default().borders(Borders::ALL).title("Payload"));
    frame.render_widget(payload, inner[2]);
}

fn badge_color(flag: &str) -> Color {
    match flag {
        "DRAFT" | "→ DRAFT" => Color::Yellow,
        "→ READY" => Color::Green,
        "REQUEST_CHANGES" => Color::Red,
        _ => Color::Cyan,
    }
}

fn draw_status(frame: &mut Frame, area: Rect, queue: &Queue, state: &UiState) {
    let hints = if queue.is_empty() {
        "q quit  ? help".to_string()
    } else {
        "↵ approve   d reject   r retry   j/k next/prev   ? help   q quit".to_string()
    };
    let text = if let Some(msg) = &state.message {
        format!("{msg}  ·  {hints}")
    } else {
        hints
    };
    let p = Paragraph::new(text).style(Style::default().fg(Color::DarkGray));
    frame.render_widget(p, area);
}

fn draw_help_overlay(frame: &mut Frame, area: Rect) {
    let popup_w = 60u16.min(area.width.saturating_sub(2));
    let popup_h = 14u16.min(area.height.saturating_sub(2));
    let x = (area.width.saturating_sub(popup_w)) / 2;
    let y = (area.height.saturating_sub(popup_h)) / 2;
    let popup = Rect::new(x + area.x, y + area.y, popup_w, popup_h);
    let text = vec![
        Line::from("approval-tui — keys"),
        Line::raw(""),
        Line::raw("  j / ↓        select next request"),
        Line::raw("  k / ↑        select previous request"),
        Line::raw("  Enter        approve focused request (YubiKey touch)"),
        Line::raw("  d            reject focused request"),
        Line::raw("  r            retry after sign/dispatch failure"),
        Line::raw("  ?            toggle this help"),
        Line::raw("  q            quit"),
        Line::raw(""),
        Line::raw("Each approval emits an ssh-keygen -Y sign over the"),
        Line::raw("canonical request envelope; the signature is recorded"),
        Line::raw("in the audit log alongside the dispatch result."),
    ];
    let p = Paragraph::new(text).block(
        Block::default()
            .borders(Borders::ALL)
            .title(" help ")
            .title_style(Style::default().add_modifier(Modifier::BOLD)),
    );
    frame.render_widget(ratatui::widgets::Clear, popup);
    frame.render_widget(p, popup);
}

fn bold() -> Style {
    Style::default().add_modifier(Modifier::BOLD)
}
