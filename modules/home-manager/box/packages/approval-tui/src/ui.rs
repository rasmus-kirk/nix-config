use crate::queue::Queue;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
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

pub fn draw(frame: &mut Frame, queue: &Queue, state: &UiState) {
    let outer = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(0), Constraint::Length(1)])
        .split(frame.area());

    let main = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Length(32), Constraint::Min(0)])
        .split(outer[0]);

    draw_queue(frame, main[0], queue);
    draw_detail(frame, main[1], queue);
    draw_status(frame, outer[1], queue, state);

    if state.help_visible {
        draw_help_overlay(frame, frame.area());
    }
}

fn draw_queue(frame: &mut Frame, area: Rect, queue: &Queue) {
    let items: Vec<ListItem> = queue
        .iter()
        .map(|(_id, r)| {
            let state_style = match r.state {
                crate::types::RequestState::Pending => Style::default().fg(Color::Yellow),
                crate::types::RequestState::Signing => Style::default().fg(Color::Cyan),
                crate::types::RequestState::Dispatching => Style::default().fg(Color::Cyan),
                crate::types::RequestState::SignFailed => Style::default().fg(Color::Red),
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

fn draw_detail(frame: &mut Frame, area: Rect, queue: &Queue) {
    let inner = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(6),
            Constraint::Length(6),
            Constraint::Min(0),
        ])
        .split(area);

    let Some(req) = queue.selected() else {
        let p = Paragraph::new("Queue empty. Waiting for requests...")
            .block(Block::default().borders(Borders::ALL).title("Detail"));
        frame.render_widget(p, area);
        return;
    };
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
        .unwrap_or_else(|| "(no summary; Haiku integration pending)".into());
    let summary = Paragraph::new(summary_text)
        .wrap(Wrap { trim: false })
        .block(Block::default().borders(Borders::ALL).title("Summary"));
    frame.render_widget(summary, inner[1]);

    let payload_pretty = serde_json::to_string_pretty(&env.payload).unwrap_or_default();
    let mut body_lines: Vec<Line> = payload_pretty.lines().map(Line::raw).collect();
    if let Some(err) = req.last_error.as_ref() {
        body_lines.push(Line::raw(""));
        body_lines.push(Line::from(vec![
            Span::styled("error: ", Style::default().fg(Color::Red).add_modifier(Modifier::BOLD)),
            Span::raw(err.clone()),
        ]));
    }
    let payload =
        Paragraph::new(body_lines).block(Block::default().borders(Borders::ALL).title("Payload"));
    frame.render_widget(payload, inner[2]);
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
