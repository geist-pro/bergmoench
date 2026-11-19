//! Import .apkg files into a fresh collection, list the decks, show and answer one card.
//! cargo run --release --example smoke -- deck1.apkg deck2.apkg
use anki::collection::CollectionBuilder;
use anki::import_export::package::ImportAnkiPackageOptions;
use anki::scheduler::answering::{CardAnswer, Rating};
use anki::timestamp::{TimestampMillis, TimestampSecs};

fn strip(html: &str) -> String {
    let mut s = String::new();
    let mut tag = false;
    for c in html.chars() {
        match c { '<' => tag = true, '>' => tag = false, _ if !tag => s.push(c), _ => {} }
    }
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let dir = std::env::temp_dir().join("kartei-smoke");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir)?;
    let mut col = CollectionBuilder::new(dir.join("collection.anki2")).with_desktop_media_paths().build()?;
    for path in std::env::args().skip(1) {
        let log = col.import_apkg(&path, ImportAnkiPackageOptions::default())?.output;
        println!("imported {path}: {} new notes", log.new.len());
    }
    let tree = col.deck_tree(Some(TimestampSecs::now()))?;
    fn show(n: &anki_proto::decks::DeckTreeNode, depth: usize) {
        if depth > 0 {
            println!("{}{}  new {} learn {} due {}", "  ".repeat(depth - 1), n.name, n.new_count, n.learn_count, n.review_count);
        }
        for c in &n.children { show(c, depth + 1); }
    }
    show(&tree, 0);
    if let Some(first) = tree.children.iter().find(|c| c.new_count + c.review_count > 0) {
        col.set_current_deck(anki::decks::DeckId(first.deck_id))?;
        println!("studying: {}", first.name);
    }
    let queued = col.get_queued_cards(1, false)?;
    println!("queue: new {} learning {} review {}", queued.new_count, queued.learning_count, queued.review_count);
    if let Some(q) = queued.cards.into_iter().next() {
        let r = col.render_existing_card(q.card.id(), false, false)?;
        if std::env::var("KARTEI_RAW").is_ok() { println!("RAW Q:\n{}\nRAW A:\n{}\nCSS:\n{}", r.question(), r.answer(), r.css); }
        println!("Q: {}", strip(&r.question()));
        println!("A: {}", strip(&r.answer()));
        println!("buttons: {:?}", col.describe_next_states(&q.states)?);
        let mut answer = CardAnswer {
            card_id: q.card.id(), current_state: q.states.current, new_state: q.states.good, rating: Rating::Good,
            answered_at: TimestampMillis::now(), milliseconds_taken: 6000, custom_data: None, from_queue: true,
        };
        col.answer_card(&mut answer)?;
        let after = col.get_queued_cards(1, false)?;
        println!("after Good: new {} learning {} review {}", after.new_count, after.learning_count, after.review_count);
    }
    Ok(())
}
