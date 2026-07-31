// now: A Nix-based distributed command runner
// Copyright (C) 2026 Eric Rodrigues Pires
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU Affero General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for
// more details.
//
// You should have received a copy of the GNU Affero General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

use std::{
    collections::HashMap,
    hash::{Hash, Hasher},
    io::Write,
    marker::PhantomData,
    sync::Mutex,
};

use owo_colors::{OwoColorize, Style};
use rand::{SeedableRng, seq::IndexedRandom};
use tracing::{Subscriber, field::Visit};
use tracing_subscriber::{Layer, field::VisitOutput, registry::LookupSpan};

use crate::utils::trim_string;

struct CachedBuilder {
    short_name: String,
    style: Style,
}

pub(crate) struct NowSubscriberLayer<S, W = fn() -> std::io::Stderr> {
    make_writer: W,
    builder_name_limit: usize,
    builder_style_cache: Mutex<HashMap<String, CachedBuilder>>,
    _subscriber: PhantomData<S>,
}

impl<S> Default for NowSubscriberLayer<S> {
    fn default() -> Self {
        Self {
            make_writer: std::io::stderr,
            builder_name_limit: 40,
            builder_style_cache: Default::default(),
            _subscriber: Default::default(),
        }
    }
}

impl<S, W> Layer<S> for NowSubscriberLayer<S, W>
where
    S: Subscriber + for<'span> LookupSpan<'span>,
    W: for<'writer> tracing_subscriber::fmt::writer::MakeWriter<'writer> + 'static,
{
    fn on_event(
        &self,
        event: &tracing::Event<'_>,
        _ctx: tracing_subscriber::layer::Context<'_, S>,
    ) {
        let mut fields_visitor =
            NowSubscriberVisitor::new(&self.builder_style_cache, self.builder_name_limit);
        event.record(&mut fields_visitor);
        if let Some(log_line) = fields_visitor.finish() {
            let _ = writeln!(
                self.make_writer.make_writer_for(event.metadata()),
                "{}",
                log_line
            );
        }
    }
}

struct NowSubscriberVisitor<'a> {
    builder_style_cache: &'a Mutex<HashMap<String, CachedBuilder>>,
    builder_name_limit: usize,
    builder: Option<String>,
    is_remote: Option<bool>,
    step: Option<String>,
    message: Option<String>,
}

impl<'a> NowSubscriberVisitor<'a> {
    fn new(
        builder_style_cache: &'a Mutex<HashMap<String, CachedBuilder>>,
        builder_name_limit: usize,
    ) -> Self {
        NowSubscriberVisitor {
            builder_style_cache,
            builder_name_limit,
            builder: None,
            is_remote: None,
            step: None,
            message: None,
        }
    }
}

impl<'a> Visit for NowSubscriberVisitor<'a> {
    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn core::fmt::Debug) {
        match field.name() {
            "message" => self.message = Some(format!("{:?}", value)),
            _ => (),
        }
    }

    fn record_bool(&mut self, field: &tracing::field::Field, value: bool) {
        match field.name() {
            "is_remote" => self.is_remote = Some(value),
            _ => self.record_debug(field, &value),
        }
    }

    fn record_str(&mut self, field: &tracing::field::Field, value: &str) {
        match field.name() {
            "builder" => self.builder = Some(value.to_string()),
            "step" => self.step = Some(value.to_string()),
            _ => self.record_debug(field, &value),
        }
    }
}

impl<'a> tracing_subscriber::field::VisitOutput<Option<String>> for NowSubscriberVisitor<'a> {
    fn finish(self) -> Option<String> {
        let Some(message) = self.message else {
            return None;
        };
        let Some(builder) = self.builder else {
            return Some(message);
        };
        let is_remote = self.is_remote.is_some_and(|is_remote| is_remote);

        let (short_name, style) = {
            let mut guard = self.builder_style_cache.lock().expect("not poisoned");
            let builder = guard
                .entry(builder.clone())
                .or_insert_with(|| CachedBuilder {
                    short_name: trim_string(builder.clone(), self.builder_name_limit),
                    style: get_style_for_runner(is_remote, &builder),
                });
            (builder.short_name.clone(), builder.style)
        };

        if let Some(step) = self.step {
            Some(format!(
                "{} {}",
                format!("{} step[{}]>", short_name, step)
                    .if_supports_color(owo_colors::Stream::Stderr, |text| text.style(style)),
                message
            ))
        } else {
            Some(format!(
                "{} {}",
                format!("{}>", short_name)
                    .if_supports_color(owo_colors::Stream::Stderr, |text| text.style(style)),
                message
            ))
        }
    }
}

fn get_style_for_runner(is_remote: bool, builder: &str) -> owo_colors::Style {
    if is_remote {
        let mut hasher = std::hash::DefaultHasher::new();
        builder.hash(&mut hasher);
        *[
            owo_colors::Style::new().yellow(),
            owo_colors::Style::new().magenta(),
            owo_colors::Style::new().green(),
            owo_colors::Style::new().cyan(),
            owo_colors::Style::new().purple(),
            owo_colors::Style::new().red(),
        ]
        .choose(&mut rand::rngs::SmallRng::seed_from_u64(hasher.finish()))
        .expect("not empty")
    } else {
        owo_colors::Style::new().blue()
    }
}
