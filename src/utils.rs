// now: Nix-based distributed command runner
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

use std::{io::Write, process::Output};

use rand::distr::SampleString;
use smol::{channel::Receiver, future::zip, io::AsyncReadExt, process::Child};

/// Waits for `child` to exit while draining its pipe buffers concurrently.
pub(crate) async fn wait_for_output(
    child: &mut Child,
    cancellation: Option<&Receiver<()>>,
) -> color_eyre::Result<Output> {
    let mut stdout = child.stdout.take();
    let mut stderr = child.stderr.take();
    let mut stdout_buf = Vec::new();
    let mut stderr_buf = Vec::new();

    let run = async {
        let ((status, out), err) = zip(
            zip(child.status(), async {
                if let Some(pipe) = stdout.as_mut() {
                    pipe.read_to_end(&mut stdout_buf).await?;
                }
                Ok::<(), color_eyre::Report>(())
            }),
            async {
                if let Some(pipe) = stderr.as_mut() {
                    pipe.read_to_end(&mut stderr_buf).await?;
                }
                Ok::<(), color_eyre::Report>(())
            },
        )
        .await;
        out?;
        err?;
        Ok(Output {
            status: status?,
            stdout: stdout_buf,
            stderr: stderr_buf,
        })
    };

    let result = if let Some(cancellation) = cancellation {
        smol::future::race(
            async {
                let _ = cancellation.recv().await;
                Err(color_eyre::eyre::eyre!("Runner aborted"))
            },
            run,
        )
        .await
    } else {
        run.await
    };
    let _ = child.kill();
    result
}

pub(crate) fn write_output_to_stderr(output: &Output) -> color_eyre::Result<()> {
    let mut stderr = std::io::stderr();
    stderr.write_all(&output.stderr)?;
    stderr.flush()?;
    Ok(())
}

pub(crate) fn get_random_string(len: usize) -> String {
    rand::distr::Alphanumeric.sample_string(&mut rand::rng(), len)
}

pub(crate) fn trim_string(original: &str, max_chars: usize) -> String {
    debug_assert!(max_chars > 0);
    let mut output = String::with_capacity(max_chars);
    let mut iter = original.chars();
    for _ in 0..max_chars - 1 {
        if let Some(char) = iter.next() {
            output.push(char);
        } else {
            return output;
        }
    }
    if iter.next().is_some() {
        output.push('…');
    }
    output
}
