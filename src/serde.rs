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
    workflow::{NowJobContainer, NowStep, NowStepDownload, NowStepEnvVar, NowStepSecret},
};

impl Serialize for NowJobContainer {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        match self {
            NowJobContainer::Single(job) => job.serialize(serializer),
            NowJobContainer::Multiple(job_vec) => job_vec.serialize(serializer),
        }
    }
}

impl<'de> Deserialize<'de> for NowJobContainer {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        struct NowJobContainerVisitor;

        impl<'de> Visitor<'de> for NowJobContainerVisitor {
            type Value = NowJobContainer;

            fn expecting(&self, formatter: &mut std::fmt::Formatter) -> std::fmt::Result {
                formatter.write_str("a job or list of jobs")
            }

            fn visit_seq<A>(self, mut seq: A) -> Result<Self::Value, A::Error>
            where
                A: serde::de::SeqAccess<'de>,
            {
                let mut job_vec = seq
                    .size_hint()
                    .map(|capacity| Vec::with_capacity(capacity))
                    .unwrap_or_default();
                while let Some(job) = seq.next_element()? {
                    job_vec.push(job);
                }
                Ok(NowJobContainer::Multiple(job_vec))
            }

            fn visit_map<A>(self, map: A) -> Result<Self::Value, A::Error>
            where
                A: serde::de::MapAccess<'de>,
            {
                Ok(NowJobContainer::Single(Deserialize::deserialize(
                    serde::de::value::MapAccessDeserializer::new(map),
                )?))
            }
        }

        deserializer.deserialize_any(NowJobContainerVisitor)
    }
}

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
                formatter.write_str("a step")
            }

            fn visit_map<A>(self, mut map: A) -> Result<Self::Value, A::Error>
            where
                A: serde::de::MapAccess<'de>,
            {
                let mut name: Option<String> = None;
                let mut run_drv: Option<PathBuf> = None;
                let mut teardown_drv: Option<PathBuf> = None;
                let mut env: Option<HashMap<String, NowStepEnvVar>> = None;
                let mut upload_key: Option<String> = None;

                while let Some(key) = map.next_key::<String>()? {
                    match key.as_ref() {
                        "name" => name = Some(map.next_value()?),
                        "runDrv" => run_drv = Some(map.next_value()?),
                        "teardownDrv" => teardown_drv = map.next_value()?,
                        "env" => env = Some(map.next_value()?),
                        _ if matches!(key.split_once(&*EVAL_ID), Some(("__nowUpload_", ""))) => {
                            upload_key = map.next_value()?
                        }
                        _ => {} // Ignore unknown keys
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
                    upload_key,
                })
            }
        }

        deserializer.deserialize_struct(
            "NowStep",
            &["name", "run_drv", "teardown_drv", "env", "upload_key"],
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

pub(crate) mod now_job_timeout {
    use std::{str::FromStr, time::Duration};

    use serde::{Deserializer, Serializer};

    pub fn serialize<S>(value: &Option<Duration>, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        match value {
            Some(value) => serializer.serialize_some(
                &jiff::Span::try_from(*value)
                    .map_err(|error| serde::ser::Error::custom(error))?
                    .round(jiff::SpanRound::new().largest(jiff::Unit::Hour))
                    .map_err(|error| serde::ser::Error::custom(error))?,
            ),
            None => serializer.serialize_none(),
        }
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<Option<Duration>, D::Error>
    where
        D: Deserializer<'de>,
    {
        struct Visitor;

        impl<'de> serde::de::Visitor<'de> for Visitor {
            type Value = Option<Duration>;

            fn expecting(&self, formatter: &mut ::std::fmt::Formatter) -> std::fmt::Result {
                formatter.write_str("an optional duration")
            }

            fn visit_str<E>(self, v: &str) -> Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                Ok(Some(
                    humantime::Duration::from_str(v)
                        .map_err(|error| serde::de::Error::custom(error))?
                        .into(),
                ))
            }

            fn visit_some<D>(self, deserializer: D) -> Result<Self::Value, D::Error>
            where
                D: Deserializer<'de>,
            {
                deserializer.deserialize_str(self)
            }

            fn visit_none<E>(self) -> Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                Ok(None)
            }
        }

        deserializer.deserialize_option(Visitor {})
    }
}

#[cfg(test)]
mod serde_tests {
    use std::str::FromStr;

    use super::*;

    #[test]
    fn deserialize_job_single() {
        let json = format!(
            "{{
                \"buildSystem\": \"x86_64-linux\",
                \"checkout\": \"default\",
                \"env\": {{}},
                \"hostSystem\": \"x86_64-linux\",
                \"name\": \"Fix formatting\",
                \"needs\": null,
                \"requiredSystemFeatures\": [],
                \"sandbox\": null,
                \"steps\": [
                    {{
                        \"__nowUpload_{}\": null,
                        \"env\": {{}},
                        \"name\": \"format-0\",
                        \"runDrv\": \"/nix/store/7djw1vhncf4953h80pq7xwvddrq0k88i-now-step.drv\",
                        \"teardownDrv\": null
                    }}
                ],
                \"strategy\": null,
                \"timeout\": null
            }}",
            *EVAL_ID
        );
        let job: NowJobContainer = serde_json::from_str(&json).unwrap();
        assert!(matches!(job, NowJobContainer::Single(_)))
    }

    #[test]
    fn serde_now_job_timeout() {
        #[derive(Serialize, Deserialize)]
        struct Wrapper(#[serde(with = "now_job_timeout")] Option<std::time::Duration>);

        let value: Wrapper = serde_json::from_str("null").unwrap();
        assert!(value.0.is_none());
        assert_eq!(serde_json::to_string(&value).unwrap(), "null");

        let value: Wrapper = serde_json::from_str(r#""1h""#).unwrap();
        assert_eq!(
            value.0.unwrap(),
            humantime::Duration::from_str("1h").unwrap().into()
        );
        assert_eq!(serde_json::to_string(&value).unwrap(), r#""PT1H""#);
    }
}
