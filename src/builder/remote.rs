use std::{
    collections::{HashMap, HashSet},
    ffi::{OsStr, OsString},
    hash::{DefaultHasher, Hash, Hasher},
    io::{PipeReader, Write},
    os::unix::ffi::OsStrExt,
    path::{Path, PathBuf},
    process::{Child, Command},
};

use owo_colors::Style;
use rand::{SeedableRng, seq::IndexedRandom};

use crate::{
    CheckoutStrategy,
    builder::{NixConfig, UnevenBuilder},
    workflow::UnevenJob,
};

pub(crate) struct RemoteBuilder {
    pub(crate) ssh_uri: String,
    pub(crate) ssh_identity: Option<String>,
    pub(crate) systems: HashSet<String>,
    pub(crate) system_features: HashSet<String>,
}

impl RemoteBuilder {
    pub(crate) fn get_remote_builders(config: &NixConfig) -> color_eyre::Result<Vec<Self>> {
        let builders = if let Some(file) = config.builders.value.strip_prefix('@') {
            if !std::fs::exists(file)? {
                return Ok(vec![]);
            }
            String::from_utf8(std::fs::read(file)?)?
        } else {
            config.builders.value.clone()
        };

        let mut vec = vec![];
        for builder in regex::Regex::new(r"[\n;]+")
            .expect("valid regex")
            .split(&builders)
        {
            let mut iter = builder.split(' ');
            let Some(ssh_uri) = iter.next() else {
                continue;
            };
            let systems = if let Some(systems) = iter.next()
                && systems != "-"
            {
                systems
                    .split(',')
                    .map(|system| system.to_string())
                    .collect()
            } else {
                [config.system.value.clone()].into_iter().collect()
            };
            let ssh_identity = iter.next().and_then(|identity| {
                if identity == "-" {
                    None
                } else {
                    Some(identity.to_string())
                }
            });
            let _maximum_builds = iter.next();
            let _speed_factor = iter.next();
            let system_features = if let Some(system_features) = iter.next()
                && system_features != "-"
            {
                system_features
                    .split(',')
                    .map(|feature| feature.to_string())
                    .collect()
            } else {
                HashSet::new()
            };
            vec.push(RemoteBuilder {
                ssh_uri: ssh_uri.to_string(),
                ssh_identity,
                systems,
                system_features,
            })
        }

        Ok(vec)
    }
}

impl UnevenBuilder for RemoteBuilder {
    fn get_name(&self) -> String {
        self.ssh_uri.clone()
    }

    fn get_style(&self) -> owo_colors::Style {
        let mut hasher = DefaultHasher::new();
        self.ssh_uri.hash(&mut hasher);
        *[
            Style::new().yellow(),
            Style::new().magenta(),
            Style::new().green(),
            Style::new().cyan(),
            Style::new().purple(),
            Style::new().red(),
        ]
        .choose(&mut rand::rngs::SmallRng::seed_from_u64(hasher.finish()))
        .expect("not empty")
    }

    fn checkout(&self, strategy: CheckoutStrategy) -> color_eyre::Result<PathBuf> {
        match strategy {
            CheckoutStrategy::Default => {
                let files_to_copy: Vec<PathBuf> = ignore::Walk::new(std::env::current_dir()?)
                    .filter_map(|dir_entry| {
                        dir_entry.ok().and_then(|dir_entry| {
                            let pathbuf = dir_entry.into_path();
                            if pathbuf.is_file() {
                                Some(pathbuf)
                            } else {
                                None
                            }
                        })
                    })
                    .collect();
                todo!()
            }
        }
    }

    fn copy_derivations(&self, job: &UnevenJob) -> color_eyre::Result<()> {
        let mut command = Command::new("nix");
        command.args([
            "--extra-experimental-features",
            "nix-command",
            "copy",
            "--to",
        ]);
        command.arg(&self.ssh_uri);
        command.args(
            job.steps
                .iter()
                .flat_map(|step| {
                    if let Some(teardown_drv) = step.teardown_drv.as_ref() {
                        vec![
                            step.run_drv.clone().into_os_string(),
                            teardown_drv.clone().into_os_string(),
                        ]
                    } else {
                        vec![step.run_drv.clone().into_os_string()]
                    }
                })
                .collect::<Vec<_>>(),
        );

        let output = command.output()?;
        if !output.status.success() {
            let mut stderr = std::io::stderr();
            stderr.write_all(&output.stderr)?;
            stderr.flush()?;
            return Err(color_eyre::eyre::eyre!(
                "Failed to copy '{}' derivations to {}",
                job.name,
                self.ssh_uri
            ));
        }

        Ok(())
    }

    fn realize_derivation(&self, derivation: &Path) -> color_eyre::Result<PathBuf> {
        let mut command = Command::new("ssh");
        command.args([&self.ssh_uri, "nix-store", "--realise"]);
        command.arg(derivation);

        let output = command.output()?;
        if !output.status.success() {
            let mut stderr = std::io::stderr();
            stderr.write_all(&output.stderr)?;
            stderr.flush()?;
            return Err(color_eyre::eyre::eyre!(
                "Failed to realize derivation '{}' in {}",
                derivation.to_string_lossy(),
                self.ssh_uri
            ));
        }

        Ok(PathBuf::from(OsStr::from_bytes(
            output.stdout.as_slice().trim_ascii(),
        )))
    }

    fn download(&self, downloads: &[&Path]) -> color_eyre::Result<()> {
        let mut command = Command::new("nix");
        command.args([
            "--extra-experimental-features",
            "nix-command",
            "copy",
            "--to",
        ]);
        command.arg(&self.ssh_uri);
        command.args(downloads);

        let output = command.output()?;
        if !output.status.success() {
            let mut stderr = std::io::stderr();
            stderr.write_all(&output.stderr)?;
            stderr.flush()?;
            return Err(color_eyre::eyre::eyre!(
                "Failed to copy uploads to {}",
                self.ssh_uri
            ));
        }

        Ok(())
    }

    fn run_derivation(
        &self,
        cwdir: &Path,
        mut derivation: PathBuf,
        envs: HashMap<OsString, OsString>,
    ) -> color_eyre::Result<(Child, PipeReader)> {
        derivation.push("bin");
        derivation.push("uneven-step");

        todo!("run derivation on remote")
    }

    fn fetch_derivation(&self, derivation: &Path) -> color_eyre::Result<()> {
        let mut command = Command::new("nix");
        command.args([
            "--extra-experimental-features",
            "nix-command",
            "copy",
            "--from",
        ]);
        command.arg(&self.ssh_uri);
        command.arg(derivation);

        let output = command.output()?;
        if !output.status.success() {
            let mut stderr = std::io::stderr();
            stderr.write_all(&output.stderr)?;
            stderr.flush()?;
            return Err(color_eyre::eyre::eyre!(
                "Failed to copy '{}' derivation from {}",
                derivation.to_string_lossy(),
                self.ssh_uri
            ));
        }

        Ok(())
    }
}
