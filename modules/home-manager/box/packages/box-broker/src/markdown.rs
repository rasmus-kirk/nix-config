//! Markdown → ratatui `Text` renderer. Used by the host approver's
//! detail pane to render PR bodies, Linear issue descriptions, and
//! the inline-comment threads we synthesise for `gh.pr.review*`.
//!
//! Deliberately minimal: maps the common pulldown-cmark events to
//! `Span`s with ratatui modifiers. No syntax highlighting, no link
//! URL resolution beyond appending the target in parens when it
//! differs from the link text.

use pulldown_cmark::{CodeBlockKind, Event, Options, Parser, Tag, TagEnd};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span, Text};

const BULLETS: [&str; 4] = ["•", "◦", "▪", "▫"];

pub fn markdown_to_text(md: &str, width: u16) -> Text<'static> {
    let mut opts = Options::empty();
    opts.insert(Options::ENABLE_STRIKETHROUGH);
    opts.insert(Options::ENABLE_TABLES);
    opts.insert(Options::ENABLE_TASKLISTS);
    let mut renderer = Renderer::with_width(width);
    for event in Parser::new_ext(md, opts) {
        renderer.event(event);
    }
    renderer.finish()
}

#[derive(Default)]
struct Renderer {
    /// Render-area width (in cells), used for word-wrapping blockquote
    /// content so the `│ ` prefix repeats on continuation lines.
    width: u16,
    lines: Vec<Line<'static>>,
    /// Spans accumulating into the line currently being built.
    current: Vec<Span<'static>>,
    /// Inline modifier stack (Strong/Emphasis/Code/Strikethrough/Link).
    style_stack: Vec<Style>,
    /// List nesting; each frame is (is_ordered, next_number).
    list_stack: Vec<ListFrame>,
    /// Blockquote nesting depth.
    quote_depth: u8,
    /// True while inside a CodeBlock — content goes onto its own
    /// dimmed lines (no inline merging).
    in_code_block: bool,
    /// Pending Link target — appended in parens at link-end if it
    /// differs from the displayed text.
    link_target: Vec<String>,
    /// Visible text accumulated within the current link, so we can
    /// decide whether to show the URL alongside it.
    link_text: Vec<String>,
}

#[derive(Debug)]
struct ListFrame {
    ordered: bool,
    next: u64,
}

impl Renderer {
    fn with_width(width: u16) -> Self {
        Self {
            width,
            ..Default::default()
        }
    }

    fn event(&mut self, ev: Event<'_>) {
        match ev {
            Event::Start(tag) => self.start_tag(tag),
            Event::End(tag) => self.end_tag(tag),
            Event::Text(t) => self.text(t.as_ref()),
            Event::Code(t) => {
                let style = Style::default().fg(Color::LightYellow).add_modifier(Modifier::DIM);
                self.push_span(t.into_string(), style);
            }
            Event::Html(html) | Event::InlineHtml(html) => {
                // Show raw HTML as dimmed inline text — common in
                // GitHub PR bodies for things like <details>/<br>.
                self.push_span(
                    html.into_string(),
                    Style::default().fg(Color::DarkGray),
                );
            }
            Event::SoftBreak => self.push_text(" ", Style::default()),
            Event::HardBreak => self.flush_line(),
            Event::Rule => {
                self.flush_line();
                self.lines.push(Line::from(Span::styled(
                    "──────────",
                    Style::default().fg(Color::DarkGray),
                )));
            }
            Event::TaskListMarker(checked) => {
                let marker = if checked { "[x] " } else { "[ ] " };
                let style = if checked {
                    Style::default().fg(Color::Green)
                } else {
                    Style::default().fg(Color::DarkGray)
                };
                self.push_span(marker.to_string(), style);
            }
            // Footnotes / images / inline-math — render as raw text;
            // these aren't common in our inputs.
            Event::FootnoteReference(s) => self.push_text(&format!("[^{s}]"), Style::default()),
            Event::InlineMath(s) | Event::DisplayMath(s) => {
                self.push_text(s.as_ref(), Style::default())
            }
        }
    }

