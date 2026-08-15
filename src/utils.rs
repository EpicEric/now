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

use std::io::Write;

use rand::distr::SampleString;
use smol::{io::AsyncReadExt, process::Child};

pub(crate) async fn pipe_outputs_to_stderr(child: &mut Child) -> color_eyre::Result<()> {
    let mut stderr = std::io::stderr();
    if let Some(mut pipe) = child.stdout.take() {
        let mut buf = Vec::new();
        pipe.read_to_end(&mut buf).await?;
        stderr.write_all(&buf)?;
    }
    if let Some(mut pipe) = child.stderr.take() {
        let mut buf = Vec::new();
        pipe.read_to_end(&mut buf).await?;
        stderr.write_all(&buf)?;
    }
    Ok(stderr.flush()?)
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
