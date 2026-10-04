use std::{
    backtrace::Backtrace,
    error::Error,
    fmt::{self, Display},
};

use color_eyre::{Report, eyre};
use tracing_error::SpanTrace;

pub(crate) trait Section: Sized {
    type Return;

    fn error<E: Error + Send + Sync + 'static>(self, error: E) -> Self::Return;
    fn note<D: Display + Send + Sync + 'static>(self, message: D) -> Self::Return;
    fn suggestion<D: Display + Send + Sync + 'static>(self, message: D) -> Self::Return;
}

fn add_error<E: Error + Send + Sync + 'static>(mut report: Report, error: E) -> Report {
    if let Some(handler) = report.handler_mut().downcast_mut::<Handler>() {
        handler.errors.push(Box::new(error));
        report
    } else {
        color_eyre::Section::error(report, error)
    }
}

fn add_note<D: Display + Send + Sync + 'static>(mut report: Report, msg: D) -> Report {
    if let Some(h) = report.handler_mut().downcast_mut::<Handler>() {
        h.notes.push(msg.to_string());
        report
    } else {
        color_eyre::Section::note(report, msg)
    }
}

fn add_suggestion<D: Display + Send + Sync + 'static>(mut report: Report, msg: D) -> Report {
    if let Some(h) = report.handler_mut().downcast_mut::<Handler>() {
        h.suggestions.push(msg.to_string());
        report
    } else {
        color_eyre::Section::suggestion(report, msg)
    }
}

impl Section for Report {
    type Return = Report;

    fn error<E: Error + Send + Sync + 'static>(self, error: E) -> Report {
        add_error(self, error)
    }

    fn note<D: Display + Send + Sync + 'static>(self, message: D) -> Report {
        add_note(self, message)
    }

    fn suggestion<D: Display + Send + Sync + 'static>(self, message: D) -> Report {
        add_suggestion(self, message)
    }
}

impl<T, R: Into<Report>> Section for Result<T, R> {
    type Return = Result<T, Report>;

    fn error<E: Error + Send + Sync + 'static>(self, error: E) -> Self::Return {
        self.map_err(|report| add_error(report.into(), error))
    }

    fn note<D: Display + Send + Sync + 'static>(self, msg: D) -> Self::Return {
        self.map_err(|report| add_note(report.into(), msg))
    }

    fn suggestion<D: Display + Send + Sync + 'static>(self, msg: D) -> Self::Return {
        self.map_err(|report| add_suggestion(report.into(), msg))
    }
}

pub struct Handler {
    pub span_trace: SpanTrace,
    pub backtrace: Backtrace,
    pub location: Option<&'static std::panic::Location<'static>>,
    pub errors: Vec<Box<dyn Error + Send + Sync + 'static>>,
    pub notes: Vec<String>,
    pub suggestions: Vec<String>,
}

impl eyre::EyreHandler for Handler {
    fn debug(&self, error: &(dyn Error + 'static), f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{error}")?;
        let mut source = error.source();
        while let Some(e) = source {
            write!(f, ": {e}")?;
            source = e.source();
        }
        Ok(())
    }

    fn track_caller(&mut self, location: &'static std::panic::Location<'static>) {
        self.location = Some(location);
    }
}

pub(crate) fn install_tracing_hook() -> eyre::Result<()> {
    eyre::set_hook(Box::new(|_error| {
        Box::new(Handler {
            span_trace: SpanTrace::capture(),
            backtrace: Backtrace::capture(),
            location: None,
            errors: Vec::new(),
            notes: Vec::new(),
            suggestions: Vec::new(),
        })
    }))?;
    Ok(())
}

pub(crate) fn log_report(report: &color_eyre::Report) {
    let chain = format!("{report:#}");
    let handler = report.handler();

    if let Some(handler) = handler.downcast_ref::<Handler>() {
        tracing::error!(
            error = %chain,
            location =
                handler.location.map(|location| location.to_string()).unwrap_or_default(),
            "$duper.errors" =
                duper::serde::ser::to_string_compact(
                    &handler.errors.iter().map(|error| format!("{error:?}")).collect::<Vec<_>>()
                )
                .expect("valid Duper"),
            "$duper.notes" =
                duper::serde::ser::to_string_compact(&handler.notes)
                .expect("valid Duper"),
            "$duper.suggestions" =
                duper::serde::ser::to_string_compact(&handler.suggestions)
                .expect("valid Duper"),
            span_trace = %handler.span_trace,
            backtrace = %handler.backtrace,
            "unhandled error"
        )
    } else if let Some(handler) = handler.downcast_ref::<color_eyre::Handler>() {
        tracing::error!(
            error = %chain,
            span_trace = handler.span_trace().map(|span_trace| span_trace.to_string()).unwrap_or_default(),
            "unhandled error"
        );
    } else {
        tracing::error!(error = %chain, "unhandled error");
    }
}