    fn start_tag(&mut self, tag: Tag<'_>) {
        match tag {
            Tag::Paragraph => {
                self.flush_line();
            }
            Tag::Heading { level, .. } => {
                let _ = level;
                self.flush_line();
                // Blank line above headings for breathing room
                // (except at the very top of the document).
                if !self.lines.is_empty() {
                    self.lines.push(Line::default());
                }
                self.style_stack.push(
                    Style::default()
                        .fg(Color::White)
                        .add_modifier(Modifier::BOLD),
                );
            }
            Tag::BlockQuote(_) => {
                self.flush_line();
                self.quote_depth = self.quote_depth.saturating_add(1);
            }
            Tag::CodeBlock(kind) => {
                self.flush_line();
                self.in_code_block = true;
                let lang = match kind {
                    CodeBlockKind::Fenced(l) => l.into_string(),
                    CodeBlockKind::Indented => String::new(),
                };
                self.lines.push(Line::from(Span::raw(format!("```{lang}"))));
            }
            Tag::List(first) => {
                self.flush_line();
                self.list_stack.push(ListFrame {
                    ordered: first.is_some(),
                    next: first.unwrap_or(1),
                });
            }
            Tag::Item => {
                self.flush_line();
                let depth = self.list_stack.len().saturating_sub(1);
                let indent = "  ".repeat(depth);
                let marker = if let Some(frame) = self.list_stack.last_mut() {
                    if frame.ordered {
                        let s = format!("{}. ", frame.next);
                        frame.next += 1;
                        s
                    } else {
                        format!("{} ", BULLETS[depth.min(BULLETS.len() - 1)])
                    }
                } else {
                    "• ".into()
                };
                self.push_span(
                    format!("{indent}{marker}"),
                    Style::default().fg(Color::DarkGray),
                );
            }
            Tag::Strong => self.style_stack.push(Style::default().add_modifier(Modifier::BOLD)),
            Tag::Emphasis => self.style_stack.push(Style::default().add_modifier(Modifier::ITALIC)),
            Tag::Strikethrough => self
                .style_stack
                .push(Style::default().add_modifier(Modifier::CROSSED_OUT)),
            Tag::Link { dest_url, .. } => {
                self.link_target.push(dest_url.into_string());
                self.link_text.push(String::new());
                self.style_stack.push(
                    Style::default()
                        .fg(Color::Blue)
                        .add_modifier(Modifier::UNDERLINED),
                );
            }
            Tag::Image { dest_url, .. } => {
                self.push_span(
                    format!("[image: {dest_url}]"),
                    Style::default().fg(Color::DarkGray),
                );
            }
            // Tables / footnotes / metadata blocks: collapse to plain
            // text. We can specialise later if any of them appear in
            // real broker payloads.
            _ => {}
        }
    }

    fn end_tag(&mut self, tag: TagEnd) {
        match tag {
            TagEnd::Paragraph => {
                self.flush_line();
                self.blank_line();
            }
            TagEnd::Heading(_) => {
                self.style_stack.pop();
                self.flush_line();
                self.blank_line();
            }
            TagEnd::BlockQuote(_) => {
                self.flush_line();
                self.quote_depth = self.quote_depth.saturating_sub(1);
                self.blank_line();
            }
            TagEnd::CodeBlock => {
                self.flush_line();
                self.in_code_block = false;
                self.lines.push(Line::from(Span::raw("```".to_string())));
                self.blank_line();
            }
            TagEnd::List(_) => {
                self.flush_line();
                self.list_stack.pop();
                self.blank_line();
            }
            TagEnd::Item => self.flush_line(),
            TagEnd::Strong | TagEnd::Emphasis | TagEnd::Strikethrough => {
                self.style_stack.pop();
            }
            TagEnd::Link => {
                let target = self.link_target.pop().unwrap_or_default();
                let text = self.link_text.pop().unwrap_or_default();
                self.style_stack.pop();
                if !target.is_empty() && target != text {
                    self.push_span(
                        format!(" ({target})"),
                        Style::default().fg(Color::DarkGray),
                    );
                }
            }
            _ => {}
        }
    }

