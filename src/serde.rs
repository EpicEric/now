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

use std::{collections::HashMap, path::PathBuf};

use serde::{Deserialize, Serialize, de::Visitor, ser::SerializeStruct};

use crate::{
    environment::EVAL_ID,
    workflow::{NowSandbox, NowStep, NowStepDownload, NowStepEnvVar, NowStepSecret},
};

impl Serialize for NowStep {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let mut strct = serializer.serialize_struct("NowStep", 5)?;
        strct.serialize_field("name", &self.name)?;
        strct.serialize_field("runDrv", &self.run_drv)?;
        strct.serialize_field("teardownDrv", &self.teardown_drv)?;
        strct.serialize_field("env", &self.env)?;
        strct.serialize_field("sandbox", &self.sandbox)?;
        strct.serialize_field("uploadKey", &self.upload_key)?;
        strct.end()
    }
}

impl<'de> Deserialize<'de> for NowStep {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        struct NowStepVisitor;

        impl<'de> Visitor<'de> for NowStepVisitor {
            type Value = NowStep;

            fn expecting(&self, formatter: &mut std::fmt::Formatter) -> std::fmt::Result {
                formatter.write_str("a now step")
            }

            fn visit_map<A>(self, mut map: A) -> Result<Self::Value, A::Error>
            where
                A: serde::de::MapAccess<'de>,
            {
                let mut name: Option<String> = None;
                let mut run_drv: Option<PathBuf> = None;
                let mut teardown_drv: Option<PathBuf> = None;
                let mut env: Option<HashMap<String, NowStepEnvVar>> = None;
                let mut sandbox: Option<NowSandbox> = None;
                let mut upload_key: Option<String> = None;

                while let Some(key) = map.next_key::<String>()? {
                    match key.as_ref() {
                        "name" => name = Some(map.next_value()?),
                        "runDrv" => run_drv = Some(map.next_value()?),
                        "teardownDrv" => teardown_drv = map.next_value()?,
                        "env" => env = Some(map.next_value()?),
                        "sandbox" => sandbox = map.next_value()?,
                        _ if matches!(key.split_once(&*EVAL_ID), Some(("__nowUpload_", ""))) => {
                            upload_key = map.next_value()?
                        }
                        _ => {
                            return Err(serde::de::Error::unknown_field(
                                &key,
                                &[
                                    "name",
                                    "runDrv",
                                    "teardownDrv",
                                    "env",
                                    "sandbox",
                                    "__nowUpload_<EVAL_ID>",
                                ],
                            ));
                        }
                    }
                }

                let name = name.ok_or_else(|| serde::de::Error::missing_field("name"))?;
                let run_drv = run_drv.ok_or_else(|| serde::de::Error::missing_field("runDrv"))?;
                let env = env.ok_or_else(|| serde::de::Error::missing_field("env"))?;

                Ok(NowStep {
                    name,
                    run_drv,
                    teardown_drv,
                    env,
                    sandbox,
                    upload_key,
                })
            }
        }

        deserializer.deserialize_struct(
            "NowStep",
            &[
                "name",
                "run_drv",
                "teardown_drv",
                "env",
                "sandbox",
                "upload_key",
            ],
            NowStepVisitor,
        )
    }
}

impl Serialize for NowStepSecret {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let mut strct = serializer.serialize_struct("NowStepSecret", 1)?;
        strct.serialize_field("secretName", &self.secret_name)?;
        strct.end()
    }
}

impl<'de> Deserialize<'de> for NowStepSecret {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        struct NowStepSecretVisitor;

        impl<'de> Visitor<'de> for NowStepSecretVisitor {
            type Value = NowStepSecret;

            fn expecting(&self, formatter: &mut std::fmt::Formatter) -> std::fmt::Result {
                formatter.write_str("an env secret")
            }

            fn visit_map<A>(self, mut map: A) -> Result<Self::Value, A::Error>
            where
                A: serde::de::MapAccess<'de>,
            {
                let key = map
                    .next_key::<String>()?
                    .ok_or_else(|| serde::de::Error::custom("missing key for map"))?;
                match key.split_once(&EVAL_ID.to_string()) {
                    Some(("__nowSecret_", "")) => Ok(NowStepSecret {
                        secret_name: map.next_value()?,
                    }),
                    Some(_) | None => Err(serde::de::Error::custom("invalid map key")),
                }
            }
        }

        deserializer.deserialize_struct("NowStepSecret", &["secret_name"], NowStepSecretVisitor)
    }
}

impl Serialize for NowStepDownload {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let mut strct = serializer.serialize_struct("NowStepDownload", 1)?;
        strct.serialize_field("downloadName", &self.download_name)?;
        strct.end()
    }
}

impl<'de> Deserialize<'de> for NowStepDownload {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        struct NowStepDownloadVisitor;

        impl<'de> Visitor<'de> for NowStepDownloadVisitor {
            type Value = NowStepDownload;

            fn expecting(&self, formatter: &mut std::fmt::Formatter) -> std::fmt::Result {
                formatter.write_str("an env download")
            }

            fn visit_map<A>(self, mut map: A) -> Result<Self::Value, A::Error>
            where
                A: serde::de::MapAccess<'de>,
            {
                let key = map
                    .next_key::<String>()?
                    .ok_or_else(|| serde::de::Error::custom("missing key for map"))?;
                match key.split_once(&EVAL_ID.to_string()) {
                    Some(("__nowDownload_", "")) => Ok(NowStepDownload {
                        download_name: map.next_value()?,
                    }),
                    Some(_) | None => Err(serde::de::Error::custom("invalid map key")),
                }
            }
        }

        deserializer.deserialize_struct(
            "NowStepDownload",
            &["download_name"],
            NowStepDownloadVisitor,
        )
    }
}
