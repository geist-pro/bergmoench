// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Exam-date interval capping. Before an exam, a review interval is capped at the optimal
//! spacing gap for the time left (Cepeda et al. 2008: about 43% of the retention interval at
//! 7 days, 23% at 35, 17% at 70, 8% at 350), and never lands on or after the exam day.
//! It edits the scheduling states before an answer is sent, the same hook Anki's custom
//! scheduling uses, so FSRS keeps its own memory model.

use anki_proto::scheduler::scheduling_state::{filtered, normal, Kind, Normal};
use anki_proto::scheduler::{SchedulingState, SchedulingStates};

const CEPEDA: [(f64, f64); 4] = [(7.0, 0.43), (35.0, 0.23), (70.0, 0.17), (350.0, 0.08)];

/// Optimal gap as a fraction of the days left, log-log interpolated between Cepeda's points.
pub fn gap_fraction(days_left: u32) -> f64 {
    let d = days_left.max(1) as f64;
    if d <= CEPEDA[0].0 { return CEPEDA[0].1; }
    if d >= CEPEDA[3].0 { return CEPEDA[3].1; }
    for w in CEPEDA.windows(2) {
        let ((d0, f0), (d1, f1)) = (w[0], w[1]);
        if d <= d1 {
            let t = (d.ln() - d0.ln()) / (d1.ln() - d0.ln());
            return (f0.ln() + t * (f1.ln() - f0.ln())).exp();
        }
    }
    CEPEDA[3].1
}

/// Longest interval allowed with `days_left` days to the exam; None means no cap (exam today or past).
pub fn max_interval(days_left: i32) -> Option<u32> {
    if days_left <= 0 { return None; }
    let d = days_left as u32;
    let gap = (gap_fraction(d) * d as f64).round() as u32;
    Some(gap.clamp(1, d.saturating_sub(1).max(1)))
}

fn cap_normal(n: &mut Normal, cap: u32) {
    match n.kind.as_mut() {
        Some(normal::Kind::Review(r)) => r.scheduled_days = r.scheduled_days.min(cap),
        Some(normal::Kind::Relearning(rl)) => {
            if let Some(r) = rl.review.as_mut() { r.scheduled_days = r.scheduled_days.min(cap) }
        }
        _ => {}
    }
}

fn cap_state(s: &mut Option<SchedulingState>, cap: u32) {
    let Some(state) = s.as_mut() else { return };
    match state.kind.as_mut() {
        Some(Kind::Normal(n)) => cap_normal(n, cap),
        Some(Kind::Filtered(f)) => {
            if let Some(filtered::Kind::Rescheduling(r)) = f.kind.as_mut() {
                if let Some(n) = r.original_state.as_mut() { cap_normal(n, cap) }
            }
        }
        None => {}
    }
}

/// Cap the four answer states (not the current one) for an exam `days_left` days away.
pub fn cap_states(mut states: SchedulingStates, days_left: i32) -> SchedulingStates {
    if let Some(cap) = max_interval(days_left) {
        for s in [&mut states.again, &mut states.hard, &mut states.good, &mut states.easy] { cap_state(s, cap) }
    }
    states
}

#[cfg(test)]
mod tests {
    use super::*;
    use anki_proto::scheduler::scheduling_state::{Relearning, Review};

    fn review(days: u32) -> Option<SchedulingState> {
        Some(SchedulingState { kind: Some(Kind::Normal(Normal { kind: Some(normal::Kind::Review(Review { scheduled_days: days, ..Default::default() })) })), custom_data: None })
    }
    fn days(s: &Option<SchedulingState>) -> u32 {
        match s.as_ref().unwrap().kind.as_ref().unwrap() {
            Kind::Normal(Normal { kind: Some(normal::Kind::Review(r)) }) => r.scheduled_days,
            Kind::Normal(Normal { kind: Some(normal::Kind::Relearning(rl)) }) => rl.review.as_ref().unwrap().scheduled_days,
            _ => panic!("unexpected state"),
        }
    }

    #[test]
    fn fractions_match_cepeda_points() {
        for (d, f) in CEPEDA { assert!((gap_fraction(d as u32) - f).abs() < 1e-9, "{d}"); }
        assert_eq!(gap_fraction(1), 0.43);
        assert_eq!(gap_fraction(1000), 0.08);
        let mid = gap_fraction(20);
        assert!(mid < 0.43 && mid > 0.23);
    }

    #[test]
    fn fractions_fall_as_exam_moves_away() {
        let mut last = 1.0;
        for d in 1..=400 { let f = gap_fraction(d); assert!(f <= last + 1e-12, "{d}"); last = f; }
    }

    #[test]
    fn caps() {
        assert_eq!(max_interval(0), None);
        assert_eq!(max_interval(-3), None);
        assert_eq!(max_interval(1), Some(1));
        assert_eq!(max_interval(2), Some(1));
        assert_eq!(max_interval(7), Some(3));
        assert_eq!(max_interval(35), Some(8));
        assert_eq!(max_interval(70), Some(12));
        assert_eq!(max_interval(90), Some(14));
        assert_eq!(max_interval(350), Some(28));
        for d in 1..500 { let c = max_interval(d).unwrap(); assert!(c >= 1 && (c as i32) < d.max(2), "{d}: {c}"); }
    }

    #[test]
    fn caps_answers_not_current_and_keeps_short_ones() {
        let s = SchedulingStates { current: review(40), again: review(0), hard: review(10), good: review(30), easy: review(60) };
        let c = cap_states(s, 90);
        assert_eq!((days(&c.current), days(&c.again), days(&c.hard), days(&c.good), days(&c.easy)), (40, 0, 10, 14, 14));
    }

    #[test]
    fn caps_relearning_and_ignores_past_exams() {
        let rl = Some(SchedulingState { kind: Some(Kind::Normal(Normal { kind: Some(normal::Kind::Relearning(Relearning {
            review: Some(Review { scheduled_days: 20, ..Default::default() }), learning: None })) })), custom_data: None });
        let s = SchedulingStates { current: review(5), again: rl, hard: review(9), good: review(20), easy: review(30) };
        assert_eq!(days(&cap_states(s.clone(), 7).again), 3);
        assert_eq!(days(&cap_states(s, 0).good), 20);
    }
}