    fn text(&mut self, t: &str) {
        // In a code block: emit each line as its own dimmed line.
        // `lines()` (not `split('\n')`) drops the trailing empty
        // string that pulldown-cmark's terminating newline produces,
        // so no spurious blank tail-line.
        if self.in_code_block {
            for (i, line) in t.lines().enumerate() {
                if i > 0 {
                    self.flush_line();
                }
                self.push_span(
                    format!("    {line}"),
                    Style::default().fg(Color::Gray).add_modifier(Modifier::DIM),
                );
            }
            return;
        }
        if !self.link_text.is_empty() {
            if let Some(buf) = self.link_text.last_mut() {
                buf.push_str(t);
            }
        }
        self.push_text(t, Style::default());
    }

    fn push_text(&mut self, s: &str, base: Style) {
        let style = self.merge_style(base);
        self.push_span(s.to_string(), style);
    }

    fn push_span(&mut self, content: String, style: Style) {
        if content.is_empty() {
            return;
        }
        self.current.push(Span::styled(content, style));
    }

    fn merge_style(&self, base: Style) -> Style {
        let mut out = base;
        for s in &self.style_stack {
            out = out.patch(*s);
        }
        out
    }

    /// Push an empty line for inter-block breathing room — but never
    /// stack two empties in a row.
    fn blank_line(&mut self) {
        if matches!(self.lines.last(), Some(line) if line_is_blank(line)) {
            return;
        }
        if self.lines.is_empty() {
            return;
        }
        self.lines.push(Line::default());
    }

    fn flush_line(&mut self) {
        if self.current.is_empty() {
            return;
        }
        if self.quote_depth > 0 {
            // Word-wrap blockquote content so the `│ ` prefix repeats
            // on every visual line. We collapse the per-span styles to
            // plain text for the wrap calculation (acceptable: bold/
            // italic inside blockquotes is rare; keeping the prefix
            // matters more than preserving inline styles on wrap).
            let prefix_chars = 2 * self.quote_depth as usize;
            let body: String = self.current.drain(..).map(|s| s.content.into_owned()).collect();
            let avail = (self.width as usize).saturating_sub(prefix_chars).max(1);
            for chunk in word_wrap(&body, avail) {
                let prefix_span = Span::styled(
                    "│ ".repeat(self.quote_depth as usize),
                    Style::default().fg(Color::DarkGray),
                );
                self.lines
                    .push(Line::from(vec![prefix_span, Span::raw(chunk)]));
            }
            return;
        }
        let mut spans = Vec::with_capacity(self.current.len());
        spans.extend(self.current.drain(..));
        self.lines.push(Line::from(spans));
    }

    fn finish(mut self) -> Text<'static> {
        self.flush_line();
        // Trim trailing blank lines.
        while self.lines.last().is_some_and(line_is_blank) {
            self.lines.pop();
        }
        Text::from(self.lines)
    }
}

fn line_is_blank(line: &Line<'_>) -> bool {
    line.spans.iter().all(|s| s.content.trim().is_empty())
}

/// Simple greedy word-wrap by Unicode scalar count. Good enough for
/// blockquote prose (which is typically short, prose-style text).
fn word_wrap(text: &str, max_width: usize) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut current = String::new();
    for word in text.split_whitespace() {
        let word_len = word.chars().count();
        if current.is_empty() {
            current.push_str(word);
            continue;
        }
        if current.chars().count() + 1 + word_len <= max_width {
            current.push(' ');
            current.push_str(word);
        } else {
            out.push(std::mem::take(&mut current));
            current.push_str(word);
        }
    }
    if !current.is_empty() {
        out.push(current);
    }
    if out.is_empty() {
        out.push(String::new());
    }
    out
}
