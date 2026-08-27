//! AI-agent hook event -> device state. Ported from Ulanzi's ustudio-cli mappings.
//! 8 device states, same vocabulary the stock firmware animates.

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum State {
    Idle, Thinking, Working, Error, Attention, Notification, Sweeping, Sleeping,
}

impl State {
    /// Indicator colour for this state. Matches the VibePal UI palette.
    pub fn rgb(self) -> (i32, i32, i32) {
        match self {
            State::Idle => (10, 132, 255),          // blue
            State::Thinking => (191, 90, 242),      // purple
            State::Working => (48, 209, 88),        // green
            State::Error => (255, 69, 58),          // red
            State::Attention => (255, 159, 10),     // amber
            State::Notification => (100, 210, 255), // cyan
            State::Sweeping => (200, 200, 205),     // near-white
            State::Sleeping => (40, 40, 48),        // dim
        }
    }

    /// Whether the state should pulse rather than sit still.
    /// ponytail: mode/speed enums are not decoded yet — `--mode`/`--speed` override on the CLI.
    pub fn animated(self) -> bool {
        matches!(self, State::Thinking | State::Working | State::Attention | State::Notification)
    }

    pub fn parse(s: &str) -> Option<State> {
        Some(match s {
            "idle" => State::Idle,
            "thinking" => State::Thinking,
            "working" => State::Working,
            "error" => State::Error,
            "attention" => State::Attention,
            "notification" => State::Notification,
            "sweeping" => State::Sweeping,
            "sleeping" => State::Sleeping,
            _ => return None,
        })
    }

    pub fn as_str(self) -> &'static str {
        match self {
            State::Idle => "idle",
            State::Thinking => "thinking",
            State::Working => "working",
            State::Error => "error",
            State::Attention => "attention",
            State::Notification => "notification",
            State::Sweeping => "sweeping",
            State::Sleeping => "sleeping",
        }
    }
}

/// Resolve (agent, hook-event) -> state. Returns None for events we don't animate.
pub fn map_event(agent: &str, event: &str) -> Option<State> {
    use State::*;
    let s = match agent {
        "claude-code" => match event {
            "SessionStart" => Idle,
            "UserPromptSubmit" => Thinking,
            "PreToolUse" | "PostToolUse" | "SubagentStart" | "SubagentStop" => Working,
            "PostToolUseFailure" | "StopFailure" => Error,
            "Stop" => Attention,
            "Notification" | "PermissionRequest" => Notification,
            "PreCompact" => Sweeping,
            _ => return None,
        },
        "codex" => match event {
            "SessionStart" => Idle,
            "UserPromptSubmit" => Thinking,
            "PreToolUse" | "PostToolUse" => Working,
            "Stop" => Attention,
            "PermissionRequest" => Notification,
            _ => return None,
        },
        _ => return None,
    };
    Some(s)
}

/// Hook event names a given agent needs wired up.
pub fn events_for(agent: &str) -> Option<&'static [&'static str]> {
    match agent {
        "claude-code" => Some(&[
            "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
            "PostToolUseFailure", "Stop", "StopFailure", "SubagentStart",
            "SubagentStop", "Notification", "PermissionRequest", "PreCompact",
        ]),
        "codex" => Some(&[
            "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
            "Stop", "PermissionRequest",
        ]),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn state_names_round_trip() {
        for st in [State::Idle, State::Thinking, State::Working, State::Error,
                   State::Attention, State::Notification, State::Sweeping, State::Sleeping] {
            assert_eq!(State::parse(st.as_str()), Some(st), "{} 没能往返", st.as_str());
            let (r, g, b) = st.rgb();
            assert!((0..=255).contains(&r) && (0..=255).contains(&g) && (0..=255).contains(&b));
        }
        assert_eq!(State::parse("nope"), None);
    }

    #[test]
    fn every_mapped_event_has_a_pushable_state() {
        // 每个 agent 声明要接的事件,都必须能解析出状态,否则 hook 会静默失灵
        for agent in ["claude-code", "codex"] {
            for ev in events_for(agent).unwrap() {
                let st = map_event(agent, ev).unwrap_or_else(|| panic!("{agent}/{ev} 没映射"));
                assert_eq!(State::parse(st.as_str()), Some(st));
            }
        }
    }

    #[test]
    fn known_mappings() {
        assert_eq!(map_event("claude-code", "PreToolUse"), Some(State::Working));
        assert_eq!(map_event("claude-code", "Stop"), Some(State::Attention));
        assert_eq!(map_event("codex", "PermissionRequest"), Some(State::Notification));
        assert_eq!(map_event("claude-code", "Nope"), None);
        assert_eq!(map_event("unknown-agent", "PreToolUse"), None);
    }
}
